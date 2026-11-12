// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:legacy_doc_parser/src/bounded_cfb_reader.dart';
import 'package:legacy_doc_parser/src/legacy_word_textbox_alias.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/header_textbox_alias_fixture.dart';
import 'support/structured_word_fixture.dart';
import 'support/textbox_boundary_fixture.dart';
import '../tool/fidelity/header_textbox_titlepage.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _sourcePath =
    'test/fixtures/word_native/header-textbox-duplicate-chain.doc';

List<List<String>> _boxes(Archive package) => [
  for (final file in package.files.where(
    (file) => file.name.startsWith('word/header') && file.name.endsWith('.xml'),
  ))
    for (final box in XmlDocument.parse(
      utf8.decode(file.content),
    ).findAllElements('txbxContent', namespace: _w))
      [
        for (final p in box.findElements('p', namespace: _w))
          p.findAllElements('t', namespace: _w).map((t) => t.innerText).join(),
      ],
];

LegacyWordDocument _copy(
  LegacyWordDocument source, {
  List<LegacyWordStory>? stories,
  List<LegacyWordTextboxReference>? references,
  List<LegacyWordBookmark>? bookmarks,
  List<LegacyWordField>? fields,
  List<LegacyWordNoteReference>? notes,
  List<LegacyWordCommentReference>? comments,
  LegacyWordMediaCatalog? media,
}) => LegacyWordDocument(
  blocks: source.blocks,
  sections: source.sections,
  plainText: source.plainText,
  safeHtml: source.safeHtml,
  stories: stories ?? source.stories,
  textboxReferences: references ?? source.textboxReferences,
  bookmarks: bookmarks ?? source.bookmarks,
  fields: fields ?? source.fields,
  noteReferences: notes ?? source.noteReferences,
  commentReferences: comments ?? source.commentReferences,
  media: media ?? source.media,
  warnings: source.warnings,
);

LegacyWordStory _story(
  LegacyWordStory source, {
  List<LegacyWordBlock>? blocks,
  LegacyWordStoryKind? kind,
  LegacyWordHeaderFooterType? type,
  int? section,
}) => LegacyWordStory(
  id: source.id,
  kind: kind ?? source.kind,
  startCp: source.startCp,
  endCp: source.endCp,
  blocks: blocks ?? source.blocks,
  plainText: source.plainText,
  safeHtml: source.safeHtml,
  headerFooterType: type ?? source.headerFooterType,
  sectionIndex: section ?? source.sectionIndex,
);

WordHeaderTextboxAliasPair? _resolve(LegacyWordDocument document) {
  final reference = document.textboxReferences.single;
  return WordHeaderTextboxAliases(
    stories: document.stories,
    media: document.media,
    fields: document.fields,
    bookmarks: document.bookmarks,
    notes: document.noteReferences,
    comments: document.commentReferences,
  ).resolve(reference, [...reference.anchors, ...reference.headerAliases]);
}

LegacyWordDrawing _drawingPresentation(
  LegacyWordDrawing source,
  LegacyWordMediaPresentation presentation,
) => LegacyWordDrawing(
  shapeId: source.shapeId,
  anchorCp: source.anchorCp,
  headerStory: source.headerStory,
  leftTwips: source.leftTwips,
  topTwips: source.topTwips,
  rightTwips: source.rightTwips,
  bottomTwips: source.bottomTwips,
  horizontalOrigin: source.horizontalOrigin,
  verticalOrigin: source.verticalOrigin,
  wrapMode: source.wrapMode,
  wrapSide: source.wrapSide,
  behindText: source.behindText,
  anchorLocked: source.anchorLocked,
  source: source.source,
  officeArtArtifactId: source.officeArtArtifactId,
  imageId: source.imageId,
  textboxId: source.textboxId,
  nextTextboxShapeId: source.nextTextboxShapeId,
  presentation: presentation,
  shapeDeleted: source.shapeDeleted,
  cropTopFixed16: source.cropTopFixed16,
  cropBottomFixed16: source.cropBottomFixed16,
  cropLeftFixed16: source.cropLeftFixed16,
  cropRightFixed16: source.cropRightFixed16,
  shape: source.shape,
);

void main() {
  const insertion = LegacyWordRevisionInfo(
    author: 'Insertion owner',
    authorIndex: 1,
    rawDate: 0x51e554b2,
    saveId: 0x10203040,
    reason: 1,
  );
  const deletion = LegacyWordRevisionInfo(
    author: 'Deletion owner',
    authorIndex: 2,
    rawDate: 0x51e555b2,
    saveId: 0x50607080,
    reason: 2,
  );
  const reviewedOccurrences = <String, LegacyWordMediaPresentation>{
    'hidden occurrence': LegacyWordMediaPresentation(hidden: true),
    'insertion flag': LegacyWordMediaPresentation(inserted: true),
    'deletion flag': LegacyWordMediaPresentation(deleted: true),
    'independent insertion metadata': LegacyWordMediaPresentation(
      insertionRevision: insertion,
    ),
    'independent deletion metadata': LegacyWordMediaPresentation(
      deletionRevision: deletion,
    ),
    'both independent revision histories': LegacyWordMediaPresentation(
      insertionRevision: insertion,
      deletionRevision: deletion,
    ),
    'empty insertion metadata': LegacyWordMediaPresentation(
      insertionRevision: LegacyWordRevisionInfo(),
    ),
    'empty deletion metadata': LegacyWordMediaPresentation(
      deletionRevision: LegacyWordRevisionInfo(),
    ),
  };
  for (final shapeId in [1025, 1026]) {
    for (final entry in reviewedOccurrences.entries) {
      test('public alias excludes ${entry.key} on shape $shapeId', () {
        final source = parseLegacyWordDocument(headerTextboxAliasFixture());
        expect(_resolve(source), isNotNull);
        final media = source.media;
        final forged = _copy(
          source,
          media: LegacyWordMediaCatalog.from(
            assets: media.assets,
            pictures: media.pictures,
            drawings: [
              for (final drawing in media.drawings)
                drawing.shapeId == shapeId
                    ? _drawingPresentation(drawing, entry.value)
                    : drawing,
            ],
            embeddedObjects: media.embeddedObjects,
            vbaProjects: media.vbaProjects,
            artifacts: media.artifacts,
            notices: media.notices,
          ),
        );
        expect(_resolve(forged), isNull);
        expect(() => convertLegacyWordDocument(forged), throwsFormatException);
      });
    }
  }

  test(
    'native activation control only changes section title-page semantics',
    () {
      final input = File(_sourcePath).readAsBytesSync();
      final original = BoundedCfbReader(input);
      final control = enableHeaderTitlePage(input);
      final changed = BoundedCfbReader(control.bytes);
      final oldWord = ByteData.sublistView(original.readPath('WordDocument')!);
      final newWord = ByteData.sublistView(changed.readPath('WordDocument')!);
      final tableName = oldWord.getUint16(10, Endian.little) & 0x200 == 0
          ? '0Table'
          : '1Table';
      final before = original.readPath(tableName)!,
          after = changed.readPath(tableName)!;
      for (final pair in [11, 41, 50, 58]) {
        final offset = oldWord.getUint32(154 + pair * 8, Endian.little);
        final size = oldWord.getUint32(158 + pair * 8, Endian.little);
        expect(newWord.getUint32(154 + pair * 8, Endian.little), offset);
        expect(newWord.getUint32(158 + pair * 8, Endian.little), size);
        expect(
          after.sublist(offset, offset + size),
          before.sublist(offset, offset + size),
        );
      }
      for (final entry in original.childrenOf(original.root)) {
        if (entry.isStorage ||
            entry.name == tableName ||
            entry.name == 'WordDocument') {
          continue;
        }
        expect(changed.readPath(entry.name), original.readEntry(entry));
      }
      final parsed = parseLegacyWordDocument(control.bytes);
      expect(parsed.sections.single.titlePage, isTrue);
      expect(
        parsed.textboxReferences.single.headerAliases.single.shapeId,
        1026,
      );
      expect(
        _boxes(
          ZipDecoder().decodeBytes(convertLegacyWordDocument(parsed).bytes),
        ),
        [
          ['ALPHA'],
          ['ALPHA'],
        ],
      );
      expect(() => enableHeaderTitlePage(control.bytes), throwsStateError);
    },
  );
  for (final entry in textboxBoundaryCases.entries) {
    test('normal and first header occurrences retain ${entry.key}', () {
      final input = headerTextboxAliasFixture(rawText: entry.value.$1);
      final document = parseLegacyWordDocument(input);
      final reference = document.textboxReferences.single;
      expect(reference.id, 1);
      expect(reference.chainLength, 1);
      expect(reference.declaredChainLength, isNull);
      expect(reference.anchors.single.shapeId, 1025);
      expect(reference.anchors.single.anchorCp, 7);
      expect(reference.headerAliases.single.shapeId, 1026);
      expect(reference.headerAliases.single.anchorCp, 10);
      expect(reference.headerAliases.single.chainIndex, 0);
      expect(reference.headerAliases.single.nextShapeId, isNull);
      expect(
        document.warnings,
        contains(LegacyWordWarning.recoveredHeaderTextboxAlias),
      );
      expect(
        document.warnings,
        isNot(contains(LegacyWordWarning.recoveredTextboxChainLength)),
      );
      final conversion = convertLegacyWordDocument(document);
      final package = ZipDecoder().decodeBytes(conversion.bytes);
      expect(_boxes(package), [entry.value.$2, entry.value.$2]);
      expect(conversion.preservedCounts['textboxes'], 2);
      final evidence =
          jsonDecode(
                utf8.decode(
                  package.findFile('word/evidence/manifest.json')!.content,
                ),
              )
              as Map;
      final records = evidence['records'] as List;
      final recovered = records.singleWhere(
        (record) => record['kind'] == 'headerTextboxAlias',
      );
      expect(recovered['chainLength'], 1);
      expect(
        (recovered['occurrences'] as List).map((value) => value['shapeId']),
        [1025, 1026],
      );
      expect(
        records.where((record) => record['kind'] == 'textboxChain'),
        isEmpty,
      );
      for (final file in package.files.where(
        (file) =>
            file.name.startsWith('word/header') && file.name.endsWith('.xml'),
      )) {
        expect(utf8.decode(file.content), isNot(contains('mso-next-textbox')));
      }
      expect(
        parseLegacyWordDocument(
          input,
        ).textboxReferences.single.headerAliases.single.shapeId,
        1026,
      );
    });
  }

  test(
    'exact retained native failure is recovered without changing source activation',
    () {
      final input = File(_sourcePath).readAsBytesSync();
      final original = input.toList();
      final document = parseLegacyWordDocument(input);
      final reference = document.textboxReferences.single;
      expect(reference.anchors.single.shapeId, 1025);
      expect(reference.headerAliases.single.shapeId, 1026);
      final package = ZipDecoder().decodeBytes(
        convertLegacyWordDocument(document).bytes,
      );
      expect(_boxes(package), [
        ['ALPHA'],
        ['ALPHA'],
      ]);
      final body = XmlDocument.parse(
        utf8.decode(package.findFile('word/document.xml')!.content),
      );
      expect(body.findAllElements('titlePg', namespace: _w), isEmpty);
      final types = body
          .findAllElements('headerReference', namespace: _w)
          .map((element) => element.getAttribute('type', namespace: _w));
      expect(types, containsAll(['default', 'first']));
      expect(input, original);
    },
  );

  final hostile = <String, List<int> Function()>{
    'same-header duplicates': () => headerTextboxAliasFixture(sameHeader: true),
    'main-story duplicates': () => headerTextboxAliasFixture(mainStory: true),
    'first footer instead of header': () =>
        headerTextboxAliasFixture(firstFooter: true),
    'declared two-frame chain': () => headerTextboxAliasFixture(count: 2),
    'unresolved first shape': () => headerTextboxAliasFixture(lid: 9999),
    'nonzero index without a next link': () =>
        headerTextboxAliasFixture(secondIndex: 1),
    'different textbox story': () => headerTextboxAliasFixture(secondStory: 2),
    'next link on primary': () => headerTextboxAliasFixture(firstNext: 1026),
    'next link on alias': () => headerTextboxAliasFixture(secondNext: 1025),
    'third occurrence': () => headerTextboxAliasFixture(extraOccurrence: true),
    'group child context': () => headerTextboxAliasFixture(shapeFlags: 0xa02),
    'different shape type': () => headerTextboxAliasFixture(shapeType: 1),
    'field identity': () =>
        headerTextboxAliasFixture(rawText: '\x13 PAGE \x141\x15\r\r'),
    'inserted content': () =>
        headerTextboxAliasFixture(textProperties: wordSprm(0x0801, [1])),
    'deleted content': () =>
        headerTextboxAliasFixture(textProperties: wordSprm(0x0800, [1])),
  };
  for (final entry in hostile.entries) {
    test('${entry.key} remain rejected', () {
      expect(
        () => parseLegacyWordDocument(Uint8List.fromList(entry.value())),
        throwsFormatException,
      );
    });
  }

  test('a true contiguous chain is retained as flow with no header alias', () {
    final document = parseLegacyWordDocument(
      headerTextboxAliasFixture(count: 2, secondIndex: 1, firstNext: 1026),
    );
    final reference = document.textboxReferences.single;
    expect(reference.chainLength, 2);
    expect(reference.anchors.map((anchor) => anchor.chainIndex), [0, 1]);
    expect(reference.headerAliases, isEmpty);
  });

  test('the writer rejects forged cross-section and footer aliases', () {
    final source = parseLegacyWordDocument(headerTextboxAliasFixture());
    for (final changed in [
      _story(
        source.stories.firstWhere(
          (story) => story.headerFooterType == LegacyWordHeaderFooterType.first,
        ),
        section: 1,
      ),
      _story(
        source.stories.firstWhere(
          (story) => story.headerFooterType == LegacyWordHeaderFooterType.first,
        ),
        kind: LegacyWordStoryKind.footer,
      ),
      _story(
        source.stories.firstWhere(
          (story) => story.headerFooterType == LegacyWordHeaderFooterType.first,
        ),
        type: LegacyWordHeaderFooterType.even,
      ),
    ]) {
      final forged = _copy(
        source,
        stories: [
          for (final story in source.stories)
            story.id == changed.id ? changed : story,
        ],
      );
      expect(_resolve(forged), isNull);
      expect(() => convertLegacyWordDocument(forged), throwsFormatException);
    }
  });

  test(
    'identity-bearing text events do not become independent header copies',
    () {
      final source = parseLegacyWordDocument(headerTextboxAliasFixture());
      final text = source.stories.singleWhere(
        (story) => story.kind == LegacyWordStoryKind.headerTextbox,
      );
      for (final forged in [
        _copy(
          source,
          bookmarks: [
            LegacyWordBookmark(
              name: 'Inside',
              startCp: text.startCp,
              endCp: text.endCp,
            ),
          ],
        ),
        _copy(
          source,
          bookmarks: [
            LegacyWordBookmark(
              name: 'Boundary',
              startCp: text.endCp,
              endCp: text.endCp,
            ),
          ],
        ),
        _copy(
          source,
          fields: [
            LegacyWordField(
              id: 0,
              storyId: text.id,
              startCp: text.startCp,
              endCp: text.endCp,
              instruction: 'PAGE',
              storedResult: '1',
              type: 'PAGE',
            ),
          ],
        ),
        _copy(
          source,
          notes: [
            LegacyWordNoteReference(
              id: 1,
              anchorCp: text.startCp,
              storyId: 'missing-note',
              endnote: false,
            ),
          ],
        ),
        _copy(
          source,
          comments: [
            LegacyWordCommentReference(
              id: 1,
              anchorCp: text.startCp,
              storyId: 'missing-comment',
            ),
          ],
        ),
      ]) {
        expect(_resolve(forged), isNull);
        expect(() => convertLegacyWordDocument(forged), throwsFormatException);
      }
    },
  );

  test('nested media and table content are outside the alias recovery', () {
    final source = parseLegacyWordDocument(headerTextboxAliasFixture());
    final text = source.stories.singleWhere(
      (story) => story.kind == LegacyWordStoryKind.headerTextbox,
    );
    final media = LegacyWordMediaCatalog.from(
      drawings: source.media.drawings,
      pictures: [
        LegacyWordPicture(
          id: 'nested',
          cp: text.startCp,
          source: source.media.drawings.first.source,
          officeArtArtifactId: 'unresolved',
        ),
      ],
    );
    final table = _story(
      text,
      blocks: [
        LegacyWordTable(
          startCp: text.startCp,
          endCp: text.endCp,
          rows: const [],
        ),
      ],
    );
    for (final forged in [
      _copy(source, media: media),
      _copy(
        source,
        stories: [
          for (final story in source.stories)
            story.id == text.id ? table : story,
        ],
      ),
    ]) {
      expect(_resolve(forged), isNull);
      expect(() => convertLegacyWordDocument(forged), throwsFormatException);
    }
  });

  test('public aliases cannot forge chain lengths or repeat an occurrence', () {
    final source = parseLegacyWordDocument(headerTextboxAliasFixture());
    final original = source.textboxReferences.single;
    for (final (count, aliases) in [
      (2, original.headerAliases),
      (1, [...original.headerAliases, ...original.headerAliases]),
      (1, original.anchors),
    ]) {
      final forged = _copy(
        source,
        references: [
          LegacyWordTextboxReference(
            id: original.id,
            storyId: original.storyId,
            inHeaderFooter: true,
            shapeId: original.shapeId,
            anchorCp: original.anchorCp,
            chainLength: count,
            anchors: original.anchors,
            headerAliases: aliases,
          ),
        ],
      );
      expect(_resolve(forged), isNull);
      expect(() => convertLegacyWordDocument(forged), throwsFormatException);
    }
  });

  test(
    'styled text is allowed but paragraph and run review histories are excluded',
    () {
      final source = parseLegacyWordDocument(
        headerTextboxAliasFixture(textProperties: wordSprm(0x0835, [1])),
      );
      expect(_resolve(source), isNotNull);
      final text = source.stories.singleWhere(
        (story) => story.kind == LegacyWordStoryKind.headerTextbox,
      );
      final original = text.blocks.single as LegacyWordParagraph;
      for (final changed in [
        LegacyWordParagraph(
          startCp: original.startCp,
          endCp: original.endCp,
          runs: original.runs,
          style: const LegacyWordParagraphStyle(listId: 1),
        ),
        LegacyWordParagraph(
          startCp: original.startCp,
          endCp: original.endCp,
          runs: original.runs,
          numberingRevision: LegacyWordNumberingRevision(inserted: true),
        ),
        LegacyWordParagraph(
          startCp: original.startCp,
          endCp: original.endCp,
          runs: original.runs,
          formattingRevision: const LegacyWordParagraphFormattingRevision(
            previousStyle: LegacyWordParagraphStyle(),
          ),
        ),
        LegacyWordParagraph(
          startCp: original.startCp,
          endCp: original.endCp,
          runs: original.runs,
          mark: const LegacyWordParagraphMark(deleted: true),
        ),
        LegacyWordParagraph(
          startCp: original.startCp,
          endCp: original.endCp,
          runs: [
            LegacyWordRun(
              startCp: original.startCp,
              endCp: original.endCp - 1,
              text: 'ALPHA',
              formattingRevision: const LegacyWordCharacterFormattingRevision(
                previousStyle: LegacyWordCharacterStyle(),
              ),
            ),
          ],
        ),
      ]) {
        final forged = _copy(
          source,
          stories: [
            for (final story in source.stories)
              story.id == text.id ? _story(story, blocks: [changed]) : story,
          ],
        );
        expect(_resolve(forged), isNull);
        expect(() => convertLegacyWordDocument(forged), throwsFormatException);
      }
    },
  );
}
