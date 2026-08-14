import 'dart:convert';

/// 全局展示格式化，UI 与工具摘要共用
class Fmt {
  const Fmt._();

  static const _prettyJson = JsonEncoder.withIndent('    ');

  static String clock(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    final second = time.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  static String duration(int millis) {
    if (millis < 1000) return '${millis}ms';
    if (millis < 60 * 1000) return '${(millis / 1000).toStringAsFixed(1)}s';
    final minutes = millis ~/ 60000;
    final seconds = (millis % 60000) ~/ 1000;
    if (minutes < 60) return '${minutes}m ${seconds}s';
    final hours = minutes ~/ 60;
    return '${hours}h ${minutes % 60}m';
  }

  static String uptime(DateTime since) {
    return duration(DateTime.now().difference(since).inMilliseconds);
  }

  static String bytes(int count) {
    if (count < 1024) return '$count B';
    if (count < 1024 * 1024) return '${(count / 1024).toStringAsFixed(1)} KB';
    return '${(count / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String json(Object? value) {
    try {
      return _prettyJson.convert(value);
    } catch (_) {
      return '$value';
    }
  }

  static String shortUuid(String uuid) {
    if (uuid.length <= 8) return uuid;
    return '${uuid.substring(0, 8)}…';
  }

  static String ellipsis(String text, int maxChars) {
    final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (flat.length <= maxChars) return flat;
    return '${flat.substring(0, maxChars)}…';
  }

  /// 把工具调用参数压成一行可读摘要，例如 read → src/main.dart
  static String toolArgs(Map<String, dynamic>? args) {
    if (args == null || args.isEmpty) return '';

    final edits = args['edits'];
    if (edits is List && edits.isNotEmpty) {
      final paths = edits
          .whereType<Map>()
          .map((edit) => edit['path'])
          .where((path) => path != null)
          .map((path) => '$path')
          .toSet()
          .toList();
      if (paths.isNotEmpty) return ellipsis(paths.join(', '), 90);
    }

    const preferredKeys = [
      'path',
      'paths',
      'files',
      'cmd',
      'command',
      'pattern',
      'query',
      'url',
      'name',
      'processId',
      'goalId',
      'server',
      'tool',
      'summary',
    ];
    for (final key in preferredKeys) {
      final value = args[key];
      if (value == null) continue;
      if (value is List) {
        if (value.isEmpty) continue;
        return ellipsis(value.join(', '), 90);
      }
      return ellipsis('$value', 90);
    }
    return ellipsis(args.keys.join(', '), 90);
  }
}
