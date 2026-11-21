import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/src/l10n/office_plural.dart';

void main() {
  test('English counts use singular for one', () {
    expect(officeFindings(1), '1 finding');
    expect(officeFindings(9), '9 findings');
    expect(officeIssues(1, writing: true), '1 writing issue');
    expect(officeIssues(0), '0 issues');
    expect(officeChanges(1), '1 change');
    expect(officeParagraphs(1), '1 paragraph');
    expect(officeCount(1, 'insertion'), '1 insertion');
    expect(officeCount(2, 'insertion'), '2 insertions');
  });

  test('Arabic counts use the six plural categories', () {
    expect(officeFindings(0, arabic: true), 'لا توجد نتائج');
    expect(officeFindings(1, arabic: true), 'نتيجة واحدة');
    expect(officeFindings(2, arabic: true), 'نتيجتان');
    expect(officeFindings(3, arabic: true), '3 نتائج');
    expect(officeFindings(11, arabic: true), '11 نتيجة');
    expect(officeChanges(11, arabic: true), '11 تغييرًا');
    expect(officeChanges(100, arabic: true), '100 تغيير');
    expect(officeIssues(2, arabic: true), 'ملاحظتان');
    expect(officeParagraphs(4, arabic: true), '4 فقرات');
  });
}
