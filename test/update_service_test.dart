import 'package:codexter/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppUpdateService.compareVersions', () {
    test('newer semantic version is greater', () {
      expect(
        AppUpdateService.compareVersions('1.2.0', '1.1.9'),
        greaterThan(0),
      );
    });

    test('missing segments are treated as zero', () {
      expect(AppUpdateService.compareVersions('1.0', '1.0.0'), 0);
    });

    test('v prefix and prerelease suffix do not break comparison', () {
      expect(
        AppUpdateService.compareVersions('v2.0.1-beta.1', '2.0.0'),
        greaterThan(0),
      );
    });
  });
}
