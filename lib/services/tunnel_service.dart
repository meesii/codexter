import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../utils/path_guard.dart';
import '../utils/rolling_buffer.dart';
import '../utils/win_kill_job.dart';
import 'tunnel_process_guard.dart';

class TunnelReadyInfo {
  final String? location;
  final String? protocol;

  const TunnelReadyInfo({this.location, this.protocol});
}

class TunnelProcessException implements Exception {
  final int? exitCode;
  final String message;
  final String log;

  const TunnelProcessException({this.exitCode, required this.message, this.log = ''});

  @override
  String toString() {
    final suffix = log.trim().isEmpty ? '' : '\n${log.trim()}';
    final code = exitCode == null ? '' : ' (exit $exitCode)';
    return '$message$code$suffix';
  }
}

class CloudflaredCommandException implements Exception {
  final int exitCode;
  final List<String> args;
  final String output;

  const CloudflaredCommandException({
    required this.exitCode,
    required this.args,
    required this.output,
  });

  @override
  String toString() => 'cloudflared 失败 (exit $exitCode): $output';
}

/// cloudflared 长驻进程管理，生命周期与工作区完全解耦
class TunnelService extends ChangeNotifier {
  static final _readyRegex = RegExp(r'Registered tunnel connection');
  static final _locationRegex = RegExp(r'location=(\S+)');
  static final _protocolRegex = RegExp(r'protocol=(\S+)');

  final RollingBuffer _log = RollingBuffer(32000);
  Process? _process;
  bool _running = false;
  TunnelReadyInfo? _readyInfo;
  String? _configPath;

  bool get isRunning => _running;
  TunnelReadyInfo? get readyInfo => _readyInfo;
  String get logTail => _log.text;

  Future<TunnelReadyInfo> start({
    required String bin,
    required String tunnelId,
    required String configPath,
    String? hostname,
    int readyTimeoutSec = 45,
  }) async {
    if (_running) throw Exception('Tunnel 已在运行');

    _configPath = configPath;
    _log.clear();
    _appendLog('---- ${DateTime.now().toIso8601String()} start tunnel $tunnelId ----\n');

    final stopped = await TunnelProcessGuard.stopOwned(configPath: configPath);
    if (stopped > 0) {
      _appendLog('---- stopped $stopped leftover cloudflared owned by this app ----\n');
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }

    final completer = Completer<TunnelReadyInfo>();
    _process = await Process.start(bin, [
      'tunnel',
      '--config',
      configPath,
      '--protocol',
      'http2',
      '--edge-ip-version',
      '4',
      'run',
      tunnelId,
    ], environment: Platform.environment);
    final attached = WinKillOnCloseJob.assignPid(_process!.pid);
    if (attached || WinKillOnCloseJob.boundCurrentProcess) {
      _appendLog('---- cloudflared pid=${_process!.pid} will exit with app ----\n');
    } else if (Platform.isWindows) {
      _appendLog('---- cloudflared pid=${_process!.pid} may survive if the app is killed ----\n');
    }
    _running = true;
    notifyListeners();

    void watch(Stream<List<int>> stream) {
      stream.listen((data) {
        final text = TextDecode.bytes(data);
        _appendLog(text);
        if (completer.isCompleted || !_readyRegex.hasMatch(text)) return;
        completer.complete(
          TunnelReadyInfo(
            location: _locationRegex.firstMatch(text)?.group(1),
            protocol: _protocolRegex.firstMatch(text)?.group(1),
          ),
        );
      });
    }

    watch(_process!.stdout);
    watch(_process!.stderr);

    _process!.exitCode.then((code) {
      _appendLog('---- cloudflared exited code=$code ----\n');
      _running = false;
      notifyListeners();
      if (!completer.isCompleted) {
        completer.completeError(
          TunnelProcessException(exitCode: code, message: 'cloudflared 在隧道就绪前退出', log: _log.text),
        );
      }
    });

    final timeout = Timer(Duration(seconds: readyTimeoutSec), () {
      if (!completer.isCompleted) {
        completer.completeError(
          TunnelProcessException(message: '隧道在 ${readyTimeoutSec}s 内未就绪', log: _log.text),
        );
      }
    });

    try {
      _readyInfo = await completer.future;
      return _readyInfo!;
    } catch (_) {
      await stop();
      rethrow;
    } finally {
      timeout.cancel();
    }
  }

  Future<void> stop() async {
    final process = _process;
    _process = null;
    _running = false;
    _readyInfo = null;
    notifyListeners();

    if (process != null) {
      try {
        process.kill(ProcessSignal.sigterm);
        await process.exitCode.timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            process.kill(ProcessSignal.sigkill);
            return -1;
          },
        );
      } catch (_) {}
    }

    final configPath = _configPath;
    if (configPath != null) {
      await TunnelProcessGuard.stopOwned(configPath: configPath);
    }
  }

  Future<bool> verifyRoute(String publicUrl, {int attempts = 10, int timeoutMs = 5000}) async {
    final uri = Uri.parse(publicUrl);
    for (var attempt = 0; attempt < attempts; attempt++) {
      final client = HttpClient()..connectionTimeout = Duration(milliseconds: timeoutMs);
      try {
        final request = await client.getUrl(uri);
        final response = await request.close().timeout(Duration(milliseconds: timeoutMs));
        final status = response.statusCode;
        await response.drain<void>();
        if (status < 500) return true;
      } catch (_) {
      } finally {
        client.close();
      }
      if (attempt < attempts - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
      }
    }
    return false;
  }

  void _appendLog(String text) {
    if (text.isEmpty) return;
    _log.append(text);
    notifyListeners();
  }
}

/// cloudflared.yml 生成，路径全透传给本地多工作区服务
class TunnelConfigYml {
  const TunnelConfigYml._();

  static String build({
    required String tunnelId,
    required String credentialsFile,
    required String hostname,
    required String serviceUrl,
  }) {
    return [
      'tunnel: $tunnelId',
      "credentials-file: '$credentialsFile'",
      'protocol: http2',
      'edge-ip-version: 4',
      '',
      'ingress:',
      '  - hostname: $hostname',
      '    service: $serviceUrl',
      '  - service: http_status:404',
      '',
    ].join('\n');
  }
}

class CloudflaredCommandResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  const CloudflaredCommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  String get combinedOutput =>
      [stdout.trim(), stderr.trim()].where((part) => part.isNotEmpty).join('\n');
}

/// cloudflared 命令行调用
class CloudflaredCli {
  const CloudflaredCli._();

  static Future<CloudflaredCommandResult> runDetailed(
    String bin,
    List<String> args, {
    int timeoutSec = 120,
  }) async {
    final result = await Process.run(
      bin,
      args,
      environment: Platform.environment,
      stdoutEncoding: null,
      stderrEncoding: null,
    ).timeout(Duration(seconds: timeoutSec));

    final commandResult = CloudflaredCommandResult(
      exitCode: result.exitCode,
      stdout: TextDecode.bytes(result.stdout),
      stderr: TextDecode.bytes(result.stderr),
    );
    if (result.exitCode == 0) return commandResult;

    throw CloudflaredCommandException(
      exitCode: result.exitCode,
      args: List<String>.unmodifiable(args),
      output: commandResult.combinedOutput,
    );
  }

  static Future<String> run(String bin, List<String> args, {int timeoutSec = 120}) async {
    final result = await runDetailed(bin, args, timeoutSec: timeoutSec);
    return result.stdout;
  }
}
