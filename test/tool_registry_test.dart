import 'dart:io';

import 'package:codexter/mcp/tools/registry.dart';
import 'package:codexter/mcp/tools/tool_bundle.dart';
import 'package:codexter/mcp/tools/tool_context.dart';
import 'package:codexter/mcp/ui/mcp_ui_catalog.dart';
import 'package:codexter/models/summary_notice.dart';
import 'package:codexter/models/workspace.dart';
import 'package:codexter/services/capability_runtime.dart';
import 'package:codexter/services/process_session_manager.dart';
import 'package:codexter/stores/log_store.dart';
import 'package:codexter/utils/path_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
    test('ordinary tool schema does not expose UI metadata', () {
        const schema = ToolSchema(
            name: 'apply_patch',
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
                'ui': {'resourceUri': 'ui://old/template.html'},
                'openai/outputTemplate': 'ui://old/template.html',
            },
        );

        final json = schema.toJson();
        final input = json['inputSchema'] as Map<String, dynamic>;
        final properties = input['properties'] as Map<String, dynamic>;
        final required = (input['required'] as List).cast<String>();
        final meta = json['_meta'] as Map;

        expect(properties['purpose'], isA<Map>());
        expect(required, containsAll(['purpose', 'path']));
        expect(meta.containsKey('ui'), isFalse);
        expect(meta.containsKey('openai/outputTemplate'), isFalse);
    });

    test('summary is the only tool associated with a UI resource', () {
        const schema = ToolSchema(
            name: 'summary',
            description: 'Final summary',
            inputSchema: {'type': 'object', 'properties': {}},
        );
        final meta = schema.toJson()['_meta'] as Map;

        expect((meta['ui'] as Map)['resourceUri'], McpUiCatalog.summaryResourceUri);
        expect((meta['ui'] as Map)['visibility'], ['model', 'app']);
        expect(meta['openai/outputTemplate'], McpUiCatalog.summaryResourceUri);

        final resources = McpUiCatalog.resourceList();
        expect(resources, hasLength(1));
        expect(resources.single['uri'], McpUiCatalog.summaryResourceUri);
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
        expect(ui['purpose'], '读取配置文件');
        expect(ui['ok'], isTrue);
    });

    test('summary invocation emits desktop round-summary event', () async {
        final temp = await Directory.systemTemp.createTemp('codex_summary_tool_');
        final processManager = ProcessSessionManager();
        final capabilities = CapabilityRuntime();
        final logStore = LogStore();
        SummaryNotice? summaryNotice;
        final now = DateTime.now();
        final workspace = Workspace(
            uuid: '11111111-1111-4111-8111-111111111111',
            name: 'summary-test',
            projectRoot: temp.path,
            createdAt: now,
            lastActiveAt: now,
        );
        final context = ToolContext(
            workspace: workspace,
            pathGuard: PathGuard(temp.path),
            processManager: processManager,
            capabilities: capabilities,
            logStore: logStore,
            onSummary: (notice) => summaryNotice = notice,
        );
        final registry = ToolBundle.build(context);

        try {
            final result = await registry.invoke('summary', {
                'purpose': '总结本轮处理',
                'title': '本轮处理结束',
                'summary': '已经完成这一轮处理。',
                'details': ['检查通过'],
            });

            expect(result.isError, isFalse);
            expect(result.structuredContent?.containsKey('status'), isFalse);
            expect(result.structuredContent?['endedAt'], isA<String>());
            expect(summaryNotice, isNotNull);
            expect(summaryNotice!.workspaceUuid, workspace.uuid);
            expect(summaryNotice!.title, '本轮处理结束');
            expect(summaryNotice!.summary, '已经完成这一轮处理。');
            expect(summaryNotice!.details, ['检查通过']);
        } finally {
            await processManager.shutdown();
            processManager.dispose();
            await capabilities.shutdown();
            capabilities.dispose();
            logStore.dispose();
            await temp.delete(recursive: true);
        }
    });

    test('summary resource is self-contained mcp-app html with widget domain', () {
        const widgetDomain = 'https://mcp.example.com';
        final resource = McpUiCatalog.readResource(
            McpUiCatalog.summaryResourceUri,
            widgetDomain: widgetDomain,
        )!;
        expect(resource['mimeType'], McpUiCatalog.mimeType);
        final meta = resource['_meta'] as Map;
        expect((meta['ui'] as Map)['domain'], widgetDomain);

        final html = resource['text'] as String;
        expect(html, contains('ui/initialize'));
        expect(html, contains('ui/notifications/tool-input'));
        expect(html, contains('ui/notifications/tool-result'));
        expect(html, isNot(contains('本轮处理结束')));
        expect(html, isNot(contains('任务完成')));
        expect(html, isNot(contains('tools/call')));
    });

    test('old tool UI resources are no longer served', () {
        expect(McpUiCatalog.readResource('ui://codexter/tool-apply-patch-ui.html'), isNull);
        expect(McpUiCatalog.readResource('ui://codexter/tool-exec-command-ui.html'), isNull);
        expect(McpUiCatalog.readResource('ui://codexter/tool-mcp-call-ui.html'), isNull);
        expect(McpUiCatalog.readResource('ui://codex-mcp/tool-ui-card.html'), isNull);
    });

    test('summary widget domain is normalized to a HTTPS origin', () {
        final resource = McpUiCatalog.readResource(
            McpUiCatalog.summaryResourceUri,
            widgetDomain: 'https://mcp.example.com/widget/path?x=1',
        )!;
        final meta = resource['_meta'] as Map;
        expect((meta['ui'] as Map)['domain'], 'https://mcp.example.com');

        final invalid = McpUiCatalog.readResource(
            McpUiCatalog.summaryResourceUri,
            widgetDomain: 'http://127.0.0.1:18920',
        )!;
        final invalidMeta = invalid['_meta'] as Map;
        expect((invalidMeta['ui'] as Map)['domain'], isNull);
    });
}
