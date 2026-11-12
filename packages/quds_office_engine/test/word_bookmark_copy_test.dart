import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/fidelity/step_input.dart';

WmlParagraph _pair(String id, String name, {String text = 'marked'}) =>
    WmlParagraph(
      inlines: [
        WmlBookmarkBoundary(id: id, isStart: true, name: name),
        WmlRun(text: text),
        WmlBookmarkBoundary(id: id, isStart: false),
      ],
    );

WmlDocument _with(List<WmlBlock> blocks) =>
    WmlDocument(sections: [WmlSection(blocks: blocks)]);

Map<String, String> _identities(WmlDocument document) => {
  for (final range in WordBookmarks.ranges(document))
    range.name: range.start.id,
};

Map<String, String> _parts(OpcPackage package) => {
  for (final part in package.parts) part.uri: base64Encode(part.readBytes()),
};

void main() {
  test(
    'authored complete copy remaps only native identities over three saves',
    () async {
      final package = OpcPackage.create(OpcPackageKind.word);
      package
          .getPart('/word/document.xml')!
          .writeText(
            File('test/fixtures/fidelity/bookmark_copy.xml').readAsStringSync(),
          );
      final source = package.save();
      writeOutput('build/fidelity-bookmark-copy/source.docx', source);
      writeOutput(
        'build/fidelity-bookmark-copy/copied-expected.docx',
        File(
          'test/fixtures/fidelity/bookmark_copy_expected.docx',
        ).readAsBytesSync(),
      );
      var document = WordDeserializer().readBytes(source);
      final before = _parts(document.package!);
      final original = document.sections.single.blocks.take(2).toList();
      final copies = WordBookmarks.copyForInsertion(document, original);
      expect(_parts(document.package!), before);
      expect(_identities(_with(original)), {
        'Alpha': '000',
        'Overlap': '5',
        'Cross': '6',
        'Empty': '7',
      });
      expect(_identities(_with(copies)), {
        'Alpha_copy3': '3',
        'Overlap_copy': '4',
        'Cross_copy': '8',
        'Empty_copy': '9',
      });
      document.sections.single.blocks
        ..removeLast()
        ..addAll(copies);
      for (var cycle = 1; cycle <= 3; cycle++) {
        final bytes = await OfficeIsolateSave.word(document);
        writeOutput('build/fidelity-bookmark-copy/copied-$cycle.docx', bytes);
        document = WordDeserializer().readBytes(bytes);
        expect(_identities(document), {
          'Alpha': '000',
          'Overlap': '5',
          'Cross': '6',
          'Empty': '7',
          'Alpha_copy': '1',
          'Alpha_copy2': '2',
          'Alpha_copy3': '3',
          'Overlap_copy': '4',
          'Cross_copy': '8',
          'Empty_copy': '9',
        });
        expect(WordBookmarks.byName(document, 'Alpha_copy3')!.text, 'A😀B');
        expect(
          WordBookmarks.byName(document, 'Overlap_copy')!.text,
          'BCTail\nHead',
        );
        expect(
          WordBookmarks.byName(document, 'Cross_copy')!.text,
          'Tail\nHead End',
        );
        expect(WordBookmarks.byName(document, 'Empty_copy')!.text, '');
      }
    },
  );

  test(
    'noncolliding endpoints retain their independent decimal spelling and XML',
    () {
      const startXml =
          '<q:bookmarkStart xmlns:q="${OfficeNamespaces.w}" '
          'q:id="000" q:name="Range" q:colFirst="0" q:colLast="1"/>';
      const endXml =
          '<q:bookmarkEnd xmlns:q="${OfficeNamespaces.w}" q:id="+0"/>';
      final source = WmlParagraph(
        inlines: [
          WmlBookmarkBoundary(
            id: '000',
            isStart: true,
            name: 'Range',
            sourceXml: startXml,
          ),
          WmlRun(text: 'selected'),
          WmlBookmarkBoundary(id: '+0', isStart: false, sourceXml: endXml),
        ],
      );
      final copy =
          WordBookmarks.copyForInsertion(WmlDocument.empty(), [source]).single
              as WmlParagraph;
      final markers = copy.inlines.whereType<WmlBookmarkBoundary>().toList();
      expect(markers.map((marker) => marker.id), ['000', '+0']);
      expect(markers.map((marker) => marker.sourceXml), [startXml, endXml]);
      expect(markers.first, isNot(same(source.inlines.first)));
      expect(WordBookmarks.byName(_with([copy]), 'Range')!.text, 'selected');
    },
  );

  test('ID and name collisions are resolved independently', () {
    final destination = _with([_pair('7', 'Existing')]);
    final copies = WordBookmarks.copyForInsertion(destination, [
      _pair('7', 'Fresh'),
      _pair('8', 'Existing'),
    ]);
    expect(_identities(_with(copies)), {'Fresh': '1', 'Existing_copy': '8'});
    expect(_identities(destination), {'Existing': '7'});
  });

  test('allocation reserves noncolliding later incoming IDs and names', () {
    final destination = _with([_pair('1', 'Alpha')]);
    final copies = WordBookmarks.copyForInsertion(destination, [
      _pair('1', 'Alpha'),
      _pair('2', 'Alpha_copy'),
    ]);
    expect(_identities(_with(copies)), {'Alpha_copy2': '3', 'Alpha_copy': '2'});
  });

  test(
    'all destination stories, opaque XML and generated IDs are reserved',
    () {
      final destination = _with([
        _pair('7', 'Range'),
        WmlOpaqueBlock(
          sourcePartUri: '/word/document.xml',
          relationships: const [],
          xml:
              '<w:customXml xmlns:w="${OfficeNamespaces.w}"><w:p>'
              '<w:bookmarkStart w:id="1" w:name="Range_copy"/>'
              '<w:r><w:t>Opaque</w:t></w:r><w:bookmarkEnd w:id="1"/>'
              '</w:p></w:customXml>',
        ),
        WmlFrame(blocks: [_pair('3', 'Frame')]),
        WmlParagraph(properties: WmlParagraphProps(bookmarkName: 'Generated')),
      ]);
      destination.sections.single.header.add(_pair('2', 'Header'));
      destination.footnotes.add(
        WmlNote(id: 1, endnote: false, paragraphs: [_pair('4', 'Note')]),
      );
      destination.comments.add(
        WmlComment(id: 0, paragraphs: [_pair('5', 'Comment')]),
      );
      expect(WordBookmarks.generatedIds(destination), {'Generated': '6'});
      final copies = WordBookmarks.copyForInsertion(destination, [
        _pair('7', 'Range'),
      ]);
      expect(_identities(_with(copies)), {'Range_copy2': '8'});
      destination.sections.single.blocks.addAll(copies);
      expect(WordBookmarks.generatedIds(destination), {'Generated': '6'});
      expect(WordBookmarks.byName(destination, 'Range')!.start.id, '7');
    },
  );

  test('generated paragraph bookmarks use the same collision policy', () {
    final destination = _with([_pair('1', 'Heading')]);
    final source = WmlParagraph(
      properties: WmlParagraphProps(bookmarkName: 'Heading'),
      inlines: [WmlRun(text: 'New heading')],
    );
    final copied = WordBookmarks.copyForInsertion(destination, [source]);
    expect(
      (copied.single as WmlParagraph).properties.bookmarkName,
      'Heading_copy',
    );
    expect(source.properties.bookmarkName, 'Heading');
    destination.sections.single.blocks.addAll(copied);
    expect(WordBookmarks.generatedIds(destination), {'Heading_copy': '2'});
  });

  test(
    'copying twice leaves the reusable fragment and original clone unchanged',
    () {
      final source = _pair('3', 'Range');
      final history = WmlClone.paragraph(source);
      final destination = _with([source]);
      final first = WordBookmarks.copyForInsertion(destination, [source]);
      destination.sections.single.blocks.addAll(first);
      final second = WordBookmarks.copyForInsertion(destination, [source]);
      expect(_identities(_with(first)), {'Range_copy': '1'});
      expect(_identities(_with(second)), {'Range_copy2': '2'});
      expect(_identities(_with([history])), {'Range': '3'});
      expect(_identities(_with([source])), {'Range': '3'});
      expect(source.inlines.first, isNot(same(history.inlines.first)));
    },
  );

  test('names differing only by case also receive a free target name', () {
    final destination = _with([_pair('1', 'Alpha'), _pair('2', 'ALPHA_COPY')]);
    final copies = WordBookmarks.copyForInsertion(destination, [
      _pair('3', 'alpha'),
    ]);
    expect(_identities(_with(copies)), {'alpha_copy2': '3'});
  });

  for (final name in ['A' * 40, '42 bad title', '_Hidden', 'é🫧']) {
    test('allocated name for $name is legal and bounded', () {
      final destination = _with([_pair('1', name)]);
      final copied = WordBookmarks.copyForInsertion(destination, [
        _pair('1', name),
      ]);
      final allocated = WordBookmarks.ranges(_with(copied)).single.name;
      expect(allocated.length, lessThanOrEqualTo(40));
      expect(RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(allocated), isTrue);
      expect(allocated, endsWith('_copy'));
    });
  }

  test(
    'bounded suffix allocation still reserves an existing truncated name',
    () {
      final name = 'A' * 40;
      final destination = _with([
        _pair('1', name),
        _pair('2', '${'A' * 35}_copy'),
      ]);
      final copies = WordBookmarks.copyForInsertion(destination, [
        _pair('1', name),
      ]);
      expect(_identities(_with(copies)), {'${'A' * 34}_copy2': '3'});
    },
  );

  for (final start in [true, false]) {
    test(
      'a partial ${start ? 'start' : 'end'} fails without changing either input',
      () {
        final destination = _with([_pair('2', 'Existing')]);
        final partial = WmlParagraph(
          inlines: [
            WmlBookmarkBoundary(
              id: '1',
              isStart: start,
              name: start ? 'Partial' : null,
            ),
            WmlRun(text: 'Partial selection'),
          ],
        );
        final before = List<WmlInline>.of(partial.inlines);
        expect(
          () => WordBookmarks.copyForInsertion(destination, [partial]),
          throwsStateError,
        );
        expect(partial.inlines, orderedEquals(before));
        expect(_identities(destination), {'Existing': '2'});
      },
    );
  }

  test('endpoints cannot be paired across body and textbox stories', () {
    final body = WmlParagraph(
      inlines: [
        WmlBookmarkBoundary(id: '1', isStart: true, name: 'CrossStory'),
      ],
    );
    final frame = WmlFrame(
      blocks: [
        WmlParagraph(inlines: [WmlBookmarkBoundary(id: '1', isStart: false)]),
      ],
    );
    expect(
      () => WordBookmarks.copyForInsertion(WmlDocument.empty(), [body, frame]),
      throwsStateError,
    );
  });

  test('complete body and nested table/textbox pairs retain their stories', () {
    final source = [
      _pair('1', 'Body'),
      WmlTable(
        grid: [100],
        rows: [
          WmlTableRow(
            cells: [
              WmlTableCell(blocks: [_pair('2', 'Cell')]),
            ],
          ),
        ],
      ),
      WmlFrame(blocks: [_pair('3', 'Frame')]),
    ];
    final destination = _with(source);
    final copied = WordBookmarks.copyForInsertion(destination, source);
    expect(_identities(_with(copied)), {
      'Body_copy': '4',
      'Cell_copy': '5',
      'Frame_copy': '6',
    });
    expect((copied.last as WmlFrame).blocks.single, isA<WmlParagraph>());
    expect(
      WordBookmarks.ranges(_with(copied)).map((range) => range.text),
      everyElement('marked'),
    );
  });

  test(
    'an opaque copied bookmark is rejected even into an empty destination',
    () {
      final source = WmlOpaqueBlock(
        sourcePartUri: '/word/document.xml',
        relationships: const [],
        xml:
            '<w:customXml xmlns:w="${OfficeNamespaces.w}"><w:p>'
            '<w:bookmarkStart w:id="1" w:name="Opaque"/>'
            '<w:bookmarkEnd w:id="1"/></w:p></w:customXml>',
      );
      expect(
        () => WordBookmarks.copyForInsertion(WmlDocument.empty(), [source]),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'bookmarks in preserved native TOC caches require an explicit operation',
    () {
      final paragraph = _pair('1', 'Cached');
      final toc = WmlToc(
        sourcePresentation: WmlTocPresentation(
          configuration: (1, 3, true, null, null, null),
          paragraphs: [WmlTocSourceParagraph(paragraph: paragraph)],
        ),
      );
      expect(
        () => WordBookmarks.copyForInsertion(WmlDocument.empty(), [toc]),
        throwsUnsupportedError,
      );
      expect(WordBookmarks.byName(_with([toc]), 'Cached')!.text, 'marked');
    },
  );

  test('empty and unmarked copies allocate nothing', () {
    final destination = _with([_pair('1', 'Existing')]);
    expect(WordBookmarks.copyForInsertion(destination, []), isEmpty);
    final source = WmlParagraph(inlines: [WmlRun(text: 'Ordinary text')]);
    final copied =
        WordBookmarks.copyForInsertion(destination, [source]).single
            as WmlParagraph;
    expect(copied.text, source.text);
    expect(copied, isNot(same(source)));
    expect(_identities(destination), {'Existing': '1'});
  });
}
