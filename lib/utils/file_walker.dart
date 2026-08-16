import 'dart:io';
import 'path_guard.dart';

class WalkedFile {
  final String relativePath;
  final File file;
  final int size;

  WalkedFile(this.relativePath, this.file, this.size);
}

/// 统一的目录遍历，自动跳过 node_modules/.git 等重目录并限制数量
class FileWalker {
  const FileWalker._();

  static const defaultMaxFiles = 20000;
  static const maxTextFileBytes = 2 * 1024 * 1024;

  static Future<List<WalkedFile>> collect({
    required String rootPath,
    required PathGuard guard,
    int maxFiles = defaultMaxFiles,
    bool skipHeavyDirs = true,
    bool Function(String relativePath)? accept,
  }) async {
    final results = <WalkedFile>[];
    final rootDir = Directory(rootPath);
    if (!await rootDir.exists()) return results;

    await for (final entity in rootDir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relative = guard.relativePath(entity.path);
      if (skipHeavyDirs && FsProbe.shouldSkipPath(relative)) continue;
      if (accept != null && !accept(relative)) continue;

      int size;
      try {
        size = await entity.length();
      } catch (_) {
        continue;
      }
      results.add(WalkedFile(relative, entity, size));
      if (results.length >= maxFiles) break;
    }

    results.sort((left, right) => left.relativePath.compareTo(right.relativePath));
    return results;
  }

  static Future<List<String>> collectDirs({
    required String rootPath,
    required PathGuard guard,
    int maxDepth = 2,
  }) async {
    final results = <String>[];
    final rootDir = Directory(rootPath);
    if (!await rootDir.exists()) return results;

    Future<void> walk(Directory dir, int depth) async {
      if (depth > maxDepth) return;
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final relative = guard.relativePath(entity.path);
        if (FsProbe.shouldSkipPath(relative)) continue;
        results.add(relative);
        await walk(entity, depth + 1);
      }
    }

    await walk(rootDir, 1);
    results.sort();
    return results;
  }

  static Future<List<String>> readLinesSafe(File file) async {
    try {
      if (await file.length() > maxTextFileBytes) return const [];
      return await file.readAsLines();
    } catch (_) {
      return const [];
    }
  }
}
