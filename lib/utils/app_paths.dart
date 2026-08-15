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

  static Future<String> credentialsPath(String tunnelId) async {
    final cloudflaredDir = p.join(_home(), '.cloudflared');
    return p.join(cloudflaredDir, '$tunnelId.json');
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
