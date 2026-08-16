class ProcessInfo {
  final int processId;
  final String command;
  final String cwd;
  final String? name;
  final DateTime startedAt;
  final DateTime? endedAt;
  final bool running;
  final int? exitCode;
  final String? signal;

  ProcessInfo({
    required this.processId,
    required this.command,
    required this.cwd,
    this.name,
    required this.startedAt,
    this.endedAt,
    required this.running,
    this.exitCode,
    this.signal,
  });

  Duration get wallTime => (endedAt ?? DateTime.now()).difference(startedAt);

  String get label => name ?? command;

  String get stateText {
    if (running) return '运行中';
    if (signal != null) return '已终止 $signal';
    return '已退出 (code $exitCode)';
  }
}
