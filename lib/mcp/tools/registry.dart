import 'dart:async';
import '../ui/mcp_ui_catalog.dart';

class ToolSchema {
    static const purposeKey = 'purpose';
    static const purposeProperty = {
        'type': 'string',
        'maxLength': 80,
        'description':
            'Short user-visible summary of the immediate purpose of this tool call. '
            'State what this call will obtain, verify, or change; do not expose hidden reasoning.',
    };

    final String name;
    final String title;
    final String description;
    final Map<String, dynamic> inputSchema;
    final Map<String, dynamic>? outputSchema;
    final Map<String, dynamic>? annotations;
    final Map<String, dynamic>? meta;

    const ToolSchema({
        required this.name,
        required this.description,
        required this.inputSchema,
        this.title = '',
        this.outputSchema,
        this.annotations,
        this.meta,
    });

    Map<String, dynamic> toJson() {
        final renderedMeta = McpUiCatalog.mergeToolMeta(name, meta);
        return {
            'name': name,
            if (title.isNotEmpty) 'title': title,
            'description': description,
            'inputSchema': _withPurpose(inputSchema),
            if (outputSchema != null) 'outputSchema': outputSchema,
            if (annotations != null) 'annotations': annotations,
            '_meta': renderedMeta,
        };
    }

    static Map<String, dynamic> _withPurpose(Map<String, dynamic> source) {
        final schema = Map<String, dynamic>.from(source);
        schema['type'] ??= 'object';

        final rawProperties = schema['properties'];
        final properties = rawProperties is Map
            ? Map<String, dynamic>.from(rawProperties.cast<String, dynamic>())
            : <String, dynamic>{};
        properties.putIfAbsent(purposeKey, () => purposeProperty);
        schema['properties'] = properties;

        final rawRequired = schema['required'];
        final required = rawRequired is List
            ? rawRequired.map((item) => '$item').toList()
            : <String>[];
        if (!required.contains(purposeKey)) required.insert(0, purposeKey);
        schema['required'] = required;
        return schema;
    }
}

/// 工具安全标注常量，参考 MCP 规范的 tool annotations
class ToolAnnotations {
    const ToolAnnotations._();

    static const readOnly = {
        'readOnlyHint': true,
        'destructiveHint': false,
        'openWorldHint': false,
    };

    static const write = {
        'readOnlyHint': false,
        'destructiveHint': true,
        'openWorldHint': false,
    };

    static const destructive = {
        'readOnlyHint': false,
        'destructiveHint': true,
        'openWorldHint': true,
    };

    static const openWorld = {
        'readOnlyHint': true,
        'destructiveHint': false,
        'openWorldHint': true,
    };

    static const operational = {
        'readOnlyHint': false,
        'destructiveHint': false,
        'openWorldHint': true,
    };
}

class ToolResult {
    final List<Map<String, dynamic>> content;
    final Map<String, dynamic>? structuredContent;
    final Map<String, dynamic>? meta;
    final bool isError;

    ToolResult({
        required this.content,
        this.structuredContent,
        this.meta,
        this.isError = false,
    });

    factory ToolResult.text(String text, {Map<String, dynamic>? structured}) {
        final safeText = text.isEmpty ? '(empty)' : text;
        final merged = structured == null ? null : {...structured, 'text': safeText};
        return ToolResult(
            content: [
                {'type': 'text', 'text': safeText}
            ],
            structuredContent: merged,
        );
    }

    factory ToolResult.error(String message) {
        return ToolResult(
            content: [
                {'type': 'text', 'text': message}
            ],
            structuredContent: {'error': message, 'text': message},
            isError: true,
        );
    }

    ToolResult withMeta(Map<String, dynamic> patch) {
        return ToolResult(
            content: content,
            structuredContent: structuredContent,
            meta: {...?meta, ...patch},
            isError: isError,
        );
    }

    Map<String, dynamic> toMcpResult() {
        return {
            'content': content,
            if (structuredContent != null) 'structuredContent': structuredContent,
            if (meta != null) '_meta': meta,
            if (isError) 'isError': true,
        };
    }
}

typedef ToolHandler = Future<ToolResult> Function(Map<String, dynamic> args);

class ToolEntry {
    final ToolSchema schema;
    final ToolHandler handler;

    ToolEntry({required this.schema, required this.handler});
}

class ToolRegistry {
    final Map<String, ToolEntry> _tools = {};

    void register(ToolSchema schema, ToolHandler handler) {
        _tools[schema.name] = ToolEntry(schema: schema, handler: handler);
    }

    ToolEntry? getTool(String name) => _tools[name];

    Future<ToolResult> invoke(String name, Map<String, dynamic> args) async {
        final entry = _tools[name];
        if (entry == null) return ToolResult.error('Tool not found: $name');
        final executionArgs = Map<String, dynamic>.from(args)..remove(ToolSchema.purposeKey);
        final result = await entry.handler(executionArgs);
        return decorateResult(name, args, result);
    }

    ToolResult decorateResult(String name, Map<String, dynamic> args, ToolResult result) {
        final entry = _tools[name];
        if (entry == null) return result;
        final purpose = '${args[ToolSchema.purposeKey] ?? ''}'.trim();
        final group = McpUiCatalog.groupForTool(name);
        return result.withMeta({
            'codexMcpUi': {
                'tool': name,
                'title': entry.schema.title.isEmpty ? name : entry.schema.title,
                'group': group.id,
                'groupLabel': group.label,
                if (purpose.isNotEmpty) 'purpose': purpose,
                'ok': !result.isError,
                if (entry.schema.annotations != null) 'annotations': entry.schema.annotations,
            },
        });
    }

    List<String> get names => _tools.keys.toList()..sort();

    List<ToolSchema> listSchemas() {
        final schemas = _tools.values.map((entry) => entry.schema).toList();
        schemas.sort((left, right) => left.name.compareTo(right.name));
        return schemas;
    }

    bool get isEmpty => _tools.isEmpty;

    int get count => _tools.length;
}

/// 统一的入参读取，避免每个工具重复写类型转换
class ToolArgs {
    final Map<String, dynamic> raw;

    const ToolArgs(this.raw);

    String? text(String key) {
        final value = raw[key];
        if (value == null) return null;
        final str = '$value'.trim();
        return str.isEmpty ? null : str;
    }

    String requireText(String key) {
        final value = text(key);
        if (value == null) throw ToolArgError('$key is required');
        return value;
    }

    int intOr(String key, int fallback) {
        final value = raw[key];
        if (value is num) return value.toInt();
        if (value is String) return int.tryParse(value) ?? fallback;
        return fallback;
    }

    int? intOrNull(String key) {
        final value = raw[key];
        if (value is num) return value.toInt();
        if (value is String) return int.tryParse(value);
        return null;
    }

    int requireInt(String key) {
        final value = intOrNull(key);
        if (value == null) throw ToolArgError('$key is required');
        return value;
    }

    bool boolOr(String key, bool fallback) {
        final value = raw[key];
        if (value is bool) return value;
        if (value is String) return value.toLowerCase() == 'true';
        return fallback;
    }

    List<String> stringList(String key) {
        final value = raw[key];
        if (value is List) return value.map((item) => '$item').toList();
        if (value is String && value.isNotEmpty) return [value];
        return const [];
    }

    Map<String, dynamic> mapOr(String key) {
        final value = raw[key];
        if (value is Map) return value.cast<String, dynamic>();
        return const {};
    }
}

class ToolArgError implements Exception {
    final String message;

    ToolArgError(this.message);

    @override
    String toString() => message;
}
