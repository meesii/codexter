import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

/// 把所有路径限制在工作区根目录内，防止 ChatGPT 读写越权
class PathGuard {
  final String projectRoot;

  PathGuard(this.projectRoot);

  String resolve(String relativePath) {
    final cleaned = relativePath.replaceAll('\\', '/').trim();
    if (cleaned.isEmpty) return p.normalize(projectRoot);
    if (p.isAbsolute(cleaned)) return p.normalize(cleaned);
    return p.normalize(p.join(projectRoot, cleaned));
  }

  bool isInsideProject(String absolutePath) {
    final root = p.canonicalize(projectRoot);
    final target = p.canonicalize(absolutePath);
    if (target == root) return true;
    return p.isWithin(root, target);
  }

  void assertInsideProject(String absolutePath) {
    if (!isInsideProject(absolutePath)) {
      throw PathEscapeError(absolutePath, projectRoot);
    }
  }

  /// 解析并校验，工具里最常用的组合动作
  String safeResolve(String relativePath) {
    final resolved = resolve(relativePath);
    assertInsideProject(resolved);
    return resolved;
  }

  String relativePath(String absolutePath) {
    return p.relative(absolutePath, from: projectRoot).replaceAll('\\', '/');
  }
}

class PathEscapeError implements Exception {
  final String path;
  final String projectRoot;

  PathEscapeError(this.path, this.projectRoot);

  @override
  String toString() => 'Path escapes project root ($projectRoot): $path';
}

/// 子进程/文件的字节解码，优先 UTF-8，失败时退回 Latin-1 避免整段乱码
class TextDecode {
  const TextDecode._();

  static String bytes(Object? raw) {
    if (raw == null) return '';
    if (raw is String) return raw;
    if (raw is! List) return '$raw';
    final data = raw.cast<int>();
    if (data.isEmpty) return '';
    try {
      return utf8.decode(data);
    } catch (_) {
      return latin1.decode(data, allowInvalid: true);
    }
  }
}

class FsProbe {
  const FsProbe._();

  static Future<bool> exists(String path) async {
    if (await File(path).exists()) return true;
    return Directory(path).exists();
  }

  static Future<bool> isDirectory(String path) async {
    return Directory(path).exists();
  }

  /// 需要跳过的重目录，遍历类工具共用
  static const skipDirNames = <String>{
    '.git',
    'node_modules',
    '.dart_tool',
    'build',
    'dist',
    'out',
    '.next',
    '.venv',
    'venv',
    '__pycache__',
    'target',
    '.idea',
    '.gradle',
    'Pods',
  };

  static bool shouldSkipPath(String relativePath) {
    final segments = relativePath.split('/');
    return segments.any(skipDirNames.contains);
  }
}
