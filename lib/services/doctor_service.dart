import 'dart:convert';
import 'dart:io';

import '../models/global_config.dart';
import '../models/workspace.dart';
import '../utils/app_paths.dart';
import 'setup_service.dart';
import 'tunnel_error_classifier.dart';

enum DoctorState { pass, warn, fail }

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
  static const minCheckDisplayDuration = Duration(milliseconds: 200);

  static const checkTitles = <String>[
    'Cloudflared',
    'Cloudflare 登录',
    'Tunnel 配置',
    '公网域名',
    '本地 MCP 服务',
    'Cloudflare Tunnel',
    '公网连通性',
    'Git',
    '工作区路径',
  ];

  static const startupCheckTitles = <String>[
    'Cloudflared',
    'Cloudflare 登录',
    'Tunnel 配置',
    '公网域名',
    '本地 MCP 服务',
    'Cloudflare Tunnel',
    '公网连通性',
  ];

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

  Future<List<DoctorCheck>> runStartup({
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
      includeOptional: false,
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
    final results = <DoctorCheck>[];

    Future<void> run(String title, Future<DoctorCheck> Function() check) async {
      onCheckStart?.call(title);
      final stopwatch = Stopwatch()..start();
      final result = await check();
      final remaining = minCheckDisplayDuration - stopwatch.elapsed;
      if (remaining > Duration.zero) {
        await Future<void>.delayed(remaining);
      }
      results.add(result);
      onCheckComplete?.call(result);
    }

    await run(checkTitles[0], () => _checkCloudflaredBin(config));
    await run(checkTitles[1], () => _checkCloudflareLogin(config));
    await run(checkTitles[2], () => _checkTunnelConfig(config));
    await run(checkTitles[3], () async => _checkDomain(config));
    await run(checkTitles[4], () async => _checkServer(config, serverRunning));
    await run(
      checkTitles[5],
      () async => _checkTunnel(config, tunnelRunning, tunnelError),
    );
    await run(checkTitles[6], () => _checkPublicRoute(config));

    if (includeOptional) {
      await run(checkTitles[7], _checkGit);
      await run(checkTitles[8], () => _checkWorkspacePaths(workspaces));
    }

    return results;
  }

  DoctorCheck _cloudflareSkipped(String title) {
    return DoctorCheck(
      title: title,
      state: DoctorState.warn,
      detail: '跳过（未启用 Cloudflare Tunnel）',
    );
  }

  Future<DoctorCheck> _checkCloudflaredBin(GlobalConfig config) async {
    if (!config.useCloudflared) return _cloudflareSkipped('Cloudflared');
    final candidates = <String>[
      if (config.cloudflaredBin != null) config.cloudflaredBin!,
      await AppPaths.cloudflaredPath,
    ];
    for (final bin in candidates) {
      if (!await File(bin).exists()) continue;
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
      return DoctorCheck(
        title: 'Cloudflare 登录',
        state: DoctorState.pass,
        detail: certPath,
      );
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
      return DoctorCheck(
        title: 'Tunnel 配置',
        state: DoctorState.pass,
        detail: 'id $tunnelId',
      );
    }

    final missing = <String>[
      if (credentialsMissing) 'credentials',
      if (configMissing) 'cloudflared.yml',
    ];
    return DoctorCheck(
      title: 'Tunnel 配置',
      state: DoctorState.fail,
      detail: '缺少 ${missing.join(' / ')}',
      hint: credentialsMissing
          ? '尝试恢复 Tunnel credentials，再重建本地配置'
          : '重新生成 cloudflared.yml',
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
      issue: running
          ? TunnelIssueCode.none
          : TunnelIssueCode.localServerStopped,
      repairable: !running,
    );
  }

  DoctorCheck _checkTunnel(
    GlobalConfig config,
    bool running,
    String? tunnelError,
  ) {
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
      return const DoctorCheck(
        title: '公网连通性',
        state: DoctorState.warn,
        detail: '跳过（未启用公网访问）',
      );
    }

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(
        Uri.parse('https://${config.domain}/healthz'),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      final body = await response.transform(utf8.decoder).join();
      final info = TunnelErrorClassifier.classify(
        body,
        httpStatus: response.statusCode,
      );
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
          final publicDnsReady = await SetupService().isPublicDnsResolved(
            config.domain,
          );
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
        repairable: info.code == TunnelIssueCode.unknown
            ? true
            : info.repairable,
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
      return const DoctorCheck(
        title: '工作区路径',
        state: DoctorState.warn,
        detail: '还没有工作区',
      );
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
