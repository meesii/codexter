import 'dart:io';
import 'package:path/path.dart' as p;
import '../app_info.dart';

class AppPaths {
  static String? _cached;

  static Future<String> get configDir async {
    if (_cached != null) return _cached!;
    final base = Platform.isWindows
        ? Platform.environment['APPDATA']!
        : Platform.isMacOS
        ? p.join(_home(), 'Library', 'Application Support')
        : p.join(_home(), '.local', 'share');
    _cached = p.join(base, appConfigDirName);
    final dir = Directory(_cached!);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return _cached!;
  }

  static Future<String> get binDir async {
    final dir = p.join(await configDir, 'bin');
    final d = Directory(dir);
    if (!await d.exists()) {
      await d.create(recursive: true);
    }
    return dir;
  }

  static Future<String> get skillsDir async {
    final dir = p.join(await configDir, 'skills');
    await Directory(dir).create(recursive: true);
    return dir;
  }

  static Future<String> get cloudflaredPath async {
    final ext = Platform.isWindows ? '.exe' : '';
    return p.join(await binDir, 'cloudflared$ext');
  }

  static Future<String> get cloudflaredConfigPath async {
    return p.join(await configDir, 'cloudflared.yml');
  }

  /// 当前应用环境独立的 Cloudflare 凭据目录。
  /// Debug 与 Release 会分别落在 codexter-dev / codexter 下，互不覆盖。
  static Future<String> get cloudflareDir async {
    final dir = p.join(await configDir, 'cloudflare');
    await Directory(dir).create(recursive: true);
    return dir;
  }

  static Future<String> get originCertPath async {
    return p.join(await cloudflareDir, 'cert.pem');
  }

  /// cloudflared tunnel login 只能写默认 Home 下的 .cloudflared/cert.pem，
  /// 因此登录时给子进程一个应用独享的临时 Home，完成后再收纳到 originCertPath。
  static Future<String> get cloudflareLoginHome async {
    return p.join(await cloudflareDir, '.login-home');
  }

  static Future<String> credentialsPath(String tunnelId) async {
    return p.join(await cloudflareDir, '$tunnelId.json');
  }

  /// 旧版本使用用户全局 ~/.cloudflared，保留只读迁移入口。
  static Future<String> get legacyOriginCertPath async {
    return p.join(_home(), '.cloudflared', 'cert.pem');
  }

  static Future<String> legacyCredentialsPath(String tunnelId) async {
    return p.join(_home(), '.cloudflared', '$tunnelId.json');
  }

  static Future<int> findAvailablePort([int start = 18920]) async {
    for (var port = start; port < start + 100; port++) {
      try {
        final server = await ServerSocket.bind('127.0.0.1', port);
        await server.close();
        return port;
      } catch (_) {}
    }
    throw Exception(
      'No available port found in range $start to ${start + 100}',
    );
  }

  static String _home() {
    return Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
  }
}
