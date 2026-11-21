import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

OfficeMacro _source(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    moduleName: 'PhysicalUnits',
    source: source,
  ),
);

OfficeMacro _compile(String body) => _source('Sub Main()\n$body\nEnd Sub');

Uint8List _input() =>
    (DocxDocumentBuilder()
          ..paragraph('First paragraph')
          ..paragraph('Second paragraph')
          ..paragraph('Untouched paragraph'))
        .build();

const _target = 'ActiveDocument.Paragraphs(1).Format';

void _expectExample(Uint8List bytes) {
  final paragraphs = WordDeserializer().readBytes(bytes).paragraphs.toList();
  expect(paragraphs.map((paragraph) => paragraph.text), [
    'First paragraph',
    'Second paragraph',
    'Untouched paragraph',
  ]);
  for (final paragraph in paragraphs.take(2)) {
    expect(paragraph.properties.indent.left, 72);
    expect(paragraph.properties.indent.right, 18);
    expect(paragraph.properties.spacingBefore, 12);
    expect(paragraph.properties.spacingAfter, 6);
  }
  expect(paragraphs.first.properties.indent.firstLine, 0);
  expect(paragraphs.first.properties.indent.hanging, 18);
  final untouched = WordDeserializer()
      .readBytes(_input())
      .paragraphs
      .elementAt(2);
  final actualIndent = paragraphs[2].properties.indent;
  final originalIndent = untouched.properties.indent;
  expect(actualIndent.left, originalIndent.left);
  expect(actualIndent.right, originalIndent.right);
  expect(actualIndent.firstLine, originalIndent.firstLine);
  expect(actualIndent.hanging, originalIndent.hanging);
  expect(
    paragraphs[2].properties.spacingBefore,
    untouched.properties.spacingBefore,
  );
  expect(
    paragraphs[2].properties.spacingAfter,
    untouched.properties.spacingAfter,
  );
}

void main() {
  test(
    'actual physical-unit BAS validates and repeats through save/reopen',
    () async {
      final plan = _source(
        File('example/macros/word_unit_conversions.bas').readAsStringSync(),
      );
      expect(plan.steps, hasLength(9));
      expect(plan.steps.map((step) => step.tool).toSet(), {
        'docx.paragraphFormat',
      });
      final bytes = _input();
      final session = OfficeMacroSession(bytes, format: OfficeMacroFormat.docx);
      await session.validate(plan);
      expect(session.bytes, bytes);
      expect(session.revision, 0);
      await session.run(OfficeMacro.parse(plan.encode()));
      expect(session.revision, 1);
      _expectExample(session.bytes);
      await session.run(plan);
      expect(session.revision, 2);
      _expectExample(session.bytes);
      var saved = session.bytes;
      for (var cycle = 0; cycle < 2; cycle++) {
        saved = WordSerializer().writeBytes(
          WordDeserializer().readBytes(saved),
        );
        _expectExample(saved);
      }
    },
  );

  test(
    'metric and inch conversions retain exact native decimal values',
    () async {
      final session = OfficeMacroSession(
        _input(),
        format: OfficeMacroFormat.docx,
      );
      await session.run(
        _compile('''
$_target.LeftIndent = InchesToPoints(0.2)
$_target.RightIndent = CentimetersToPoints(0.127)
$_target.FirstLineIndent = -MillimetersToPoints(1.27)
$_target.LineSpacingRule = wdLineSpaceExactly
$_target.LineSpacing = PicasToPoints(1.15)
'''),
      );
      var saved = session.bytes;
      for (var cycle = 0; cycle < 3; cycle++) {
        final document = WordDeserializer().readBytes(saved);
        final paragraph = document.paragraphs.first;
        expect(paragraph.properties.indent.left, 14.4);
        expect(paragraph.properties.indent.right, 3.6);
        expect(paragraph.properties.indent.hanging, 3.6);
        expect(paragraph.properties.lineSpacing, 13.8);
        expect(paragraph.properties.lineSpacingRule, WmlLineSpacingRule.exact);
        if (cycle < 2) saved = WordSerializer().writeBytes(document);
      }
    },
  );

  test(
    'late target failure rolls back converted measurements and revision',
    () async {
      final bytes = _input();
      final session = OfficeMacroSession(bytes, format: OfficeMacroFormat.docx);
      session.startRecording('prior-state');
      final plan = _compile('''
$_target.LeftIndent = InchesToPoints(1)
ActiveDocument.Paragraphs(99).Format.SpaceAfter = PicasToPoints(1)
''');
      final failure = isA<OfficeMacroException>().having(
        (error) => error.stepIndex,
        'step',
        1,
      );
      await expectLater(session.validate(plan), throwsA(failure));
      await expectLater(session.run(plan), throwsA(failure));
      expect(session.bytes, bytes);
      expect(session.revision, 0);
      expect(session.stopRecording().steps, isEmpty);
    },
  );

  test(
    'converted values retain mutation and operation allowlist policies',
    () async {
      final plan = _compile('$_target.LeftIndent = MillimetersToPoints(25.4)');
      final bytes = _input();
      for (final policy in [
        OfficeMacroPolicy(allowMutation: false),
        OfficeMacroPolicy(allowedTools: {'docx.replaceText'}),
      ]) {
        final session = OfficeMacroSession(
          bytes,
          format: OfficeMacroFormat.docx,
          policy: policy,
        );
        await expectLater(
          session.run(plan),
          throwsA(isA<OfficeMacroException>()),
        );
        expect(session.bytes, bytes);
        expect(session.revision, 0);
      }
    },
  );

  test('explicit metric twip rounding survives native serialization', () async {
    final session = OfficeMacroSession(
      _input(),
      format: OfficeMacroFormat.docx,
    );
    await session.run(
      _compile('''
$_target.LeftIndent = CLng(CentimetersToPoints(1) * 20) / 20
'''),
    );
    final paragraph = WordDeserializer()
        .readBytes(session.bytes)
        .paragraphs
        .first;
    expect(paragraph.properties.indent.left, 28.35);
  });

  test('scalar-only conversions leave bytes and revision unchanged', () async {
    final bytes = _input();
    final session = OfficeMacroSession(bytes, format: OfficeMacroFormat.docx);
    final plan = _compile('''
Dim value As Double
value = Application.CentimetersToPoints(1)
value = PointsToMillimeters(value)
''');
    expect(plan.steps, isEmpty);
    await session.run(plan);
    expect(session.bytes, bytes);
    expect(session.revision, 0);
  });
}
