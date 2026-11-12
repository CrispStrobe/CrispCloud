// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/media_revision_fixture.dart';
import 'support/media_word_fixture.dart';
import 'support/structured_word_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

Map<String, Uint8List> _parts(Uint8List bytes) => {
  for (final file in ZipDecoder().decodeBytes(bytes))
    if (file.isFile) file.name: file.content,
};
XmlDocument _xml(Map<String, Uint8List> parts, [String name = 'document']) =>
    XmlDocument.parse(utf8.decode(parts['word/$name.xml']!));
Iterable<XmlElement> _elements(XmlNode node, String name) =>
    node.findAllElements(name, namespace: _w);
String? _attr(XmlElement node, String name) =>
    node.getAttribute(name, namespace: _w);

String _targetName(String kind) => switch (kind) {
  'inline-picture' || 'floating-picture' || 'footnote-picture' => 'drawing',
  'editable-shape' => 'pict',
  'embedded-object' => 'object',
  'footnote-anchor' => 'footnoteReference',
  'endnote-anchor' => 'endnoteReference',
  'comment-anchor' => 'commentReference',
  _ => throw ArgumentError.value(kind),
};

LegacyWordMediaPresentation _presentation(
  LegacyWordDocument document,
  String kind,
) => switch (kind) {
  'inline-picture' ||
  'footnote-picture' => document.media.pictures.single.presentation,
  'floating-picture' ||
  'editable-shape' => document.media.drawings.single.presentation,
  'embedded-object' => document.media.embeddedObjects.single.presentation,
  'footnote-anchor' ||
  'endnote-anchor' => document.noteReferences.single.presentation,
  'comment-anchor' => document.commentReferences.single.presentation,
  _ => throw ArgumentError.value(kind),
};

// Independent native markup projection. Retaining or dropping the object run
// itself is checked, not just accepted/rejected surrounding text.
XmlDocument _project(
  XmlDocument source, {
  required bool acceptInsertion,
  required bool acceptDeletion,
}) {
  final result = XmlDocument.parse(source.toXmlString());
  final changes = result.descendants
      .whereType<XmlElement>()
      .where(
        (node) =>
            node.name.namespaceUri == _w &&
            const {'ins', 'del'}.contains(node.name.local),
      )
      .toList()
      .reversed;
  for (final change in changes) {
    final parent = change.parent!;
    final retain = change.name.local == 'ins'
        ? acceptInsertion
        : !acceptDeletion;
    final offset = parent.children.indexOf(change);
    parent.children.replaceRange(
      offset,
      offset + 1,
      retain ? change.children.map((child) => child.copy()).toList() : [],
    );
  }
  return result;
}

LegacyWordDocument _publicPicture(LegacyWordMediaPresentation presentation) {
  final original = parseLegacyWordDocument(inlinePictureWordFixture());
  final picture = original.media.pictures.single;
  return LegacyWordDocument(
    blocks: original.blocks,
    sections: original.sections,
    plainText: original.plainText,
    safeHtml: original.safeHtml,
    media: LegacyWordMediaCatalog.from(
      assets: original.media.assets,
      pictures: [
        LegacyWordPicture(
          id: picture.id,
          cp: picture.cp,
          source: picture.source,
          officeArtArtifactId: picture.officeArtArtifactId,
          imageId: picture.imageId,
          widthTwips: picture.widthTwips,
          heightTwips: picture.heightTwips,
          presentation: presentation,
        ),
      ],
    ),
  );
}

void main() {
  for (final kind in mediaReviewKinds) {
    for (final (inserted, deleted) in [
      (true, false),
      (false, true),
      (true, true),
    ]) {
      test(
        '$kind retains separate insertion=$inserted deletion=$deleted history',
        () {
          final source = mediaReviewFixture(
            kind,
            inserted: inserted,
            deleted: deleted,
          );
          final original = Uint8List.fromList(source);
          final document = parseLegacyWordDocument(source);
          final presentation = _presentation(document, kind);
          expect(presentation.inserted, inserted);
          expect(presentation.deleted, deleted);
          if (inserted) {
            expect(
              presentation.insertionRevision,
              LegacyWordRevisionInfo(
                author: 'Alice',
                time: DateTime.utc(2026, 11, 12, 8, 45),
                authorIndex: 1,
                rawDate: mediaInsertionDttm,
                saveId: 0x10203040,
                reason: 7,
              ),
            );
          } else {
            expect(presentation.insertionRevision, isNull);
          }
          if (deleted) {
            expect(
              presentation.deletionRevision,
              LegacyWordRevisionInfo(
                author: 'Bob',
                time: DateTime.utc(2026, 11, 13, 9, 15),
                authorIndex: 2,
                rawDate: mediaDeletionDttm,
                saveId: 0x50607080,
                reason: 9,
              ),
            );
          } else {
            expect(presentation.deletionRevision, isNull);
          }
          expect(presentation.revisionAuthor, deleted ? 'Bob' : 'Alice');
          final result = convertLegacyWordDocument(document);
          final parts = _parts(result.bytes),
              xml = _xml(
                parts,
                kind == 'footnote-picture' ? 'footnotes' : 'document',
              );
          final target = _elements(xml, _targetName(kind)).single;
          final run = target.ancestors.whereType<XmlElement>().firstWhere(
            (node) => node.name.local == 'r' && node.name.namespaceUri == _w,
          );
          expect(_attr(run, 'rsidR'), inserted ? '10203040' : null);
          expect(_attr(run, 'rsidDel'), deleted ? '50607080' : null);
          final revisions = target.ancestors
              .whereType<XmlElement>()
              .where((node) => const {'ins', 'del'}.contains(node.name.local))
              .toList();
          expect(revisions.map((node) => node.name.local), [
            if (deleted) 'del',
            if (inserted) 'ins',
          ]);
          for (final revision in revisions) {
            final insertion = revision.name.local == 'ins';
            expect(_attr(revision, 'author'), insertion ? 'Alice' : 'Bob');
            expect(
              _attr(revision, 'date'),
              insertion ? '2026-11-12T08:45:00' : '2026-11-13T09:15:00',
            );
          }
          final ids = xml.descendants
              .whereType<XmlElement>()
              .where((node) => const {'ins', 'del'}.contains(node.name.local))
              .map((node) => _attr(node, 'id'))
              .toList();
          expect(ids.toSet().length, ids.length);
          for (final acceptInsertion in [false, true]) {
            for (final acceptDeletion in [false, true]) {
              final projected = _project(
                xml,
                acceptInsertion: acceptInsertion,
                acceptDeletion: acceptDeletion,
              );
              final retained =
                  (!inserted || acceptInsertion) &&
                  (!deleted || !acceptDeletion);
              expect(
                _elements(projected, _targetName(kind)).length,
                retained ? 1 : 0,
                reason:
                    'Projection must select the native object/reference itself.',
              );
            }
          }
          if (const {
            'inline-picture',
            'floating-picture',
            'footnote-picture',
          }.contains(kind)) {
            expect(
              parts.entries
                  .singleWhere((entry) => entry.key.endsWith('.png'))
                  .value,
              orderedEquals(mediaFixturePng()),
            );
          }
          if (kind == 'footnote-picture') {
            final relationships = XmlDocument.parse(
              utf8.decode(parts['word/_rels/footnotes.xml.rels']!),
            );
            final image = relationships
                .findAllElements('Relationship')
                .singleWhere(
                  (node) => node.getAttribute('Type')!.endsWith('/image'),
                );
            final blip = target
                .findAllElements(
                  'blip',
                  namespace:
                      'http://schemas.openxmlformats.org/drawingml/2006/main',
                )
                .single;
            expect(
              blip.getAttribute(
                'embed',
                namespace:
                    'http://schemas.openxmlformats.org/officeDocument/2006/relationships',
              ),
              image.getAttribute('Id'),
            );
            expect(
              parts.containsKey('word/${image.getAttribute('Target')}'),
              isTrue,
            );
            expect(_elements(_xml(parts), 'drawing'), isEmpty);
            expect(_elements(_xml(parts), 'footnoteReference'), hasLength(1));
          }
          if (kind.endsWith('-anchor')) {
            final story = kind.replaceFirst('-anchor', 's');
            expect(
              _elements(_xml(parts, story), 't').map((e) => e.innerText).join(),
              'Original story',
            );
          }
          expect(source, orderedEquals(original));
        },
      );
    }
  }

  test('absent insertion metadata cannot borrow deletion provenance', () {
    final document = parseLegacyWordDocument(
      mediaReviewFixture(
        'inline-picture',
        properties: mediaReviewProperties(insertionMetadata: false),
      ),
    );
    final presentation = document.media.pictures.single.presentation;
    expect(presentation.insertionRevision!.author, isNull);
    expect(presentation.insertionRevision!.time, isNull);
    expect(presentation.deletionRevision!.author, 'Bob');
    expect(
      document.warnings,
      contains(LegacyWordWarning.revisionMetadataIncomplete),
    );
    final result = convertLegacyWordDocument(document),
        xml = _xml(_parts(result.bytes));
    final insertion = _elements(xml, 'ins').single;
    expect(_attr(insertion, 'author'), '');
    expect(_attr(insertion, 'date'), isNull);
    expect(_attr(_elements(xml, 'del').single, 'author'), 'Bob');
    expect(
      result.limitations,
      contains(LegacyWordConversionLimitation.revisions),
    );
  });

  test(
    'unknown author and malformed date stay incomplete for only that revision',
    () {
      final document = parseLegacyWordDocument(
        mediaReviewFixture(
          'inline-picture',
          properties: mediaReviewProperties(
            insertionAuthor: 7,
            insertionDate: 0,
          ),
        ),
      );
      final presentation = document.media.pictures.single.presentation;
      expect(presentation.insertionRevision!.authorIndex, 7);
      expect(presentation.insertionRevision!.rawDate, 0);
      expect(presentation.insertionRevision!.author, isNull);
      expect(presentation.insertionRevision!.time, isNull);
      expect(presentation.deletionRevision!.author, 'Bob');
      final xml = _xml(_parts(convertLegacyWordDocument(document).bytes));
      expect(_attr(_elements(xml, 'ins').single, 'date'), isNull);
      expect(
        _attr(_elements(xml, 'del').single, 'date'),
        '2026-11-13T09:15:00',
      );
    },
  );

  test('false revision flags do not synthesize edits from metadata alone', () {
    final document = parseLegacyWordDocument(
      mediaReviewFixture('inline-picture', inserted: false, deleted: false),
    );
    final presentation = document.media.pictures.single.presentation;
    expect(presentation.insertionRevision, isNull);
    expect(presentation.deletionRevision, isNull);
    final xml = _xml(_parts(convertLegacyWordDocument(document).bytes));
    expect(_elements(xml, 'ins'), isEmpty);
    expect(_elements(xml, 'del'), isEmpty);
    final run = _elements(xml, 'drawing').single.parentElement!;
    expect(_attr(run, 'rsidR'), isNull);
    expect(_attr(run, 'rsidDel'), isNull);
  });

  test('shared image bytes retain independent occurrence revisions', () {
    final document = parseLegacyWordDocument(
      StructuredWordFixture(
        pieces: const [WordFixturePiece('\x01\x01\r')],
        characterRuns: [
          for (var index = 0; index < 2; index++)
            WordFixtureFkpRun(
              8192 + index,
              8193 + index,
              properties: [
                ...wordSprm(0x0855, [1]),
                ...wordSprm(0x6a03, wordU32(16)),
                ...mediaReviewProperties(
                  inserted: index == 0,
                  deleted: index == 1,
                ),
              ],
            ),
          const WordFixtureFkpRun(8194, 8195),
        ],
        extraTablePairs: {51: mediaReviewAuthors()},
        extraStreams: {
          'Data': Uint8List.fromList([
            ...List.filled(16, 0),
            ...inlinePictureData(),
          ]),
        },
      ).build(),
    );
    expect(document.media.assets, hasLength(1));
    expect(document.media.pictures, hasLength(2));
    expect(
      document.media.pictures[0].presentation.insertionRevision!.author,
      'Alice',
    );
    expect(document.media.pictures[0].presentation.deletionRevision, isNull);
    expect(
      document.media.pictures[1].presentation.deletionRevision!.author,
      'Bob',
    );
    expect(document.media.pictures[1].presentation.insertionRevision, isNull);
    final parts = _parts(convertLegacyWordDocument(document).bytes),
        xml = _xml(parts);
    expect(_elements(xml, 'drawing'), hasLength(2));
    for (final accepted in [false, true]) {
      final projected = _project(
        xml,
        acceptInsertion: accepted,
        acceptDeletion: accepted,
      );
      final run = _elements(projected, 'drawing').single.parentElement!;
      expect(
        _attr(run, accepted ? 'rsidR' : 'rsidDel'),
        accepted ? '10203040' : '50607080',
      );
    }
    expect(parts.keys.where((name) => name.endsWith('.png')), hasLength(1));
  });

  test(
    'private-field masking keeps separate source identities without exposing objects',
    () {
      const text = '\x13IF\x14\x01\x15\r';
      final document = parseLegacyWordDocument(
        StructuredWordFixture(
          pieces: const [WordFixturePiece(text)],
          characterRuns: [
            const WordFixtureFkpRun(8192, 8196),
            WordFixtureFkpRun(
              8196,
              8197,
              properties: [
                ...wordSprm(0x0855, [1]),
                ...wordSprm(0x6a03, wordU32(16)),
                ...mediaReviewProperties(),
              ],
            ),
            const WordFixtureFkpRun(8197, 8199),
          ],
          extraTablePairs: {
            51: mediaReviewAuthors(),
            16: [
              ...wordU32(0),
              ...wordU32(3),
              ...wordU32(5),
              ...wordU32(text.length),
              0x13,
              7,
              0x14,
              0,
              0x15,
              0xa0,
            ],
          },
          extraStreams: {
            'Data': Uint8List.fromList([
              ...List.filled(16, 0),
              ...inlinePictureData(),
            ]),
          },
        ).build(),
      );
      final presentation = document.media.pictures.single.presentation;
      expect(presentation.hidden, isTrue);
      expect(presentation.insertionRevision!.author, 'Alice');
      expect(presentation.deletionRevision!.author, 'Bob');
      expect(presentation.insertionRevision!.rawDate, mediaInsertionDttm);
      expect(presentation.deletionRevision!.rawDate, mediaDeletionDttm);
      final parts = _parts(convertLegacyWordDocument(document).bytes);
      expect(_elements(_xml(parts), 'drawing'), isEmpty);
      expect(
        parts.keys.where((name) => name.startsWith('word/media/')),
        isEmpty,
      );
      expect(document.safeHtml, isNot(contains('data:image')));
    },
  );

  test(
    'legacy public model metadata remains a backward-compatible fallback',
    () {
      final document = _publicPicture(
        LegacyWordMediaPresentation(
          inserted: true,
          deleted: true,
          revisionAuthor: 'Legacy caller',
          revisionTime: DateTime(2025, 2, 3, 4, 5),
        ),
      );
      final xml = _xml(_parts(convertLegacyWordDocument(document).bytes));
      for (final tag in ['ins', 'del']) {
        expect(_attr(_elements(xml, tag).single, 'author'), 'Legacy caller');
        expect(
          _attr(_elements(xml, tag).single, 'date'),
          '2025-02-03T04:05:00',
        );
      }
    },
  );

  test(
    'explicit incomplete public history wins over legacy compatibility data',
    () {
      final document = _publicPicture(
        LegacyWordMediaPresentation(
          inserted: true,
          revisionAuthor: 'Unrelated deletion author',
          revisionTime: DateTime(2025, 2, 3),
          insertionRevision: const LegacyWordRevisionInfo(authorIndex: 12),
        ),
      );
      final result = convertLegacyWordDocument(document),
          xml = _xml(_parts(result.bytes));
      final insertion = _elements(xml, 'ins').single;
      expect(_attr(insertion, 'author'), '');
      expect(_attr(insertion, 'date'), isNull);
      expect(
        result.limitations,
        contains(LegacyWordConversionLimitation.revisions),
      );
    },
  );

  test('public media save identifiers obey the existing unsigned bound', () {
    for (final value in [-1, 0x100000000]) {
      for (final insertion in [true, false]) {
        final info = LegacyWordRevisionInfo(author: 'Author', saveId: value);
        final document = _publicPicture(
          LegacyWordMediaPresentation(
            inserted: insertion,
            deleted: !insertion,
            insertionRevision: insertion ? info : null,
            deletionRevision: insertion ? null : info,
          ),
        );
        expect(
          () => convertLegacyWordDocument(document),
          throwsFormatException,
        );
      }
    }
  });

  test(
    'malformed binary revision operands still fail before media conversion',
    () {
      for (final property in [
        wordSprm(0x0801, [3]),
        wordSprm(0x6816, [1, 2, 3]),
      ]) {
        expect(
          () => parseLegacyWordDocument(
            mediaReviewFixture('inline-picture', properties: property),
          ),
          throwsFormatException,
        );
      }
    },
  );
}
