import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

void main() {
  test('validation notices translate while retaining names and values', () {
    const messages = [
      '"x{1}" is not a valid name: start with a letter or _, then use letters, digits or _',
      'Another element is already named "x{1}"',
      '"x{1}" is not a valid name: use letters, digits and _, and dots for folders (stats.sum)',
      'Another variable is already named "x{1}"',
      '"x{1}" clashes with "other{0}": a name cannot be both a variable and a folder',
      '"x{1}" is calculated: edit its formula instead',
      '"x{1}" is not a valid number',
      '"x{1}" is not a valid boolean',
      '"x{1}" is not a valid date',
      '"x{1}" is not a valid column name: start with a letter or _, then use letters, digits or _',
      'A column named "x{1}" already exists',
      '"x{1}" is not a valid table name: use letters, digits or _, with dots between levels (customer.name)',
      '"x{1}" already exists',
    ];
    for (final language in ['de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar']) {
      final strings = ReportDesignerStrings.forLocale(Locale(language));
      for (final message in messages) {
        final translated = strings.assetNotice(message);
        expect(translated, isNot(message), reason: '$language $message');
        expect(translated, contains('x{1}'), reason: language);
        if (message.contains('other{0}')) {
          expect(translated, contains('other{0}'), reason: language);
        }
      }
      expect(
        strings.assetNotice('unrecognized external message'),
        'unrecognized external message',
      );
    }
    final german = ReportDesignerStrings.forLocale(const Locale('de'));
    expect(german.assetNotice('"x" is not a valid number'), contains('Zahl'));
    expect(
      german.assetNotice('"x" is not a valid boolean'),
      contains('Boolescher Wert'),
    );
    expect(german.assetNotice('"x" is not a valid date'), contains('Datum'));
  });

  test('font embedding status localizes face labels and preserves family', () {
    const family = 'Family {0} · name';
    for (final language in ['de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar']) {
      final strings = ReportDesignerStrings.forLocale(Locale(language));
      final status = strings.embeddedFontNotice(family, [
        'Regular',
        'Bold',
      ], '4 KB');
      expect(status, contains(family));
      expect(status, contains('4 KB'));
      expect(status, isNot(contains('Regular')));
      expect(status, isNot(contains('Bold')));
    }
  });

  test('data validation notice updates when locale changes', () {
    final controller = ReportDesignerController();
    addTearDown(controller.dispose);
    expect(controller.addDataTable('9bad'), isFalse);
    final english = controller.notice!;
    controller.strings = ReportDesignerStrings.forLocale(const Locale('de'));
    expect(controller.localizedNotice, contains('9bad'));
    expect(controller.localizedNotice, isNot(english));
    controller.strings = ReportDesignerStrings.english;
    expect(controller.localizedNotice, english);
  });
}
