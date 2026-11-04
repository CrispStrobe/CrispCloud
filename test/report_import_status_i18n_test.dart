import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

void main() {
  test('import status preserves table names across all languages', () {
    const table = 'Client {rows} · "sample"';
    for (final language in ['de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar']) {
      final strings = ReportDesignerStrings.forLocale(Locale(language));
      for (final n in [0, 1, 2, 5, 12]) {
        final status = strings.importedRows(n, table);
        expect(status, contains(table));
        expect(
          status,
          isNot(ReportDesignerStrings.english.importedRows(n, table)),
        );
      }
    }
  });

  test('import status updates on locale changes and keeps legacy notice', () {
    final controller = ReportDesignerController();
    addTearDown(controller.dispose);
    expect(
      controller.importDataText('clients.csv', 'name\nAlice\nBob'),
      isTrue,
    );
    final english = controller.notice!;
    expect(english, contains('2 rows'));
    controller.strings = ReportDesignerStrings.forLocale(const Locale('de'));
    expect(controller.localizedNotice, contains('2 Zeilen'));
    expect(controller.localizedNotice, contains('clients'));
    controller.strings = ReportDesignerStrings.english;
    expect(controller.localizedNotice, english);
  });
}
