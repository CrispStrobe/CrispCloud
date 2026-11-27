import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

final class _ReusingEncoding extends Encoding {
  final bytes = Uint8List.fromList([65]);

  @override
  String get name => 'reusing-test-encoding';

  @override
  Converter<List<int>, String> get decoder => ascii.decoder;

  @override
  Converter<String, List<int>> get encoder => ascii.encoder;

  @override
  List<int> encode(String input) => bytes;
}

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

    test('text and binary writes own their part buffers', () {
      final package = OpcPackage.openBytes(
        OpcPackage.create(OpcPackageKind.word).save(),
      );
      final document = package.getPart('/word/document.xml')!;
      expect(document.isModified, isFalse);
      document.writeText('Grüße & 😀');
      expect(document.isModified, isTrue);
      expect(document.readText(), 'Grüße & 😀');

      final codec = _ReusingEncoding();
      document.writeText('ignored', encoding: codec);
      codec.bytes[0] = 66;
      expect(document.readText(), 'A');

      document.writeBytes(codec.bytes);
      codec.bytes[0] = 67;
      expect(document.readText(), 'B');
      final reopened = OpcPackage.openBytes(
        package.save(reuseCompressedParts: true),
      );
      expect(reopened.getPart('/word/document.xml')!.readText(), 'B');
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

    test('CRC32 matches the IEEE vector across subviews and split points', () {
      final bytes = Uint8List.fromList([0, ...ascii.encode('123456789'), 0]);
      final data = Uint8List.sublistView(bytes, 1, bytes.length - 1);
      expect(Crc32.compute(data), 0xCBF43926);
      expect(Crc32.compute(data.toList()), 0xCBF43926);
      for (var split = 0; split <= data.length; split++) {
        final head = Uint8List.sublistView(data, 0, split);
        final tail = Uint8List.sublistView(data, split);
        expect(Crc32.compute(tail, Crc32.compute(head)), 0xCBF43926);
      }
    });

    test('CRC32 keeps the right checksum across bulk blocks and tails', () {
      final bytes = Uint8List(4100);
      final data = Uint8List.sublistView(bytes, 1);
      for (var i = 0; i < data.length; i++) {
        data[i] = i % 251;
      }
      expect(Crc32.compute(data), 0x48D1721D);
      for (var split = 0; split < 16; split++) {
        final head = Uint8List.sublistView(data, 0, split);
        final tail = Uint8List.sublistView(data, split);
        expect(Crc32.compute(tail, Crc32.compute(head)), 0x48D1721D);
      }
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

    test('native ZIP compression packs XML and preserves copied entries', () {
      final xml = utf8.encode(
        '<w:p><w:r><w:t>Repeated document text</w:t></w:r></w:p>' * 2500,
      );
      const name = 'word/document.xml';
      final writer = ZipWriter()..addFile(name, xml);
      final reader = ZipReader.fromBytes(writer.close());
      final entry = reader[name]!;
      final compressed = reader.compressedPayload(entry);
      expect(entry.compressionMethod, zipMethodDeflate);
      expect(compressed.length, lessThan(RawDeflate.deflate(xml).length));
      expect(reader.read(name, maxBytes: xml.length), xml);

      final copy = ZipWriter()..copyFile(reader, name);
      final reopened = ZipReader.fromBytes(copy.close());
      expect(reopened.compressedPayload(reopened[name]!), compressed);
      expect(reopened.read(name), xml);
    }, testOn: 'vm');
  });
}
