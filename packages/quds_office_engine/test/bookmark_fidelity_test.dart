import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

WmlDocument _source() => WordDeserializer().readBytes(
  File('test/fixtures/fidelity/bookmarks.docx').readAsBytesSync(),
);

List<({String id, String? name, bool start, int paragraph, int offset})>
_markers(Iterable<WmlParagraph> paragraphs) {
  final out =
      <({String id, String? name, bool start, int paragraph, int offset})>[];
  var index = 0;
  for (final paragraph in paragraphs) {
    var offset = 0;
    for (final inline in paragraph.inlines) {
      if (inline is WmlRun) offset += inline.text.length;
      if (inline is WmlBookmarkMarker) {
        out.add((
          id: inline.id,
          name: inline is WmlBookmarkStart ? inline.name : null,
          start: inline.isStart,
          paragraph: index,
          offset: offset,
        ));
      }
    }
    index++;
  }
  return out;
}

Iterable<List<WmlParagraph>> _stories(WmlSection section) =>
    <List<WmlParagraph>>[
      section.header,
      section.footer,
      section.firstHeader,
      section.firstFooter,
      section.evenHeader,
      section.evenFooter,
    ];

void _edit(WmlDocument document) {
  final paragraphs = document.paragraphs.toList();
  WmlRunEdit.replaceRange(
    paragraphs[0],
    0,
    paragraphs[0].text.length,
    'Edited probe prefix',
  );
  WmlRunEdit.replaceRange(paragraphs[1], 0, 5, 'ALPHA!');
  WmlRunEdit.replaceRange(paragraphs[1], 9, 9, '+');
  WmlRunEdit.applyRange(paragraphs[1], 7, 12, (props) => props.italic = true);
  final split = WmlParagraph(
    properties: paragraphs[2].properties.copy()..bookmarkName = null,
    inlines: WmlRunEdit.splitParagraphInlines(paragraphs[2], 6),
  );
  document.sections.first.blocks.insert(3, split);
  WmlRunEdit.replaceRange(split, 0, 0, 'new ');
  WmlRunEdit.replaceRange(paragraphs[3], 0, 5, 'CROSS');
  WmlRunEdit.replaceRange(paragraphs[4], 2, 2, '+');
  WmlRunEdit.replaceRange(
    paragraphs[6],
    0,
    paragraphs[6].text.length,
    'Cell edited',
  );
  for (final story in _stories(document.sections.first)) {
    story.single.inlines.whereType<WmlRun>().last.text += '!';
  }
  WmlRunEdit.replaceRange(
    document.footnotes.single.paragraphs.single,
    0,
    'FootnoteRange'.length,
    'Edited footnote',
  );
  WmlRunEdit.replaceRange(
    document.endnotes.single.paragraphs.single,
    0,
    'EndnoteRange'.length,
    'Edited endnote',
  );
}

void main() {
  setUpAll(() {
    final source = File('build/fidelity-bookmarks/bookmarks-source.docx');
    source.parent.createSync(recursive: true);
    source.writeAsBytesSync(
      File('test/fixtures/fidelity/bookmarks.docx').readAsBytesSync(),
    );
  });

  for (final edited in <bool>[false, true]) {
    test(
      'native bookmarks keep ${edited ? 'edited' : 'imported'} boundaries over three cycles',
      () async {
        var document = _source();
        expect(_markers(document.paragraphs), hasLength(16));
        expect(WordLink.paragraphIndexForAnchor(document, 'Beta'), 1);
        if (edited) _edit(document);
        final before = _markers(document.paragraphs);
        final text = document.paragraphs.map((p) => p.text).toList();
        final headers = [
          for (final story in _stories(document.sections.first))
            _markers(story),
        ];
        final footnotes = _markers(document.footnotes.single.allParagraphs);
        final endnotes = _markers(document.endnotes.single.allParagraphs);
        for (var cycle = 1; cycle <= 3; cycle++) {
          final bytes = await OfficeIsolateSave.word(document);
          File(
            'build/fidelity-bookmarks/bookmarks-${edited ? 'edited' : 'imported'}-$cycle.docx',
          ).writeAsBytesSync(bytes);
          document = WordDeserializer().readBytes(bytes);
          expect(_markers(document.paragraphs), before);
          expect(document.paragraphs.map((p) => p.text), text);
          expect([
            for (final story in _stories(document.sections.first))
              _markers(story),
          ], headers);
          expect(_markers(document.footnotes.single.allParagraphs), footnotes);
          expect(_markers(document.endnotes.single.allParagraphs), endnotes);
          final table = document.paragraphs.firstWhere(
            (p) => p.text.startsWith('Cell'),
          );
          final marker = table.inlines.whereType<WmlBookmarkStart>().single;
          expect(marker.sourceXml, contains('colFirst="0"'));
          expect(marker.sourceXml, contains('colLast="0"'));
          final beta = document.paragraphs
              .elementAt(1)
              .inlines
              .whereType<WmlRun>()
              .where((run) => run.properties.bold)
              .toList();
          expect(beta.map((run) => run.text).join(), edited ? 'Be+ta' : 'Beta');
          expect(beta.every((run) => run.properties.color == '345678'), isTrue);
        }
      },
    );
  }

  test('cloning and exact-range selection copy both ordered endpoints', () {
    final paragraph = _source().paragraphs.elementAt(1);
    final slice = WmlClone.slicedParagraph(paragraph, 6, 10);
    expect(slice.text, 'Beta');
    expect(slice.properties.bookmarkName, isNull);
    expect(_markers([slice]).map((m) => (m.id, m.start, m.offset)), [
      ('11', true, 0),
      ('11', false, 4),
    ]);
    final original = paragraph.inlines.whereType<WmlBookmarkStart>().last;
    expect(
      slice.inlines.whereType<WmlBookmarkStart>().single,
      isNot(same(original)),
    );
    WmlRunEdit.applyRange(slice, 0, 4, (props) => props.italic = true);
    expect(
      paragraph.inlines.whereType<WmlRun>().last.properties.italic,
      isFalse,
    );
    final destination = WmlParagraph(inlines: [WmlRun(text: 'Before After')]);
    WmlRunEdit.insertInlines(destination, 7, slice.inlines);
    expect(destination.text, 'Before BetaAfter');
    expect(_markers([destination]).map((m) => (m.id, m.start, m.offset)), [
      ('11', true, 7),
      ('11', false, 11),
    ]);
  });

  test('partial-copy boundary packets keep a collapsed pair together', () {
    final paragraph = WmlParagraph(
      inlines: [
        WmlRun(text: 'left'),
        WmlBookmarkStart(id: '1', name: 'Point'),
        WmlBookmarkEnd(id: '1'),
        WmlRun(text: 'right'),
      ],
    );
    expect(
      WmlClone.slicedParagraph(
        paragraph,
        0,
        4,
      ).inlines.whereType<WmlBookmarkMarker>(),
      isEmpty,
    );
    final right = WmlClone.slicedParagraph(paragraph, 4, 9);
    expect(_markers([right]).map((m) => (m.id, m.start, m.offset)), [
      ('1', true, 0),
      ('1', false, 0),
    ]);
  });

  test(
    'split boundary keeps collapsed and overlapping ranges ordered',
    () async {
      var document = _source();
      final paragraph = document.paragraphs.elementAt(4);
      final tail = WmlParagraph(
        inlines: WmlRunEdit.splitParagraphInlines(paragraph, 4),
      );
      document.sections.first.blocks.insert(5, tail);
      expect(_markers([paragraph]).map((m) => (m.id, m.start)), [
        ('20', true),
        ('21', true),
        ('20', false),
        ('21', false),
      ]);
      expect(_markers([tail]).map((m) => (m.id, m.start, m.offset)), [
        ('22', true, 0),
        ('22', false, 0),
      ]);
      document = WordDeserializer().readBytes(
        await OfficeIsolateSave.word(document),
      );
      expect(
        document.paragraphs.elementAt(5).inlines.whereType<WmlBookmarkMarker>(),
        hasLength(2),
      );
    },
  );

  test(
    'generated heading identities avoid native IDs and do not duplicate after reopen',
    () async {
      var document = _source();
      WordToc.applyHeading(document.paragraphs.first, 2);
      var generatedId = '';
      for (var cycle = 0; cycle < 3; cycle++) {
        document = WordDeserializer().readBytes(
          await OfficeIsolateSave.word(document),
        );
        final starts = document.paragraphs
            .expand((p) => p.inlines.whereType<WmlBookmarkStart>())
            .toList();
        expect(starts, hasLength(9));
        expect(starts.map((m) => m.id).toSet(), hasLength(9));
        final generated = starts.singleWhere(
          (m) => m.name.startsWith('_Heading2_'),
        );
        if (cycle == 0) generatedId = generated.id;
        expect(generated.id, generatedId);
      }
    },
  );

  test('unmodeled block-level bookmark endpoints fail import explicitly', () {
    final package = _source().package!;
    final part = package.getPart('/word/document.xml')!;
    part.writeText(
      part.readText().replaceFirst(
        '<w:body>',
        '<w:body><b:bookmarkStart b:id="999" b:name="Outside"/><b:bookmarkEnd b:id="999"/>',
      ),
    );
    expect(() => WordDeserializer().read(package), throwsUnsupportedError);
  });

  test(
    'CLI destructive endpoint deletion preserves an existing output on failure',
    () async {
      final folder = Directory.systemTemp.createTempSync(
        'bookmark-invalid-step-',
      );
      addTearDown(() => folder.deleteSync(recursive: true));
      final steps = File('${folder.path}/steps.json')
        ..writeAsStringSync(
          jsonEncode([
            {'op': 'paragraphDelete', 'paragraph': 3},
          ]),
        );
      final output = File('${folder.path}/retained.docx')
        ..writeAsStringSync('Existing output');
      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/fidelity/office_steps.dart',
        'modify',
        'test/fixtures/fidelity/bookmarks.docx',
        steps.path,
        output.path,
      ]);
      expect(result.exitCode, isNot(0));
      expect(result.stderr.toString(), contains('unclosed bookmarks 12'));
      expect(output.readAsStringSync(), 'Existing output');
    },
  );

  for (final kind in [
    'missing start',
    'missing end',
    'duplicate',
    'inverted',
  ]) {
    test('$kind bookmark rejects export before package mutation', () {
      final document = _source();
      final paragraph = document.paragraphs.elementAt(1);
      if (kind == 'missing start') {
        paragraph.inlines.removeWhere(
          (i) => i is WmlBookmarkStart && i.id == '10',
        );
      } else if (kind == 'missing end') {
        paragraph.inlines.removeWhere(
          (i) => i is WmlBookmarkEnd && i.id == '10',
        );
      } else if (kind == 'duplicate') {
        document.sections.first.blocks.add(WmlClone.paragraph(paragraph));
      } else {
        final marker = paragraph.inlines.removeAt(0);
        paragraph.inlines.add(marker);
      }
      final before = document.package!.save();
      expect(() => WordSerializer().write(document), throwsStateError);
      expect(document.package!.save(), before);
    });
  }
}
