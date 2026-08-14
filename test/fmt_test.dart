import 'package:codexter/utils/fmt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('toolArgs prefers exec command content', () {
    expect(
      Fmt.toolArgs({'cmd': 'flutter analyze', 'workdir': '.'}),
      'flutter analyze',
    );
  });

  test('toolArgs summarizes apply patch paths', () {
    expect(
      Fmt.toolArgs({
        'edits': [
          {'path': 'lib/a.dart'},
          {'path': 'lib/b.dart'},
          {'path': 'lib/a.dart'},
        ],
      }),
      'lib/a.dart, lib/b.dart',
    );
  });
}
