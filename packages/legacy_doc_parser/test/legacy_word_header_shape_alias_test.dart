// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/header_textbox_alias_fixture.dart';
import 'support/structured_word_fixture.dart';
import 'support/textbox_boundary_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _v = 'urn:schemas-microsoft-com:vml';

List<XmlElement> _rectangles(Archive package) => [
  for (final file in package.files.where(
    (file) => file.name.startsWith('word/header') && file.name.endsWith('.xml'),
  ))
    ...XmlDocument.parse(
      utf8.decode(file.content),
    ).findAllElements('rect', namespace: _v),
];

List<String> _paragraphs(XmlElement shape) => [
  for (final paragraph
      in shape
          .findAllElements('txbxContent', namespace: _w)
          .single
          .findElements('p', namespace: _w))
    paragraph
        .findAllElements('t', namespace: _w)
        .map((text) => text.innerText)
        .join(),
];

LegacyWordDrawing _drawing(
  LegacyWordDrawing original, {
  int? cp,
  LegacyWordOfficeArtShape? shape,
  LegacyWordMediaPresentation? presentation,
  String? imageId,
}) => LegacyWordDrawing(
  shapeId: original.shapeId,
  anchorCp: cp ?? original.anchorCp,
  headerStory: original.headerStory,
  leftTwips: original.leftTwips,
  topTwips: original.topTwips,
  rightTwips: original.rightTwips,
  bottomTwips: original.bottomTwips,
  horizontalOrigin: original.horizontalOrigin,
  verticalOrigin: original.verticalOrigin,
  wrapMode: original.wrapMode,
  wrapSide: original.wrapSide,
  behindText: original.behindText,
  anchorLocked: original.anchorLocked,
  source: original.source,
  officeArtArtifactId: original.officeArtArtifactId,
  imageId: imageId ?? original.imageId,
  textboxId: original.textboxId,
  nextTextboxShapeId: original.nextTextboxShapeId,
  presentation: presentation ?? original.presentation,
  shapeDeleted: original.shapeDeleted,
  shape: shape ?? original.shape,
);

LegacyWordDocument _withDrawings(
  LegacyWordDocument original,
  List<LegacyWordDrawing> drawings,
) => LegacyWordDocument(
  blocks: original.blocks,
  sections: original.sections,
  plainText: original.plainText,
  safeHtml: original.safeHtml,
  stories: original.stories,
  textboxReferences: original.textboxReferences,
  fields: original.fields,
  bookmarks: original.bookmarks,
  noteReferences: original.noteReferences,
  commentReferences: original.commentReferences,
  media: LegacyWordMediaCatalog.from(drawings: drawings),
  warnings: original.warnings,
);

void main() {
  test(
    'exact native first-header roundtrip retains both source occurrences',
    () {
      final input = File(
        'test/fixtures/word_native/header-textbox-first-roundtrip.doc',
      ).readAsBytesSync();
      final before = input.toList();
      final document = parseLegacyWordDocument(input);
      final reference = document.textboxReferences.single;
      expect(reference.chainLength, 1);
      expect(reference.shapeId, 1025);
      expect(reference.anchorCp, 7);
      expect(reference.anchors.single.shapeId, 1025);
      expect(reference.headerAliases.single.shapeId, 1025);
      expect(reference.headerAliases.single.anchorCp, 10);
      expect(reference.headerAliases.single.chainIndex, 0);
      expect(reference.headerAliases.single.nextShapeId, isNull);
      expect(
        document.media.drawings.map(
          (drawing) => (drawing.shapeId, drawing.anchorCp),
        ),
        [(1025, 7), (1025, 10)],
      );
      expect(
        identical(
          document.media.drawings[0].shape,
          document.media.drawings[1].shape,
        ),
        isTrue,
      );
      expect(
        document.warnings,
        contains(LegacyWordWarning.recoveredHeaderTextboxShapeAlias),
      );
      expect(
        document.warnings,
        isNot(contains(LegacyWordWarning.recoveredTextboxChainLength)),
      );
      final conversion = convertLegacyWordDocument(document);
      final package = ZipDecoder().decodeBytes(conversion.bytes);
      final rectangles = _rectangles(package);
      expect(rectangles.map(_paragraphs), [
        ['ALPHA'],
        ['ALPHA'],
      ]);
      expect(rectangles.map((shape) => shape.getAttribute('id')), [
        '_legacyHeaderTextboxShape1025Cp7',
        '_legacyHeaderTextboxShape1025Cp10',
      ]);
      // These independently observed SPA rectangles differ. An ID-only lookup
      // would silently move the normal occurrence to the first-header rectangle.
      expect(
        rectangles[0].getAttribute('style'),
        contains(
          'margin-left:72.35pt;margin-top:72.35pt;width:143.2pt;height:21.2pt',
        ),
      );
      expect(
        rectangles[1].getAttribute('style'),
        contains(
          'margin-left:72.7pt;margin-top:72.7pt;width:142.5pt;height:20.5pt',
        ),
      );
      expect(rectangles[0].getAttribute('style'), contains('z-index:1025'));
      expect(rectangles[1].getAttribute('style'), contains('z-index:-1'));
      expect(
        rectangles.any((shape) => shape.outerXml.contains('mso-next-textbox')),
        isFalse,
      );
      final evidence =
          jsonDecode(
                utf8.decode(
                  package.findFile('word/evidence/manifest.json')!.content,
                ),
              )
              as Map;
      final alias =
          (evidence['records'] as List).singleWhere(
                (record) => record['kind'] == 'headerTextboxAlias',
              )
              as Map;
      expect(alias['sharedShape'], isTrue);
      expect(
        (alias['occurrences'] as List).map(
          (record) => [record['shapeId'], record['anchorCp']],
        ),
        [
          [1025, 7],
          [1025, 10],
        ],
      );
      expect(conversion.preservedCounts['textboxes'], 2);
      expect(input, before);
    },
  );

  for (final entry in textboxBoundaryCases.entries) {
    test('shared-shape literal retains ${entry.key} in both headers', () {
      final document = parseLegacyWordDocument(
        headerTextboxAliasFixture(sharedShape: true, rawText: entry.value.$1),
      );
      final conversion = convertLegacyWordDocument(document);
      expect(
        _rectangles(
          ZipDecoder().decodeBytes(conversion.bytes),
        ).map(_paragraphs),
        [entry.value.$2, entry.value.$2],
      );
      expect(document.textboxReferences.single.chainLength, 1);
      expect(document.media.drawings.map((drawing) => drawing.shapeId), [
        1025,
        1025,
      ]);
    });
  }

  test(
    'shared source shape retains signed independent bounds and wrapping',
    () {
      final source = parseLegacyWordDocument(
        headerTextboxAliasFixture(
          sharedShape: true,
          secondBounds: (-360, 720, 2400, 1920),
          secondFlags: 0x406a,
        ),
      );
      final shapes = _rectangles(
        ZipDecoder().decodeBytes(convertLegacyWordDocument(source).bytes),
      );
      expect(
        shapes[0].getAttribute('style'),
        contains(
          'margin-left:72.0pt;margin-top:72.0pt;width:144.0pt;height:22.0pt',
        ),
      );
      expect(
        shapes[1].getAttribute('style'),
        contains(
          'margin-left:-18.0pt;margin-top:36.0pt;width:138.0pt;height:60.0pt',
        ),
      );
      expect(shapes[0].getAttribute('style'), contains('z-index:1025'));
      expect(shapes[1].getAttribute('style'), contains('z-index:-1'));
    },
  );

  final hostile = {
    'same header': () =>
        headerTextboxAliasFixture(sharedShape: true, sameHeader: true),
    'main story': () =>
        headerTextboxAliasFixture(sharedShape: true, mainStory: true),
    'first footer': () =>
        headerTextboxAliasFixture(sharedShape: true, firstFooter: true),
    'three anchor occurrences': () =>
        headerTextboxAliasFixture(sharedShape: true, extraOccurrence: true),
    'two-frame count': () =>
        headerTextboxAliasFixture(sharedShape: true, count: 2),
    'unresolved FTXBXS first shape': () =>
        headerTextboxAliasFixture(sharedShape: true, lid: 9999),
    'unbound ClientTextbox': () =>
        headerTextboxAliasFixture(sharedShape: true, firstStory: 0),
    'different ClientTextbox story': () =>
        headerTextboxAliasFixture(sharedShape: true, firstStory: 2),
    'self link': () =>
        headerTextboxAliasFixture(sharedShape: true, firstNext: 1025),
    'next-shape link': () =>
        headerTextboxAliasFixture(sharedShape: true, firstNext: 1026),
    'duplicate OfficeArt FSP': () => headerTextboxAliasFixture(
      sharedShape: true,
      duplicateShapeRecord: true,
    ),
    'group context': () =>
        headerTextboxAliasFixture(sharedShape: true, shapeFlags: 0xa02),
    'non-textbox shape': () =>
        headerTextboxAliasFixture(sharedShape: true, shapeType: 1),
    'field content': () => headerTextboxAliasFixture(
      sharedShape: true,
      rawText: '\x13 PAGE \x141\x15\r\r',
    ),
    'inserted content': () => headerTextboxAliasFixture(
      sharedShape: true,
      textProperties: wordSprm(0x0801, [1]),
    ),
    'deleted content': () => headerTextboxAliasFixture(
      sharedShape: true,
      textProperties: wordSprm(0x0800, [1]),
    ),
  };
  for (final entry in hostile.entries) {
    test('shared-shape recovery rejects ${entry.key}', () {
      expect(
        () => parseLegacyWordDocument(entry.value()),
        throwsFormatException,
      );
    });
  }

  test('public model cannot substitute a different shape payload or image', () {
    final source = parseLegacyWordDocument(
      headerTextboxAliasFixture(sharedShape: true),
    );
    final first = source.media.drawings[0], second = source.media.drawings[1];
    for (final changed in [
      _drawing(
        second,
        shape: LegacyWordOfficeArtShape(
          type: 202,
          sourceFlags: 0xa00,
          fill: const LegacyWordOfficeArtFill(color: 'FF0000'),
        ),
      ),
      _drawing(second, imageId: 'forged-shared-image'),
      _drawing(second, cp: first.anchorCp),
    ]) {
      expect(
        () =>
            convertLegacyWordDocument(_withDrawings(source, [first, changed])),
        throwsFormatException,
      );
    }
  });

  for (final cp in [7, 10]) {
    for (final (name, presentation) in [
      ('hidden state', const LegacyWordMediaPresentation(hidden: true)),
      ('insertion flag', const LegacyWordMediaPresentation(inserted: true)),
      ('deletion flag', const LegacyWordMediaPresentation(deleted: true)),
      (
        'independent insertion',
        const LegacyWordMediaPresentation(
          insertionRevision: LegacyWordRevisionInfo(author: 'Reviewer'),
        ),
      ),
      (
        'independent deletion',
        const LegacyWordMediaPresentation(
          deletionRevision: LegacyWordRevisionInfo(author: 'Reviewer'),
        ),
      ),
    ]) {
      test('shared-shape occurrence $cp excludes $name', () {
        final source = parseLegacyWordDocument(
          headerTextboxAliasFixture(sharedShape: true),
        );
        expect(
          () => convertLegacyWordDocument(
            _withDrawings(source, [
              for (final original in source.media.drawings)
                original.anchorCp == cp
                    ? _drawing(original, presentation: presentation)
                    : original,
            ]),
          ),
          throwsFormatException,
        );
      });
    }
  }
}
