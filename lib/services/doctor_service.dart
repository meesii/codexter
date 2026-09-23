import 'dart:convert';
import 'dart:io';

import '../models/global_config.dart';
import '../models/workspace.dart';
import '../utils/app_paths.dart';
import 'network_proxy.dart';
import 'setup_service.dart';
import 'tunnel_error_classifier.dart';

enum DoctorState { pass, warn, fail, skip }

class DoctorCheck {
  final String title;
  final DoctorState state;
  final String detail;
  final String? hint;
  final String? rawError;
  final TunnelIssueCode issue;
  final bool repairable;

  const DoctorCheck({
    required this.title,
    required this.state,
    required this.detail,
    this.hint,
    this.rawError,
    this.issue = TunnelIssueCode.none,
    this.repairable = false,
  });
}

/// 环境自检：cloudflared、Cloudflare 登录、Tunnel 配置、本地服务、Git、工作区路径。
class DoctorService {
  static const cloudflareCheckTitles = <String>[
    'Cloudflared',
    'Cloudflare 登录',
    'Tunnel 配置',
    '公网域名',
    '本地 MCP 服务',
    'Cloudflare Tunnel',
    '公网连通性',
    'Git',
    '工作区路径',
    '网络代理',
  ];

  static const openAiCheckTitles = <String>[
    'tunnel-client',
    'Runtime API Key',
    '工作区 Tunnel',
    '本地 MCP 服务',
    'OpenAI Tunnel',
    'Git',
    '工作区路径',
    '网络代理',
  ];

  static List<String> checkTitlesFor(GlobalConfig config) =>
      config.useOpenAiTunnel ? openAiCheckTitles : cloudflareCheckTitles;

  Future<List<DoctorCheck>> runAll({
    required GlobalConfig config,
    required List<Workspace> workspaces,
    required bool serverRunning,
    required bool tunnelRunning,
    String? tunnelError,
    void Function(String title)? onCheckStart,
    void Function(DoctorCheck check)? onCheckComplete,
  }) async {
    return _run(
      config: config,
      workspaces: workspaces,
      serverRunning: serverRunning,
      tunnelRunning: tunnelRunning,
      tunnelError: tunnelError,
      includeOptional: true,
      onCheckStart: onCheckStart,
      onCheckComplete: onCheckComplete,
    );
  }

  Future<List<DoctorCheck>> _run({
    required GlobalConfig config,
    required List<Workspace> workspaces,
    required bool serverRunning,
    required bool tunnelRunning,
    String? tunnelError,
    required bool includeOptional,
    void Function(String title)? onCheckStart,
    void Function(DoctorCheck check)? onCheckComplete,
  }) async {
    Future<DoctorCheck> run(String title, Future<DoctorCheck> Function() check) async {
      onCheckStart?.call(title);
      DoctorCheck result;
      try {
        result = await check();
      } catch (error) {
        result = DoctorCheck(
          title: title,
          state: DoctorState.fail,
          detail: '检查未完成：$error',
          hint: '处理上述错误后重新检查。',
          rawError: '$error',
        );
      }
      onCheckComplete?.call(result);
      return result;
    }

    final titles = checkTitlesFor(config);
    final checks = <Future<DoctorCheck>>[];
    if (config.useOpenAiTunnel) {
      checks.addAll([
        run(titles[0], () => _checkTunnelClient(config)),
        run(titles[1], () => _checkOpenAiRuntimeKey(config, workspaces)),
        run(titles[2], () => _checkOpenAiWorkspaceTunnels(config, workspaces)),
        run(titles[3], () async => _checkServer(config, serverRunning)),
        run(titles[4], () async => _checkOpenAiTunnel(workspaces, tunnelRunning, tunnelError)),
      ]);
      if (includeOptional) {
        checks.add(run(titles[5], _checkGit));
        checks.add(run(titles[6], () => _checkWorkspacePaths(workspaces)));
      }
      checks.add(run(titles[7], () => _checkProxy(config)));
    } else {
      checks.addAll([
        run(titles[0], () => _checkCloudflaredBin(config)),
        run(titles[1], () => _checkCloudflareLogin(config)),
        run(titles[2], () => _checkTunnelConfig(config)),
        run(titles[3], () async => _checkDomain(config)),
        run(titles[4], () async => _checkServer(config, serverRunning)),
        run(titles[5], () async => _checkTunnel(config, tunnelRunning, tunnelError)),
        run(titles[6], () => _checkPublicRoute(config)),
      ]);
      if (includeOptional) {
        checks.add(run(titles[7], _checkGit));
        checks.add(run(titles[8], () => _checkWorkspacePaths(workspaces)));
      }
      checks.add(run(titles[9], () => _checkProxy(config)));
    }
    return Future.wait(checks);
  }

  DoctorCheck _cloudflareSkipped(String title) {
    return DoctorCheck(title: title, state: DoctorState.warn, detail: '跳过（未启用 Cloudflare Tunnel）');
  }

  Future<DoctorCheck> _checkProxy(GlobalConfig config) async {
    if (!config.proxyEnabled) {
      return const DoctorCheck(title: '网络代理', state: DoctorState.skip, detail: '未启用');
    }

    final url = NetworkProxy.normalizeUrl(config.proxyUrl, enabled: true);
    try {
      await NetworkProxy.testConnection(url);
      return DoctorCheck(title: '网络代理', state: DoctorState.pass, detail: '已启用 · $url');
    } catch (error) {
      return DoctorCheck(
        title: '网络代理',
        state: DoctorState.fail,
        detail: '代理连接失败：$url',
        rawError: '$error',
      );
    }
  }

  Future<DoctorCheck> _checkTunnelClient(GlobalConfig config) async {
    final bin = await SetupService().findTunnelClientBin(configuredPath: config.tunnelClientBin);
    if (bin == null) {
      return const DoctorCheck(
        title: 'tunnel-client',
        state: DoctorState.fail,
        detail: '未找到 OpenAI tunnel-client',
        hint: '安装 tunnel-client，或在全局设置中填写可执行文件路径',
      );
    }
    try {
      final result = await Process.run(bin, ['--version']).timeout(const Duration(seconds: 5));
      if (result.exitCode == 0) {
        final version = '${result.stdout}'.trim();
        return DoctorCheck(
          title: 'tunnel-client',
          state: DoctorState.pass,
          detail: version.isEmpty ? bin : version,
        );
      }
      return DoctorCheck(
        title: 'tunnel-client',
        state: DoctorState.fail,
        detail: 'tunnel-client 无法正常执行（exit ${result.exitCode}）',
        rawError: '${result.stderr}'.trim(),
        hint: '重新安装 tunnel-client，或检查当前可执行文件路径',
      );
    } catch (error) {
      return DoctorCheck(
        title: 'tunnel-client',
        state: DoctorState.fail,
        detail: 'tunnel-client 无法正常执行',
        rawError: '$error',
        hint: '重新安装 tunnel-client，或检查当前可执行文件路径',
      );
    }
  }

  Future<DoctorCheck> _checkOpenAiRuntimeKey(
    GlobalConfig config,
    List<Workspace> workspaces,
  ) async {
    final key = config.openAiRuntimeApiKey.trim();
    if (key.isEmpty) {
      return const DoctorCheck(
        title: 'Runtime API Key',
        state: DoctorState.fail,
        detail: '尚未配置',
        hint: '在全局设置中填写具有 Tunnels Read + Use 权限的 Runtime API Key',
      );
    }

    final tunnelId = workspaces
        .where((workspace) => workspace.enabled)
        .map((workspace) => (workspace.openAiTunnelId ?? '').trim())
        .firstWhere(SetupService.isValidOpenAiTunnelId, orElse: () => '');
    if (tunnelId.isEmpty) {
      return const DoctorCheck(
        title: 'Runtime API Key',
        state: DoctorState.warn,
        detail: '已配置，暂无有效 Tunnel ID 可验证权限',
        hint: '为启用的工作区填写有效 Tunnel ID 后重新检查',
      );
    }

    try {
      await SetupService().validateOpenAiTunnelRuntimeKey(apiKey: key, tunnelId: tunnelId);
      return const DoctorCheck(
        title: 'Runtime API Key',
        state: DoctorState.pass,
        detail: 'OpenAI API 验证通过',
      );
    } on OpenAiTunnelValidationException catch (error) {
      return _openAiValidationFailureCheck(title: 'Runtime API Key', error: error, config: config);
    } catch (error) {
      return DoctorCheck(
        title: 'Runtime API Key',
        state: DoctorState.fail,
        detail: 'OpenAI API 验证未完成',
        rawError: '$error',
        hint: '查看详细错误后重新检查',
      );
    }
  }

  Future<DoctorCheck> _checkOpenAiWorkspaceTunnels(
    GlobalConfig config,
    List<Workspace> workspaces,
  ) async {
    final enabled = workspaces.where((workspace) => workspace.enabled).toList();
    if (enabled.isEmpty) {
      return const DoctorCheck(title: '工作区 Tunnel', state: DoctorState.warn, detail: '暂无启用的工作区');
    }

    final missing = enabled
        .where((workspace) => (workspace.openAiTunnelId ?? '').trim().isEmpty)
        .toList();
    if (missing.isNotEmpty) {
      return DoctorCheck(
        title: '工作区 Tunnel',
        state: DoctorState.fail,
        detail: '${missing.length} 个工作区缺少 tunnel_id',
        hint: '编辑对应工作区并填写 OpenAI Tunnel ID',
      );
    }

    final invalid = enabled
        .where((workspace) => !SetupService.isValidOpenAiTunnelId(workspace.openAiTunnelId ?? ''))
        .toList();
    if (invalid.isNotEmpty) {
      return DoctorCheck(
        title: '工作区 Tunnel',
        state: DoctorState.fail,
        detail: '${invalid.length} 个工作区的 tunnel_id 格式无效',
        hint: '重新填写 OpenAI Tunnel ID',
      );
    }

    final seen = <String, Workspace>{};
    for (final workspace in enabled) {
      final id = workspace.openAiTunnelId!.trim().toLowerCase();
      final duplicate = seen[id];
      if (duplicate != null) {
        return DoctorCheck(
          title: '工作区 Tunnel',
          state: DoctorState.fail,
          detail: '工作区「${duplicate.name}」与「${workspace.name}」使用了同一 Tunnel ID',
          hint: '每个工作区必须使用独立的 OpenAI Tunnel ID',
        );
      }
      seen[id] = workspace;
    }

    final key = config.openAiRuntimeApiKey.trim();
    if (key.isEmpty) {
      return const DoctorCheck(
        title: '工作区 Tunnel',
        state: DoctorState.warn,
        detail: 'Tunnel ID 格式正常，等待 Runtime API Key 验证',
      );
    }

    for (final workspace in enabled) {
      try {
        await SetupService().validateOpenAiTunnelRuntimeKey(
          apiKey: key,
          tunnelId: workspace.openAiTunnelId!,
        );
      } on OpenAiTunnelValidationException catch (error) {
        return _openAiValidationFailureCheck(
          title: '工作区 Tunnel',
          error: error,
          config: config,
          workspaceName: workspace.name,
        );
      } catch (error) {
        return DoctorCheck(
          title: '工作区 Tunnel',
          state: DoctorState.fail,
          detail: '工作区「${workspace.name}」的 Tunnel 验证未完成',
          rawError: '$error',
          hint: '查看详细错误后重新检查',
        );
      }
    }

    return DoctorCheck(
      title: '工作区 Tunnel',
      state: DoctorState.pass,
      detail: '${enabled.length} 个工作区均已通过 OpenAI API 验证',
    );
  }

  DoctorCheck _openAiValidationFailureCheck({
    required String title,
    required OpenAiTunnelValidationException error,
    required GlobalConfig config,
    String? workspaceName,
  }) {
    final prefix = workspaceName == null ? '' : '工作区「$workspaceName」：';
    switch (error.issue) {
      case OpenAiTunnelValidationIssue.network:
        return DoctorCheck(
          title: title,
          state: DoctorState.fail,
          detail: '$prefix无法连接 OpenAI API',
          rawError: error.message,
          hint: config.proxyEnabled
              ? '检查当前网络和网络代理配置后重新检查'
              : '当前网络无法访问 OpenAI API；可在网络代理中配置可用代理后重新检查',
        );
      case OpenAiTunnelValidationIssue.unauthorized:
        return DoctorCheck(
          title: title,
          state: DoctorState.fail,
          detail: '${prefix}Runtime API Key 无效或已失效',
          rawError: error.message,
          hint: '重新填写有效的 Runtime API Key',
        );
      case OpenAiTunnelValidationIssue.forbidden:
        return DoctorCheck(
          title: title,
          state: DoctorState.fail,
          detail: '${prefix}Runtime API Key 缺少 Tunnel Read 权限',
          rawError: error.message,
          hint: '为 Runtime API Key 添加当前 Tunnel 的 Read 权限',
        );
      case OpenAiTunnelValidationIssue.notFound:
        return DoctorCheck(
          title: title,
          state: DoctorState.fail,
          detail: '${prefix}Tunnel 不存在或当前 Key 无权查看',
          rawError: error.message,
          hint: '检查 Tunnel ID，并确认 Runtime API Key 可以访问该 Tunnel',
        );
      case OpenAiTunnelValidationIssue.server:
        return DoctorCheck(
          title: title,
          state: DoctorState.fail,
          detail: '${prefix}OpenAI API 暂时不可用',
          rawError: error.message,
          hint: '稍后重新检查；若持续失败再检查网络代理',
        );
      case OpenAiTunnelValidationIssue.other:
        return DoctorCheck(
          title: title,
          state: DoctorState.fail,
          detail: '${prefix}OpenAI API 返回异常响应',
          rawError: error.message,
          hint: '查看详细错误后重新检查',
        );
    }
  }

  DoctorCheck _checkOpenAiTunnel(List<Workspace> workspaces, bool running, String? tunnelError) {
    final hasEnabledWorkspace = workspaces.any((workspace) => workspace.enabled);
    if (!hasEnabledWorkspace) {
      return const DoctorCheck(
        title: 'OpenAI Tunnel',
        state: DoctorState.skip,
        detail: '等待创建并启用工作区',
      );
    }

    final raw = tunnelError?.trim() ?? '';
    return DoctorCheck(
      title: 'OpenAI Tunnel',
      state: running ? DoctorState.pass : DoctorState.fail,
      detail: running ? 'tunnel-client 已就绪' : 'tunnel-client 未就绪',
      hint: running ? null : '检查 tunnel-client、Runtime API Key 和各工作区 tunnel_id',
      rawError: raw.isEmpty ? null : raw,
      issue: running ? TunnelIssueCode.none : TunnelIssueCode.tunnelStopped,
      repairable: !running,
    );
  }

  Future<DoctorCheck> _checkCloudflaredBin(GlobalConfig config) async {
    if (!config.useCloudflared) return _cloudflareSkipped('Cloudflared');
    final bin = await SetupService().findCloudflaredBin(configuredPath: config.cloudflaredBin);
    if (bin != null) {
      try {
        final result = await Process.run(bin, ['--version']);
        if (result.exitCode == 0) {
          return DoctorCheck(
            title: 'Cloudflared',
            state: DoctorState.pass,
            detail: '${result.stdout}'.trim(),
          );
        }
      } catch (_) {}
    }
    return const DoctorCheck(
      title: 'Cloudflared',
      state: DoctorState.fail,
      detail: '未找到可用的 Cloudflared',
      hint: '重新下载 Cloudflared',
      issue: TunnelIssueCode.cloudflaredMissing,
      repairable: true,
    );
  }

  Future<DoctorCheck> _checkCloudflareLogin(GlobalConfig config) async {
    if (!config.useCloudflared) return _cloudflareSkipped('Cloudflare 登录');
    final certPath = await AppPaths.originCertPath;
    if (await File(certPath).exists()) {
      return DoctorCheck(title: 'Cloudflare 登录', state: DoctorState.pass, detail: certPath);
    }
    return const DoctorCheck(
      title: 'Cloudflare 登录',
      state: DoctorState.fail,
      detail: '当前环境未找到 cert.pem',
      hint: '登录 Cloudflare，为当前环境生成独立 cert.pem',
      issue: TunnelIssueCode.originCertMissing,
      repairable: true,
    );
  }

  Future<DoctorCheck> _checkTunnelConfig(GlobalConfig config) async {
    if (!config.useCloudflared) return _cloudflareSkipped('Tunnel 配置');
    final tunnelId = config.tunnelId;
    if (tunnelId == null || tunnelId.isEmpty) {
      return const DoctorCheck(
        title: 'Tunnel 配置',
        state: DoctorState.fail,
        detail: '尚未创建 Tunnel',
        hint: '使用当前域名创建 Tunnel 和 DNS 路由',
        issue: TunnelIssueCode.tunnelMissing,
        repairable: true,
      );
    }

    final credentials = await AppPaths.credentialsPath(tunnelId);
    final ymlPath = await AppPaths.cloudflaredConfigPath;
    final credentialsMissing = !await File(credentials).exists();
    final configMissing = !await File(ymlPath).exists();

    if (!credentialsMissing && !configMissing) {
      return DoctorCheck(title: 'Tunnel 配置', state: DoctorState.pass, detail: 'id $tunnelId');
    }

    final missing = <String>[
      if (credentialsMissing) 'credentials',
      if (configMissing) 'cloudflared.yml',
    ];
    return DoctorCheck(
      title: 'Tunnel 配置',
      state: DoctorState.fail,
      detail: '缺少 ${missing.join(' / ')}',
      hint: credentialsMissing ? '尝试恢复 Tunnel credentials，再重建本地配置' : '重新生成 cloudflared.yml',
      issue: credentialsMissing
          ? TunnelIssueCode.tunnelCredentialsMissing
          : TunnelIssueCode.tunnelConfigMissing,
      repairable: true,
    );
  }

  DoctorCheck _checkDomain(GlobalConfig config) {
    if (!config.useCloudflared) return _cloudflareSkipped('公网域名');
    if (config.domain.isEmpty) {
      return const DoctorCheck(
        title: '公网域名',
        state: DoctorState.fail,
        detail: '未配置域名',
        hint: '进入主页面后在「公网服务」中填写域名',
        issue: TunnelIssueCode.domainMissing,
      );
    }
    return DoctorCheck(
      title: '公网域名',
      state: DoctorState.pass,
      detail: 'https://${config.domain}/{uuid}/mcp',
    );
  }

  DoctorCheck _checkServer(GlobalConfig config, bool running) {
    return DoctorCheck(
      title: '本地 MCP 服务',
      state: running ? DoctorState.pass : DoctorState.fail,
      detail: running ? '监听 ${config.host}:${config.port}' : '未运行',
      hint: running ? null : '重新启动本地 MCP 服务',
      issue: running ? TunnelIssueCode.none : TunnelIssueCode.localServerStopped,
      repairable: !running,
    );
  }

  DoctorCheck _checkTunnel(GlobalConfig config, bool running, String? tunnelError) {
    if (!config.useCloudflared) return _cloudflareSkipped('Cloudflare Tunnel');
    if (running) {
      return const DoctorCheck(
        title: 'Cloudflare Tunnel',
        state: DoctorState.pass,
        detail: '隧道已连接',
      );
    }

    final raw = tunnelError?.trim() ?? '';
    final info = raw.isEmpty ? null : TunnelErrorClassifier.classify(raw);
    final recognized = info != null && info.code != TunnelIssueCode.unknown;
    return DoctorCheck(
      title: 'Cloudflare Tunnel',
      state: DoctorState.fail,
      detail: recognized ? info.summary : '隧道未运行',
      hint: recognized ? info.hint : '重新启动 Tunnel；失败时查看 cloudflared 日志',
      rawError: raw.isEmpty ? null : raw,
      issue: recognized ? info.code : TunnelIssueCode.tunnelStopped,
      repairable: recognized ? info.repairable : true,
    );
  }

  Future<DoctorCheck> _checkPublicRoute(GlobalConfig config) async {
    if (config.domain.isEmpty || !config.useCloudflared) {
      return const DoctorCheck(title: '公网连通性', state: DoctorState.warn, detail: '跳过（未启用公网访问）');
    }

    final client = NetworkProxy.createHttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(Uri.parse('https://${config.domain}/healthz'));
      final response = await request.close().timeout(const Duration(seconds: 10));
      final body = await response.transform(utf8.decoder).join();
      final info = TunnelErrorClassifier.classify(body, httpStatus: response.statusCode);
      final cloudflareFailure =
          info.code == TunnelIssueCode.cloudflare1016 ||
          info.code == TunnelIssueCode.cloudflare1033;

      if (response.statusCode < 500 && !cloudflareFailure) {
        return DoctorCheck(
          title: '公网连通性',
          state: DoctorState.pass,
          detail: 'HTTP ${response.statusCode} from ${config.domain}',
        );
      }

      return DoctorCheck(
        title: '公网连通性',
        state: DoctorState.fail,
        detail: 'HTTP ${response.statusCode} · ${info.summary}',
        hint: info.hint,
        rawError: body.trim().isEmpty ? null : body.trim(),
        issue: info.code,
        repairable: info.repairable,
      );
    } catch (error) {
      final raw = '$error';
      final info = TunnelErrorClassifier.classify(raw);
      if (info.code == TunnelIssueCode.dnsMissing) {
        try {
          final publicDnsReady = await SetupService().isPublicDnsResolved(config.domain);
          if (publicDnsReady) {
            return DoctorCheck(
              title: '公网连通性',
              state: DoctorState.warn,
              detail: '公网 DNS 已生效，本机 DNS 缓存尚未刷新',
              hint: '稍后会自动恢复；也可以重新检测',
              rawError: raw,
            );
          }
        } catch (_) {}
      }
      return DoctorCheck(
        title: '公网连通性',
        state: DoctorState.fail,
        detail: info.code == TunnelIssueCode.unknown ? raw : info.summary,
        hint: info.hint,
        rawError: raw,
        issue: info.code,
        repairable: info.code == TunnelIssueCode.unknown ? true : info.repairable,
      );
    } finally {
      client.close();
    }
  }

  Future<DoctorCheck> _checkGit() async {
    try {
      final result = await Process.run('git', ['--version']);
      if (result.exitCode == 0) {
        return DoctorCheck(
          title: 'Git',
          state: DoctorState.pass,
          detail: '${result.stdout}'.trim(),
        );
      }
    } catch (_) {}
    return const DoctorCheck(
      title: 'Git',
      state: DoctorState.warn,
      detail: '未安装，exec_command 无法使用 git 命令',
    );
  }

  Future<DoctorCheck> _checkWorkspacePaths(List<Workspace> workspaces) async {
    if (workspaces.isEmpty) {
      return const DoctorCheck(title: '工作区路径', state: DoctorState.warn, detail: '还没有工作区');
    }

    final missing = <String>[];
    for (final workspace in workspaces) {
      if (!await Directory(workspace.projectRoot).exists()) {
        missing.add(workspace.name);
      }
    }
    if (missing.isEmpty) {
      return DoctorCheck(
        title: '工作区路径',
        state: DoctorState.pass,
        detail: '${workspaces.length} 个工作区路径可访问',
      );
    }
    return DoctorCheck(
      title: '工作区路径',
      state: DoctorState.fail,
      detail: '路径不存在：${missing.join('、')}',
      hint: '在主页删除或重新创建这些工作区',
    );
  }
}
