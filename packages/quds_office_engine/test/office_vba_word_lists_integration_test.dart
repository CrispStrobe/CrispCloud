import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/macros/web_vba_word_lists_smoke.dart' as portable;

OfficeMacro _compile(String body) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    source: 'Sub Main()\n$body\nEnd Sub',
  ),
);

Matcher _failure(String code) =>
    isA<OfficeMacroException>().having((error) => error.code, 'code', code);

List<WmlParagraph> _paragraphs(Uint8List bytes) =>
    WordDeserializer().readBytes(bytes).paragraphs.toList();

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

Uint8List _fieldInput(String field) {
  final bytes = portable.wordListInput();
  final bullet = _paragraphs(bytes)[3].properties.numId;
  final package = OpcPackage.openBytes(bytes);
  package.getPart('/word/document.xml')!.writeText('''
<w:document xmlns:w="$_w"><w:body>
  <w:p><w:r><w:t>First paragraph</w:t></w:r></w:p>
  <w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="$bullet"/></w:numPr></w:pPr>
    <w:r><w:t xml:space="preserve">Value </w:t></w:r>$field
  </w:p>
  <w:p><w:r><w:t>Untouched paragraph</w:t></w:r></w:p>
  <w:sectPr/>
</w:body></w:document>
''');
  return package.save();
}

String _simpleField(String instruction) =>
    '<w:fldSimple w:instr="$instruction"><w:r><w:t>7</w:t></w:r></w:fldSimple>';

const _complexListNum =
    '<w:r><w:fldChar w:fldCharType="begin"/></w:r>'
    '<w:r><w:instrText xml:space="preserve"> LIST</w:instrText></w:r>'
    '<w:r><w:instrText xml:space="preserve">NUM LegalDefault </w:instrText></w:r>'
    '<w:r><w:fldChar w:fldCharType="separate"/></w:r>'
    '<w:r><w:t>7</w:t></w:r>'
    '<w:r><w:fldChar w:fldCharType="end"/></w:r>';

String _fieldInstruction(Uint8List bytes) {
  final xml = OpcPackage.openBytes(
    bytes,
  ).getPart('/word/document.xml')!.readText();
  final instructions = StringBuffer();
  void visit(XmlElement node) {
    if (node.localName == 'fldSimple') {
      instructions.write(node.getAttribute('instr'));
    }
    if (node.localName == 'instrText') instructions.write(node.text);
    for (final child in node.childElements) {
      visit(child);
    }
  }

  visit(XmlDocument.parse(xml).root!);
  return instructions.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
}

void main() {
  test(
    'actual list BAS publishes once and survives two native reopens',
    () async {
      final source = File('example/macros/word_lists.bas').readAsStringSync();
      final result = await portable.runWordListExample(source);
      expect(result['operations'], 8);
      expect(result['revision'], 1);
      expect(result['additionalReopens'], 2);
    },
  );

  for (final (method, kind) in [
    ('ApplyBulletDefault', 'bullet'),
    ('ApplyNumberDefault', 'decimal'),
  ]) {
    test(
      '$method toggles on, off, and on across separate saved runs',
      () async {
        final input = portable.wordListInput();
        final untouched = portable.wordListState(input).last;
        final session = OfficeMacroSession(
          input,
          format: OfficeMacroFormat.docx,
        );
        final plan = _compile('''
Dim target As ListFormat
Set target = ActiveDocument.Paragraphs(1).Range.ListFormat
With target
  .$method DefaultListBehavior:=wdWord8ListBehavior
End With
''');
        for (var revision = 1; revision <= 3; revision++) {
          await session.validate(plan);
          expect(session.revision, revision - 1);
          await session.run(plan);
          expect(session.revision, revision);
          var saved = session.bytes;
          for (var cycle = 0; cycle < 3; cycle++) {
            final state = portable.wordListState(saved);
            expect(state.first['kind'], revision == 2 ? 'none' : kind);
            expect(state.first['suppressed'], revision == 2);
            expect(state.first['leftTwips'], 360);
            expect(state.first['rightTwips'], 240);
            expect(state.first['hangingTwips'], 180);
            expect(state.last, untouched);
            saved = WordSerializer().writeBytes(
              WordDeserializer().readBytes(saved),
            );
          }
        }
      },
    );
  }

  test(
    'opposite default kind replaces a supported list with level-zero defaults',
    () async {
      final input = portable.wordListInput();
      final untouched = portable.wordListState(input).last;
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      await session.run(
        _compile('''
Call ActiveDocument.Paragraphs(4).Range.ListFormat.ApplyNumberDefault(DefaultListBehavior:=0)
'''),
      );
      var saved = session.bytes;
      for (var cycle = 0; cycle < 3; cycle++) {
        final state = portable.wordListState(saved);
        expect(state[3]['kind'], 'decimal');
        expect(state[3]['level'], 0);
        expect(state[3]['leftTwips'], 360);
        expect(state[3]['rightTwips'], 100);
        expect(state[3]['hangingTwips'], 180);
        expect(state.last, untouched);
        saved = WordSerializer().writeBytes(
          WordDeserializer().readBytes(saved),
        );
      }
    },
  );

  for (final method in ['ApplyBulletDefault', 'ApplyNumberDefault']) {
    test(
      '$method refuses an outline label and rolls back earlier list edits',
      () async {
        final input = portable.wordListInput();
        final session = OfficeMacroSession(
          input,
          format: OfficeMacroFormat.docx,
        );
        session.startRecording('Unsupported outline conversion');
        final plan = _compile('''
ActiveDocument.Paragraphs(1).Range.ListFormat.ApplyNumberDefault
ActiveDocument.Paragraphs(5).Range.ListFormat.$method
''');
        final failure = isA<OfficeMacroException>()
            .having((error) => error.code, 'code', 'operation_failed')
            .having((error) => error.stepIndex, 'step', 1)
            .having((error) => error.tool, 'tool', 'docx.listDefault');
        await expectLater(session.validate(plan), throwsA(failure));
        await expectLater(session.run(plan), throwsA(failure));
        expect(session.bytes, input);
        expect(session.revision, 0);
        expect(session.stopRecording().steps, isEmpty);
      },
    );
  }

  for (final argument in [
    '',
    'NumberType:=wdNumberParagraph',
    'wdNumberAllNumbers',
  ]) {
    test(
      'RemoveNumbers $argument preserves text and explicit indentation',
      () async {
        final input = portable.wordListInput();
        final session = OfficeMacroSession(
          input,
          format: OfficeMacroFormat.docx,
        );
        await session.run(
          _compile('''
ActiveDocument.Paragraphs(4).Range.ListFormat.RemoveNumbers $argument
ActiveDocument.Paragraphs(5).Range.ListFormat.RemoveNumbers $argument
'''),
        );
        var saved = session.bytes;
        for (var cycle = 0; cycle < 3; cycle++) {
          final paragraphs = _paragraphs(saved);
          for (final index in [3, 4]) {
            expect(paragraphs[index].properties.numId, isNull);
            expect(paragraphs[index].properties.numberingSuppressed, isTrue);
            expect(paragraphs[index].properties.ilvl, 0);
            expect(paragraphs[index].properties.listRestart, isNull);
            expect(paragraphs[index].text, _paragraphs(input)[index].text);
            final expected = _paragraphs(input)[index].properties.indent;
            final actual = paragraphs[index].properties.indent;
            expect(
              [actual.left, actual.right, actual.firstLine, actual.hanging],
              [
                expected.left,
                expected.right,
                expected.firstLine,
                expected.hanging,
              ],
            );
          }
          saved = WordSerializer().writeBytes(
            WordDeserializer().readBytes(saved),
          );
        }
      },
    );
  }

  test(
    'late missing paragraph rolls back list defaults, removal, and recording',
    () async {
      final input = portable.wordListInput();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      session.startRecording('Must not publish');
      final plan = _compile('''
ActiveDocument.Paragraphs(1).Range.ListFormat.ApplyNumberDefault
ActiveDocument.Paragraphs(4).Range.ListFormat.RemoveNumbers
ActiveDocument.Paragraphs(99).Range.ListFormat.ApplyBulletDefault
''');
      final failure = isA<OfficeMacroException>()
          .having((error) => error.code, 'code', 'operation_failed')
          .having((error) => error.stepIndex, 'step', 2)
          .having((error) => error.tool, 'tool', 'docx.listDefault');
      await expectLater(session.validate(plan), throwsA(failure));
      await expectLater(session.run(plan), throwsA(failure));
      expect(session.bytes, input);
      expect(session.revision, 0);
      expect(session.stopRecording().steps, isEmpty);
    },
  );

  for (final (label, field) in [
    ('simple', _simpleField(' LISTNUM LegalDefault ')),
    ('split complex', _complexListNum),
  ]) {
    test(
      'default RemoveNumbers refuses selected $label LISTNUM atomically',
      () async {
        final input = _fieldInput(field);
        final session = OfficeMacroSession(
          input,
          format: OfficeMacroFormat.docx,
        );
        session.startRecording('Rejected LISTNUM removal');
        final plan = _compile('''
ActiveDocument.Paragraphs(1).Range.ListFormat.ApplyNumberDefault
ActiveDocument.Paragraphs(2).Range.ListFormat.RemoveNumbers
''');
        final failure = isA<OfficeMacroException>()
            .having((error) => error.code, 'code', 'operation_failed')
            .having((error) => error.stepIndex, 'step', 1)
            .having((error) => error.tool, 'tool', 'docx.removeNumbers');
        await expectLater(session.validate(plan), throwsA(failure));
        await expectLater(session.run(plan), throwsA(failure));
        expect(session.bytes, input);
        expect(session.revision, 0);
        expect(session.stopRecording().steps, isEmpty);
      },
    );

    test(
      'paragraph-only removal preserves selected $label LISTNUM through reopens',
      () async {
        final input = _fieldInput(field);
        final session = OfficeMacroSession(
          input,
          format: OfficeMacroFormat.docx,
        );
        await session.run(
          _compile('''
Call ActiveDocument.Paragraphs(2).Range.ListFormat.RemoveNumbers(NumberType:=wdNumberParagraph)
'''),
        );
        var saved = session.bytes;
        for (var cycle = 0; cycle < 3; cycle++) {
          final paragraphs = _paragraphs(saved);
          expect(paragraphs[1].text, 'Value 7');
          expect(paragraphs[1].properties.numId, isNull);
          expect(paragraphs[1].properties.numberingSuppressed, isTrue);
          expect(_fieldInstruction(saved), 'LISTNUM LegalDefault');
          expect(paragraphs[0].text, 'First paragraph');
          expect(paragraphs[2].text, 'Untouched paragraph');
          saved = WordSerializer().writeBytes(
            WordDeserializer().readBytes(saved),
          );
        }
      },
    );
  }

  test(
    'all-number removal does not refuse an unselected LISTNUM field',
    () async {
      final input = _fieldInput(_simpleField(' LISTNUM LegalDefault '));
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      await session.run(
        _compile('''
ActiveDocument.Paragraphs(1).Range.ListFormat.ApplyNumberDefault
ActiveDocument.Paragraphs(1).Range.ListFormat.RemoveNumbers
'''),
      );
      expect(session.revision, 1);
      expect(_paragraphs(session.bytes)[0].properties.numId, isNull);
      expect(_paragraphs(session.bytes)[1].properties.numId, isNotNull);
      expect(_fieldInstruction(session.bytes), 'LISTNUM LegalDefault');
    },
  );

  test('all-number removal preserves a selected non-LISTNUM field', () async {
    final input = _fieldInput(_simpleField(' SEQ Figure '));
    final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
    await session.run(
      _compile('''
ActiveDocument.Paragraphs(2).Range.ListFormat.RemoveNumbers
'''),
    );
    var saved = session.bytes;
    for (var cycle = 0; cycle < 3; cycle++) {
      expect(_paragraphs(saved)[1].properties.numId, isNull);
      expect(_paragraphs(saved)[1].text, 'Value 7');
      expect(_fieldInstruction(saved), 'SEQ Figure');
      saved = WordSerializer().writeBytes(WordDeserializer().readBytes(saved));
    }
  });

  for (final (label, policy, code) in <(String, OfficeMacroPolicy, String)>[
    ('read-only', OfficeMacroPolicy(allowMutation: false), 'permission_denied'),
    (
      'default-only',
      OfficeMacroPolicy(allowedTools: {'docx.listDefault'}),
      'permission_denied',
    ),
    (
      'remove-only',
      OfficeMacroPolicy(allowedTools: {'docx.removeNumbers'}),
      'permission_denied',
    ),
    ('step-limit', OfficeMacroPolicy(maxSteps: 1), 'limit_exceeded'),
  ]) {
    test('source list plans retain the $label policy restriction', () async {
      final input = portable.wordListInput();
      final session = OfficeMacroSession(
        input,
        format: OfficeMacroFormat.docx,
        policy: policy,
      );
      final plan = _compile('''
ActiveDocument.Paragraphs(1).Range.ListFormat.ApplyNumberDefault
ActiveDocument.Paragraphs(4).Range.ListFormat.RemoveNumbers
''');
      await expectLater(session.validate(plan), throwsA(_failure(code)));
      await expectLater(session.run(plan), throwsA(_failure(code)));
      expect(session.bytes, input);
      expect(session.revision, 0);
    });
  }

  test(
    'allowlisting both list tools permits one isolated transaction',
    () async {
      final input = portable.wordListInput();
      final session = OfficeMacroSession(
        input,
        format: OfficeMacroFormat.docx,
        policy: OfficeMacroPolicy(
          allowedTools: {'docx.listDefault', 'docx.removeNumbers'},
        ),
      );
      final plan = _compile('''
ActiveDocument.Paragraphs(1).Range.ListFormat.ApplyNumberDefault
ActiveDocument.Paragraphs(4).Range.ListFormat.RemoveNumbers
''');
      final result = await session.validate(plan);
      expect(result.validatedOnly, isTrue);
      expect(result.completedSteps, 2);
      expect(session.bytes, input);
      expect(session.revision, 0);
      await session.run(plan);
      expect(session.revision, 1);
      final state = portable.wordListState(session.bytes);
      expect(state[0]['kind'], 'decimal');
      expect(state[3]['kind'], 'none');
    },
  );

  test(
    'new numbering parts preserve opaque DOCM VBA bytes and relationships',
    () async {
      const documentType =
          'application/vnd.ms-word.document.macroEnabled.main+xml';
      const projectType = 'application/vnd.ms-office.vbaProject';
      const projectRelationship =
          'http://schemas.microsoft.com/office/2006/relationships/vbaProject';
      final projectBytes = Uint8List.fromList([0, 1, 127, 128, 254, 255]);
      final signatureBytes = Uint8List.fromList([9, 8, 7, 6]);
      final plain = WordSerializer().writeBytes(
        WmlDocument(
          sections: [
            WmlSection(
              blocks: [
                WmlParagraph(inlines: [WmlRun(text: 'Macro document')]),
              ],
            ),
          ],
        ),
      );
      final package = OpcPackage.openBytes(plain);
      // A fresh serializer package includes defaults even without list use.
      // Remove that unused part so this fixture exercises relationship creation.
      final documentRelationships = package.relationshipsFor(
        '/word/document.xml',
      );
      for (final relationship
          in documentRelationships
              .byType(RelationshipTypes.numbering)
              .toList()) {
        documentRelationships.removeById(relationship.id);
      }
      package.deletePart('/word/numbering.xml');
      expect(package.getPart('/word/numbering.xml'), isNull);
      package.getPart('/word/document.xml')!.contentType = documentType;
      package.contentTypes.setOverride('/word/document.xml', documentType);
      package.createPart('/word/vbaProject.bin', projectType, projectBytes);
      package.createPart(
        '/word/vbaProjectSignature.bin',
        'application/octet-stream',
        signatureBytes,
      );
      final project = package
          .relationshipsFor('/word/document.xml')
          .add(type: projectRelationship, target: 'vbaProject.bin');
      final signature = package
          .relationshipsFor('/word/vbaProject.bin')
          .add(
            type: '${projectRelationship}Signature',
            target: 'vbaProjectSignature.bin',
          );
      final input = package.save();
      final guard = (await WordPackagePreservation.capture(
        input,
        'lists.docm',
      ))!;
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      final plan = _compile('''
ActiveDocument.Paragraphs(1).Range.ListFormat.ApplyNumberDefault
''');
      await session.validate(plan);
      expect(session.bytes, input);
      await session.run(plan);
      var saved = session.bytes;
      for (var cycle = 0; cycle < 3; cycle++) {
        await guard.validateSaved(saved);
        final reopened = OpcPackage.openBytes(saved);
        expect(
          reopened.getPart('/word/document.xml')!.contentType,
          documentType,
        );
        expect(
          reopened.getPart('/word/vbaProject.bin')!.contentType,
          projectType,
        );
        expect(
          reopened.getPart('/word/vbaProject.bin')!.readBytes(),
          projectBytes,
        );
        expect(
          reopened.getPart('/word/vbaProjectSignature.bin')!.readBytes(),
          signatureBytes,
        );
        final retainedProject = reopened
            .relationshipsFor('/word/document.xml')
            .items
            .singleWhere((item) => item.type == projectRelationship);
        expect(retainedProject.id, project.id);
        expect(retainedProject.target, project.target);
        final retainedSignature = reopened
            .relationshipsFor('/word/vbaProject.bin')
            .items
            .single;
        expect(retainedSignature.id, signature.id);
        expect(retainedSignature.target, signature.target);
        expect(retainedSignature.type, signature.type);
        expect(reopened.getPart('/word/numbering.xml'), isNotNull);
        expect(portable.wordListState(saved).single['kind'], 'decimal');
        expect(_paragraphs(saved).single.text, 'Macro document');
        saved = WordSerializer().writeBytes(
          WordDeserializer().readBytes(saved),
        );
      }
    },
  );
}
