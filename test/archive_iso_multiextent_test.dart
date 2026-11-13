import 'dart:async';
import 'dart:typed_data';

import 'package:crisp_cloud/services/archive_iso_reader.dart';
import 'package:crisp_cloud/services/archive_iso_writer.dart';
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import 'support/archive_iso_fixtures.dart';

Future<ViewerArchive> _open(Uint8List bytes) =>
    openIsoArchive(koni.MemoryByteSource(bytes), maxMemberBytes: 1024 * 1024);

Future<List<int>> _stream(ViewerArchive archive, {int chunkSize = 3}) async => [
  await for (final chunk in archive.openMember(
    archive.members.single,
    chunkSize: chunkSize,
  ))
    ...chunk,
];

void main() {
  group('ISO multi-extent regular files', () {
    test('lists one logical file and reads exact separated sections', () async {
      final fixture = IsoMultiExtentFixture();
      final source = _Source(fixture.bytes);
      final archive = await openIsoArchive(source, maxMemberBytes: 1024);
      addTearDown(archive.close);
      expect(archive.members.single.name, 'HELLO.TXT');
      expect(archive.members.single.size, fixture.expected.length);
      expect(archive.members.single.isFile, isTrue);
      expect(
        source.reads.every((r) => r.$1 < fixture.dataOffsets.first),
        isTrue,
      );
      expect(
        await archive.readMember(archive.members.single),
        fixture.expected,
      );
      source.reads.clear();
      expect(await _stream(archive), fixture.expected);
      expect(source.reads.every((r) => r.$2 <= 3), isTrue);
      expect(source.reads.any((r) => r.$1 == fixture.dataOffsets.last), isTrue);
    });

    test(
      'continues a record chain across zero directory-sector padding',
      () async {
        final fixture = IsoMultiExtentFixture(separateRecordSectors: true);
        expect(fixture.recordOffsets.last % 2048, 0);
        final archive = await _open(fixture.bytes);
        addTearDown(archive.close);
        expect(await _stream(archive), fixture.expected);
      },
    );

    test('keeps record order when physical extents are reversed', () async {
      final fixture = IsoMultiExtentFixture(
        contents: [
          [1, 2, 3],
          [4, 5, 6],
        ],
      );
      isoBoth32(
        fixture.bytes,
        fixture.recordOffsets.first + 2,
        fixture.dataOffsets.last ~/ 2048,
      );
      isoBoth32(
        fixture.bytes,
        fixture.recordOffsets.last + 2,
        fixture.dataOffsets.first ~/ 2048,
      );
      final archive = await _open(fixture.bytes);
      addTearDown(archive.close);
      expect(await _stream(archive, chunkSize: 2), [4, 5, 6, 1, 2, 3]);
    });

    test(
      'retains repeated physical sections as repeated logical bytes',
      () async {
        final fixture = IsoMultiExtentFixture(
          contents: [
            [1, 2, 3],
            [4, 5, 6],
          ],
        );
        isoBoth32(
          fixture.bytes,
          fixture.recordOffsets.last + 2,
          fixture.dataOffsets.first ~/ 2048,
        );
        final archive = await _open(fixture.bytes);
        addTearDown(archive.close);
        expect(await _stream(archive, chunkSize: 2), [1, 2, 3, 1, 2, 3]);
      },
    );

    test('supports empty sections without reading unrelated bytes', () async {
      final fixture = IsoMultiExtentFixture(
        contents: [
          [],
          [7, 8],
          [],
        ],
      );
      final archive = await _open(fixture.bytes);
      addTearDown(archive.close);
      expect(await archive.readMember(archive.members.single), [7, 8]);
      expect(await _stream(archive), [7, 8]);
    });

    test('supports Joliet names for one logical member', () async {
      final fixture = IsoMultiExtentFixture(joliet: true);
      final archive = await _open(fixture.bytes);
      addTearDown(archive.close);
      expect(archive.members.single.name, '複数.txt');
      expect(await _stream(archive), fixture.expected);
    });

    test('retains consistent Rock Ridge names and permissions', () async {
      final fixture = IsoMultiExtentFixture(rockRidgeName: 'héllo.txt');
      final archive = await _open(fixture.bytes);
      addTearDown(archive.close);
      expect(archive.members.single.name, 'héllo.txt');
      expect(archive.members.single.posixMode, 0x81a4);
      expect(await _stream(archive), fixture.expected);
    });

    test(
      'checks the total logical size against configured and read limits',
      () async {
        final fixture = IsoMultiExtentFixture();
        final source = _Source(fixture.bytes);
        final archive = await openIsoArchive(source, maxMemberBytes: 10);
        addTearDown(archive.close);
        source.reads.clear();
        await expectLater(
          archive.readMember(archive.members.single, maxBytes: 100),
          throwsA(isA<ArchiveViewException>()),
        );
        await expectLater(
          archive
              .openMember(archive.members.single, maxBytes: 100)
              .drain<void>(),
          throwsA(isA<ArchiveViewException>()),
        );
        await expectLater(
          archive.readMember(archive.members.single, maxBytes: 5),
          throwsA(isA<ArchiveViewException>()),
        );
        expect(source.reads, isEmpty);
      },
    );

    test(
      'retains sizes above 4 GiB without buffering image or payload',
      () async {
        final fixture = IsoMultiExtentFixture();
        const firstSize = 0xfffff800;
        const lastSize = 4096;
        const imageBytes = 6 * 1024 * 1024 * 1024;
        isoBoth32(fixture.bytes, 16 * 2048 + 80, imageBytes ~/ 2048);
        isoBoth32(fixture.bytes, fixture.recordOffsets.first + 10, firstSize);
        isoBoth32(fixture.bytes, fixture.recordOffsets.last + 10, lastSize);
        final source = _Source(fixture.bytes, virtualLength: imageBytes);
        final archive = await openIsoArchive(
          source,
          maxMemberBytes: imageBytes,
        );
        addTearDown(archive.close);
        final member = archive.members.single;
        expect(member.size, firstSize + lastSize);
        expect(member.size, greaterThan(0xffffffff));
        expect(source.reads.every((r) => r.$2 <= 2048), isTrue);
        source.reads.clear();
        await expectLater(
          archive.readMember(member),
          throwsA(isA<ArchiveViewException>()),
        );
        expect(source.reads, isEmpty);
        final chunks = await archive
            .openMember(member, maxBytes: imageBytes, chunkSize: 128)
            .take(2)
            .toList();
        expect(chunks.map((chunk) => chunk.length), [128, 128]);
        expect(source.reads, [
          (fixture.dataOffsets.first, 128),
          (fixture.dataOffsets.first + 128, 128),
        ]);
      },
    );

    test(
      'closing revokes a pending multi-section stream and closes once',
      () async {
        final fixture = IsoMultiExtentFixture();
        final source = _Source(fixture.bytes);
        final archive = await openIsoArchive(source, maxMemberBytes: 1024);
        final iterator = StreamIterator(
          archive.openMember(archive.members.single, chunkSize: 2),
        );
        expect(await iterator.moveNext(), isTrue);
        await archive.close();
        await archive.close();
        await expectLater(
          iterator.moveNext(),
          throwsA(isA<ArchiveViewException>()),
        );
        await iterator.cancel();
        expect(source.closes, 1);
      },
    );

    test('rejects truncated later payload reads', () async {
      final fixture = IsoMultiExtentFixture();
      final source = _Source(fixture.bytes, shortAt: fixture.dataOffsets.last);
      final archive = await openIsoArchive(source, maxMemberBytes: 1024);
      addTearDown(archive.close);
      await expectLater(
        archive.readMember(archive.members.single),
        throwsA(isA<ArchiveViewException>()),
      );
      await expectLater(_stream(archive), throwsA(isA<ArchiveViewException>()));
    });

    test('remains outside the ISO rewrite profile', () async {
      final fixture = IsoMultiExtentFixture();
      final archive = await _open(fixture.bytes);
      addTearDown(archive.close);
      final inspection = await inspectIsoRewrite(fixture.bytes, archive);
      expect(inspection.reason, contains('multi-extents'));
    });
  });

  group('invalid or unsupported ISO section chains', () {
    final mutations = <String, void Function(IsoMultiExtentFixture)>{
      'different identifier': (f) => f.bytes[f.recordOffsets.last + 33] = 0x58,
      'different version with same displayed path': (f) =>
          f.bytes[f.recordOffsets.last +
                  33 +
                  f.bytes[f.recordOffsets.last + 32] -
                  1] =
              0x32,
      'inconsistent hidden flag': (f) =>
          f.bytes[f.recordOffsets.last + 25] |= 1,
      'different recording time': (f) => f.bytes[f.recordOffsets.last + 22]++,
      'unfinished chain': (f) => f.bytes[f.recordOffsets.last + 25] |= 0x80,
      'unmarked duplicate records': (f) =>
          f.bytes[f.recordOffsets.first + 25] = 0,
      'directory continuation': (f) => f.bytes[f.recordOffsets.first + 25] |= 2,
      'directory as final section': (f) =>
          f.bytes[f.recordOffsets.last + 25] |= 2,
      'extended attributes': (f) => f.bytes[f.recordOffsets.first + 1] = 1,
      'record structure': (f) => f.bytes[f.recordOffsets.first + 25] |= 8,
      'protected sections': (f) => f.bytes[f.recordOffsets.first + 25] |= 16,
      'interleaved sections': (f) => f.bytes[f.recordOffsets.first + 26] = 1,
      'another volume': (f) => isoBoth16(f.bytes, f.recordOffsets.last + 28, 2),
      'extent beyond volume': (f) => isoBoth32(
        f.bytes,
        f.recordOffsets.last + 2,
        f.bytes.length ~/ 2048 + 1,
      ),
      'disagreeing byte orders': (f) => f.bytes[f.recordOffsets.last + 14] = 1,
    };
    for (final entry in mutations.entries) {
      test('rejects ${entry.key}', () async {
        final fixture = IsoMultiExtentFixture();
        entry.value(fixture);
        final source = _Source(fixture.bytes);
        await expectLater(
          openIsoArchive(source, maxMemberBytes: 1024),
          throwsA(isA<ArchiveViewException>()),
        );
        expect(source.closes, 1);
      });
    }

    test('rejects inconsistent Rock Ridge names or permissions', () async {
      for (final changeName in [true, false]) {
        final fixture = IsoMultiExtentFixture(rockRidgeName: 'hello.txt');
        final last = fixture.recordOffsets.last;
        final nameLength = fixture.bytes[last + 32];
        final system = last + 33 + nameLength + (nameLength.isEven ? 1 : 0);
        if (changeName) {
          fixture.bytes[system + 5] = 0x58;
        } else {
          final px = system + fixture.bytes[system + 2];
          isoBoth32(fixture.bytes, px + 4, 0x81ed);
        }
        await expectLater(
          _open(fixture.bytes),
          throwsA(isA<ArchiveViewException>()),
        );
      }
    });

    test('rejects special-file section chains', () async {
      await expectLater(
        _open(IsoMultiExtentFixture(symbolicLink: true).bytes),
        throwsA(isA<ArchiveViewException>()),
      );
    });

    test(
      'bounds section metadata independently from logical file count',
      () async {
        for (final perFile in [true, false]) {
          final fixture = IsoMultiExtentFixture(
            contents: [
              [1],
              [2],
              [3],
            ],
          );
          final source = _Source(fixture.bytes);
          await expectLater(
            openIsoArchive(
              source,
              maxMemberBytes: 1024,
              maxEntries: 1,
              maxFileSections: perFile ? 2 : 1024,
              maxSectionRecords: perFile ? 100000 : 2,
            ),
            throwsA(isA<ArchiveViewException>()),
          );
          expect(source.closes, 1);
        }
      },
    );

    test(
      'refuses logical totals above 8 GiB even for repeated extents',
      () async {
        final fixture = IsoMultiExtentFixture(
          contents: [
            [1],
            [2],
            [3],
          ],
        );
        const imageBytes = 6 * 1024 * 1024 * 1024;
        isoBoth32(fixture.bytes, 16 * 2048 + 80, imageBytes ~/ 2048);
        for (final record in fixture.recordOffsets) {
          isoBoth32(fixture.bytes, record + 10, 0xffffffff);
        }
        final source = _Source(fixture.bytes, virtualLength: imageBytes);
        await expectLater(
          openIsoArchive(source, maxMemberBytes: imageBytes),
          throwsA(
            isA<ArchiveViewException>().having(
              (e) => e.message,
              'message',
              contains('8 GiB'),
            ),
          ),
        );
        expect(source.closes, 1);
      },
    );

    test(
      'rejects nonpositive metadata limits and releases the source',
      () async {
        for (final perFile in [true, false]) {
          final source = _Source(IsoMultiExtentFixture().bytes);
          await expectLater(
            openIsoArchive(
              source,
              maxMemberBytes: 1024,
              maxFileSections: perFile ? 0 : 1024,
              maxSectionRecords: perFile ? 100000 : 0,
            ),
            throwsArgumentError,
          );
          expect(source.closes, 1);
          expect(source.reads, isEmpty);
        }
      },
    );
  });
}

class _Source implements koni.ByteSource {
  _Source(this.bytes, {this.virtualLength, this.shortAt});
  final Uint8List bytes;
  final int? virtualLength;
  final int? shortAt;
  final reads = <(int, int)>[];
  int closes = 0;
  @override
  int get length => virtualLength ?? bytes.length;
  @override
  String get name => 'sections.iso';
  @override
  Future<Uint8List> read(int offset, int length) async {
    reads.add((offset, length));
    if (shortAt != null && offset >= shortAt! && length > 0) length--;
    if (offset + length <= bytes.length) {
      return Uint8List.sublistView(bytes, offset, offset + length);
    }
    final result = Uint8List(length);
    if (offset < bytes.length) {
      result.setRange(0, bytes.length - offset, bytes, offset);
    }
    return result;
  }

  @override
  Future<void> close() async => closes++;
}
