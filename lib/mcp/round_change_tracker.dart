import 'dart:io';
import 'package:path/path.dart' as p;

/// 一轮对话内由写入工具造成的文件净变更。
class RoundFileChange {
  final String path;
  final String status;
  final int additions;
  final int deletions;

  const RoundFileChange({
    required this.path,
    required this.status,
    required this.additions,
    required this.deletions,
  });

  Map<String, dynamic> toJson() => {
    'path': path,
    'status': status,
    'additions': additions,
    'deletions': deletions,
  };
}

class RoundChangeSet {
  final List<RoundFileChange> files;

  const RoundChangeSet(this.files);

  int get additions => files.fold(0, (sum, item) => sum + item.additions);
  int get deletions => files.fold(0, (sum, item) => sum + item.deletions);

  Map<String, dynamic> toJson() => {
    'count': files.length,
    'additions': additions,
    'deletions': deletions,
    'files': files.map((item) => item.toJson()).toList(growable: false),
  };
}

/// 以 summary 为轮次边界，记录 apply_patch 首次修改前与最后一次提交后的内容。
///
/// 这里只追踪明确经过本 MCP 写入工具的文件，不扫描 Git 或整个工作区，避免把
/// 用户手工编辑、构建产物等变化误判为 ChatGPT 修改。
class RoundChangeTracker {
  final Map<String, _TrackedFile> _files = {};

  void recordCommitted({
    required String relativePath,
    required String absolutePath,
    required bool originalExists,
    required String? originalContent,
    required bool finalExists,
    required String? finalContent,
  }) {
    final key = _pathKey(absolutePath);
    final current = _files[key];
    if (current == null) {
      _files[key] = _TrackedFile(
        path: p.posix.normalize(relativePath.replaceAll('\\', '/')),
        originalExists: originalExists,
        originalContent: originalContent,
        finalExists: finalExists,
        finalContent: finalContent,
      );
      return;
    }

    current
      ..finalExists = finalExists
      ..finalContent = finalContent;
  }

  /// 生成当前轮次的净变更并清空状态，供下一轮重新记录基线。
  RoundChangeSet takeAndReset() {
    final changes = <RoundFileChange>[];
    for (final tracked in _files.values) {
      final change = _buildChange(tracked);
      if (change != null) changes.add(change);
    }
    _files.clear();
    changes.sort((left, right) => left.path.compareTo(right.path));
    return RoundChangeSet(List.unmodifiable(changes));
  }

  static RoundFileChange? _buildChange(_TrackedFile tracked) {
    final before = tracked.originalContent ?? '';
    final after = tracked.finalContent ?? '';
    if (tracked.originalExists == tracked.finalExists &&
        _normalizeText(before) == _normalizeText(after)) {
      return null;
    }

    final status = !tracked.originalExists
        ? 'added'
        : !tracked.finalExists
        ? 'deleted'
        : 'modified';
    final stats = _lineDiff(before, after);
    return RoundFileChange(
      path: tracked.path,
      status: status,
      additions: stats.$1,
      deletions: stats.$2,
    );
  }

  /// 返回 (新增行, 删除行)。使用 Myers 最短编辑距离，适合代码文件的局部修改。
  static (int, int) _lineDiff(String before, String after) {
    final left = _lines(before);
    final right = _lines(after);

    var prefix = 0;
    final commonLength = left.length < right.length
        ? left.length
        : right.length;
    while (prefix < commonLength && left[prefix] == right[prefix]) {
      prefix++;
    }

    var leftEnd = left.length;
    var rightEnd = right.length;
    while (leftEnd > prefix &&
        rightEnd > prefix &&
        left[leftEnd - 1] == right[rightEnd - 1]) {
      leftEnd--;
      rightEnd--;
    }

    final leftCount = leftEnd - prefix;
    final rightCount = rightEnd - prefix;
    if (leftCount == 0) return (rightCount, 0);
    if (rightCount == 0) return (0, leftCount);

    final distance = _myersDistance(
      left,
      right,
      leftStart: prefix,
      leftCount: leftCount,
      rightStart: prefix,
      rightCount: rightCount,
    );
    final common = (leftCount + rightCount - distance) ~/ 2;
    return (rightCount - common, leftCount - common);
  }

  static int _myersDistance(
    List<String> left,
    List<String> right, {
    required int leftStart,
    required int leftCount,
    required int rightStart,
    required int rightCount,
  }) {
    final max = leftCount + rightCount;
    final offset = max;
    final furthest = List<int>.filled(max * 2 + 1, 0);

    for (var distance = 0; distance <= max; distance++) {
      for (var diagonal = -distance; diagonal <= distance; diagonal += 2) {
        final index = offset + diagonal;
        int x;
        if (diagonal == -distance ||
            (diagonal != distance &&
                furthest[index - 1] < furthest[index + 1])) {
          x = furthest[index + 1];
        } else {
          x = furthest[index - 1] + 1;
        }

        var y = x - diagonal;
        while (x < leftCount &&
            y < rightCount &&
            left[leftStart + x] == right[rightStart + y]) {
          x++;
          y++;
        }
        furthest[index] = x;
        if (x >= leftCount && y >= rightCount) return distance;
      }
    }
    return max;
  }

  static List<String> _lines(String text) {
    if (text.isEmpty) return const [];
    final lines = _normalizeText(text).split('\n');
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
    return lines;
  }

  static String _normalizeText(String value) =>
      value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  static String _pathKey(String value) {
    final normalized = p.normalize(value);
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }
}

class _TrackedFile {
  final String path;
  final bool originalExists;
  final String? originalContent;
  bool finalExists;
  String? finalContent;

  _TrackedFile({
    required this.path,
    required this.originalExists,
    required this.originalContent,
    required this.finalExists,
    required this.finalContent,
  });
}
