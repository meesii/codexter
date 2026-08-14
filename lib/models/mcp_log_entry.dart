import '../utils/fmt.dart';

enum McpLogKind { request, tunnel, server, workspace }

class McpLogEntry {
    final String id;
    final String workspaceUuid;
    final DateTime timestamp;
    final String method;
    final String? toolName;
    final McpLogKind kind;
    final Map<String, dynamic>? request;
    Map<String, dynamic>? response;
    int durationMs;
    bool pending;
    bool success;
    String? error;

    McpLogEntry({
        required this.id,
        required this.workspaceUuid,
        required this.timestamp,
        required this.method,
        this.toolName,
        this.kind = McpLogKind.request,
        this.request,
        this.response,
        this.durationMs = 0,
        this.pending = true,
        this.success = true,
        this.error,
    });

    String get title => toolName ?? method;

    bool get isToolCall => toolName != null;

    Map<String, dynamic>? get arguments {
        final params = request?['params'];
        if (params is! Map) return null;
        final args = params['arguments'];
        if (args is Map<String, dynamic>) return args;
        return null;
    }

    String? get purpose {
        final value = arguments?['purpose'];
        if (value == null) return null;
        final text = '$value'.trim();
        return text.isEmpty ? null : text;
    }

    Map<String, dynamic>? get executionArguments {
        final args = arguments;
        if (args == null) return null;
        return Map<String, dynamic>.from(args)..remove('purpose');
    }

    String get argsSummary => Fmt.toolArgs(executionArguments);

    /// 日志详情中的请求负载。工具调用只保留真正参与执行的字段，
    /// 隐藏 JSON-RPC id/version、客户端 _meta 等协议噪音。
    Map<String, dynamic>? get displayRequest {
        if (!isToolCall) return request;
        return {
            'name': toolName ?? request?['params']?['name'],
            if (purpose != null) 'purpose': purpose,
            'arguments': executionArguments ?? const <String, dynamic>{},
        };
    }

    /// 日志详情中的响应负载。工具调用优先展示 structuredContent，
    /// 去掉 JSON-RPC 外壳以及 content/structuredContent 的重复文本。
    Map<String, dynamic>? get displayResponse {
        final raw = response;
        if (!isToolCall || raw == null) return raw;

        final rpcError = raw['error'];
        if (rpcError is Map) {
            return {'error': Map<String, dynamic>.from(rpcError)};
        }
        if (rpcError != null) return {'error': rpcError};

        final result = raw['result'];
        if (result is! Map) return raw;

        final structured = result['structuredContent'];
        if (structured is Map) return Map<String, dynamic>.from(structured);

        final content = result['content'];
        final isError = result['isError'] == true;
        if (content is List && content.length == 1 && content.first is Map) {
            final item = content.first as Map;
            if (item['type'] == 'text' && item['text'] != null) {
                return {
                    'text': item['text'],
                    if (isError) 'isError': true,
                };
            }
        }

        return Map<String, dynamic>.from(result);
    }

    String get clockText => Fmt.clock(timestamp);

    String get durationText => pending ? '' : Fmt.duration(durationMs);

    void complete({
        required Map<String, dynamic> response,
        required int durationMs,
        required bool success,
        String? error,
    }) {
        this.response = response;
        this.durationMs = durationMs;
        this.success = success;
        this.error = error;
        pending = false;
    }
}

class WorkspaceLogStats {
    int toolCalls = 0;
    int errors = 0;
    DateTime? lastActiveAt;

    void record(McpLogEntry entry) {
        if (entry.isToolCall) toolCalls++;
        lastActiveAt = entry.timestamp;
    }

    void recordFailure() {
        errors++;
    }
}
