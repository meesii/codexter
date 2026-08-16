import '../../utils/file_walker.dart';
import '../../utils/glob_match.dart';
import 'registry.dart';
import 'tool_context.dart';

/// 代码搜索工具组：grep / glob / code_explore
class SearchTools {
  const SearchTools._();

  static final _symbolRegex = RegExp(
    r'^\s*(?:export\s+)?(?:abstract\s+|final\s+|sealed\s+|static\s+|async\s+)*'
    r'(class|mixin|enum|extension|typedef|interface|struct|func|function|def|fn)\s+([A-Za-z_][\w]*)',
  );

  static void register(ToolRegistry registry, ToolContext context) {
    final guard = context.pathGuard;

    registry.register(_grepSchema, (raw) async {
      final args = ToolArgs(raw);
      final pattern = args.requireText('pattern');
      final searchRoot = guard.safeResolve(args.text('path') ?? '.');
      final include = args.text('include');
      final maxResults = args.intOr('maxResults', 100);
      final caseSensitive = args.boolOr('caseSensitive', true);

      final RegExp searchRegex;
      try {
        searchRegex = RegExp(pattern, caseSensitive: caseSensitive);
      } catch (error) {
        return ToolResult.error('Invalid regex: $error');
      }

      final includePattern = include == null ? null : GlobMatch.normalize(include);
      final files = await FileWalker.collect(
        rootPath: searchRoot,
        guard: guard,
        accept: includePattern == null
            ? null
            : (relative) => GlobMatch.matches(includePattern, relative),
      );

      final matches = <Map<String, dynamic>>[];
      for (final walked in files) {
        final lines = await FileWalker.readLinesSafe(walked.file);
        for (var index = 0; index < lines.length; index++) {
          if (!searchRegex.hasMatch(lines[index])) continue;
          final text = lines[index];
          matches.add({
            'path': walked.relativePath,
            'line': index + 1,
            'text': text.length > 240 ? '${text.substring(0, 240)}…' : text,
          });
          if (matches.length >= maxResults) break;
        }
        if (matches.length >= maxResults) break;
      }

      final buffer = StringBuffer();
      for (final match in matches) {
        buffer.writeln('${match['path']}:${match['line']}: ${match['text']}');
      }

      return ToolResult.text(
        buffer.toString(),
        structured: {
          'matchCount': matches.length,
          'truncated': matches.length >= maxResults,
          'matches': matches,
        },
      );
    });

    registry.register(_globSchema, (raw) async {
      final args = ToolArgs(raw);
      final pattern = GlobMatch.normalize(args.requireText('pattern'));
      final searchRoot = guard.safeResolve(args.text('path') ?? '.');
      final maxResults = args.intOr('maxResults', 500);

      final files = await FileWalker.collect(
        rootPath: searchRoot,
        guard: guard,
        maxFiles: maxResults,
        accept: (relative) => GlobMatch.matches(pattern, relative),
      );

      final paths = files.map((walked) => walked.relativePath).toList();
      return ToolResult.text(paths.join('\n'), structured: {'count': paths.length, 'files': paths});
    });

    registry.register(_codeExploreSchema, (raw) async {
      final args = ToolArgs(raw);
      final relative = args.text('path') ?? '.';
      final exploreRoot = guard.safeResolve(relative);
      final maxFiles = args.intOr('maxFiles', 80);

      final files = await FileWalker.collect(
        rootPath: exploreRoot,
        guard: guard,
        maxFiles: maxFiles,
        accept: (path) => _isSourceFile(path),
      );

      final buffer = StringBuffer();
      final outline = <Map<String, dynamic>>[];

      for (final walked in files) {
        final lines = await FileWalker.readLinesSafe(walked.file);
        final symbols = <String>[];
        for (var index = 0; index < lines.length; index++) {
          final match = _symbolRegex.firstMatch(lines[index]);
          if (match == null) continue;
          symbols.add('${match.group(1)} ${match.group(2)} (L${index + 1})');
          if (symbols.length >= 12) break;
        }
        buffer.writeln('${walked.relativePath}  ·  ${lines.length} lines');
        for (final symbol in symbols) {
          buffer.writeln('    $symbol');
        }
        outline.add({'path': walked.relativePath, 'lines': lines.length, 'symbols': symbols});
      }

      return ToolResult.text(
        buffer.toString(),
        structured: {'root': relative, 'fileCount': outline.length, 'outline': outline},
      );
    });
  }

  static const _sourceExtensions = <String>{
    'dart',
    'ts',
    'tsx',
    'js',
    'jsx',
    'py',
    'go',
    'rs',
    'java',
    'kt',
    'swift',
    'c',
    'h',
    'cc',
    'cpp',
    'hpp',
    'cs',
    'rb',
    'php',
    'vue',
    'svelte',
    'sql',
    'sh',
  };

  static bool _isSourceFile(String relativePath) {
    final dotIndex = relativePath.lastIndexOf('.');
    if (dotIndex < 0) return false;
    return _sourceExtensions.contains(relativePath.substring(dotIndex + 1).toLowerCase());
  }

  static const _grepSchema = ToolSchema(
    name: 'grep',
    title: 'Search file contents',
    description: 'Search file contents by regex. Use include to narrow by glob.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'pattern': {'type': 'string', 'description': 'Dart/RE2 style regex'},
        'path': {'type': 'string', 'default': '.'},
        'include': {'type': 'string', 'description': 'Glob filter, e.g. **/*.dart'},
        'maxResults': {'type': 'integer', 'default': 100},
        'caseSensitive': {'type': 'boolean', 'default': true},
      },
      'required': ['pattern'],
    },
    outputSchema: {
      'type': 'object',
      'properties': {
        'text': {'type': 'string', 'description': 'Formatted match list'},
        'matchCount': {'type': 'integer'},
        'truncated': {'type': 'boolean'},
        'matches': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'path': {'type': 'string'},
              'line': {'type': 'integer'},
              'text': {'type': 'string'},
            },
          },
        },
      },
      'required': ['text', 'matchCount', 'truncated', 'matches'],
    },
    annotations: ToolAnnotations.readOnly,
    meta: {'openai/toolInvocation/invoking': '正在搜索…', 'openai/toolInvocation/invoked': '搜索完成'},
  );

  static const _globSchema = ToolSchema(
    name: 'glob',
    title: 'Find files by glob',
    description: 'Find files by glob pattern, e.g. **/*.dart or lib/**/{a,b}.ts.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'pattern': {'type': 'string'},
        'path': {'type': 'string', 'default': '.'},
        'maxResults': {'type': 'integer', 'default': 500},
      },
      'required': ['pattern'],
    },
    outputSchema: {
      'type': 'object',
      'properties': {
        'text': {'type': 'string', 'description': 'Newline-separated file paths'},
        'count': {'type': 'integer'},
        'files': {
          'type': 'array',
          'items': {'type': 'string'},
        },
      },
      'required': ['text', 'count', 'files'],
    },
    annotations: ToolAnnotations.readOnly,
    meta: {'openai/toolInvocation/invoking': '正在查找文件…', 'openai/toolInvocation/invoked': '已查找文件'},
  );

  static const _codeExploreSchema = ToolSchema(
    name: 'code_explore',
    title: 'Explore code structure',
    description: 'Outline source files under a directory with their top-level symbols.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'path': {'type': 'string', 'default': '.'},
        'maxFiles': {'type': 'integer', 'default': 80},
      },
    },
    outputSchema: {
      'type': 'object',
      'properties': {
        'text': {'type': 'string', 'description': 'Formatted outline'},
        'root': {'type': 'string'},
        'fileCount': {'type': 'integer'},
        'outline': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'path': {'type': 'string'},
              'lines': {'type': 'integer'},
              'symbols': {
                'type': 'array',
                'items': {'type': 'string'},
              },
            },
          },
        },
      },
      'required': ['text', 'root', 'fileCount', 'outline'],
    },
    annotations: ToolAnnotations.readOnly,
    meta: {'openai/toolInvocation/invoking': '正在探索代码…', 'openai/toolInvocation/invoked': '代码探索完成'},
  );
}
