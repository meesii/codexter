import 'dart:convert';
import 'dart:io';

import 'package:codexter/mcp/multi_workspace_server.dart';
import 'package:codexter/mcp/ui/mcp_ui_catalog.dart';
import 'package:codexter/models/workspace.dart';
import 'package:codexter/services/capability_runtime.dart';
import 'package:codexter/stores/log_store.dart';
import 'package:flutter_test/flutter_test.dart';

class _HttpResult {
    final int status;
    final String? sessionId;
    final Map<String, dynamic> body;

    const _HttpResult(this.status, this.sessionId, this.body);
}

Future<_HttpResult> _postJson(
    HttpClient client,
    Uri uri,
    Map<String, dynamic> payload,
) async {
    final request = await client.postUrl(uri);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(payload));
    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    return _HttpResult(
        response.statusCode,
        response.headers.value('mcp-session-id'),
        jsonDecode(text) as Map<String, dynamic>,
    );
}

void main() {
    test('MCP HTTP transport stays stateless across concurrent clients', () async {
        final temp = await Directory.systemTemp.createTemp('codex_mcp_transport_');
        final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final port = probe.port;
        await probe.close();

        final server = MultiWorkspaceServer();
        final logs = LogStore();
        final capabilities = CapabilityRuntime();
        final now = DateTime.now();
        final workspace = Workspace(
            uuid: '11111111-1111-4111-8111-111111111111',
            name: 'transport-test',
            projectRoot: temp.path,
            createdAt: now,
            lastActiveAt: now,
        );

        await server.start(host: '127.0.0.1', port: port);
        server.addWorkspace(
            workspace: workspace,
            logStore: logs,
            capabilities: capabilities,
        );

        final client = HttpClient();
        final uri = Uri.parse('http://127.0.0.1:$port/${workspace.uuid}/mcp');

        try {
            final initializeResults = await Future.wait(List.generate(12, (index) {
                return _postJson(client, uri, {
                    'jsonrpc': '2.0',
                    'id': index + 1,
                    'method': 'initialize',
                    'params': {
                        'protocolVersion': '2025-11-25',
                        'capabilities': <String, dynamic>{},
                        'clientInfo': {'name': 'client-$index', 'version': '1.0'},
                    },
                });
            }));

            for (final result in initializeResults) {
                expect(result.status, HttpStatus.ok);
                expect(result.sessionId, isNull);
            }

            final readResults = await Future.wait(List.generate(24, (index) {
                return _postJson(client, uri, {
                    'jsonrpc': '2.0',
                    'id': 100 + index,
                    'method': 'resources/read',
                    'params': {'uri': McpUiCatalog.sharedResourceUri},
                });
            }));

            for (final result in readResults) {
                expect(result.status, HttpStatus.ok);
                expect(result.sessionId, isNull);
                final rpcResult = result.body['result'] as Map<String, dynamic>;
                final contents = rpcResult['contents'] as List;
                final resource = contents.single as Map<String, dynamic>;
                expect(resource['uri'], McpUiCatalog.sharedResourceUri);
                expect(resource['mimeType'], McpUiCatalog.mimeType);
                expect((resource['text'] as String).length, greaterThan(10000));
            }
        } finally {
            client.close(force: true);
            await server.stop();
            await capabilities.shutdown();
            capabilities.dispose();
            logs.dispose();
            await temp.delete(recursive: true);
        }
    });
}
