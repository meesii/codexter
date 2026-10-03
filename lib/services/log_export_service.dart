import 'dart:convert';

import '../models/mcp_log_entry.dart';
import '../utils/fmt.dart';

enum LogExportGranularity { compact, standard, detailed }

enum LogExportResponseMode { none, truncated, full }

class LogExportOptions {
  final LogExportGranularity granularity;
  final LogExportResponseMode responseMode;
  final int truncatedResponseChars;

  const LogExportOptions({
    this.granularity = LogExportGranularity.standard,
    this.responseMode = LogExportResponseMode.none,
    this.truncatedResponseChars = 4000,
  });
}

class LogExportDocument {
  final String text;
  final int utf8Bytes;
  final int estimatedTokens;

  const LogExportDocument({
    required this.text,
    required this.utf8Bytes,
    required this.estimatedTokens,
  });
}

/// 把 MCP 日志整理成适合重新提供给 ChatGPT 的 Markdown。
///
/// 默认只导出 purpose、工具名、参数摘要与状态；Response 必须由用户显式开启，
/// 避免 read / exec_command 等大结果无意中占满上下文。
class LogExportService {
  const LogExportService._();

  static const _prettyJson = JsonEncoder.withIndent('  ');

  static LogExportDocument build({
    required List<McpLogEntry> entries,
    required LogExportOptions options,
    String? workspaceName,
    String? projectRoot,
    DateTime? exportedAt,
  }) {
    final now = exportedAt ?? DateTime.now();
    final buffer = StringBuffer()
      ..writeln('# Codexter Log Export')
      ..writeln()
      ..writeln('- Exported: ${now.toIso8601String()}')
      ..writeln('- Entries: ${entries.length}')
      ..writeln('- Granularity: ${_granularityLabel(options.granularity)}')
      ..writeln('- Response: ${_responseLabel(options.responseMode)}');

    if (workspaceName != null && workspaceName.trim().isNotEmpty) {
      buffer.writeln('- Workspace: ${workspaceName.trim()}');
    }
    if (projectRoot != null && projectRoot.trim().isNotEmpty) {
      buffer.writeln('- Project root: `${projectRoot.trim()}`');
    }

    for (final entry in entries) {
      buffer
        ..writeln()
        ..writeln('---')
        ..writeln()
        ..writeln('## ${entry.clockText} · ${entry.title}')
        ..writeln();

      final purpose = entry.purpose;
      if (purpose != null) {
        buffer
          ..writeln('**Purpose**')
          ..writeln()
          ..writeln(purpose)
          ..writeln();
      }

      if (options.granularity == LogExportGranularity.compact) {
        _writeCompactEntry(buffer, entry);
      } else if (options.granularity == LogExportGranularity.standard) {
        _writeStandardEntry(buffer, entry);
      } else {
        _writeDetailedEntry(buffer, entry);
      }

      final error = entry.error?.trim();
      if (error != null && error.isNotEmpty) {
        buffer
          ..writeln()
          ..writeln('**Error**')
          ..writeln()
          ..writeln(error);
      }

      if (options.responseMode != LogExportResponseMode.none) {
        final response = options.responseMode == LogExportResponseMode.full
            ? entry.response
            : entry.displayResponse;
        if (response != null) {
          var responseText = _json(response);
          if (options.responseMode == LogExportResponseMode.truncated &&
              responseText.length > options.truncatedResponseChars) {
            responseText =
                '${responseText.substring(0, options.truncatedResponseChars)}\n… response truncated …';
          }
          buffer
            ..writeln()
            ..writeln('**Response**')
            ..writeln()
            ..writeln('~~~json')
            ..writeln(responseText)
            ..writeln('~~~');
        }
      }
    }

    final text = buffer.toString();
    final bytes = utf8.encode(text).length;
    return LogExportDocument(
      text: text,
      utf8Bytes: bytes,
      // 中英文混合日志用 UTF-8 字节 / 4 做粗略估算，比字符数 / 4 更接近实际量级。
      estimatedTokens: (bytes / 4).ceil(),
    );
  }

  static void _writeCompactEntry(StringBuffer buffer, McpLogEntry entry) {
    buffer.writeln('**Status** ${_status(entry)}');
  }

  static void _writeStandardEntry(StringBuffer buffer, McpLogEntry entry) {
    final summary = entry.argsSummary.trim();
    if (summary.isNotEmpty) {
      buffer
        ..writeln('**Arguments**')
        ..writeln()
        ..writeln(summary)
        ..writeln();
    }
    buffer.writeln('**Status** ${_status(entry)}');
  }

  static void _writeDetailedEntry(StringBuffer buffer, McpLogEntry entry) {
    buffer
      ..writeln('**Method** `${entry.method}`')
      ..writeln()
      ..writeln('**Status** ${_status(entry)}');
    if (!entry.pending) {
      buffer
        ..writeln()
        ..writeln('**Duration** ${Fmt.duration(entry.durationMs)}');
    }

    final args = entry.executionArguments;
    if (args != null && args.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('**Arguments**')
        ..writeln()
        ..writeln('~~~json')
        ..writeln(_json(args))
        ..writeln('~~~');
    } else if (!entry.isToolCall && entry.displayRequest != null) {
      buffer
        ..writeln()
        ..writeln('**Request**')
        ..writeln()
        ..writeln('~~~json')
        ..writeln(_json(entry.displayRequest))
        ..writeln('~~~');
    }
  }

  static String _status(McpLogEntry entry) {
    if (entry.pending) return 'pending';
    return entry.success ? 'success' : 'error';
  }

  static String _json(Object? value) {
    try {
      return _prettyJson.convert(value);
    } catch (_) {
      return '$value';
    }
  }

  static String _granularityLabel(LogExportGranularity value) => switch (value) {
    LogExportGranularity.compact => 'compact',
    LogExportGranularity.standard => 'standard',
    LogExportGranularity.detailed => 'detailed',
  };

  static String _responseLabel(LogExportResponseMode value) => switch (value) {
    LogExportResponseMode.none => 'none',
    LogExportResponseMode.truncated => 'truncated',
    LogExportResponseMode.full => 'full',
  };
}
