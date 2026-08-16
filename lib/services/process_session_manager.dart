import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/process_info.dart';
import '../utils/path_guard.dart';
import '../utils/rolling_buffer.dart';

const defaultMaxOutputChars = 40000;
const maxToolBufferChars = 1000000;
const maxViewBufferChars = 200000;
const completedTtl = Duration(minutes: 5);
const processNotifyThrottleMs = 250;

class ProcessSnapshot {
  final int? processId;
  final String output;
  final bool outputTruncated;
  final bool running;
  final int? exitCode;
  final String? signal;

  ProcessSnapshot({
    this.processId,
    required this.output,
    required this.outputTruncated,
    required this.running,
    this.exitCode,
    this.signal,
  });
}

/// 单个受管子进程。toolBuffer 供工具读取后清空，viewBuffer 只增不清供 GUI 终端渲染
class ProcessSession {
  final int id;
  final String command;
  final String cwd;
  final String? name;
  final DateTime startedAt = DateTime.now();
  final RollingBuffer toolBuffer = RollingBuffer(maxToolBufferChars);
  final RollingBuffer viewBuffer = RollingBuffer(maxViewBufferChars);

  Process? child;
  bool running = true;
  int? exitCode;
  String? signal;
  DateTime? endedAt;
  bool truncated = false;
  Timer? cleanupTimer;

  ProcessSession({required this.id, required this.command, required this.cwd, this.name});

  ProcessInfo toInfo() {
    return ProcessInfo(
      processId: id,
      command: command,
      cwd: cwd,
      name: name,
      startedAt: startedAt,
      endedAt: endedAt,
      running: running,
      exitCode: exitCode,
      signal: signal,
    );
  }
}

/// 工作区内的长驻进程池，同时驱动「运行终端」页面
class ProcessSessionManager extends ChangeNotifier {
  final Map<int, ProcessSession> _sessions = {};
  int _nextId = 1;
  Timer? _notifyTimer;
  bool _disposed = false;

  List<ProcessInfo> list() {
    final infos = _sessions.values.map((session) => session.toInfo()).toList();
    infos.sort((left, right) => left.processId.compareTo(right.processId));
    return infos;
  }

  List<ProcessInfo> listRunning() {
    return list().where((info) => info.running).toList();
  }

  int get runningCount => _sessions.values.where((session) => session.running).length;

  ProcessSession? getSession(int processId) => _sessions[processId];

  String viewOutput(int processId) {
    final session = _sessions[processId];
    if (session == null) return '';
    return session.viewBuffer.text;
  }

  Future<ProcessSnapshot> start(
    String command,
    String cwd, {
    String? name,
    int yieldMs = 10000,
  }) async {
    final session = ProcessSession(id: _nextId++, command: command, cwd: cwd, name: name);
    _sessions[session.id] = session;

    try {
      final shell = Platform.isWindows ? 'powershell.exe' : '/bin/bash';
      final shellArgs = Platform.isWindows
          ? ['-NoLogo', '-NonInteractive', '-Command', command]
          : ['-c', command];

      session.child = await Process.start(
        shell,
        shellArgs,
        workingDirectory: cwd,
        environment: {...Platform.environment, 'NO_COLOR': '1'},
      );

      session.child!.stdout.listen((data) => _append(session, TextDecode.bytes(data)));
      session.child!.stderr.listen((data) => _append(session, TextDecode.bytes(data)));
      session.child!.exitCode
          .then((code) {
            _finish(session, code, null);
          })
          .catchError((Object error) {
            _append(session, '$error');
            _finish(session, -1, null);
          });
    } catch (error) {
      _sessions.remove(session.id);
      rethrow;
    }

    _scheduleNotify();
    await _waitForExit(session, yieldMs);
    return _consume(session, defaultMaxOutputChars);
  }

  Future<ProcessSnapshot> poll(int processId, {String? stdinChars, int yieldMs = 5000}) async {
    final session = _requireSession(processId);

    if (stdinChars != null && stdinChars.isNotEmpty && session.running) {
      if (stdinChars.contains('\u0003')) {
        _signalProcess(session, ProcessSignal.sigint);
      }
      final writable = stdinChars.replaceAll('\u0003', '');
      if (writable.isNotEmpty) {
        try {
          session.child?.stdin.write(writable);
        } catch (_) {}
      }
    }

    if (session.running) {
      await _waitForExit(session, yieldMs);
    }
    return _consume(session, defaultMaxOutputChars);
  }

  Future<ProcessSnapshot> kill(int processId) async {
    final session = _requireSession(processId);
    return _killSession(session);
  }

  String peekOutput(int processId, {int maxChars = defaultMaxOutputChars}) {
    final session = _sessions[processId];
    if (session == null) return '';
    return _clampOutput(session.toolBuffer.text, maxChars);
  }

  Future<void> shutdown() async {
    final sessions = _sessions.values.toList();
    for (final session in sessions) {
      try {
        await _killSession(session);
      } catch (_) {}
      session.cleanupTimer?.cancel();
    }
    _sessions.clear();
    _scheduleNotify();
  }

  void _append(ProcessSession session, String chunk) {
    if (chunk.isEmpty) return;
    if (session.toolBuffer.append(chunk)) session.truncated = true;
    session.viewBuffer.append(chunk);
    _scheduleNotify();
  }

  void _finish(ProcessSession session, int code, String? signal) {
    if (!session.running) return;
    session.running = false;
    session.exitCode = code;
    session.signal = signal;
    session.endedAt = DateTime.now();
    session.cleanupTimer = Timer(completedTtl, () {
      _sessions.remove(session.id);
      _scheduleNotify();
    });
    _scheduleNotify();
  }

  Future<void> _waitForExit(ProcessSession session, int yieldMs) async {
    if (!session.running) return;
    final completer = Completer<void>();
    final timer = Timer(Duration(milliseconds: yieldMs), () {
      if (!completer.isCompleted) completer.complete();
    });

    session.child?.exitCode
        .then((_) {
          if (!completer.isCompleted) completer.complete();
        })
        .catchError((Object _) {
          if (!completer.isCompleted) completer.complete();
        });

    await completer.future;
    timer.cancel();
  }

  ProcessSnapshot _consume(ProcessSession session, int maxChars) {
    final raw = session.toolBuffer.text;
    final output = _clampOutput(raw, maxChars);
    final truncated = session.truncated || output.length < raw.length;
    session.toolBuffer.clear();
    session.truncated = false;

    return ProcessSnapshot(
      processId: session.running ? session.id : null,
      output: output,
      outputTruncated: truncated,
      running: session.running,
      exitCode: session.exitCode,
      signal: session.signal,
    );
  }

  Future<ProcessSnapshot> _killSession(ProcessSession session) async {
    if (session.running) {
      _signalProcess(session, ProcessSignal.sigterm);
      await _waitForExit(session, 2000);
      if (session.running) {
        _signalProcess(session, ProcessSignal.sigkill);
        await _waitForExit(session, 1000);
      }
      if (session.running) {
        _finish(session, -1, 'SIGKILL');
      } else {
        session.signal ??= 'SIGTERM';
      }
    }
    return _consume(session, defaultMaxOutputChars);
  }

  void _signalProcess(ProcessSession session, ProcessSignal signal) {
    try {
      session.child?.kill(signal);
    } catch (_) {}
  }

  ProcessSession _requireSession(int processId) {
    final session = _sessions[processId];
    if (session == null) throw Exception('Unknown processId: $processId');
    return session;
  }

  String _clampOutput(String output, int maxChars) {
    if (output.length <= maxChars) return output;
    final half = maxChars ~/ 2;
    final head = output.substring(0, half);
    final tail = output.substring(output.length - half);
    return '$head\n... output truncated ...\n$tail';
  }

  void _scheduleNotify() {
    if (_disposed || _notifyTimer != null) return;
    _notifyTimer = Timer(const Duration(milliseconds: processNotifyThrottleMs), () {
      _notifyTimer = null;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _notifyTimer?.cancel();
    super.dispose();
  }
}
