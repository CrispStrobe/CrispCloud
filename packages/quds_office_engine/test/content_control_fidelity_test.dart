import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

WmlDocument source({bool legacy = false}) => WordDeserializer().readBytes(
  File(
    'test/fixtures/fidelity/content-controls${legacy ? '-legacy' : ''}.docx',
  ).readAsBytesSync(),
);

WmlParagraph paragraph(WmlDocument document, String text) =>
    document.paragraphs.firstWhere((p) => p.text == text);

void check(WmlDocument document, bool edited, {bool legacy = false}) {
  expect(document.paragraphs.map((p) => p.text), <String>[
    edited ? 'Before edited1' : 'Before1',
    edited ? 'Customer Omega tail' : 'Customer Alpha tail',
    edited ? 'Nested edited' : 'Nested Beta',
    'Cell Gamma',
    edited ? 'Inline before Updated after' : 'Inline before Inside after',
    legacy ? 'Legacy frame' : 'Ordinary block',
    'After',
  ]);
  final controls = WordTree.descendants(
    document.sections.first.blocks,
  ).whereType<WmlContentControlBlock>().toList();
  expect(controls, hasLength(6));
  expect(controls.map((block) => block.control.id), [
    '101',
    '102',
    '103',
    '104',
    '105',
    '106',
  ]);
  final outer = controls.first;
  expect(
    outer.blocks.whereType<WmlContentControlBlock>().single.control.id,
    '102',
  );
  expect(
    outer.blocks
        .whereType<WmlTable>()
        .single
        .rows
        .single
        .cells
        .single
        .blocks
        .whereType<WmlContentControlBlock>()
        .single
        .control
        .id,
    '103',
  );
  final frames = WordTree.descendants(
    document.sections.first.blocks,
  ).whereType<WmlFrame>();
  if (legacy) {
    final frame = frames.single;
    expect(frame.x, 72);
    expect(frame.y, 90);
    expect(frame.width, 200);
    expect(frame.height, 120);
    expect(frame.blocks.whereType<WmlFrame>(), isEmpty);
  } else {
    expect(frames, isEmpty);
  }
  expect(
    document.sections.first.header.single.text,
    edited ? 'Header edited' : 'Header value',
  );
  expect(
    WordNotes.editableParagraphs(document.footnotes.single).last.text,
    edited ? 'Note edited' : 'Note Delta',
  );
}

void main() {
  setUpAll(() {
    final output = File(
      'build/fidelity-content-controls-legacy/controls-source.docx',
    );
    output.parent.createSync(recursive: true);
    output.writeAsBytesSync(
      File('test/fixtures/fidelity/content-controls.docx').readAsBytesSync(),
    );
  });

  for (final edited in [false, true]) {
    test(
      'native ${edited ? 'edited' : 'imported'} SDT contents remain addressable through three async saves',
      () async {
        var document = source();
        check(document, false);
        if (edited) {
          WmlRunEdit.replaceRange(
            document.paragraphs.first,
            0,
            6,
            'Before edited',
          );
          WmlRunEdit.replaceRange(
            paragraph(document, 'Customer Alpha tail'),
            9,
            14,
            'Omega',
          );
          WmlRunEdit.replaceRange(
            paragraph(document, 'Nested Beta'),
            0,
            11,
            'Nested edited',
          );
          WmlRunEdit.replaceRange(
            paragraph(document, 'Inline before Inside after'),
            14,
            20,
            'Updated',
          );
          WmlRunEdit.replaceRange(
            document.sections.first.header.single,
            0,
            12,
            'Header edited',
          );
          WmlRunEdit.replaceRange(
            WordNotes.editableParagraphs(document.footnotes.single).last,
            0,
            10,
            'Note edited',
          );
        }
        for (var cycle = 1; cycle <= 3; cycle++) {
          final bytes = await OfficeIsolateSave.word(document);
          final output = File(
            'build/fidelity-content-controls-legacy/controls-${edited ? 'edited' : 'imported'}-$cycle.docx',
          );
          output.parent.createSync(recursive: true);
          output.writeAsBytesSync(bytes);
          document = WordDeserializer().readBytes(bytes);
          check(document, edited);
        }
      },
    );
  }

  test(
    'legacy private frame converts once and survives three async saves',
    () async {
      var document = source(legacy: true);
      check(document, false, legacy: true);
      for (var cycle = 1; cycle <= 3; cycle++) {
        final bytes = await OfficeIsolateSave.word(document);
        final output = File(
          'build/fidelity-content-controls-legacy/legacy-frame-$cycle.docx',
        );
        output.parent.createSync(recursive: true);
        output.writeAsBytesSync(bytes);
        document = WordDeserializer().readBytes(bytes);
        check(document, false, legacy: true);
      }
    },
  );

  test('invalid SDT structure fails before the source package is modified', () {
    for (final change in <void Function(WmlDocument)>[
      (doc) {
        final block = doc.sections.first.blocks
            .whereType<WmlContentControlBlock>()
            .first;
        final control = block.control;
        doc.sections.first.blocks[doc.sections.first.blocks.indexOf(
          block,
        )] = WmlContentControlBlock(
          control: WmlContentControlData(
            xml: control.xml.replaceAll('sdtContent', 'sdtPr'),
            sourcePartUri: control.sourcePartUri,
            relationships: control.relationships,
            id: control.id,
          ),
          blocks: block.blocks,
        );
      },
      (doc) {
        final p = paragraph(doc, 'Customer Alpha tail');
        p.inlines.removeWhere(
          (i) => i is WmlContentControlBoundary && !i.start,
        );
      },
      (doc) {
        final p = paragraph(doc, 'Customer Alpha tail');
        final next = WmlClone.paragraph(p);
        doc.sections.first.blocks.add(next);
      },
      (doc) {
        final absent = WordTree.descendants(doc.sections.first.blocks)
            .whereType<WmlContentControlBlock>()
            .singleWhere((block) => block.control.id == '105');
        absent.blocks.add(
          WmlParagraph(inlines: [WmlRun(text: 'Hidden insertion')]),
        );
      },
    ]) {
      final document = source();
      final before = document.package!
          .getPart('/word/document.xml')!
          .readText();
      change(document);
      expect(() => WordSerializer().writeBytes(document), throwsStateError);
      expect(
        document.package!.getPart('/word/document.xml')!.readText(),
        before,
      );
    }
  });

  test(
    'wide tables remain within their live native control over three saves',
    () async {
      var document = source();
      document.sections.first.columnCount = 2;
      WordTree.descendants(
        document.sections.first.blocks,
      ).whereType<WmlTable>().single.grid[0] = 400;
      for (var cycle = 0; cycle < 3; cycle++) {
        document = WordDeserializer().readBytes(
          await OfficeIsolateSave.word(document),
        );
        final outer = document.sections.first.blocks
            .whereType<WmlContentControlBlock>()
            .first;
        expect(outer.control.id, '101');
        expect(outer.blocks.whereType<WmlTable>().single.grid.single, 400);
        check(document, false);
      }
    },
  );

  test('native namespace aliases preserve SDT properties and contents', () {
    final document = source();
    for (final part in document.package!.parts) {
      if (!part.uri.endsWith('.xml')) continue;
      final xml = part.readText();
      if (xml.contains('xmlns:w=')) {
        part.writeText(
          xml
              .replaceAll('w:', 'native:')
              .replaceAll('xmlns:w=', 'xmlns:native='),
        );
      }
    }
    final reopened = WordDeserializer().read(document.package!);
    check(reopened, false);
    check(
      WordDeserializer().readBytes(WordSerializer().writeBytes(reopened)),
      false,
    );
  });

  test('unsupported row/cell wrappers reject instead of flattening', () {
    for (final location in ['row', 'cell']) {
      final document = source();
      final package = document.package!;
      final main = package.getPart('/word/document.xml')!;
      const open =
          '<w:sdt><w:sdtPr><w:id w:val="999"/></w:sdtPr><w:sdtContent>';
      const close = '</w:sdtContent></w:sdt>';
      if (location == 'row') {
        main.writeText(
          main
              .readText()
              .replaceFirst('<w:tr>', '$open<w:tr>')
              .replaceFirst('</w:tr>', '</w:tr>$close'),
        );
      } else {
        main.writeText(
          main
              .readText()
              .replaceFirst('<w:tc>', '$open<w:tc>')
              .replaceFirst('</w:tc>', '</w:tc>$close'),
        );
      }
      expect(
        () => WordDeserializer().read(package),
        throwsUnsupportedError,
        reason: location,
      );
    }
  });

  test(
    'CLI rejects an inline control split before replacing an existing output',
    () async {
      final directory = Directory.systemTemp.createTempSync('quds-sdt-reject-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final steps = File('${directory.path}/steps.json')
        ..writeAsStringSync(
          jsonEncode([
            {'op': 'paragraphSplit', 'paragraph': 1, 'offset': 11},
          ]),
        );
      final output = File('${directory.path}/preserved.docx')
        ..writeAsStringSync('existing output stays');
      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/fidelity/office_steps.dart',
        'modify',
        'test/fixtures/fidelity/content-controls.docx',
        steps.path,
        output.path,
      ]);
      expect(result.exitCode, isNot(0));
      expect('${result.stderr}', contains('inline content control'));
      expect(output.readAsStringSync(), 'existing output stays');
    },
  );
}
