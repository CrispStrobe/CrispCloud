// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/media_word_fixture.dart';
import 'support/list_word_fixture.dart';
import 'support/story_word_fixture.dart';
import 'support/structured_word_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _r =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _wp =
    'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing';
const _a = 'http://schemas.openxmlformats.org/drawingml/2006/main';

Map<String, Uint8List> _checked(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final files = <String, Uint8List>{};
  for (final file in archive) {
    expect(files.containsKey(file.name), isFalse, reason: 'duplicate ZIP part');
    expect(file.name.split('/'), isNot(contains('..')));
    if (file.isFile) files[file.name] = file.content;
  }
  final types = _xml(files, '[Content_Types].xml');
  final overrides = {
    for (final node in types.findAllElements('Override', namespace: '*'))
      node.getAttribute('PartName'): node.getAttribute('ContentType'),
  };
  for (final entry in files.entries) {
    if (entry.key.endsWith('.xml') || entry.key.endsWith('.rels')) {
      expect(
        () => XmlDocument.parse(utf8.decode(entry.value)),
        returnsNormally,
        reason: entry.key,
      );
    }
    if (entry.key != '[Content_Types].xml' && !entry.key.endsWith('.rels')) {
      expect(overrides.containsKey('/${entry.key}'), isTrue, reason: entry.key);
    }
    if (!entry.key.endsWith('.rels')) continue;
    final index = entry.key.indexOf('_rels/');
    final directory = entry.key.substring(0, index);
    for (final relation in _xml(files, entry.key).rootElement.childElements) {
      expect(relation.getAttribute('TargetMode'), isNull);
      final target = relation.getAttribute('Target')!;
      expect(
        files.containsKey('$directory$target'),
        isTrue,
        reason: '${entry.key}: $target',
      );
    }
  }
  return files;
}

XmlDocument _xml(
  Map<String, Uint8List> files, [
  String path = 'word/document.xml',
]) => XmlDocument.parse(utf8.decode(files[path]!));
Iterable<XmlElement> _elements(XmlNode node, String name, [String ns = _w]) =>
    node.findAllElements(name, namespace: ns);
String? _attr(XmlElement node, String name) =>
    node.getAttribute(name, namespace: _w);
String _text(XmlNode node) =>
    _elements(node, 't').map((element) => element.innerText).join();

LegacyWordParagraph _paragraph(
  int start,
  String value, {
  LegacyWordParagraphStyle style = const LegacyWordParagraphStyle(),
}) => LegacyWordParagraph(
  startCp: start,
  endCp: start + value.length + 1,
  runs: [
    LegacyWordRun(startCp: start, endCp: start + value.length, text: value),
  ],
  style: style,
);

LegacyWordStory _story(
  String id,
  LegacyWordStoryKind kind,
  int start,
  String value, {
  int? section,
  LegacyWordHeaderFooterType? headerType,
}) => LegacyWordStory(
  id: id,
  kind: kind,
  startCp: start,
  endCp: start + value.length + 1,
  blocks: [_paragraph(start, value)],
  plainText: value,
  safeHtml: '',
  sectionIndex: section,
  headerFooterType: headerType,
);

void main() {
  test(
    'stored first and even headers remain inactive unless source settings enable them',
    () {
      final document = LegacyWordDocument(
        blocks: [_paragraph(0, 'Body')],
        sections: const [LegacyWordSection(startCp: 0, endCp: 5)],
        plainText: 'Body',
        safeHtml: '',
        stories: [
          _story(
            'first',
            LegacyWordStoryKind.header,
            10,
            'Stored first',
            section: 0,
            headerType: LegacyWordHeaderFooterType.first,
          ),
          _story(
            'even',
            LegacyWordStoryKind.header,
            30,
            'Stored even',
            section: 0,
            headerType: LegacyWordHeaderFooterType.even,
          ),
        ],
      );
      final files = _checked(convertLegacyWordDocument(document).bytes);
      expect(_elements(_xml(files), 'headerReference'), hasLength(2));
      expect(_elements(_xml(files), 'titlePg'), isEmpty);
      expect(
        _elements(_xml(files, 'word/settings.xml'), 'evenAndOddHeaders'),
        isEmpty,
      );
      expect(_text(_xml(files, 'word/header1.xml')), 'Stored first');
    },
  );

  test(
    'private field notes and comments become inert evidence with no active references',
    () {
      const main = 'A\x13 REF Name\x14\x02\x05Secret\x15B\r';
      const note = '\x02Note\r', comment = '\x05Comment\r';
      final source = storyWordFixture(
        main: main,
        footnotes: '$note\r',
        comments: '$comment\r',
        tablePairs: {
          2: storyPlc([main.indexOf('\x02'), 0xffffffff], wordU16(1)),
          3: storyPlc([0, note.length, 0xffffffff]),
          4: storyPlc([main.indexOf('\x05'), 0xffffffff], storyCommentRecord()),
          5: storyPlc([0, comment.length, 0xffffffff]),
          36: storyXst('Alice'),
          16: storyPlc(
            [
              main.indexOf('\x13'),
              main.indexOf('\x14'),
              main.indexOf('\x15'),
              0xffffffff,
            ],
            [0x13, 0, 0x14, 0, 0x15, 0xa0],
          ),
        },
      );
      final result = convertLegacyWordToStructuredDocx(source),
          files = _checked(convertLegacyWordToStructuredDocx(source).bytes);
      final xml = _xml(files);
      expect(_text(xml), 'AB');
      expect(_elements(xml, 'footnoteReference'), isEmpty);
      expect(_elements(xml, 'commentReference'), isEmpty);
      expect(files.keys, isNot(contains('word/footnotes.xml')));
      expect(files.keys, isNot(contains('word/comments.xml')));
      final stories = files.keys
          .where((path) => path.startsWith('word/inertStoryEvidence'))
          .toList();
      expect(stories, hasLength(2));
      expect(
        stories.map((path) => _text(_xml(files, path))),
        unorderedEquals(['Note', 'Comment']),
      );
      expect(
        result.limitations,
        contains(LegacyWordConversionLimitation.notesComments),
      );
    },
  );

  test(
    'deleted note anchors retain tracked deletion instead of becoming ordinary markers',
    () {
      const note = '\x02Note\r';
      final source = storyWordFixture(
        main: 'A\x02B\r',
        footnotes: '$note\r',
        tablePairs: {
          2: storyPlc([1, 0xffffffff], wordU16(1)),
          3: storyPlc([0, note.length, 0xffffffff]),
        },
        characterRuns: [
          const WordFixtureFkpRun(8192, 16386),
          WordFixtureFkpRun(16386, 16388, properties: wordSprm(0x0800, [1])),
          const WordFixtureFkpRun(16388, 28672),
        ],
      );
      final files = _checked(convertLegacyWordToStructuredDocx(source).bytes);
      final marker = _elements(_xml(files), 'footnoteReference').single;
      expect((marker.parent!.parent as XmlElement).name.local, 'del');
      expect(_text(_xml(files, 'word/footnotes.xml')), 'Note');
    },
  );

  test(
    'validated textbox chain writes linked shapes and keeps the story exactly once',
    () {
      LegacyWordDrawing drawing(int shape, int cp, int chain) =>
          LegacyWordDrawing(
            shapeId: shape,
            anchorCp: cp,
            headerStory: false,
            leftTwips: chain * 1440,
            topTwips: 0,
            rightTwips: (chain + 1) * 1440,
            bottomTwips: 720,
            horizontalOrigin: 1,
            verticalOrigin: 1,
            wrapMode: 3,
            wrapSide: 0,
            behindText: false,
            anchorLocked: false,
            textboxId: 0x00010000 | chain,
            nextTextboxShapeId: chain == 0 ? 43 : null,
            source: const LegacyWordSourceReference(
              streamPath: '0Table',
              offset: 0,
              length: 26,
              structure: 'FSPA',
            ),
          );
      final document = LegacyWordDocument(
        blocks: [_paragraph(0, 'ABC')],
        sections: const [],
        plainText: 'ABC',
        safeHtml: '',
        stories: [
          _story('textbox', LegacyWordStoryKind.textbox, 10, 'Linked content'),
        ],
        textboxReferences: const [
          LegacyWordTextboxReference(
            id: 1,
            storyId: 'textbox',
            inHeaderFooter: false,
            shapeId: 42,
            anchorCp: 1,
            chainLength: 2,
            anchors: [
              LegacyWordTextboxAnchor(
                shapeId: 42,
                anchorCp: 1,
                chainIndex: 0,
                nextShapeId: 43,
              ),
              LegacyWordTextboxAnchor(shapeId: 43, anchorCp: 2, chainIndex: 1),
            ],
          ),
        ],
        media: LegacyWordMediaCatalog.from(
          drawings: [drawing(42, 1, 0), drawing(43, 2, 1)],
        ),
      );
      final result = convertLegacyWordDocument(document),
          files = _checked(convertLegacyWordDocument(document).bytes);
      final xml = _xml(files),
          boxes = _elements(_xml(files), 'txbxContent').toList();
      expect(boxes, hasLength(2));
      expect(boxes.map(_text), ['Linked content', '']);
      final shapes = _elements(
        xml,
        'rect',
        'urn:schemas-microsoft-com:vml',
      ).toList();
      expect(
        shapes.first.getAttribute('style'),
        contains('mso-next-textbox:#${shapes.last.getAttribute('id')}'),
      );
      expect(result.preservedCounts['textboxes'], 2);
      expect(
        utf8.decode(files['word/evidence/manifest.json']!),
        contains('exact reflow not claimed'),
      );
    },
  );

  test('saved picture names do not suppress valid stored image bytes', () {
    final result = convertLegacyWordToStructuredDocx(
      inlinePictureWordFixture(
        picture: inlinePictureData(
          storedName: 'https://invalid.test/stored.png',
        ),
      ),
    );
    final files = _checked(result.bytes);
    expect(files['word/media/image1.png'], orderedEquals(mediaFixturePng()));
    expect(_elements(_xml(files), 'drawing'), hasLength(1));
    expect(
      result.limitations,
      isNot(contains(LegacyWordConversionLimitation.images)),
    );
    expect(
      utf8.decode(files['word/evidence/manifest.json']!),
      contains('external name was not fetched'),
    );
  });

  test(
    'floating crop is retained from the referenced OfficeArt properties',
    () {
      final result = convertLegacyWordToStructuredDocx(
        floatingPictureWordFixture(
          imageProperties: {0x0100: 8192, 0x0102: 16384},
        ),
      );
      final files = _checked(result.bytes);
      final crop = _elements(_xml(files), 'srcRect', _a).single;
      expect(crop.getAttribute('t'), '12500');
      expect(crop.getAttribute('l'), '25000');
    },
  );

  test('deleted OfficeArt shapes remain evidence instead of active images', () {
    for (final source in [
      inlinePictureWordFixture(picture: inlinePictureData(shapeFlags: 0x0a08)),
      floatingPictureWordFixture(shapeFlags: 0x0a08),
    ]) {
      final result = convertLegacyWordToStructuredDocx(source);
      final files = _checked(result.bytes);
      expect(_elements(_xml(files), 'drawing'), isEmpty);
      expect(
        files.keys.where((path) => path.startsWith('word/media/')),
        isEmpty,
      );
      expect(
        files.keys.where((path) => path.startsWith('word/evidence/')),
        isNotEmpty,
      );
      expect(
        result.limitations,
        contains(LegacyWordConversionLimitation.images),
      );
    }
  });

  test(
    'images in headers resolve from the header part, not the document part',
    () {
      final parsed = parseLegacyWordDocument(inlinePictureWordFixture());
      final original = parsed.media.pictures.single;
      final document = LegacyWordDocument(
        blocks: [_paragraph(0, 'Body')],
        sections: const [],
        plainText: 'Body',
        safeHtml: '',
        stories: [
          _story('header', LegacyWordStoryKind.header, 10, 'XY', section: 0),
        ],
        media: LegacyWordMediaCatalog.from(
          assets: parsed.media.assets,
          pictures: [
            LegacyWordPicture(
              id: original.id,
              cp: 11,
              source: original.source,
              officeArtArtifactId: original.officeArtArtifactId,
              imageId: original.imageId,
              widthTwips: 1440,
              heightTwips: 720,
            ),
          ],
        ),
      );
      final files = _checked(convertLegacyWordDocument(document).bytes);
      expect(_elements(_xml(files), 'drawing'), isEmpty);
      expect(
        _elements(_xml(files, 'word/header1.xml'), 'drawing'),
        hasLength(1),
      );
      expect(files.keys, contains('word/_rels/header1.xml.rels'));
      expect(
        utf8.decode(files['word/_rels/header1.xml.rels']!),
        contains('Target="media/image1.png"'),
      );
    },
  );

  test(
    'numbering from the binary parser keeps localized formats and marker-only formatting',
    () {
      for (final format in [0, 23, 24, 25, 26, 33, 35, 36, 58]) {
        final source = listWordFixture(
          levels: [
            listFixtureLevel(
              format: format,
              text: format == 23 ? '\uf0a7' : '\x00.',
              placeholders: format == 23 ? [] : [1],
              character: wordSprm(0x0835, [1]),
            ),
          ],
        );
        final document = parseLegacyWordDocument(source);
        final files = _checked(convertLegacyWordToStructuredDocx(source).bytes);
        final numbering = _xml(files, 'word/numbering.xml');
        expect(
          _attr(_elements(numbering, 'numFmt').single, 'val'),
          document.numbering.single.levels.single.format,
        );
        expect(_attr(_elements(numbering, 'b').single, 'val'), '1');
        expect(_attr(_elements(_xml(files), 'b').single, 'val'), '0');
      }
    },
  );

  test(
    'referenced PNG is byte-exact, cropped, and linked from its owning part',
    () {
      final source = inlinePictureWordFixture(
        picture: inlinePictureData(properties: {0x0102: 16384}),
      );
      final result = convertLegacyWordToStructuredDocx(source);
      final files = _checked(result.bytes), xml = _xml(_checked(result.bytes));
      expect(files['word/media/image1.png'], orderedEquals(mediaFixturePng()));
      expect(_elements(xml, 'inline', _wp), hasLength(1));
      final extent = _elements(xml, 'extent', _wp).single;
      expect(
        (extent.getAttribute('cx'), extent.getAttribute('cy')),
        ('914400', '457200'),
      );
      expect(_elements(xml, 'srcRect', _a).single.getAttribute('l'), '25000');
      expect(
        _elements(xml, 'blip', _a).single.getAttribute('embed', namespace: _r),
        startsWith('rId'),
      );
      expect(result.preservedCounts['images'], 1);
      expect(
        result.limitations,
        isNot(contains(LegacyWordConversionLimitation.images)),
      );
    },
  );

  test(
    'floating image preserves FSPA position, anchoring, and wrap selection',
    () {
      final files = _checked(
        convertLegacyWordToStructuredDocx(floatingPictureWordFixture()).bytes,
      );
      final xml = _xml(files),
          anchor = _elements(_xml(files), 'anchor', _wp).single;
      expect(anchor.getAttribute('behindDoc'), '1');
      expect(anchor.getAttribute('locked'), '1');
      expect(
        _elements(xml, 'positionH', _wp).single.getAttribute('relativeFrom'),
        'page',
      );
      expect(
        _elements(xml, 'positionV', _wp).single.getAttribute('relativeFrom'),
        'paragraph',
      );
      expect(_elements(xml, 'posOffset', _wp).map((e) => e.innerText), [
        '76200',
        '152400',
      ]);
      expect(_elements(xml, 'wrapNone', _wp), hasLength(1));
    },
  );

  test(
    'hidden deleted pictures, drawings and OLE retain source presentation',
    () {
      final properties = [
        ...wordSprm(0x083c, [1]),
        ...wordSprm(0x0800, [1]),
      ];
      for (final source in [
        inlinePictureWordFixture(characterProperties: properties),
        floatingPictureWordFixture(characterProperties: properties),
        oleWordFixture(characterProperties: properties),
      ]) {
        final xml = _xml(
          _checked(convertLegacyWordToStructuredDocx(source).bytes),
        );
        final content = [
          ..._elements(xml, 'drawing'),
          ..._elements(xml, 'object'),
        ].single;
        final run = content.parent as XmlElement;
        expect(_elements(run, 'vanish'), hasLength(1));
        expect((run.parent as XmlElement).name.local, 'del');
      }
    },
  );

  test(
    'headers, footers, notes and comments have actual typed parts and references',
    () {
      final document = LegacyWordDocument(
        blocks: [_paragraph(0, 'Body')],
        sections: [
          const LegacyWordSection(startCp: 0, endCp: 5, titlePage: true),
        ],
        evenAndOddHeaders: true,
        plainText: 'Body',
        safeHtml: '',
        stories: [
          _story(
            'header',
            LegacyWordStoryKind.header,
            10,
            'Heading',
            section: 0,
            headerType: LegacyWordHeaderFooterType.first,
          ),
          _story(
            'footer',
            LegacyWordStoryKind.footer,
            20,
            '',
            section: 0,
            headerType: LegacyWordHeaderFooterType.even,
          ),
          _story('footnote', LegacyWordStoryKind.footnote, 30, 'Footnote'),
          _story('endnote', LegacyWordStoryKind.endnote, 40, 'Endnote'),
          _story('comment', LegacyWordStoryKind.comment, 50, 'Review'),
        ],
        noteReferences: const [
          LegacyWordNoteReference(
            id: 1,
            anchorCp: 1,
            storyId: 'footnote',
            endnote: false,
          ),
          LegacyWordNoteReference(
            id: 1,
            anchorCp: 2,
            storyId: 'endnote',
            endnote: true,
          ),
        ],
        commentReferences: [
          LegacyWordCommentReference(
            id: 0,
            anchorCp: 3,
            storyId: 'comment',
            rangeStartCp: 0,
            rangeEndCp: 3,
            author: 'A & B',
            initials: 'AB',
            time: DateTime.utc(2026, 11, 12, 8, 45),
          ),
        ],
      );
      final result = convertLegacyWordDocument(document),
          files = _checked(convertLegacyWordDocument(document).bytes);
      final xml = _xml(files);
      expect(_attr(_elements(xml, 'headerReference').single, 'type'), 'first');
      expect(_attr(_elements(xml, 'footerReference').single, 'type'), 'even');
      expect(_elements(xml, 'titlePg'), hasLength(1));
      expect(
        _elements(_xml(files, 'word/settings.xml'), 'evenAndOddHeaders'),
        hasLength(1),
      );
      expect(_text(_xml(files, 'word/header1.xml')), 'Heading');
      expect(_text(_xml(files, 'word/footer1.xml')), '');
      expect(_elements(xml, 'footnoteReference'), hasLength(1));
      expect(_elements(xml, 'endnoteReference'), hasLength(1));
      expect(_text(_xml(files, 'word/footnotes.xml')), 'Footnote');
      expect(_text(_xml(files, 'word/endnotes.xml')), 'Endnote');
      final comment = _elements(
        _xml(files, 'word/comments.xml'),
        'comment',
      ).single;
      expect(_attr(comment, 'author'), 'A & B');
      expect(_attr(comment, 'date'), '2026-11-12T08:45:00');
      expect(_elements(xml, 'commentRangeStart'), hasLength(1));
      expect(_elements(xml, 'commentRangeEnd'), hasLength(1));
      expect(
        result.limitations,
        isNot(contains(LegacyWordConversionLimitation.notesComments)),
      );
      expect(
        result.limitations,
        isNot(contains(LegacyWordConversionLimitation.headersFooters)),
      );
      expect(result.preservedCounts['comments'], 1);
    },
  );

  test(
    'typed note references preserve separate authored stories without duplicating markers',
    () {
      const foot = '\x02Foot\r', end = '\x02End\r';
      final source = storyWordFixture(
        main: 'A\x02B\x02\r',
        footnotes: '$foot\r',
        endnotes: '$end\r',
        tablePairs: {
          2: storyPlc([1, 0xffffffff], wordU16(1)),
          3: storyPlc([0, foot.length, 0xffffffff]),
          46: storyPlc([3, 0xffffffff], wordU16(1)),
          47: storyPlc([0, end.length, 0xffffffff]),
        },
      );
      final files = _checked(convertLegacyWordToStructuredDocx(source).bytes);
      expect(_text(_xml(files)), 'AB');
      expect(
        _elements(_xml(files, 'word/footnotes.xml'), 'footnoteRef'),
        hasLength(1),
      );
      expect(
        _elements(_xml(files, 'word/endnotes.xml'), 'endnoteRef'),
        hasLength(1),
      );
      expect(_text(_xml(files, 'word/footnotes.xml')), 'Foot');
    },
  );

  test(
    'nested reference fields remain locked editable syntax and cached display text',
    () {
      const text = 'A\x13 REF \x13 PAGE \x142\x15 \x14Value\x15Z\r';
      final result = convertLegacyWordToStructuredDocx(
        storyWordFixture(main: text),
      );
      final files = _checked(result.bytes), xml = _xml(_checked(result.bytes));
      final fields = _elements(xml, 'fldChar').toList();
      expect(fields.map((e) => _attr(e, 'fldCharType')), [
        'begin',
        'begin',
        'separate',
        'end',
        'separate',
        'end',
      ]);
      expect(
        fields
            .where((e) => _attr(e, 'fldCharType') == 'begin')
            .every((e) => _attr(e, 'fldLock') == '1'),
        isTrue,
      );
      expect(_elements(xml, 'instrText').map((e) => e.innerText), [
        ' REF ',
        ' PAGE ',
        ' ',
      ]);
      expect(_text(xml), 'A2ValueZ');
      expect(
        _attr(
          _elements(_xml(files, 'word/settings.xml'), 'updateFields').single,
          'val',
        ),
        'false',
      );
      expect(result.preservedCounts['fields'], 2);
    },
  );

  test('private cached field results never enter display XML', () {
    const text = 'A\x13 REF Hidden \x14Secret\x15B\r';
    final source = storyWordFixture(
      main: text,
      tablePairs: {
        16: storyPlc(
          [
            text.indexOf('\x13'),
            text.indexOf('\x14'),
            text.indexOf('\x15'),
            0xffffffff,
          ],
          [0x13, 0, 0x14, 0, 0x15, 0xb0],
        ),
      },
    );
    final files = _checked(convertLegacyWordToStructuredDocx(source).bytes);
    expect(_text(_xml(files)), 'AB');
    expect(utf8.decode(files['word/document.xml']!), isNot(contains('Secret')));
  });

  test(
    'external and unsafe nested fields stay inert with cached results only',
    () {
      for (final text in [
        'A\x13 INCLUDETEXT "https://invalid.test/a" \x14Cached\x15Z\r',
        'A\x13 REF \x13 DDEAUTO server topic item \x14cached\x15 \x14Outer\x15Z\r',
      ]) {
        final result = convertLegacyWordToStructuredDocx(
          storyWordFixture(main: text),
        );
        final files = _checked(result.bytes),
            xml = _xml(_checked(result.bytes));
        expect(_elements(xml, 'fldChar'), isEmpty);
        expect(_elements(xml, 'instrText'), isEmpty);
        expect(files.keys, contains('word/evidence/manifest.json'));
        expect(
          result.limitations,
          contains(LegacyWordConversionLimitation.fieldsLists),
        );
      }
    },
  );

  test(
    'bookmarks and list definitions become actual semantic Word elements',
    () {
      final document = LegacyWordDocument(
        blocks: [
          _paragraph(
            0,
            'First',
            style: const LegacyWordParagraphStyle(
              listId: 1,
              listLevel: 0,
              leftIndentTwips: 720,
              firstLineIndentTwips: -360,
            ),
          ),
        ],
        sections: const [],
        plainText: 'First',
        safeHtml: '',
        bookmarks: const [
          LegacyWordBookmark(name: 'Target', startCp: 0, endCp: 5),
        ],
        numbering: const [
          LegacyWordNumberingDefinition(
            id: 1,
            sourceListId: 17,
            levels: [
              LegacyWordNumberingLevel(
                level: 0,
                format: 'decimal',
                text: '%1.',
                startAt: 3,
                markerAlignment: LegacyWordAlignment.right,
                paragraphStyle: LegacyWordParagraphStyle(
                  leftIndentTwips: 720,
                  firstLineIndentTwips: -360,
                ),
              ),
            ],
          ),
        ],
      );
      final result = convertLegacyWordDocument(document),
          files = _checked(convertLegacyWordDocument(document).bytes);
      final xml = _xml(files), numbering = _xml(files, 'word/numbering.xml');
      expect(_attr(_elements(xml, 'bookmarkStart').single, 'name'), 'Target');
      expect(
        _attr(_elements(xml, 'bookmarkEnd').single, 'id'),
        _attr(_elements(xml, 'bookmarkStart').single, 'id'),
      );
      expect(_attr(_elements(xml, 'numId').single, 'val'), '1');
      expect(_attr(_elements(numbering, 'start').single, 'val'), '3');
      expect(_attr(_elements(numbering, 'lvlJc').single, 'val'), 'right');
      expect(result.preservedCounts['numberingDefinitions'], 1);
      expect(
        result.limitations,
        isNot(contains(LegacyWordConversionLimitation.fieldsLists)),
      );
    },
  );

  test(
    'textbox content is editable and anchored through the matching source shape',
    () {
      const content = 'Text box\r';
      final source = storyWordFixture(
        main: 'A\x08B\r',
        textboxes: '${content}x',
        tablePairs: {
          56: storyPlc(
            [0, content.length, content.length + 1],
            [
              ...wordU32(1),
              ...wordU32(0),
              ...wordU16(0),
              ...wordU32(0),
              ...wordU32(42),
              ...wordU32(0),
              ...List.filled(22, 0),
            ],
          ),
          40: storyPlc(
            [1, 0xffffffff],
            [
              ...wordU32(42),
              ...wordU32(0),
              ...wordU32(0),
              ...wordU32(1440),
              ...wordU32(720),
              ...wordU16(0),
              ...wordU32(0),
            ],
          ),
        },
        characterRuns: [
          WordFixtureFkpRun(8192, 28672, properties: wordSprm(0x0855, [1])),
        ],
      );
      final result = convertLegacyWordToStructuredDocx(source),
          xml = _xml(_checked(convertLegacyWordToStructuredDocx(source).bytes));
      expect(_text(_elements(xml, 'txbxContent').single), 'Text box');
      expect(result.preservedCounts['textboxes'], 1);
    },
  );

  test(
    'only verified embedded OLE becomes an active embedded-object relationship',
    () {
      final source = oleWordFixture(),
          parsed = parseLegacyWordDocument(oleWordFixture());
      final files = _checked(convertLegacyWordToStructuredDocx(source).bytes);
      expect(
        files['word/embeddings/oleObject1.bin'],
        orderedEquals(parsed.media.embeddedObjects.single.storage.bytes),
      );
      expect(_elements(_xml(files), 'object'), hasLength(1));
      for (final rejected in [
        oleWordFixture(linked: true),
        oleWordFixture(fieldTable: false),
        oleWordFixture(zombie: true),
      ]) {
        final result = convertLegacyWordToStructuredDocx(rejected),
            inert = _checked(convertLegacyWordToStructuredDocx(rejected).bytes);
        expect(
          inert.keys.where((path) => path.startsWith('word/embeddings/')),
          isEmpty,
        );
        expect(_elements(_xml(inert), 'object'), isEmpty);
        expect(inert.keys, contains('word/evidence/manifest.json'));
        expect(
          result.limitations,
          contains(LegacyWordConversionLimitation.embeddedObjects),
        );
      }
    },
  );

  test(
    'DOCX is macro-free; explicit DOCM copies VBA but keeps signatures inert',
    () {
      final signature = Uint8List.fromList([2, 0, 0xaa, 0xbb, 0xcc, 0xdd]);
      final source = StructuredWordFixture(
        pieces: const [WordFixturePiece('Macros\r')],
        extraTablePairs: {
          60: [
            ...wordU16(0xffff),
            ...wordU16(1),
            ...wordU16(4),
            ...wordU16(4),
            for (final c in 'Sign'.codeUnits) ...wordU16(c),
            ...wordU32(0),
            ...signature,
          ],
        },
        extraStreams: {
          'Macros/PROJECT': Uint8List.fromList('Name="Fixture"'.codeUnits),
          'Macros/VBA/dir': Uint8List.fromList([1, 2, 3]),
          'Macros/VBA/_VBA_PROJECT': Uint8List.fromList([
            0xcc,
            0x61,
            0,
            0,
            0,
            0,
            0,
          ]),
          'Macros/VBA/Module1': Uint8List.fromList([11, 22, 33]),
          '_signatures': Uint8List.fromList([9, 8, 7]),
          '_xmlsignatures/sig1.xml': Uint8List.fromList(
            '<Signature/>'.codeUnits,
          ),
        },
      ).build();
      final parsed = parseLegacyWordDocument(source);
      final docx = convertLegacyWordToStructuredDocx(source),
          docm = convertLegacyWord(source, format: LegacyWordOutputFormat.docm);
      final x = _checked(docx.bytes), m = _checked(docm.bytes);
      expect(x.keys, isNot(contains('word/vbaProject.bin')));
      expect(
        utf8.decode(x['[Content_Types].xml']!),
        isNot(contains('macroEnabled')),
      );
      expect(
        m['word/vbaProject.bin'],
        orderedEquals(parsed.media.vbaProjects.single.storage.bytes),
      );
      expect(
        utf8.decode(m['[Content_Types].xml']!),
        contains('macroEnabled.main+xml'),
      );
      expect(docm.extension, 'docm');
      expect(docm.preservedCounts['vbaProjects'], 1);
      for (final result in [docx, docm]) {
        final files = _checked(result.bytes);
        expect(result.signatureValidityClaimed, isFalse);
        expect(result.signatureEvidenceParts, hasLength(3));
        expect(result.signatureEvidenceParts.every(files.containsKey), isTrue);
        expect(
          result.signatureEvidenceParts.any(
            (p) => base64Encode(files[p]!) == base64Encode(signature),
          ),
          isTrue,
        );
        final relations = files.entries
            .where((e) => e.key.endsWith('.rels'))
            .map((e) => utf8.decode(e.value))
            .join();
        expect(relations, isNot(contains('digital-signature')));
        expect(relations, isNot(contains('vbaProjectSignature')));
        expect(
          files.keys.any((path) => path.contains('_xmlsignatures')),
          isFalse,
        );
        final manifest =
            jsonDecode(utf8.decode(files['word/evidence/manifest.json']!))
                as Map;
        expect(manifest['signatureValidityClaimed'], isFalse);
      }
    },
  );

  test(
    'deterministic output is independently immutable and never mutates the source',
    () {
      final source = inlinePictureWordFixture(),
          before = Uint8List.fromList(inlinePictureWordFixture());
      final first = convertLegacyWordToStructuredDocx(source),
          second = convertLegacyWordToStructuredDocx(source);
      expect(first.bytes, orderedEquals(second.bytes));
      expect(source, orderedEquals(before));
      expect(() => first.bytes[0] = 0, throwsUnsupportedError);
      expect(() => first.preservedCounts['images'] = 9, throwsUnsupportedError);
      expect(
        () => first.signatureEvidenceParts.add('bad'),
        throwsUnsupportedError,
      );
    },
  );
}
