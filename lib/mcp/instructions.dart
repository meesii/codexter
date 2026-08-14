import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/skill_entry.dart';
import '../services/downstream_client.dart';

/// 生成 initialize/server-discover 返回给 ChatGPT 的工作区说明。
class ServerInstructions {
    const ServerInstructions._();

    static String build({
        required String projectRoot,
        required List<SkillEntry> skills,
        required List<DownstreamClient> downstream,
        required int toolCount,
    }) {
        final shell = Platform.isWindows ? 'powershell' : 'bash';
        final sections = <String>[
            _environment(projectRoot, shell, toolCount),
            '',
            'This MCP server exposes local coding tools for the current workspace.',
            'For every tools/call request, include `purpose`: a concise user-visible summary (max 80 characters) of what the immediate call will obtain, verify, or change. `purpose` is used by the desktop app for activity UI and is never forwarded to downstream MCP tools.',
            'When you are finishing a user request, use `summary` so the desktop app can notify the user that this round of work has ended and show a concise summary.',
        ];

        final agents = _loadRootAgents(projectRoot);
        if (agents != null) {
            sections
                ..add('')
                ..add('<project_instructions>')
                ..add(agents)
                ..add('</project_instructions>');
        }

        sections
            ..add('')
            ..addAll(_toolMap())
            ..add('')
            ..addAll(_playbook());

        if (skills.isNotEmpty) {
            sections
                ..add('')
                ..add('Available Skills (metadata only; use skill_read for the current SKILL.md body):');
            for (final skill in skills) {
                sections.add('- ${skill.name}: ${skill.description}');
            }
            sections.add('Skills can change while the desktop app is running; use skills_list when current availability matters.');
        }

        if (downstream.isNotEmpty) {
            sections
                ..add('')
                ..add('Downstream MCP servers (discover with mcp_tools, invoke with mcp_call):');
            for (final client in downstream) {
                sections.add('- ${client.name} [${client.state.name}] ${client.tools.length} tools');
            }
        }

        return sections.join('\n');
    }

    static String _environment(String projectRoot, String shell, int toolCount) {
        return [
            '<environment_context>',
            '  <project_root>$projectRoot</project_root>',
            '  <shell>$shell</shell>',
            '  <tool_count>$toolCount</tool_count>',
            '  <paths>relative to project_root unless stated otherwise</paths>',
            '</environment_context>',
        ].join('\n');
    }

    /// For a workspace-scoped MCP endpoint the project root is the agent cwd.
    /// Prefer AGENTS.override.md over AGENTS.md, matching Codex precedence at one directory level.
    static String? _loadRootAgents(String projectRoot) {
        for (final name in const ['AGENTS.override.md', 'AGENTS.md']) {
            final file = File(p.join(projectRoot, name));
            try {
                if (file.existsSync()) return file.readAsStringSync();
            } catch (_) {}
        }
        return null;
    }

    static List<String> _toolMap() {
        return const [
            'Tool map (pick by goal):',
            '- read — read one file or several files with numbered lines before changing code.',
            '- apply_patch — exact replacements, create/overwrite, or delete files atomically.',
            '- ls — inspect one directory quickly.',
            '- grep / glob — structured content and path search without shell syntax differences.',
            '- code_explore — quickly outline source files and top-level symbols.',
            '- exec_command — run shell commands; long-running commands return session_id.',
            '- write_stdin — poll a running command or send stdin/Ctrl+C using session_id.',
            '- skills_list / skill_read — discover dynamic local Skills and load SKILL.md on demand.',
            '- mcp_tools / mcp_call — discover and invoke tools from enabled downstream MCP servers.',
            '- summary — summarize the current round for the desktop app when you are finishing a user request.',
        ];
    }

    static List<String> _playbook() {
        return const [
            'Working order:',
            '1. Use ls / glob / code_explore / grep to locate relevant code efficiently.',
            '2. Read the relevant files before changing them.',
            '3. Use apply_patch for all source/text file changes; compose related edits there and avoid rewriting unrelated content.',
            '4. Use exec_command for tests, builds, git, package managers, adb, and other installed CLI tools. Do not edit source/text files through shell redirection or Get-Content/Set-Content.',
            '5. If exec_command returns session_id, continue with write_stdin; send \\u0003 to stop an interactive/long-running command when appropriate.',
            '6. Use skill_read only when a listed Skill is relevant; use mcp_tools before mcp_call when downstream capabilities are unknown.',
            '7. When finishing the current user request, use summary to provide the desktop app with a concise round summary.',
        ];
    }
}
