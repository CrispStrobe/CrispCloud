// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/unidentified_textbox_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

List<Map> _records(Archive archive) =>
    ((jsonDecode(
                  utf8.decode(
                    archive.findFile('word/evidence/manifest.json')!.content,
                  ),
                )
                as Map)['records']
            as List)
        .cast<Map>();

void main() {
  for (final mutation in ['self', 'client-zero']) {
    for (final hidden in [false, true]) {
      test('$mutation hidden=$hidden preserves inert self-link evidence', () {
        final source = unidentifiedTextboxDocument(mutation, hidden: hidden);
        final result = convertLegacyWordDocument(source);
        final archive = ZipDecoder().decodeBytes(result.bytes);
        final body = XmlDocument.parse(
          utf8.decode(archive.findFile('word/document.xml')!.content),
        );
        expect(body.findAllElements('txbxContent', namespace: _w), isEmpty);
        final record = _records(
          archive,
        ).singleWhere((record) => record['kind'] == 'textbox');
        expect(record['reason'], 'unidentified singleton has a self-link');
        expect(record['nextShapeId'], 42);
        expect(record['shapeId'], 42);
        expect(record['anchorCp'], 1);
        final evidence = XmlDocument.parse(
          utf8.decode(archive.findFile(record['part'] as String)!.content),
        );
        expect(
          evidence
              .findAllElements('t', namespace: _w)
              .map((node) => node.innerText)
              .join(),
          'One',
        );
        expect(
          result.limitations,
          contains(LegacyWordConversionLimitation.embeddedObjects),
        );
        expect(source.media.drawings.single.nextTextboxShapeId, 42);
        expect(source.textboxReferences.single.anchors, isEmpty);
      });
    }
  }
  for (final mutation in [
    'client-id',
    'wrong-client',
    'nonself',
    'explicit-anchor',
    'header-alias',
    'replica',
    'wrong-anchor',
    'wrong-owner',
    'duplicate-owner',
  ]) {
    for (final hidden in [false, true]) {
      test('self-link recovery rejects $mutation hidden=$hidden', () {
        expect(
          () => convertLegacyWordDocument(
            unidentifiedTextboxDocument(mutation, hidden: hidden),
          ),
          throwsFormatException,
        );
      });
    }
  }
  test('POI Bug50936_1 retains unidentified self-linked boxes as evidence', () {
    final bytes = File(
      'test/fixtures/external/poi-20261114/poi/doc/Bug50936_1.doc',
    ).readAsBytesSync();
    final source = parseLegacyWordDocument(bytes);
    final linked = source.media.drawings
        .where(
          (shape) =>
              shape.textboxId == null &&
              shape.nextTextboxShapeId == shape.shapeId,
        )
        .toList();
    expect(linked, hasLength(13));
    for (final mode in LegacyWordFieldMode.values) {
      final result = convertLegacyWordDocument(source, fieldMode: mode);
      final archive = ZipDecoder().decodeBytes(result.bytes);
      final records = _records(
        archive,
      ).where((r) => r['reason'] == 'unidentified singleton has a self-link');
      expect(records, hasLength(13));
      for (final record in records) {
        expect(record['nextShapeId'], record['shapeId']);
        expect(record['chainLength'], 1);
        final body = utf8.decode(
          archive.findFile('word/document.xml')!.content,
        );
        expect(
          body,
          isNot(contains('id="_legacyTextboxShape${record['shapeId']}"')),
        );
      }
    }
  });
}
