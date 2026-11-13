// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/media_word_fixture.dart';

const _v = 'urn:schemas-microsoft-com:vml';
const _o = 'urn:schemas-microsoft-com:office:office';
const _r =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _placeholder = 'word/media/embedded-object-placeholder.png';

Map<String, Uint8List> _parts(Uint8List bytes) => {
  for (final file in ZipDecoder().decodeBytes(bytes))
    if (file.isFile) file.name: file.content,
};

void main() {
  test(
    'unavailable preview uses reviewed pixels and retains exact OLE bytes',
    () {
      final source = oleWordFixture();
      final before = Uint8List.fromList(source);
      final document = parseLegacyWordDocument(source);
      final result = convertLegacyWordDocument(document);
      final parts = _parts(result.bytes);
      expect(
        parts[_placeholder],
        File(
          'test/fixtures/word_native/generated-ole-placeholder.png',
        ).readAsBytesSync(),
      );
      expect(result.preservedCounts['generatedPlaceholderImages'], 1);
      expect(result.preservedCounts['embeddedObjectPlaceholders'], 1);
      expect(result.preservedCounts['images'], isNull);
      expect(
        result.limitations,
        contains(LegacyWordConversionLimitation.partialFormatting),
      );
      expect(
        parts['word/embeddings/oleObject1.bin'],
        document.media.embeddedObjects.single.storage.bytes,
      );
      final xml = XmlDocument.parse(utf8.decode(parts['word/document.xml']!));
      final shape = xml.findAllElements('shape', namespace: _v).single;
      final type = xml.findAllElements('shapetype', namespace: _v).single;
      expect(type.getAttribute('spt', namespace: _o), '75');
      expect(shape.getAttribute('type'), '#${type.getAttribute('id')}');
      expect(shape.getAttribute('style'), 'width:72pt;height:36pt');
      expect(
        shape.getAttribute('alt'),
        contains('original preview unavailable'),
      );
      expect(xml.findAllElements('textbox', namespace: _v), isEmpty);
      expect(source, before);
      expect(document.plainText.contains('Preview unavailable'), isFalse);
    },
  );

  test(
    'repeated objects share only generated pixels, not object identities',
    () {
      final original = parseLegacyWordDocument(oleWordFixture());
      final object = original.media.embeddedObjects.single;
      final document = LegacyWordDocument(
        blocks: original.blocks,
        sections: original.sections,
        plainText: original.plainText,
        safeHtml: original.safeHtml,
        fields: original.fields,
        media: LegacyWordMediaCatalog.from(
          embeddedObjects: [
            object,
            LegacyWordEmbeddedObject(
              id: '${object.id}-second',
              cp: object.cp,
              storage: object.storage,
              progId: object.progId,
              linked: object.linked,
              canEmbed: object.canEmbed,
            ),
          ],
        ),
      );
      final result = convertLegacyWordDocument(document);
      final parts = _parts(result.bytes);
      expect(parts.keys.where((path) => path.startsWith('word/media/')), [
        _placeholder,
      ]);
      expect(result.preservedCounts['generatedPlaceholderImages'], 1);
      expect(result.preservedCounts['embeddedObjectPlaceholders'], 2);
      final xml = XmlDocument.parse(utf8.decode(parts['word/document.xml']!));
      final objects = xml.findAllElements('OLEObject', namespace: _o).toList();
      expect(objects.length, 2);
      expect(
        objects.map((node) => node.getAttribute('ShapeID')).toSet().length,
        2,
      );
      expect(
        objects.map((node) => node.getAttribute('ObjectID')).toSet().length,
        2,
      );
      final images = xml.findAllElements('imagedata', namespace: _v);
      expect(images.length, 2);
      expect(
        images
            .map((node) => node.getAttribute('id', namespace: _r))
            .toSet()
            .length,
        1,
      );
      expect(parts['word/embeddings/oleObject1.bin'], object.storage.bytes);
      expect(parts['word/embeddings/oleObject2.bin'], object.storage.bytes);
    },
  );

  test('ordinary pictures do not acquire placeholder pixels or counts', () {
    final result = convertLegacyWord(inlinePictureWordFixture());
    final parts = _parts(result.bytes);
    expect(parts.containsKey(_placeholder), isFalse);
    expect(result.preservedCounts['generatedPlaceholderImages'], isNull);
    expect(result.preservedCounts['embeddedObjectPlaceholders'], isNull);
    expect(parts['word/media/image1.png'], mediaFixturePng());
    expect(result.preservedCounts['images'], 1);
  });
}
