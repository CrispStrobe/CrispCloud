import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  group('OpcPackage', () {
    test('creates, mutates, and reopens a Word package', () {
      final OpcPackage created = OpcPackage.create(OpcPackageKind.word);
      expect(created.kind, OpcPackageKind.word);
      final PackagePart? document = created.getPart('/word/document.xml');
      expect(document, isNotNull);
      document!.writeText(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:body><w:p><w:r><w:t>Quds</w:t></w:r></w:p></w:body></w:document>',
      );
      created
          .relationshipsFor('/word/document.xml')
          .add(
            type: RelationshipTypes.oleObject,
            target: 'embeddings/oleObject1.bin',
          );

      final Uint8List bytes = created.save();
      expect(bytes[0], 0x50);
      expect(bytes[1], 0x4b);

      final OpcPackage opened = OpcPackage.openBytes(bytes);
      expect(opened.kind, OpcPackageKind.word);
      expect(
        opened.contentTypes.contentTypeFor('/word/document.xml'),
        OfficeContentTypes.wordMain,
      );
      expect(
        opened.getPart('/word/document.xml')!.readText(),
        contains('Quds'),
      );
      expect(
        opened
            .relationshipsFor('/word/document.xml')
            .firstByType(RelationshipTypes.oleObject)!
            .target,
        'embeddings/oleObject1.bin',
      );
    });

    test('allocates unique relationship ids', () {
      final RelationshipCollection rels = RelationshipCollection(
        sourcePartUri: '/',
      );
      rels.add(type: 't', target: 'a', id: 'rId2');
      expect(rels.allocateId(), 'rId1');
      expect(rels.add(type: 't', target: 'b').id, 'rId3');
    });

    test('resolves relative OPC targets', () {
      expect(
        OpcUris.resolve('/word/document.xml', 'embeddings/oleObject1.bin'),
        '/word/embeddings/oleObject1.bin',
      );
      expect(
        OpcUris.resolve('/word/document.xml', '../media/image1.png'),
        '/media/image1.png',
      );
      expect(
        OpcUris.relativize('/word/document.xml', '/word/embeddings/x.bin'),
        'embeddings/x.bin',
      );
    });

    test('ZIP store and deflate round-trip', () {
      final ZipWriter writer = ZipWriter();
      writer.addFile('plain.txt', utf8.encode('hello'), store: true);
      writer.addFile('deflated.txt', utf8.encode('hello world ' * 20));
      final Uint8List zip = writer.close();
      final ZipReader reader = ZipReader.fromBytes(zip);
      expect(utf8.decode(reader.read('plain.txt')), 'hello');
      expect(utf8.decode(reader.read('deflated.txt')), 'hello world ' * 20);
    });
  });
}
