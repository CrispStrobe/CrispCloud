import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

OfficeMacro _source(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    moduleName: 'CellTextControls',
    source: source,
  ),
);

OfficeMacro _compile(String body) => _source('Sub Main()\n$body\nEnd Sub');

const _range = 'ActiveDocument.Tables(2).Cell(3, 4).Range';

Map<String, Object?> _cell(Map<String, Object?> fields) => {
  'paragraph': 0,
  'story': 'tableCell',
  'table': 1,
  'row': 2,
  'column': 3,
  ...fields,
};

Matcher _error([String? code]) {
  final result = isA<OfficeVbaCompileException>()
      .having((error) => error.moduleName, 'module', 'CellTextControls')
      .having((error) => error.entryPoint, 'entry', 'Main')
      .having((error) => error.line, 'line', greaterThan(0))
      .having((error) => error.column, 'column', greaterThan(0));
  return code == null
      ? result
      : result.having((error) => error.code, 'code', code);
}

void main() {
  for (final document in [
    'ThisDocument',
    'ActiveDocument',
    'Application.ActiveDocument',
  ]) {
    for (final item in ['', '.Item']) {
      test('$document.Tables$item keeps direct cell identity', () {
        final selected = '$document.Tables$item(2).Cell(3, 4).Range';
        final plan = _compile('''
$selected.NoProofing = True
$selected.HighlightColorIndex = wdYellow
$selected.LanguageID = wdEnglishUS
$selected.LanguageIDOther = wdGerman
''');
        expect(
          plan.steps.map((step) => step.tool),
          List<String>.filled(4, 'docx.runFormat'),
        );
        expect(plan.steps.map((step) => step.arguments), [
          _cell({'noProof': true}),
          _cell({'highlight': 'FFFF00'}),
          _cell({'language': 'en-US'}),
          _cell({'language': 'de-DE'}),
        ]);
        expect(OfficeMacro.parse(plan.encode()).toJson(), plan.toJson());
      });
    }
  }

  test('typed aliases and nested With survive parent rebinding', () {
    final plan = _compile('''
Dim selectedTable As Table, selected As Cell
Dim target As Range, retained As Range
Set selectedTable = ActiveDocument.Tables(2)
Set selected = selectedTable.Cell(3, 4)
Set target = selected.Range
Set retained = target
Set selectedTable = ActiveDocument.Tables(1)
Set selected = selectedTable.Cell(1, 2)
Set target = selected.Range
With retained
  .NoProofing = False
  .LanguageID = wdFrench
  .HighlightColorIndex = wdNoHighlight
End With
With Application
  With .ActiveDocument.Tables.Item(2)
    With .Cell(3, 4).Range
      .LanguageIDOther = wdEnglishUK
    End With
  End With
End With
target.NoProofing = True
''');
    expect(plan.steps.map((step) => step.arguments), [
      _cell({'noProof': false}),
      _cell({'language': 'fr-FR'}),
      _cell({'highlight': null}),
      _cell({'language': 'en-GB'}),
      {
        'paragraph': 0,
        'story': 'tableCell',
        'table': 0,
        'row': 0,
        'column': 1,
        'noProof': true,
      },
    ]);
  });

  test('named ByVal helpers work across body, header and cell ranges', () {
    final plan = _source('''
Sub Mark(ByVal target As Range, Optional ByVal skipProof As Boolean = False)
  target.NoProofing = skipProof
  target.LanguageIDOther = wdGerman
  target.HighlightColorIndex = wdBrightGreen
  Set target = ActiveDocument.Paragraphs(1).Range
  target.NoProofing = False
End Sub
Sub Main()
  Dim retained As Range
  Set retained = $_range
  Mark skipProof:=True, target:=retained
  retained.LanguageID = wdFrench
  Mark target:=ActiveDocument.Paragraphs(2).Range
  Mark target:=ActiveDocument.Sections(1).Headers(1).Range.Paragraphs(1).Range
End Sub
''');
    expect(plan.steps.map((step) => step.arguments), [
      _cell({'noProof': true}),
      _cell({'language': 'de-DE'}),
      _cell({'highlight': '00FF00'}),
      {'paragraph': 0, 'noProof': false},
      _cell({'language': 'fr-FR'}),
      {'paragraph': 1, 'noProof': false},
      {'paragraph': 1, 'language': 'de-DE'},
      {'paragraph': 1, 'highlight': '00FF00'},
      {'paragraph': 0, 'noProof': false},
      {'paragraph': 0, 'story': 'header', 'section': 0, 'noProof': false},
      {'paragraph': 0, 'story': 'header', 'section': 0, 'language': 'de-DE'},
      {'paragraph': 0, 'story': 'header', 'section': 0, 'highlight': '00FF00'},
      {'paragraph': 0, 'noProof': false},
    ]);
  });

  test('all fixed highlights and explicit removal retain native values', () {
    const colors = <String?>[
      null,
      '000000',
      '0000FF',
      '00FFFF',
      '00FF00',
      'FF00FF',
      'FF0000',
      'FFFF00',
      'FFFFFF',
      '000080',
      '008080',
      '008000',
      '800080',
      '800000',
      '808000',
      '808080',
      'C0C0C0',
    ];
    final plan = _compile('''
Dim index As Long
For index = 0 To 16
  $_range.HighlightColorIndex = index
Next index
''');
    expect(plan.steps.map((step) => step.arguments), [
      for (final color in colors) _cell({'highlight': color}),
    ]);
  });

  for (final statement in [
    'NoProofing = True',
    'NoProofing = False',
    'HighlightColorIndex = wdYellow',
    'LanguageID = wdGerman',
    'LanguageIDOther = wdEnglishUS',
  ]) {
    test('supported member is admitted in inactive code: $statement', () {
      expect(
        _compile('If False Then\n$_range.$statement\nEnd If').steps,
        isEmpty,
      );
    });
    test('text control cannot interrupt a custom spacing pair: $statement', () {
      expect(
        () => _compile('''
$_range.ParagraphFormat.LineSpacingRule = wdLineSpaceExactly
$_range.$statement
$_range.ParagraphFormat.LineSpacing = 14
'''),
        throwsA(_error('vba_unsupported')),
      );
    });
  }

  for (final statement in [
    'NoProofing = 1',
    'NoProofing = -1',
    'NoProofing = "True"',
    'NoProofing = Empty',
    'HighlightColorIndex = True',
    'HighlightColorIndex = "7"',
    'LanguageID = True',
    'LanguageIDOther = "1031"',
  ]) {
    test('strict control value rejects $statement', () {
      expect(
        () => _compile('$_range.$statement'),
        throwsA(_error('vba_type_error')),
      );
    });
  }
  for (final statement in [
    'HighlightColorIndex = 17',
    'HighlightColorIndex = wdByAuthor',
    'LanguageID = wdLanguageNone',
    'LanguageIDOther = wdNoProofing',
    'LanguageID = 99999',
  ]) {
    test('unsupported enum retains its source position: $statement', () {
      expect(
        () => _compile('$_range.$statement'),
        throwsA(_error('vba_unsupported')),
      );
    });
  }
  for (final property in [
    'NoProofing',
    'HighlightColorIndex',
    'LanguageID',
    'LanguageIDOther',
  ]) {
    test('cell control property reads remain unsupported: $property', () {
      expect(
        () => _compile('Dim result As Variant\nresult = $_range.$property'),
        throwsA(_error('vba_unsupported')),
      );
    });
  }
}
