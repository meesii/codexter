import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/global_config.dart';
import '../utils/app_paths.dart';
import '../utils/path_guard.dart';
import 'tunnel_service.dart';

const cloudflaredVersion = '2026.7.2';

class CloudflareLoginResult {
    final bool success;
    final bool alreadyLoggedIn;
    final String? error;

    const CloudflareLoginResult._({
        required this.success,
        this.alreadyLoggedIn = false,
        this.error,
    });

    static const alreadyDone = CloudflareLoginResult._(success: true, alreadyLoggedIn: true);
    static const done = CloudflareLoginResult._(success: true);

    static CloudflareLoginResult failed(String error) {
        return CloudflareLoginResult._(success: false, error: error);
    }
}

class DownloadProgress {
    final int received;
    final int total;

    const DownloadProgress(this.received, this.total);

    double get fraction => total > 0 ? received / total : 0;
}

/// 首次配置向导使用的服务：cloudflared 安装、Cloudflare 登录、Tunnel 创建与 DNS
class SetupService {
    static final _uuidRegex = RegExp(
        r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
    );

    Future<String> get cloudflaredPath => AppPaths.cloudflaredPath;

    String normalizeDomain(String domain) {
        final text = domain.trim();
        if (text.isEmpty) return '';
        final withScheme = text.contains('://') ? text : 'https://$text';
        try {
            final host = Uri.parse(withScheme).host.toLowerCase();
            return host.replaceAll(RegExp(r'\.$'), '');
        } catch (_) {
            return text.toLowerCase();
        }
    }

    Future<String?> findCloudflaredBin() async {
        final managed = await cloudflaredPath;
        if (await File(managed).exists()) return managed;

        final candidates = Platform.isWindows
            ? <String>[
                  p.join(_homeDir(), 'cloudflared.exe'),
                  r'C:\Program Files (x86)\cloudflared\cloudflared.exe',
                  r'C:\Program Files\cloudflared\cloudflared.exe',
              ]
            : <String>[
                  '/usr/local/bin/cloudflared',
                  '/usr/bin/cloudflared',
                  '/opt/homebrew/bin/cloudflared',
              ];

        for (final candidate in candidates) {
            if (await File(candidate).exists()) return candidate;
        }

        try {
            final result = await Process.run('cloudflared', ['--version']);
            if (result.exitCode == 0) return 'cloudflared';
        } catch (_) {}
        return null;
    }

    Future<String> probeVersion(String bin) async {
        try {
            final result = await Process.run(bin, ['--version'], stdoutEncoding: null);
            return TextDecode.bytes(result.stdout).trim();
        } catch (_) {
            return '';
        }
    }

    Future<void> downloadCloudflared({void Function(DownloadProgress)? onProgress}) async {
        final targetPath = await cloudflaredPath;
        final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);

        try {
            final request = await client.getUrl(Uri.parse(_downloadUrl));
            final response = await request.close();
            if (response.statusCode != 200) {
                throw Exception('下载失败 (HTTP ${response.statusCode})');
            }

            final total = response.contentLength;
            var received = 0;
            final sink = File(targetPath).openWrite();
            await for (final chunk in response) {
                sink.add(chunk);
                received += chunk.length;
                onProgress?.call(DownloadProgress(received, total));
            }
            await sink.close();

            if (!Platform.isWindows) {
                final chmod = await Process.run('chmod', ['+x', targetPath]);
                if (chmod.exitCode != 0) throw Exception('设置执行权限失败');
            }

            final probe = await Process.run(targetPath, ['--version']);
            if (probe.exitCode != 0) throw Exception('下载的文件无法运行');
        } catch (_) {
            final file = File(targetPath);
            if (await file.exists()) {
                try {
                    await file.delete();
                } catch (_) {}
            }
            rethrow;
        } finally {
            client.close();
        }
    }

    /// cert.pem 已存在则视为已登录，否则拉起浏览器等待用户授权
    Future<CloudflareLoginResult> loginCloudflare(String bin) async {
        final certFile = File(p.join(_homeDir(), '.cloudflared', 'cert.pem'));
        if (await certFile.exists()) return CloudflareLoginResult.alreadyDone;

        final process = await Process.start(bin, ['tunnel', 'login']);
        final output = StringBuffer();
        final urlRegex = RegExp(r'https://[^\s"]+');
        var opened = false;

        void scan(String text) {
            output.write(text);
            if (opened) return;
            final url = urlRegex.firstMatch(text)?.group(0);
            if (url == null) return;
            if (!url.contains('cloudflare') && !url.contains('dash')) return;
            opened = true;
            openUrl(url);
        }

        process.stdout.listen((data) => scan(TextDecode.bytes(data)));
        process.stderr.listen((data) => scan(TextDecode.bytes(data)));

        final exitCode = await process.exitCode;
        if (await certFile.exists()) return CloudflareLoginResult.done;
        return CloudflareLoginResult.failed('登录未完成 (exit $exitCode)：$output');
    }

    Future<String> createTunnel(String bin, String tunnelName) async {
        try {
            final output = await CloudflaredCli.run(bin, ['tunnel', 'create', tunnelName]);
            final created = _uuidRegex.firstMatch(output)?.group(0);
            if (created != null) return created;
        } catch (_) {}

        final list = await CloudflaredCli.run(bin, ['tunnel', 'list']);
        for (final line in list.split('\n')) {
            if (!line.contains(tunnelName)) continue;
            final existing = _uuidRegex.firstMatch(line)?.group(0);
            if (existing != null) return existing;
        }
        throw Exception('创建 Tunnel 失败，且未在列表中找到 $tunnelName');
    }

    Future<void> routeDns(String bin, String tunnelName, String domain) async {
        try {
            await CloudflaredCli.run(bin, ['tunnel', 'route', 'dns', tunnelName, domain]);
        } catch (error) {
            final message = '$error';
            if (message.contains('already exists') || message.contains('1003')) return;
            rethrow;
        }
    }

    Future<GlobalConfig> writeTunnelConfig(GlobalConfig config, String tunnelId) async {
        final credentialsFile = await AppPaths.credentialsPath(tunnelId);
        final configPath = await AppPaths.cloudflaredConfigPath;

        await File(configPath).writeAsString(TunnelConfigYml.build(
            tunnelId: tunnelId,
            credentialsFile: credentialsFile,
            hostname: config.domain,
            serviceUrl: config.localServiceUrl,
        ));

        final credentials = File(credentialsFile);
        if (!await credentials.exists()) {
            final legacy = File(p.join(await AppPaths.configDir, '$tunnelId.json'));
            if (await legacy.exists()) {
                await credentials.parent.create(recursive: true);
                await legacy.rename(credentialsFile);
            }
        }
        return config.copyWith(tunnelId: tunnelId);
    }

    Future<bool> openUrl(String url) async {
        try {
            ProcessResult result;
            if (Platform.isWindows) {
                result = await Process.run('cmd', ['/c', 'start', '', url]);
            } else if (Platform.isMacOS) {
                result = await Process.run('open', [url]);
            } else {
                result = await Process.run('xdg-open', [url]);
            }
            return result.exitCode == 0;
        } catch (_) {
            return false;
        }
    }

    static const githubReleasesUrl =
        'https://github.com/cloudflare/cloudflared/releases/latest';

    String get githubAssetName {
        if (Platform.isWindows) return 'cloudflared-windows-amd64.exe';
        final arch = _isArm64 ? 'arm64' : 'amd64';
        if (Platform.isMacOS) return 'cloudflared-darwin-$arch.tgz';
        return 'cloudflared-linux-$arch';
    }

    String get managedBinName => Platform.isWindows ? 'cloudflared.exe' : 'cloudflared';

    String get _downloadUrl {
        final base =
            'https://github.com/cloudflare/cloudflared/releases/download/$cloudflaredVersion';
        return '$base/$githubAssetName';
    }

    bool get _isArm64 {
        if (Platform.version.contains('arm64')) return true;
        final arch = Platform.environment['PROCESSOR_ARCHITECTURE']?.toLowerCase() ?? '';
        return arch.contains('arm');
    }

    String _homeDir() {
        return Platform.environment['HOME'] ??
            Platform.environment['USERPROFILE'] ??
            '.';
    }
}
