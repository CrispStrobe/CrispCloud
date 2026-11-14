import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/services/archive_types.dart';
import 'package:crisp_cloud/services/archive_udf_reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import 'support/archive_udf_fixture.dart';

Future<ViewerArchive> _open(UdfFixture fixture, {int maxMemberBytes = 65536}) =>
    openUdfArchive(fixture.source(), maxMemberBytes: maxMemberBytes);

Future<void> _reject(UdfFixture fixture, [String? reason]) async {
  final source = fixture.source();
  await expectLater(
    openUdfArchive(source, maxMemberBytes: 65536),
    throwsA(
      isA<ArchiveViewException>().having(
        (error) => error.message,
        'message',
        reason == null ? isNotEmpty : contains(reason),
      ),
    ),
  );
  expect(source.closed, isTrue);
  expect(source.closeCount, 1);
}

void _allocations(
  UdfFixture fixture,
  List<(int, int, int)> allocations, {
  int? size,
  bool long = false,
}) {
  final bytes = fixture.fileEntry;
  final at = fixture.fileAllocationAt;
  bytes.fillRange(at, bytes.length, 0);
  udfPut16(bytes, 34, long ? 1 : 0);
  udfPut32(bytes, at - 4, allocations.length * (long ? 16 : 8));
  if (size != null) {
    udfPut64(bytes, 56, size);
    if (fixture.extended) udfPut64(bytes, 64, size);
  }
  for (var i = 0; i < allocations.length; i++) {
    final (kind, length, block) = allocations[i];
    if (long) {
      udfLong(bytes, at + i * 16, length, block, kind: kind);
    } else {
      udfShort(bytes, at + i * 8, length, block, kind: kind);
    }
  }
  udfRetag(bytes, length: at + allocations.length * (long ? 16 : 8));
}

void _rootContents(UdfFixture fixture, List<Uint8List> identifiers) {
  final data = Uint8List.fromList(
    identifiers.expand((bytes) => bytes).toList(),
  );
  fixture.makeFile(1, type: 4, size: data.length, data: data, dataBlock: 10);
}

void main() {
  group('bounded UDF reader', () {
    for (final revision in [0x102, 0x150, 0x200, 0x201]) {
      for (final allocation in ['short', 'long', 'embedded']) {
        test(
          'revision ${revision.toRadixString(16)} $allocation reads exact Unicode member',
          () async {
            final fixture = UdfFixture(
              revision: revision,
              allocation: allocation,
              extended: revision >= 0x200,
              fileName: 'café-雪.txt',
            );
            final archive = await _open(fixture);
            addTearDown(archive.close);
            expect(archive.formatName, 'udf');
            final member = archive.members.single;
            expect(member.name, 'café-雪.txt');
            expect(member.modified, DateTime.utc(2026, 11, 14, 8, 30, 12));
            expect(await archive.readMember(member), fixture.payload);
            final streamed = await archive
                .openMember(member, chunkSize: 3)
                .expand((chunk) => chunk)
                .toList();
            expect(streamed, fixture.payload);
          },
        );
      }
    }

    test('ordinary FE remains supported in a UDF 2.01 volume', () async {
      final archive = await _open(UdfFixture(revision: 0x201));
      addTearDown(archive.close);
      expect(
        utf8.decode(await archive.readMember(archive.members.single)),
        'hello UDF\n',
      );
    });

    test('embedded directory uses the owning ICB tag location', () async {
      final archive = await _open(UdfFixture(embeddedDirectory: true));
      addTearDown(archive.close);
      expect(archive.members.single.name, 'hello.txt');
    });

    for (final allocation in ['short', 'long', 'embedded']) {
      test(
        'zero-length $allocation file reads and streams empty contents',
        () async {
          final archive = await _open(
            UdfFixture(allocation: allocation, fileData: []),
          );
          addTearDown(archive.close);
          expect(await archive.readMember(archive.members.single), isEmpty);
          expect(
            await archive.openMember(archive.members.single).toList(),
            isEmpty,
          );
        },
      );
    }

    test(
      'nonascending repeated allocations preserve logical descriptor order',
      () async {
        final fixture = UdfFixture(
          fileData: List.generate(4099, (i) => i & 255),
        );
        fixture.partitionSector(22).fillRange(0, 2048, 0x41);
        fixture.partitionSector(20).fillRange(0, 2048, 0x42);
        _allocations(fixture, [(0, 2048, 22), (0, 2048, 20), (0, 3, 22)]);
        final archive = await _open(fixture);
        addTearDown(archive.close);
        expect(await archive.readMember(archive.members.single), [
          ...List.filled(2048, 0x41),
          ...List.filled(2048, 0x42),
          0x41,
          0x41,
          0x41,
        ]);
      },
    );

    test('final allocated block padding is excluded from contents', () async {
      final fixture = UdfFixture();
      _allocations(fixture, [(0, 2048, 20)]);
      final archive = await _open(fixture);
      addTearDown(archive.close);
      expect(await archive.readMember(archive.members.single), fixture.payload);
    });

    for (final shortCrc in [false, true]) {
      test(
        'allocation continuation chain supports ${shortCrc ? 'fixed' : 'complete'} CRC coverage',
        () async {
          final fixture = UdfFixture(
            fileData: List.generate(2051, (i) => (i * 31) & 255),
          );
          _allocations(fixture, [(3, 2048, 30)]);
          final first = fixture.partitionSector(30);
          udfPut32(first, 20, 16);
          udfShort(first, 24, 2048, 20);
          udfShort(first, 32, 2048, 31, kind: 3);
          udfTag(first, 258, 30, 40, crcLength: shortCrc ? 8 : null);
          final second = fixture.partitionSector(31);
          udfPut32(second, 20, 8);
          udfShort(second, 24, 3, 21);
          udfTag(second, 258, 31, 32, crcLength: shortCrc ? 8 : null);
          final archive = await _open(fixture);
          addTearDown(archive.close);
          expect(
            await archive.readMember(archive.members.single),
            fixture.payload,
          );
        },
      );
    }

    test(
      'long allocation continuation keeps partition-reference semantics',
      () async {
        final fixture = UdfFixture(allocation: 'long');
        _allocations(fixture, [(3, 2048, 30)], long: true);
        final continuation = fixture.partitionSector(30);
        udfPut32(continuation, 20, 16);
        udfLong(continuation, 24, fixture.payload.length, 20);
        udfTag(continuation, 258, 30, 40);
        final archive = await _open(fixture);
        addTearDown(archive.close);
        expect(
          await archive.readMember(archive.members.single),
          fixture.payload,
        );
      },
    );

    test('allocated and unallocated sparse extents return zero without reading stale sectors', () async {
      final fixture = UdfFixture(fileData: List.filled(4099, 0xcc));
      _allocations(fixture, [(1, 2048, 20), (2, 2048, 0), (0, 3, 22)]);
      final source = fixture.source();
      final archive = await openUdfArchive(source, maxMemberBytes: 65536);
      addTearDown(archive.close);
      source.reads.clear();
      expect(await archive.readMember(archive.members.single), [
        ...List.filled(4096, 0),
        0xcc,
        0xcc,
        0xcc,
      ]);
      expect(source.reads, [((fixture.partitionStart + 22) * 2048, 3)]);
    });

    test(
      'sparse 8 GiB logical file lists and streams a bounded prefix',
      () async {
        final fixture = UdfFixture();
        const logical = 8 * 1024 * 1024 * 1024;
        _allocations(fixture, [
          for (var i = 0; i < 8; i++) (2, 1073739776, 0),
          (2, 16384, 0),
        ], size: logical);
        final source = fixture.source();
        final archive = await openUdfArchive(source, maxMemberBytes: logical);
        addTearDown(archive.close);
        final member = archive.members.single;
        expect(member.size, logical);
        source.reads.clear();
        expect(
          await archive
              .openMember(member, maxBytes: logical, chunkSize: 17)
              .first,
          List.filled(17, 0),
        );
        expect(source.reads, isEmpty);
        await expectLater(
          archive.readMember(member, maxBytes: logical),
          throwsA(
            isA<ArchiveViewException>().having(
              (error) => error.message,
              'message',
              contains('67108864'),
            ),
          ),
        );
      },
    );

    test(
      'physical offsets above 4 TiB stay exact without full allocation',
      () async {
        final fixture = UdfFixture(partitionStart: 3000000000);
        final source = fixture.source();
        final archive = await openUdfArchive(source, maxMemberBytes: 65536);
        addTearDown(archive.close);
        expect(
          await archive.readMember(archive.members.single),
          fixture.payload,
        );
        expect(
          source.reads.any((read) => read.$1 == (3000000020) * 2048),
          isTrue,
        );
        expect(source.reads.every((read) => read.$2 <= 65536), isTrue);
      },
    );

    test(
      'source closes on success and member identity remains enforced',
      () async {
        final source = UdfFixture().source();
        final archive = await openUdfArchive(source, maxMemberBytes: 65536);
        expect(source.closed, isFalse);
        final other = await _open(UdfFixture());
        addTearDown(other.close);
        await expectLater(
          archive.readMember(other.members.single),
          throwsA(isA<ArchiveViewException>()),
        );
        await archive.close();
        expect(source.closed, isTrue);
        await expectLater(
          archive.readMember(archive.members.single),
          throwsA(isA<ArchiveViewException>()),
        );
      },
    );

    test('stream cancellation avoids reading the next data extent', () async {
      final fixture = UdfFixture(fileData: List.filled(4096, 7));
      _allocations(fixture, [(0, 2048, 20), (0, 2048, 21)]);
      final source = fixture.source();
      final archive = await openUdfArchive(source, maxMemberBytes: 65536);
      addTearDown(archive.close);
      source.reads.clear();
      expect(
        (await archive.openMember(archive.members.single, chunkSize: 16).first)
            .length,
        16,
      );
      expect(source.reads, [((fixture.partitionStart + 20) * 2048, 16)]);
      expect(source.closed, isFalse);
      expect((await archive.readMember(archive.members.single)).length, 4096);
    });

    test(
      'recognized special entries never become readable regular files',
      () async {
        final fixture = UdfFixture();
        fixture.fileEntry[27] = 12;
        udfRetag(fixture.fileEntry);
        final archive = await _open(fixture);
        addTearDown(archive.close);
        expect(archive.members.single.isSpecial, isTrue);
        await expectLater(
          archive.readMember(archive.members.single),
          throwsA(isA<ArchiveViewException>()),
        );
      },
    );

    test('an open integrity state is disclosed without mutation', () async {
      final fixture = UdfFixture();
      udfPut32(fixture.sector(264), 28, 0);
      udfRetag(fixture.sector(264));
      final before = fixture.materialize();
      final archive = await _open(fixture);
      addTearDown(archive.close);
      expect(
        archive.notices.any((notice) => notice.contains('marked open')),
        isTrue,
      );
      expect(fixture.materialize(), before);
    });

    test('invalid calendar date is omitted rather than normalized', () async {
      final fixture = UdfFixture();
      fixture.fileEntry[88] = 2;
      fixture.fileEntry[89] = 31;
      udfRetag(fixture.fileEntry);
      final archive = await _open(fixture);
      addTearDown(archive.close);
      expect(archive.members.single.modified, isNull);
    });

    test(
      'probe is non-owning and stops after unrelated first descriptor',
      () async {
        final fixture = UdfFixture();
        final source = fixture.source();
        expect(await hasUdfVolumeRecognition(source), isTrue);
        expect(source.closed, isFalse);
        fixture.sector(16).fillRange(0, 2048, 0);
        source.reads.clear();
        expect(await hasUdfVolumeRecognition(source), isFalse);
        expect(source.reads, [(32768, 7)]);
        expect(source.closed, isFalse);
      },
    );

    test(
      'buffer slices are accepted without changing original input',
      () async {
        final fixture = UdfFixture();
        final original = fixture.materialize();
        final outer = Uint8List(original.length + 17)
          ..setRange(9, 9 + original.length, original);
        final archive = await openUdfArchive(
          koni.MemoryByteSource(
            Uint8List.sublistView(outer, 9, 9 + original.length),
          ),
          maxMemberBytes: 65536,
        );
        addTearDown(archive.close);
        expect(
          await archive.readMember(archive.members.single),
          fixture.payload,
        );
        expect(outer.sublist(9, 9 + original.length), original);
      },
    );

    test('rejects a continuation loop', () async {
      final fixture = UdfFixture();
      _allocations(fixture, [(3, 2048, 30)]);
      final continuation = fixture.partitionSector(30);
      udfPut32(continuation, 20, 8);
      udfShort(continuation, 24, 2048, 30, kind: 3);
      udfTag(continuation, 258, 30, 32);
      await _reject(fixture, 'continuation loop');
    });

    test('rejects allocations outside their partition', () async {
      final fixture = UdfFixture();
      _allocations(fixture, [(0, fixture.payload.length, 100)]);
      await _reject(fixture, 'leaves its physical partition');
    });

    test(
      'rejects short allocations that do not cover information length',
      () async {
        final fixture = UdfFixture();
        _allocations(fixture, [(0, fixture.payload.length - 1, 20)]);
        await _reject(fixture, 'information length');
      },
    );

    test('rejects nonfinal allocations lacking block alignment', () async {
      final fixture = UdfFixture();
      _allocations(fixture, [(0, 1, 20), (0, fixture.payload.length - 1, 21)]);
      await _reject(fixture, 'not block aligned');
    });

    test(
      'rejects unallocated extents that still name a physical block',
      () async {
        final fixture = UdfFixture();
        _allocations(fixture, [(2, fixture.payload.length, 20)]);
        await _reject(fixture, 'physical address');
      },
    );

    test(
      'rejects 64-bit information length before precision loss or allocation',
      () async {
        final fixture = UdfFixture();
        udfPut32(fixture.fileEntry, 60, 0x200000);
        udfRetag(fixture.fileEntry);
        await _reject(fixture, '8 GiB');
      },
    );

    test('rejects EFE in a pre-2.00 domain', () async {
      final fixture = UdfFixture(extended: true);
      await _reject(fixture, 'before UDF 2.00');
    });

    test('rejects transformed file data', () async {
      final fixture = UdfFixture();
      udfPut16(fixture.fileEntry, 34, 0x800);
      udfRetag(fixture.fileEntry);
      await _reject(fixture, 'Transformed');
    });

    test('rejects named streams on an extended file entry', () async {
      final fixture = UdfFixture(revision: 0x201, extended: true);
      udfLong(fixture.fileEntry, 152, 2048, 40);
      udfRetag(fixture.fileEntry);
      await _reject(fixture, 'Named streams');
    });

    for (final name in ['..', '.', '../escape', 'a/b', r'a\b']) {
      test(
        'rejects unsafe component $name',
        () async => _reject(UdfFixture(fileName: name), 'filename component'),
      );
    }

    test('rejects duplicate resulting paths', () async {
      final fixture = UdfFixture();
      _rootContents(fixture, [
        udfFid(directoryBlock: 10, childBlock: 1),
        udfFid(directoryBlock: 10, childBlock: 2, name: 'hello.txt'),
        udfFid(directoryBlock: 10, childBlock: 2, name: 'hello.txt'),
      ]);
      await _reject(fixture, 'Duplicate');
    });

    test(
      'rejects a directory cycle rather than traversing indefinitely',
      () async {
        final fixture = UdfFixture();
        _rootContents(fixture, [
          udfFid(directoryBlock: 10, childBlock: 1),
          udfFid(
            directoryBlock: 10,
            childBlock: 1,
            name: 'loop',
            isDirectory: true,
          ),
        ]);
        await _reject(fixture, 'cycle limit');
      },
    );

    test(
      'caller entry allowance bounds listing before extra ICB reads',
      () async {
        final fixture = UdfFixture();
        _rootContents(fixture, [
          udfFid(directoryBlock: 10, childBlock: 1),
          udfFid(directoryBlock: 10, childBlock: 2, name: 'a'),
          udfFid(directoryBlock: 10, childBlock: 2, name: 'b'),
        ]);
        final source = fixture.source();
        await expectLater(
          openUdfArchive(source, maxMemberBytes: 65536, maxEntries: 1),
          throwsA(isA<ArchiveViewException>()),
        );
        expect(source.closed, isTrue);
      },
    );

    test(
      'caller metadata allowance stops before over-budget source reads',
      () async {
        final source = UdfFixture().source();
        await expectLater(
          openUdfArchive(source, maxMemberBytes: 65536, maxMetadataBytes: 32),
          throwsA(isA<ArchiveViewException>()),
        );
        expect(
          source.reads.fold<int>(0, (sum, read) => sum + read.$2),
          lessThanOrEqualTo(32),
        );
        expect(source.closed, isTrue);
      },
    );

    test(
      'caller directory and allocation allowances reject explicitly',
      () async {
        final fixture = UdfFixture();
        await expectLater(
          openUdfArchive(
            fixture.source(),
            maxMemberBytes: 65536,
            maxDirectoryBytes: 8,
          ),
          throwsA(isA<ArchiveViewException>()),
        );
        await expectLater(
          openUdfArchive(
            fixture.source(),
            maxMemberBytes: 65536,
            maxExtents: 1,
          ),
          throwsA(isA<ArchiveViewException>()),
        );
      },
    );

    test('invalid caller limits still release owned source', () async {
      final source = UdfFixture().source();
      await expectLater(
        openUdfArchive(source, maxMemberBytes: 0),
        throwsArgumentError,
      );
      expect(source.closed, isTrue);
    });

    test('lists nested and empty directories with exact child paths', () async {
      final fixture = UdfFixture();
      final childData = Uint8List.fromList([
        ...udfFid(directoryBlock: 11, childBlock: 1),
        ...udfFid(directoryBlock: 11, childBlock: 4, name: 'nested.txt'),
      ]);
      fixture.makeFile(
        3,
        type: 4,
        size: childData.length,
        data: childData,
        dataBlock: 11,
      );
      fixture.makeFile(
        4,
        type: 5,
        size: 6,
        data: Uint8List.fromList(utf8.encode('nested')),
        dataBlock: 21,
      );
      final emptyData = udfFid(directoryBlock: 12, childBlock: 1);
      fixture.makeFile(
        5,
        type: 4,
        size: emptyData.length,
        data: emptyData,
        dataBlock: 12,
      );
      _rootContents(fixture, [
        udfFid(directoryBlock: 10, childBlock: 1),
        udfFid(
          directoryBlock: 10,
          childBlock: 3,
          name: 'docs',
          isDirectory: true,
        ),
        udfFid(
          directoryBlock: 10,
          childBlock: 5,
          name: 'empty',
          isDirectory: true,
        ),
      ]);
      final archive = await _open(fixture);
      addTearDown(archive.close);
      expect(archive.members.map((member) => member.name), [
        'docs',
        'empty',
        'docs/nested.txt',
      ]);
      expect(
        archive.members
            .take(2)
            .every((member) => !member.isFile && member.size == 0),
        isTrue,
      );
      expect(
        utf8.decode(await archive.readMember(archive.members.last)),
        'nested',
      );
    });

    test('caller depth limit bounds nested directories', () async {
      final fixture = UdfFixture();
      final childData = Uint8List.fromList([
        ...udfFid(directoryBlock: 11, childBlock: 1),
        ...udfFid(
          directoryBlock: 11,
          childBlock: 5,
          name: 'deeper',
          isDirectory: true,
        ),
      ]);
      fixture.makeFile(
        3,
        type: 4,
        size: childData.length,
        data: childData,
        dataBlock: 11,
      );
      final deepest = udfFid(directoryBlock: 12, childBlock: 3);
      fixture.makeFile(
        5,
        type: 4,
        size: deepest.length,
        data: deepest,
        dataBlock: 12,
      );
      _rootContents(fixture, [
        udfFid(directoryBlock: 10, childBlock: 1),
        udfFid(
          directoryBlock: 10,
          childBlock: 3,
          name: 'docs',
          isDirectory: true,
        ),
      ]);
      final source = fixture.source();
      await expectLater(
        openUdfArchive(source, maxMemberBytes: 65536, maxDepth: 1),
        throwsA(
          isA<ArchiveViewException>().having(
            (error) => error.message,
            'message',
            contains('depth'),
          ),
        ),
      );
      expect(source.closed, isTrue);
    });

    test('rejects prohibited Unicode byte-order marks', () async {
      await _reject(
        UdfFixture(fileName: '\ufeffname.txt'),
        'filename component',
      );
    });

    test('rejects reserved long allocation flags', () async {
      final fixture = UdfFixture(allocation: 'long');
      udfPut16(fixture.fileEntry, fixture.fileAllocationAt + 10, 2);
      udfRetag(fixture.fileEntry);
      await _reject(fixture, 'reserved or erased flags');
    });

    test('accepts erased flag only for allocated unrecorded extent', () async {
      final fixture = UdfFixture(allocation: 'long');
      _allocations(fixture, [(1, fixture.payload.length, 20)], long: true);
      udfPut16(fixture.fileEntry, fixture.fileAllocationAt + 10, 1);
      udfRetag(fixture.fileEntry);
      final archive = await _open(fixture);
      addTearDown(archive.close);
      expect(
        await archive.readMember(archive.members.single),
        List.filled(fixture.payload.length, 0),
      );
      _allocations(fixture, [(0, fixture.payload.length, 20)], long: true);
      udfPut16(fixture.fileEntry, fixture.fileAllocationAt + 10, 1);
      udfRetag(fixture.fileEntry);
      await _reject(fixture, 'reserved or erased flags');
    });

    test('rejects malformed strategy-4 parameters', () async {
      final fixture = UdfFixture();
      fixture.fileEntry[26] = 1;
      udfRetag(fixture.fileEntry);
      await _reject(fixture, 'strategy-4');
    });

    test('rejects partial FID implementation identifier', () async {
      final fixture = UdfFixture(fileName: 'long-enough-name.txt');
      final parentLength = udfGet16(fixture.rootDirectory, 10) + 16;
      final length = udfGet16(fixture.rootDirectory, parentLength + 10) + 16;
      final fid = Uint8List.sublistView(
        fixture.rootDirectory,
        parentLength,
        parentLength + length,
      );
      udfPut16(fid, 36, 4);
      fid[19] -= 4;
      udfRetag(fid);
      await _reject(fixture, 'identifier dimensions');
    });

    test(
      'long allocations can cross two independently mapped physical partitions',
      () async {
        final fixture = UdfFixture(
          allocation: 'long',
          imageBlocks: 500,
          fileData: List.generate(2051, (i) => i & 255),
        );
        final secondPartition = fixture.sector(260);
        secondPartition.setAll(0, fixture.sector(258));
        udfPut32(secondPartition, 16, 4);
        udfPut16(secondPartition, 22, 1);
        udfPut32(secondPartition, 188, 400);
        udfTag(secondPartition, 5, 260, 512);
        udfTag(fixture.sector(261), 8, 261, 512);
        udfPut32(fixture.sector(256), 16, 5 * udfBlockBytes);
        udfRetag(fixture.sector(256));
        final logical = fixture.sector(259);
        udfPut32(logical, 264, 12);
        udfPut32(logical, 268, 2);
        logical[446] = 1;
        logical[447] = 6;
        udfPut16(logical, 448, 1);
        udfPut16(logical, 450, 1);
        udfRetag(logical, length: 452);
        final integrity = fixture.sector(264);
        integrity.fillRange(80, 142, 0);
        udfPut32(integrity, 72, 2);
        udfPut32(integrity, 88, 100);
        udfPut32(integrity, 92, 100);
        udfPut16(integrity, 136, 0x102);
        udfPut16(integrity, 138, 0x102);
        udfPut16(integrity, 140, 0x102);
        udfRetag(integrity, length: 142);
        _allocations(fixture, [(0, 2048, 20), (0, 3, 0)], long: true);
        udfPut16(fixture.fileEntry, fixture.fileAllocationAt + 16 + 8, 1);
        udfRetag(fixture.fileEntry);
        fixture.sector(400).setRange(0, 3, fixture.payload.sublist(2048));
        final source = fixture.source();
        final archive = await openUdfArchive(source, maxMemberBytes: 65536);
        addTearDown(archive.close);
        expect(
          await archive.readMember(archive.members.single),
          fixture.payload,
        );
        expect(source.reads.contains((400 * 2048, 3)), isTrue);
      },
    );
  });
}
