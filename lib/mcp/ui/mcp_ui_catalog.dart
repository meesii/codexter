import 'tool_card_html.dart';

class McpUiGroup {
    final String id;
    final String label;
    final String description;

    const McpUiGroup({
        required this.id,
        required this.label,
        required this.description,
    });

    String get legacyResourcePrefix => 'ui://codex-mcp/$id-tools';
}

/// Shared MCP Apps UI resources for ChatGPT.
///
/// Tools of the same type intentionally reuse one resource URI so ChatGPT can
/// reuse the same component template instead of fetching one HTML page per tool.
class McpUiCatalog {
    const McpUiCatalog._();

    static const mimeType = 'text/html;profile=mcp-app';
    static const sharedResourceUri = 'ui://codex-mcp/tool-card-v7.html';
    static const legacySharedResourceUris = <String>{
        'ui://codex-mcp/tool-card-v3.html',
        'ui://codex-mcp/tool-card-v4.html',
        'ui://codex-mcp/tool-card-v5.html',
        'ui://codex-mcp/tool-card-v6.html',
    };

    static const file = McpUiGroup(
        id: 'file',
        label: '文件操作',
        description: '读取、写入、编辑、补丁和目录浏览工具的紧凑执行卡片。',
    );
    static const search = McpUiGroup(
        id: 'search',
        label: '代码搜索',
        description: '文本搜索、路径匹配和代码结构探索工具的紧凑执行卡片。',
    );
    static const terminal = McpUiGroup(
        id: 'terminal',
        label: '终端',
        description: '命令执行和运行会话交互工具的紧凑执行卡片。',
    );
    static const git = McpUiGroup(
        id: 'git',
        label: 'Git',
        description: 'Git 状态、差异、历史和分支工具的紧凑执行卡片。',
    );
    static const workspace = McpUiGroup(
        id: 'workspace',
        label: '工作区',
        description: '工作区定位、上下文收集和仓库规则工具的紧凑执行卡片。',
    );
    static const goal = McpUiGroup(
        id: 'goal',
        label: '目标跟踪',
        description: '多步骤目标创建、更新、校验和完成工具的紧凑执行卡片。',
    );
    static const skill = McpUiGroup(
        id: 'skill',
        label: 'Skills',
        description: 'Skills 列表和读取工具的紧凑执行卡片。',
    );
    static const downstream = McpUiGroup(
        id: 'mcp',
        label: '下游 MCP',
        description: '下游 MCP 服务器、工具、资源和提示词调用的紧凑执行卡片。',
    );
    static const runtime = McpUiGroup(
        id: 'runtime',
        label: '运行时',
        description: '服务状态、设置、总结和网络读取工具的紧凑执行卡片。',
    );

    static const groups = <McpUiGroup>[
        file,
        search,
        terminal,
        git,
        workspace,
        goal,
        skill,
        downstream,
        runtime,
    ];

    static final String _sharedHtml = buildMcpToolCardHtml();

    static McpUiGroup groupForTool(String toolName) {
        if (const {'read', 'apply_patch', 'ls'}.contains(toolName)) return file;
        if (const {'grep', 'glob', 'code_explore'}.contains(toolName)) return search;
        if (const {'exec_command', 'write_stdin'}.contains(toolName)) return terminal;
        if (const {'skills_list', 'skill_read'}.contains(toolName)) return skill;
        if (const {'mcp_tools', 'mcp_call'}.contains(toolName)) return downstream;
        return terminal;
    }

    static String resourceUriForTool(String toolName) => sharedResourceUri;

    static Map<String, dynamic> mergeToolMeta(
        String toolName,
        Map<String, dynamic>? source,
    ) {
        final meta = <String, dynamic>{...?source};
        final rawUi = meta['ui'];
        final ui = rawUi is Map
            ? Map<String, dynamic>.from(rawUi.cast<String, dynamic>())
            : <String, dynamic>{};
        final resourceUri = resourceUriForTool(toolName);
        ui['resourceUri'] = resourceUri;
        ui['visibility'] = const ['model', 'app'];
        meta['ui'] = ui;
        meta.putIfAbsent('openai/outputTemplate', () => resourceUri);
        meta.putIfAbsent('openai/widgetAccessible', () => true);
        return meta;
    }

    static List<Map<String, dynamic>> resourceList() {
        return const [
            {
                'uri': sharedResourceUri,
                'name': 'Codexter · 工具调用',
                'description': '所有普通工具共用的紧凑执行卡片；工具与分组信息由每次调用动态提供。',
                'mimeType': mimeType,
            },
        ];
    }

    static Map<String, dynamic>? readResource(
        String uri, {
        String widgetDomain = '',
    }) {
        final legacyGroup = _legacyGroupForResourceUri(uri);
        final isLegacyShared = legacySharedResourceUris.contains(uri);
        if (uri != sharedResourceUri && !isLegacyShared && legacyGroup == null) return null;
        final domain = _normalizeWidgetDomain(widgetDomain);
        final csp = {
            'connectDomains': <String>[],
            'resourceDomains': <String>[],
        };
        final descriptionPrefix = legacyGroup?.label ?? '工具调用';
        return {
            // Preserve the exact requested URI so cached legacy descriptors remain valid.
            'uri': uri,
            'mimeType': mimeType,
            'text': _sharedHtml,
            '_meta': {
                'ui': {
                    // The component draws a border matching the Flutter desktop UI.
                    'prefersBorder': false,
                    'csp': csp,
                    ...?_domainUiMeta(domain),
                },
                ...?_domainCompatMeta(domain),
                'openai/widgetPrefersBorder': false,
                'openai/widgetCSP': {
                    'connect_domains': <String>[],
                    'resource_domains': <String>[],
                },
                'openai/widgetDescription':
                    '$descriptionPrefix工具的紧凑执行卡片；默认折叠，可展开查看参数和结果。',
            },
        };
    }

    static McpUiGroup? _legacyGroupForResourceUri(String uri) {
        for (final group in groups) {
            final prefix = group.legacyResourcePrefix;
            if (uri == '$prefix.html') return group;
            if (RegExp('^${RegExp.escape(prefix)}-v\\d+\\.html\$').hasMatch(uri)) {
                return group;
            }
        }
        return null;
    }

    static Map<String, dynamic>? _domainUiMeta(String? domain) {
        return domain == null ? null : {'domain': domain};
    }

    static Map<String, dynamic>? _domainCompatMeta(String? domain) {
        return domain == null ? null : {'openai/widgetDomain': domain};
    }

    static String? _normalizeWidgetDomain(String value) {
        final text = value.trim();
        if (text.isEmpty) return null;
        final uri = Uri.tryParse(text);
        if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
        return Uri(scheme: 'https', host: uri.host, port: uri.hasPort ? uri.port : null).toString();
    }
}
