import 'dart:convert';
import 'dart:io';

/// 只结束「使用本应用 cloudflared.yml」拉起的 cloudflared，避免误杀用户其它隧道。
class TunnelProcessGuard {
  const TunnelProcessGuard._();

  /// 命令行是否指向本应用的隧道配置文件。
  static bool isOwnedCommand(String commandLine, String configPath) {
    final command = _fold(commandLine);
    final config = _fold(configPath);
    if (command.isEmpty || config.isEmpty) return false;
    if (!command.contains('cloudflared')) return false;
    if (!command.contains('--config')) return false;
    final escaped = RegExp.escape(config);
    final pattern = RegExp('--config(?:\\s+|=)["\']?$escaped["\']?(?:\\s|\$)');
    return pattern.hasMatch(command);
  }

  /// 从 `pid<TAB>commandLine` 列表中解析出属于本应用的 PID。
  static List<int> parseOwnedPids(String listing, String configPath) {
    final pids = <int>[];
    for (final raw in listing.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final tab = line.indexOf('\t');
      final pidText = tab < 0 ? line : line.substring(0, tab);
      final command = tab < 0 ? '' : line.substring(tab + 1);
      final pid = int.tryParse(pidText.trim());
      if (pid == null || pid <= 0) continue;
      if (!isOwnedCommand(command, configPath)) continue;
      pids.add(pid);
    }
    return pids;
  }

  /// 结束使用 [configPath] 的残留 cloudflared。
  ///
  /// [keepPid] 若提供则跳过该进程。返回实际发出结束信号的进程数。
  static Future<int> stopOwned({required String configPath, int? keepPid}) async {
    final targets = (await listOwnedPids(configPath)).where((pid) => pid != keepPid).toList();
    if (targets.isEmpty) return 0;

    for (final pid in targets) {
      Process.killPid(pid);
    }

    for (var attempt = 0; attempt < 10; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final left = (await listOwnedPids(configPath)).where((pid) => pid != keepPid).toList();
      if (left.isEmpty) break;
      for (final pid in left) {
        Process.killPid(pid);
      }
    }
    return targets.length;
  }

  /// 列出当前仍占用本应用配置文件的 cloudflared PID。
  static Future<List<int>> listOwnedPids(String configPath) async {
    final listing = Platform.isWindows ? await _listWindows() : await _listUnix();
    return parseOwnedPids(listing, configPath);
  }

  static String _fold(String value) {
    return value.replaceAll(r'\', '/').toLowerCase().trim();
  }

  static Future<String> _listWindows() async {
    final result = await Process.run(
      'powershell',
      const [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r'''Get-CimInstance Win32_Process -Filter "Name = 'cloudflared.exe'" | ForEach-Object { '{0}`t{1}' -f $_.ProcessId, $_.CommandLine }''',
      ],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    return result.stdout.toString();
  }

  static Future<String> _listUnix() async {
    final result = await Process.run(
      'ps',
      const ['-ax', '-o', 'pid=,args='],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    final buffer = StringBuffer();
    for (final raw in result.stdout.toString().split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final match = RegExp(r'^(\d+)\s+(.*)$').firstMatch(line);
      if (match == null) continue;
      buffer.writeln('${match.group(1)}\t${match.group(2)}');
    }
    return buffer.toString();
  }
}
