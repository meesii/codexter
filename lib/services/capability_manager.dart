import 'dart:io';
import 'package:path/path.dart' as p;
import '../utils/app_paths.dart';

class ScannedSkill {
    final String name;
    final String description;
    final String rootPath;

    ScannedSkill({
        required this.name,
        required this.description,
        required this.rootPath,
    });
}

class ScannedMcp {
    final String name;
    final Map<String, dynamic> transport;
    final bool enabled;
    final int? startupTimeoutMs;
    final int? toolTimeoutMs;

    ScannedMcp({
        required this.name,
        required this.transport,
        this.enabled = true,
        this.startupTimeoutMs,
        this.toolTimeoutMs,
    });
}

/// 从 Codex 目录导入 Skills / 下游 MCP，并保存手动创建的 Skill
class CapabilityManager {
    Future<List<ScannedSkill>> scanCodexSkills() async {
        final roots = [
            p.join(_codexDir, 'skills'),
            p.join(_homeDir, '.agents', 'skills'),
            await AppPaths.skillsDir,
        ];

        final found = <String, ScannedSkill>{};
        for (final root in roots) {
            final dir = Directory(root);
            if (!await dir.exists()) continue;
            try {
                await for (final entity in dir.list(followLinks: false)) {
                    if (entity is! Directory) continue;
                    final dirName = p.basename(entity.path);
                    if (dirName.startsWith('.')) continue;

                    final skillFile = File(p.join(entity.path, 'SKILL.md'));
                    if (!await skillFile.exists()) continue;

                    final metadata = _parseFrontMatter(await skillFile.readAsString(), dirName);
                    found[metadata.name] = ScannedSkill(
                        name: metadata.name,
                        description: metadata.description,
                        rootPath: entity.path,
                    );
                }
            } catch (_) {}
        }
        final results = found.values.toList();
        results.sort((left, right) => left.name.compareTo(right.name));
        return results;
    }

    Future<String> writeManualSkill({
        required String name,
        required String description,
        required String body,
    }) async {
        final root = p.join(await AppPaths.skillsDir, name);
        await Directory(root).create(recursive: true);

        final content = [
            '---',
            'name: $name',
            'description: $description',
            '---',
            '',
            body.trim(),
            '',
        ].join('\n');
        await File(p.join(root, 'SKILL.md')).writeAsString(content);
        return root;
    }

    Future<String?> readSkillBody(String? rootPath) async {
        if (rootPath == null || rootPath.isEmpty) return null;
        final file = File(p.join(rootPath, 'SKILL.md'));
        if (!await file.exists()) return null;
        return file.readAsString();
    }

    Future<List<ScannedMcp>> scanCodexMcps() async {
        final configFile = File(p.join(_codexDir, 'config.toml'));
        if (!await configFile.exists()) return const [];
        return _parseMcpServers(await configFile.readAsString());
    }

    _SkillMeta _parseFrontMatter(String content, String fallbackName) {
        final lines = content.replaceAll('\r\n', '\n').split('\n');
        if (lines.isEmpty || lines.first.trim() != '---') {
            return _SkillMeta(fallbackName, '');
        }

        var name = fallbackName;
        var description = '';
        for (var index = 1; index < lines.length; index++) {
            final line = lines[index];
            if (line.trim() == '---') break;

            final nameMatch = RegExp(r'^name:\s*(.*)$').firstMatch(line);
            if (nameMatch != null) {
                final parsed = nameMatch.group(1)!.trim();
                if (parsed.isNotEmpty) name = _unquote(parsed);
                continue;
            }

            final descMatch = RegExp(r'^description:\s*(.*)$').firstMatch(line);
            if (descMatch == null) continue;

            var value = descMatch.group(1)!.trim();
            if (value == '>' || value == '|' || value == '>-' || value == '|-') {
                final folded = <String>[];
                while (index + 1 < lines.length && RegExp(r'^\s+\S').hasMatch(lines[index + 1])) {
                    index++;
                    folded.add(lines[index].trim());
                }
                value = folded.join(' ');
            }
            description = _unquote(value);
        }
        return _SkillMeta(name, description);
    }

    /// 极简 TOML 解析，只取 [mcp_servers.*] 段落
    List<ScannedMcp> _parseMcpServers(String toml) {
        final results = <ScannedMcp>[];
        final lines = toml.replaceAll('\r\n', '\n').split('\n');
        _McpDraft? draft;

        void flush() {
            final built = draft?.build();
            if (built != null) results.add(built);
        }

        for (final rawLine in lines) {
            final line = rawLine.trim();
            if (line.isEmpty || line.startsWith('#')) continue;

            final serverMatch = RegExp(r'^\[mcp_servers\.([^\].]+)\]$').firstMatch(line);
            if (serverMatch != null) {
                flush();
                draft = _McpDraft(serverMatch.group(1)!);
                continue;
            }
            if (draft == null) continue;

            if (line.startsWith('[')) {
                final envMatch = RegExp(r'^\[mcp_servers\.([^\].]+)\.env\]$').firstMatch(line);
                if (envMatch != null && envMatch.group(1) == draft.name) {
                    draft.inEnvSection = true;
                    continue;
                }
                flush();
                draft = null;
                continue;
            }

            draft.consume(line, _unquote);
        }
        flush();
        return results;
    }

    String _unquote(String value) {
        if (value.length < 2) return value;
        if (value.startsWith("'") && value.endsWith("'")) {
            return value.substring(1, value.length - 1).replaceAll("''", "'");
        }
        if (value.startsWith('"') && value.endsWith('"')) {
            return value.substring(1, value.length - 1);
        }
        return value;
    }

    String get _homeDir {
        return Platform.environment['HOME'] ??
            Platform.environment['USERPROFILE'] ??
            '.';
    }

    String get _codexDir => p.join(_homeDir, '.codex');
}

class _SkillMeta {
    final String name;
    final String description;

    _SkillMeta(this.name, this.description);
}

class _McpDraft {
    final String name;
    final List<String> args = [];
    final Map<String, String> env = {};

    String? type;
    String? command;
    String? url;
    int? startupTimeoutSec;
    int? toolTimeoutSec;
    bool enabled = true;
    bool inEnvSection = false;

    _McpDraft(this.name);

    void consume(String line, String Function(String) unquote) {
        final pair = RegExp(r'^([A-Za-z0-9_\-]+)\s*=\s*(.+)$').firstMatch(line);
        if (pair == null) return;
        final key = pair.group(1)!;
        final value = pair.group(2)!.trim();

        if (inEnvSection) {
            env[key] = unquote(value);
            return;
        }

        switch (key) {
            case 'type':
                type = unquote(value);
                return;
            case 'command':
                command = unquote(value);
                return;
            case 'url':
                url = unquote(value);
                return;
            case 'enabled':
                enabled = value == 'true';
                return;
            case 'startup_timeout_sec':
                startupTimeoutSec = int.tryParse(value);
                return;
            case 'tool_timeout_sec':
                toolTimeoutSec = int.tryParse(value);
                return;
            case 'args':
                final inner = RegExp(r'^\[(.*)\]$').firstMatch(value)?.group(1) ?? '';
                for (final match in RegExp(r'''["']([^"']*)["']''').allMatches(inner)) {
                    args.add(match.group(1) ?? '');
                }
                return;
        }
    }

    ScannedMcp? build() {
        if (type == 'stdio' || (command != null && url == null)) {
            if (command == null || command!.isEmpty) return null;
            return ScannedMcp(
                name: name,
                transport: {
                    'command': command,
                    if (args.isNotEmpty) 'args': args,
                    if (env.isNotEmpty) 'env': env,
                },
                enabled: enabled,
                startupTimeoutMs: startupTimeoutSec == null ? null : startupTimeoutSec! * 1000,
                toolTimeoutMs: toolTimeoutSec == null ? null : toolTimeoutSec! * 1000,
            );
        }

        if (url != null && url!.isNotEmpty) {
            return ScannedMcp(
                name: name,
                transport: {'url': url},
                enabled: enabled,
                startupTimeoutMs: startupTimeoutSec == null ? null : startupTimeoutSec! * 1000,
                toolTimeoutMs: toolTimeoutSec == null ? null : toolTimeoutSec! * 1000,
            );
        }
        return null;
    }
}
