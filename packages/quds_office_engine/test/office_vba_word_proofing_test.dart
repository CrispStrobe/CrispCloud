import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

import '../tool/macros/web_vba_word_proofing_smoke.dart' as portable;

const _range = 'ActiveDocument.Paragraphs(1).Range';

void _reject(String body, String code) => expect(
  () => portable.wordProofingPlan(body),
  throwsA(
    isA<OfficeVbaCompileException>()
        .having((e) => e.code, 'code', code)
        .having((e) => e.moduleName, 'module', 'WordProofingControls')
        .having((e) => e.line, 'line', greaterThan(0))
        .having((e) => e.column, 'column', greaterThan(0)),
  ),
);

void main() {
  test('proofing controls preserve assignment order and Boolean polarity', () {
    final plan = portable.wordProofingPlan('''
With $_range
  .NoProofing = True
  .NoProofing = False
  .ParagraphFormat.Hyphenation = False
  .ParagraphFormat.Hyphenation = True
  .Font.Kerning = 12.5
  .Font.Kerning = 0
End With
''');
    expect(plan.steps.map((s) => s.tool), [
      'docx.runFormat',
      'docx.runFormat',
      'docx.paragraphFormat',
      'docx.paragraphFormat',
      'docx.runFormat',
      'docx.runFormat',
    ]);
    expect(plan.steps.map((s) => s.arguments), <Map<String, Object?>>[
      {'paragraph': 0, 'noProof': true},
      {'paragraph': 0, 'noProof': false},
      {'paragraph': 0, 'suppressAutoHyphens': true},
      {'paragraph': 0, 'suppressAutoHyphens': false},
      {'paragraph': 0, 'kerning': 12.5},
      {'paragraph': 0, 'kerning': 0},
    ]);
  });

  test('typed aliases and named ByVal helpers retain target identity', () {
    final plan = portable.wordProofingSource('''
Option Explicit
Sub Configure(ByVal target As Range, ByVal font As Font, ByVal format As ParagraphFormat)
  target.NoProofing = False
  font.Kerning = 12
  format.Hyphenation = True
  Set target = ActiveDocument.Paragraphs(3).Range
  target.NoProofing = True
End Sub
Sub Main()
  Dim target As Range
  Dim font As Font
  Dim format As ParagraphFormat
  Set target = Application.ActiveDocument.Paragraphs.Item(2).Range
  Set font = target.Font
  Set format = ActiveDocument.Paragraphs(1).Format
  Configure format:=format, target:=target, font:=font
  target.NoProofing = False
End Sub
''');
    expect(plan.steps.map((s) => s.arguments['paragraph']), [1, 1, 0, 2, 1]);
  });

  for (final (collection, index, story) in [
    ('Headers', 'wdHeaderFooterPrimary', 'header'),
    ('Headers', 'wdHeaderFooterFirstPage', 'firstHeader'),
    ('Headers', 'wdHeaderFooterEvenPages', 'evenHeader'),
    ('Footers', 'wdHeaderFooterPrimary', 'footer'),
    ('Footers', 'wdHeaderFooterFirstPage', 'firstFooter'),
    ('Footers', 'wdHeaderFooterEvenPages', 'evenFooter'),
  ]) {
    test('$story preserves section/story identity for all three setters', () {
      final plan = portable.wordProofingPlan('''
With ThisDocument.Sections.Item(2).$collection.Item($index).Range.Paragraphs.Item(3).Range
  .nOpRoOfInG = False
  .ParagraphFormat.Hyphenation = True
  .Font.Kerning = 0.5
End With
''');
      for (final step in plan.steps) {
        expect(step.arguments['section'], 1);
        expect(step.arguments['story'], story);
        expect(step.arguments['paragraph'], 2);
      }
    });
  }

  for (final value in ['0', '0.5', '12', '12.5', '1638']) {
    test('accept exact supported kerning threshold $value', () {
      final plan = portable.wordProofingPlan('$_range.Font.Kerning = $value');
      expect(plan.steps.single.arguments['kerning'], num.parse(value));
    });
  }
  for (final value in [
    '-0.5',
    '0.25',
    '1638.5',
    'True',
    '"12"',
    'Null',
    'Empty',
  ]) {
    test('reject unsupported kerning value $value without a partial plan', () {
      _reject(
        '$_range.NoProofing = True\n$_range.Font.Kerning = $value',
        'vba_type_error',
      );
    });
  }
  test('shared numeric literal limits still apply before plan creation', () {
    _reject('$_range.Font.Kerning = 1E100', 'vba_limit_exceeded');
  });
  for (final property in ['NoProofing', 'ParagraphFormat.Hyphenation']) {
    for (final value in ['1', '-1', '"True"', 'Null', 'Empty']) {
      test('$property requires an actual Boolean, not $value', () {
        _reject('$_range.$property = $value', 'vba_type_error');
      });
    }
  }
  for (final body in [
    '$_range.Font.NoProofing = True',
    '$_range.Hyphenation = True',
    '$_range.ParagraphFormat.Kerning = 12',
    'ThisDocument.Sections(1).Headers(1).Range.NoProofing = True',
    'Dim value As Variant\nvalue = $_range.NoProofing',
    'Dim value As Variant\nvalue = $_range.Font.Kerning',
    'Dim value As Variant\nvalue = $_range.ParagraphFormat.Hyphenation',
  ]) {
    test(
      'unsupported receiver or property read is checked in inactive code: $body',
      () {
        _reject('If False Then\n$body\nEnd If', 'vba_unsupported');
      },
    );
  }
  test('unused helpers still validate new Boolean assignment types', () {
    expect(
      () => portable.wordProofingSource('''
Sub Unused()
  $_range.NoProofing = 1
End Sub
Sub Main()
End Sub
'''),
      throwsA(
        isA<OfficeVbaCompileException>().having(
          (e) => e.code,
          'code',
          'vba_type_error',
        ),
      ),
    );
  });
  for (final write in [
    'NoProofing = True',
    'Font.Kerning = 12',
    'ParagraphFormat.Hyphenation = True',
  ]) {
    test('$write cannot split a pending custom line-spacing pair', () {
      _reject('''
$_range.ParagraphFormat.LineSpacingRule = wdLineSpaceExactly
$_range.$write
$_range.ParagraphFormat.LineSpacing = 14
''', 'vba_unsupported');
    });
  }
}
