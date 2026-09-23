import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/workspace.dart';
import '../utils/app_paths.dart';
import '../utils/path_guard.dart';
import '../utils/rolling_buffer.dart';
import '../utils/win_kill_job.dart';
import 'network_proxy.dart';

class OpenAiTunnelService extends ChangeNotifier {
  final RollingBuffer _log = RollingBuffer(32000);
  final Map<String, Process> _processes = {};
  final Set<String> _ready = {};
  int _expectedCount = 0;

  bool get isRunning => isFullyRunningState(
    expectedCount: _expectedCount,
    processCount: _processes.length,
    readyCount: _ready.length,
  );

  @visibleForTesting
  static bool isFullyRunningState({
    required int expectedCount,
    required int processCount,
    required int readyCount,
  }) => expectedCount > 0 && processCount == expectedCount && readyCount == expectedCount;
  String get logTail => _log.text;
  int get runningCount => _processes.length;
  int get expectedCount => _expectedCount;

  Future<void> startAll({
    required String bin,
    required String runtimeApiKey,
    required String localServiceUrl,
    required List<Workspace> workspaces,
    int readyTimeoutSec = 20,
  }) async {
    await stopAll();
    _log.clear();

    final enabled = workspaces.where((workspace) => workspace.enabled).toList();
    if (enabled.isEmpty) return;
    _expectedCount = enabled.length;
    notifyListeners();

    try {
      for (final workspace in enabled) {
        final tunnelId = workspace.openAiTunnelId?.trim() ?? '';
        if (tunnelId.isEmpty) {
          throw Exception('工作区「${workspace.name}」尚未配置 OpenAI tunnel_id');
        }
        await _startWorkspace(
          bin: bin,
          runtimeApiKey: runtimeApiKey,
          localMcpUrl: '$localServiceUrl${workspace.mcpPath}',
          workspace: workspace,
          tunnelId: tunnelId,
          readyTimeoutSec: readyTimeoutSec,
        );
      }
    } catch (_) {
      await stopAll();
      rethrow;
    }
  }

  Future<void> _startWorkspace({
    required String bin,
    required String runtimeApiKey,
    required String localMcpUrl,
    required Workspace workspace,
    required String tunnelId,
    required int readyTimeoutSec,
  }) async {
    final healthFile = File(await AppPaths.openAiHealthUrlPath(workspace.uuid));
    if (await healthFile.exists()) await healthFile.delete();

    _appendLog('---- start OpenAI tunnel ${workspace.name} ($tunnelId) ----\n');
    final environment = NetworkProxy.processEnvironment(
      overrides: {'CONTROL_PLANE_API_KEY': runtimeApiKey},
    );
    final process = await Process.start(bin, [
      'run',
      '--control-plane.tunnel-id',
      tunnelId,
      '--mcp.server-url',
      localMcpUrl,
      '--health.listen-addr',
      '127.0.0.1:0',
      '--health.url-file',
      healthFile.path,
      '--log.level',
      'info',
      '--log.format',
      'struct-text',
    ], environment: environment);
    _processes[workspace.uuid] = process;
    WinKillOnCloseJob.assignPid(process.pid);
    notifyListeners();

    void watch(Stream<List<int>> stream) {
      stream.listen((data) => _appendLog(TextDecode.bytes(data)));
    }

    watch(process.stdout);
    watch(process.stderr);
    unawaited(
      process.exitCode.then((code) {
        if (identical(_processes[workspace.uuid], process)) {
          _processes.remove(workspace.uuid);
          _ready.remove(workspace.uuid);
          unawaited(_deleteHealthFile(workspace.uuid));
          _appendLog('---- OpenAI tunnel ${workspace.name} exited code=$code ----\n');
          notifyListeners();
        }
      }),
    );

    final deadline = DateTime.now().add(Duration(seconds: readyTimeoutSec));
    while (DateTime.now().isBefore(deadline)) {
      if (!identical(_processes[workspace.uuid], process)) {
        throw Exception('OpenAI tunnel-client 在就绪前退出：${workspace.name}');
      }
      if (await _isReady(healthFile)) {
        _ready.add(workspace.uuid);
        _appendLog('---- OpenAI tunnel ready: ${workspace.name} ----\n');
        notifyListeners();
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }

    await stopWorkspace(workspace.uuid);
    throw TimeoutException('OpenAI tunnel-client 在 ${readyTimeoutSec}s 内未就绪：${workspace.name}');
  }

  Future<bool> _isReady(File healthFile) async {
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

  Future<void> stopWorkspace(String workspaceUuid) async {
    final process = _processes.remove(workspaceUuid);
    _ready.remove(workspaceUuid);
    if (process != null) await _terminate(process);
    await _deleteHealthFile(workspaceUuid);
    notifyListeners();
  }

  Future<void> stopAll() async {
    final workspaceUuids = _processes.keys.toList();
    final processes = _processes.values.toList();
    _processes.clear();
    _ready.clear();
    _expectedCount = 0;
    for (final process in processes) {
      await _terminate(process);
    }
    for (final workspaceUuid in workspaceUuids) {
      await _deleteHealthFile(workspaceUuid);
    }
    notifyListeners();
  }

  Future<void> _deleteHealthFile(String workspaceUuid) async {
    final file = File(await AppPaths.openAiHealthUrlPath(workspaceUuid));
    if (!await file.exists()) return;
    try {
      await file.delete();
    } catch (_) {}
  }

  Future<void> _terminate(Process process) async {
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

  void _appendLog(String text) {
    if (text.isEmpty) return;
    _log.append(text);
    notifyListeners();
  }
}
