// test/path_access_test.dart
//
// Regression tests for security-scoped path containment (macOS bookmark
// paths may carry trailing slashes or differ in case).

import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/utils/path_access.dart';

void main() {
  test('normalizeAccessPath strips trailing slashes and normalizes separators', () {
    expect(normalizeAccessPath('/Volumes/backups/'), '/Volumes/backups');
    expect(normalizeAccessPath('/Volumes/backups///'), '/Volumes/backups');
    expect(normalizeAccessPath(r'C:\Users\test\'), 'C:/Users/test');
    expect(normalizeAccessPath('/'), '/');
  });

  test('isSameOrUnderPath accepts the directory and its children', () {
    expect(
      isSameOrUnderPath('/Volumes/backups', '/Volumes/backups',
          caseInsensitive: false),
      isTrue,
    );
    expect(
      isSameOrUnderPath('/Volumes/backups/file.zip', '/Volumes/backups',
          caseInsensitive: false),
      isTrue,
    );
    expect(
      isSameOrUnderPath('/Volumes/backups/file.zip', '/Volumes/backups/',
          caseInsensitive: false),
      isTrue,
    );
  });

  test('isSameOrUnderPath rejects sibling paths with the same prefix', () {
    expect(
      isSameOrUnderPath('/Volumes/backups2/file.zip', '/Volumes/backups',
          caseInsensitive: false),
      isFalse,
    );
    expect(
      isSameOrUnderPath('/Volumes', '/Volumes/backups', caseInsensitive: false),
      isFalse,
    );
  });

  test('isSameOrUnderPath can compare case-insensitively', () {
    expect(
      isSameOrUnderPath('/volumes/BACKUPS/File.ZIP', '/Volumes/backups',
          caseInsensitive: true),
      isTrue,
    );
    expect(
      isSameOrUnderPath('/volumes/BACKUPS/File.ZIP', '/Volumes/backups',
          caseInsensitive: false),
      isFalse,
    );
  });
}
