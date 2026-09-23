import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../utils/app_paths.dart';

class ScannedSkill {
  final String name;
  final String description;
  final String rootPath;

  ScannedSkill({required this.name, required this.description, required this.rootPath});
}

class SkillImportResult {
  final int scanned;
  final int imported;
  final int skipped;

  const SkillImportResult({required this.scanned, required this.imported, required this.skipped});
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

/// Skills 直接以 Codexter 数据目录下的 skills 文件夹为数据源；下游 MCP 仍从 Codex 配置扫描。
class CapabilityManager {
  final Future<String> Function()? _skillsDirectoryProvider;
  final String? _homeDirectoryOverride;

  CapabilityManager({this._skillsDirectoryProvider, String? homeDirectory})
    : _homeDirectoryOverride = homeDirectory;

  Future<String> get _skillsDirectory => _skillsDirectoryProvider?.call() ?? AppPaths.skillsDir;

  Future<List<ScannedSkill>> scanLocalSkills() async {
    return _scanSkillRoots([await _skillsDirectory]);
  }

  Future<List<ScannedSkill>> scanCodexSkills() async {
    return _scanSkillRoots([p.join(_codexDir, 'skills'), p.join(_homeDir, '.agents', 'skills')]);
  }

  Future<List<ScannedSkill>> scanCursorSkills() async {
    return _scanSkillRoots([p.join(_homeDir, '.cursor', 'skills')]);
  }

  Future<SkillImportResult> importCodexSkills() async {
    return _importSkills(await scanCodexSkills());
  }

  Future<SkillImportResult> importCursorSkills() async {
    return _importSkills(await scanCursorSkills());
  }

  Future<String> get localSkillsDirectory => _skillsDirectory;

  Future<bool> openLocalSkillsDirectory() async {
    final path = await _skillsDirectory;
    try {
      final result = Platform.isWindows
          ? await Process.run('explorer.exe', [path])
          : Platform.isMacOS
          ? await Process.run('open', [path])
          : await Process.run('xdg-open', [path]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<void> deleteLocalSkill(String rootPath) async {
    final skillsRoot = p.normalize(p.absolute(await _skillsDirectory));
    final candidate = p.normalize(p.absolute(rootPath));
    final expectedParent = p.dirname(candidate);
    final sameParent = Platform.isWindows
        ? expectedParent.toLowerCase() == skillsRoot.toLowerCase()
        : expectedParent == skillsRoot;
    if (!sameParent || p.equals(candidate, skillsRoot)) {
      throw StateError('拒绝删除 Skills 目录之外的路径：$rootPath');
    }

    final type = await FileSystemEntity.type(candidate, followLinks: false);
    if (type == FileSystemEntityType.notFound) return;
    if (type != FileSystemEntityType.directory) {
      throw StateError('Skill 路径不是目录：$rootPath');
    }
    await Directory(candidate).delete(recursive: true);
  }

  Future<List<ScannedMcp>> scanCodexMcps() async {
    final configFile = File(p.join(_codexDir, 'config.toml'));
    if (!await configFile.exists()) return const [];
    return _parseMcpServers(await configFile.readAsString());
  }

  Future<List<ScannedMcp>> scanCursorMcps() async {
    final configFile = File(p.join(_homeDir, '.cursor', 'mcp.json'));
    if (!await configFile.exists()) return const [];

    final decoded = jsonDecode(await configFile.readAsString());
    if (decoded is! Map) return const [];
    final servers = decoded['mcpServers'];
    if (servers is! Map) return const [];

    final results = <ScannedMcp>[];
    for (final entry in servers.entries) {
      final name = '${entry.key}'.trim();
      final raw = entry.value;
      if (name.isEmpty || raw is! Map) continue;

      final command = '${raw['command'] ?? ''}'.trim();
      final url = '${raw['url'] ?? ''}'.trim();
      final enabled = raw['enabled'] != false && raw['disabled'] != true;
      if (command.isNotEmpty) {
        final args = raw['args'] is List
            ? (raw['args'] as List).map((item) => '$item').toList()
            : <String>[];
        final env = raw['env'] is Map
            ? Map<String, String>.fromEntries(
                (raw['env'] as Map).entries.map((item) => MapEntry('${item.key}', '${item.value}')),
              )
            : <String, String>{};
        final cwd = '${raw['cwd'] ?? ''}'.trim();
        results.add(
          ScannedMcp(
            name: name,
            enabled: enabled,
            transport: {
              'command': command,
              if (args.isNotEmpty) 'args': args,
              if (env.isNotEmpty) 'env': env,
              if (cwd.isNotEmpty) 'cwd': cwd,
            },
          ),
        );
        continue;
      }

      if (url.isNotEmpty) {
        final headers = raw['headers'] is Map
            ? Map<String, String>.fromEntries(
                (raw['headers'] as Map).entries.map(
                  (item) => MapEntry('${item.key}', '${item.value}'),
                ),
              )
            : <String, String>{};
        results.add(
          ScannedMcp(
            name: name,
            enabled: enabled,
            transport: {'url': url, if (headers.isNotEmpty) 'headers': headers},
          ),
        );
      }
    }
    results.sort((left, right) => left.name.compareTo(right.name));
    return results;
  }

  Future<List<ScannedSkill>> _scanSkillRoots(List<String> roots) async {
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

  Future<SkillImportResult> _importSkills(List<ScannedSkill> scanned) async {
    final existingNames = (await scanLocalSkills()).map((item) => item.name).toSet();
    final targetRoot = await _skillsDirectory;
    await Directory(targetRoot).create(recursive: true);
    var imported = 0;
    var skipped = 0;

    for (final skill in scanned) {
      final source = Directory(skill.rootPath);
      final folderName = p.basename(source.path);
      final target = Directory(p.join(targetRoot, folderName));
      if (existingNames.contains(skill.name) || await target.exists()) {
        skipped++;
        continue;
      }

      final staging = await Directory(targetRoot).createTemp('.skill-import-');
      final staged = Directory(p.join(staging.path, folderName));
      try {
        await _copyDirectory(source, staged);
        await staged.rename(target.path);
        imported++;
        existingNames.add(skill.name);
      } catch (_) {
        if (await target.exists()) {
          try {
            await target.delete(recursive: true);
          } catch (_) {}
        }
        rethrow;
      } finally {
        if (await staging.exists()) {
          try {
            await staging.delete(recursive: true);
          } catch (_) {}
        }
      }
    }

    return SkillImportResult(scanned: scanned.length, imported: imported, skipped: skipped);
  }

  Future<void> _copyDirectory(Directory source, Directory target) async {
    await target.create(recursive: true);
    await for (final entity in source.list(recursive: false, followLinks: false)) {
      final destination = p.join(target.path, p.basename(entity.path));
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(destination));
      } else if (entity is File) {
        await entity.copy(destination);
      }
    }
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
        final nestedMatch = RegExp(r'^\[mcp_servers\.([^\].]+)\.([^\]]+)\]$').firstMatch(line);
        if (nestedMatch != null && nestedMatch.group(1) == draft.name) {
          draft.nestedSection = nestedMatch.group(2);
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
    return _homeDirectoryOverride ??
        Platform.environment['HOME'] ??
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
  final Map<String, String> headers = {};

  String? type;
  String? command;
  String? url;
  int? startupTimeoutSec;
  int? toolTimeoutSec;
  bool enabled = true;
  String? nestedSection;

  _McpDraft(this.name);

  void consume(String line, String Function(String) unquote) {
    final pair = RegExp(r'^([A-Za-z0-9_\-]+)\s*=\s*(.+)$').firstMatch(line);
    if (pair == null) return;
    final key = pair.group(1)!;
    final value = pair.group(2)!.trim();

    switch (nestedSection) {
      case 'env':
        env[key] = unquote(value);
        return;
      case 'http_headers':
        headers[key] = unquote(value);
        return;
      case 'env_http_headers':
        _addEnvironmentHeader(key, unquote(value));
        return;
    }

    if (nestedSection != null) return;

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
      case 'http_headers':
        headers.addAll(_parseInlineStringMap(value, unquote));
        return;
      case 'env_http_headers':
        final environmentHeaders = _parseInlineStringMap(value, unquote);
        for (final entry in environmentHeaders.entries) {
          _addEnvironmentHeader(entry.key, entry.value);
        }
        return;
    }
  }

  void _addEnvironmentHeader(String key, String environmentName) {
    final environmentValue = Platform.environment[environmentName];
    if (environmentValue != null && environmentValue.isNotEmpty) {
      headers[key] = environmentValue;
    }
  }

  Map<String, String> _parseInlineStringMap(String value, String Function(String) unquote) {
    final trimmed = value.trim();
    if (!trimmed.startsWith('{') || !trimmed.endsWith('}')) return const {};

    final result = <String, String>{};
    final inner = trimmed.substring(1, trimmed.length - 1);
    var offset = 0;
    final pairPattern = RegExp(
      r'''\s*("(?:\\.|[^"\\])*"|'[^']*'|[A-Za-z0-9_\-]+)\s*=\s*("(?:\\.|[^"\\])*"|'[^']*')\s*''',
    );

    while (offset < inner.length) {
      final match = pairPattern.matchAsPrefix(inner, offset);
      if (match == null) return const {};
      result[unquote(match.group(1)!)] = unquote(match.group(2)!);
      offset = match.end;
      if (offset == inner.length) break;
      if (inner[offset] != ',') return const {};
      offset++;
    }
    return result;
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
        transport: {'url': url, if (headers.isNotEmpty) 'headers': headers},
        enabled: enabled,
        startupTimeoutMs: startupTimeoutSec == null ? null : startupTimeoutSec! * 1000,
        toolTimeoutMs: toolTimeoutSec == null ? null : toolTimeoutSec! * 1000,
      );
    }
    return null;
  }
}
