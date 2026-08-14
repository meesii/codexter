import 'package:codexter/mcp/tools/registry.dart';
import 'package:codexter/mcp/ui/mcp_ui_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
    test('tool schema injects required user-visible purpose', () {
        const schema = ToolSchema(
            name: 'sample',
            description: 'Sample tool',
            inputSchema: {
                'type': 'object',
                'properties': {
                    'path': {'type': 'string'},
                },
                'required': ['path'],
            },
            annotations: ToolAnnotations.readOnly,
            meta: {
                'openai/toolInvocation/invoking': '正在读取…',
                'openai/toolInvocation/invoked': '读取完成',
            },
        );

        final json = schema.toJson();
        final input = json['inputSchema'] as Map<String, dynamic>;
        final properties = input['properties'] as Map<String, dynamic>;
        final required = (input['required'] as List).cast<String>();

        expect(properties['purpose'], isA<Map>());
        expect(properties['path'], isA<Map>());
        expect(required, containsAll(['purpose', 'path']));
        expect(json['annotations'], ToolAnnotations.readOnly);
        final meta = json['_meta'] as Map;
        expect(meta['openai/toolInvocation/invoking'], '正在读取…');
        expect(meta['openai/outputTemplate'], McpUiCatalog.sharedResourceUri);
        expect((meta['ui'] as Map)['resourceUri'], McpUiCatalog.sharedResourceUri);
        expect((meta['ui'] as Map)['visibility'], ['model', 'app']);
    });

    test('registry strips purpose before invoking business handler', () async {
        final registry = ToolRegistry();
        Map<String, dynamic>? received;
        registry.register(
            const ToolSchema(
                name: 'sample',
                description: 'Sample tool',
                inputSchema: {'type': 'object', 'properties': {}},
            ),
            (args) async {
                received = args;
                return ToolResult.text('ok');
            },
        );

        final result = await registry.invoke(
            'sample',
            {'purpose': '读取配置文件', 'path': 'config.json'},
        );

        expect(received, {'path': 'config.json'});
        expect(result.meta?['codexMcpUi'], isA<Map>());
        final ui = result.meta!['codexMcpUi'] as Map;
        expect(ui['tool'], 'sample');
        expect(ui['groupLabel'], '终端');
        expect(ui['purpose'], '读取配置文件');
        expect(ui['ok'], isTrue);
    });

    test('all ordinary tools share one MCP UI resource', () {
        for (final toolName in ['read', 'grep', 'bash', 'git_status', 'goal_status', 'mcp_call']) {
            expect(McpUiCatalog.resourceUriForTool(toolName), McpUiCatalog.sharedResourceUri);
        }
        final resources = McpUiCatalog.resourceList();
        expect(resources, hasLength(1));
        expect(resources.single['uri'], McpUiCatalog.sharedResourceUri);
    });

    test('MCP UI resource is self-contained mcp-app html with widget domain', () {
        const widgetDomain = 'https://mcp.example.com';
        final resource = McpUiCatalog.readResource(
            McpUiCatalog.sharedResourceUri,
            widgetDomain: widgetDomain,
        )!;
        expect(resource['mimeType'], McpUiCatalog.mimeType);
        final meta = resource['_meta'] as Map;
        expect((meta['ui'] as Map)['domain'], widgetDomain);
        expect(meta['openai/widgetDomain'], widgetDomain);

        final html = resource['text'] as String;
        expect(html, contains('ui/initialize'));
        expect(html, contains('ui/notifications/initialized'));
        expect(html, contains('ui/notifications/tool-input'));
        expect(html, contains('ui/notifications/tool-result'));
        expect(html, isNot(contains('tools/call')));
        expect(html, isNot(contains('callTool')));
        expect(html, isNot(contains('id="rerun"')));
        expect(html, isNot(contains('function rerun()')));
        expect(html, contains('notifyIntrinsicHeight'));
        expect(html, contains('setWidgetState'));
        expect(html, contains('class="frame"'));
        expect(html, contains('html.is-mobile .frame'));
        expect(html, contains('env(safe-area-inset-left'));
        expect(html, contains('function isMobileHost()'));
        expect(html, contains('applyViewportClass'));
        expect(html, contains(r'raw.indexOf("\n")'));
        expect(html.contains('raw.indexOf("\n")'), isFalse);
    });

    test('legacy MCP UI resource versions resolve to the current template', () {
        final resource = McpUiCatalog.readResource(
            'ui://codex-mcp/file-tools-v1.html',
            widgetDomain: 'https://mcp.example.com',
        )!;
        expect(resource['uri'], 'ui://codex-mcp/file-tools-v1.html');
        expect(resource['mimeType'], McpUiCatalog.mimeType);
        expect(resource['text'], isNotEmpty);

        final sharedResource = McpUiCatalog.readResource(
            'ui://codex-mcp/tool-card-v3.html',
            widgetDomain: 'https://mcp.example.com',
        )!;
        expect(McpUiCatalog.sharedResourceUri, 'ui://codex-mcp/tool-card-v7.html');
        expect(sharedResource['uri'], 'ui://codex-mcp/tool-card-v3.html');
        expect(sharedResource['mimeType'], McpUiCatalog.mimeType);
        expect(sharedResource['text'], isNotEmpty);

        final v4Resource = McpUiCatalog.readResource(
            'ui://codex-mcp/tool-card-v4.html',
            widgetDomain: 'https://mcp.example.com',
        )!;
        expect(v4Resource['uri'], 'ui://codex-mcp/tool-card-v4.html');
        expect(v4Resource['mimeType'], McpUiCatalog.mimeType);
        expect(v4Resource['text'], isNotEmpty);

        final v5Resource = McpUiCatalog.readResource(
            'ui://codex-mcp/tool-card-v5.html',
            widgetDomain: 'https://mcp.example.com',
        )!;
        expect(v5Resource['uri'], 'ui://codex-mcp/tool-card-v5.html');
        expect(v5Resource['mimeType'], McpUiCatalog.mimeType);
        expect(v5Resource['text'], isNotEmpty);

        final v6Resource = McpUiCatalog.readResource(
            'ui://codex-mcp/tool-card-v6.html',
            widgetDomain: 'https://mcp.example.com',
        )!;
        expect(v6Resource['uri'], 'ui://codex-mcp/tool-card-v6.html');
        expect(v6Resource['mimeType'], McpUiCatalog.mimeType);
        expect(v6Resource['text'], isNotEmpty);
    });

    test('MCP UI widget domain is normalized to a HTTPS origin', () {
        final resource = McpUiCatalog.readResource(
            McpUiCatalog.sharedResourceUri,
            widgetDomain: 'https://mcp.example.com/widget/path?x=1',
        )!;
        final meta = resource['_meta'] as Map;
        expect((meta['ui'] as Map)['domain'], 'https://mcp.example.com');
        expect(meta['openai/widgetDomain'], 'https://mcp.example.com');

        final invalid = McpUiCatalog.readResource(
            McpUiCatalog.sharedResourceUri,
            widgetDomain: 'http://127.0.0.1:18920',
        )!;
        final invalidMeta = invalid['_meta'] as Map;
        expect((invalidMeta['ui'] as Map)['domain'], isNull);
        expect(invalidMeta['openai/widgetDomain'], isNull);
    });
}
