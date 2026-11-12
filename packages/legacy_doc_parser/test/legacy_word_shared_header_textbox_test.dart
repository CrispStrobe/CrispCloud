// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/shared_header_textbox_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _v = 'urn:schemas-microsoft-com:vml';

List<XmlDocument> _parts(LegacyWordDocument document) => [
  for (final file in ZipDecoder().decodeBytes(
    convertLegacyWordDocument(document).bytes,
  ))
    if (RegExp(r'^word/(header|footer)\d+\.xml$').hasMatch(file.name))
      XmlDocument.parse(utf8.decode(file.content)),
];

void main() {
  for (final (role, slots) in [
    ('header', [0, 1, 4]),
    ('footer', [2, 3, 5]),
    ('header and footer', [0, 1, 2, 3, 4, 5]),
  ]) {
    test('distinct $role variants retain every shared singleton instance', () {
      final document = parseLegacyWordDocument(
        sharedHeaderTextboxFixture(slots: slots),
      );
      final reference = document.textboxReferences.single;
      expect(reference.chainLength, 1);
      expect(reference.anchors, hasLength(1));
      expect(reference.replicaAnchors, hasLength(slots.length - 1));
      expect(
        document.stories.where(
          (s) => s.kind == LegacyWordStoryKind.headerTextbox,
        ),
        hasLength(1),
      );
      expect(
        document.warnings,
        contains(LegacyWordWarning.recoveredSharedHeaderTextbox),
      );
      final parts = _parts(document);
      expect(parts, hasLength(slots.length));
      for (final part in parts) {
        expect(
          part.findAllElements('txbxContent', namespace: _w).single.innerText,
          'SHARED',
        );
        expect(
          part
              .findAllElements('rect', namespace: _v)
              .single
              .getAttribute('style'),
          isNot(contains('mso-next-textbox')),
        );
      }
    });
  }

  test('shared header fields replay in every owning part', () {
    final document = parseLegacyWordDocument(
      sharedHeaderTextboxFixture(field: true),
    );
    for (final part in _parts(document)) {
      expect(
        part
            .findAllElements('instrText', namespace: _w)
            .single
            .innerText
            .trim(),
        'PAGE',
      );
      expect(part.findAllElements('fldChar', namespace: _w), hasLength(3));
      expect(part.findAllElements('t', namespace: _w).map((t) => t.innerText), [
        'SHARED',
      ]);
    }
  });

  test('the source primary shape need not be the first header occurrence', () {
    final document = parseLegacyWordDocument(
      sharedHeaderTextboxFixture(firstShape: 1026),
    );
    final reference = document.textboxReferences.single;
    expect(reference.anchors.single.shapeId, 1026);
    expect(reference.replicaAnchors.single.shapeId, 1025);
    expect(
      _parts(document).map(
        (part) =>
            part.findAllElements('txbxContent', namespace: _w).single.innerText,
      ),
      ['SHARED', 'SHARED'],
    );
  });

  test('singleton without a replica does not report recovery', () {
    final document = parseLegacyWordDocument(
      sharedHeaderTextboxFixture(slots: [1]),
    );
    expect(document.textboxReferences.single.replicaAnchors, isEmpty);
    expect(
      document.warnings,
      isNot(contains(LegacyWordWarning.recoveredSharedHeaderTextbox)),
    );
  });

  for (final (name, source) in [
    ('same owner', sharedHeaderTextboxFixture(sameOwner: true)),
    ('declared multi-shape chain', sharedHeaderTextboxFixture(declared: 2)),
    ('wrong original shape', sharedHeaderTextboxFixture(firstShape: 1027)),
    ('nonzero continuation index', sharedHeaderTextboxFixture(indices: [0, 1])),
    (
      'cross-instance next link',
      sharedHeaderTextboxFixture(nextShapes: [1026, null]),
    ),
    ('replica next link', sharedHeaderTextboxFixture(nextShapes: [null, 1025])),
  ]) {
    test('rejects shared singleton with $name', () {
      expect(() => parseLegacyWordDocument(source), throwsFormatException);
    });
  }

  test('native first/even/default controls keep their independent stories', () {
    final document = parseLegacyWordDocument(
      File(
        'test/fixtures/word_native/header-textbox-page-variants.doc',
      ).readAsBytesSync(),
    );
    expect(document.textboxReferences, hasLength(3));
    expect(
      document.textboxReferences.every(
        (reference) =>
            reference.replicaAnchors.isEmpty && reference.chainLength == 1,
      ),
      isTrue,
    );
    expect(
      document.warnings,
      isNot(contains(LegacyWordWarning.recoveredSharedHeaderTextbox)),
    );
    final parts = _parts(document);
    expect(parts, hasLength(3));
    for (final part in parts) {
      expect(
        part
            .findAllElements('txbxContent', namespace: _w)
            .single
            .findAllElements('t', namespace: _w)
            .map((t) => t.innerText),
        ['BOX', 'CELL', 'AFTER_BOX'],
      );
    }
  });

  for (final context in ['paragraph', 'table']) {
    test(
      'native header $context anchor retains normal and first instances',
      () {
        final document = parseLegacyWordDocument(
          File(
            'test/fixtures/word_native/shared-header-textbox-$context.doc',
          ).readAsBytesSync(),
        );
        final reference = document.textboxReferences.single;
        expect(reference.chainLength, 1);
        expect(reference.anchors.map((a) => a.shapeId), [1025]);
        expect(reference.replicaAnchors.map((a) => a.shapeId), [1026]);
        final parts = _parts(document)
            .where(
              (part) =>
                  part.findAllElements('txbxContent', namespace: _w).isNotEmpty,
            )
            .toList();
        expect(parts, hasLength(2));
        for (final part in parts) {
          expect(
            part
                .findAllElements('txbxContent', namespace: _w)
                .single
                .findAllElements('t', namespace: _w)
                .map((t) => t.innerText),
            ['BOX', 'CELL', 'AFTER_BOX'],
          );
        }
      },
    );
  }
}
