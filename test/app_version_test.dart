import 'package:crisp_cloud/utils/app_version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatAppVersion', () {
    test('shows version and build without a git hash', () {
      expect(
        formatAppVersion(version: '1.1.0', buildNumber: '10'),
        'Version 1.1.0 (build 10)',
      );
    });

    test('shows the commit hash next to the build number', () {
      expect(
        formatAppVersion(
          version: '1.1.0',
          buildNumber: '10',
          gitHash: 'b750d35',
        ),
        'Version 1.1.0 (build 10, b750d35)',
      );
    });

    test('trims a full hash to twelve characters', () {
      expect(
        formatAppVersion(
          version: '1.1.0',
          buildNumber: '10',
          gitHash: 'b750d35a1b2c3d4e5f60718293a4b5c6d7e8f901',
        ),
        'Version 1.1.0 (build 10, b750d35a1b2c)',
      );
    });

    test('omits missing or zero metadata', () {
      expect(
        formatAppVersion(version: '2.0.0', buildNumber: '0'),
        'Version 2.0.0',
      );
    });
  });
}
