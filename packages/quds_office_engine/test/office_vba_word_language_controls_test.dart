import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

const _range = 'ActiveDocument.Paragraphs(1).Range';

OfficeMacro _source(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    moduleName: 'WordLanguageControls',
    source: source,
  ),
);

OfficeMacro _plan(String body) => _source('Sub Main()\n$body\nEnd Sub');

void _reject(String body, String code) => expect(
  () => _plan(body),
  throwsA(
    isA<OfficeVbaCompileException>()
        .having((e) => e.code, 'code', code)
        .having((e) => e.moduleName, 'module', 'WordLanguageControls')
        .having((e) => e.line, 'line', greaterThan(0))
        .having((e) => e.column, 'column', greaterThan(0)),
  ),
);

// Independently authored from Microsoft's WdLanguageID table. The BCP47
// projection and supported subset are explicit dialect contracts, not
// differential observations from an installed Word host.
const _languages = <(String, int, String)>[
  ('wdEnglishUS', 1033, 'en-US'),
  ('wdEnglishUK', 2057, 'en-GB'),
  ('wdEnglishAUS', 3081, 'en-AU'),
  ('wdEnglishCanadian', 4105, 'en-CA'),
  ('wdEnglishNewZealand', 5129, 'en-NZ'),
  ('wdEnglishIreland', 6153, 'en-IE'),
  ('wdEnglishSouthAfrica', 7177, 'en-ZA'),
  ('wdGerman', 1031, 'de-DE'),
  ('wdGermanAustria', 3079, 'de-AT'),
  ('wdSwissGerman', 2055, 'de-CH'),
  ('wdFrench', 1036, 'fr-FR'),
  ('wdBelgianFrench', 2060, 'fr-BE'),
  ('wdFrenchCanadian', 3084, 'fr-CA'),
  ('wdSwissFrench', 4108, 'fr-CH'),
  ('wdItalian', 1040, 'it-IT'),
  ('wdSwissItalian', 2064, 'it-CH'),
  ('wdDutch', 1043, 'nl-NL'),
  ('wdBelgianDutch', 2067, 'nl-BE'),
  ('wdPortuguese', 2070, 'pt-PT'),
  ('wdPortugueseBrazil', 1046, 'pt-BR'),
  ('wdSpanishModernSort', 3082, 'es-ES'),
  ('wdMexicanSpanish', 2058, 'es-MX'),
  ('wdDanish', 1030, 'da-DK'),
  ('wdSwedish', 1053, 'sv-SE'),
  ('wdSwedishFinland', 2077, 'sv-FI'),
  ('wdNorwegianBokmol', 1044, 'nb-NO'),
  ('wdNorwegianNynorsk', 2068, 'nn-NO'),
  ('wdFinnish', 1035, 'fi-FI'),
  ('wdIcelandic', 1039, 'is-IS'),
  ('wdTurkish', 1055, 'tr-TR'),
];

void main() {
  for (final (name, id, language) in _languages) {
    for (final property in ['LanguageID', 'LanguageIDOther']) {
      test('$property accepts $name and its exact numeric value', () {
        for (final expression in [name, name.toUpperCase(), '$id', '$id.0']) {
          final plan = _plan('$_range.$property = $expression');
          expect(plan.steps.single.tool, 'docx.runFormat');
          expect(plan.steps.single.arguments, {
            'paragraph': 0,
            'language': language,
          });
          expect(OfficeMacro.parse(plan.encode()).toJson(), plan.toJson());
        }
      });
    }
  }

  test('normal and complex font writes retain order and separate fields', () {
    final plan = _plan('''
With $_range
  .LanguageID = wdGerman
  .Font.NameBi = "Amiri"
  .LanguageIDOther = wdEnglishUK
  .Font.Name = "Calibri"
  .NoProofing = False
End With
''');
    expect(plan.steps.map((step) => step.arguments), [
      {'paragraph': 0, 'language': 'de-DE'},
      {'paragraph': 0, 'csFont': 'Amiri'},
      {'paragraph': 0, 'language': 'en-GB'},
      {'paragraph': 0, 'font': 'Calibri'},
      {'paragraph': 0, 'noProof': false},
    ]);
  });

  test('typed aliases and optional named ByVal arguments retain identity', () {
    final plan = _source('''
Sub Configure(ByVal target As Range, ByVal face As Font, Optional ByVal language As Long = wdFrench)
  target.LanguageID = language
  face.NameBi = "Amiri"
  Set target = ThisDocument.Paragraphs(3).Range
  target.LanguageIDOther = wdGerman
End Sub
Sub Main()
  Dim target As Range, face As Font
  Set target = Application.ActiveDocument.Paragraphs.Item(2).Range
  Set face = ThisDocument.Paragraphs(1).Range.Font
  Configure face:=face, target:=target
  target.LanguageID = wdEnglishUS
End Sub
''');
    expect(plan.steps.map((step) => step.arguments), [
      {'paragraph': 1, 'language': 'fr-FR'},
      {'paragraph': 0, 'csFont': 'Amiri'},
      {'paragraph': 2, 'language': 'de-DE'},
      {'paragraph': 1, 'language': 'en-US'},
    ]);
  });

  for (final (collection, index, story) in [
    ('Headers', 'wdHeaderFooterPrimary', 'header'),
    ('Headers', 'wdHeaderFooterFirstPage', 'firstHeader'),
    ('Headers', 'wdHeaderFooterEvenPages', 'evenHeader'),
    ('Footers', 'wdHeaderFooterPrimary', 'footer'),
    ('Footers', 'wdHeaderFooterFirstPage', 'firstFooter'),
    ('Footers', 'wdHeaderFooterEvenPages', 'evenFooter'),
  ]) {
    test('$story selectors retain section and paragraph identity', () {
      final plan = _plan('''
With ThisDocument.Sections.Item(2).$collection.Item($index).Range.Paragraphs.Item(3).Range
  .LanguageID = wdEnglishUS
  .LanguageIDOther = wdGerman
  .Font.NameBi = "خط عربي"
End With
''');
      expect(plan.steps, hasLength(3));
      for (final step in plan.steps) {
        expect(step.arguments['section'], 1);
        expect(step.arguments['story'], story);
        expect(step.arguments['paragraph'], 2);
      }
      expect(plan.steps.last.arguments['csFont'], 'خط عربي');
    });
  }

  for (final value in [
    'wdLanguageNone',
    'wdNoProofing',
    'wdUndefined',
    'wdArabic',
    'wdHebrew',
    'wdJapanese',
    '-1',
    '1034',
    '65535',
  ]) {
    for (final property in ['LanguageID', 'LanguageIDOther']) {
      test('$property refuses unsupported value $value', () {
        _reject('$_range.$property = $value', 'vba_unsupported');
      });
    }
  }
  for (final value in [
    '1033.5',
    '"1033"',
    '"en-US"',
    'True',
    'Null',
    'Empty',
  ]) {
    test('language setter refuses implicit coercion from $value', () {
      _reject('$_range.LanguageID = $value', 'vba_type_error');
    });
  }
  for (final value in [
    '1033',
    'True',
    'Null',
    'Empty',
    '""',
    '"A\tB"',
    '"A\u0001B"',
  ]) {
    test('NameBi refuses invalid font expression ${value.codeUnits}', () {
      _reject('$_range.Font.NameBi = $value', 'vba_type_error');
    });
  }
  for (final property in ['LanguageID', 'LanguageIDOther', 'Font.NameBi']) {
    test('$property remains write-only, including unused branches', () {
      _reject('''
If False Then
  Dim value As Variant
  value = $_range.$property
End If
''', 'vba_unsupported');
    });
    test('$property cannot interrupt a custom line-spacing pair', () {
      final value = property == 'Font.NameBi' ? '"Amiri"' : 'wdGerman';
      _reject('''
$_range.ParagraphFormat.LineSpacingRule = wdLineSpaceExactly
$_range.$property = $value
$_range.ParagraphFormat.LineSpacing = 12
''', 'vba_unsupported');
    });
  }
  for (final member in [
    'LanguageIDFarEast',
    'Font.LanguageID',
    'Font.SizeBi',
  ]) {
    test('$member is not silently mapped to an unrelated native field', () {
      _reject('$_range.$member = 12', 'vba_unsupported');
    });
  }
  test('a whole header story is not a paragraph-language target', () {
    _reject(
      'ThisDocument.Sections(1).Headers(1).Range.LanguageID = wdFrench',
      'vba_unsupported',
    );
  });
  test('Word constants do not leak into Excel or PowerPoint', () {
    for (final (dialect, format) in [
      ('vba-excel', OfficeMacroFormat.xlsx),
      ('vba-powerpoint', OfficeMacroFormat.pptx),
    ]) {
      expect(
        () => OfficeMacroLanguages().compile(
          OfficeMacroSource(
            language: dialect,
            format: format,
            source:
                'Sub Main()\nDim language As Long\nlanguage = wdGerman\nEnd Sub',
          ),
        ),
        throwsA(isA<OfficeVbaCompileException>()),
      );
    }
  });
}
