// Copyright 2026 CrispCloud contributors
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:typed_data';

import 'package:crisp_cloud/services/archive_ext_reader.dart';
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/archive_ext_fixture.dart';
import 'support/archive_ext_reference_data.dart';

Matcher _error(ArchiveMessageCode code, [String? detail]) =>
    isA<ArchiveViewException>()
        .having((e) => e.code, 'code', code)
        .having(
          (e) => e.message,
          'detail',
          detail == null ? isNotEmpty : contains(detail),
        );

Future<void> _reject(
  ExtFixture fixture, {
  ArchiveMessageCode code = ArchiveMessageCode.corrupt,
  String? detail,
  Future<ViewerArchive> Function(ExtFixtureSource)? open,
}) async {
  final source = fixture.source();
  await expectLater(
    open?.call(source) ?? openExtArchive(source, maxMemberBytes: 1048576),
    throwsA(_error(code, detail)),
  );
  expect(source.closeCount, 1);
}

void _extent(
  ExtFixture f, {
  int size = 10,
  int physical = 8,
  int logical = 0,
  int length = 1,
  bool unwritten = false,
}) {
  final at = f.inodeOffset(12);
  extPut32(f.bytes, 1120, 0x42);
  extPut32(f.bytes, at + 4, size);
  extPut32(f.bytes, at + 32, 0x80000);
  f.bytes.fillRange(at + 40, at + 100, 0);
  extPut16(f.bytes, at + 40, 0xf30a);
  extPut16(f.bytes, at + 42, 1);
  extPut16(f.bytes, at + 44, 4);
  extPut32(f.bytes, at + 52, logical);
  extPut16(f.bytes, at + 56, length + (unwritten ? 32768 : 0));
  extPut32(f.bytes, at + 60, physical);
}

class _MutableLengthSource extends ExtFixtureSource {
  _MutableLengthSource(super.bytes);
  int adjustment = 0;
  @override
  int get length => super.length + adjustment;
}

class _ReusedBufferSource extends ExtFixtureSource {
  _ReusedBufferSource(super.bytes);
  final buffer = Uint8List(65536 + 16);
  @override
  Future<Uint8List> read(int offset, int count) async {
    final result = await super.read(offset, count);
    buffer.fillRange(0, buffer.length, 0x5a);
    buffer.setRange(7, 7 + result.length, result);
    return Uint8List.sublistView(buffer, 7, 7 + result.length);
  }
}

void main() {
  group('bounded ext reader adversarial and boundary controls', () {
    test(
      'synthetic ext2 listing remains lazy, owns source and streams exactly',
      () async {
        final f = ExtFixture(), source = f.source(borrowedReads: true);
        expect(await hasExtVolumeRecognition(source), isTrue);
        expect(source.closeCount, 0);
        final archive = await openExtArchive(source, maxMemberBytes: 1048576);
        final member = archive.members.single;
        expect(member.name, 'hello.txt');
        expect(member.posixMode, 0x81a4);
        expect(member.modified, DateTime.utc(2023, 11, 14, 22, 13, 20));
        expect(source.reads.any((r) => r.$1 == 8192), isFalse);
        expect(await archive.readMember(member), f.payload);
        expect(
          await archive
              .openMember(member, chunkSize: 3)
              .expand((b) => b)
              .toList(),
          f.payload,
        );
        expect(source.reads.every((r) => r.$2 <= 65536), isTrue);
        await archive.close();
        await archive.close();
        expect(source.closeCount, 1);
        await expectLater(
          archive.readMember(member),
          throwsA(_error(ArchiveMessageCode.closed)),
        );
      },
    );

    test(
      'provider-reused offset buffers cannot change parsed metadata',
      () async {
        final f = ExtFixture();
        final source = _ReusedBufferSource(f.bytes);
        final archive = await openExtArchive(source, maxMemberBytes: 1048576);
        addTearDown(archive.close);
        expect(await archive.readMember(archive.members.single), f.payload);
      },
    );

    test('empty files need no allocation', () async {
      final f = ExtFixture(payload: []);
      final archive = await openExtArchive(f.source(), maxMemberBytes: 1024);
      addTearDown(archive.close);
      expect(await archive.readMember(archive.members.single), isEmpty);
      expect(
        await archive.openMember(archive.members.single).toList(),
        isEmpty,
      );
    });

    test('immutable allocations survive later mapping-byte mutation', () async {
      final f = ExtFixture();
      final archive = await openExtArchive(
        f.source(borrowedReads: true),
        maxMemberBytes: 1024,
      );
      addTearDown(archive.close);
      extPut32(f.bytes, f.inodeOffset(12) + 40, 7);
      expect(await archive.readMember(archive.members.single), f.payload);
    });

    for (final (label, mutate) in <(String, void Function(ExtFixture))>[
      ('superblock bounds', (f) => extPut32(f.bytes, 1028, 100000)),
      ('inode geometry', (f) => extPut16(f.bytes, 1112, 192)),
      ('overlapping metadata', (f) => extPut32(f.bytes, 2052, 3)),
      (
        'data aliases inode table',
        (f) => extPut32(f.bytes, f.inodeOffset(12) + 40, 5),
      ),
      (
        'data aliases directory',
        (f) => extPut32(f.bytes, f.inodeOffset(12) + 40, 7),
      ),
      (
        'data leaves image',
        (f) => extPut32(f.bytes, f.inodeOffset(12) + 40, 128),
      ),
      ('referenced free block', (f) => f.allocatedBlock(8, allocated: false)),
      ('referenced free inode', (f) => f.bytes[4097] &= ~8),
      (
        'deleted live inode',
        (f) => extPut32(f.bytes, f.inodeOffset(12) + 20, 123),
      ),
      ('zero record length', (f) => extPut16(f.bytes, 7168 + 24 + 4, 0)),
      (
        'cross-block directory record',
        (f) => extPut16(f.bytes, 7168 + 24 + 4, 1024),
      ),
      ('incorrect parent', (f) => extPut32(f.bytes, 7168 + 12, 12)),
      ('type disagreement', (f) => f.bytes[7168 + 24 + 7] = 2),
      ('short-name invalid UTF8', (f) => f.bytes[7168 + 24 + 8] = 255),
    ]) {
      test('rejects $label before publication', () async {
        final f = ExtFixture();
        mutate(f);
        await _reject(
          f,
          code: label.contains('UTF8')
              ? ArchiveMessageCode.unsupported
              : ArchiveMessageCode.corrupt,
        );
      });
    }

    for (final name in [
      '..',
      '../escape',
      'slash/name',
      r'back\slash',
      'C:drive',
      'line\nbreak',
    ]) {
      test(
        'refuses unsafe component $name',
        () => _reject(ExtFixture(name: name)),
      );
    }

    for (final (offset, flag) in [
      (1116, 0x1000),
      (1120, 4),
      (1120, 0x10),
      (1120, 0x8000),
      (1120, 0x10000),
      (1120, 0x20000),
      (1124, 0x200),
    ]) {
      test('rejects unsupported feature $offset/$flag', () async {
        final f = ExtFixture();
        extPut32(f.bytes, offset, extGet32(f.bytes, offset) | flag);
        await _reject(f, code: ArchiveMessageCode.unsupported);
      });
    }
    test('unclean filesystem cannot be browsed', () async {
      final f = ExtFixture();
      extPut16(f.bytes, 1082, 0);
      await _reject(f, code: ArchiveMessageCode.unsupported);
    });
    test('indexed directory is explicitly unsupported', () async {
      final f = ExtFixture();
      extPut32(f.bytes, f.inodeOffset(2) + 32, 0x1000);
      await _reject(f, code: ArchiveMessageCode.unsupported);
    });
    test('external xattrs cannot be mistaken for data', () async {
      final f = ExtFixture();
      extPut32(f.bytes, f.inodeOffset(12) + 104, 9);
      await _reject(f, code: ArchiveMessageCode.unsupported);
    });

    test('duplicate names are refused', () async {
      final f = ExtFixture();
      f.directory(7, [
        (2, '.', 2),
        (2, '..', 2),
        (12, 'same', 1),
        (12, 'same', 1),
      ]);
      await _reject(f, detail: 'Duplicate');
    });
    test('regular hard links reuse verified allocation', () async {
      final f = ExtFixture();
      extPut16(f.bytes, f.inodeOffset(12) + 26, 2);
      f.directory(7, [
        (2, '.', 2),
        (2, '..', 2),
        (12, 'one', 1),
        (12, 'two', 1),
      ]);
      final archive = await openExtArchive(f.source(), maxMemberBytes: 1024);
      addTearDown(archive.close);
      for (final member in archive.members) {
        expect(await archive.readMember(member), f.payload);
      }
    });
    test('hard link count under-reporting is refused', () async {
      final f = ExtFixture();
      f.directory(7, [
        (2, '.', 2),
        (2, '..', 2),
        (12, 'one', 1),
        (12, 'two', 1),
      ]);
      await _reject(f, detail: 'links');
    });
    test('directory cycle is refused', () async {
      final f = ExtFixture();
      f.allocatedBlock(9);
      f.inode(13, mode: 0x41ed, size: 1024, block: 9, links: 3);
      f.directory(7, [(2, '.', 2), (2, '..', 2), (13, 'nested', 2)]);
      f.directory(9, [(13, '.', 2), (2, '..', 2), (13, 'cycle', 2)]);
      await _reject(f, detail: 'cycle');
    });
    test('long symlink blocks cannot alias a regular file', () async {
      final f = ExtFixture();
      f.inode(13, mode: 0xa1ff, size: 100, block: 8);
      f.directory(7, [
        (2, '.', 2),
        (2, '..', 2),
        (13, 'link', 7),
        (12, 'file', 1),
      ]);
      await _reject(f, detail: 'Cross-linked');
    });
    test('short symlink payload is never read as a block map', () async {
      final f = ExtFixture();
      f.inode(13, mode: 0xa1ff, size: 5);
      f.bytes.setRange(f.inodeOffset(13) + 40, f.inodeOffset(13) + 45, [
        104,
        101,
        108,
        108,
        111,
      ]);
      f.directory(7, [(2, '.', 2), (2, '..', 2), (13, 'link', 7)]);
      final archive = await openExtArchive(f.source(), maxMemberBytes: 1024);
      addTearDown(archive.close);
      expect(archive.members.single.isSpecial, isTrue);
      await expectLater(
        archive.readMember(archive.members.single),
        throwsA(isA<ArchiveViewException>()),
      );
    });

    test(
      'unwritten extents return zeroes without reading backing content',
      () async {
        final f = ExtFixture();
        _extent(f, size: 10, unwritten: true);
        final source = f.source();
        final archive = await openExtArchive(source, maxMemberBytes: 1024);
        addTearDown(archive.close);
        source.reads.clear();
        expect(
          await archive.readMember(archive.members.single),
          List.filled(10, 0),
        );
        expect(source.reads, isEmpty);
      },
    );
    test('sparse gaps precede exact extent payload', () async {
      final f = ExtFixture();
      _extent(f, size: 1034, logical: 1);
      final archive = await openExtArchive(f.source(), maxMemberBytes: 2048);
      addTearDown(archive.close);
      expect(await archive.readMember(archive.members.single), [
        ...List.filled(1024, 0),
        ...f.payload,
      ]);
    });
    test('overlapping extent records are refused', () async {
      final f = ExtFixture();
      _extent(f, size: 2048);
      final at = f.inodeOffset(12) + 40;
      extPut16(f.bytes, at + 2, 2);
      extPut32(f.bytes, at + 24, 0);
      extPut16(f.bytes, at + 28, 1);
      extPut32(f.bytes, at + 32, 9);
      await _reject(f, detail: 'extent-tree');
    });
    test('extent high halves cannot escape exact integer bounds', () async {
      final f = ExtFixture();
      _extent(f);
      extPut16(f.bytes, f.inodeOffset(12) + 58, 65535);
      await _reject(f);
    });
    test('indirect cycles are refused before publication', () async {
      final f = ExtFixture();
      f.allocatedBlock(9);
      extPut32(f.bytes, f.inodeOffset(12) + 40, 0);
      extPut32(f.bytes, f.inodeOffset(12) + 92, 9);
      extPut32(f.bytes, 9 * 1024, 9);
      await _reject(f, detail: 'Cross-linked');
    });

    for (final (label, open)
        in <(String, Future<ViewerArchive> Function(ExtFixtureSource))>[
          (
            'metadata',
            (s) =>
                openExtArchive(s, maxMemberBytes: 1024, maxMetadataBytes: 1024),
          ),
          (
            'directory',
            (s) =>
                openExtArchive(s, maxMemberBytes: 1024, maxDirectoryBytes: 1),
          ),
          (
            'path',
            (s) => openExtArchive(
              s,
              maxMemberBytes: 1024,
              maxRetainedPathBytes: 1,
            ),
          ),
          (
            'blocks',
            (s) => openExtArchive(s, maxMemberBytes: 1024, maxBlocks: 1),
          ),
          (
            'extents',
            (s) => openExtArchive(s, maxMemberBytes: 1024, maxExtents: 1),
          ),
        ]) {
      test(
        'lowered $label limit is enforced',
        () => _reject(
          ExtFixture(),
          code: ArchiveMessageCode.archiveLimit,
          open: open,
        ),
      );
    }
    test('failed opens consume shared traversal budget', () async {
      final budget = ArchiveExtTraversalBudget(maxBlocks: 3);
      final first = await openExtArchive(
        ExtFixture().source(),
        maxMemberBytes: 1024,
        traversalBudget: budget,
      );
      await first.close();
      expect(budget.blocksVisited, 2);
      await _reject(
        ExtFixture(),
        code: ArchiveMessageCode.archiveLimit,
        open: (s) =>
            openExtArchive(s, maxMemberBytes: 1024, traversalBudget: budget),
      );
      expect(budget.blocksVisited, 3);
    });
    test('argument failures close source once', () async {
      final source = ExtFixture().source();
      await expectLater(
        openExtArchive(source, maxMemberBytes: 1024, maxEntries: 100001),
        throwsArgumentError,
      );
      expect(source.closeCount, 1);
    });
    test('larger member limit is enforced during read', () async {
      final f = ExtFixture();
      final archive = await openExtArchive(f.source(), maxMemberBytes: 1);
      addTearDown(archive.close);
      await expectLater(
        archive.readMember(archive.members.single),
        throwsA(_error(ArchiveMessageCode.archiveLimit)),
      );
    });

    test('provider exception identity survives cleanup failure', () async {
      final failure = StateError('provider revoked');
      final source = ExtFixture().source()
        ..readFailure = failure
        ..closeFailure = StateError('close failed');
      await expectLater(
        openExtArchive(source, maxMemberBytes: 1024),
        throwsA(same(failure)),
      );
      expect(source.closeCount, 1);
    });
    test('short signature read is a failure, not a negative probe', () async {
      final source = ExtFixture().source()..shortRead = true;
      await expectLater(
        hasExtVolumeRecognition(source),
        throwsA(_error(ArchiveMessageCode.corrupt)),
      );
      expect(source.closeCount, 0);
    });
    test('source length changes during opening are refused', () async {
      final source = _MutableLengthSource(ExtFixture().bytes);
      source.afterRead = (_, __) {
        source.adjustment = 512;
      };
      await expectLater(
        openExtArchive(source, maxMemberBytes: 1024),
        throwsA(_error(ArchiveMessageCode.corrupt, 'length changed')),
      );
      expect(source.closeCount, 1);
    });
    test('source length changes before extraction are refused', () async {
      final source = _MutableLengthSource(ExtFixture().bytes);
      final archive = await openExtArchive(source, maxMemberBytes: 1024);
      addTearDown(archive.close);
      source.adjustment = 512;
      await expectLater(
        archive.readMember(archive.members.single),
        throwsA(_error(ArchiveMessageCode.corrupt, 'length changed')),
      );
    });
    test(
      'cancellation at opening and during streaming stays distinct',
      () async {
        var cancelled = true;
        final source = ExtFixture().source();
        await expectLater(
          openExtArchive(
            source,
            maxMemberBytes: 1024,
            isCancelled: () => cancelled,
          ),
          throwsA(isA<ArchiveExtCancelledException>()),
        );
        expect(source.closeCount, 1);
        cancelled = false;
        final archive = await openExtArchive(
          ExtFixture().source(),
          maxMemberBytes: 1024,
          isCancelled: () => cancelled,
        );
        addTearDown(archive.close);
        final stream = StreamIterator(
          archive.openMember(archive.members.single, chunkSize: 3),
        );
        expect(await stream.moveNext(), isTrue);
        cancelled = true;
        await expectLater(
          stream.moveNext(),
          throwsA(isA<ArchiveExtCancelledException>()),
        );
      },
    );

    test('resize-inode index cannot be exposed as file contents', () async {
      final bytes = extReferenceBytes('ext2');
      const sb = 1024;
      final block = 1024 * (1 << extGet32(bytes, sb + 24));
      final inodeSize = extGet16(bytes, sb + 88);
      final table =
          extGet32(bytes, (extGet32(bytes, sb + 20) + 1) * block + 8) * block;
      final resizeIndex = extGet32(bytes, table + 6 * inodeSize + 40 + 13 * 4);
      expect(resizeIndex, greaterThan(0));
      // In this independent image /hello.txt is inode 12; locate its directory
      // record instead of assuming the writer's inode allocation order.
      final root = table + inodeSize;
      final rootBlock = extGet32(bytes, root + 40);
      int? fileInode;
      for (var at = rootBlock * block; at < (rootBlock + 1) * block;) {
        final length = extGet16(bytes, at + 4), nameLength = bytes[at + 6];
        final name = String.fromCharCodes(
          bytes.sublist(at + 8, at + 8 + nameLength),
        );
        if (name == 'hello.txt') fileInode = extGet32(bytes, at);
        at += length;
      }
      expect(fileInode, isNotNull);
      extPut32(bytes, table + (fileInode! - 1) * inodeSize + 40, resizeIndex);
      final source = ExtFixtureSource(bytes);
      await expectLater(
        openExtArchive(source, maxMemberBytes: 2 * 1024 * 1024),
        throwsA(_error(ArchiveMessageCode.corrupt, 'Cross-linked')),
      );
      expect(source.closeCount, 1);
    });

    test('future ext timestamps use exact UTC millisecond precision', () async {
      final bytes = extReferenceBytes('ext3');
      final block = 1024 * (1 << extGet32(bytes, 1048));
      final inodeSize = extGet16(bytes, 1112);
      final table =
          extGet32(bytes, (extGet32(bytes, 1044) + 1) * block + 8) * block;
      final root = table + inodeSize;
      final firstData = extGet32(bytes, root + 40) * block;
      var ino = 0;
      for (var at = firstData; at < firstData + block;) {
        final name = String.fromCharCodes(
          bytes.sublist(at + 8, at + 8 + bytes[at + 6]),
        );
        if (name == 'hello.txt') ino = extGet32(bytes, at);
        at += extGet16(bytes, at + 4);
      }
      final at = table + (ino - 1) * inodeSize;
      expect(inodeSize, greaterThanOrEqualTo(256));
      extPut16(bytes, at + 128, 32);
      extPut32(bytes, at + 16, 1700000000);
      extPut32(bytes, at + 136, 987654321 * 4 + 3);
      final archive = await openExtArchive(
        ExtFixtureSource(bytes),
        maxMemberBytes: 2 * 1024 * 1024,
      );
      addTearDown(archive.close);
      expect(
        archive.members
            .firstWhere((m) => m.name == 'hello.txt')
            .modified
            ?.millisecondsSinceEpoch,
        (1700000000 + 3 * 4294967296) * 1000 + 987,
      );
    });
  });
}
