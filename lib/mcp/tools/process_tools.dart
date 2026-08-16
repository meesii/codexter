import 'registry.dart';
import 'tool_context.dart';

/// 终端工具组：exec_command / write_stdin
class ProcessTools {
  const ProcessTools._();

  static const _charsPerTokenEstimate = 4;

  static void register(ToolRegistry registry, ToolContext context) {
    final manager = context.processManager;
    final guard = context.pathGuard;

    registry.register(_execCommandSchema, (raw) async {
      final args = ToolArgs(raw);
      final cmd = args.requireText('cmd');
      final workdir = guard.safeResolve(args.text('workdir') ?? '.');
      final snapshot = await manager.start(
        cmd,
        workdir,
        yieldMs: args.intOr('yield_time_ms', 10000),
      );
      return _snapshotResult(
        snapshot.output,
        running: snapshot.running,
        sessionId: snapshot.processId,
        exitCode: snapshot.exitCode,
        outputTruncated: snapshot.outputTruncated,
        maxOutputTokens: _optionalInt(raw['max_output_tokens']),
      );
    });

    registry.register(_writeStdinSchema, (raw) async {
      final args = ToolArgs(raw);
      final sessionId = args.requireInt('session_id');
      final snapshot = await manager.poll(
        sessionId,
        stdinChars: raw['chars'] as String?,
        yieldMs: args.intOr('yield_time_ms', 5000),
      );
      return _snapshotResult(
        snapshot.output,
        running: snapshot.running,
        sessionId: sessionId,
        exitCode: snapshot.exitCode,
        outputTruncated: snapshot.outputTruncated,
        maxOutputTokens: _optionalInt(raw['max_output_tokens']),
      );
    });
  }

  static int? _optionalInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  static ToolResult _snapshotResult(
    String rawOutput, {
    required bool running,
    required int? sessionId,
    required int? exitCode,
    required bool outputTruncated,
    required int? maxOutputTokens,
  }) {
    final maxChars = maxOutputTokens == null || maxOutputTokens <= 0
        ? null
        : maxOutputTokens * _charsPerTokenEstimate;
    final output = maxChars == null ? rawOutput : _clamp(rawOutput, maxChars);
    final truncated = outputTruncated || output.length < rawOutput.length;
    final text = output.isEmpty
        ? (running ? '(running, no new output)' : '(command completed with no output)')
        : output;
    return ToolResult.text(
      text,
      structured: {
        'session_id': ?sessionId,
        'running': running,
        'output_truncated': truncated,
        'exit_code': ?exitCode,
      },
    );
  }

  static String _clamp(String output, int maxChars) {
    if (output.length <= maxChars) return output;
    if (maxChars < 80) return output.substring(output.length - maxChars);
    final half = maxChars ~/ 2;
    return '${output.substring(0, half)}\n... output truncated ...\n'
        '${output.substring(output.length - half)}';
  }

  static const _execCommandSchema = ToolSchema(
    name: 'exec_command',
    title: 'Execute command',
    description:
        'Run shell commands for tests, builds, git, package managers, adb, and other CLI operations. Do not use shell redirection, Get-Content/Set-Content, or similar commands to edit source/text files; use apply_patch instead. If still running after yield_time_ms, returns a session_id for write_stdin.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'cmd': {'type': 'string', 'description': 'Shell command to execute'},
        'workdir': {
          'type': 'string',
          'description': 'Working directory relative to project root',
          'default': '.',
        },
        'yield_time_ms': {
          'type': 'integer',
          'description': 'Wait this long for initial output or completion',
          'default': 10000,
        },
        'max_output_tokens': {
          'type': 'integer',
          'description': 'Approximate maximum output tokens returned to the model',
        },
      },
      'required': ['cmd'],
    },
    outputSchema: {
      'type': 'object',
      'properties': {
        'text': {'type': 'string'},
        'session_id': {'type': 'integer'},
        'running': {'type': 'boolean'},
        'output_truncated': {'type': 'boolean'},
        'exit_code': {'type': 'integer'},
      },
      'required': ['text', 'running', 'output_truncated'],
    },
    annotations: ToolAnnotations.destructive,
    meta: {'openai/toolInvocation/invoking': '正在执行命令…', 'openai/toolInvocation/invoked': '命令执行完成'},
  );

  static const _writeStdinSchema = ToolSchema(
    name: 'write_stdin',
    title: 'Continue command',
    description:
        'Poll a running exec_command session and optionally send stdin. Use \\u0003 in chars to send Ctrl+C.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'session_id': {'type': 'integer'},
        'chars': {
          'type': 'string',
          'description': 'Optional stdin characters; \\u0003 sends Ctrl+C',
        },
        'yield_time_ms': {
          'type': 'integer',
          'description': 'Wait this long for new output or completion',
          'default': 5000,
        },
        'max_output_tokens': {
          'type': 'integer',
          'description': 'Approximate maximum output tokens returned to the model',
        },
      },
      'required': ['session_id'],
    },
    outputSchema: {
      'type': 'object',
      'properties': {
        'text': {'type': 'string'},
        'session_id': {'type': 'integer'},
        'running': {'type': 'boolean'},
        'output_truncated': {'type': 'boolean'},
        'exit_code': {'type': 'integer'},
      },
      'required': ['text', 'session_id', 'running', 'output_truncated'],
    },
    annotations: ToolAnnotations.destructive,
    meta: {'openai/toolInvocation/invoking': '正在读取终端…', 'openai/toolInvocation/invoked': '终端已更新'},
  );
}
