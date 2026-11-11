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
  test(
    'image replacement preserves pixels and dimensions through async saves',
    () async {
      final temporary = Directory.systemTemp.createTempSync('office-image-');
      addTearDown(() => temporary.deleteSync(recursive: true));
      final source = OpcPackage.openBytes(
        File('test/fixtures/fidelity/native.pptx').readAsBytesSync(),
      );
      final image = source.getPart('/ppt/media/image2.png')!.readBytes();
      final path = File('${temporary.path}/replacement.png')
        ..writeAsBytesSync(image);
      var doc = fixture();
      final original = doc.visuals.single.visual;
      final width = original.width, height = original.height;
      cli.applyStep(doc, {'op': 'imageReplace', 'image': 0, 'file': path.path});
      for (int cycle = 1; cycle <= 3; cycle++) {
        final bytes = await OfficeIsolateSave.word(doc);
        Directory('build/fidelity-image').createSync(recursive: true);
        File(
          'build/fidelity-image/replaced-$cycle.docx',
        ).writeAsBytesSync(bytes);
        doc = WordDeserializer().readBytes(bytes);
        expect(doc.visuals.single.visual.imageBytes, image);
        expect(doc.visuals.single.visual.width, width);
        expect(doc.visuals.single.visual.height, height);
      }
    },
  );
  test(
    'failing later script step leaves existing output intact and no temporary file',
    () async {
      final temporary = Directory.systemTemp.createTempSync('office-atomic-');
      addTearDown(() => temporary.deleteSync(recursive: true));
      final output = File('${temporary.path}/keep.docx')
        ..writeAsBytesSync([1, 2, 3, 4]);
      final steps = File('${temporary.path}/steps.json')
        ..writeAsStringSync(
          jsonEncode([
            {'op': 'replaceText', 'paragraph': 0, 'text': 'Partial edit'},
            {'op': 'imageReplace', 'image': 999, 'file': 'missing.png'},
          ]),
        );
      await expectLater(
        cli.main([
          'modify',
          'test/fixtures/fidelity/word.docx',
          steps.path,
          output.path,
        ]),
        throwsStateError,
      );
      expect(output.readAsBytesSync(), [1, 2, 3, 4]);
      expect(
        temporary.listSync().where((f) => f.path.contains('.tmp.')),
        isEmpty,
      );
    },
  );
  test(
    'successful CLI export replaces output with a complete package',
    () async {
      final temporary = Directory.systemTemp.createTempSync('office-export-');
      addTearDown(() => temporary.deleteSync(recursive: true));
      final output = File('${temporary.path}/result.docx')
        ..writeAsStringSync('old');
      await cli.main([
        'export',
        'test/fixtures/fidelity/word.docx',
        output.path,
      ]);
      expect(
        WordDeserializer()
            .readBytes(output.readAsBytesSync())
            .paragraphs
            .first
            .text,
        'Imported heading',
      );
      expect(
        temporary.listSync().where((f) => f.path.contains('.tmp.')),
        isEmpty,
      );
    },
  );
}
