import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/services/archive_iso_reader.dart';
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import 'support/archive_iso_fixtures.dart';

Future<ViewerArchive> _open(Uint8List bytes, {int maxMemberBytes = 1024}) =>
    openIsoArchive(
      koni.MemoryByteSource(bytes),
      maxMemberBytes: maxMemberBytes,
    );

void main() {
  group('ISO 9660 reader', () {
    test(
      'reads an independently generated libarchive ISO with a long name',
      () async {
        final archive = await _open(independentLibarchiveIso());
        addTearDown(archive.close);
        final content = <String, String>{};
        for (final member in archive.members.where((member) => member.isFile)) {
          content[member.name] = utf8.decode(await archive.readMember(member));
        }
        expect(content, {
          'hello.txt': 'libarchive ISO fixture\n',
          'folder/日本語.txt': 'Unicode names\n',
          'long-${'a' * 170}.txt': 'Continuation name\n',
        });
      },
    );

    test('allows a zero-length file without an allocated extent', () async {
      final fixture = IsoFixture();
      isoBoth32(fixture.bytes, fixture.fileRecordOffset + 2, 0);
      isoBoth32(fixture.bytes, fixture.fileRecordOffset + 10, 0);
      final archive = await _open(fixture.bytes);
      addTearDown(archive.close);
      expect(await archive.readMember(archive.members.first), isEmpty);
    });

    test(
      'lists nested and empty directories and reads exact file bytes',
      () async {
        final archive = await _open(IsoFixture().bytes);
        addTearDown(archive.close);
        expect(archive.formatName, 'iso');
        expect(archive.members.map((m) => m.name), [
          'HELLO.TXT',
          'DOCS',
          'EMPTY',
          'DOCS/NOTE.TXT',
        ]);
        expect(archive.members.where((m) => !m.isFile).map((m) => m.name), [
          'DOCS',
          'EMPTY',
        ]);
        expect(
          utf8.decode(await archive.readMember(archive.members[0])),
          'hello iso',
        );
        expect(
          utf8.decode(await archive.readMember(archive.members[3])),
          'nested iso',
        );
        expect(
          archive.members[0].modified,
          DateTime.utc(2026, 11, 12, 9, 15, 30),
        );
      },
    );

    test(
      'prefers Unicode Joliet names when no Rock Ridge is present',
      () async {
        final archive = await _open(IsoFixture(jolietName: '挨拶.txt').bytes);
        addTearDown(archive.close);
        expect(archive.members.map((m) => m.name), [
          '挨拶.txt',
          '文書',
          '文書/日本語.txt',
        ]);
        expect(
          utf8.decode(await archive.readMember(archive.members.last)),
          'nested iso',
        );
      },
    );

    test(
      'reads Rock Ridge UTF-8 names and POSIX modes before Joliet',
      () async {
        final archive = await _open(
          IsoFixture(rockRidgeName: 'héllo.txt', jolietName: 'other.txt').bytes,
        );
        addTearDown(archive.close);
        expect(archive.members.first.name, 'héllo.txt');
        expect(archive.members.first.posixMode, 0x81a4);
        expect(
          utf8.decode(await archive.readMember(archive.members.first)),
          'hello iso',
        );
      },
    );

    test('follows bounded Rock Ridge continuation metadata', () async {
      final archive = await _open(
        IsoFixture(
          rockRidgeName: 'continued.txt',
          rockRidgeContinuation: true,
        ).bytes,
      );
      addTearDown(archive.close);
      expect(archive.members.first.name, 'continued.txt');
    });

    test('marks symbolic links special and refuses their contents', () async {
      final archive = await _open(IsoFixture(symbolicLink: true).bytes);
      addTearDown(archive.close);
      expect(archive.members.first.isSpecial, isTrue);
      expect(archive.members.first.isFile, isFalse);
      await expectLater(
        archive.readMember(archive.members.first),
        throwsA(isA<ArchiveViewException>()),
      );
    });

    test(
      'metadata open never reads file data and closes its source once',
      () async {
        final source = _TrackingSource(IsoFixture().bytes);
        final archive = await openIsoArchive(source, maxMemberBytes: 1024);
        const contentOffset = IsoFixture.fileSector * IsoFixture.sectorSize;
        expect(
          source.reads.any(
            (range) =>
                range.$1 <= contentOffset &&
                range.$1 + range.$2 > contentOffset,
          ),
          isFalse,
        );
        expect(
          await archive.readMember(archive.members.first),
          utf8.encode('hello iso'),
        );
        expect(source.reads.last, (contentOffset, 9));
        await archive.close();
        await archive.close();
        expect(source.closes, 1);
        await expectLater(
          archive.readMember(archive.members.first),
          throwsA(isA<ArchiveViewException>()),
        );
      },
    );

    test(
      'enforces both configured and per-read caps before reading data',
      () async {
        final source = _TrackingSource(IsoFixture().bytes);
        final archive = await openIsoArchive(source, maxMemberBytes: 8);
        addTearDown(archive.close);
        final count = source.reads.length;
        await expectLater(
          archive.readMember(archive.members.first, maxBytes: 100),
          throwsA(isA<ArchiveViewException>()),
        );
        await expectLater(
          archive.readMember(archive.members.first, maxBytes: 2),
          throwsA(isA<ArchiveViewException>()),
        );
        expect(source.reads.length, count);
      },
    );

    test('refuses directories as file data', () async {
      final archive = await _open(IsoFixture().bytes);
      addTearDown(archive.close);
      await expectLater(
        archive.readMember(archive.members[1]),
        throwsA(isA<ArchiveViewException>()),
      );
    });

    test('cleans up failed opens, including short source reads', () async {
      final source = _TrackingSource(IsoFixture().bytes, returnShortRead: true);
      await expectLater(
        openIsoArchive(source, maxMemberBytes: 1024),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(source.closes, 1);
    });

    test(
      'bounds metadata bytes and entry count independently from file sizes',
      () async {
        for (final testCase in ['bytes', 'entries']) {
          final source = _TrackingSource(IsoFixture().bytes);
          await expectLater(
            openIsoArchive(
              source,
              maxMemberBytes: 1024,
              maxDirectoryBytes: testCase == 'bytes' ? 2048 : 32 * 1024 * 1024,
              maxEntries: testCase == 'entries' ? 1 : 100000,
            ),
            throwsA(isA<ArchiveViewException>()),
          );
          expect(source.closes, 1);
        }
      },
    );
  });

  group('invalid and unsupported ISO images', () {
    test(
      'enforces the directory depth budget before reading descendants',
      () async {
        final fixture = IsoFixture();
        const nested = IsoFixture.childSector * 2048 + 68;
        fixture.bytes[nested + 25] = 2;
        isoBoth32(fixture.bytes, nested + 2, IsoFixture.emptySector);
        isoBoth32(fixture.bytes, nested + 10, 2048);
        await expectLater(
          openIsoArchive(
            koni.MemoryByteSource(fixture.bytes),
            maxMemberBytes: 1024,
            maxDepth: 1,
          ),
          throwsA(
            isA<ArchiveViewException>().having(
              (error) => error.message,
              'message',
              contains('nesting limit'),
            ),
          ),
        );
      },
    );

    final mutations = <String, void Function(IsoFixture)>{
      'bad descriptor signature': (f) => f.bytes[16 * 2048 + 1] = 0,
      'missing terminator': (f) => f.bytes[17 * 2048] = 0,
      'different endian volume lengths': (f) => f.bytes[16 * 2048 + 84] = 1,
      'different endian member extent': (f) =>
          f.bytes[f.fileRecordOffset + 6] = 1,
      'unsupported logical block size': (f) =>
          isoBoth16(f.bytes, 16 * 2048 + 128, 1024),
      'multi-volume image': (f) => isoBoth16(f.bytes, 16 * 2048 + 120, 2),
      'file outside volume': (f) =>
          isoBoth32(f.bytes, f.fileRecordOffset + 2, 1000),
      'oversized declared member length': (f) =>
          isoBoth32(f.bytes, f.fileRecordOffset + 10, 0xffffffff),
      'member in another volume': (f) =>
          isoBoth16(f.bytes, f.fileRecordOffset + 28, 2),
      'multi-extent file': (f) => f.bytes[f.fileRecordOffset + 25] = 0x80,
      'interleaved file': (f) => f.bytes[f.fileRecordOffset + 26] = 1,
      'associated resource file': (f) => f.bytes[f.fileRecordOffset + 25] = 4,
      'invalid name length': (f) => f.bytes[f.fileRecordOffset + 32] = 255,
      'short directory record': (f) => f.bytes[f.fileRecordOffset] = 20,
      'invalid timestamp': (f) => f.bytes[f.fileRecordOffset + 19] = 13,
      'directory cycle': (f) => isoBoth32(
        f.bytes,
        f.directoryRecordOffset + 2,
        IsoFixture.rootSector,
      ),
      'nonsector directory length': (f) =>
          isoBoth32(f.bytes, f.directoryRecordOffset + 10, 100),
      'missing self record': (f) =>
          f.bytes[IsoFixture.rootSector * 2048 + 33] = 3,
      'padding contains hidden records': (f) =>
          f.bytes[IsoFixture.rootSector * 2048 + 1000] = 1,
    };
    for (final mutation in mutations.entries) {
      test(mutation.key, () async {
        final fixture = IsoFixture();
        mutation.value(fixture);
        final source = _TrackingSource(fixture.bytes);
        await expectLater(
          openIsoArchive(source, maxMemberBytes: 1024),
          throwsA(isA<ArchiveViewException>()),
        );
        expect(source.closes, 1);
      });
    }

    for (final name in ['../ESCAPE;1', '/ABS.TXT;1', r'C:\DRIVE;1', '..;1']) {
      test('refuses unsafe ISO name $name', () async {
        await expectLater(
          _open(IsoFixture(fileName: name).bytes),
          throwsA(isA<ArchiveViewException>()),
        );
      });
    }

    for (final name in [
      '../escape',
      '/absolute',
      r'C:\drive',
      '..',
      'a\u0000b',
    ]) {
      test('refuses unsafe Rock Ridge name $name', () async {
        await expectLater(
          _open(IsoFixture(rockRidgeName: name).bytes),
          throwsA(isA<ArchiveViewException>()),
        );
      });
    }

    test('refuses traversal in Joliet', () async {
      await expectLater(
        _open(IsoFixture(jolietName: '../escape').bytes),
        throwsA(isA<ArchiveViewException>()),
      );
    });

    test(
      'rejects truncated media before accepting a partial listing',
      () async {
        final bytes = IsoFixture().bytes;
        for (final length in [0, 32768, bytes.length - 1]) {
          await expectLater(
            _open(Uint8List.sublistView(bytes, 0, length)),
            throwsA(isA<ArchiveViewException>()),
          );
        }
      },
    );

    test('rejects out of range Rock Ridge continuation pointers', () async {
      final fixture = IsoFixture(
        rockRidgeName: 'continued',
        rockRidgeContinuation: true,
      );
      final system =
          fixture.fileRecordOffset +
          33 +
          fixture.fileName.length +
          (fixture.fileName.length.isEven ? 1 : 0);
      isoBoth32(fixture.bytes, system + 4, 0xffffffff);
      await expectLater(
        _open(fixture.bytes),
        throwsA(isA<ArchiveViewException>()),
      );
    });

    test('rejects cyclic Rock Ridge continuation pointers', () async {
      final fixture = IsoFixture(
        rockRidgeName: 'continued',
        rockRidgeContinuation: true,
      );
      final system =
          fixture.fileRecordOffset +
          33 +
          fixture.fileName.length +
          (fixture.fileName.length.isEven ? 1 : 0);
      isoBoth32(fixture.bytes, system + 20, 28);
      fixture.bytes.setAll(
        IsoFixture.continuationSector * 2048,
        fixture.bytes.sublist(system, system + 28),
      );
      await expectLater(
        _open(fixture.bytes),
        throwsA(isA<ArchiveViewException>()),
      );
    });

    test('rejects a Rock Ridge name with a missing continuation', () async {
      final fixture = IsoFixture(rockRidgeName: 'unfinished');
      final system =
          fixture.fileRecordOffset +
          33 +
          fixture.fileName.length +
          (fixture.fileName.length.isEven ? 1 : 0);
      fixture.bytes[system + 4] = 1;
      await expectLater(
        _open(fixture.bytes),
        throwsA(isA<ArchiveViewException>()),
      );
    });

    test(
      'rejects names that collapse to the same ISO versionless path',
      () async {
        final fixture = IsoFixture();
        final directory = fixture.directoryRecordOffset;
        // Turn DOCS into a second regular HELLO.TXT record by copying the
        // first file record over it; clear its old tail and following entries.
        final first = fixture.bytes.sublist(
          fixture.fileRecordOffset,
          directory,
        );
        fixture.bytes.fillRange(
          directory,
          (IsoFixture.rootSector + 1) * 2048,
          0,
        );
        fixture.bytes.setAll(directory, first);
        await expectLater(
          _open(fixture.bytes),
          throwsA(isA<ArchiveViewException>()),
        );
      },
    );
  });
}

class _TrackingSource implements koni.ByteSource {
  _TrackingSource(this.bytes, {this.returnShortRead = false});
  final Uint8List bytes;
  final bool returnShortRead;
  final reads = <(int, int)>[];
  int closes = 0;
  @override
  int get length => bytes.length;
  @override
  String get name => 'fixture.iso';
  @override
  Future<Uint8List> read(int offset, int length) async {
    reads.add((offset, length));
    return Uint8List.sublistView(
      bytes,
      offset,
      offset + length - (returnShortRead ? 1 : 0),
    );
  }

  @override
  Future<void> close() async => closes++;
}
