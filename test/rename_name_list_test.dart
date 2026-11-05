import 'package:crisp_cloud/services/rename_name_list.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('UTF-8 BOM and CRLF keep names and order intact', () {
    expect(
      parseRenameNameList('\uFEFFtwo.txt\r\n one.txt\r\n', expectedCount: 2),
      ['two.txt', ' one.txt'],
    );
  });

  test('wrong counts and blank rows cannot shift the mapping', () {
    for (final input in ['a.txt', 'a.txt\nb.txt\nc.txt', 'a.txt\n\nb.txt']) {
      expect(
        () => parseRenameNameList(input, expectedCount: 2),
        throwsFormatException,
      );
    }
  });

  test('paths, reserved names and trailing spaces are not silently repaired', () {
    for (final name in ['../a.txt', 'folder/a.txt', r'folder\a.txt', 'NUL', 'a ']) {
      expect(
        () => parseRenameNameList(name, expectedCount: 1),
        throwsFormatException,
      );
    }
  });

  test('duplicate basenames remain available for different source folders', () {
    expect(
      parseRenameNameList('report.txt\nreport.txt', expectedCount: 2),
      ['report.txt', 'report.txt'],
    );
  });
}
