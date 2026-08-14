import 'dart:io';

import 'package:codexter/mcp/tools/file_tools.dart';
import 'package:codexter/mcp/tools/registry.dart';
import 'package:codexter/mcp/tools/tool_context.dart';
import 'package:codexter/models/workspace.dart';
import 'package:codexter/services/capability_runtime.dart';
import 'package:codexter/services/process_session_manager.dart';
import 'package:codexter/stores/log_store.dart';
import 'package:codexter/utils/path_guard.dart';
import 'package:flutter_test/flutter_test.dart';

class _Harness {
    final Directory root;
    final ToolRegistry registry;
    final ProcessSessionManager processManager;
    final CapabilityRuntime capabilities;
    final LogStore logs;

    _Harness._({
        required this.root,
        required this.registry,
        required this.processManager,
        required this.capabilities,
        required this.logs,
    });

    static Future<_Harness> create() async {
        final root = await Directory.systemTemp.createTemp('codex_mcp_file_tools_');
        final processManager = ProcessSessionManager();
        final capabilities = CapabilityRuntime();
        final logs = LogStore();
        final workspace = Workspace(
            uuid: '11111111-1111-4111-8111-111111111111',
            name: 'file-tools-test',
            projectRoot: root.path,
            createdAt: DateTime.now(),
            lastActiveAt: DateTime.now(),
        );
        final context = ToolContext(
            workspace: workspace,
            pathGuard: PathGuard(root.path),
            processManager: processManager,
            capabilities: capabilities,
            logStore: logs,
        );
        final registry = ToolRegistry();
        FileTools.register(registry, context);
        return _Harness._(
            root: root,
            registry: registry,
            processManager: processManager,
            capabilities: capabilities,
            logs: logs,
        );
    }

    Future<void> dispose() async {
        await processManager.shutdown();
        processManager.dispose();
        await capabilities.shutdown();
        capabilities.dispose();
        logs.dispose();
        await root.delete(recursive: true);
    }
}

void main() {
    test('apply_patch composes multiple edits to the same file in order', () async {
        final harness = await _Harness.create();
        addTearDown(harness.dispose);
        final file = File('${harness.root.path}${Platform.pathSeparator}sample.txt');
        await file.writeAsString('alpha\n中文内容\nomega\n');

        final result = await harness.registry.invoke('apply_patch', {
            'purpose': 'patch test',
            'edits': [
                {'path': 'sample.txt', 'oldText': 'alpha', 'newText': 'ALPHA'},
                {'path': './sample.txt', 'oldText': 'omega', 'newText': 'OMEGA'},
            ],
        });

        expect(result.isError, isFalse);
        expect(await file.readAsString(), 'ALPHA\n中文内容\nOMEGA\n');
        expect(result.structuredContent?['files'], ['sample.txt']);
    });

    test('apply_patch validation failure leaves the original file untouched', () async {
        final harness = await _Harness.create();
        addTearDown(harness.dispose);
        final file = File('${harness.root.path}${Platform.pathSeparator}sample.txt');
        const original = 'alpha\n中文内容\nomega\n';
        await file.writeAsString(original);

        final result = await harness.registry.invoke('apply_patch', {
            'purpose': 'patch test',
            'edits': [
                {'path': 'sample.txt', 'oldText': 'alpha', 'newText': 'ALPHA'},
                {'path': 'sample.txt', 'oldText': 'missing text', 'newText': 'value'},
            ],
        });

        expect(result.isError, isTrue);
        expect(await file.readAsString(), original);
    });

    test('apply_patch rejects empty oldText instead of silently overwriting', () async {
        final harness = await _Harness.create();
        addTearDown(harness.dispose);
        final file = File('${harness.root.path}${Platform.pathSeparator}sample.txt');
        const original = '保留中文\n';
        await file.writeAsString(original);

        final result = await harness.registry.invoke('apply_patch', {
            'purpose': 'patch test',
            'edits': [
                {'path': 'sample.txt', 'oldText': '', 'newText': 'replacement'},
            ],
        });

        expect(result.isError, isTrue);
        expect(await file.readAsString(), original);
    });
}
