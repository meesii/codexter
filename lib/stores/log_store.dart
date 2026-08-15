import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import '../models/mcp_log_entry.dart';

const maxLogEntriesPerWorkspace = 1000;
const logNotifyThrottleMs = 120;

/// 每工作区内存环形日志缓冲，不落盘。写入合并节流后再通知 UI
class LogStore extends ChangeNotifier {
  final Map<String, Queue<McpLogEntry>> _entries = {};
  final Map<String, WorkspaceLogStats> _stats = {};
  Timer? _notifyTimer;
  bool _disposed = false;

  List<McpLogEntry> entriesOf(String workspaceUuid) {
    final queue = _entries[workspaceUuid];
    if (queue == null) return const [];
    return queue.toList(growable: false);
  }

  List<McpLogEntry> recentOf(String workspaceUuid, int count) {
    final all = entriesOf(workspaceUuid);
    if (all.length <= count) return all;
    return all.sublist(all.length - count);
  }

  String? latestToolPurposeOf(String workspaceUuid) {
    return latestToolOf(workspaceUuid)?.purpose;
  }

  McpLogEntry? latestToolOf(String workspaceUuid) {
    final queue = _entries[workspaceUuid];
    if (queue == null) return null;
    for (final entry in queue.toList(growable: false).reversed) {
      if (entry.isToolCall) return entry;
    }
    return null;
  }

  McpLogEntry? activeToolOf(String workspaceUuid) {
    final queue = _entries[workspaceUuid];
    if (queue == null) return null;
    for (final entry in queue.toList(growable: false).reversed) {
      if (entry.isToolCall && entry.pending && entry.toolName != 'summary') {
        return entry;
      }
    }
    return null;
  }

  WorkspaceLogStats statsOf(String workspaceUuid) {
    return _stats.putIfAbsent(workspaceUuid, WorkspaceLogStats.new);
  }

  void add(McpLogEntry entry) {
    final queue = _entries.putIfAbsent(
      entry.workspaceUuid,
      Queue<McpLogEntry>.new,
    );
    queue.addLast(entry);
    while (queue.length > maxLogEntriesPerWorkspace) {
      queue.removeFirst();
    }
    statsOf(entry.workspaceUuid).record(entry);
    _scheduleNotify();
  }

  void completeEntry(
    McpLogEntry entry, {
    required Map<String, dynamic> response,
    required int durationMs,
    required bool success,
    String? error,
  }) {
    entry.complete(
      response: response,
      durationMs: durationMs,
      success: success,
      error: error,
    );
    if (!success) statsOf(entry.workspaceUuid).recordFailure();
    _scheduleNotify();
  }

  void clearEntries(String workspaceUuid) {
    _entries.remove(workspaceUuid);
    _scheduleNotify();
  }

  void clear(String workspaceUuid) {
    _entries.remove(workspaceUuid);
    _stats.remove(workspaceUuid);
    _scheduleNotify();
  }

  void clearAll() {
    _entries.clear();
    _stats.clear();
    _scheduleNotify();
  }

  void _scheduleNotify() {
    if (_disposed || _notifyTimer != null) return;
    _notifyTimer = Timer(const Duration(milliseconds: logNotifyThrottleMs), () {
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
