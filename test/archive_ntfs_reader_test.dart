// Copyright 2026 CrispCloud contributors
// SPDX-License-Identifier: MIT

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import 'package:crisp_cloud/services/archive_ntfs_reader.dart';
import 'package:crisp_cloud/services/archive_types.dart';

import 'support/archive_ntfs_fixture.dart';

Future<ViewerArchive> _open(
  NtfsFixture fixture, {
  int limit = kArchiveStreamingLimit,
}) => openNtfsArchive(fixture.source(), maxMemberBytes: limit);
Matcher _code(ArchiveMessageCode code) =>
    isA<ArchiveViewException>().having((error) => error.code, 'code', code);
Future<void> _reject(
  NtfsFixture fixture, [
  ArchiveMessageCode code = ArchiveMessageCode.corrupt,
]) async {
  final source = fixture.source();
  await expectLater(
    openNtfsArchive(source, maxMemberBytes: kArchiveStreamingLimit),
    throwsA(_code(code)),
  );
  expect(source.closeCount, 1);
  expect(
    source.reads.every(
      (read) =>
          read.$1 >= 0 &&
          read.$2 >= 0 &&
          read.$2 <= 65536 &&
          read.$1 + read.$2 <= source.length,
    ),
    isTrue,
  );
}

void _attribute(
  NtfsFixture fixture,
  int record,
  int type,
  void Function(Uint8List bytes, int at) change, {
  String name = '',
}) {
  fixture.mutateRecord(record, (bytes) {
    change(bytes, NtfsFixture.attributeOffset(bytes, type, name: name));
  });
}

NtfsFixture _mapped({
  int size = 2048,
  int initialized = -1,
  List<NtfsFixtureRun> runs = const [NtfsFixtureRun(2, 60)],
  int flags = 0,
  int compressionUnit = 0,
}) {
  final fixture = NtfsFixture(
    dataAttribute: ntfsMappedAttribute(
      0x80,
      size: size,
      initialized: initialized,
      runs: runs,
      flags: flags,
      compressionUnit: compressionUnit,
    ),
  );
  for (final run in runs) {
    if (run.lcn != null) {
      for (var cluster = run.lcn!; cluster < run.lcn! + run.count; cluster++) {
        fixture.allocate(cluster);
      }
    }
  }
  fixture.syncBitmap();
  return fixture;
}

void main() {
  group('NTFS recognition and ownership', () {
    test('OEM probe is minimal and never owns the source', () async {
      final bytes = Uint8List(11)..setRange(3, 11, ascii.encode('NTFS    '));
      final source = NtfsFixtureSource(bytes);
      expect(await hasNtfsVolumeRecognition(source), isTrue);
      expect(source.reads, [(3, 8)]);
      expect(source.closeCount, 0);
      bytes[10] = 0;
      expect(await hasNtfsVolumeRecognition(source), isFalse);
      final short = NtfsFixtureSource(Uint8List(10));
      expect(await hasNtfsVolumeRecognition(short), isFalse);
      expect(short.reads, isEmpty);
    });

    test(
      'probe preserves provider failure and rejects a short range',
      () async {
        final source = NtfsFixture().source(), error = StateError('provider');
        source.readFailure = error;
        await expectLater(
          hasNtfsVolumeRecognition(source),
          throwsA(same(error)),
        );
        source.readFailure = null;
        source.shortRead = true;
        await expectLater(
          hasNtfsVolumeRecognition(source),
          throwsA(_code(ArchiveMessageCode.corrupt)),
        );
        expect(source.closeCount, 0);
      },
    );

    test('invalid arguments still close the owned source once', () async {
      for (final limit in [0, -1, kArchiveStreamingLimit + 1]) {
        final source = NtfsFixture().source();
        await expectLater(
          openNtfsArchive(source, maxMemberBytes: limit),
          throwsArgumentError,
        );
        expect(source.closeCount, 1);
        expect(source.reads, isEmpty);
      }
      expect(
        () => ArchiveNtfsTraversalBudget(maxClusters: 0),
        throwsArgumentError,
      );
      expect(
        () => ArchiveNtfsTraversalBudget(maxExtents: 100001),
        throwsArgumentError,
      );
    });

    test('provider exception identity wins over failed cleanup', () async {
      final source = NtfsFixture().source(),
          error = StateError('read identity');
      source.readFailure = error;
      source.closeFailure = StateError('cleanup');
      await expectLater(
        openNtfsArchive(source, maxMemberBytes: 1024),
        throwsA(same(error)),
      );
      expect(source.closeCount, 1);
    });

    test('callback exception identity wins over cleanup', () async {
      final source = NtfsFixture().source(), error = StateError('callback');
      await expectLater(
        openNtfsArchive(
          source,
          maxMemberBytes: 1024,
          isCancelled: () => throw error,
        ),
        throwsA(same(error)),
      );
      expect(source.closeCount, 1);
      expect(source.reads, isEmpty);
    });

    test('pre-cancellation is distinct and closes once', () async {
      final source = NtfsFixture().source();
      await expectLater(
        openNtfsArchive(source, maxMemberBytes: 1024, isCancelled: () => true),
        throwsA(isA<ArchiveNtfsCancelledException>()),
      );
      expect(source.closeCount, 1);
      expect(source.reads, isEmpty);
    });

    test('cancellation after an awaited range is not corruption', () async {
      var cancelled = false;
      final source = NtfsFixture().source()
        ..afterRead = (_, __) {
          cancelled = true;
        };
      await expectLater(
        openNtfsArchive(
          source,
          maxMemberBytes: 1024,
          isCancelled: () => cancelled,
        ),
        throwsA(isA<ArchiveNtfsCancelledException>()),
      );
      expect(source.closeCount, 1);
      expect(source.reads.length, 1);
    });

    test('a changed source length aborts opening', () async {
      final source = NtfsFixture().source();
      source.afterRead = (_, __) {
        source.reportedLength = source.bytes.length + 512;
      };
      await expectLater(
        openNtfsArchive(source, maxMemberBytes: 1024),
        throwsA(_code(ArchiveMessageCode.corrupt)),
      );
      expect(source.closeCount, 1);
    });

    test('a short exact read cannot publish a tree', () async {
      final source = NtfsFixture().source()..shortRead = true;
      await expectLater(
        openNtfsArchive(source, maxMemberBytes: 1024),
        throwsA(_code(ArchiveMessageCode.corrupt)),
      );
      expect(source.closeCount, 1);
    });
  });

  group('NTFS validated ordinary reads', () {
    test('resident data is copied, streams exactly, and closes once', () async {
      final fixture = NtfsFixture(name: 'snow-雪-😀.txt');
      final source = fixture.source(borrowedReads: true);
      final archive = await openNtfsArchive(source, maxMemberBytes: 1024);
      expect(archive.formatName, 'ntfs');
      expect(archive.members.map((entry) => entry.name), ['snow-雪-😀.txt']);
      final member = archive.members.single;
      expect(member.isFile, isTrue);
      expect(member.isSpecial, isFalse);
      expect(member.modified!.isUtc, isTrue);
      expect(await archive.readMember(member), fixture.payload);
      final first = await archive.readMember(member);
      first[0] = 0;
      expect(await archive.readMember(member), fixture.payload);
      expect(
        await archive
            .openMember(member, chunkSize: 3)
            .expand((v) => v)
            .toList(),
        fixture.payload,
      );
      expect(archive.notices.join(' '), contains('system records'));
      await archive.close();
      await archive.close();
      expect(source.closeCount, 1);
    });

    test('providers may reuse one offset backing buffer', () async {
      final fixture = NtfsFixture();
      final archive = await openNtfsArchive(
        _ReusingSource(fixture.bytes),
        maxMemberBytes: 1024,
      );
      expect(await archive.readMember(archive.members.single), fixture.payload);
      await archive.close();
    });

    test('nonresident negative run deltas preserve logical order', () async {
      final fixture = _mapped(
        size: 3000,
        runs: const [
          NtfsFixtureRun(1, 62),
          NtfsFixtureRun(1, 60),
          NtfsFixtureRun(1, 61),
        ],
      );
      fixture.bytes.fillRange(62 * 1024, 63 * 1024, 1);
      fixture.bytes.fillRange(60 * 1024, 61 * 1024, 2);
      fixture.bytes.fillRange(61 * 1024, 62 * 1024, 3);
      final source = fixture.source();
      final archive = await openNtfsArchive(source, maxMemberBytes: 4096);
      expect(
        source.reads.where((r) => r.$1 >= 60 * 1024 && r.$1 < 63 * 1024),
        isEmpty,
      );
      final expected = [
        ...List.filled(1024, 1),
        ...List.filled(1024, 2),
        ...List.filled(952, 3),
      ];
      expect(await archive.readMember(archive.members.single), expected);
      expect(
        await archive
            .openMember(archive.members.single, chunkSize: 777)
            .expand((v) => v)
            .toList(),
        expected,
      );
      await archive.close();
    });

    test(
      'sparse regions and uninitialized tails zero without backing reads',
      () async {
        final fixture = _mapped(
          size: 4096,
          initialized: 3500,
          flags: 0x8000,
          compressionUnit: 4,
          runs: const [
            NtfsFixtureRun(1, 60),
            NtfsFixtureRun(1, null),
            NtfsFixtureRun(2, 61),
          ],
        );
        fixture.bytes.fillRange(60 * 1024, 61 * 1024, 17);
        fixture.bytes.fillRange(61 * 1024, 63 * 1024, 34);
        final source = fixture.source();
        final archive = await openNtfsArchive(source, maxMemberBytes: 8192);
        final expected = [
          ...List.filled(1024, 17),
          ...List.filled(1024, 0),
          ...List.filled(1452, 34),
          ...List.filled(596, 0),
        ];
        expect(await archive.readMember(archive.members.single), expected);
        expect(
          source.reads
              .where((r) => r.$1 >= 61 * 1024 && r.$1 < 63 * 1024)
              .every((r) => r.$1 + r.$2 <= 61 * 1024 + 1452),
          isTrue,
        );
        await archive.close();
      },
    );

    test('a fully uninitialized physical allocation is never read', () async {
      final fixture = _mapped(size: 2048, initialized: 0);
      fixture.bytes.fillRange(60 * 1024, 62 * 1024, 0xee);
      final source = fixture.source();
      final archive = await openNtfsArchive(source, maxMemberBytes: 4096);
      expect(
        await archive.readMember(archive.members.single),
        List.filled(2048, 0),
      );
      expect(
        source.reads.where((r) => r.$1 >= 60 * 1024 && r.$1 < 62 * 1024),
        isEmpty,
      );
      await archive.close();
    });

    test(
      'named DATA keeps its exact name and size only in bounded notices',
      () async {
        const stream = 'notes:private/雪\\draft';
        final fixture = NtfsFixture(
          extraAttributes: [
            ntfsResidentAttribute(0x80, [1, 2, 3, 4], name: stream),
          ],
        );
        final archive = await _open(fixture);
        expect(archive.members.map((entry) => entry.name), ['hello.txt']);
        final notice = archive.notices.singleWhere(
          (value) => value.startsWith('Alternate DATA'),
        );
        expect(notice, contains(jsonEncode(stream)));
        expect(notice, contains('(4 bytes)'));
        expect(notice, contains('not read, tested, or extracted'));
        expect(
          await archive.readMember(archive.members.single),
          fixture.payload,
        );
        await archive.close();
      },
    );

    test('different hardlink paths share one checked allocation', () async {
      final data = ntfsMappedAttribute(
        0x80,
        size: 2048,
        runs: const [NtfsFixtureRun(2, 60)],
      );
      final fixture = _mapped();
      fixture.setFile(data, links: 2, extraNames: [ntfsFileName('alias.txt')]);
      fixture.rootEntries.add(const NtfsFixtureEntry(24, 'alias.txt'));
      fixture.rebuildIndex();
      final budget = ArchiveNtfsTraversalBudget();
      final archive = await openNtfsArchive(
        fixture.source(),
        maxMemberBytes: 4096,
        traversalBudget: budget,
      );
      expect(archive.members.map((entry) => entry.name), [
        'hello.txt',
        'alias.txt',
      ]);
      expect(
        await archive.readMember(archive.members.first),
        await archive.readMember(archive.members.last),
      );
      expect(budget.clustersVisited, 44);
      await archive.close();
    });

    test('DOS aliases are checked but do not duplicate public files', () async {
      final fixture = NtfsFixture(name: 'long-name.txt');
      fixture.setFile(
        ntfsResidentAttribute(0x80, fixture.payload),
        extraNames: [ntfsFileName('LONGNA~1.TXT', namespace: 2)],
      );
      fixture.rootEntries.add(
        const NtfsFixtureEntry(24, 'LONGNA~1.TXT', namespace: 2),
      );
      fixture.rebuildIndex();
      final archive = await _open(fixture);
      expect(archive.members.map((entry) => entry.name), ['long-name.txt']);
      await archive.close();
    });

    test(
      'declared geometry permits trailing padding without reading it',
      () async {
        final fixture = NtfsFixture();
        final source = NtfsFixtureSource(
          Uint8List(fixture.bytes.length + 4096)
            ..setRange(0, fixture.bytes.length, fixture.bytes),
        );
        final archive = await openNtfsArchive(source, maxMemberBytes: 1024);
        expect(
          source.reads.every((r) => r.$1 + r.$2 <= fixture.bytes.length),
          isTrue,
        );
        expect(
          await archive.readMember(archive.members.single),
          fixture.payload,
        );
        await archive.close();
      },
    );

    test('NTFS3.0 uses the older FILE header and coherent mirror', () async {
      final fixture = NtfsFixture();
      _attribute(fixture, 3, 0x70, (b, at) {
        b[at + ntfsGet16(b, at + 20) + 9] = 0;
      });
      for (final number in [...List.generate(16, (i) => i), 24]) {
        final b = fixture.fixedRecord(number);
        final used = ntfsGet32(b, 24);
        final attrs = Uint8List.fromList(b.sublist(56, used));
        b.fillRange(42, b.length, 0);
        ntfsPut16(b, 4, 42);
        ntfsPut16(b, 20, 48);
        ntfsPut32(b, 24, used - 8);
        b.setRange(48, 48 + attrs.length, attrs);
        fixture.writeRecord(number, b);
      }
      fixture.syncMirror();
      final archive = await _open(fixture);
      expect(await archive.readMember(archive.members.single), fixture.payload);
      await archive.close();
    });

    test('future FILETIME is decoded in exact UTC milliseconds', () async {
      final fixture = NtfsFixture();
      // A value whose tick count exceeds the JavaScript exact-integer range.
      const high = 0x12345678, low = 0x87654321;
      _attribute(fixture, 24, 0x10, (b, at) {
        final value = at + ntfsGet16(b, at + 20);
        ntfsPut32(b, value + 8, low);
        ntfsPut32(b, value + 12, high);
      });
      final archive = await _open(fixture);
      final expected =
          (BigInt.from(high) * BigInt.from(4294967296) + BigInt.from(low)) ~/
              BigInt.from(10000) -
          BigInt.from(11644473600000);
      expect(
        archive.members.single.modified!.millisecondsSinceEpoch,
        expected.toInt(),
      );
      expect(archive.members.single.modified!.isUtc, isTrue);
      await archive.close();
    });
  });

  group('NTFS resource and deferred read boundaries', () {
    test(
      'large files stay listed but caller allowance blocks both reads',
      () async {
        final fixture = _mapped();
        final source = fixture.source();
        final archive = await openNtfsArchive(source, maxMemberBytes: 1024);
        expect(archive.members.single.size, 2048);
        final before = source.reads.length;
        await expectLater(
          archive.readMember(archive.members.single, maxBytes: 4096),
          throwsA(_code(ArchiveMessageCode.archiveLimit)),
        );
        await expectLater(
          archive
              .openMember(archive.members.single, maxBytes: 4096)
              .drain<void>(),
          throwsA(_code(ArchiveMessageCode.archiveLimit)),
        );
        expect(source.reads.length, before);
        await archive.close();
      },
    );

    test(
      '64MiB buffered hard cap remains despite an8GiB stream allowance',
      () async {
        const size = kArchiveReadLimit + 1;
        final fixture = _mapped(
          size: size,
          flags: 0x8000,
          compressionUnit: 4,
          runs: const [NtfsFixtureRun((size + 1023) ~/ 1024, null)],
        );
        final source = fixture.source();
        final archive = await openNtfsArchive(
          source,
          maxMemberBytes: kArchiveStreamingLimit,
        );
        final before = source.reads.length;
        await expectLater(
          archive.readMember(
            archive.members.single,
            maxBytes: kArchiveStreamingLimit,
          ),
          throwsA(_code(ArchiveMessageCode.archiveLimit)),
        );
        final first = await archive
            .openMember(
              archive.members.single,
              maxBytes: kArchiveStreamingLimit,
              chunkSize: 4096,
            )
            .first;
        expect(first, List.filled(4096, 0));
        expect(source.reads.length, before);
        await archive.close();
      },
    );

    test('source changes and cancellation after opening stop reads', () async {
      var cancelled = false;
      final source = NtfsFixture().source();
      final archive = await openNtfsArchive(
        source,
        maxMemberBytes: 1024,
        isCancelled: () => cancelled,
      );
      source.reportedLength = source.length + 1;
      await expectLater(
        archive.readMember(archive.members.single),
        throwsA(_code(ArchiveMessageCode.corrupt)),
      );
      source.reportedLength = null;
      cancelled = true;
      await expectLater(
        archive.openMember(archive.members.single).drain<void>(),
        throwsA(isA<ArchiveNtfsCancelledException>()),
      );
      await archive.close();
      expect(source.closeCount, 1);
    });

    test('deferred payload provider errors retain identity', () async {
      final fixture = _mapped();
      final source = fixture.source(), error = StateError('payload source');
      final archive = await openNtfsArchive(source, maxMemberBytes: 4096);
      source.readFailure = error;
      source.failWhen = (offset, _) =>
          offset >= 60 * 1024 && offset < 62 * 1024;
      await expectLater(
        archive.readMember(archive.members.single),
        throwsA(same(error)),
      );
      await expectLater(
        archive.openMember(archive.members.single).drain<void>(),
        throwsA(same(error)),
      );
      await archive.close();
      expect(source.closeCount, 1);
    });

    test('lowered metadata, directory, allocation, extent and path budgets fail explicitly', () async {
      final constructors = <Future<ViewerArchive> Function(NtfsFixtureSource)>[
        (s) => openNtfsArchive(s, maxMemberBytes: 1024, maxMetadataBytes: 511),
        (s) => openNtfsArchive(s, maxMemberBytes: 1024, maxDirectoryBytes: 512),
        (s) => openNtfsArchive(s, maxMemberBytes: 1024, maxClusters: 1),
        (s) => openNtfsArchive(s, maxMemberBytes: 1024, maxExtents: 1),
        (s) =>
            openNtfsArchive(s, maxMemberBytes: 1024, maxRetainedPathBytes: 1),
      ];
      for (final open in constructors) {
        final source = NtfsFixture().source();
        await expectLater(
          open(source),
          throwsA(_code(ArchiveMessageCode.archiveLimit)),
        );
        expect(source.closeCount, 1);
      }
    });

    test('ADS notice names count against the retained-byte budget', () async {
      final source = NtfsFixture(
        extraAttributes: [
          ntfsResidentAttribute(0x80, [1], name: 'notes-雪'),
        ],
      ).source();
      await expectLater(
        openNtfsArchive(source, maxMemberBytes: 1024, maxRetainedPathBytes: 16),
        throwsA(_code(ArchiveMessageCode.archiveLimit)),
      );
      expect(source.closeCount, 1);
    });

    test('failed attempts spend shared allocation budgets', () async {
      final fixture = NtfsFixture();
      fixture.bytes[fixture.indexOffset + 510] ^= 1;
      final budget = ArchiveNtfsTraversalBudget(maxClusters: 70);
      await expectLater(
        openNtfsArchive(
          fixture.source(),
          maxMemberBytes: 1024,
          traversalBudget: budget,
        ),
        throwsA(_code(ArchiveMessageCode.corrupt)),
      );
      expect(budget.clustersVisited, 42);
      expect(budget.extentsCreated, greaterThan(0));
      expect(budget.remainingClusters, 28);
      await expectLater(
        openNtfsArchive(
          NtfsFixture().source(),
          maxMemberBytes: 1024,
          traversalBudget: budget,
        ),
        throwsA(_code(ArchiveMessageCode.archiveLimit)),
      );
      expect(budget.clustersVisited, 42);
    });

    test('retained paths use UTF16 byte accounting', () async {
      final fixture = NtfsFixture(name: '😀.txt');
      final source = fixture.source();
      await expectLater(
        openNtfsArchive(source, maxMemberBytes: 1024, maxRetainedPathBytes: 11),
        throwsA(_code(ArchiveMessageCode.archiveLimit)),
      );
      final archive = await openNtfsArchive(
        fixture.source(),
        maxMemberBytes: 1024,
        maxRetainedPathBytes: 12,
      );
      expect(archive.members.single.name, '😀.txt');
      await archive.close();
    });

    test(
      '4096 UTF16 path units are admitted and longer paths refused',
      () async {
        final exact = _deepFixture(componentLength: 240);
        final archive = await _open(exact);
        expect(archive.members.last.name.length, 4096);
        expect(archive.members.last.isFile, isTrue);
        await archive.close();
        await _reject(
          _deepFixture(componentLength: 241),
          ArchiveMessageCode.archiveLimit,
        );
      },
    );

    test(
      'directory depth ceiling is checked before tree publication',
      () async {
        final source = _deepFixture(componentLength: 3).source();
        await expectLater(
          openNtfsArchive(source, maxMemberBytes: 1024, maxDepth: 15),
          throwsA(_code(ArchiveMessageCode.archiveLimit)),
        );
        expect(source.closeCount, 1);
      },
    );

    test('entry limit is charged for distinct hardlink paths', () async {
      final fixture = NtfsFixture();
      fixture.setFile(
        ntfsResidentAttribute(0x80, fixture.payload),
        links: 2,
        extraNames: [ntfsFileName('alias.txt')],
      );
      fixture.rootEntries.add(const NtfsFixtureEntry(24, 'alias.txt'));
      fixture.rebuildIndex();
      final source = fixture.source();
      await expectLater(
        openNtfsArchive(source, maxMemberBytes: 1024, maxEntries: 1),
        throwsA(_code(ArchiveMessageCode.archiveLimit)),
      );
      expect(source.closeCount, 1);
    });
  });

  group('NTFS malformed boot and FILE records', () {
    final corruptions = <String, void Function(NtfsFixture)>{
      'OEM signature': (f) {
        f.bytes[3] ^= 1;
      },
      'boot signature': (f) {
        f.bytes[511] = 0;
      },
      'reserved geometry': (f) {
        f.bytes[14] = 1;
        f.syncBackup();
      },
      'volume outside source': (f) {
        ntfsPut64(f.bytes, 40, 100000);
        f.syncBackup();
      },
      'backup boot mismatch': (f) {
        f.bytes[f.bytes.length - 512 + 3] ^= 1;
      },
      'MFT and mirror collide': (f) {
        ntfsPut64(f.bytes, 56, 4);
        f.syncBackup();
      },
      'FILE fixup mismatch': (f) {
        f.bytes[f.recordOffset(24) + 510] ^= 1;
      },
      'FILE update sequence count': (f) {
        ntfsPut16(f.bytes, f.recordOffset(24) + 6, 2);
      },
      'FILE number mismatch': (f) {
        f.mutateRecord(24, (b) {
          ntfsPut32(b, 44, 25);
        });
      },
      'FILE used bytes': (f) {
        f.mutateRecord(24, (b) {
          ntfsPut32(b, 24, 55);
        });
      },
      'FILE not in use': (f) {
        f.mutateRecord(24, (b) {
          ntfsPut16(b, 22, 0);
        });
      },
      'unallocated MFT record': (f) {
        f.setMftAllocated(24, false);
      },
      'zero attribute length': (f) {
        _attribute(f, 24, 0x80, (b, at) {
          ntfsPut32(b, at + 4, 0);
        });
      },
      'resident header overlap': (f) {
        _attribute(f, 24, 0x80, (b, at) {
          ntfsPut16(b, at + 20, 8);
        });
      },
      'resident value overflow': (f) {
        _attribute(f, 24, 0x80, (b, at) {
          ntfsPut32(b, at + 16, 0xffffffff);
        });
      },
      'attribute instance reuse': (f) {
        _attribute(f, 24, 0x80, (b, at) {
          ntfsPut16(b, at + 14, 0);
        });
      },
      'MFT mirror mismatch': (f) {
        f.bytes[40 * 1024 + 100] ^= 1;
      },
    };
    for (final entry in corruptions.entries) {
      test(entry.key, () async {
        final fixture = NtfsFixture();
        entry.value(fixture);
        await _reject(fixture);
      });
    }

    final unsupported = <String, void Function(NtfsFixture)>{
      'sector geometry': (f) {
        ntfsPut16(f.bytes, 11, 768);
        f.syncBackup();
      },
      'oversized cluster geometry': (f) {
        ntfsPut16(f.bytes, 11, 4096);
        f.bytes[13] = 128;
        f.syncBackup();
      },
      'inexact volume integer': (f) {
        ntfsPut32(f.bytes, 44, 0xffffffff);
        f.syncBackup();
      },
      'dirty volume': (f) {
        _attribute(f, 3, 0x70, (b, at) {
          ntfsPut16(b, at + ntfsGet16(b, at + 20) + 10, 1);
        });
      },
      'unknown NTFS version': (f) {
        _attribute(f, 3, 0x70, (b, at) {
          b[at + ntfsGet16(b, at + 20) + 8] = 4;
        });
      },
      'extension FILE record': (f) {
        f.mutateRecord(24, (b) {
          ntfsPut32(b, 32, 1);
        });
      },
      'compressed attribute': (f) {
        _attribute(f, 24, 0x80, (b, at) {
          ntfsPut16(b, at + 12, 1);
        });
      },
      'encrypted attribute': (f) {
        _attribute(f, 24, 0x80, (b, at) {
          ntfsPut16(b, at + 12, 0x4000);
        });
      },
      'unknown attribute flags': (f) {
        _attribute(f, 24, 0x80, (b, at) {
          ntfsPut16(b, at + 12, 0x2000);
        });
      },
      'public view-index record': (f) {
        f.mutateRecord(24, (b) {
          ntfsPut16(b, 22, 13);
        });
      },
    };
    for (final entry in unsupported.entries) {
      test(entry.key, () async {
        final fixture = NtfsFixture();
        entry.value(fixture);
        await _reject(fixture, ArchiveMessageCode.unsupported);
      });
    }
    test('attribute list is refused before namespace publication', () async {
      await _reject(
        NtfsFixture(extraAttributes: [ntfsResidentAttribute(0x20, [])]),
        ArchiveMessageCode.unsupported,
      );
    });
    test('reparse-point attribute is refused', () async {
      await _reject(
        NtfsFixture(
          extraAttributes: [
            ntfsResidentAttribute(0xc0, [1, 2, 3]),
          ],
        ),
        ArchiveMessageCode.unsupported,
      );
    });
  });

  group('NTFS namespace and directory index consistency', () {
    test('stale reference sequence', () async {
      final f = NtfsFixture();
      f.rootEntries[f.rootEntries.length - 1] = const NtfsFixtureEntry(
        24,
        'hello.txt',
        sequence: 8,
      );
      f.rebuildIndex();
      await _reject(f);
    });
    test('filename parent sequence', () async {
      final f = NtfsFixture();
      f.rootEntries[f.rootEntries.length - 1] = const NtfsFixtureEntry(
        24,
        'hello.txt',
        parentSequence: 6,
      );
      f.rebuildIndex();
      await _reject(f);
    });
    test('directory key lacks a matching FILE_NAME', () async {
      final f = NtfsFixture();
      f.rootEntries[f.rootEntries.length - 1] = const NtfsFixtureEntry(
        24,
        'different.txt',
      );
      f.rebuildIndex();
      await _reject(f);
    });
    test('duplicate index filename', () async {
      final f = NtfsFixture();
      f.rootEntries.add(const NtfsFixtureEntry(24, 'hello.txt'));
      f.rebuildIndex();
      await _reject(f);
    });
    test('directory type disagreement', () async {
      final f = NtfsFixture();
      f.rootEntries[f.rootEntries.length - 1] = const NtfsFixtureEntry(
        24,
        'hello.txt',
        directory: true,
      );
      f.rebuildIndex();
      await _reject(f);
    });
    for (final name in [
      '../escape',
      'a/b',
      'a\\b',
      'a:b',
      '..',
      'nul\u0000name',
    ]) {
      test('unsafe component ${jsonEncode(name)}', () async {
        await _reject(NtfsFixture(name: name), ArchiveMessageCode.unsupported);
      });
    }
    test('ordinary dot name collides with the root self-entry', () async {
      // The root already indexes its legitimate dot entry. A second dot is
      // refused as a duplicate index key before the ordinary FILE name is read.
      await _reject(NtfsFixture(name: '.'), ArchiveMessageCode.corrupt);
    });
    test('invalid UTF16 surrogate is rejected', () async {
      final f = NtfsFixture();
      _attribute(f, 24, 0x30, (b, at) {
        ntfsPut16(b, at + ntfsGet16(b, at + 20) + 66, 0xd800);
      });
      await _reject(f);
    });
    test('INDX update-sequence mismatch', () async {
      final f = NtfsFixture();
      f.bytes[f.indexOffset + 1022] ^= 1;
      await _reject(f);
    });
    test('INDX own VCN mismatch', () async {
      final f = NtfsFixture();
      f.mutateIndex((b) {
        ntfsPut64(b, 16, 1);
      });
      await _reject(f);
    });
    test('INDX entry leaves used region', () async {
      final f = NtfsFixture();
      f.mutateIndex((b) {
        ntfsPut16(b, 64 + 8, 65528);
      });
      await _reject(f);
    });
    test('INDX entry offset overlaps fixups', () async {
      final f = NtfsFixture();
      f.mutateIndex((b) {
        ntfsPut32(b, 24, 16);
      });
      await _reject(f);
    });
    test('live index child marked unallocated', () async {
      final f = NtfsFixture();
      _attribute(f, 5, 0xb0, (b, at) {
        b[at + ntfsGet16(b, at + 20)] = 0;
      }, name: r'$I30');
      await _reject(f);
    });
    test('bitmap set bit outside rooted index tree', () async {
      final f = NtfsFixture();
      _attribute(f, 5, 0xb0, (b, at) {
        b[at + ntfsGet16(b, at + 20)] = 3;
      }, name: r'$I30');
      await _reject(f);
    });
    test('index child outside allocation', () async {
      final f = NtfsFixture();
      _attribute(f, 5, 0x90, (b, at) {
        ntfsPut64(b, at + ntfsGet16(b, at + 20) + 48, 4);
      }, name: r'$I30');
      await _reject(f);
    });
    test('INDX child cycle is rejected', () async {
      final fixture = NtfsFixture();
      fixture.mutateIndex((b) {
        b.fillRange(64, b.length, 0);
        b[36] = 1;
        ntfsPut32(b, 28, 64);
        ntfsPut16(b, 72, 24);
        ntfsPut16(b, 76, 3);
        ntfsPut64(b, 80, 0);
      });
      await _reject(fixture);
    });

    test(
      'system child and public file allocation aliases are rejected',
      () async {
        await _reject(_systemAlias());
      },
    );

    test(
      'clearing the system-directory kind cannot hide its allocations',
      () async {
        final fixture = _systemAlias();
        fixture.mutateRecord(11, (b) {
          ntfsPut16(b, 22, 1);
        });
        final at = fixture.rootEntries.indexWhere((e) => e.number == 11);
        fixture.rootEntries[at] = const NtfsFixtureEntry(
          11,
          r'$Extend',
          sequence: 11,
        );
        fixture.rebuildIndex();
        await _reject(fixture);
      },
    );

    test(
      'omitting the required system-directory edge cannot hide its allocations',
      () async {
        final fixture = _systemAlias();
        fixture.rootEntries.removeWhere((e) => e.number == 11);
        fixture.rebuildIndex();
        await _reject(fixture);
      },
    );

    test('links cannot exceed the FILE hardlink count', () async {
      final f = NtfsFixture();
      f.setFile(
        ntfsResidentAttribute(0x80, f.payload),
        extraNames: [ntfsFileName('alias.txt')],
      );
      f.rootEntries.add(const NtfsFixtureEntry(24, 'alias.txt'));
      f.rebuildIndex();
      await _reject(f);
    });
  });

  group('NTFS runlist and allocation refusal', () {
    final mutations = <String, void Function(NtfsFixture)>{
      'zero run length': (f) {
        _attribute(f, 24, 0x80, (b, at) {
          b[at + ntfsGet16(b, at + 32) + 1] = 0;
        });
      },
      'oversized run widths': (f) {
        _attribute(f, 24, 0x80, (b, at) {
          b[at + ntfsGet16(b, at + 32)] = 0x91;
        });
      },
      'run outside volume': (f) {
        _attribute(f, 24, 0x80, (b, at) {
          b[at + ntfsGet16(b, at + 32) + 2] = 126;
        });
      },
      'unterminated runlist': (f) {
        _attribute(f, 24, 0x80, (b, at) {
          b[at + ntfsGet16(b, at + 32) + 3] = 0x11;
        });
      },
      'highest VCN disagreement': (f) {
        _attribute(f, 24, 0x80, (b, at) {
          ntfsPut64(b, at + 24, 2);
        });
      },
      'initialized length overflow': (f) {
        _attribute(f, 24, 0x80, (b, at) {
          ntfsPut64(b, at + 56, 2049);
        });
      },
      'allocation marked free': (f) {
        f.allocate(60, allocated: false);
        f.syncBitmap();
      },
    };
    for (final entry in mutations.entries) {
      test(entry.key, () async {
        final f = _mapped();
        entry.value(f);
        await _reject(f);
      });
    }
    test('mapping-pair lowest VCN extension is refused', () async {
      final f = _mapped();
      _attribute(f, 24, 0x80, (b, at) {
        ntfsPut64(b, at + 16, 1);
      });
      await _reject(f, ArchiveMessageCode.unsupported);
    });
    test('unflagged sparse data is refused', () async {
      await _reject(_mapped(runs: const [NtfsFixtureRun(2, null)]));
    });
    test('sparse physical allocation must match its runs', () async {
      final f = _mapped(flags: 0x8000, compressionUnit: 4);
      _attribute(f, 24, 0x80, (b, at) {
        ntfsPut64(b, at + 64, 1024);
      });
      await _reject(f);
    });
    test('file allocation cannot alias the MFT', () async {
      await _reject(_mapped(runs: const [NtfsFixtureRun(2, 4)]));
    });
    test('file allocation cannot alias boot metadata', () async {
      await _reject(_mapped(runs: const [NtfsFixtureRun(2, 0)]));
    });
    test(
      'two different files cannot claim the same physical clusters',
      () async {
        final f = _mapped();
        f.addFile(
          25,
          'second.bin',
          ntfsMappedAttribute(
            0x80,
            size: 2048,
            runs: const [NtfsFixtureRun(2, 60)],
          ),
        );
        await _reject(f);
      },
    );
    test('metadata-only ADS allocations also reject crosslinks', () async {
      final f = _mapped();
      f.setFile(
        ntfsMappedAttribute(
          0x80,
          size: 2048,
          runs: const [NtfsFixtureRun(2, 60)],
        ),
        extraAttributes: [
          ntfsMappedAttribute(
            0x80,
            name: 'private',
            size: 1024,
            runs: const [NtfsFixtureRun(1, 60)],
          ),
        ],
      );
      await _reject(f);
    });
    test('overlapping runs within one file are rejected', () async {
      await _reject(
        _mapped(
          size: 3072,
          runs: const [NtfsFixtureRun(2, 60), NtfsFixtureRun(1, 61)],
        ),
      );
    });
  });
}

NtfsFixture _deepFixture({required int componentLength}) {
  final name = 'd' * componentLength, fileName = 'f' * 240;
  final fixture = NtfsFixture(name: fileName);
  fixture.extendMftTo36Records();
  fixture.rootEntries.removeWhere((entry) => entry.number == 24);
  final ids = [
    for (var i = 16; i <= 32; i++)
      if (i != 24) i,
  ];
  for (var i = 0; i < ids.length; i++) {
    final child = i + 1 < ids.length ? ids[i + 1] : 24;
    fixture.addDirectory(
      ids[i],
      name,
      indexLcn: 60 + i * 4,
      parent: i == 0 ? 5 : ids[i - 1],
      parentSequence: i == 0 ? 5 : 7,
      entries: [
        NtfsFixtureEntry(
          child,
          child == 24 ? fileName : name,
          directory: child != 24,
          parent: ids[i],
          parentSequence: 7,
        ),
      ],
    );
  }
  _attribute(fixture, 24, 0x30, (b, at) {
    final value = at + ntfsGet16(b, at + 20);
    ntfsPut32(b, value, ids.last);
    ntfsPut16(b, value + 6, 7);
  });
  fixture.rebuildIndex();
  return fixture;
}

NtfsFixture _systemAlias() {
  final data = ntfsMappedAttribute(
    0x80,
    size: 4,
    runs: const [NtfsFixtureRun(1, 100)],
  );
  final fixture = _mapped(size: 4, runs: const [NtfsFixtureRun(1, 100)]);
  fixture.addFile(25, 'system-metadata.bin', data);
  fixture.rootEntries.removeWhere(
    (entry) => entry.number == 25 || entry.number == 11,
  );
  _attribute(fixture, 25, 0x30, (b, at) {
    final value = at + ntfsGet16(b, at + 20);
    ntfsPut32(b, value, 11);
    ntfsPut16(b, value + 6, 11);
  });
  fixture.addDirectory(
    11,
    r'$Extend',
    indexLcn: 80,
    sequence: 11,
    entries: const [
      NtfsFixtureEntry(
        25,
        'system-metadata.bin',
        parent: 11,
        parentSequence: 11,
      ),
    ],
  );
  return fixture;
}

class _ReusingSource implements koni.ByteSource {
  _ReusingSource(this.bytes);
  final Uint8List bytes;
  final buffer = Uint8List(65536 + 7);
  @override
  int get length => bytes.length;
  @override
  String get name => 'borrowed.ntfs';
  @override
  Future<Uint8List> read(int offset, int count) async {
    buffer.fillRange(0, buffer.length, 0xee);
    buffer.setRange(7, 7 + count, bytes, offset);
    return Uint8List.sublistView(buffer, 7, 7 + count);
  }

  @override
  Future<void> close() async {}
}
