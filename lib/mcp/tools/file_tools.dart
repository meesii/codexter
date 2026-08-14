import 'dart:io';
import 'package:path/path.dart' as p;
import 'registry.dart';
import 'tool_context.dart';

/// 文件工具组：read / apply_patch / ls
class FileTools {
    const FileTools._();

    static const maxReadLines = 2000;
    static const maxReadFiles = 20;

    static void register(ToolRegistry registry, ToolContext context) {
        final guard = context.pathGuard;

        registry.register(_readSchema, (raw) async {
            final args = ToolArgs(raw);
            final single = args.text('path');
            final many = args.stringList('paths');
            final targets = <String>[
                if (single != null && single.isNotEmpty) single,
                ...many.where((item) => item.isNotEmpty),
            ];
            final uniqueTargets = targets.toSet().take(maxReadFiles).toList();
            if (uniqueTargets.isEmpty) {
                return ToolResult.error('path or paths is required');
            }

            final offset = args.intOr('offset', 1);
            final defaultLimit = uniqueTargets.length == 1 ? maxReadLines : 400;
            final limit = args.intOr('limit', defaultLimit).clamp(1, maxReadLines);
            final buffer = StringBuffer();
            final results = <Map<String, dynamic>>[];

            for (final relative in uniqueTargets) {
                final file = File(guard.safeResolve(relative));
                if (!await file.exists()) {
                    if (uniqueTargets.length > 1) buffer.writeln('=== $relative (not found) ===');
                    results.add({'path': relative, 'found': false});
                    continue;
                }

                final rendered = await _renderNumbered(file, offset, limit);
                if (uniqueTargets.length > 1) buffer.writeln('=== $relative ===');
                buffer.write(rendered.text);
                if (uniqueTargets.length > 1) buffer.writeln();
                results.add({
                    'path': relative,
                    'found': true,
                    'offset': rendered.startLine,
                    'lineCount': rendered.lineCount,
                    'totalLines': rendered.totalLines,
                });
            }

            return ToolResult.text(buffer.toString(), structured: {
                'files': results,
                'truncated': targets.length > maxReadFiles,
            });
        });

        registry.register(_applyPatchSchema, (raw) async {
            final edits = raw['edits'];
            if (edits is! List || edits.isEmpty) return ToolResult.error('edits is required');

            final states = <String, _PatchState>{};
            for (final item in edits) {
                if (item is! Map) return ToolResult.error('each edit must be an object');
                final edit = item.cast<String, dynamic>();
                final editArgs = ToolArgs(edit);
                final relative = editArgs.requireText('path');
                final delete = editArgs.boolOr('delete', false);
                final file = File(guard.safeResolve(relative));
                final resolvedKey = p.normalize(file.absolute.path);
                final stateKey = Platform.isWindows ? resolvedKey.toLowerCase() : resolvedKey;
                final state = states[stateKey] ??= await _PatchState.load(file, relative);

                if (delete) {
                    if (!state.exists) {
                        return ToolResult.error('File not found: $relative (nothing was written)');
                    }
                    state.delete();
                    continue;
                }

                final newText = edit['newText'] as String? ?? '';
                if (!edit.containsKey('oldText')) {
                    state.overwrite(newText);
                    continue;
                }

                final oldText = edit['oldText'] as String? ?? '';
                if (oldText.isEmpty) {
                    return ToolResult.error(
                        'oldText must not be empty in $relative; omit oldText to create/overwrite (nothing was written)',
                    );
                }
                if (!state.exists) {
                    return ToolResult.error('File not found: $relative (nothing was written)');
                }

                final rawContent = state.content!;
                final content = _normalizeNewlines(rawContent);
                final normalizedOld = _normalizeNewlines(oldText);
                final occurrences = _countOccurrences(content, normalizedOld);
                if (occurrences != 1) {
                    return ToolResult.error(
                        'oldText must match exactly once in $relative (nothing was written)',
                    );
                }

                final normalizedNew = _normalizeNewlines(newText);
                final updated = content.replaceFirst(normalizedOld, normalizedNew);
                state.overwrite(_preserveNewlines(rawContent, updated));
            }

            final plans = states.values.toList(growable: false);
            try {
                for (final state in plans) {
                    await state.commit();
                }
            } catch (error) {
                final rollbackErrors = <String>[];
                for (final state in plans.reversed) {
                    try {
                        await state.rollback();
                    } catch (rollbackError) {
                        rollbackErrors.add('${state.relative}: $rollbackError');
                    }
                }
                final suffix = rollbackErrors.isEmpty
                    ? ''
                    : '; rollback errors: ${rollbackErrors.join(' | ')}';
                return ToolResult.error('apply_patch commit failed: $error$suffix');
            }

            return ToolResult.text(
                'Applied ${edits.length} edit(s) across ${plans.length} file(s): '
                '${plans.map((state) => state.relative).join(', ')}',
                structured: {
                    'files': plans.map((state) => state.relative).toList(),
                    'deleted': plans.where((state) => !state.exists).map((state) => state.relative).toList(),
                },
            );
        });

        registry.register(_lsSchema, (raw) async {
            final args = ToolArgs(raw);
            final relative = args.text('path') ?? '.';
            final dir = Directory(guard.safeResolve(relative));
            if (!await dir.exists()) return ToolResult.error('Directory not found: $relative');

            final entries = <Map<String, dynamic>>[];
            await for (final entity in dir.list(followLinks: false)) {
                final isDir = entity is Directory;
                final stat = await entity.stat();
                entries.add({
                    'name': p.basename(entity.path),
                    'type': isDir ? 'directory' : 'file',
                    if (!isDir) 'size': stat.size,
                });
            }
            entries.sort(_compareEntries);

            final buffer = StringBuffer();
            for (final entry in entries) {
                final marker = entry['type'] == 'directory' ? '[dir] ' : '      ';
                buffer.writeln('$marker${entry['name']}');
            }

            return ToolResult.text(buffer.toString(), structured: {
                'path': relative,
                'count': entries.length,
                'entries': entries,
            });
        });
    }

    static int _compareEntries(Map<String, dynamic> left, Map<String, dynamic> right) {
        final leftIsDir = left['type'] == 'directory';
        final rightIsDir = right['type'] == 'directory';
        if (leftIsDir != rightIsDir) return leftIsDir ? -1 : 1;
        return (left['name'] as String).compareTo(right['name'] as String);
    }

    static int _countOccurrences(String content, String needle) {
        if (needle.isEmpty) return 0;
        var count = 0;
        var index = content.indexOf(needle);
        while (index != -1) {
            count++;
            index = content.indexOf(needle, index + needle.length);
        }
        return count;
    }

    static String _normalizeNewlines(String value) {
        return value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    }

    static String _preserveNewlines(String original, String normalized) {
        final target = original.contains('\r\n') ? '\r\n' : '\n';
        if (target == '\n') return normalized;
        return normalized.replaceAll('\n', '\r\n');
    }

    static Future<_NumberedText> _renderNumbered(File file, int offset, int limit) async {
        final lines = await file.readAsLines();
        final startIndex = (offset - 1).clamp(0, lines.length);
        final endIndex = (startIndex + limit).clamp(0, lines.length);
        final slice = lines.sublist(startIndex, endIndex);

        final buffer = StringBuffer();
        for (var index = 0; index < slice.length; index++) {
            buffer.writeln('${startIndex + index + 1}| ${slice[index]}');
        }
        return _NumberedText(
            text: buffer.toString(),
            startLine: startIndex + 1,
            lineCount: slice.length,
            totalLines: lines.length,
        );
    }

    static const _readSchema = ToolSchema(
        name: 'read',
        title: 'Read files',
        description:
            'Read one file with path, or several files with paths (max 20). Returns numbered lines. Read before changing code.',
        inputSchema: {
            'type': 'object',
            'properties': {
                'path': {'type': 'string', 'description': 'One path relative to project root'},
                'paths': {
                    'type': 'array',
                    'items': {'type': 'string'},
                    'description': 'Several paths relative to project root (max 20)',
                },
                'offset': {'type': 'integer', 'description': '1-based first line', 'default': 1},
                'limit': {'type': 'integer', 'description': 'Max lines per file'},
            },
        },
        outputSchema: {
            'type': 'object',
            'properties': {
                'text': {'type': 'string', 'description': 'Numbered file content'},
                'files': {'type': 'array'},
                'truncated': {'type': 'boolean'},
            },
            'required': ['text', 'files', 'truncated'],
        },
        annotations: ToolAnnotations.readOnly,
        meta: {
            'openai/toolInvocation/invoking': '正在读取文件…',
            'openai/toolInvocation/invoked': '已读取文件',
        },
    );

    static const _applyPatchSchema = ToolSchema(
        name: 'apply_patch',
        title: 'Apply patch',
        description:
            'Apply validated file changes transactionally. Multiple edits to the same file are composed in order; oldText replaces one exact snippet, omit oldText to create/overwrite, and set delete=true to delete. Writes are verified and commit failures are rolled back.',
        inputSchema: {
            'type': 'object',
            'properties': {
                'edits': {
                    'type': 'array',
                    'items': {
                        'type': 'object',
                        'properties': {
                            'path': {'type': 'string'},
                            'oldText': {'type': 'string'},
                            'newText': {'type': 'string'},
                            'delete': {'type': 'boolean', 'default': false},
                        },
                        'required': ['path'],
                    },
                },
            },
            'required': ['edits'],
        },
        outputSchema: {
            'type': 'object',
            'properties': {
                'text': {'type': 'string'},
                'files': {'type': 'array', 'items': {'type': 'string'}},
                'deleted': {'type': 'array', 'items': {'type': 'string'}},
            },
            'required': ['text', 'files', 'deleted'],
        },
        annotations: ToolAnnotations.write,
        meta: {
            'openai/toolInvocation/invoking': '正在应用补丁…',
            'openai/toolInvocation/invoked': '已应用补丁',
        },
    );

    static const _lsSchema = ToolSchema(
        name: 'ls',
        title: 'List directory',
        description: 'List a single directory without recursion.',
        inputSchema: {
            'type': 'object',
            'properties': {
                'path': {'type': 'string', 'default': '.'},
            },
        },
        outputSchema: {
            'type': 'object',
            'properties': {
                'text': {'type': 'string'},
                'path': {'type': 'string'},
                'count': {'type': 'integer'},
                'entries': {'type': 'array'},
            },
            'required': ['text', 'path', 'count', 'entries'],
        },
        annotations: ToolAnnotations.readOnly,
        meta: {
            'openai/toolInvocation/invoking': '正在列出目录…',
            'openai/toolInvocation/invoked': '已列出目录',
        },
    );
}

class _NumberedText {
    final String text;
    final int startLine;
    final int lineCount;
    final int totalLines;

    _NumberedText({
        required this.text,
        required this.startLine,
        required this.lineCount,
        required this.totalLines,
    });
}

class _PatchState {
    final File file;
    final String relative;
    final bool originalExists;
    final String? originalContent;

    bool exists;
    String? content;

    _PatchState._({
        required this.file,
        required this.relative,
        required this.originalExists,
        required this.originalContent,
        required this.exists,
        required this.content,
    });

    static Future<_PatchState> load(File file, String relative) async {
        final exists = await file.exists();
        final content = exists ? await file.readAsString() : null;
        return _PatchState._(
            file: file,
            relative: relative,
            originalExists: exists,
            originalContent: content,
            exists: exists,
            content: content,
        );
    }

    void overwrite(String value) {
        exists = true;
        content = value;
    }

    void delete() {
        exists = false;
        content = null;
    }

    Future<void> commit() async {
        if (!exists) {
            if (await file.exists()) await file.delete();
            if (await file.exists()) throw FileSystemException('delete verification failed', file.path);
            return;
        }

        await file.parent.create(recursive: true);
        await file.writeAsString(content!, flush: true);
        final written = await file.readAsString();
        if (written != content) {
            throw FileSystemException('write verification failed', file.path);
        }
    }

    Future<void> rollback() async {
        if (!originalExists) {
            if (await file.exists()) await file.delete();
            return;
        }

        await file.parent.create(recursive: true);
        await file.writeAsString(originalContent!, flush: true);
        final restored = await file.readAsString();
        if (restored != originalContent) {
            throw FileSystemException('rollback verification failed', file.path);
        }
    }
}
