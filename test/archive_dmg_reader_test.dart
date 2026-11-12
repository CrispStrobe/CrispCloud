import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/services/archive_dmg_reader.dart';
import 'package:crisp_cloud/services/archive_member_index.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import 'support/archive_iso_fixtures.dart';
import 'support/dmg_fixture.dart';
import 'support/hfs_fixture.dart';

void main() {
  Future<ViewerArchive> open(
    DmgFixture fixture, {
    int cap = kArchiveReadLimit,
  }) =>
      openDmgArchive(koni.MemoryByteSource(fixture.bytes), maxMemberBytes: cap);
  final content = Uint8List.fromList(List.generate(1024, (i) => i % 251));

  for (final method in [1, 0x80000005, 0x80000006]) {
    test('UDIF method $method extracts exact partition bytes', () async {
      final fixture = DmgFixture(content, method: method);
      final archive = await open(fixture);
      addTearDown(archive.close);
      expect(archive.formatName, 'dmg');
      expect(archive.members.single.name, startsWith('partitions/001-'));
      expect(await archive.readMember(archive.members.single), content);
      expect(archive.notices.join(' '), contains('raw partition images'));
    });

    test(
      'UDIF method $method browses HFS files without materializing volume',
      () async {
        final fixture = DmgFixture(HfsFixture().bytes, method: method);
        final archive = await open(fixture, cap: 1024);
        addTearDown(archive.close);
        final hello = archive.members.singleWhere(
          (m) => m.name.endsWith('/hello.txt'),
        );
        final nested = archive.members.singleWhere(
          (m) => m.name.endsWith('/nested.bin'),
        );
        expect(await archive.readMember(hello), HfsFixture.helloBytes);
        expect(await archive.readMember(nested), HfsFixture.nestedBytes);
        expect(
          ArchiveMemberIndex(archive).list('').map((f) => f.name),
          containsAll(['files', 'partitions']),
        );
        await expectLater(
          archive.readMember(archive.members.first),
          throwsA(isA<ArchiveViewException>()),
        );
      },
    );
  }

  test(
    'native UDIF reads HFS files and verifies all five partition CRCs',
    () async {
      final bytes = File('test/fixtures/archives/native-hfsplus.dmg')
          .readAsBytesSync();
      final archive = await openViewerArchive(bytes, name: 'native.dmg');
      addTearDown(archive.close);
      final files = archive.members
          .where((m) => m.isFile && m.name.startsWith('files/'))
          .toList();
      expect(files, hasLength(42));
      for (final member in files) {
        expect(
          utf8.decode(await archive.readMember(member)),
          'CrispCloud independently created HFS+ fixture\n',
        );
      }
      final partitions = archive.members
          .where((m) => m.name.startsWith('partitions/'))
          .toList();
      expect(partitions, hasLength(5));
      for (final partition in partitions) {
        expect((await archive.readMember(partition)).length, partition.size);
      }
      expect(archive.notices.join(' '), contains('Symbolic links'));
      expect(() => ArchiveMemberIndex(archive), returnsNormally);
    },
  );

  test(
    'a bzip2-first DMG is identified by trailer before stream magic',
    () async {
      final fixture = DmgFixture(HfsFixture().bytes, method: 0x80000006);
      final archive = await openViewerArchive(
        fixture.bytes,
        name: 'download.DMG',
      );
      addTearDown(archive.close);
      expect(archive.formatName, 'dmg');
      expect(archive.members.any((m) => m.name.endsWith('/hello.txt')), isTrue);
    },
  );

  test('ISO inside a DMG is browsed through random-access chunks', () async {
    final fixture = DmgFixture(IsoFixture().bytes, method: 0x80000005);
    final archive = await open(fixture);
    addTearDown(archive.close);
    expect(archive.members.first.name, endsWith('.iso'));
    final file = archive.members.singleWhere(
      (m) => m.name.endsWith('/HELLO.TXT'),
    );
    expect(await archive.readMember(file), 'hello iso'.codeUnits);
  });

  for (final method in [0, 2]) {
    test('zero-fill method $method expands without reading payload', () async {
      final fixture = DmgFixture(Uint8List(1024), method: method);
      final archive = await open(fixture);
      addTearDown(archive.close);
      expect(await archive.readMember(archive.members.single), Uint8List(1024));
    });
  }

  test('special HFS entries are omitted explicitly; regular files remain browsable', () async {
    final hfs = HfsFixture();
    hfs.data.setUint16(hfs.dataOffsets[17]! + 42, 0xa1ff);
    final archive = await open(DmgFixture(hfs.bytes, method: 0x80000005));
    addTearDown(archive.close);
    expect(archive.members.any((m) => m.name.endsWith('/hello.txt')), isFalse);
    expect(archive.members.any((m) => m.name.endsWith('/nested.bin')), isTrue);
    expect(archive.notices.join(' '), contains('Symbolic links'));
    expect(() => ArchiveMemberIndex(archive), returnsNormally);
  });

  test(
    'unsupported HFS state leaves raw partition plus visible explanation',
    () async {
      final hfs = HfsFixture();
      hfs.data.setUint32(1028, 0); // journal recovery would be needed
      final fixture = DmgFixture(hfs.bytes);
      final archive = await open(fixture);
      addTearDown(archive.close);
      expect(archive.members, hasLength(1));
      expect(
        archive.notices.join(' '),
        contains('filesystem browsing unavailable'),
      );
      expect(await archive.readMember(archive.members.single), hfs.bytes);
    },
  );

  test('partition label cannot inject an extraction path', () async {
    final archive = await open(
      DmgFixture(content, label: '../../outside\\evil:part'),
    );
    addTearDown(archive.close);
    final path = archive.members.single.name;
    expect(path.split('/'), hasLength(2));
    expect(path, isNot(contains('..')));
    expect(path, isNot(contains('\\')));
    expect(path, isNot(contains(':')));
    expect(() => ArchiveMemberIndex(archive), returnsNormally);
  });

  test('partition CRC is checked on full extraction', () async {
    final fixture = DmgFixture(content);
    fixture.tableData.setUint32(72, 1);
    fixture.rebuild();
    final archive = await open(fixture);
    addTearDown(archive.close);
    await expectLater(
      archive.readMember(archive.members.single),
      throwsA(isA<ArchiveViewException>()),
    );
  });

  test('truncated compressed chunk is rejected', () async {
    final fixture = DmgFixture(content, method: 0x80000005);
    fixture.packedBytes = fixture.packedBytes.sublist(
      0,
      fixture.packedBytes.length - 4,
    );
    fixture.tableData.setUint64(204 + 32, fixture.packedBytes.length);
    fixture.rebuild();
    final archive = await open(fixture);
    addTearDown(archive.close);
    await expectLater(
      archive.readMember(archive.members.single),
      throwsA(isA<ArchiveViewException>()),
    );
  });

  final malformed = <String, void Function(DmgFixture)>{
    'trailer version': (f) => f.trailer.setUint32(4, 3),
    'trailer length': (f) => f.trailer.setUint32(8, 128),
    'segmented image': (f) => f.trailer.setUint32(60, 2),
    'running fork offset': (f) => f.trailer.setUint64(16, 1),
    'XML points outside': (f) => f.trailer.setUint64(216, f.bytes.length),
    'XML overlaps data': (f) => f.trailer.setUint64(216, 0),
    'empty XML': (f) => f.trailer.setUint64(224, 0),
    'oversized XML': (f) => f.trailer.setUint64(224, 9 * 1024 * 1024),
    'non-exact integer': (f) => f.trailer.setUint32(492, 0xffffffff),
    'oversized disk': (f) => f.trailer.setUint64(492, 0x100000001),
  };
  for (final entry in malformed.entries) {
    test('rejects ${entry.key}', () async {
      final fixture = DmgFixture(content);
      entry.value(fixture);
      await expectLater(open(fixture), throwsA(isA<ArchiveViewException>()));
    });
  }

  final badTables = <String, void Function(ByteData)>{
    'wrong table signature': (d) => d.setUint32(0, 0),
    'wrong table version': (d) => d.setUint32(4, 0),
    'partition past disk': (d) => d.setUint64(8, 2),
    'invalid run count': (d) => d.setUint32(200, 0xffffffff),
    'unsupported LZFSE': (d) => d.setUint32(204, 0x80000007),
    'missing extent': (d) => d.setUint64(204 + 8, 1),
    'size mismatch': (d) => d.setUint64(204 + 32, 1),
    'data outside fork': (d) => d.setUint64(204 + 24, 100000),
    'invalid checksum length': (d) => d.setUint32(68, 64),
    'unsupported checksum': (d) => d.setUint32(64, 100),
    'invalid terminator': (d) => d.setUint64(244 + 16, 1),
    'missing terminator': (d) => d.setUint32(244, 0x7ffffffe),
  };
  for (final entry in badTables.entries) {
    test('rejects ${entry.key}', () async {
      final fixture = DmgFixture(content);
      entry.value(fixture.tableData);
      fixture.rebuild();
      await expectLater(open(fixture), throwsA(isA<ArchiveViewException>()));
    });
  }

  test('truncated source and missing footer close the owned source', () async {
    final source = _TrackingSource(DmgFixture(content).bytes.sublist(0, 100));
    await expectLater(
      openDmgArchive(source, maxMemberBytes: 1024),
      throwsA(isA<ArchiveViewException>()),
    );
    expect(source.closed, isTrue);
  });

  test('successful close closes input and blocks further reads', () async {
    final source = _TrackingSource(DmgFixture(content).bytes);
    final archive = await openDmgArchive(source, maxMemberBytes: 1024);
    await archive.close();
    await archive.close();
    expect(source.closes, 1);
    await expectLater(
      archive.readMember(archive.members.single),
      throwsA(isA<ArchiveViewException>()),
    );
  });
}

class _TrackingSource implements koni.ByteSource {
  _TrackingSource(Uint8List bytes) : inner = koni.MemoryByteSource(bytes);
  final koni.MemoryByteSource inner;
  bool closed = false;
  int closes = 0;
  @override
  String? get name => inner.name;
  @override
  int get length => inner.length;
  @override
  Future<Uint8List> read(int offset, int length) => inner.read(offset, length);
  @override
  Future<void> close() async {
    closed = true;
    closes++;
    await inner.close();
  }
}
