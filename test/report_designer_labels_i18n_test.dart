import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

void main() {
  test('element kinds localize while preserving document names', () {
    final elements = <ReportElement>[
      ReportTextElement(name: 'Name "{0}"'),
      ReportCrosstabElement(name: 'Crosstab custom'),
      ReportSubreportElement(name: 'Subreport custom'),
    ];
    const english = ReportDesignerStrings.english;
    for (final language in ['de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar']) {
      final strings = ReportDesignerStrings.forLocale(Locale(language));
      for (final element in elements) {
        final label = strings.elementTitle(element);
        expect(label, contains('"${element.name}"'));
        // 'Text' is a valid identical word in several supported languages.
        if (element is! ReportTextElement) {
          expect(label, isNot(english.elementTitle(element)), reason: language);
        }
      }
    }
  });

  test('default fields localize without modifying a custom Fields table', () {
    final strings = ReportDesignerStrings.forLocale(const Locale('de'));
    expect(
      strings.inspectorTitle(
        'Data: Fields',
        objectSelected: false,
        dataFields: true,
      ),
      'Daten: Felder',
    );
    expect(
      strings.inspectorTitle(
        'Data: Fields',
        objectSelected: false,
        dataFields: false,
      ),
      'Daten: Fields',
    );
  });

  test('compound font face names localize in all languages', () {
    for (final language in ['de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar']) {
      final strings = ReportDesignerStrings.forLocale(Locale(language));
      final labels = strings.fontFaces('Regular + Italic + Bold Italic');
      expect(labels, isNot(contains('Regular')), reason: language);
      expect(labels, isNot(contains('Bold Italic')), reason: language);
      expect(labels.split(' + '), hasLength(3));
    }
  });
}
