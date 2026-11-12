import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' as codecs;
import 'package:crisp_cloud/services/archive_compression_writer.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final repeated = Uint8List.fromList(
    utf8.encode('CrispCloud content\n' * 20000),
  );
  final suffixes = {
    ArchiveCompressionKind.gzip: '.gz',
    ArchiveCompressionKind.bzip2: '.bz2',
    ArchiveCompressionKind.xz: '.xz',
    ArchiveCompressionKind.zstd: '.zst',
  };

  for (final kind in ArchiveCompressionKind.values) {
    test(
      '${kind.name} compresses, verifies and round-trips real content',
      () async {
        final packed = encodeArchiveCompression(repeated, kind);
        expect(packed.length, lessThan(repeated.length ~/ 10));
        expect(archiveCompressionForBytes(packed), kind);
        expect(
          () => validateArchiveCompressionRewrite(packed, kind),
          returnsNormally,
        );
        final archive = await openViewerArchive(
          packed,
          name: 'content.txt${suffixes[kind]}',
        );
        addTearDown(archive.close);
        expect(await archive.readMember(archive.members.single), repeated);
        final corrupt = Uint8List.fromList(packed);
        // Alter the trailer or index rather than accidentally making a valid
        // differently-compressed stream with the same content.
        corrupt[corrupt.length -
                (kind == ArchiveCompressionKind.xz ? 16 : 1)] ^=
            0x80;
        await expectLater(
          openViewerArchive(corrupt, name: 'content.txt${suffixes[kind]}'),
          throwsA(anything),
        );
      },
    );

    test(
      '${kind.name} writes empty input and enforces output bounds',
      () async {
        final empty = encodeArchiveCompression(Uint8List(0), kind);
        final archive = await openViewerArchive(
          empty,
          name: 'empty${suffixes[kind]}',
        );
        addTearDown(archive.close);
        expect(await archive.readMember(archive.members.single), isEmpty);
        expect(
          () => encodeArchiveCompression(repeated, kind, maxOutputBytes: 8),
          throwsA(isA<ArchiveViewException>()),
        );
      },
    );
  }

  for (final check in [0, 1, 4, 10]) {
    test('XZ check $check is accepted by Python liblzma independently', () async {
      final directory = await Directory.systemTemp.createTemp('crisp-xz-test-');
      addTearDown(() => directory.delete(recursive: true));
      final packed = encodeArchiveCompression(
        repeated,
        ArchiveCompressionKind.xz,
        xzCheck: check,
      );
      final file = File('${directory.path}/data.xz');
      await file.writeAsBytes(packed);
      final result = await Process.run('python3', [
        '-c',
        'import lzma,sys; data=lzma.open(sys.argv[1],"rb").read(); '
            'assert data == b"CrispCloud content\\n" * 20000; print(len(data))',
        file.path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect('${result.stdout}'.trim(), '${repeated.length}');
    });
  }

  test(
    'gzip preserves bounded name, comment, extra and header CRC fields',
    () async {
      final header = <int>[
        0x1f,
        0x8b,
        8,
        2 | 4 | 8 | 16,
        4,
        3,
        2,
        1,
        0,
        3,
        3,
        0,
        1,
        2,
        3,
        ...utf8.encode('original.txt'),
        0,
        ...utf8.encode('retained comment'),
        0,
      ];
      final crc = codecs.getCrc32(header);
      header.addAll([crc & 0xff, crc >> 8 & 0xff]);
      final bytes = Uint8List.fromList(header);
      final packed = encodeArchiveCompression(
        repeated,
        ArchiveCompressionKind.gzip,
        gzipHeader: bytes,
      );
      expect(archiveGzipHeader(packed), bytes);
      expect(
        const codecs.GZipDecoder().decodeBytes(packed, verify: true),
        repeated,
      );
      bytes[bytes.length - 1] ^= 1;
      expect(
        () => archiveGzipHeader(bytes),
        throwsA(isA<ArchiveViewException>()),
      );
    },
  );

  test('malformed metadata and unsupported checks are refused', () {
    expect(
      () => archiveGzipHeader(Uint8List.fromList([0x1f, 0x8b])),
      throwsA(anything),
    );
    expect(
      () => encodeArchiveCompression(
        repeated,
        ArchiveCompressionKind.xz,
        xzCheck: 3,
      ),
      throwsA(anything),
    );
    expect(
      () => encodeArchiveCompression(
        repeated,
        ArchiveCompressionKind.gzip,
        level: -1,
      ),
      throwsArgumentError,
    );
  });

  for (final tail in <List<int>>[
    [0],
    utf8.encode('opaque trailing metadata'),
  ]) {
    test('bzip2 refuses a ${tail.length}-byte ignored trailing region', () {
      final packed = encodeArchiveCompression(
        repeated,
        ArchiveCompressionKind.bzip2,
      );
      final withTail = Uint8List.fromList([...packed, ...tail]);
      // This is a valid readable payload: the upstream decoder intentionally
      // ignores the suffix. Editing must explicitly refuse that lossy rewrite.
      expect(
        codecs.BZip2Decoder().decodeBytes(withTail, verify: true),
        repeated,
      );
      expect(
        () => validateArchiveCompressionRewrite(
          withTail,
          ArchiveCompressionKind.bzip2,
        ),
        throwsA(isA<ArchiveViewException>()),
      );
    });
  }

  test('bzip2 refuses a truncated following stream header', () {
    final packed = encodeArchiveCompression(
      repeated,
      ArchiveCompressionKind.bzip2,
    );
    final truncated = Uint8List.fromList([...packed, 0x42, 0x5a]);
    expect(
      () => validateArchiveCompressionRewrite(
        truncated,
        ArchiveCompressionKind.bzip2,
      ),
      throwsA(anything),
    );
  });

  test('bzip2 checks for trailing bytes after every concatenated payload', () {
    final first = encodeArchiveCompression(
      Uint8List.fromList([1, 2, 3]),
      ArchiveCompressionKind.bzip2,
    );
    final second = encodeArchiveCompression(
      Uint8List.fromList([4, 5]),
      ArchiveCompressionKind.bzip2,
    );
    final withTail = Uint8List.fromList([...first, ...second, 0x7f]);
    expect(codecs.BZip2Decoder().decodeBytes(withTail, verify: true), [
      1,
      2,
      3,
      4,
      5,
    ]);
    expect(
      () => validateArchiveCompressionRewrite(
        withTail,
        ArchiveCompressionKind.bzip2,
      ),
      throwsA(isA<ArchiveViewException>()),
    );
  });

  for (final kind in [
    ArchiveCompressionKind.gzip,
    ArchiveCompressionKind.xz,
    ArchiveCompressionKind.zstd,
  ]) {
    test(
      '${kind.name} refuses metadata-losing concatenated frame rewrites',
      () {
        final first = encodeArchiveCompression(repeated, kind);
        final combined = Uint8List.fromList([...first, ...first]);
        expect(
          () => validateArchiveCompressionRewrite(combined, kind),
          throwsA(isA<ArchiveViewException>()),
        );
      },
    );
  }
}
