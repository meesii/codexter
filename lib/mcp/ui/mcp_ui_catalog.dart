import 'task_summary_html.dart';

class McpUiGroup {
  final String id;
  final String label;
  final String description;

  const McpUiGroup({required this.id, required this.label, required this.description});
}

/// MCP Apps UI resources for ChatGPT.
///
/// Only the summary tool exposes a round-summary UI resource.
class McpUiCatalog {
  const McpUiCatalog._();

  static const mimeType = 'text/html;profile=mcp-app';
  static const summaryToolName = 'summary';
  static const summaryResourceUri = 'ui://codexter/round-summary-ui.html';

  static const file = McpUiGroup(id: 'file', label: '文件操作', description: '读取、写入、编辑、补丁和目录浏览工具。');
  static const search = McpUiGroup(id: 'search', label: '代码搜索', description: '文本搜索、路径匹配和代码结构探索工具。');
  static const terminal = McpUiGroup(id: 'terminal', label: '终端', description: '命令执行和运行会话交互工具。');
  static const git = McpUiGroup(id: 'git', label: 'Git', description: 'Git 状态、差异、历史和分支工具。');
  static const workspace = McpUiGroup(
    id: 'workspace',
    label: '工作区',
    description: '工作区定位、上下文收集和仓库规则工具。',
  );
  static const goal = McpUiGroup(id: 'goal', label: '目标跟踪', description: '多步骤目标创建、更新、校验和完成工具。');
  static const skill = McpUiGroup(id: 'skill', label: 'Skills', description: 'Skills 列表和读取工具。');
  static const downstream = McpUiGroup(id: 'mcp', label: '下游 MCP', description: '下游 MCP 服务器和工具调用。');
  static const summary = McpUiGroup(id: 'summary', label: '本轮摘要', description: '当前一轮处理的摘要。');

  static final String _summaryHtml = buildRoundSummaryHtml();

  static McpUiGroup groupForTool(String toolName) {
    if (toolName == summaryToolName) return summary;
    if (const {'read', 'read_image', 'apply_patch', 'ls'}.contains(toolName)) return file;
    if (const {'grep', 'glob', 'code_explore'}.contains(toolName)) return search;
    if (const {'exec_command', 'write_stdin'}.contains(toolName)) return terminal;
    if (const {'skills_list', 'skill_read'}.contains(toolName)) return skill;
    if (const {'mcp_tools', 'mcp_call'}.contains(toolName)) return downstream;
    return terminal;
  }

  static Map<String, dynamic> mergeToolMeta(String toolName, Map<String, dynamic>? source) {
    final meta = <String, dynamic>{...?source};
    if (toolName != summaryToolName) {
      meta.remove('ui');
      meta.remove('openai/outputTemplate');
      meta.remove('openai/widgetAccessible');
      return meta;
    }

    final rawUi = meta['ui'];
    final ui = rawUi is Map
        ? Map<String, dynamic>.from(rawUi.cast<String, dynamic>())
        : <String, dynamic>{};
    ui['resourceUri'] = summaryResourceUri;
    ui['visibility'] = const ['model', 'app'];
    meta['ui'] = ui;
    meta['openai/outputTemplate'] = summaryResourceUri;
    return meta;
  }

  static List<Map<String, dynamic>> resourceList() {
    return const [
      {
        'uri': summaryResourceUri,
        'name': 'Round summary',
        'description': '当前一轮处理结束时展示的摘要卡片。',
        'mimeType': mimeType,
      },
    ];
  }

  static Map<String, dynamic>? readResource(String uri, {String widgetDomain = ''}) {
    if (uri != summaryResourceUri) return null;
    final domain = _normalizeWidgetDomain(widgetDomain);
    return {
      'uri': summaryResourceUri,
      'mimeType': mimeType,
      'text': _summaryHtml,
      '_meta': {
        'ui': {
          'prefersBorder': false,
          'csp': {'connectDomains': <String>[], 'resourceDomains': <String>[]},
          ...?_domainUiMeta(domain),
        },
      },
    };
  }

  static Map<String, dynamic>? _domainUiMeta(String? domain) {
    return domain == null ? null : {'domain': domain};
  }

  static String? _normalizeWidgetDomain(String value) {
    final text = value.trim();
    if (text.isEmpty) return null;
    final uri = Uri.tryParse(text);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    return Uri(scheme: 'https', host: uri.host, port: uri.hasPort ? uri.port : null).toString();
  }
}
