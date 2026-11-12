import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' as ar;
import 'package:crisp_cloud/services/archive_hfs_reader.dart';
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import 'support/hfs_fixture.dart';

void main() {
  Future<ViewerArchive> open(HfsFixture fixture, {int limit = 1024 * 1024}) =>
      openHfsArchive(
        koni.MemoryByteSource(fixture.bytes),
        maxMemberBytes: limit,
      );

  test('reads a native-created HFS+ catalog with multiple leaves and an index root', () async {
    final bytes = const ar.GZipDecoder().decodeBytes(
      File('test/fixtures/archives/native-hfsplus.hfs.gz').readAsBytesSync(),
      verify: true,
      maxOutputSize: 8 * 1024 * 1024,
    );
    final archive = await openHfsArchive(
      koni.MemoryByteSource(bytes),
      maxMemberBytes: 1024,
    );
    addTearDown(archive.close);
    expect(archive.members, hasLength(44));
    expect(
      archive.members.singleWhere((m) => m.name == 'Applications').isSpecial,
      isTrue,
    );
    expect(
      archive.members.singleWhere((m) => m.name == 'docs').isFile,
      isFalse,
    );
    final files = archive.members.where((m) => m.isFile && !m.isSpecial);
    expect(files, hasLength(42));
    for (final member in files) {
      expect(
        utf8.decode(await archive.readMember(member)),
        'CrispCloud independently created HFS+ fixture\n',
        reason: member.name,
      );
    }
  });

  for (final hfsx in [false, true]) {
    test(
      '${hfsx ? 'HFSX' : 'HFS+'} lists Unicode paths and reads fragmented data forks',
      () async {
        final archive = await open(HfsFixture(hfsx: hfsx));
        addTearDown(archive.close);
        expect(archive.formatName, hfsx ? 'hfsx' : 'hfs+');
        expect(archive.members.map((entry) => entry.name), [
          '資料',
          'hello.txt',
          '資料/nested.bin',
        ]);
        final hello = archive.members.singleWhere(
          (entry) => entry.name == 'hello.txt',
        );
        expect(await archive.readMember(hello), HfsFixture.helloBytes);
        expect(hello.posixMode, 0x81a4);
        expect(
          hello.modified,
          DateTime.fromMillisecondsSinceEpoch(
            (3800000000 - 2082844800) * 1000,
            isUtc: true,
          ),
        );
        final nested = archive.members.singleWhere(
          (entry) => entry.name.endsWith('nested.bin'),
        );
        expect(await archive.readMember(nested), HfsFixture.nestedBytes);
      },
    );
  }

  test('opening is metadata-only and closing owns the input', () async {
    final source = _TrackingSource(HfsFixture().bytes);
    final archive = await openHfsArchive(source, maxMemberBytes: 1024);
    expect(source.reads.every((read) => read.$1 + read.$2 <= 20 * 512), isTrue);
    expect(source.closed, isFalse);
    await archive.close();
    await archive.close();
    expect(source.closes, 1);
    await expectLater(
      archive.readMember(archive.members[1]),
      throwsA(isA<ArchiveViewException>()),
    );
  });

  test('member caps prevent reading any oversized payload bytes', () async {
    final source = _TrackingSource(HfsFixture().bytes);
    final archive = await openHfsArchive(source, maxMemberBytes: 5);
    addTearDown(archive.close);
    final readCount = source.reads.length;
    await expectLater(
      archive.readMember(archive.members[1]),
      throwsA(isA<ArchiveViewException>()),
    );
    expect(source.reads.length, readCount);
  });

  test('a requested cap lower than the opening cap also applies', () async {
    final archive = await open(HfsFixture());
    addTearDown(archive.close);
    await expectLater(
      archive.readMember(archive.members[1], maxBytes: 4),
      throwsA(isA<ArchiveViewException>()),
    );
  });

  test(
    'rejects volumes beyond exact web offsets before reading catalog extents',
    () async {
      final fixture = HfsFixture();
      fixture.data.setUint32(1024 + 40, 1 << 24);
      fixture.data.setUint32(1024 + 44, 1 << 30);
      final source = _TrackingSource(fixture.bytes, reportedLength: 1 << 54);
      await expectLater(
        openHfsArchive(source, maxMemberBytes: 1024),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(source.reads, [(1024, 512)]);
      expect(source.closes, 1);
    },
  );

  test('empty data fork reads as an empty file', () async {
    final fixture = HfsFixture();
    fixture.bytes.fillRange(
      fixture.dataOffsets[17]! + 88,
      fixture.dataOffsets[17]! + 168,
      0,
    );
    final archive = await open(fixture);
    addTearDown(archive.close);
    expect(await archive.readMember(archive.members[1]), isEmpty);
  });

  test('special entries are marked and never followed or read', () async {
    final fixture = HfsFixture();
    fixture.data.setUint16(fixture.dataOffsets[17]! + 42, 0xa1ff);
    final archive = await open(fixture);
    addTearDown(archive.close);
    expect(archive.members[1].isSpecial, isTrue);
    await expectLater(
      archive.readMember(archive.members[1]),
      throwsA(isA<ArchiveViewException>()),
    );
  });

  final malformed = <String, void Function(HfsFixture)>{
    'signature': (f) => f.data.setUint16(1024, 0x4244),
    'version': (f) => f.data.setUint16(1026, 0),
    'dirty volume': (f) => f.data.setUint32(1028, 0),
    'boot volume needing journal replay': (f) => f.data.setUint32(1028, 0x900),
    'non-power-of-two block size': (f) => f.data.setUint32(1064, 513),
    'out-of-bounds volume': (f) => f.data.setUint32(1068, 10000),
    'catalog overflow extents': (f) => f.data.setUint32(1024 + 272 + 12, 17),
    'fork beyond image': (f) =>
        f.data.setUint32(f.dataOffsets[17]! + 88 + 16, 64),
    'fork allocation too small': (f) =>
        f.data.setUint64(f.dataOffsets[17]! + 88, 1000),
    'overlapping fork extents': (f) =>
        f.data.setUint32(f.dataOffsets[18]! + 88 + 24, 26),
    'empty extent with nonzero offset': (f) =>
        f.data.setUint32(f.dataOffsets[17]! + 88 + 24, 30),
    'compressed file': (f) => f.bytes[f.dataOffsets[17]! + 41] = 0x20,
    'hard-link chain': (f) => f.data.setUint16(f.dataOffsets[17]! + 2, 0x20),
    'hard-link Finder signature': (f) {
      f.data.setUint32(f.dataOffsets[17]! + 48, 0x686c6e6b);
      f.data.setUint32(f.dataOffsets[17]! + 52, 0x6866732b);
    },
    'invalid B-tree node size': (f) =>
        f.data.setUint16(HfsFixture.catalogOffset + 32, 513),
    'cyclic leaf chain': (f) => f.data.setUint32(HfsFixture.leafOffset, 1),
    'broken backward link': (f) =>
        f.data.setUint32(HfsFixture.leafOffset + 4, 1),
    'bad leaf kind': (f) => f.bytes[HfsFixture.leafOffset + 8] = 0,
    'overlapping record table': (f) =>
        f.data.setUint16(HfsFixture.leafOffset + 10, 65535),
    'descending record offsets': (f) =>
        f.data.setUint16(HfsFixture.leafOffset + HfsFixture.nodeSize - 4, 14),
    'mismatched leaf count': (f) =>
        f.data.setUint32(HfsFixture.catalogOffset + 20, 9),
    'missing parent': (f) => f.data.setUint32(f.keyOffsets[18]! + 2, 999),
    'parent cycle': (f) => f.data.setUint32(f.keyOffsets[16]! + 2, 16),
    'file parent': (f) => f.data.setUint32(f.keyOffsets[18]! + 2, 17),
    'duplicate catalog ID': (f) => f.data.setUint32(f.dataOffsets[18]! + 8, 17),
    'unsafe name separator': (f) => f.data.setUint16(f.keyOffsets[17]! + 8, 47),
    'invalid UTF-16': (f) => f.data.setUint16(f.keyOffsets[17]! + 8, 0xd800),
    'directory mode on a file': (f) =>
        f.data.setUint16(f.dataOffsets[17]! + 42, 0x41ed),
  };
  for (final entry in malformed.entries) {
    test('rejects ${entry.key} and closes the source', () async {
      final fixture = HfsFixture();
      entry.value(fixture);
      final source = _TrackingSource(fixture.bytes);
      await expectLater(
        openHfsArchive(source, maxMemberBytes: 1024),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(source.closes, 1);
    });
  }

  test(
    'data-fork overflow extents fail on read without partial extraction',
    () async {
      final fixture = HfsFixture();
      fixture.data.setUint32(fixture.dataOffsets[17]! + 88 + 12, 2);
      final archive = await open(fixture);
      addTearDown(archive.close);
      await expectLater(
        archive.readMember(archive.members[1]),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(
        await archive.readMember(archive.members[2]),
        HfsFixture.nestedBytes,
      );
    },
  );

  test('metadata, entry and depth limits are enforced', () async {
    for (final open in <Future<ViewerArchive> Function()>[
      () => openHfsArchive(
        koni.MemoryByteSource(HfsFixture().bytes),
        maxMemberBytes: 1024,
        maxCatalogBytes: 4096,
      ),
      () => openHfsArchive(
        koni.MemoryByteSource(HfsFixture().bytes),
        maxMemberBytes: 1024,
        maxEntries: 1,
      ),
      () => openHfsArchive(
        koni.MemoryByteSource(HfsFixture().bytes),
        maxMemberBytes: 1024,
        maxDepth: 1,
      ),
    ]) {
      await expectLater(open(), throwsA(isA<ArchiveViewException>()));
    }
  });

  test('truncated input and short source reads fail cleanly', () async {
    for (final bytes in [Uint8List(10), HfsFixture().bytes.sublist(0, 8192)]) {
      await expectLater(
        openHfsArchive(koni.MemoryByteSource(bytes), maxMemberBytes: 1024),
        throwsA(isA<ArchiveViewException>()),
      );
    }
    final source = _TrackingSource(HfsFixture().bytes, shortRead: true);
    await expectLater(
      openHfsArchive(source, maxMemberBytes: 1024),
      throwsA(isA<ArchiveViewException>()),
    );
    expect(source.closes, 1);
  });
}

class _TrackingSource implements koni.ByteSource {
  _TrackingSource(this.bytes, {this.shortRead = false, this.reportedLength});
  final Uint8List bytes;
  final bool shortRead;
  final int? reportedLength;
  final reads = <(int, int)>[];
  bool closed = false;
  int closes = 0;

  @override
  int get length => reportedLength ?? bytes.length;
  @override
  String? get name => 'fixture.hfs';
  @override
  Future<Uint8List> read(int offset, int length) async {
    if (closed) throw StateError('closed');
    reads.add((offset, length));
    return Uint8List.fromList(
      bytes.sublist(
        offset,
        offset + length - (shortRead && length > 0 ? 1 : 0),
      ),
    );
  }

  @override
  Future<void> close() async {
    closed = true;
    closes++;
  }
}
