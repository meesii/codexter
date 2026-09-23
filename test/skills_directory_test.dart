import 'dart:io';

import 'package:codexter/mcp/tools/tool_context.dart';
import 'package:codexter/models/skill_entry.dart';
import 'package:codexter/models/workspace.dart';
import 'package:codexter/services/capability_manager.dart';
import 'package:codexter/services/capability_runtime.dart';
import 'package:codexter/services/process_session_manager.dart';
import 'package:codexter/stores/log_store.dart';
import 'package:codexter/utils/path_guard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('Skills 目录数据源', () {
    late Directory root;
    late Directory home;
    late CapabilityManager manager;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('codexter-skills-');
      home = await Directory.systemTemp.createTemp('codexter-home-');
      manager = CapabilityManager(
        skillsDirectoryProvider: () async => root.path,
        homeDirectory: home.path,
      );
    });

    tearDown(() async {
      await root.delete(recursive: true);
      await home.delete(recursive: true);
    });

    test('只从指定 skills 目录读取包含 SKILL.md 的子目录', () async {
      final skillDir = await Directory(p.join(root.path, 'demo-skill')).create();
      await File(p.join(skillDir.path, 'SKILL.md')).writeAsString('''---
name: demo
 description: ignored
---
# Demo
''');
      await Directory(p.join(root.path, 'no-skill')).create();
      await Directory(p.join(root.path, '.hidden')).create();
      await File(p.join(root.path, '.hidden', 'SKILL.md')).writeAsString('# hidden');

      final skills = await manager.scanLocalSkills();

      expect(skills, hasLength(1));
      expect(skills.single.name, 'demo');
      expect(skills.single.rootPath, skillDir.path);
    });

    test('目录新增和删除会直接反映到下一次扫描结果', () async {
      expect(await manager.scanLocalSkills(), isEmpty);

      final skillDir = await Directory(p.join(root.path, 'copy-in')).create();
      await File(p.join(skillDir.path, 'SKILL.md')).writeAsString('# copied');
      expect((await manager.scanLocalSkills()).map((item) => item.name), ['copy-in']);

      await skillDir.delete(recursive: true);
      expect(await manager.scanLocalSkills(), isEmpty);
    });

    test('可以删除指定本地 Skill 的整个目录', () async {
      final skillDir = await Directory(p.join(root.path, 'delete-me')).create();
      await File(p.join(skillDir.path, 'SKILL.md')).writeAsString('# delete');
      await Directory(p.join(skillDir.path, 'references')).create();
      await File(p.join(skillDir.path, 'references', 'note.txt')).writeAsString('nested');

      await manager.deleteLocalSkill(skillDir.path);

      expect(await skillDir.exists(), isFalse);
      expect(await manager.scanLocalSkills(), isEmpty);
    });

    test('拒绝删除 Codexter skills 目录之外的路径', () async {
      final outside = await Directory(p.join(home.path, 'outside-skill')).create();
      await File(p.join(outside.path, 'SKILL.md')).writeAsString('# outside');

      await expectLater(manager.deleteLocalSkill(outside.path), throwsStateError);
      expect(await outside.exists(), isTrue);
    });

    test('Cursor Skills 导入会复制到 Codexter skills 目录并跳过重复项', () async {
      final source = await Directory(
        p.join(home.path, '.cursor', 'skills', 'cursor-demo'),
      ).create(recursive: true);
      await File(p.join(source.path, 'SKILL.md')).writeAsString('''---
name: cursor-demo
---
# Cursor Demo
''');
      await Directory(p.join(source.path, 'references')).create();
      await File(p.join(source.path, 'references', 'note.txt')).writeAsString('copied');

      final first = await manager.importCursorSkills();
      expect(first.scanned, 1);
      expect(first.imported, 1);
      expect(first.skipped, 0);
      expect(File(p.join(root.path, 'cursor-demo', 'SKILL.md')).existsSync(), isTrue);
      expect(
        await File(p.join(root.path, 'cursor-demo', 'references', 'note.txt')).readAsString(),
        'copied',
      );

      final second = await manager.importCursorSkills();
      expect(second.imported, 0);
      expect(second.skipped, 1);
    });

    test('Codex Skills 导入从用户 Codex skills 目录复制到本地目录', () async {
      final source = await Directory(
        p.join(home.path, '.codex', 'skills', 'codex-demo'),
      ).create(recursive: true);
      await File(p.join(source.path, 'SKILL.md')).writeAsString('# Codex Demo');

      final result = await manager.importCodexSkills();
      expect(result.scanned, 1);
      expect(result.imported, 1);
      expect((await manager.scanLocalSkills()).single.name, 'codex-demo');
    });

    test('Cursor mcp.json 同时解析 STDIO、环境变量和 HTTP MCP', () async {
      final config = File(p.join(home.path, '.cursor', 'mcp.json'));
      await config.parent.create(recursive: true);
      await config.writeAsString(r'''{
  "mcpServers": {
    "stdio-demo": {
      "command": "demo.exe",
      "args": ["--stdio"],
      "env": {"TOKEN": "abc"}
    },
    "http-demo": {
      "type": "http",
      "url": "http://127.0.0.1:13000/mcp"
    }
  }
}''');

      final mcps = await manager.scanCursorMcps();
      expect(mcps.map((item) => item.name), ['http-demo', 'stdio-demo']);
      final stdio = mcps.singleWhere((item) => item.name == 'stdio-demo');
      expect(stdio.transport['command'], 'demo.exe');
      expect(stdio.transport['args'], ['--stdio']);
      expect(stdio.transport['env'], {'TOKEN': 'abc'});
      final http = mcps.singleWhere((item) => item.name == 'http-demo');
      expect(http.transport['url'], 'http://127.0.0.1:13000/mcp');
    });

    test('全局开关和工作区自定义选择仍会共同过滤目录 Skills', () async {
      final runtime = CapabilityRuntime();
      final processManager = ProcessSessionManager();
      final logStore = LogStore();
      final now = DateTime.now();
      runtime.syncSkills([
        SkillEntry(
          name: 'enabled-a',
          description: '',
          source: 'local_directory',
          enabled: true,
          createdAt: now,
        ),
        SkillEntry(
          name: 'enabled-b',
          description: '',
          source: 'local_directory',
          enabled: true,
          createdAt: now,
        ),
        SkillEntry(
          name: 'disabled-c',
          description: '',
          source: 'local_directory',
          enabled: false,
          createdAt: now,
        ),
      ]);
      final workspace = Workspace(
        uuid: '11111111-1111-4111-8111-111111111114',
        name: 'skills-filter',
        projectRoot: root.path,
        createdAt: now,
        lastActiveAt: now,
        selectedSkillNames: const ['enabled-b', 'disabled-c'],
      );
      final context = ToolContext(
        workspace: workspace,
        pathGuard: PathGuard(root.path),
        processManager: processManager,
        capabilities: runtime,
        logStore: logStore,
      );

      expect(context.enabledSkills.map((item) => item.name), ['enabled-b']);

      await runtime.shutdown();
      runtime.dispose();
      await processManager.shutdown();
      processManager.dispose();
      logStore.dispose();
    });
  });
}
