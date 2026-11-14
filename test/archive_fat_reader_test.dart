import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/services/archive_fat_reader.dart';
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/archive_fat_fixture.dart';

Future<ViewerArchive> _open(
  FatFixture fixture, {
  int maxMemberBytes = 1048576,
}) => openFatArchive(fixture.source(), maxMemberBytes: maxMemberBytes);

Matcher _error(ArchiveMessageCode code, [String? detail]) =>
    isA<ArchiveViewException>()
        .having((error) => error.code, 'code', code)
        .having(
          (error) => error.message,
          'message',
          detail == null ? isNotEmpty : contains(detail),
        );

Future<void> _reject(
  FatFixture fixture, {
  ArchiveMessageCode code = ArchiveMessageCode.corrupt,
  String? detail,
  Future<ViewerArchive> Function(FatFixtureSource)? open,
}) async {
  final source = fixture.source();
  await expectLater(
    open?.call(source) ?? openFatArchive(source, maxMemberBytes: 1048576),
    throwsA(_error(code, detail)),
  );
  expect(source.closed, isTrue);
  expect(source.closeCount, 1);
}

List<Uint8List> _namedEntries(
  String name, {
  String alias = 'LONGNA~1.TXT',
  Uint8List? aliasBytes,
  int first = 0,
  int size = 0,
}) {
  final bytes = aliasBytes ?? fatAlias(alias);
  return [
    ...fatLongEntries(name, bytes),
    fatShortEntry(alias, alias: bytes, firstCluster: first, size: size),
  ];
}

void main() {
  group('bounded read-only FAT reader', () {
    for (final bits in [12, 16, 32]) {
      test(
        'FAT$bits lists metadata, reads and streams exact payload',
        () async {
          final fixture = FatFixture(bits: bits);
          final source = fixture.source(offsetView: true);
          expect(await hasFatVolumeRecognition(source), isTrue);
          expect(source.closed, isFalse);
          final archive = await openFatArchive(source, maxMemberBytes: 1048576);
          addTearDown(archive.close);
          expect(archive.formatName, 'fat');
          expect(archive.notices.join(' '), contains('FAT$bits;'));
          final member = archive.members.single;
          expect(member.name, 'HELLO.TXT');
          expect(member.modified, DateTime(2000, 1, 1, 12, 34, 56));
          expect(member.isFile, isTrue);
          expect(member.isSpecial, isFalse);
          expect(member.pathEscapedRoot, isFalse);
          expect(member.posixMode, isNull);
          // The listing inspects allocation metadata, not the member contents.
          expect(
            source.reads.any((read) => read.$1 == fixture.fileOffset),
            isFalse,
          );
          source.reads.clear();
          expect(await archive.readMember(member), fixture.payload);
          expect(source.reads, [(fixture.fileOffset, fixture.payload.length)]);
          expect(
            await archive
                .openMember(member, chunkSize: 3)
                .expand((b) => b)
                .toList(),
            fixture.payload,
          );
          expect(source.reads.every((read) => read.$2 <= 65536), isTrue);
          await archive.close();
          await archive.close();
          expect(source.closeCount, 1);
          await expectLater(
            archive.readMember(member),
            throwsA(_error(ArchiveMessageCode.closed)),
          );
        },
      );

      for (final sectorBytes in [1024, 2048, 4096]) {
        test('FAT$bits admits $sectorBytes-byte logical sectors', () async {
          final fixture = FatFixture(bits: bits, sectorBytes: sectorBytes);
          final archive = await _open(fixture);
          addTearDown(archive.close);
          expect(
            await archive.readMember(archive.members.single),
            fixture.payload,
          );
          expect(
            archive.notices.join(' '),
            contains('$sectorBytes-byte sectors'),
          );
        });
      }

      test('FAT$bits empty regular file has no allocation', () async {
        final fixture = FatFixture(bits: bits, fileData: []);
        final archive = await _open(fixture);
        addTearDown(archive.close);
        expect(await archive.readMember(archive.members.single), isEmpty);
        expect(
          await archive.openMember(archive.members.single).toList(),
          isEmpty,
        );
      });

      test(
        'FAT$bits nested directories preserve parent relationships',
        () async {
          final fixture = FatFixture(bits: bits, includeFile: false);
          fixture.setRoot([
            fatShortEntry('DIR', firstCluster: 10, isDirectory: true),
          ]);
          fixture.setDirectory(10, [
            fatShortEntry('SUB', firstCluster: 11, isDirectory: true),
            fatShortEntry('EMPTY', firstCluster: 12, isDirectory: true),
          ]);
          fixture.setDirectory(11, [
            fatShortEntry('NOTE.TXT', firstCluster: 20, size: 4),
            fatShortEntry('ZERO'),
          ], parent: 10);
          fixture.setDirectory(12, [], parent: 10);
          fixture.writeFile([20], [70, 65, 84, 33]);
          final archive = await _open(fixture);
          addTearDown(archive.close);
          expect(archive.members.map((m) => m.name), [
            'DIR',
            'DIR/SUB',
            'DIR/SUB/NOTE.TXT',
            'DIR/SUB/ZERO',
            'DIR/EMPTY',
          ]);
          expect(archive.members.where((m) => !m.isFile).length, 3);
          final file = archive.members.singleWhere(
            (m) => m.name.endsWith('NOTE.TXT'),
          );
          expect(await archive.readMember(file), [70, 65, 84, 33]);
          await expectLater(
            archive.readMember(archive.members.first),
            throwsA(isA<ArchiveViewException>()),
          );
        },
      );
    }

    for (final geometry in [(12, 4084), (16, 4085), (16, 65524), (32, 65525)]) {
      test(
        'variant derives from ${geometry.$2} clusters, not FAT label',
        () async {
          final fixture = FatFixture(
            bits: geometry.$1,
            clusterCount: geometry.$2,
          );
          fixture.boot.setRange(
            geometry.$1 == 32 ? 82 : 54,
            geometry.$1 == 32 ? 90 : 62,
            ascii.encode('FAT12   '),
          );
          final archive = await _open(fixture);
          addTearDown(archive.close);
          expect(archive.notices.join(' '), contains('FAT${geometry.$1};'));
          expect(
            await archive.readMember(archive.members.single),
            fixture.payload,
          );
        },
      );
    }

    test('one FAT table and 32 KiB clusters need no redundant copy', () async {
      final fixture = FatFixture(fatCount: 1, sectorsPerCluster: 64);
      final archive = await _open(fixture);
      addTearDown(archive.close);
      expect(await archive.readMember(archive.members.single), fixture.payload);
      expect(archive.notices.join(' '), contains('32768-byte clusters'));
    });

    test(
      'fragmented descending chains preserve logical order and omit slack',
      () async {
        final fixture = FatFixture(
          fileData: List.generate(1027, (i) => (i * 19) & 255),
          fileClusters: [100, 3, 25],
        );
        fixture.write(fixture.clusterOffset(25) + 3, List.filled(509, 0xcc));
        final archive = await _open(fixture);
        addTearDown(archive.close);
        expect(
          await archive.readMember(archive.members.single),
          fixture.payload,
        );
        expect(
          await archive
              .openMember(archive.members.single, chunkSize: 509)
              .expand((bytes) => bytes)
              .toList(),
          fixture.payload,
        );
      },
    );

    for (final cluster in [341, 2730]) {
      test(
        'packed FAT12 cluster $cluster crosses a sector/page boundary',
        () async {
          final fixture = FatFixture(
            clusterCount: 3000,
            fileClusters: [cluster],
          );
          final archive = await _open(fixture);
          addTearDown(archive.close);
          expect(
            await archive.readMember(archive.members.single),
            fixture.payload,
          );
        },
      );
    }

    test('sparse FAT32 high physical offsets remain exact', () async {
      final fixture = FatFixture(
        bits: 32,
        sectorBytes: 4096,
        clusterCount: 200000100,
        fileClusters: [200000000],
      );
      final source = fixture.source();
      final archive = await openFatArchive(source, maxMemberBytes: 1048576);
      addTearDown(archive.close);
      expect(fixture.fileOffset, greaterThan(0xffffffff));
      expect(await archive.readMember(archive.members.single), fixture.payload);
      expect(
        source.reads.fold<int>(0, (sum, read) => sum + read.$2),
        lessThan(32768),
      );
    });

    test(
      'streaming above the buffer cap reads only a requested prefix',
      () async {
        const logical = 65 * 1024 * 1024;
        final fixture = FatFixture(bits: 16, sectorsPerCluster: 64);
        fixture.writeFile(
          List.generate(logical ~/ fixture.clusterBytes, (i) => i + 2),
          [],
        );
        fatPut32(fixture.fileEntry, 28, logical);
        final source = fixture.source();
        final archive = await openFatArchive(source, maxMemberBytes: logical);
        addTearDown(archive.close);
        final member = archive.members.single;
        expect(member.size, logical);
        source.reads.clear();
        await expectLater(
          archive.readMember(member, maxBytes: logical),
          throwsA(_error(ArchiveMessageCode.archiveLimit, 'Buffered')),
        );
        expect(source.reads, isEmpty);
        final prefix = await archive
            .openMember(member, maxBytes: logical, chunkSize: 1048576)
            .take(1)
            .single;
        expect(prefix.length, 65536);
        expect(prefix.take(fixture.payload.length), fixture.payload);
        expect(source.reads, [(fixture.fileOffset, 65536)]);
      },
    );

    test(
      'member allowance limits reads without hiding oversized metadata',
      () async {
        final fixture = FatFixture();
        final archive = await _open(fixture, maxMemberBytes: 1);
        addTearDown(archive.close);
        expect(archive.members.single.size, fixture.payload.length);
        expect(archive.maxStreamingMemberBytes, 1);
        await expectLater(
          archive.readMember(archive.members.single),
          throwsA(_error(ArchiveMessageCode.archiveLimit)),
        );
        await expectLater(
          archive.openMember(archive.members.single).toList(),
          throwsA(_error(ArchiveMessageCode.archiveLimit)),
        );
      },
    );
  });

  group('FAT recognition and ownership', () {
    test(
      'explicit marker routes a malformed BPB to precise FAT rejection',
      () async {
        final fixture = FatFixture();
        fixture.boot[13] = 3;
        final source = fixture.source();
        expect(await hasFatVolumeRecognition(source), isTrue);
        expect(source.reads, [(0, 512)]);
        expect(source.closeCount, 0);
        await source.close();
        await _reject(fixture, detail: 'sectors-per-cluster');
      },
    );

    test(
      'unlabeled FAT recognizes geometry, exFAT stays outside this probe',
      () async {
        final fixture = FatFixture();
        fixture.boot.fillRange(54, 62, 32);
        final source = fixture.source();
        expect(await hasFatVolumeRecognition(source), isTrue);
        expect(source.closeCount, 0);
        await source.close();
        fixture.boot.setRange(3, 11, ascii.encode('EXFAT   '));
        final exfat = fixture.source();
        expect(await hasFatVolumeRecognition(exfat), isFalse);
        expect(exfat.closeCount, 0);
        await exfat.close();
        await _reject(
          fixture,
          code: ArchiveMessageCode.unsupported,
          detail: 'exFAT',
        );
      },
    );

    test(
      'short source and missing boot signature are not positively recognized',
      () async {
        final fixture = FatFixture();
        final short = _ControlledSource(fixture, reportedLength: 511);
        expect(await hasFatVolumeRecognition(short), isFalse);
        expect(short.reads, isEmpty);
        expect(short.closeCount, 0);
        await short.close();
        fixture.boot[511] = 0;
        final invalid = fixture.source();
        expect(await hasFatVolumeRecognition(invalid), isFalse);
        await invalid.close();
        await _reject(fixture, detail: '55AA');
      },
    );

    test(
      'short source responses are rejected and owned source closes',
      () async {
        final source = _ControlledSource(FatFixture(), truncateBy: 1);
        await expectLater(
          openFatArchive(source, maxMemberBytes: 100),
          throwsA(_error(ArchiveMessageCode.corrupt, 'Truncated')),
        );
        expect(source.closeCount, 1);
      },
    );

    test('transport exception identity survives a failing close', () async {
      final failure = StateError('provider revoked');
      final source = _ControlledSource(
        FatFixture(),
        readFailure: failure,
        closeFailure: StateError('cleanup'),
      );
      await expectLater(
        openFatArchive(source, maxMemberBytes: 100),
        throwsA(same(failure)),
      );
      expect(source.closeCount, 1);
    });

    test('invalid configured limits close the newly owned source', () async {
      final source = FatFixture().source();
      await expectLater(
        openFatArchive(source, maxMemberBytes: 100, maxEntries: 100001),
        throwsArgumentError,
      );
      expect(source.closeCount, 1);
      expect(source.reads, isEmpty);
    });

    test('trailing bytes do not become part of the filesystem', () async {
      final fixture = FatFixture();
      final source = _ControlledSource(
        fixture,
        reportedLength: fixture.length + 512,
      );
      final archive = await openFatArchive(source, maxMemberBytes: 100);
      addTearDown(archive.close);
      expect(archive.notices.join(' '), contains('after the BPB-declared'));
      expect(await archive.readMember(archive.members.single), fixture.payload);
      expect(source.reads.every((r) => r.$1 + r.$2 <= fixture.length), isTrue);
    });
  });

  group('FAT names and directory structure', () {
    for (final name in [
      'café-雪.txt',
      'emoji-😀.txt',
      'abcdefghijklm',
      'abcdefghijklmnopqrstuvwxyz',
      '${'x' * 251}.txt',
    ]) {
      test(
        'validated VFAT name survives exactly: ${name.length} UTF-16 units',
        () async {
          final fixture = FatFixture(fileName: name);
          final archive = await _open(fixture);
          addTearDown(archive.close);
          expect(archive.members.single.name, name);
          expect(
            await archive.readMember(archive.members.single),
            fixture.payload,
          );
        },
      );
    }

    for (final first in [0x82, 0x05]) {
      test(
        'Unicode name admits opaque OEM/DBCS alias beginning $first',
        () async {
          final fixture = FatFixture(includeFile: false);
          final alias = fatAlias('OEM~1.TXT')
            ..[0] = first
            ..[1] = 0x5c
            ..[2] = 0x61;
          fixture.setRoot(_namedEntries('漢字.txt', aliasBytes: alias));
          final archive = await _open(fixture);
          addTearDown(archive.close);
          expect(archive.members.single.name, '漢字.txt');
        },
      );
    }

    test(
      'DBCS trail case is not folded into a false raw-alias collision',
      () async {
        final fixture = FatFixture(includeFile: false);
        final a = fatAlias('OEM~1.TXT')
          ..[0] = 0x82
          ..[1] = 0x61;
        final b = Uint8List.fromList(a)..[1] = 0x41;
        fixture.setRoot([
          ..._namedEntries('one.txt', aliasBytes: a),
          ..._namedEntries('two.txt', aliasBytes: b),
        ]);
        final archive = await _open(fixture);
        addTearDown(archive.close);
        expect(archive.members.map((m) => m.name), ['one.txt', 'two.txt']);
      },
    );

    test(
      'OEM-only name is explicit unsupported, never lossy replacement',
      () async {
        final fixture = FatFixture();
        fixture.fileEntry[0] = 0x82;
        await _reject(
          fixture,
          code: ArchiveMessageCode.unsupported,
          detail: 'OEM',
        );
      },
    );

    test('ASCII short name retains embedded spaces and NT case bits', () async {
      final fixture = FatFixture(includeFile: false);
      fixture.setRoot([fatShortEntry('AB CD.TXT', ntCase: 0x18)]);
      final archive = await _open(fixture);
      addTearDown(archive.close);
      expect(archive.members.single.name, 'ab cd.txt');
    });

    test(
      'root volume label and deleted slots do not become extracted entries',
      () async {
        final fixture = FatFixture(includeFile: false);
        final deleted = fatShortEntry('OLD.TXT', firstCluster: 999, size: 100)
          ..[0] = 0xe5;
        fixture.setRoot([
          fatShortEntry('LABEL', attributes: 8),
          deleted,
          fatShortEntry('LIVE.TXT'),
        ]);
        final archive = await _open(fixture);
        addTearDown(archive.close);
        expect(archive.members.map((m) => m.name), ['LIVE.TXT']);
      },
    );

    test('directory end marker excludes stale later records', () async {
      final fixture = FatFixture(includeFile: false);
      fixture.setRoot([
        fatShortEntry('LIVE'),
        Uint8List(32),
        fatShortEntry('STALE', firstCluster: 999, size: 7),
      ]);
      final archive = await _open(fixture);
      addTearDown(archive.close);
      expect(archive.members.map((m) => m.name), ['LIVE']);
    });

    final mutations = <String, void Function(List<Uint8List>)>{
      'alias checksum': (records) => records.last[0] = 0x58,
      'missing final ordinal': (records) => records.first[0] &= 0x3f,
      'wrong ordinal order': (records) => records[1][0] = 2,
      'different slot checksum': (records) => records[1][13] ^= 1,
      'nonzero first cluster': (records) => records.first[26] = 1,
      'nonminimal terminator sequence': (records) => fatPut16(records[1], 1, 0),
      'terminator padding': (records) => fatPut16(records.first, 30, 0x41),
      'unpaired high surrogate': (records) => fatPut16(records[1], 1, 0xd800),
      'unpaired low surrogate': (records) => fatPut16(records[1], 1, 0xdc00),
      'reserved Unicode unit': (records) => fatPut16(records[1], 1, 0xffff),
    };
    for (final mutation in mutations.entries) {
      test(
        'malformed LFN ${mutation.key} never falls back to its alias',
        () async {
          final fixture = FatFixture(includeFile: false);
          final records = _namedEntries('long-unicode-name.txt');
          mutation.value(records);
          fixture.setRoot(records);
          await _reject(fixture);
        },
      );
    }

    test('unknown LFN type is explicit unsupported', () async {
      final fixture = FatFixture(includeFile: false);
      final records = _namedEntries('Unicode.txt')..first[12] = 1;
      fixture.setRoot(records);
      await _reject(
        fixture,
        code: ArchiveMessageCode.unsupported,
        detail: 'record type',
      );
    });

    test('incomplete and orphan LFN sequences are rejected', () async {
      for (final ending in [
        <Uint8List>[],
        [fatShortEntry('DELETED')..[0] = 0xe5],
      ]) {
        final fixture = FatFixture(includeFile: false);
        fixture.setRoot([
          ...fatLongEntries('orphan.txt', fatAlias('ORPHAN.TXT')),
          ...ending,
        ]);
        await _reject(fixture, detail: 'orphan');
      }
      final fixture = FatFixture(includeFile: false);
      final records = _namedEntries('long-unicode-name.txt')..removeAt(1);
      fixture.setRoot(records);
      await _reject(fixture, detail: 'Incomplete');
    });

    for (final name in [
      '../escape',
      'a/b',
      r'a\b',
      'name:stream',
      ' leading',
      'trailing ',
      'trailing.',
      '.',
      '..',
      'bad\u0001name',
    ]) {
      test(
        'unsafe Unicode component is rejected: ${jsonEncode(name)}',
        () async {
          final fixture = FatFixture(includeFile: false);
          fixture.setRoot(_namedEntries(name));
          await _reject(fixture, detail: 'filename component');
        },
      );
    }

    for (final name in ['CON', 'nul.txt', 'COM1.log', 'LPT9']) {
      test(
        'reserved extraction component $name is explicitly unsupported',
        () async {
          final fixture = FatFixture(includeFile: false);
          fixture.setRoot(_namedEntries(name));
          await _reject(
            fixture,
            code: ArchiveMessageCode.unsupported,
            detail: 'device',
          );
        },
      );
    }

    test(
      'case aliases and long-name/short-name collisions are rejected',
      () async {
        for (final other in ['LONGNA~1.TXT', 'ONE.TXT']) {
          final fixture = FatFixture(includeFile: false);
          fixture.setRoot([..._namedEntries('one.txt'), fatShortEntry(other)]);
          await _reject(fixture, detail: 'conflicting');
        }
      },
    );

    test(
      'identical opaque OEM aliases cannot bind different long names',
      () async {
        final fixture = FatFixture(includeFile: false);
        final alias = fatAlias('OEM~1.TXT')..[0] = 0x82;
        fixture.setRoot([
          ..._namedEntries('one', aliasBytes: alias),
          ..._namedEntries('two', aliasBytes: alias),
        ]);
        await _reject(fixture, detail: 'conflicting');
      },
    );

    test('bad parent pointer and missing dot entries are rejected', () async {
      for (final missing in [false, true]) {
        final fixture = FatFixture(includeFile: false);
        fixture.setRoot([
          fatShortEntry('DIR', firstCluster: 10, isDirectory: true),
        ]);
        fixture.setDirectory(10, [], parent: missing ? 0 : 2);
        if (missing) fixture.setByte(fixture.clusterOffset(10), 0);
        await _reject(fixture, detail: missing ? 'Missing dot' : 'parent');
      }
    });

    test(
      'directory size and FAT12/16 high cluster words are validated',
      () async {
        final directory = FatFixture(includeFile: false);
        directory.setRoot([
          fatShortEntry('DIR', firstCluster: 10, size: 1, isDirectory: true),
        ]);
        directory.setDirectory(10, []);
        await _reject(directory, detail: 'nonzero file-size');
        final file = FatFixture();
        fatPut16(file.fileEntry, 20, 1);
        await _reject(file, detail: 'high cluster word');
      },
    );

    test(
      'invalid timestamp is omitted without changing file payload',
      () async {
        final fixture = FatFixture();
        fatPut16(fixture.fileEntry, 24, (20 << 9) | (2 << 5) | 31);
        final archive = await _open(fixture);
        addTearDown(archive.close);
        expect(archive.members.single.modified, isNull);
        expect(archive.notices.join(' '), contains('timestamps were omitted'));
        expect(
          await archive.readMember(archive.members.single),
          fixture.payload,
        );
      },
    );
  });

  group('FAT corruption, state and authoritative tables', () {
    final geometryFailures = <String, void Function(FatFixture)>{
      'zero reserved region': (f) => fatPut16(f.boot, 14, 0),
      'ambiguous total counts': (f) => fatPut32(f.boot, 32, f.totalSectors),
      'zero sectors per cluster': (f) => f.boot[13] = 0,
      'short declared volume': (f) => fatPut16(f.boot, 19, 2),
      'volume exceeds input': (f) => fatPut16(f.boot, 19, f.totalSectors + 1),
      'table too short': (f) => fatPut16(f.boot, 22, 1),
      'unaligned fixed root': (f) => fatPut16(f.boot, 17, 1),
      'media disagreement': (f) => f.boot[21] = 0xf0,
      'invalid media': (f) => f.boot[21] = 0xf1,
      'missing FAT header': (f) => f.setFat(0, 0),
      'invalid reserved FAT entry': (f) => f.setFat(1, 2),
    };
    for (final failure in geometryFailures.entries) {
      test('rejects ${failure.key}', () async {
        final fixture = FatFixture();
        failure.value(fixture);
        await _reject(fixture);
      });
    }

    test(
      'unsupported sector sizes, cluster sizes and table counts are explicit',
      () async {
        final sector = FatFixture();
        fatPut16(sector.boot, 11, 8192);
        await _reject(
          sector,
          code: ArchiveMessageCode.unsupported,
          detail: 'sector size',
        );
        final cluster = FatFixture(sectorsPerCluster: 128);
        await _reject(
          cluster,
          code: ArchiveMessageCode.unsupported,
          detail: '32 KiB',
        );
        final copies = FatFixture();
        copies.boot[16] = 3;
        await _reject(
          copies,
          code: ArchiveMessageCode.unsupported,
          detail: 'tables',
        );
      },
    );

    for (final bits in [12, 16, 32]) {
      test(
        'FAT$bits rejects free, reserved, bad and out-of-range chains',
        () async {
          for (final value in [
            0,
            1,
            bits == 12 ? 0xff0 : (bits == 16 ? 0xfff0 : 0x0ffffff0),
            bits == 12 ? 0xff7 : (bits == 16 ? 0xfff7 : 0x0ffffff7),
            bits == 12 ? 2000 : (bits == 16 ? 10000 : 70000),
          ]) {
            final fixture = FatFixture(bits: bits);
            fixture.setFat(fixture.fileStartCluster, value);
            await _reject(fixture, detail: 'cluster reference');
          }
        },
      );

      test('FAT$bits rejects short, long and cyclic file chains', () async {
        final short = FatFixture(bits: bits, fileData: List.filled(513, 42));
        short.setFat(short.fileStartCluster, short.fatMask);
        await _reject(short, detail: 'shorter');
        final long = FatFixture(bits: bits);
        long.setFat(long.fileStartCluster, 100);
        long.setFat(100, long.fatMask);
        await _reject(long, detail: 'exceeds');
        final cyclic = FatFixture(bits: bits, fileData: List.filled(1536, 42));
        cyclic.setFat(cyclic.fileClusters[1], cyclic.fileStartCluster);
        await _reject(cyclic, detail: 'loops');
      });

      test(
        'FAT$bits rejects cross-linked live file and directory chains',
        () async {
          final fixture = FatFixture(bits: bits);
          fixture.setRoot([
            Uint8List.fromList(fixture.fileEntry),
            fatShortEntry(
              'OTHER',
              firstCluster: fixture.fileStartCluster,
              size: fixture.payload.length,
            ),
          ]);
          await _reject(fixture, detail: 'crosses');
          final directory = FatFixture(bits: bits, includeFile: false);
          directory.setRoot([
            fatShortEntry('DIR', firstCluster: 10, isDirectory: true),
          ]);
          directory.setDirectory(10, [
            fatShortEntry('SELF', firstCluster: 10, isDirectory: true),
          ]);
          await _reject(directory, detail: 'crosses');
        },
      );

      test('FAT$bits compares mirrored traversed entries', () async {
        final fixture = FatFixture(bits: bits);
        fixture.setFat(fixture.fileStartCluster, 100, table: 1);
        await _reject(fixture, detail: 'Mirrored');
      });
    }

    test('empty file with allocated clusters is rejected', () async {
      final fixture = FatFixture();
      fatPut32(fixture.fileEntry, 28, 0);
      await _reject(fixture, detail: 'empty regular file');
    });

    test('unreferenced FAT mismatches are outside the listing check', () async {
      final fixture = FatFixture();
      fixture.setFat(100, 101, table: 1);
      final archive = await _open(fixture);
      addTearDown(archive.close);
      expect(archive.notices.join(' '), contains('unreferenced clusters'));
      expect(await archive.readMember(archive.members.single), fixture.payload);
    });

    for (final bits in [16, 32]) {
      test(
        'FAT$bits dirty and disk-error state is visible without repair',
        () async {
          final fixture = FatFixture(bits: bits);
          fixture.setFat(1, bits == 16 ? 0x3fff : 0x03ffffff);
          final archive = await _open(fixture);
          addTearDown(archive.close);
          expect(archive.notices.join(' '), contains('marked dirty'));
          expect(archive.notices.join(' '), contains('earlier disk I/O error'));
          expect(
            await archive.readMember(archive.members.single),
            fixture.payload,
          );
        },
      );
    }

    test(
      'FAT32 reserved upper entry bits do not alter chain or mirror comparison',
      () async {
        final fixture = FatFixture(bits: 32);
        fixture.setFat(0, 0xaffffff8, table: 0);
        fixture.setFat(1, 0xbfffffff, table: 0);
        fixture.setFat(2, 0xcfffffff, table: 0);
        fixture.setFat(3, 0xdfffffff, table: 0);
        final archive = await _open(fixture);
        addTearDown(archive.close);
        expect(
          await archive.readMember(archive.members.single),
          fixture.payload,
        );
      },
    );

    test(
      'FAT32 disabled mirroring honors active table and ignores stale copy',
      () async {
        final fixture = FatFixture(bits: 32, mirrored: false, activeFat: 1);
        for (final cluster in [0, 1, 2, 3]) {
          fixture.setFat(cluster, 0, table: 0);
        }
        final archive = await _open(fixture);
        addTearDown(archive.close);
        expect(archive.notices.join(' '), contains('uses FAT 2 only'));
        expect(
          await archive.readMember(archive.members.single),
          fixture.payload,
        );
      },
    );

    test(
      'FAT32 bad active table never falls back to valid inactive copy',
      () async {
        final fixture = FatFixture(bits: 32, mirrored: false, activeFat: 1);
        fixture.setFat(3, 0, table: 1);
        await _reject(fixture, detail: 'cluster reference');
      },
    );

    test(
      'FAT32 invalid active index, root pointer and unknown flags fail',
      () async {
        final active = FatFixture(bits: 32, mirrored: false, activeFat: 2);
        await _reject(active, detail: 'Active FAT index');
        final root = FatFixture(bits: 32);
        fatPut32(root.boot, 44, 0xf0000002);
        await _reject(root, detail: 'cluster reference');
        final flags = FatFixture(bits: 32);
        fatPut16(flags.boot, 40, 0x100);
        await _reject(
          flags,
          code: ArchiveMessageCode.unsupported,
          detail: 'extended flags',
        );
        final version = FatFixture(bits: 32);
        fatPut16(version.boot, 42, 1);
        await _reject(
          version,
          code: ArchiveMessageCode.unsupported,
          detail: 'version',
        );
      },
    );

    test(
      'FAT32 invalid FSInfo is advisory and cannot replace allocation',
      () async {
        final fixture = FatFixture(bits: 32);
        fatPut32(fixture.sector(1), 0, 0);
        fatPut32(fixture.sector(1), 488, fixture.clusterCount + 1);
        fatPut32(fixture.sector(1), 492, 1);
        final archive = await _open(fixture);
        addTearDown(archive.close);
        expect(
          archive.notices.join(' '),
          contains('FSInfo hints were ignored'),
        );
        expect(
          await archive.readMember(archive.members.single),
          fixture.payload,
        );
      },
    );

    test('FAT32 absent hints and differing backup remain explicit', () async {
      final fixture = FatFixture(bits: 32);
      fatPut16(fixture.boot, 48, 0xffff);
      final archive = await _open(fixture);
      addTearDown(archive.close);
      expect(archive.notices.join(' '), contains('FSInfo hints are absent'));
      expect(
        archive.notices.join(' '),
        contains('backup boot metadata differs'),
      );
    });

    test('FAT32 hint pointers must remain in the reserved region', () async {
      final info = FatFixture(bits: 32);
      fatPut16(info.boot, 48, 32);
      await _reject(info, detail: 'FSInfo pointer');
      final backup = FatFixture(bits: 32);
      fatPut16(backup.boot, 50, 1);
      await _reject(backup, detail: 'Backup boot pointer');
    });
  });

  group('FAT compositional limits and cancellation', () {
    final limits = <String, Future<ViewerArchive> Function(FatFixtureSource)>{
      'metadata': (s) =>
          openFatArchive(s, maxMemberBytes: 100, maxMetadataBytes: 511),
      'directory allocation': (s) =>
          openFatArchive(s, maxMemberBytes: 100, maxDirectoryBytes: 4095),
      'component text': (s) =>
          openFatArchive(s, maxMemberBytes: 100, maxNameBytes: 1),
      'retained full paths': (s) =>
          openFatArchive(s, maxMemberBytes: 100, maxRetainedPathBytes: 1),
      'allocation extents': (s) =>
          openFatArchive(s, maxMemberBytes: 100, maxExtents: 1),
    };
    for (final limit in limits.entries) {
      test('${limit.key} allowance fails atomically', () async {
        await _reject(
          FatFixture(),
          code: ArchiveMessageCode.archiveLimit,
          open: limit.value,
        );
      });
    }

    test(
      'directory entry count is checked before accepting the next member',
      () async {
        final fixture = FatFixture(includeFile: false);
        fixture.setRoot([fatShortEntry('ONE'), fatShortEntry('TWO')]);
        await _reject(
          fixture,
          code: ArchiveMessageCode.entryLimit,
          open: (s) => openFatArchive(s, maxMemberBytes: 100, maxEntries: 1),
        );
      },
    );

    test(
      'cluster allowance bounds long contiguous files despite one extent',
      () async {
        final fixture = FatFixture(fileData: List.filled(1024, 3));
        await _reject(
          fixture,
          code: ArchiveMessageCode.archiveLimit,
          detail: 'Cluster traversal',
          open: (s) => openFatArchive(s, maxMemberBytes: 2048, maxClusters: 1),
        );
      },
    );

    test('full-path accounting includes repeated parent prefixes', () async {
      final fixture = FatFixture(includeFile: false);
      fixture.setRoot([
        fatShortEntry('PARENT', firstCluster: 10, isDirectory: true),
      ]);
      fixture.setDirectory(10, [fatShortEntry('A'), fatShortEntry('B')]);
      // Component text is 16 bytes, but retained paths need 44 bytes.
      await _reject(
        fixture,
        code: ArchiveMessageCode.archiveLimit,
        detail: 'full-path',
        open: (s) => openFatArchive(
          s,
          maxMemberBytes: 100,
          maxNameBytes: 16,
          maxRetainedPathBytes: 43,
        ),
      );
    });

    test('depth limit applies even to empty nested directories', () async {
      final fixture = FatFixture(includeFile: false);
      fixture.setRoot([
        fatShortEntry('A', firstCluster: 10, isDirectory: true),
      ]);
      fixture.setDirectory(10, [
        fatShortEntry('B', firstCluster: 11, isDirectory: true),
      ]);
      fixture.setDirectory(11, [], parent: 10);
      await _reject(
        fixture,
        code: ArchiveMessageCode.archiveLimit,
        detail: 'depth',
        open: (s) => openFatArchive(s, maxMemberBytes: 100, maxDepth: 1),
      );
    });

    test(
      'shared cluster and extent budgets span independently opened volumes',
      () async {
        final budget = ArchiveFatTraversalBudget(maxClusters: 1, maxExtents: 4);
        final first = await openFatArchive(
          FatFixture().source(),
          maxMemberBytes: 100,
          traversalBudget: budget,
        );
        addTearDown(first.close);
        expect(budget.clustersVisited, 1);
        expect(budget.extentsCreated, 2);
        await _reject(
          FatFixture(),
          code: ArchiveMessageCode.archiveLimit,
          detail: 'Shared cluster',
          open: (s) =>
              openFatArchive(s, maxMemberBytes: 100, traversalBudget: budget),
        );
        expect(budget.remainingClusters, 0);
        expect(budget.extentsCreated, 3);
        final extentBudget = ArchiveFatTraversalBudget(maxExtents: 2);
        final accepted = await openFatArchive(
          FatFixture().source(),
          maxMemberBytes: 100,
          traversalBudget: extentBudget,
        );
        addTearDown(accepted.close);
        await _reject(
          FatFixture(),
          code: ArchiveMessageCode.archiveLimit,
          detail: 'Shared allocation',
          open: (s) => openFatArchive(
            s,
            maxMemberBytes: 100,
            traversalBudget: extentBudget,
          ),
        );
        expect(extentBudget.remainingExtents, 0);
      },
    );

    test('failed volume traversal does not refund shared work', () async {
      final fixture = FatFixture();
      fixture.setFat(fixture.fileStartCluster, 0);
      final budget = ArchiveFatTraversalBudget(maxClusters: 2);
      await _reject(
        fixture,
        open: (s) =>
            openFatArchive(s, maxMemberBytes: 100, traversalBudget: budget),
      );
      expect(budget.clustersVisited, 1);
      expect(budget.extentsCreated, 2);
    });

    test(
      'pre-cancelled open has a distinct cancellation type and no reads',
      () async {
        final source = FatFixture().source();
        await expectLater(
          openFatArchive(source, maxMemberBytes: 100, isCancelled: () => true),
          throwsA(isA<ArchiveFatCancelledException>()),
        );
        expect(source.reads, isEmpty);
        expect(source.closeCount, 1);
      },
    );

    test(
      'callback failures remain transport-like failures, not corrupt FAT',
      () async {
        final source = FatFixture().source();
        final failure = StateError('revoked capability');
        await expectLater(
          openFatArchive(
            source,
            maxMemberBytes: 100,
            isCancelled: () => throw failure,
          ),
          throwsA(same(failure)),
        );
        expect(source.closeCount, 1);
      },
    );

    test('cached FAT chain work yields to cancellation before exhausting the chain', () async {
      final fixture = FatFixture(fileData: List.filled(512 * 800, 0x41));
      final source = fixture.source();
      var cancelled = false;
      final budget = ArchiveFatTraversalBudget();
      final opening = openFatArchive(
        source,
        maxMemberBytes: 1048576,
        traversalBudget: budget,
        isCancelled: () => cancelled,
      );
      Timer.run(() => cancelled = true);
      await expectLater(opening, throwsA(isA<ArchiveFatCancelledException>()));
      expect(budget.clustersVisited, greaterThan(0));
      expect(budget.clustersVisited, lessThan(800));
      expect(source.closeCount, 1);
    });

    test('cached directory records also yield to cancellation', () async {
      final fixture = FatFixture(includeFile: false);
      fixture.setRoot(List.generate(128, (i) => fatShortEntry('F$i')));
      final source = fixture.source();
      var cancelled = false;
      final opening = openFatArchive(
        source,
        maxMemberBytes: 100,
        isCancelled: () => cancelled,
      );
      Timer.run(() => cancelled = true);
      await expectLater(opening, throwsA(isA<ArchiveFatCancelledException>()));
      expect(source.closeCount, 1);
    });

    test('cancellation after listing stops payload reads', () async {
      var cancelled = false;
      final source = FatFixture().source();
      final archive = await openFatArchive(
        source,
        maxMemberBytes: 100,
        isCancelled: () => cancelled,
      );
      addTearDown(archive.close);
      source.reads.clear();
      cancelled = true;
      await expectLater(
        archive.readMember(archive.members.single),
        throwsA(isA<ArchiveFatCancelledException>()),
      );
      expect(source.reads, isEmpty);
    });
  });
}

class _ControlledSource extends FatFixtureSource {
  _ControlledSource(
    super.fixture, {
    this.reportedLength,
    this.truncateBy = 0,
    this.readFailure,
    this.closeFailure,
  });
  final int? reportedLength;
  final int truncateBy;
  final Object? readFailure, closeFailure;
  @override
  int get length => reportedLength ?? super.length;
  @override
  Future<Uint8List> read(int offset, int length) async {
    if (readFailure != null) throw readFailure!;
    final result = await super.read(offset, length);
    return truncateBy == 0
        ? result
        : Uint8List.sublistView(result, 0, result.length - truncateBy);
  }

  @override
  Future<void> close() async {
    await super.close();
    if (closeFailure != null) throw closeFailure!;
  }
}
