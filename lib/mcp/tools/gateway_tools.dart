import '../../services/downstream_client.dart';
import '../../utils/fmt.dart';
import 'registry.dart';
import 'tool_context.dart';

/// 下游 MCP 网关：mcp_tools / mcp_call
class GatewayTools {
  const GatewayTools._();

  static void register(ToolRegistry registry, ToolContext context) {
    final capabilities = context.capabilities;

    DownstreamClient requireClient(String name) {
      final client = context.downstreamClientOf(name);
      if (client == null) throw ToolArgError('Unknown downstream MCP: $name');
      return client;
    }

    registry.register(_toolsSchema, (raw) async {
      final name = ToolArgs(raw).text('server');
      final targets = name == null ? context.downstreamClients : [requireClient(name)];

      if (targets.isEmpty) {
        return ToolResult.text(
          'No downstream MCP enabled. Manage them in the desktop app under MCP.',
          structured: {'servers': const [], 'tools': const <String, dynamic>{}},
        );
      }

      final buffer = StringBuffer();
      final grouped = <String, dynamic>{};
      final servers = <Map<String, dynamic>>[];
      for (final client in targets) {
        final status = client.toStatusJson();
        servers.add(status);
        buffer.writeln(
          '=== ${client.name} [${client.state.name}] ${client.tools.length} tools ===',
        );
        for (final tool in client.tools) {
          buffer.writeln('  ${tool['name']}: ${Fmt.ellipsis('${tool['description'] ?? ''}', 160)}');
        }
        grouped[client.name] = client.tools;
      }
      return ToolResult.text(buffer.toString(), structured: {'servers': servers, 'tools': grouped});
    });

    registry.register(_callSchema, (raw) async {
      final args = ToolArgs(raw);
      final server = args.requireText('server');
      var client = requireClient(server);

      // Connection management is an implementation detail. Retry one reconnect internally
      // instead of exposing mcp_reconnect to the model.
      if (!client.isConnected) {
        await capabilities.reconnect(server);
        client = requireClient(server);
      }
      if (!client.isConnected) {
        return ToolResult.error(
          'Downstream MCP $server is not connected${client.lastError == null ? '' : ': ${client.lastError}'}',
        );
      }

      final toolName = args.requireText('tool');
      final result = await client.callTool(toolName, args.mapOr('arguments'));
      return ToolResult.text(_renderContent(result), structured: result);
    });
  }

  /// 下游返回的 content 数组里抽出可读文本，抽不到就回落到 JSON。
  static String _renderContent(Map<String, dynamic> result) {
    final contents = result['content'] ?? result['contents'];
    if (contents is! List) return Fmt.json(result);

    final buffer = StringBuffer();
    for (final item in contents) {
      if (item is! Map) continue;
      final text = item['text'];
      if (text is String) {
        buffer.writeln(text);
        continue;
      }
      buffer.writeln(Fmt.json(item));
    }
    final rendered = buffer.toString().trim();
    return rendered.isEmpty ? Fmt.json(result) : rendered;
  }

  static const _serverProperty = {'type': 'string', 'description': 'Downstream MCP name'};

  static const _toolsSchema = ToolSchema(
    name: 'mcp_tools',
    title: 'Discover downstream MCP tools',
    description:
        'List enabled downstream MCP servers and their available tools. Pass server to inspect one server in detail.',
    inputSchema: {
      'type': 'object',
      'properties': {'server': _serverProperty},
    },
    outputSchema: {
      'type': 'object',
      'properties': {
        'text': {'type': 'string', 'description': 'Formatted server and tool list'},
        'servers': {'type': 'array'},
        'tools': {'type': 'object'},
      },
      'required': ['text', 'servers', 'tools'],
    },
    annotations: ToolAnnotations.openWorld,
    meta: {
      'openai/toolInvocation/invoking': '正在发现 MCP 工具…',
      'openai/toolInvocation/invoked': 'MCP 工具已加载',
    },
  );

  static const _callSchema = ToolSchema(
    name: 'mcp_call',
    title: 'Call downstream MCP tool',
    description:
        'Call one tool exposed by a downstream MCP server. Only arguments is forwarded to the downstream tool.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'server': _serverProperty,
        'tool': {'type': 'string', 'description': 'Downstream tool name'},
        'arguments': {'type': 'object', 'description': 'Arguments for the downstream tool only'},
      },
      'required': ['server', 'tool'],
    },
    outputSchema: {
      'type': 'object',
      'properties': {
        'text': {'type': 'string', 'description': 'Rendered downstream tool result'},
      },
      'required': ['text'],
    },
    annotations: ToolAnnotations.openWorld,
    meta: {
      'openai/toolInvocation/invoking': '正在调用 MCP 工具…',
      'openai/toolInvocation/invoked': 'MCP 工具调用完成',
    },
  );
}
