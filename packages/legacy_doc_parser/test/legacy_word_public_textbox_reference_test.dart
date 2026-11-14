// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import '../tool/public_textbox_reference_web_acceptance.dart';
import 'support/public_textbox_reference_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _v = 'urn:schemas-microsoft-com:vml';

void main() {
  test('shared public textbox acceptance also passes on the VM', () {
    expect(verifyPublicTextboxReferenceWebAcceptance(), {
      'visibleCases': 17,
      'headerOwnerCases': 8,
      'inertEvidenceCases': 3,
      'malformedInputsRejected': 38,
      'convertedPackages': 20,
      'sourceMetadataUnchanged': true,
    });
  });

  for (final mutation in publicTextboxInvalidCases) {
    test('public textbox rejects $mutation', () {
      expect(
        () =>
            convertLegacyWordDocument(publicTextboxReferenceDocument(mutation)),
        throwsA(
          anyOf(isA<FormatException>(), isA<LegacyWordConversionException>()),
        ),
      );
    });
  }
  for (final mutation in publicTextboxHiddenInvalidCases) {
    test('hidden public textbox rejects $mutation', () {
      expect(
        () => convertLegacyWordDocument(
          publicTextboxReferenceDocument(mutation, hidden: true),
        ),
        throwsA(
          anyOf(isA<FormatException>(), isA<LegacyWordConversionException>()),
        ),
      );
    });
  }
  for (final mutation in publicTextboxValidCases) {
    test('public textbox preserves source chain for $mutation', () {
      final document = publicTextboxReferenceDocument(mutation);
      final inputOrder = document.textboxReferences.first.anchors
          .map((anchor) => anchor.chainIndex)
          .toList();
      final result = convertLegacyWordDocument(document);
      expect(
        document.textboxReferences.first.anchors
            .map((anchor) => anchor.chainIndex)
            .toList(),
        inputOrder,
      );
      final archive = ZipDecoder().decodeBytes(result.bytes);
      final xml = XmlDocument.parse(
        utf8.decode(
          archive.findFile(publicTextboxOutputPart(mutation))!.content,
        ),
      );
      final rects = xml.findAllElements('rect', namespace: _v).toList();
      final boxes = xml.findAllElements('txbxContent', namespace: _w).toList();
      if (mutation == 'unresolved-chain') {
        expect(rects, isEmpty);
        expect(boxes, isEmpty);
        final evidence = archive.files
            .where(
              (file) =>
                  file.name.startsWith('word/textboxEvidence') &&
                  file.name.endsWith('.xml'),
            )
            .single;
        final text = XmlDocument.parse(utf8.decode(evidence.content))
            .findAllElements('t', namespace: _w)
            .map((text) => text.innerText)
            .join();
        expect(text, 'One');
        final manifest =
            jsonDecode(
                  utf8.decode(
                    archive.findFile('word/evidence/manifest.json')!.content,
                  ),
                )
                as Map;
        final record = (manifest['records'] as List).cast<Map>().singleWhere(
          (record) => record['kind'] == 'textbox',
        );
        expect(record['chainLength'], 2);
        expect(
          result.limitations,
          contains(LegacyWordConversionLimitation.embeddedObjects),
        );
        return;
      }
      final two = !mutation.startsWith('single');
      expect(rects, hasLength(two ? 2 : 1));
      expect(
        rects.map((rect) => rect.getAttribute('id')).toSet(),
        hasLength(rects.length),
      );
      expect(result.preservedCounts['textboxes'], rects.length);
      final words = boxes
          .map(
            (box) => box
                .findAllElements('t', namespace: _w)
                .map((text) => text.innerText)
                .join(),
          )
          .toList();
      if (mutation.startsWith('two-stories')) {
        expect(words, ['One', 'Two']);
        expect(
          rects.every(
            (rect) => !rect.getAttribute('style')!.contains('mso-next-textbox'),
          ),
          isTrue,
        );
      } else if (two) {
        expect(words, ['One', '']);
        expect(rects.first.getAttribute('id'), '_legacyTextboxShape42');
        expect(
          rects.first.getAttribute('style'),
          contains('mso-next-textbox:#_legacyTextboxShape43'),
        );
        expect(
          rects.last.getAttribute('style'),
          isNot(contains('mso-next-textbox')),
        );
      } else {
        expect(words, ['One']);
        if (publicTextboxOutputPart(mutation) != 'word/document.xml') {
          final main = XmlDocument.parse(
            utf8.decode(archive.findFile('word/document.xml')!.content),
          );
          expect(main.findAllElements('txbxContent', namespace: _w), isEmpty);
        }
      }
    });
  }
  for (final mutation in ['single', 'chain']) {
    test('hidden valid public textbox retains $mutation as inert evidence', () {
      final result = convertLegacyWordDocument(
        publicTextboxReferenceDocument(mutation, hidden: true),
      );
      final archive = ZipDecoder().decodeBytes(result.bytes);
      final main = XmlDocument.parse(
        utf8.decode(archive.findFile('word/document.xml')!.content),
      );
      expect(main.findAllElements('txbxContent', namespace: _w), isEmpty);
      final evidence = archive.files.singleWhere(
        (file) => file.name.startsWith('word/textboxEvidence'),
      );
      expect(
        XmlDocument.parse(utf8.decode(evidence.content))
            .findAllElements('t', namespace: _w)
            .map((text) => text.innerText)
            .join(),
        'One',
      );
      final manifest =
          jsonDecode(
                utf8.decode(
                  archive.findFile('word/evidence/manifest.json')!.content,
                ),
              )
              as Map;
      final record = (manifest['records'] as List).cast<Map>().singleWhere(
        (record) => record['kind'] == 'textbox',
      );
      expect(record['chainLength'], mutation == 'single' ? 1 : 2);
      if (mutation == 'chain') {
        expect(
          (record['anchors'] as List).map(
            (anchor) => (anchor as Map)['shapeId'],
          ),
          [42, 43],
        );
      }
    });
  }
}
