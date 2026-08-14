import 'package:codexter/utils/glob_match.dart';
import 'package:codexter/utils/path_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
    group('GlobMatch', () {
        test('** 跨目录匹配', () {
            expect(GlobMatch.matches('**/*.dart', 'lib/ui/pages/home_page.dart'), isTrue);
            expect(GlobMatch.matches('**/*.dart', 'main.dart'), isTrue);
            expect(GlobMatch.matches('**/*.dart', 'lib/main.ts'), isFalse);
        });

        test('* 不跨目录', () {
            expect(GlobMatch.matches('lib/*.dart', 'lib/main.dart'), isTrue);
            expect(GlobMatch.matches('lib/*.dart', 'lib/ui/main.dart'), isFalse);
        });

        test('花括号可选项', () {
            expect(GlobMatch.matches('**/*.{ts,tsx}', 'src/app.tsx'), isTrue);
            expect(GlobMatch.matches('**/*.{ts,tsx}', 'src/app.js'), isFalse);
        });

        test('裸文件名自动补前缀', () {
            expect(GlobMatch.matches(GlobMatch.normalize('*.dart'), 'lib/a/b.dart'), isTrue);
        });
    });

    group('PathGuard', () {
        final guard = PathGuard(r'C:\Projects\demo');

        test('相对路径解析在根目录内', () {
            final resolved = guard.resolve('lib/main.dart');
            expect(guard.isInsideProject(resolved), isTrue);
        });

        test('.. 越权被拦截', () {
            expect(() => guard.safeResolve('../secret.txt'), throwsA(isA<PathEscapeError>()));
        });

        test('同前缀的兄弟目录不算在内', () {
            expect(guard.isInsideProject(r'C:\Projects\demo-evil\a.txt'), isFalse);
        });

        test('根目录自身视为合法', () {
            expect(guard.isInsideProject(r'C:\Projects\demo'), isTrue);
        });
    });

    group('TextDecode', () {
        test('UTF-8 字节正确解码', () {
            const bytes = [228, 189, 160, 229, 165, 189];
            expect(TextDecode.bytes(bytes), '你好');
        });

        test('非法字节不抛异常', () {
            expect(TextDecode.bytes(const [0xC3, 0x28]), isNotEmpty);
        });
    });
}
