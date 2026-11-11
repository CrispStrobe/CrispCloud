import 'dart:convert';
import 'dart:io';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';
import '../tool/fidelity/office_steps.dart' as cli;

void main() {
  WmlDocument fixture() => WordDeserializer().readBytes(
    File('test/fixtures/fidelity/word.docx').readAsBytesSync(),
  );
  test('scripted multi-feature edits survive export and reopen', () {
    final WmlDocument doc = fixture();
    final List<dynamic> steps =
        jsonDecode(File('tool/fidelity/example_steps.json').readAsStringSync())
            as List<dynamic>;
    for (final dynamic step in steps) {
      cli.applyStep(doc, (step as Map).cast<String, dynamic>());
    }
    final WmlDocument after = WordDeserializer().readBytes(
      WordSerializer().writeBytes(doc),
    );
    expect(after.paragraphs.first.text, startsWith('Edited headline'));
    expect(after.paragraphs.first.properties.headingLevel, 2);
    final WmlParagraph p = after.paragraphs.elementAt(1);
    expect(p.properties.justification, WmlJustification.center);
    expect(p.properties.spacingBefore, 6);
    expect(p.properties.lineSpacing, 1.5);
    expect(p.inlines.whereType<WmlRun>().first.properties.bold, isTrue);
    expect(after.footnotes.single.text, 'Revised footnote');
    expect(
      after.endnotes.map((WmlNote n) => n.text),
      contains('Added endnote'),
    );
    expect(after.visuals.single.visual.width, 72);
    expect(after.visuals.single.visual.height, 48);
  });
  test('script can delete notes without altering bracketed text', () {
    final WmlDocument doc = fixture();
    cli.applyStep(doc, <String, dynamic>{'op': 'deleteNote', 'id': 12});
    expect(doc.footnotes, isEmpty);
    expect(doc.paragraphs.elementAt(1).text, 'Body text3');
  });
  test('unknown steps and note ids fail explicitly', () {
    final WmlDocument doc = fixture();
    expect(
      () => cli.applyStep(doc, <String, dynamic>{'op': 'typo'}),
      throwsArgumentError,
    );
    expect(
      () => cli.applyStep(doc, <String, dynamic>{
        'op': 'editNote',
        'id': 999,
        'text': 'x',
      }),
      throwsArgumentError,
    );
  });
}
