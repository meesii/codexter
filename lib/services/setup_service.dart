import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import '../models/global_config.dart';
import '../platform/desktop_platform.dart';
import '../utils/app_paths.dart';
import '../utils/path_guard.dart';
import 'cloudflared_login_output.dart';
import 'cloudflared_tunnel_setup.dart';
import 'network_proxy.dart';
import 'tunnel_service.dart';

const cloudflaredVersion = '2026.7.2';
const tunnelClientVersion = 'v0.0.14';

class CloudflareLoginResult {
  final bool success;
  final bool alreadyLoggedIn;
  final bool authorizationPending;
  final String? error;

  const CloudflareLoginResult._({
    required this.success,
    this.alreadyLoggedIn = false,
    this.authorizationPending = false,
    this.error,
  });

  static const alreadyDone = CloudflareLoginResult._(success: true, alreadyLoggedIn: true);
  static const done = CloudflareLoginResult._(success: true);
  static const pending = CloudflareLoginResult._(success: false, authorizationPending: true);

  static CloudflareLoginResult failed(String error) {
    return CloudflareLoginResult._(success: false, error: error);
  }
}

class TunnelNameConflictException implements Exception {
  final String name;
  final String tunnelId;

  const TunnelNameConflictException(this.name, this.tunnelId);

  @override
  String toString() => 'Tunnel「$name」已存在';
}

class OpenAiTunnelValidationResult {
  final String tunnelId;
  final String? name;

  const OpenAiTunnelValidationResult({required this.tunnelId, this.name});
}

enum OpenAiTunnelValidationIssue { network, unauthorized, forbidden, notFound, server, other }

class OpenAiTunnelValidationException implements Exception {
  final OpenAiTunnelValidationIssue issue;
  final String message;

  const OpenAiTunnelValidationException(this.issue, this.message);

  @override
  String toString() => message;
}

class DownloadProgress {
  final int received;
  final int total;

  const DownloadProgress(this.received, this.total);

  double get fraction => total > 0 ? received / total : 0;
}

/// 首次配置向导使用的服务：cloudflared 安装、Cloudflare 登录、Tunnel 创建与 DNS
class SetupService {
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  Future<String> get cloudflaredPath => AppPaths.cloudflaredPath;
  Future<String> get tunnelClientPath => AppPaths.tunnelClientPath;

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

  /// 统一返回绝对路径，不能把 PATH 中的命令名作为文件路径保存。
  Future<String?> findCloudflaredBin({String? configuredPath}) async {
    final executableName = Platform.isWindows ? 'cloudflared.exe' : 'cloudflared';
    final pathDirectories = (Platform.environment['PATH'] ?? '').split(
      Platform.isWindows ? ';' : ':',
    );
    final candidates = <String>[
      if (configuredPath != null && configuredPath.isNotEmpty) configuredPath,
      await cloudflaredPath,
      if (Platform.isWindows) ...[
        p.join(_homeDir(), executableName),
        r'C:\Program Files (x86)\cloudflared\cloudflared.exe',
        r'C:\Program Files\cloudflared\cloudflared.exe',
      ] else ...[
        '/usr/local/bin/cloudflared',
        '/usr/bin/cloudflared',
        '/opt/homebrew/bin/cloudflared',
      ],
      for (final directory in pathDirectories)
        if (directory.isNotEmpty)
          p.join(
            Platform.isWindows ? directory.replaceAll(RegExp(r'^"|"$'), '') : directory,
            executableName,
          ),
    ];

    for (final candidate in candidates.toSet()) {
      final file = File(candidate);
      if (await file.exists()) return p.normalize(file.absolute.path);
    }
    return null;
  }

  Future<String?> findTunnelClientBin({String? configuredPath}) async {
    final executableName = Platform.isWindows ? 'tunnel-client.exe' : 'tunnel-client';
    final pathDirectories = (Platform.environment['PATH'] ?? '').split(
      Platform.isWindows ? ';' : ':',
    );
    final candidates = <String>[
      if (configuredPath != null && configuredPath.isNotEmpty) configuredPath,
      await tunnelClientPath,
      if (!Platform.isWindows) ...[
        '/usr/local/bin/tunnel-client',
        '/opt/homebrew/bin/tunnel-client',
      ],
      for (final directory in pathDirectories)
        if (directory.isNotEmpty)
          p.join(
            Platform.isWindows ? directory.replaceAll(RegExp(r'^"|"$'), '') : directory,
            executableName,
          ),
    ];

    for (final candidate in candidates.toSet()) {
      final file = File(candidate);
      if (await file.exists()) return p.normalize(file.absolute.path);
    }
    return null;
  }

  Future<void> downloadTunnelClient({void Function(DownloadProgress)? onProgress}) async {
    final targetPath = await tunnelClientPath;
    final target = File(targetPath);
    final staging = await Directory(await AppPaths.binDir).createTemp('.tunnel-client-');
    final archiveFile = File(p.join(staging.path, 'tunnel-client.zip'));
    final stagedBinary = File(
      p.join(staging.path, Platform.isWindows ? 'tunnel-client.exe' : 'tunnel-client'),
    );
    final backup = File('$targetPath.codexter-backup');
    final client = NetworkProxy.createHttpClient()..connectionTimeout = const Duration(seconds: 30);

    try {
      final request = await client.getUrl(Uri.parse(tunnelClientDownloadUrl));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw Exception('下载 Tunnel Client 失败 (HTTP ${response.statusCode})');
      }

      final total = response.contentLength;
      var received = 0;
      final sink = archiveFile.openWrite();
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(DownloadProgress(received, total));
      }
      await sink.close();

      final archive = ZipDecoder().decodeBytes(await archiveFile.readAsBytes());
      final executableName = Platform.isWindows ? 'tunnel-client.exe' : 'tunnel-client';
      ArchiveFile? executable;
      for (final entry in archive.files) {
        final name = p.basename(entry.name);
        if (entry.isFile && name == executableName) {
          executable = entry;
          break;
        }
      }
      if (executable == null) throw Exception('官方压缩包中未找到 $executableName');

      await stagedBinary.writeAsBytes(executable.content as List<int>, flush: true);
      if (!Platform.isWindows) {
        final chmod = await Process.run('chmod', ['+x', stagedBinary.path]);
        if (chmod.exitCode != 0) throw Exception('设置 Tunnel Client 执行权限失败');
      }

      final probe = await Process.run(stagedBinary.path, ['--version']);
      if (probe.exitCode != 0) throw Exception('下载的 Tunnel Client 无法运行');

      await target.parent.create(recursive: true);
      if (await backup.exists()) await backup.delete();
      if (await target.exists()) await target.rename(backup.path);
      try {
        await stagedBinary.rename(target.path);
        if (await backup.exists()) await backup.delete();
      } catch (_) {
        if (await target.exists()) {
          try {
            await target.delete();
          } catch (_) {}
        }
        if (await backup.exists()) await backup.rename(target.path);
        rethrow;
      }
    } finally {
      client.close();
      if (await backup.exists() && !await target.exists()) {
        try {
          await backup.rename(target.path);
        } catch (_) {}
      }
      try {
        await staging.delete(recursive: true);
      } catch (_) {}
    }
  }

  static bool isValidOpenAiTunnelId(String value) =>
      RegExp(r'^tunnel_[0-9a-fA-F]{32}$').hasMatch(value.trim());

  Future<OpenAiTunnelValidationResult> validateOpenAiTunnelRuntimeKey({
    required String apiKey,
    required String tunnelId,
  }) async {
    final key = apiKey.trim();
    final id = tunnelId.trim();
    if (key.isEmpty) throw const FormatException('OpenAI API Key 不能为空');
    if (!isValidOpenAiTunnelId(id)) {
      throw const FormatException('Tunnel ID 格式无效');
    }

    final client = NetworkProxy.createHttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(Uri.https('api.openai.com', '/v1/tunnels/$id'));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(const Duration(seconds: 15));
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200) {
        final decoded = jsonDecode(body);
        final data = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
        return OpenAiTunnelValidationResult(
          tunnelId: '${data['id'] ?? id}',
          name: data['name'] is String ? data['name'] as String : null,
        );
      }

      throw _openAiTunnelValidationException(response.statusCode, body);
    } on TimeoutException catch (error) {
      throw OpenAiTunnelValidationException(
        OpenAiTunnelValidationIssue.network,
        '连接 OpenAI API 超时：$error',
      );
    } on SocketException catch (error) {
      throw OpenAiTunnelValidationException(
        OpenAiTunnelValidationIssue.network,
        '无法连接 OpenAI API：${error.message}',
      );
    } on HandshakeException catch (error) {
      throw OpenAiTunnelValidationException(
        OpenAiTunnelValidationIssue.network,
        '连接 OpenAI API 时 TLS 握手失败：$error',
      );
    } on HttpException catch (error) {
      throw OpenAiTunnelValidationException(
        OpenAiTunnelValidationIssue.network,
        '连接 OpenAI API 失败：${error.message}',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<void> testOpenAiTunnelClientConnection({
    required String bin,
    required String apiKey,
    required String tunnelId,
    int timeoutSec = 20,
  }) async {
    final key = apiKey.trim();
    final id = tunnelId.trim();
    if (key.isEmpty) throw const FormatException('OpenAI API Key 不能为空');
    if (!isValidOpenAiTunnelId(id)) {
      throw const FormatException('Tunnel ID 格式无效');
    }

    final healthFile = File(await AppPaths.openAiHealthUrlPath('setup-test'));
    if (await healthFile.exists()) await healthFile.delete();

    final output = StringBuffer();
    Process? process;
    int? exitCode;
    try {
      process = await Process.start(bin, [
        'run',
        '--embedded-mcp-stub',
        '--control-plane.tunnel-id',
        id,
        '--health.listen-addr',
        '127.0.0.1:0',
        '--health.url-file',
        healthFile.path,
        '--log.level',
        'info',
        '--log.format',
        'struct-text',
      ], environment: NetworkProxy.processEnvironment(overrides: {'CONTROL_PLANE_API_KEY': key}));

      void collect(Stream<List<int>> stream) {
        stream.listen((data) {
          final text = TextDecode.bytes(data);
          output.write(text);
        });
      }

      collect(process.stdout);
      collect(process.stderr);
      unawaited(process.exitCode.then((code) => exitCode = code));

      final deadline = DateTime.now().add(Duration(seconds: timeoutSec));
      while (DateTime.now().isBefore(deadline)) {
        if (exitCode != null) {
          throw Exception(_tunnelClientTestError(output.toString(), exitCode!));
        }
        if (await _isTunnelClientReady(healthFile)) return;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      throw TimeoutException('Tunnel Client 在 ${timeoutSec}s 内未连接到 OpenAI');
    } finally {
      if (process != null && exitCode == null) {
        process.kill(ProcessSignal.sigterm);
        try {
          await process.exitCode.timeout(
            const Duration(seconds: 3),
            onTimeout: () {
              process!.kill(ProcessSignal.sigkill);
              return -1;
            },
          );
        } catch (_) {}
      }
      if (await healthFile.exists()) {
        try {
          await healthFile.delete();
        } catch (_) {}
      }
    }
  }

  Future<bool> _isTunnelClientReady(File healthFile) async {
    if (!await healthFile.exists()) return false;
    final base = (await healthFile.readAsString()).trim();
    if (base.isEmpty) return false;
    final uri = Uri.tryParse('$base/readyz');
    if (uri == null) return false;

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(const Duration(seconds: 2));
      await response.drain<void>();
      return response.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  String _tunnelClientTestError(String raw, int exitCode) {
    final text = raw.trim();
    final lower = text.toLowerCase();
    if (lower.contains('unauthorized') || lower.contains('401')) {
      return 'Tunnel Client 认证失败，请检查 OpenAI API Key 和 Tunnels Use 权限';
    }
    if (lower.contains('forbidden') || lower.contains('403')) {
      return 'OpenAI API Key 缺少当前 Tunnel 的 Use 权限';
    }
    if (lower.contains('not found') || lower.contains('404')) {
      return '未找到该 Tunnel，或当前 Key 无权使用它';
    }
    final lines = text.split(RegExp(r'\r?\n')).where((line) => line.trim().isNotEmpty).toList();
    final tail = lines.length <= 4 ? lines : lines.sublist(lines.length - 4);
    return tail.isEmpty
        ? 'Tunnel Client 启动失败（exit $exitCode）'
        : 'Tunnel Client 启动失败（exit $exitCode）：${tail.join(' / ')}';
  }

  OpenAiTunnelValidationException _openAiTunnelValidationException(int statusCode, String body) {
    String? apiMessage;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map && error['message'] is String) {
          apiMessage = error['message'] as String;
        }
      }
    } catch (_) {}

    final suffix = apiMessage == null || apiMessage.trim().isEmpty ? '' : '：${apiMessage.trim()}';
    return switch (statusCode) {
      401 => OpenAiTunnelValidationException(
        OpenAiTunnelValidationIssue.unauthorized,
        'OpenAI API Key 无效或已失效$suffix',
      ),
      403 => OpenAiTunnelValidationException(
        OpenAiTunnelValidationIssue.forbidden,
        'OpenAI API Key 缺少当前 Tunnel 的 Read 权限$suffix',
      ),
      404 => OpenAiTunnelValidationException(
        OpenAiTunnelValidationIssue.notFound,
        '未找到该 Tunnel，或当前 Key 无权查看它$suffix',
      ),
      >= 500 => OpenAiTunnelValidationException(
        OpenAiTunnelValidationIssue.server,
        'OpenAI API 暂时不可用（HTTP $statusCode）$suffix',
      ),
      _ => OpenAiTunnelValidationException(
        OpenAiTunnelValidationIssue.other,
        'OpenAI Tunnel 验证失败（HTTP $statusCode）$suffix',
      ),
    };
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
    if (await desktopPlatform.installCloudflared(
      source: Uri.parse(_downloadUrl),
      targetPath: targetPath,
      onProgress: (received, total) => onProgress?.call(DownloadProgress(received, total)),
    )) {
      return;
    }
    final client = NetworkProxy.createHttpClient()..connectionTimeout = const Duration(seconds: 30);

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

  /// 使用当前应用环境独立的 cert.pem 登录；[force] 用于切换 Zone 时重新授权。
  Future<CloudflareLoginResult> loginCloudflare(
    String bin, {
    bool force = false,
    void Function(String?)? onLoginUrl,
  }) async {
    onLoginUrl?.call(null);
    await migrateLegacyCloudflareCredentials();
    final certFile = File(await AppPaths.originCertPath);
    if (await certFile.exists() && !force) {
      return CloudflareLoginResult.alreadyDone;
    }

    File? backup;
    if (force && await certFile.exists()) {
      backup = File('${certFile.path}.codexter-backup');
      if (await backup.exists()) await backup.delete();
      await certFile.copy(backup.path);
      await certFile.delete();
    }

    final loginHome = Directory(await AppPaths.cloudflareLoginHome);
    if (await loginHome.exists()) await loginHome.delete(recursive: true);
    await loginHome.create(recursive: true);
    final generatedCert = File(p.join(loginHome.path, '.cloudflared', 'cert.pem'));
    final environment = NetworkProxy.processEnvironment()
      ..['HOME'] = loginHome.path
      ..['USERPROFILE'] = loginHome.path;

    try {
      final process = await Process.start(bin, ['tunnel', 'login'], environment: environment);
      // 自动打开只交给 cloudflared。应用仅提供完整链接供用户手动复制，避免重复标签页。
      String? reportedLoginUrl;
      final output = CloudflaredLoginOutput(
        onLoginUrl: (url) {
          reportedLoginUrl = url;
          onLoginUrl?.call(url);
        },
      );
      final results = await Future.wait<Object>([
        process.exitCode,
        output.collect(process.stdout, process.stderr),
      ]);
      final exitCode = results[0] as int;
      final loginOutput = results[1] as String;
      if (await generatedCert.exists()) {
        await certFile.parent.create(recursive: true);
        if (await certFile.exists()) await certFile.delete();
        await generatedCert.copy(certFile.path);
        if (backup != null && await backup.exists()) await backup.delete();
        return CloudflareLoginResult.done;
      }

      if (backup != null && await backup.exists()) {
        await backup.rename(certFile.path);
      }
      // cloudflared 的浏览器授权和证书回传可能因网络抖动提前退出。
      // 只要已经拿到授权 URL，等待授权或证书下载阶段的瞬时网络错误都视为“待完成”，
      // 让用户完成浏览器授权后重试，而不是直接展示整段 cloudflared 原始日志。
      if (isCloudflareLoginRetryable(loginOutput, hasLoginUrl: reportedLoginUrl != null)) {
        return CloudflareLoginResult.pending;
      }

      return CloudflareLoginResult.failed('登录未完成 (exit $exitCode)：$loginOutput');
    } catch (_) {
      if (backup != null && await backup.exists() && !await certFile.exists()) {
        await backup.rename(certFile.path);
      }
      rethrow;
    } finally {
      onLoginUrl?.call(null);
      if (await loginHome.exists()) {
        try {
          await loginHome.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  static bool isCloudflareLoginRetryable(String output, {required bool hasLoginUrl}) {
    if (!hasLoginUrl) return false;
    final text = output.toLowerCase();
    final waitingForAuthorization =
        text.contains('failed to fetch resource') && text.contains('waiting for login');
    final certificateTransportFailure =
        text.contains('failed to write the certificate') &&
        (text.contains('tls handshake timeout') ||
            text.contains('i/o timeout') ||
            text.contains('context deadline exceeded'));
    return waitingForAuthorization || certificateTransportFailure;
  }

  Future<String> createTunnel(String _, String tunnelName) async {
    final name = tunnelName.trim();
    if (name.isEmpty) throw const FormatException('Tunnel 名称不能为空');

    final credentials = await _readOriginCredentials();
    final random = Random.secure();
    final tunnelSecret = base64Encode(List<int>.generate(32, (_) => random.nextInt(256)));
    Map<String, dynamic> result;
    try {
      result = await _cloudflareApi(
        credentials,
        'POST',
        Uri.https('api.cloudflare.com', '/client/v4/accounts/${credentials.accountId}/cfd_tunnel'),
        body: {'name': name, 'tunnel_secret': tunnelSecret},
      );
    } catch (error) {
      final message = '$error'.toLowerCase();
      final nameConflict =
          message.contains('code: 1013') ||
          (message.contains('tunnel') &&
              (message.contains('already exists') || message.contains('already have')));
      if (!nameConflict) rethrow;
      final existingId = await _findTunnelIdByName(credentials, name);
      throw TunnelNameConflictException(name, existingId);
    }

    final id = '${result['id'] ?? ''}'.toLowerCase();
    if (!_uuid.hasMatch(id)) throw const FormatException('Cloudflare 创建结果中缺少有效 Tunnel ID');

    final staging = await Directory(await AppPaths.cloudflareDir).createTemp('.create-tunnel-');
    final pending = File(p.join(staging.path, 'credentials.json'));
    await pending.writeAsString(
      jsonEncode({
        'AccountTag': '${result['account_tag'] ?? credentials.accountId}',
        'TunnelSecret': tunnelSecret,
        'TunnelID': id,
      }),
      flush: true,
    );
    if (!await _adoptTunnelCredentials(id, pending)) {
      throw Exception('Tunnel「$name」已创建（$id），但本机未能保存有效运行凭据。');
    }
    try {
      await staging.delete(recursive: true);
    } catch (_) {}
    return id;
  }

  Future<String> _findTunnelIdByName(_CloudflareOriginCredentials credentials, String name) async {
    final result = await _cloudflareApi(
      credentials,
      'GET',
      Uri.https('api.cloudflare.com', '/client/v4/accounts/${credentials.accountId}/cfd_tunnel', {
        'name': name,
        'is_deleted': 'false',
        'per_page': '100',
      }),
    );
    final items = result['items'];
    if (items is! List) throw const FormatException('Cloudflare Tunnel 列表格式异常');
    final ids = items
        .whereType<Map>()
        .where((item) => item['name'] == name)
        .map((item) => '${item['id'] ?? ''}'.toLowerCase())
        .where(_uuid.hasMatch)
        .toSet();
    if (ids.length != 1) {
      throw Exception('Tunnel 名称「$name」已存在，但未能唯一确认其 ID；请修改名称或在 Cloudflare 核对。');
    }
    return ids.single;
  }

  Future<void> deleteTunnel(String tunnelId) async {
    if (!_uuid.hasMatch(tunnelId)) throw const FormatException('Tunnel ID 无效');
    final credentials = await _readOriginCredentials();
    await _cloudflareApi(
      credentials,
      'DELETE',
      Uri.https(
        'api.cloudflare.com',
        '/client/v4/accounts/${credentials.accountId}/cfd_tunnel/$tunnelId',
        {'cascade': 'true'},
      ),
    );

    final localCredentials = File(await AppPaths.credentialsPath(tunnelId));
    if (await localCredentials.exists()) {
      try {
        await localCredentials.delete();
      } catch (_) {}
    }
  }

  /// 使用与 cloudflared `tunnel route dns` 相同的 Zone-level route API。
  /// cloudflared 的 REST client 不读取系统代理，因此由 Codexter 自己发出请求，
  /// 让 HTTP / SOCKS5 代理覆盖整个初始化控制面。
  Future<void> routeDns(String _, String tunnelId, String domain) async {
    final credentials = await _readOriginCredentials();
    final requestedDomain = normalizeDomain(domain);
    if (requestedDomain.isEmpty) throw const FormatException('公网域名不能为空');
    if (!_uuid.hasMatch(tunnelId)) throw const FormatException('Tunnel ID 无效');

    try {
      final result = await _cloudflareApi(
        credentials,
        'PUT',
        Uri.https(
          'api.cloudflare.com',
          '/client/v4/zones/${credentials.zoneId}/tunnels/$tunnelId/routes',
        ),
        body: {'type': 'dns', 'user_hostname': requestedDomain, 'overwrite_existing': true},
      );

      final actualDomain = normalizeDomain('${result['name'] ?? ''}');
      if (actualDomain.isNotEmpty && actualDomain != requestedDomain) {
        throw Exception('DNS-ZONE-MISMATCH：Cloudflare 实际配置的是 $actualDomain，而不是 $requestedDomain。');
      }
    } catch (error) {
      final message = '$error';
      if (_isDnsAuthorizationError(message)) {
        throw Exception('DNS 路由创建失败：当前 Cloudflare 登录凭据无权管理 $domain。\n$message');
      }
      rethrow;
    }
  }

  /// 创建或修复 DNS；Zone 不匹配或权限错误时强制重新授权一次，
  /// 最终还要通过 1.1.1.1 DoH 验证真实域名已经可解析。
  Future<void> ensureDnsRoute(
    String bin,
    String tunnelId,
    String domain, {
    void Function(String?)? onLoginUrl,
  }) async {
    try {
      await routeDns(bin, tunnelId, domain);
    } catch (error) {
      if (!_shouldReloginForDns('$error')) rethrow;

      final login = await loginCloudflare(bin, force: true, onLoginUrl: onLoginUrl);
      if (!login.success) {
        throw Exception(login.error ?? 'Cloudflare 重新授权未完成');
      }
      await routeDns(bin, tunnelId, domain);
    }

    await waitForPublicDns(domain);
  }

  Future<void> waitForPublicDns(
    String domain, {
    int attempts = 10,
    Duration interval = const Duration(seconds: 1),
  }) async {
    String? lastError;
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        if (await isPublicDnsResolved(domain)) return;
        lastError = '1.1.1.1 仍未返回可用记录';
      } catch (error) {
        lastError = '$error';
      }
      if (attempt < attempts - 1) await Future<void>.delayed(interval);
    }
    throw Exception('DNS 路由命令已执行，但公网 DNS 验证未通过：$domain。${lastError == null ? '' : ' $lastError'}');
  }

  /// 使用 Cloudflare 1.1.1.1 DoH 绕过本机/路由器的 NXDOMAIN 负缓存。
  Future<bool> isPublicDnsResolved(String domain) async {
    final client = NetworkProxy.createHttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final uri = Uri.https('cloudflare-dns.com', '/dns-query', {'name': domain, 'type': 'A'});
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/dns-json');
      final response = await request.close().timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) {
        throw Exception('DoH HTTP ${response.statusCode}');
      }
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body);
      if (json is! Map<String, dynamic>) return false;
      if (json['Status'] != 0) return false;
      final answers = json['Answer'];
      return answers is List && answers.isNotEmpty;
    } finally {
      client.close();
    }
  }

  bool _shouldReloginForDns(String message) {
    return _isDnsAuthorizationError(message) || message.toLowerCase().contains('dns-zone-mismatch');
  }

  bool _isDnsAuthorizationError(String message) {
    final text = message.toLowerCase();
    return text.contains('1003') ||
        text.contains('9109') ||
        text.contains('unauthorized') ||
        text.contains('not authorized') ||
        text.contains('permission') ||
        text.contains('无权管理') ||
        text.contains('未找到当前环境的 cloudflare cert.pem');
  }

  Future<_CloudflareOriginCredentials> _readOriginCredentials() async {
    final path = await _requireOriginCert();
    final content = await File(path).readAsString();
    final match = RegExp(
      r'-----BEGIN ARGO TUNNEL TOKEN-----\s*(.*?)\s*-----END ARGO TUNNEL TOKEN-----',
      dotAll: true,
    ).firstMatch(content);
    if (match == null) throw const FormatException('Cloudflare cert.pem 格式无效，请重新登录');

    try {
      final encoded = match.group(1)!.replaceAll(RegExp(r'\s+'), '');
      final decoded = jsonDecode(utf8.decode(base64Decode(base64.normalize(encoded))));
      if (decoded is! Map) throw const FormatException();
      final accountId = '${decoded['accountID'] ?? ''}'.trim();
      final zoneId = '${decoded['zoneID'] ?? ''}'.trim();
      final apiToken = '${decoded['apiToken'] ?? ''}'.trim();
      if (accountId.isEmpty || zoneId.isEmpty || apiToken.isEmpty) {
        throw const FormatException();
      }
      return _CloudflareOriginCredentials(accountId: accountId, zoneId: zoneId, apiToken: apiToken);
    } on FormatException {
      throw const FormatException('Cloudflare cert.pem 缺少有效账号、Zone 或 API 凭据，请重新登录');
    }
  }

  Future<Map<String, dynamic>> _cloudflareApi(
    _CloudflareOriginCredentials credentials,
    String method,
    Uri uri, {
    Object? body,
  }) async {
    final client = NetworkProxy.createHttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = const Duration(seconds: 15);
    try {
      final request = await client.openUrl(method, uri);
      request.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer ${credentials.apiToken}')
        ..set(HttpHeaders.acceptHeader, 'application/json;version=1')
        ..set(HttpHeaders.userAgentHeader, 'Codexter cloudflared/$cloudflaredVersion');
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }

      final response = await request.close().timeout(const Duration(seconds: 20));
      final text = await response.transform(utf8.decoder).join();
      Map<String, dynamic>? envelope;
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map) envelope = Map<String, dynamic>.from(decoded);
      } catch (_) {}

      final success = envelope?['success'] == true;
      if (response.statusCode < 200 || response.statusCode >= 300 || !success) {
        final errors = envelope?['errors'];
        final details = errors is List
            ? errors
                  .whereType<Map>()
                  .map(
                    (error) =>
                        'code: ${error['code'] ?? '-'}, reason: ${error['message'] ?? 'unknown'}',
                  )
                  .join('; ')
            : '';
        throw Exception(
          details.isEmpty
              ? 'Cloudflare API $method ${uri.path} 失败（HTTP ${response.statusCode}）'
              : 'Cloudflare API $method ${uri.path} 失败：$details',
        );
      }

      final result = envelope?['result'];
      if (result is Map) return Map<String, dynamic>.from(result);
      if (result is List) return {'items': result};
      return {'value': result};
    } finally {
      client.close(force: true);
    }
  }

  /// 旧版本的 Tunnel JSON 可以安全复制到当前环境；账号级 cert.pem 不迁移。
  /// Debug / Release 必须分别登录，避免不同账号或 Zone 的 cert.pem 互相污染。
  Future<void> migrateLegacyCloudflareCredentials([String? tunnelId]) async {
    if (tunnelId == null || tunnelId.isEmpty) return;
    await ensureTunnelCredentials(tunnelId);
  }

  Future<bool> ensureTunnelCredentials(String tunnelId) async {
    final target = File(await AppPaths.credentialsPath(tunnelId));
    if (await target.exists()) return true;

    final candidates = <File>[
      File(p.join(await AppPaths.configDir, '$tunnelId.json')),
      File(await AppPaths.legacyCredentialsPath(tunnelId)),
    ];
    for (final source in candidates) {
      if (!await source.exists()) continue;
      await target.parent.create(recursive: true);
      await source.copy(target.path);
      return true;
    }
    return false;
  }

  Future<String> _requireOriginCert() async {
    await migrateLegacyCloudflareCredentials();
    final path = await AppPaths.originCertPath;
    if (!await File(path).exists()) {
      throw Exception('未找到当前环境的 Cloudflare cert.pem，请重新登录 Cloudflare');
    }
    return path;
  }

  Future<bool> _adoptTunnelCredentials(String tunnelId, File pendingCredentials) async {
    final target = File(await AppPaths.credentialsPath(tunnelId));
    if (await CloudflaredTunnelSetup.credentialsMatch(pendingCredentials, tunnelId)) {
      await target.parent.create(recursive: true);
      await pendingCredentials.rename(target.path);
      return true;
    }
    return await ensureTunnelCredentials(tunnelId) &&
        await CloudflaredTunnelSetup.credentialsMatch(target, tunnelId);
  }

  Future<GlobalConfig> writeTunnelConfig(GlobalConfig config, String tunnelId) async {
    final credentialsFile = await AppPaths.credentialsPath(tunnelId);
    final configPath = await AppPaths.cloudflaredConfigPath;
    if (!await ensureTunnelCredentials(tunnelId)) {
      throw Exception('缺少 Tunnel credentials：$credentialsFile');
    }

    await File(configPath).writeAsString(
      TunnelConfigYml.build(
        tunnelId: tunnelId,
        credentialsFile: credentialsFile,
        hostname: config.domain,
        serviceUrl: config.localServiceUrl,
      ),
    );

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

  static const githubReleasesUrl = 'https://github.com/cloudflare/cloudflared/releases/latest';
  static const tunnelClientReleasesUrl = 'https://github.com/openai/tunnel-client/releases/latest';

  String get githubAssetName {
    final platformAsset = desktopPlatform.cloudflaredAssetName;
    if (platformAsset != null) return platformAsset;
    if (Platform.isWindows) return 'cloudflared-windows-amd64.exe';
    final arch = _isArm64 ? 'arm64' : 'amd64';
    return 'cloudflared-linux-$arch';
  }

  String get managedBinName => Platform.isWindows ? 'cloudflared.exe' : 'cloudflared';

  String get tunnelClientAssetName {
    final platform = Platform.isWindows
        ? 'windows'
        : Platform.isMacOS
        ? 'darwin'
        : 'linux';
    final arch = _isArm64 ? 'arm64' : 'amd64';
    return 'tunnel-client-$tunnelClientVersion-$platform-$arch.zip';
  }

  String get tunnelClientManagedBinName =>
      Platform.isWindows ? 'tunnel-client.exe' : 'tunnel-client';

  String get tunnelClientDownloadUrl {
    final base = 'https://github.com/openai/tunnel-client/releases/download/$tunnelClientVersion';
    return '$base/$tunnelClientAssetName';
  }

  String get _downloadUrl {
    final base = 'https://github.com/cloudflare/cloudflared/releases/download/$cloudflaredVersion';
    return '$base/$githubAssetName';
  }

  bool get _isArm64 {
    if (Platform.version.contains('arm64')) return true;
    final arch = Platform.environment['PROCESSOR_ARCHITECTURE']?.toLowerCase() ?? '';
    return arch.contains('arm');
  }

  String _homeDir() {
    return Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
  }
}

class _CloudflareOriginCredentials {
  final String accountId;
  final String zoneId;
  final String apiToken;

  const _CloudflareOriginCredentials({
    required this.accountId,
    required this.zoneId,
    required this.apiToken,
  });
}
