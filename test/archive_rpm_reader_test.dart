import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/services/archive_rpm_reader.dart';
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import 'support/archive_package_fixtures.dart';
import 'support/archive_rpm_fixtures.dart';

Future<ViewerArchive> _open(Uint8List bytes, {int limit = kArchiveReadLimit}) =>
    openRpmArchive(koni.MemoryByteSource(bytes), maxMemberBytes: limit);

class _OwnedSource implements koni.ByteSource {
  _OwnedSource(this.bytes, {this.shortReadAt, this.failReadAt});
  final Uint8List bytes;
  final int? shortReadAt, failReadAt;
  final reads = <(int, int)>[];
  int closes = 0;
  @override
  int get length => bytes.length;
  @override
  String? get name => 'fixture.rpm';
  @override
  Future<Uint8List> read(int offset, int length) async {
    if (closes != 0) throw StateError('Read after close');
    if (offset < 0 || length < 0 || offset + length > bytes.length) {
      throw StateError('Out-of-bounds source read');
    }
    reads.add((offset, length));
    if (offset == failReadAt) throw StateError('Injected read failure');
    return Uint8List.sublistView(
      bytes,
      offset,
      offset + length - (offset == shortReadAt && length > 0 ? 1 : 0),
    );
  }

  @override
  Future<void> close() async => closes++;
}

void main() {
  for (final compressor in ['none', 'gzip', 'bzip2', 'xz', 'zstd']) {
    for (final crc in [false, true]) {
      test(
        '$compressor ${crc ? 'CRC' : 'newc'} payload contents and metadata',
        () async {
          final archive = await _open(
            RpmFixture(compressor: compressor, crc: crc).bytes,
          );
          addTearDown(archive.close);
          expect(archive.formatName, 'rpm');
          expect(archive.members.map((e) => e.name), [
            'docs',
            'docs/hello.txt',
            'empty',
          ]);
          expect(archive.members.first.isFile, isFalse);
          final file = archive.members[1];
          expect(file.posixMode, 0x81a4);
          expect(
            file.modified,
            DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true),
          );
          expect(utf8.decode(await archive.readMember(file)), 'hello\n');
          expect(await archive.readMember(archive.members[2]), isEmpty);
          expect(archive.notices.join(' '), contains('Publisher signatures'));
          expect(archive.notices.join(' '), contains('not verified'));
        },
      );
    }
  }

  for (final codec in ['gzip', 'bzip2']) {
    test('independent rpmbuild/libarchive $codec fixture', () async {
      final archive = await _open(
        await File('test/fixtures/archives/libarchive-$codec.rpm')
            .readAsBytes(),
      );
      addTearDown(archive.close);
      expect(archive.members.map((e) => e.name), [
        'etc/file1',
        'etc/file2',
        'etc/file3',
      ]);
      for (final entry in archive.members) {
        expect(entry.size, 6);
        expect(entry.posixMode, 0x81a4);
        expect(
          entry.modified,
          DateTime.fromMillisecondsSinceEpoch(86401000, isUtc: true),
        );
        expect(utf8.decode(await archive.readMember(entry)), 'hello\n');
      }
    });
  }

  test('legacy RPM without payload tags defaults to gzip CPIO', () async {
    final archive = await _open(
      RpmFixture(payloadTags: false, payloadDigests: false).bytes,
    );
    addTearDown(archive.close);
    expect(
      utf8.decode(await archive.readMember(archive.members[1])),
      'hello\n',
    );
  });

  test('retains safe special-entry and path traversal rules', () async {
    final archive = await _open(
      RpmFixture(
        entries: [
          const PackageFixtureEntry('../outside.txt', [1]),
          const PackageFixtureEntry('link', [
            46,
            46,
            47,
            111,
            117,
            116,
          ], mode: 0xa1ff),
          const PackageFixtureEntry('hard-link', [3], links: 2),
          const PackageFixtureEntry('safe', [4]),
        ],
      ).bytes,
    );
    addTearDown(archive.close);
    expect(archive.members.first.pathEscapedRoot, isTrue);
    expect(archive.members[1].isSpecial, isTrue);
    expect(archive.members[2].isSpecial, isTrue);
    for (final member in archive.members.take(3)) {
      await expectLater(
        archive.readMember(member),
        throwsA(isA<ArchiveViewException>()),
      );
    }
    expect(await archive.readMember(archive.members.last), [4]);
  });

  test('source ownership, member identity, streaming and close', () async {
    final source = _OwnedSource(RpmFixture().bytes);
    final archive = await openRpmArchive(source, maxMemberBytes: 100);
    expect(source.closes, 0);
    final other = await _open(RpmFixture().bytes);
    addTearDown(other.close);
    await expectLater(
      archive.readMember(other.members[1]),
      throwsA(isA<ArchiveViewException>()),
    );
    final chunks = await archive
        .openMember(archive.members[1], chunkSize: 2)
        .toList();
    expect(chunks.expand((e) => e).toList(), utf8.encode('hello\n'));
    expect(chunks.every((e) => e.length <= 2), isTrue);
    await archive.close();
    await archive.close();
    expect(source.closes, 1);
    await expectLater(
      archive.readMember(archive.members[1]),
      throwsA(isA<ArchiveViewException>()),
    );
  });

  test(
    'per-member limit is retained even with a larger read override',
    () async {
      final archive = await _open(RpmFixture().bytes, limit: 5);
      addTearDown(archive.close);
      await expectLater(
        archive.readMember(archive.members[1], maxBytes: 100),
        throwsA(isA<ArchiveViewException>()),
      );
      await expectLater(
        archive.openMember(archive.members[1], maxBytes: 100).toList(),
        throwsA(isA<ArchiveViewException>()),
      );
    },
  );

  for (final compressor in ['gzip', 'bzip2', 'xz', 'zstd']) {
    test('$compressor expansion bound is enforced', () async {
      final source = _OwnedSource(
        RpmFixture(
          compressor: compressor,
          entries: [PackageFixtureEntry('large', List.filled(32 * 1024, 42))],
        ).bytes,
      );
      await expectLater(
        openRpmArchive(
          source,
          maxMemberBytes: kArchiveReadLimit,
          maxBufferedContainerBytes: 4096,
        ),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(source.closes, 1);
    });
  }

  test('packed payload bound is checked before reading it', () async {
    final fixture = RpmFixture(compressor: 'none');
    final source = _OwnedSource(fixture.bytes);
    await expectLater(
      openRpmArchive(
        source,
        maxMemberBytes: 1000,
        maxBufferedContainerBytes: 32,
      ),
      throwsA(isA<ArchiveViewException>()),
    );
    expect(
      source.reads.any((read) => read.$1 == fixture.payloadOffset),
      isFalse,
    );
    expect(source.closes, 1);
  });

  final malformed = <String, void Function(RpmFixture)>{
    'lead magic': (f) => f.bytes[0] = 0,
    'unsupported lead': (f) => f.bytes[4] = 2,
    'unsupported lead minor': (f) => f.bytes[5] = 1,
    'unsupported signature type': (f) => f.bytes[79] = 1,
    'signature header magic': (f) => f.bytes[96] = 0,
    'header magic': (f) => f.bytes[f.headerOffset] = 0,
    'header reserved fields': (f) => f.bytes[f.headerOffset + 4] = 1,
    'header index count': (f) =>
        ByteData.sublistView(f.bytes).setUint32(f.headerOffset + 8, 200001),
    'header data length': (f) =>
        ByteData.sublistView(f.bytes)
            .setUint32(f.headerOffset + 12, 0xffffffff),
    'negative index offset': (f) =>
        ByteData.sublistView(f.bytes).setInt32(f.indexOffset(1124) + 8, -1),
    'index extent': (f) =>
        ByteData.sublistView(f.bytes)
            .setUint32(f.indexOffset(1046) + 12, 0xffffffff),
    'invalid type': (f) =>
        ByteData.sublistView(f.bytes).setUint32(f.indexOffset(1124) + 4, 10),
    'wrong semantic tag type': (f) =>
        ByteData.sublistView(f.bytes).setUint32(f.indexOffset(1124) + 4, 7),
    'duplicate tag': (f) =>
        ByteData.sublistView(f.bytes).setUint32(f.indexOffset(1125), 1124),
    'zero value count': (f) =>
        ByteData.sublistView(f.bytes).setUint32(f.indexOffset(1124) + 12, 0),
    'multiple scalar strings': (f) =>
        ByteData.sublistView(f.bytes).setUint32(f.indexOffset(1124) + 12, 2),
    'misaligned integers': (f) =>
        ByteData.sublistView(f.bytes).setUint32(f.indexOffset(1046) + 8, 1),
    'wrong payload signature': (f) => f.bytes[f.payloadOffset] = 0,
    'header/payload size mismatch': (f) =>
        ByteData.sublistView(f.bytes)
            .setUint32(f.dataOffset(1000, signature: true), 1),
    'header/payload MD5 mismatch': (f) =>
        f.bytes[f.dataOffset(1004, signature: true)] ^= 1,
    'unpacked size mismatch': (f) =>
        ByteData.sublistView(f.bytes).setUint32(f.dataOffset(1046), 1),
    'unsupported digest algorithm': (f) =>
        ByteData.sublistView(f.bytes).setUint32(f.dataOffset(5093), 2),
    'compressed payload digest mismatch': (f) => f.bytes[f.dataOffset(5092)] =
        f.bytes[f.dataOffset(5092)] == 48 ? 49 : 48,
    'expanded payload digest mismatch': (f) => f.bytes[f.dataOffset(5097)] =
        f.bytes[f.dataOffset(5097)] == 48 ? 49 : 48,
  };
  for (final example in malformed.entries) {
    test('rejects ${example.key} without leaking its source', () async {
      // Do not let a catch-all MD5 failure mask the field's own validation.
      final fixture = RpmFixture(
        checksum: example.key == 'header/payload MD5 mismatch',
      );
      example.value(fixture);
      final source = _OwnedSource(fixture.bytes);
      await expectLater(
        openRpmArchive(source, maxMemberBytes: kArchiveReadLimit),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(source.closes, 1);
    });
  }

  test('rejects unterminated header strings', () async {
    final fixture = RpmFixture(
      checksum: false,
      headerTags: [RpmFixtureTag.string(6000, 'last')],
    );
    fixture.bytes[fixture.payloadOffset - 1] = 65;
    await expectLater(
      _open(fixture.bytes),
      throwsA(isA<ArchiveViewException>()),
    );
  });

  test('rejects nonzero signature alignment padding', () async {
    final fixture = RpmFixture(
      signatureTags: [
        const RpmFixtureTag(1100, 7, 1, [1]),
      ],
    );
    fixture.bytes[fixture.headerOffset - 1] = 1;
    await expectLater(
      _open(fixture.bytes),
      throwsA(isA<ArchiveViewException>()),
    );
  });

  test('CPIO CRC remains enforced on member extraction', () async {
    final archive = await _open(
      RpmFixture(
        crc: true,
        entries: [
          const PackageFixtureEntry('bad', [1, 2, 3], checksum: 7),
        ],
      ).bytes,
    );
    addTearDown(archive.close);
    await expectLater(
      archive.readMember(archive.members.single),
      throwsA(isA<ArchiveViewException>()),
    );
  });

  for (final compressor in ['gzip', 'bzip2', 'xz', 'zstd']) {
    test(
      'rejects truncated $compressor payload without relying on RPM digests',
      () async {
        final fixture = RpmFixture(
          compressor: compressor,
          checksum: false,
          payloadDigests: false,
        );
        final cut = Uint8List.sublistView(
          fixture.bytes,
          0,
          fixture.bytes.length - 5,
        );
        ByteData.sublistView(cut).setUint32(
          fixture.dataOffset(1000, signature: true),
          cut.length - fixture.headerOffset,
        );
        await expectLater(_open(cut), throwsA(isA<ArchiveViewException>()));
      },
    );
    test('rejects corrupt $compressor payload integrity', () async {
      final fixture = RpmFixture(
        compressor: compressor,
        checksum: false,
        payloadDigests: false,
      );
      fixture.bytes[fixture.bytes.length - (compressor == 'gzip' ? 8 : 1)] ^=
          0x40;
      await expectLater(
        _open(fixture.bytes),
        throwsA(isA<ArchiveViewException>()),
      );
    });
  }

  final unsupported = <String, RpmFixture Function()>{
    'RPM v6': () => RpmFixture(headerTags: [RpmFixtureTag.uint32(5114, 6)]),
    'non-CPIO payload': () => RpmFixture(format: 'tar'),
    'unsupported compressor': () => RpmFixture(declaredCompressor: 'lzma'),
    'mismatched compressor': () => RpmFixture(declaredCompressor: 'xz'),
    'stripped CPIO payload': () => RpmFixture(
      compressor: 'none',
      payload: Uint8List.fromList(ascii.encode('07070X00000000')),
    ),
    'old octal CPIO payload': () => RpmFixture(
      compressor: 'none',
      payload: Uint8List.fromList(ascii.encode('07070700000000')),
    ),
    'non-CPIO decoded data': () =>
        RpmFixture(payload: Uint8List.fromList(utf8.encode('not CPIO'))),
  };
  for (final example in unsupported.entries) {
    test('rejects ${example.key}', () async {
      await expectLater(
        _open(example.value().bytes),
        throwsA(isA<ArchiveViewException>()),
      );
    });
  }

  test('rejects truncated lead, headers and data extents', () async {
    final fixture = RpmFixture();
    for (final end in [
      0,
      4,
      95,
      96,
      111,
      fixture.headerOffset - 1,
      fixture.headerOffset + 15,
      fixture.payloadOffset - 1,
    ]) {
      final source = _OwnedSource(Uint8List.sublistView(fixture.bytes, 0, end));
      await expectLater(
        openRpmArchive(source, maxMemberBytes: 1024),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(source.closes, 1);
    }
  });

  for (final offset in [0, 96]) {
    test('short metadata read at $offset closes the source', () async {
      final source = _OwnedSource(RpmFixture().bytes, shortReadAt: offset);
      await expectLater(
        openRpmArchive(source, maxMemberBytes: 1000),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(source.closes, 1);
    });
  }

  test('payload read failure closes the source', () async {
    final fixture = RpmFixture();
    final source = _OwnedSource(
      fixture.bytes,
      failReadAt: fixture.payloadOffset,
    );
    await expectLater(
      openRpmArchive(source, maxMemberBytes: 1000),
      throwsA(isA<ArchiveViewException>()),
    );
    expect(source.closes, 1);
  });
}
