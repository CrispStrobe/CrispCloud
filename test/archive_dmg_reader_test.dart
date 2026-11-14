import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/services/archive_dmg_reader.dart';
import 'package:crisp_cloud/services/archive_member_index.dart';
import 'package:crisp_cloud/services/archive_streaming_unsupported.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import 'support/archive_iso_fixtures.dart';
import 'support/dmg_fixture.dart';
import 'support/hfs_fixture.dart';
import 'support/lzfse_fixture.dart';

void main() {
  Future<ViewerArchive> open(
    DmgFixture fixture, {
    int cap = kArchiveReadLimit,
  }) =>
      openDmgArchive(koni.MemoryByteSource(fixture.bytes), maxMemberBytes: cap);
  final content = Uint8List.fromList(List.generate(1024, (i) => i % 251));

  for (final method in [
    1,
    0x80000004,
    0x80000005,
    0x80000006,
    0x80000007,
    0x80000008,
  ]) {
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

  DmgFixture independentChunk(String plain, String packed, int method) {
    final fixture = DmgFixture(
      File('test/fixtures/archives/dmg-codecs/$plain').readAsBytesSync(),
      method: method,
    );
    fixture.packedBytes = File('test/fixtures/archives/dmg-codecs/$packed')
        .readAsBytesSync();
    fixture.tableData.setUint64(204 + 32, fixture.packedBytes.length);
    fixture.rebuild();
    return fixture;
  }

  for (final example in [
    ('apple-hdiutil.bin', 'apple-hdiutil.adc', 0x80000004),
    ('liblzma.bin', 'liblzma-1m.xz', 0x80000008),
  ]) {
    test(
      'independent ${example.$2} bytes decode through UDIF and stream CRC',
      () async {
        final fixture = independentChunk(example.$1, example.$2, example.$3);
        final archive = await open(fixture);
        addTearDown(archive.close);
        expect(
          await archive.readMember(archive.members.single),
          fixture.logical,
        );
        final output = BytesBuilder();
        await for (final bytes in archive.openMember(
          archive.members.single,
          chunkSize: 137,
        )) {
          output.add(bytes);
        }
        expect(output.takeBytes(), fixture.logical);
      },
    );
  }

  test('ULMO rejects dictionaries above 16 MiB and closes source', () async {
    final fixture = independentChunk(
      'liblzma.bin',
      'liblzma-32m.xz',
      0x80000008,
    );
    final source = _TrackingSource(fixture.bytes);
    await expectLater(
      openDmgArchive(source, maxMemberBytes: kArchiveReadLimit),
      throwsA(isA<ArchiveViewException>()),
    );
    expect(source.closes, 1);
  });

  for (final sample in [lzfseV1Fixture, lzfseV2Fixture, lzfseLzvnFixture]) {
    test(
      'Apple ${sample.name} decodes through ULFO and streamed partition CRC',
      () async {
        final plain = sample.plain;
        final fixture = DmgFixture(
          plain,
          method: 0x80000007,
          chunkBytes: plain.length,
        )..packedBytes = sample.packed;
        fixture.tableData.setUint64(204 + 32, fixture.packedBytes.length);
        fixture.rebuild();
        final archive = await open(fixture);
        addTearDown(archive.close);
        expect(await archive.readMember(archive.members.single), plain);
        final streamed = BytesBuilder();
        await for (final bytes in archive.openMember(
          archive.members.single,
          chunkSize: 137,
        )) {
          streamed.add(bytes);
        }
        expect(streamed.takeBytes(), plain);
        expect(
          archive.notices.join(' '),
          contains('ADC and LZFSE have no embedded checksum'),
        );
      },
    );
  }

  test(
    'corrupt LZFSE during filesystem probing closes the image source',
    () async {
      final fixture = DmgFixture(HfsFixture().bytes, method: 0x80000007);
      fixture.packedBytes[0] = 0;
      fixture.rebuild();
      final source = _TrackingSource(fixture.bytes);
      await expectLater(
        openDmgArchive(source, maxMemberBytes: kArchiveReadLimit),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(source.closes, 1);
    },
  );

  test(
    'raw, Apple LZFSE and zlib chunks share one partition and CRC',
    () async {
      final plain = lzfseV2Fixture.plain;
      final logical = Uint8List.fromList([...plain, ...plain, ...plain]);
      final fixture = DmgFixture(logical, chunkBytes: plain.length);
      final pieces = <Uint8List>[
        plain,
        lzfseV2Fixture.packed,
        DmgFixture(
          plain,
          method: 0x80000005,
          chunkBytes: plain.length,
        ).packedBytes,
      ];
      final packed = BytesBuilder(copy: false);
      const methods = [1, 0x80000007, 0x80000005];
      for (var i = 0; i < pieces.length; i++) {
        final record = 204 + i * 40;
        fixture.tableData.setUint32(record, methods[i]);
        fixture.tableData.setUint64(record + 24, packed.length);
        fixture.tableData.setUint64(record + 32, pieces[i].length);
        packed.add(pieces[i]);
      }
      fixture.packedBytes = packed.takeBytes();
      fixture.rebuild();
      final archive = await open(fixture);
      addTearDown(archive.close);
      expect(await archive.readMember(archive.members.single), logical);
      final streamed = BytesBuilder();
      await for (final bytes in archive.openMember(
        archive.members.single,
        chunkSize: 8191,
      )) {
        streamed.add(bytes);
      }
      expect(streamed.takeBytes(), logical);
    },
  );

  test('cancelling LZFSE extraction stops before the next chunk', () async {
    final logical = Uint8List.fromList(List.generate(16384, (i) => i % 251));
    final fixture = DmgFixture(logical, method: 0x80000007);
    final secondOffset = fixture.tableData.getUint64(244 + 24);
    final source = _TrackingSource(fixture.bytes);
    final archive = await openDmgArchive(
      source,
      maxMemberBytes: kArchiveReadLimit,
    );
    addTearDown(archive.close);
    final prefix = await archive
        .openMember(archive.members.single, chunkSize: 137)
        .take(1)
        .toList();
    expect(prefix.single, logical.sublist(0, 137));
    expect(source.reads.where((read) => read.$1 == secondOffset), isEmpty);
    expect(source.closes, 0);
    // Cancelling one extraction leaves the same archive available to the pane.
    expect(await archive.readMember(archive.members.single), logical);
    await archive.close();
    expect(source.closes, 1);
  });

  for (final method in [0x80000004, 0x80000007, 0x80000008]) {
    for (final name in ['image.dmg', 'misleading.xz', 'download']) {
      test('new method $method keeps UDIF routing for $name', () async {
        final archive = await openViewerArchive(
          DmgFixture(HfsFixture().bytes, method: method).bytes,
          name: name,
        );
        addTearDown(archive.close);
        expect(archive.formatName, 'dmg');
        final member = archive.members.singleWhere(
          (m) => m.name.endsWith('/hello.txt'),
        );
        expect(await archive.readMember(member), HfsFixture.helloBytes);
      });
    }

    test('new method $method can browse ISO files inside a DMG', () async {
      final archive = await open(
        DmgFixture(IsoFixture().bytes, method: method),
      );
      addTearDown(archive.close);
      final member = archive.members.singleWhere(
        (m) => m.name.endsWith('/HELLO.TXT'),
      );
      expect(await archive.readMember(member), 'hello iso'.codeUnits);
    });

    test('new method $method stays outside the canonical DMG writer', () async {
      await expectLater(
        openStreamedDmgSource(
          koni.MemoryByteSource(
            DmgFixture(HfsFixture().bytes, method: method).bytes,
          ),
        ),
        throwsA(isA<ArchiveStreamingUnsupported>()),
      );
    });

    for (final mutation in ['truncate', 'append', 'oversized output']) {
      test('new method $method rejects $mutation', () async {
        final fixture = DmgFixture(content, method: method);
        fixture.packedBytes = switch (mutation) {
          'truncate' => fixture.packedBytes.sublist(
            0,
            fixture.packedBytes.length - 1,
          ),
          'append' => Uint8List.fromList([...fixture.packedBytes, 0x80, 42]),
          _ => fixture.packedBytes,
        };
        fixture.tableData.setUint64(204 + 32, fixture.packedBytes.length);
        if (mutation == 'oversized output') {
          fixture.tableData.setUint64(204 + 16, 1);
          fixture.tableData.setUint64(16, 1);
        }
        fixture.rebuild();
        final archive = await open(fixture);
        addTearDown(archive.close);
        await expectLater(
          archive.readMember(archive.members.single),
          throwsA(isA<ArchiveViewException>()),
        );
      });
    }

    test(
      'new method $method verifies present partition CRC on streamed extraction',
      () async {
        final fixture = DmgFixture(content, method: method);
        fixture.tableData.setUint32(72, 1);
        fixture.rebuild();
        final archive = await open(fixture);
        addTearDown(archive.close);
        await expectLater(
          archive
              .openMember(archive.members.single, chunkSize: 139)
              .drain<void>(),
          throwsA(isA<ArchiveViewException>()),
        );
      },
    );
  }

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
    'unsupported compression method': (d) => d.setUint32(204, 0x80000009),
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
  final reads = <(int, int)>[];
  @override
  String? get name => inner.name;
  @override
  int get length => inner.length;
  @override
  Future<Uint8List> read(int offset, int length) {
    reads.add((offset, length));
    return inner.read(offset, length);
  }

  @override
  Future<void> close() async {
    closed = true;
    closes++;
    await inner.close();
  }
}
