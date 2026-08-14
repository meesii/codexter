import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/global_config.dart';
import '../models/workspace.dart';
import '../utils/app_paths.dart';

enum DoctorState { pass, warn, fail }

class DoctorCheck {
    final String title;
    final DoctorState state;
    final String detail;
    final String? hint;

    const DoctorCheck({
        required this.title,
        required this.state,
        required this.detail,
        this.hint,
    });
}

/// 环境自检：cloudflared、Cloudflare 登录、Tunnel 配置、本地服务、Git、工作区路径
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

    Future<List<DoctorCheck>> runAll({
        required GlobalConfig config,
        required List<Workspace> workspaces,
        required bool serverRunning,
        required bool tunnelRunning,
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
        await run(checkTitles[1], _checkCloudflareLogin);
        await run(checkTitles[2], () => _checkTunnelConfig(config));
        await run(checkTitles[3], () async => _checkDomain(config));
        await run(checkTitles[4], () async => _checkServer(config, serverRunning));
        await run(checkTitles[5], () async => _checkTunnel(config, tunnelRunning));
        await run(checkTitles[6], () => _checkPublicRoute(config));
        await run(checkTitles[7], _checkGit);
        await run(checkTitles[8], () => _checkWorkspacePaths(workspaces));

        return results;
    }

    Future<DoctorCheck> _checkCloudflaredBin(GlobalConfig config) async {
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
            hint: '在「公网配置」页重新下载 Cloudflared',
        );
    }

    Future<DoctorCheck> _checkCloudflareLogin() async {
        final certPath = p.join(_homeDir(), '.cloudflared', 'cert.pem');
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
            detail: '未找到 cert.pem',
            hint: '重新运行首次配置向导完成 cloudflared tunnel login',
        );
    }

    Future<DoctorCheck> _checkTunnelConfig(GlobalConfig config) async {
        final tunnelId = config.tunnelId;
        if (tunnelId == null || tunnelId.isEmpty) {
            return const DoctorCheck(
                title: 'Tunnel 配置',
                state: DoctorState.fail,
                detail: '尚未创建 Tunnel',
                hint: '在「公网配置」页创建 Tunnel',
            );
        }

        final credentials = await AppPaths.credentialsPath(tunnelId);
        final ymlPath = await AppPaths.cloudflaredConfigPath;
        final missing = <String>[];
        if (!await File(credentials).exists()) missing.add('credentials');
        if (!await File(ymlPath).exists()) missing.add('cloudflared.yml');

        if (missing.isEmpty) {
            return DoctorCheck(
                title: 'Tunnel 配置',
                state: DoctorState.pass,
                detail: 'id $tunnelId',
            );
        }
        return DoctorCheck(
            title: 'Tunnel 配置',
            state: DoctorState.fail,
            detail: '缺少 ${missing.join(' / ')}',
            hint: '重新执行「保存并重启服务」以生成配置',
        );
    }

    DoctorCheck _checkDomain(GlobalConfig config) {
        if (config.domain.isEmpty) {
            return const DoctorCheck(
                title: '公网域名',
                state: DoctorState.fail,
                detail: '未配置域名',
                hint: '在「公网配置」页填写域名',
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
            detail: running
                ? '监听 ${config.host}:${config.port}'
                : '未运行',
            hint: running ? null : '在「公网配置」页点击「保存并重启服务」',
        );
    }

    DoctorCheck _checkTunnel(GlobalConfig config, bool running) {
        if (!config.useCloudflared) {
            return const DoctorCheck(
                title: 'Cloudflare Tunnel',
                state: DoctorState.warn,
                detail: '已关闭，仅本机可访问',
            );
        }
        return DoctorCheck(
            title: 'Cloudflare Tunnel',
            state: running ? DoctorState.pass : DoctorState.fail,
            detail: running ? '隧道已连接' : '隧道未运行',
            hint: running ? null : '检查 cloudflared 日志后重启服务',
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
            final request = await client.getUrl(Uri.parse('https://${config.domain}/healthz'));
            final response = await request.close().timeout(const Duration(seconds: 10));
            await response.drain<void>();
            if (response.statusCode < 500) {
                return DoctorCheck(
                    title: '公网连通性',
                    state: DoctorState.pass,
                    detail: 'HTTP ${response.statusCode} from ${config.domain}',
                );
            }
            return DoctorCheck(
                title: '公网连通性',
                state: DoctorState.fail,
                detail: 'HTTP ${response.statusCode}',
                hint: '检查 DNS 路由与 cloudflared 是否指向本机端口',
            );
        } catch (error) {
            return DoctorCheck(
                title: '公网连通性',
                state: DoctorState.fail,
                detail: '$error',
                hint: '确认 DNS 已指向 Tunnel 且隧道正在运行',
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

    String _homeDir() {
        return Platform.environment['HOME'] ??
            Platform.environment['USERPROFILE'] ??
            '.';
    }
}
