import 'dart:ui';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

void main() {
  test('specialized report diagnostics translate in every locale', () {
    const cases = [
      'ReportFontException: Font collections (.ttc) are not supported; use a single .ttf',
      'ReportFontException: CFF/OpenType outlines (.otf) cannot be embedded; use a TrueType .ttf',
      'ReportFontException: The font license forbids embedding (restricted fsType)',
      'ReportPackageException: template.json: Invalid template id "my{0}"',
      'ReportPackageException: template.json: Unknown category "my{0}"',
      'ReportShapeException: Unknown shape layer version 17',
      'ReportShapeException: Invalid GeoJSON: external {0}',
      'ReportShapeException: Not a shapefile',
    ];
    for (final language in ['de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar']) {
      final strings = ReportDesignerStrings.forLocale(Locale(language));
      for (final input in cases) {
        final result = strings.diagnostic(input);
        expect(result, isNot(input), reason: '$language $input');
        if (input.contains('my{0}')) expect(result, contains('my{0}'));
        if (input.contains('external {0}')) {
          expect(result, contains('external {0}'));
        }
        if (input.contains('17')) expect(result, contains('17'));
      }
    }
  });

  test(
    'data imports and embedded asset entries localize without losing details',
    () {
      for (final language in ['de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar']) {
        final strings = ReportDesignerStrings.forLocale(Locale(language));
        for (final input in [
          'ReportDataException: Unterminated quoted CSV cell',
          'ReportDataException: CSV has no header row',
          'ReportDataException: Empty data path',
          'ReportDataException: JSON data must be an object',
          'ReportPackageException: data/sample.json: Invalid JSON: external {0}',
          'ReportPackageException: fonts/my:font.ttf: Font is missing its glyf table',
        ]) {
          final result = strings.diagnostic(input);
          expect(result, isNot(input), reason: '$language $input');
          if (input.contains('external {0}')) {
            expect(result, contains('external {0}'));
          }
          if (input.contains('my:font.ttf')) {
            expect(result, contains('my:font.ttf'));
          }
        }
        expect(
          strings.assetNotice('Invalid JSON: external {0}'),
          contains('external {0}'),
        );
        expect(
          strings.assetNotice('Unterminated quoted CSV cell'),
          isNot('Unterminated quoted CSV cell'),
        );
      }
    },
  );

  test('data import status changes language without losing parser details', () {
    final controller = ReportDesignerController();
    addTearDown(controller.dispose);
    expect(controller.importDataText('data.csv', 'name\n"unfinished'), isFalse);
    final english = controller.notice;
    controller.strings = ReportDesignerStrings.forLocale(const Locale('de'));
    expect(controller.localizedNotice, isNot(english));
    controller.strings = ReportDesignerStrings.english;
    expect(controller.localizedNotice, english);
  });

  test('font wrappers and glyph errors retain names and nested details', () {
    for (final language in ['de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar']) {
      final strings = ReportDesignerStrings.forLocale(Locale(language));
      const wrapped =
          'ReportPackageException: Font "Family {1}" (bold): Font file is truncated';
      final translated = strings.diagnostic(wrapped);
      expect(translated, contains('Family {1}'));
      expect(translated, contains('bold'));
      expect(translated, isNot(contains('Font file is truncated')));
      final external = strings.diagnostic(
        'ReportPackageException: Font "Family {1}" (bold): remote {0}',
      );
      expect(external, contains('remote {0}'));
      final glyph = strings.diagnostic(
        'ReportFontException: Bold face of "Family {1}" has no glyf table (CFF/OTF outlines cannot be embedded)',
      );
      expect(glyph, contains('Family {1}'));
      expect(glyph, contains('glyf'));
      expect(glyph, isNot(contains('has no glyf table')));
      final embed = strings.assetNotice(
        'Could not embed Family {1}: Font file is truncated',
      );
      expect(embed, contains('Family {1}'));
      expect(embed, isNot(contains('Font file is truncated')));
      final invalid = strings.diagnostic(
        'ReportFontException: "Family {1}" cannot be used as a family name',
      );
      expect(invalid, contains('Family {1}'));
      expect(invalid, isNot(contains('cannot be used')));
    }
  });

  test(
    'compound font import notices preserve filenames and update with locale',
    () async {
      final controller = ReportDesignerController(
        fontPicker: () async => [
          (name: 'one · two: {0}.ttf', bytes: Uint8List(0)),
          (name: 'three.ttf', bytes: Uint8List(0)),
        ],
      );
      addTearDown(controller.dispose);
      await controller.importFonts();
      final legacy = controller.notice!;
      controller.strings = ReportDesignerStrings.forLocale(const Locale('de'));
      final german = controller.localizedNotice!;
      expect(german, contains('one · two: {0}.ttf'));
      expect(german, contains('three.ttf'));
      expect(german, isNot(legacy));
      controller.strings = ReportDesignerStrings.english;
      expect(controller.localizedNotice, legacy);
    },
  );

  test(
    'package and asset errors translate without changing supplied values',
    () {
      const cases = <String, String>{
        'ReportPackageException: Damaged .qrep archive: external {1}':
            'external {1}',
        'ReportPackageException: Missing report.xml': 'report.xml',
        'ReportPackageException: images/{0}.png exceeds 12 MB':
            'images/{0}.png',
        'ReportPackageException: images/{0}.png is not PNG or JPEG':
            'images/{0}.png',
        'ReportPackageException: Invalid font family "Custom {1}"':
            'Custom {1}',
        'ReportPackageException: Cannot read file/{0}: external {1}':
            'external {1}',
        'ReportFontException: Font is missing its glyf table': 'glyf',
      };
      for (final language in ['de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar']) {
        final strings = ReportDesignerStrings.forLocale(Locale(language));
        for (final entry in cases.entries) {
          final actual = strings.diagnostic(entry.key);
          expect(actual, isNot(entry.key), reason: '$language ${entry.key}');
          expect(actual, contains(entry.value), reason: language);
        }
        const unknown = 'ReportPackageException: external unknown failure';
        expect(strings.diagnostic(unknown), unknown);
        final notice = strings.assetNotice(
          'Custom {1} has no regular or bold TrueType face',
        );
        expect(notice, contains('Custom {1}'));
        expect(
          notice,
          isNot('Custom {1} has no regular or bold TrueType face'),
        );
        expect(
          strings.assetNotice('myfont.ttf: Not a TrueType font'),
          contains('myfont.ttf'),
        );
        expect(
          strings.assetNotice('external unknown failure'),
          'external unknown failure',
        );
      }
    },
  );
}
