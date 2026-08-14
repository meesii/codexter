import 'dart:io';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import '../../models/skill_entry.dart';
import 'registry.dart';
import 'tool_context.dart';

/// Skills 工具组：skills_list / skill_read
class SkillTools {
    const SkillTools._();

    static void register(ToolRegistry registry, ToolContext context) {
        final capabilities = context.capabilities;

        registry.register(_listSchema, (raw) async {
            final skills = capabilities.enabledSkills;
            if (skills.isEmpty) {
                return ToolResult.text(
                    'No skills enabled. The desktop app manages them under Skills.',
                    structured: {'count': 0, 'skills': const []},
                );
            }

            final buffer = StringBuffer();
            for (final skill in skills) {
                buffer.writeln('- ${skill.name}: ${skill.description}');
            }
            return ToolResult.text(buffer.toString(), structured: {
                'count': skills.length,
                'skills': skills.map(_skillToJson).toList(),
            });
        });

        registry.register(_readSchema, (raw) async {
            final name = ToolArgs(raw).requireText('name');
            final skill = capabilities.enabledSkills
                .firstWhereOrNull((item) => item.name == name);
            if (skill == null) return ToolResult.error('Unknown skill: $name');

            final content = await _readSkillBody(skill);
            if (content == null) {
                return ToolResult.text(
                    '${skill.name}: ${skill.description}',
                    structured: _skillToJson(skill),
                );
            }
            return ToolResult.text(content, structured: _skillToJson(skill));
        });
    }

    static Future<String?> _readSkillBody(SkillEntry skill) async {
        final root = skill.rootPath;
        if (root == null || root.isEmpty) return null;
        final candidates = [
            File(root),
            File(p.join(root, 'SKILL.md')),
        ];
        for (final file in candidates) {
            if (await file.exists()) {
                final stat = await file.stat();
                if (stat.type == FileSystemEntityType.file) {
                    return file.readAsString();
                }
            }
        }
        return null;
    }

    static Map<String, dynamic> _skillToJson(SkillEntry skill) {
        return {
            'name': skill.name,
            'description': skill.description,
            'source': skill.source,
            if (skill.rootPath != null) 'rootPath': skill.rootPath,
        };
    }

    static const _listSchema = ToolSchema(
        name: 'skills_list',
        title: 'List skills',
        description: 'List the skills enabled in the desktop app.',
        inputSchema: {'type': 'object', 'properties': {}},
        outputSchema: {
            'type': 'object',
            'properties': {
                'text': {'type': 'string', 'description': 'Formatted skill list'},
                'count': {'type': 'integer'},
                'skills': {
                    'type': 'array',
                    'items': {
                        'type': 'object',
                        'properties': {
                            'name': {'type': 'string'},
                            'description': {'type': 'string'},
                            'source': {'type': 'string'},
                            'rootPath': {'type': 'string'},
                        },
                    },
                },
            },
            'required': ['text', 'count', 'skills'],
        },
        annotations: ToolAnnotations.readOnly,
        meta: {
            'openai/toolInvocation/invoking': '正在列出技能…',
            'openai/toolInvocation/invoked': '已列出技能',
        },
    );

    static const _readSchema = ToolSchema(
        name: 'skill_read',
        title: 'Read skill',
        description: 'Read the full SKILL.md body of one enabled skill.',
        inputSchema: {
            'type': 'object',
            'properties': {
                'name': {'type': 'string'},
            },
            'required': ['name'],
        },
        outputSchema: {
            'type': 'object',
            'properties': {
                'text': {'type': 'string', 'description': 'Skill body content'},
                'name': {'type': 'string'},
                'description': {'type': 'string'},
                'source': {'type': 'string'},
                'rootPath': {'type': 'string'},
            },
            'required': ['text', 'name', 'description', 'source'],
        },
        annotations: ToolAnnotations.readOnly,
        meta: {
            'openai/toolInvocation/invoking': '正在读取技能…',
            'openai/toolInvocation/invoked': '已读取技能',
        },
    );
}
