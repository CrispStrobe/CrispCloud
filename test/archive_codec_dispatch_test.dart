import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' as ar;
import 'package:crypto/crypto.dart';
import 'package:crisp_cloud/services/archive_compression_writer.dart';
import 'package:crisp_cloud/services/archive_endpoint_policy.dart';
import 'package:crisp_cloud/services/archive_lz4_codec.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/internal_viewer_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

Uint8List _file(String name) =>
    File('test/fixtures/archives/$name').readAsBytesSync();
Uint8List _skip(Uint8List frame) {
  final prefix = Uint8List(8 + 777);
  final data = ByteData.sublistView(prefix);
  data.setUint32(0, 0x184d2a50, Endian.little);
  data.setUint32(4, 777, Endian.little);
  return Uint8List.fromList([...prefix, ...frame]);
}

void main() {
  for (final (suffix, nativeName) in [
    ('tar.lz', 'codec-container.tar.lz'),
    ('tar.Z', 'codec-container.tar.Z'),
    ('taz', 'codec-container.tar.Z'),
  ]) {
    test(
      '$suffix discovers independent wrapped TAR content with its writer policy',
      () async {
        final bytes = _file(nativeName);
        final archive = await openViewerArchive(bytes, name: 'tree.$suffix');
        addTearDown(archive.close);
        expect(archive.formatName, 'tar');
        expect(
          archive.members.any(
            (member) =>
                !member.isFile &&
                member.name.replaceAll(RegExp(r'/+$'), '') == 'empty',
          ),
          isTrue,
        );
        final member = archive.members.singleWhere((member) => member.isFile);
        expect(member.name, 'docs/hello.txt');
        expect(
          utf8.decode(await archive.readMember(member)),
          'Independent wrapped TAR\n',
        );
        expect(member.posixMode! & 0xfff, 0x1a0);
        expect(
          (await ArchiveEndpointPolicy.inspect(
            bytes,
            'tree.$suffix',
            archive,
            null,
          )).reason,
          suffix == 'tar.lz' ? isNotNull : isNull,
        );
      },
    );
  }

  for (final (name, format, expectedSize) in [
    ('lzip-reference-default.lz', 'lzip', 175000),
  ]) {
    test(
      '$format routes by magic with no extension and exposes check notices',
      () async {
        final bytes = _file(name);
        expect(
          const InternalViewerService().detectMode('Payload', header: bytes),
          ViewerMode.archive,
        );
        final archive = await openViewerArchive(bytes, name: 'Payload');
        addTearDown(archive.close);
        expect(archive.formatName, format);
        final actual = await archive.readMember(archive.members.single);
        expect(actual.length, expectedSize);
        expect(
          utf8.decode(actual),
          'Independent Lzip reference fixture\n' * 5000,
        );
        expect(archive.notices.join(' '), contains('CRC32'));
      },
    );
  }

  test(
    'UNIX compress magic and no-checksum notice survive a misleading name',
    () async {
      final bytes = _file('compress-reference-text.Z');
      expect(
        const InternalViewerService().detectMode('Payload', header: bytes),
        ViewerMode.archive,
      );
      final archive = await openViewerArchive(bytes, name: 'misleading.zip');
      addTearDown(archive.close);
      expect(archive.formatName, 'compress');
      final actual = await archive.readMember(archive.members.single);
      expect(actual.length, 43200);
      expect(
        sha256.convert(actual).toString(),
        '56c42e0be9190123e12f5ab6f5e536a28f63344326d40eff4ea6b17d394cd008',
      );
      expect(archive.notices.join(' '), contains('no stored checksum'));
    },
  );

  for (final kind in [
    ArchiveCompressionKind.lz4,
    ArchiveCompressionKind.zstd,
  ]) {
    test(
      'shared skippable magic resolves to ${kind.name} beyond the sniff header',
      () async {
        final expected = Uint8List.fromList(utf8.encode('exact payload'));
        final bytes = _skip(encodeArchiveCompression(expected, kind));
        expect(
          const InternalViewerService().detectMode(
            'Payload',
            header: bytes.sublist(0, 16),
          ),
          ViewerMode.archive,
        );
        final archive = await openViewerArchive(bytes, name: 'Payload');
        addTearDown(archive.close);
        expect(archive.formatName, kind.name);
        expect(await archive.readMember(archive.members.single), expected);
        expect(decompressSingleFile(bytes, 'misleading.gz').data, expected);
        expect(
          (await ArchiveEndpointPolicy.inspect(
            bytes,
            'file.${kind.name == 'zstd' ? 'zst' : 'lz4'}',
            archive,
            null,
          )).reason,
          isNotNull,
        );
      },
    );
  }

  test(
    'LZ4 frame collections are readable without silently losing frames on save',
    () async {
      final first = encodeArchiveLz4(Uint8List.fromList([1, 2]));
      final second = encodeArchiveLz4(Uint8List.fromList([3]));
      final bytes = Uint8List.fromList([...first, ...second]);
      final archive = await openViewerArchive(bytes, name: 'data.lz4');
      addTearDown(archive.close);
      expect(await archive.readMember(archive.members.single), [1, 2, 3]);
      expect(archive.notices.join(' '), contains('read-only'));
      expect(
        (await ArchiveEndpointPolicy.inspect(
          bytes,
          'data.lz4',
          archive,
          null,
        )).reason,
        isNotNull,
      );
    },
  );

  test(
    'binary CPIO is discovered after compression without an inner suffix',
    () async {
      final bytes = encodeArchiveLz4(_file('reference-binary-be.cpio'));
      final archive = await openViewerArchive(bytes, name: 'Payload.lz4');
      addTearDown(archive.close);
      expect(archive.formatName, 'cpio');
      expect(archive.members.length, 4);
      expect(archive.isDirectCompressionPayload, isFalse);
      expect(
        (await ArchiveEndpointPolicy.inspect(
          bytes,
          'Payload.lz4',
          archive,
          null,
        )).reason,
        isNotNull,
      );
    },
  );

  test('strong archive magic wins over a raw-LZMA filename hint', () async {
    final bytes = Uint8List.fromList(
      ar.ZipEncoder().encode(
        ar.Archive()..addFile(ar.ArchiveFile.bytes('file', [4, 5])),
      ),
    );
    final archive = await openViewerArchive(bytes, name: 'wrong.lzma');
    addTearDown(archive.close);
    expect(archive.formatName, 'zip');
    expect(await archive.readMember(archive.members.single), [4, 5]);
    expect(
      (await ArchiveEndpointPolicy.inspect(
        bytes,
        'wrong.lzma',
        archive,
        null,
      )).reason,
      isNotNull,
    );
  });

  test(
    'new compression input, output and recursion limits remain enforced',
    () async {
      var bytes = encodeArchiveLz4(Uint8List.fromList([1, 2, 3, 4]));
      await expectLater(
        openViewerArchiveSource(
          koni.MemoryByteSource(bytes),
          name: 'file.lz4',
          maxBufferedContainerBytes: bytes.length - 1,
        ),
        throwsA(isA<ArchiveViewException>()),
      );
      await expectLater(
        openViewerArchive(bytes, name: 'file.lz4', maxMemberBytes: 3),
        throwsA(isA<ArchiveViewException>()),
      );
      final small = await openViewerArchive(
        bytes,
        name: 'file.lz4',
        maxMemberBytes: 128 * 1024 * 1024,
      );
      expect(await small.readMember(small.members.single), [1, 2, 3, 4]);
      await small.close();
      for (var i = 0; i < 4; i++) {
        bytes = encodeArchiveLz4(bytes);
      }
      await expectLater(
        openViewerArchive(bytes, name: 'nested.lz4'),
        throwsA(isA<ArchiveViewException>()),
      );
    },
  );
}
