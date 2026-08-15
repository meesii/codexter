import 'package:codexter/mcp/round_change_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RoundChangeTracker', () {
    test('统计单个文件的净新增和删除行', () {
      final tracker = RoundChangeTracker();
      tracker.recordCommitted(
        relativePath: 'lib/example.dart',
        absolutePath: r'C:\project\lib\example.dart',
        originalExists: true,
        originalContent: 'a\nb\nc\n',
        finalExists: true,
        finalContent: 'a\nx\nc\ny\n',
      );

      final result = tracker.takeAndReset();
      expect(result.files, hasLength(1));
      expect(result.files.single.path, 'lib/example.dart');
      expect(result.files.single.status, 'modified');
      expect(result.additions, 2);
      expect(result.deletions, 1);
    });

    test('同一文件多次提交只比较首个基线和最终内容', () {
      final tracker = RoundChangeTracker();
      const absolute = r'C:\project\lib\example.dart';
      tracker.recordCommitted(
        relativePath: 'lib/example.dart',
        absolutePath: absolute,
        originalExists: true,
        originalContent: 'a\nb\n',
        finalExists: true,
        finalContent: 'a\nx\nb\n',
      );
      tracker.recordCommitted(
        relativePath: 'lib/example.dart',
        absolutePath: absolute,
        originalExists: true,
        originalContent: 'a\nx\nb\n',
        finalExists: true,
        finalContent: 'a\ny\nb\n',
      );

      final result = tracker.takeAndReset();
      expect(result.files, hasLength(1));
      expect(result.additions, 1);
      expect(result.deletions, 0);
    });

    test('一轮内完全恢复原内容时不展示文件', () {
      final tracker = RoundChangeTracker();
      const absolute = r'C:\project\lib\example.dart';
      tracker.recordCommitted(
        relativePath: 'lib/example.dart',
        absolutePath: absolute,
        originalExists: true,
        originalContent: 'a\nb\n',
        finalExists: true,
        finalContent: 'a\nx\nb\n',
      );
      tracker.recordCommitted(
        relativePath: 'lib/example.dart',
        absolutePath: absolute,
        originalExists: true,
        originalContent: 'a\nx\nb\n',
        finalExists: true,
        finalContent: 'a\nb\n',
      );

      expect(tracker.takeAndReset().files, isEmpty);
    });

    test('支持新增和删除文件', () {
      final tracker = RoundChangeTracker();
      tracker.recordCommitted(
        relativePath: r'lib\new.dart',
        absolutePath: r'C:\project\lib\new.dart',
        originalExists: false,
        originalContent: null,
        finalExists: true,
        finalContent: 'one\ntwo\n',
      );
      tracker.recordCommitted(
        relativePath: 'lib/old.dart',
        absolutePath: r'C:\project\lib\old.dart',
        originalExists: true,
        originalContent: 'old\n',
        finalExists: false,
        finalContent: null,
      );

      final result = tracker.takeAndReset();
      expect(result.files, hasLength(2));
      expect(result.additions, 2);
      expect(result.deletions, 1);
      expect(result.files.first.path, 'lib/new.dart');
      expect(result.files.first.status, 'added');
      expect(result.files.last.status, 'deleted');
    });

    test('takeAndReset 会清空上一轮状态', () {
      final tracker = RoundChangeTracker();
      tracker.recordCommitted(
        relativePath: 'a.dart',
        absolutePath: r'C:\project\a.dart',
        originalExists: false,
        originalContent: null,
        finalExists: true,
        finalContent: 'a\n',
      );

      expect(tracker.takeAndReset().files, hasLength(1));
      expect(tracker.takeAndReset().files, isEmpty);
    });
  });
}
