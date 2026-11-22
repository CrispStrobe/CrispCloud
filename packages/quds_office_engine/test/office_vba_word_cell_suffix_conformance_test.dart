import 'dart:io';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

import 'support/vba_conformance.dart';

OfficeMacro _source(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    moduleName: 'CellSuffixConformance',
    source: source,
  ),
);

OfficeMacro _body(String source) => _source('Sub Main()\n$source\nEnd Sub');

const _cell = 'ActiveDocument.Tables(1).Cell(1, 1).Range';
const _suffix = 'docx.tableCellRangeInsertAfter';

TypeMatcher<OfficeVbaCompileException> _diagnostic(String code) =>
    isA<OfficeVbaCompileException>()
        .having((error) => error.code, 'code', code)
        .having((error) => error.moduleName, 'module', 'CellSuffixConformance')
        .having((error) => error.entryPoint, 'entry', 'Main')
        .having((error) => error.line, 'line', greaterThan(0))
        .having((error) => error.column, 'column', greaterThan(0));

void main() {
  final suite = VbaConformanceSuite.parse(
    File(
      'test/fixtures/vba_conformance/word_cell_suffix_v1.json',
    ).readAsStringSync(),
  );
  for (final fixture in suite.cases) {
    test('${fixture.feature}: ${fixture.id}', () {
      expect(runVbaConformanceCase(fixture)['actual'], fixture.expected);
    });
  }

  test('independent corpus is bounded and makes no Office-host claim', () {
    expect(suite.id, 'vba-word-cell-suffix');
    expect(suite.dialect, 'vba-word');
    expect(suite.cases, hasLength(73));
    expect(
      suite.cases.where((fixture) => fixture.expected.containsKey('steps')),
      hasLength(27),
    );
    expect(
      suite.cases.where(
        (fixture) => fixture.expected.containsKey('diagnostic'),
      ),
      hasLength(46),
    );
    expect(suite.cases.map((fixture) => fixture.provenance['kind']).toSet(), {
      'spec-derived',
      'dialect-contract',
    });
    expect(
      suite.cases.where((fixture) => fixture.provenance.containsKey('host')),
      isEmpty,
    );
    final receipt = runVbaConformanceSuite(suite);
    expect(receipt['caseCount'], 73);
    expect(
      canonicalVbaConformanceJson(receipt),
      canonicalVbaConformanceJson(runVbaConformanceSuite(suite)),
    );
  });

  group('independent suffix resource boundaries', () {
    test('accepts exactly 32767 UTF-16 units and rejects one more', () {
      final plan = _body('$_cell.InsertAfter Text:=String(32767, "x")');
      final text = plan.steps.single.arguments['text']! as String;
      expect(plan.steps.single.tool, _suffix);
      expect(text.length, 32767);
      expect(text, 'x' * 32767);
      expect(OfficeMacro.parse(plan.encode()).toJson(), plan.toJson());
      expect(
        () => _body('$_cell.InsertAfter Text:=String(32768, "x")'),
        throwsA(_diagnostic('vba_limit_exceeded')),
      );
    });

    test('counts supplementary characters as two UTF-16 units', () {
      final plan = _body('$_cell.InsertAfter Text:="😀" & String(32765, "x")');
      final text = plan.steps.single.arguments['text']! as String;
      expect(text.length, 32767);
      expect(text.runes.length, 32766);
      expect(text.startsWith('😀'), isTrue);
      expect(
        () => _body('$_cell.InsertAfter Text:="😀" & String(32766, "x")'),
        throwsA(_diagnostic('vba_limit_exceeded')),
      );
    });

    String repeated(int count, String text) =>
        '''
Dim target As Range, i As Long, label As String
Set target = $_cell
label = $text
For i = 1 To $count
  target.InsertAfter Text:=label
Next i
''';

    test('empty suffixes still consume the 10000-operation budget', () {
      final plan = _body(repeated(10000, '""'));
      expect(plan.steps, hasLength(10000));
      expect(plan.steps.every((step) => step.tool == _suffix), isTrue);
      expect(plan.steps.every((step) => step.arguments['text'] == ''), isTrue);
      expect(
        () => _body(repeated(10001, '""')),
        throwsA(_diagnostic('vba_limit_exceeded')),
      );
    });

    test(
      'repeated valid Strings retain the shared compilation work budget',
      () {
        final plan = _body(repeated(2, 'String(32767, "x")'));
        expect(plan.steps, hasLength(2));
        expect(
          () => _body(repeated(3, 'String(32767, "x")')),
          throwsA(
            _diagnostic('vba_limit_exceeded').having(
              (error) => error.message,
              'shared work budget',
              contains('100000 work units'),
            ),
          ),
        );
      },
    );

    test('aggregate JSON counts UTF-8 bytes rather than UTF-16 text units', () {
      final ascii = _body(repeated(10000, '"xxxx"'));
      final unicode = _body(repeated(9000, '"界界界界"'));
      expect(ascii.steps, hasLength(10000));
      expect(unicode.steps, hasLength(9000));
      expect(
        () => _body(repeated(10000, '"界界界界"')),
        throwsA(
          _diagnostic('vba_limit_exceeded').having(
            (error) => error.message,
            'native JSON byte budget',
            contains('Compiled native JSON exceeds 1 MiB'),
          ),
        ),
      );
    });
  });

  group('independent suffix sequencing and refusal', () {
    for (final text in ['"tail"', '""']) {
      test('cannot interleave $text with a pending line-spacing pair', () {
        expect(
          () => _body('''
$_cell.ParagraphFormat.LineSpacingRule = wdLineSpaceExactly
$_cell.InsertAfter Text:=$text
$_cell.ParagraphFormat.LineSpacing = 14
'''),
          throwsA(_diagnostic('vba_unsupported')),
        );
      });
    }

    test(
      'rebinding a ByVal helper to a paragraph cannot authorize suffixes',
      () {
        expect(
          () => _source('''
Sub Append(ByVal target As Range)
  target.InsertAfter "before local rebinding"
  Set target = ActiveDocument.Paragraphs(1).Range
  target.InsertAfter "after local rebinding"
End Sub
Sub Main()
  Append $_cell
End Sub
'''),
          throwsA(_diagnostic('vba_unsupported')),
        );
      },
    );

    test('known projected nested With is refused on an inactive path', () {
      expect(
        () => _body('''
With $_cell
  With .Paragraphs(1).Range
    If False Then
      .InsertAfter Text:="x"
    End If
  End With
End With
'''),
        throwsA(_diagnostic('vba_unsupported')),
      );
    });

    test('failed compilation never returns a partially valid native plan', () {
      OfficeMacro? result;
      expect(
        () => result = _body('''
$_cell.InsertAfter "valid"
ActiveDocument.Paragraphs(1).Range.InsertAfter "refused"
'''),
        throwsA(_diagnostic('vba_unsupported')),
      );
      expect(result, isNull);
    });
  });
}
