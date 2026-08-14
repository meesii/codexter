import 'package:codexter/models/mcp_log_entry.dart';
import 'package:codexter/stores/log_store.dart';
import 'package:flutter_test/flutter_test.dart';

McpLogEntry _entry({
  required String id,
  String method = 'tools/call',
  String? toolName = 'read',
  String? purpose,
}) {
  final arguments = <String, dynamic>{};
  if (purpose != null) arguments['purpose'] = purpose;

  final params = <String, dynamic>{};
  if (toolName != null) {
    params['name'] = toolName;
    params['arguments'] = arguments;
  }

  return McpLogEntry(
    id: id,
    workspaceUuid: 'workspace-1',
    timestamp: DateTime(2026, 8, 13),
    method: method,
    toolName: toolName,
    request: {'params': params},
  );
}

void main() {
  test('latestToolPurposeOf follows the latest tool call', () {
    final store = LogStore();
    addTearDown(store.dispose);

    store.add(_entry(id: '1', purpose: '读取配置'));
    store.add(_entry(id: '2', method: 'resources/read', toolName: null));
    expect(store.latestToolPurposeOf('workspace-1'), '读取配置');

    store.add(_entry(id: '3', purpose: '更新侧栏'));
    expect(store.latestToolPurposeOf('workspace-1'), '更新侧栏');
  });

  test('latest tool call without purpose uses fallback', () {
    final store = LogStore();
    addTearDown(store.dispose);

    store.add(_entry(id: '1', purpose: '旧任务'));
    store.add(_entry(id: '2'));

    expect(store.latestToolPurposeOf('workspace-1'), isNull);
  });

  test('clearEntries removes logs but keeps workspace stats', () {
    final store = LogStore();
    addTearDown(store.dispose);

    store.add(_entry(id: '1', purpose: '读取配置'));
    expect(store.statsOf('workspace-1').toolCalls, 1);

    store.clearEntries('workspace-1');

    expect(store.entriesOf('workspace-1'), isEmpty);
    expect(store.latestToolPurposeOf('workspace-1'), isNull);
    expect(store.statsOf('workspace-1').toolCalls, 1);
  });
}
