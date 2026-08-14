import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:uuid/uuid.dart';
import '../app_info.dart';
import '../models/mcp_log_entry.dart';
import '../models/summary_notice.dart';
import '../models/workspace.dart';
import '../services/capability_runtime.dart';
import '../services/process_session_manager.dart';
import '../stores/log_store.dart';
import '../utils/fmt.dart';
import '../utils/path_guard.dart';
import 'instructions.dart';
import 'json_rpc.dart';
import 'tools/registry.dart';
import 'tools/tool_bundle.dart';
import 'tools/tool_context.dart';
import 'ui/mcp_ui_catalog.dart';

const mcpServerName = appId;
const mcpServerVersion = '1.0.0';
const mcpProtocolVersion = '2025-06-18';
const mcpProtocolVersion2026 = '2026-07-28';

/// 本服务端同时支持的协议版本：
/// - 2026-07-28：stateless + server/discover
/// - 2025-11-25：legacy initialize 握手（ChatGPT openai-mcp 实际使用的版本）
/// - 2025-06-18：legacy initialize 握手（早期版本，向后兼容）
const supportedProtocolVersions = [
  mcpProtocolVersion2026,
  '2025-11-25',
  mcpProtocolVersion,
];

/// 一个工作区的 MCP 端点：解析 JSON-RPC、分发工具、记录日志
class WorkspaceHandler {
  final Workspace workspace;
  final ToolRegistry tools;
  final ToolContext context;
  final LogStore logStore;
  String widgetDomain;

  WorkspaceHandler._({
    required this.workspace,
    required this.tools,
    required this.context,
    required this.logStore,
    required this.widgetDomain,
  });

  factory WorkspaceHandler.create({
    required Workspace workspace,
    required LogStore logStore,
    required CapabilityRuntime capabilities,
    required String widgetDomain,
    SummaryHandler? onSummary,
  }) {
    final context = ToolContext(
      workspace: workspace,
      pathGuard: PathGuard(workspace.projectRoot),
      processManager: ProcessSessionManager(),
      capabilities: capabilities,
      logStore: logStore,
      onSummary: onSummary,
    );
    return WorkspaceHandler._(
      workspace: workspace,
      tools: ToolBundle.build(context),
      context: context,
      logStore: logStore,
      widgetDomain: widgetDomain,
    );
  }

  ProcessSessionManager get processManager => context.processManager;

  Future<void> handle(HttpRequest request) async {
    _applyCommonHeaders(request.response);

    switch (request.method) {
      case 'POST':
        await _handlePost(request);
        return;
      case 'OPTIONS':
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
        return;
      case 'DELETE':
        request.response.statusCode = HttpStatus.methodNotAllowed;
        request.response.headers.set(HttpHeaders.allowHeader, 'POST, OPTIONS');
        await request.response.close();
        return;
      case 'GET':
        request.response.statusCode = HttpStatus.methodNotAllowed;
        request.response.headers.set(
          HttpHeaders.allowHeader,
          'POST, DELETE, OPTIONS',
        );
        await request.response.close();
        return;
      default:
        request.response.statusCode = HttpStatus.methodNotAllowed;
        request.response.headers.set(
          HttpHeaders.allowHeader,
          'POST, DELETE, OPTIONS',
        );
        await _writeJson(request.response, {
          'error': 'Only JSON-RPC over POST is supported',
        });
    }
  }

  Future<void> _handlePost(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();

    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      request.response.statusCode = HttpStatus.badRequest;
      await _writeJson(
        request.response,
        JsonRpcResponse.failure(null, JsonRpcError.parseError).toJson(),
      );
      return;
    }

    final batch = decoded is List ? decoded : [decoded];
    final responses = <Map<String, dynamic>>[];

    for (final message in batch) {
      final parsed = JsonRpcRequest.tryParse(message);
      if (parsed == null) {
        responses.add(
          JsonRpcResponse.failure(null, JsonRpcError.invalidRequest).toJson(),
        );
        continue;
      }
      final response = await _process(parsed, message);
      if (response != null) responses.add(response);
    }

    if (responses.isEmpty) {
      request.response.statusCode = HttpStatus.accepted;
      await request.response.close();
      return;
    }

    final responseBody = decoded is List ? responses : responses.first;
    await _writeBody(request.response, responseBody);
  }

  Future<Map<String, dynamic>?> _process(
    JsonRpcRequest rpcRequest,
    Object? rawMessage,
  ) async {
    final entry = _startLog(rpcRequest, rawMessage);
    final stopwatch = Stopwatch()..start();

    JsonRpcResponse response;
    try {
      response = await _dispatch(rpcRequest);
    } on ToolArgError catch (error) {
      response = JsonRpcResponse.failure(
        rpcRequest.id,
        JsonRpcError.params(error.message),
      );
    } catch (error) {
      response = JsonRpcResponse.failure(
        rpcRequest.id,
        JsonRpcError.internal(error),
      );
    }
    stopwatch.stop();

    final json = response.toJson();
    logStore.completeEntry(
      entry,
      response: json,
      durationMs: stopwatch.elapsedMilliseconds,
      success: _isSuccessful(response),
      error: _errorTextOf(response),
    );

    if (rpcRequest.isNotification) return null;
    return json;
  }

  Future<JsonRpcResponse> _dispatch(JsonRpcRequest rpcRequest) async {
    switch (rpcRequest.method) {
      case 'server/discover':
        return JsonRpcResponse.success(rpcRequest.id, _discoverResult());
      case 'initialize':
        return JsonRpcResponse.success(
          rpcRequest.id,
          _initializeResult(rpcRequest),
        );
      case 'ping':
        return JsonRpcResponse.success(rpcRequest.id, const {});
      case 'notifications/initialized':
      case 'notifications/cancelled':
        return JsonRpcResponse.success(rpcRequest.id, const {});
      case 'tools/list':
        return JsonRpcResponse.success(rpcRequest.id, {
          'tools': tools
              .listSchemas()
              .map((schema) => schema.toJson())
              .toList(),
          'ttlMs': 300000,
          'cacheScope': 'public',
        });
      case 'tools/call':
        return _callTool(rpcRequest);
      case 'resources/list':
        return JsonRpcResponse.success(rpcRequest.id, {
          'resources': _resourceList(),
          'ttlMs': 300000,
          'cacheScope': 'public',
        });
      case 'resources/read':
        return _readResource(rpcRequest);
      case 'prompts/list':
        return JsonRpcResponse.success(rpcRequest.id, const {
          'prompts': [],
          'ttlMs': 300000,
          'cacheScope': 'public',
        });
      default:
        return JsonRpcResponse.failure(
          rpcRequest.id,
          JsonRpcError.methodNotFound,
        );
    }
  }

  /// MCP 2026-07-28 stateless 协议下的发现响应：一次性返回服务端支持的版本、能力与身份
  Map<String, dynamic> _discoverResult() {
    return {
      'resultType': 'complete',
      'supportedVersions': supportedProtocolVersions,
      'capabilities': {'tools': {}, 'resources': {}},
      '_meta': {
        'io.modelcontextprotocol/serverInfo': {
          'name': mcpServerName,
          'version': mcpServerVersion,
        },
      },
      'instructions': ServerInstructions.build(
        projectRoot: workspace.projectRoot,
        skills: context.enabledSkills,
        downstream: context.downstreamClients,
        toolCount: tools.count,
        agentsMode: workspace.agentsMode,
        customAgents: workspace.customAgents,
      ),
    };
  }

  Map<String, dynamic> _initializeResult(JsonRpcRequest rpcRequest) {
    final requestedVersion = rpcRequest.params?['protocolVersion'] as String?;
    final negotiatedVersion =
        supportedProtocolVersions.contains(requestedVersion)
        ? requestedVersion!
        : mcpProtocolVersion;
    return {
      'protocolVersion': negotiatedVersion,
      'capabilities': {
        'tools': {'listChanged': false},
        'resources': {'listChanged': false, 'subscribe': false},
      },
      'serverInfo': {
        'name': mcpServerName,
        'version': mcpServerVersion,
        'title': workspace.name,
      },
      'instructions': ServerInstructions.build(
        projectRoot: workspace.projectRoot,
        skills: context.enabledSkills,
        downstream: context.downstreamClients,
        toolCount: tools.count,
        agentsMode: workspace.agentsMode,
        customAgents: workspace.customAgents,
      ),
    };
  }

  Future<JsonRpcResponse> _callTool(JsonRpcRequest rpcRequest) async {
    final toolName = rpcRequest.toolName;
    if (toolName == null) {
      return JsonRpcResponse.failure(
        rpcRequest.id,
        JsonRpcError.params('name is required'),
      );
    }

    final tool = tools.getTool(toolName);
    if (tool == null) {
      return JsonRpcResponse.success(
        rpcRequest.id,
        ToolResult.error('Unknown tool: $toolName').toMcpResult(),
      );
    }

    try {
      final result = await tools.invoke(toolName, rpcRequest.arguments);
      return JsonRpcResponse.success(rpcRequest.id, result.toMcpResult());
    } on ToolArgError catch (error) {
      final result = tools.decorateResult(
        toolName,
        rpcRequest.arguments,
        ToolResult.error('$toolName: ${error.message}'),
      );
      return JsonRpcResponse.success(rpcRequest.id, result.toMcpResult());
    } on PathEscapeError catch (error) {
      final result = tools.decorateResult(
        toolName,
        rpcRequest.arguments,
        ToolResult.error('$error'),
      );
      return JsonRpcResponse.success(rpcRequest.id, result.toMcpResult());
    } catch (error) {
      final result = tools.decorateResult(
        toolName,
        rpcRequest.arguments,
        ToolResult.error('$toolName failed: $error'),
      );
      return JsonRpcResponse.success(rpcRequest.id, result.toMcpResult());
    }
  }

  List<Map<String, dynamic>> _resourceList() {
    return [
      {
        'uri': _workspaceCardUri,
        'name': '${workspace.name} overview',
        'description':
            'Workspace card: paths, tools, processes and recent activity.',
        'mimeType': 'text/markdown',
      },
      ...McpUiCatalog.resourceList(),
    ];
  }

  JsonRpcResponse _readResource(JsonRpcRequest rpcRequest) {
    final uri = rpcRequest.params?['uri'] as String?;
    if (uri != null) {
      final uiResource = McpUiCatalog.readResource(
        uri,
        widgetDomain: widgetDomain,
      );
      if (uiResource != null) {
        return JsonRpcResponse.success(rpcRequest.id, {
          'contents': [uiResource],
          'ttlMs': 300000,
          'cacheScope': 'public',
        });
      }
    }
    if (uri != _workspaceCardUri) {
      return JsonRpcResponse.failure(
        rpcRequest.id,
        JsonRpcError.params('Unknown resource: $uri'),
      );
    }
    return JsonRpcResponse.success(rpcRequest.id, {
      'contents': [
        {
          'uri': _workspaceCardUri,
          'mimeType': 'text/markdown',
          'text': _renderWorkspaceCard(),
        },
      ],
      'ttlMs': 0,
      'cacheScope': 'private',
    });
  }

  String get _workspaceCardUri => 'ui://workspace/${workspace.uuid}';

  String _renderWorkspaceCard() {
    final stats = logStore.statsOf(workspace.uuid);
    final processes = processManager.list();
    final recent = logStore.recentOf(workspace.uuid, 5);

    final buffer = StringBuffer()
      ..writeln('# ${workspace.name}')
      ..writeln()
      ..writeln('- project_root: `${workspace.projectRoot}`')
      ..writeln('- tools: ${tools.count}')
      ..writeln('- tool calls: ${stats.toolCalls} (errors ${stats.errors})')
      ..writeln(
        '- processes: ${processes.where((info) => info.running).length} running',
      );

    if (recent.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## Recent activity');
      for (final item in recent) {
        buffer.writeln(
          '- ${item.clockText} ${item.title} ${item.durationText}',
        );
      }
    }
    return buffer.toString();
  }

  McpLogEntry _startLog(JsonRpcRequest rpcRequest, Object? rawMessage) {
    final entry = McpLogEntry(
      id: const Uuid().v4(),
      workspaceUuid: workspace.uuid,
      timestamp: DateTime.now(),
      method: rpcRequest.method,
      toolName: rpcRequest.method == 'tools/call' ? rpcRequest.toolName : null,
      request: rawMessage is Map ? rawMessage.cast<String, dynamic>() : null,
    );
    logStore.add(entry);
    return entry;
  }

  bool _isSuccessful(JsonRpcResponse response) {
    if (!response.isSuccess) return false;
    return response.result?['isError'] != true;
  }

  String? _errorTextOf(JsonRpcResponse response) {
    if (response.error != null) return response.error!.message;
    if (response.result?['isError'] != true) return null;
    final content = response.result?['content'];
    if (content is List && content.isNotEmpty && content.first is Map) {
      return Fmt.ellipsis('${(content.first as Map)['text']}', 200);
    }
    return 'tool error';
  }

  void _applyCommonHeaders(HttpResponse response) {
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set(
      'Access-Control-Allow-Headers',
      'content-type, mcp-session-id, accept',
    );
    response.headers.set(
      'Access-Control-Allow-Methods',
      'POST, DELETE, OPTIONS',
    );
  }

  Future<void> _writeJson(HttpResponse response, Map<String, dynamic> payload) {
    return _writeBody(response, payload);
  }

  Future<void> _writeBody(HttpResponse response, Object payload) async {
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(payload));
    await response.close();
  }

  Future<void> close() async {
    await processManager.shutdown();
    processManager.dispose();
  }
}
