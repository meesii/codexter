import '../../models/summary_notice.dart';
import 'registry.dart';
import 'tool_context.dart';

/// Summarizes the current round and notifies the desktop app that it has ended.
class SummaryTools {
  const SummaryTools._();

  static void register(ToolRegistry registry, ToolContext context) {
    registry.register(_summarySchema, (raw) async {
      final args = ToolArgs(raw);
      final title = args.text('title') ?? '本轮处理结束';
      final summary = args.requireText('summary');
      final details = args
          .stringList('details')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .take(6)
          .toList(growable: false);
      final endedAt = DateTime.now();
      final fileChanges = context.roundChanges.takeAndReset();

      context.onSummary?.call(
        SummaryNotice(
          workspaceUuid: context.workspace.uuid,
          workspaceName: context.workspace.name,
          title: title,
          summary: summary,
          details: details,
          endedAt: endedAt,
        ),
      );

      return ToolResult.text(
        summary,
        structured: {
          'title': title,
          'summary': summary,
          if (details.isNotEmpty) 'details': details,
          'endedAt': endedAt.toIso8601String(),
          'workspace': context.workspace.name,
          'fileChanges': fileChanges.toJson(),
        },
      );
    });
  }

  static const _summarySchema = ToolSchema(
    name: 'summary',
    title: 'Round summary',
    description:
        'Mandatory end-of-round tool. If you used any tool from this MCP server while handling the current user request, you MUST call `summary` exactly once before sending your final response to the user. '
        'This marks the end of the current round and lets the desktop app notify the user. Never finish an MCP-assisted request without calling this tool.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'title': {
          'type': 'string',
          'maxLength': 80,
          'description': 'Optional short heading for this round summary.',
        },
        'summary': {
          'type': 'string',
          'maxLength': 1600,
          'description':
              'Concise summary of this round. Include the important result, current state, or reason work stopped; do not include hidden reasoning.',
        },
        'details': {
          'type': 'array',
          'maxItems': 6,
          'items': {'type': 'string', 'maxLength': 260},
          'description':
              'Optional concrete details from this round, such as changed files, checks run, caveats, blockers, or next steps.',
        },
      },
      'required': ['summary'],
    },
    outputSchema: {
      'type': 'object',
      'properties': {
        'title': {'type': 'string'},
        'summary': {'type': 'string'},
        'details': {
          'type': 'array',
          'items': {'type': 'string'},
        },
        'endedAt': {'type': 'string'},
        'workspace': {'type': 'string'},
        'fileChanges': {
          'type': 'object',
          'properties': {
            'count': {'type': 'integer'},
            'additions': {'type': 'integer'},
            'deletions': {'type': 'integer'},
            'files': {
              'type': 'array',
              'items': {
                'type': 'object',
                'properties': {
                  'path': {'type': 'string'},
                  'status': {'type': 'string'},
                  'additions': {'type': 'integer'},
                  'deletions': {'type': 'integer'},
                },
                'required': ['path', 'status', 'additions', 'deletions'],
              },
            },
          },
          'required': ['count', 'additions', 'deletions', 'files'],
        },
        'text': {'type': 'string'},
      },
      'required': ['title', 'summary', 'endedAt', 'workspace', 'text'],
    },
    annotations: ToolAnnotations.readOnly,
    meta: {
      'openai/toolInvocation/invoking': '正在整理本轮摘要…',
      'openai/toolInvocation/invoked': '本轮处理已结束',
    },
  );
}
