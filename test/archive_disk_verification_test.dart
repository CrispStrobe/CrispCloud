import 'dart:typed_data';

import 'package:crisp_cloud/services/archive_disk_verification.dart';
import 'package:crisp_cloud/services/archive_dmg_writer.dart';
import 'package:crisp_cloud/services/archive_hfs_writer.dart';
import 'package:crisp_cloud/services/archive_iso_writer.dart';
import 'package:crisp_cloud/services/archive_output_spool.dart';
import 'package:crisp_cloud/services/archive_output_spool_memory.dart'
    as memory;
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:crisp_cloud/services/archive_write_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/dmg_fixture.dart';
import 'support/hfs_fixture.dart';

ArchiveWriteEntry _file(
  String path,
  List<int> bytes, {
  DateTime? modified,
  int? mode,
}) => ArchiveWriteEntry(
  path: path,
  isDirectory: false,
  size: bytes.length,
  modified: modified,
  mode: mode,
  readChunks: () => Stream.value(bytes),
);

Future<ArchiveOutputSpool> _create(
  String format,
  List<ArchiveWriteEntry> entries,
) async {
  final spool = await memory.createArchiveOutputSpool(
    maxBytes: 32 * 1024 * 1024,
  );
  try {
    switch (format) {
      case 'iso':
        await writeIsoArchive(entries, sink: spool.write);
      case 'hfsx':
        await writeHfsArchive(entries, sink: spool.write);
      case 'dmg':
        await writeDmgArchive(entries, sink: spool.write);
    }
    await spool.finish();
    return spool;
  } catch (_) {
    await spool.dispose();
    rethrow;
  }
}

void main() {
  for (final format in ['iso', 'hfsx', 'dmg']) {
    test(
      '$format validates exact payload, implicit directories, modes and second timestamps',
      () async {
        final entries = [
          _file(
            'café/one.txt',
            [1, 2, 3],
            modified: DateTime.utc(2024, 1, 2, 3, 4, 5, 678),
            mode: 0x1ed,
          ),
          _file('empty', []),
          ArchiveWriteEntry(
            path: 'empty-dir',
            isDirectory: true,
            size: 0,
            mode: 0x41c0,
            modified: DateTime.utc(2024, 1, 2),
          ),
        ];
        final spool = await _create(format, entries);
        addTearDown(spool.dispose);
        await verifyCreatedDiskArchive(spool, entries, format: format);
        expect(await spool.openRead().first, isNotEmpty);
      },
    );

    test('$format rejects wrong bytes with the same length', () async {
      final spool = await _create(format, [
        _file('one', [1, 2, 3]),
      ]);
      addTearDown(spool.dispose);
      await expectLater(
        verifyCreatedDiskArchive(spool, [
          _file('one', [1, 2, 4]),
        ], format: format),
        throwsA(isA<ArchiveViewException>()),
      );
    });

    test('$format rejects added/missing members and wrong metadata', () async {
      final date = DateTime.utc(2024);
      final spool = await _create(format, [
        _file('one', [1], modified: date, mode: 0x81a4),
      ]);
      addTearDown(spool.dispose);
      for (final expected in [
        <ArchiveWriteEntry>[],
        [
          _file('one', [1]),
          _file('extra', []),
        ],
        [
          _file('one', [1], modified: DateTime.utc(2025)),
        ],
        [
          _file('one', [1], mode: 0x81ed),
        ],
      ]) {
        await expectLater(
          verifyCreatedDiskArchive(spool, expected, format: format),
          throwsA(isA<ArchiveViewException>()),
        );
      }
    });

    test('$format verifies an empty data volume', () async {
      final spool = await _create(format, []);
      addTearDown(spool.dispose);
      await verifyCreatedDiskArchive(spool, [], format: format);
    });
  }

  test('HFS preserves second timestamps before the Unix epoch', () async {
    final entries = [
      _file('old', [1], modified: DateTime.utc(1969, 12, 31, 23, 59, 59, 987)),
    ];
    final spool = await _create('hfsx', entries);
    addTearDown(spool.dispose);
    await verifyCreatedDiskArchive(spool, entries, format: 'hfsx');
  });

  test('a valid raw CRC cannot hide a corrupt empty DMG filesystem', () async {
    final hfs = HfsFixture();
    hfs.bytes[HfsFixture.catalogOffset + 8] = 0;
    final dmg = DmgFixture(hfs.bytes);
    final spool = await memory.createArchiveOutputSpool(maxBytes: 1024 * 1024);
    addTearDown(spool.dispose);
    await spool.write(dmg.bytes);
    await spool.finish();
    await expectLater(
      verifyCreatedDiskArchive(spool, [], format: 'dmg'),
      throwsA(isA<ArchiveViewException>()),
    );
  });

  test(
    'verification cancellation leaves the caller-owned spool available',
    () async {
      final spool = await _create('hfsx', [_file('one', Uint8List(1024))]);
      addTearDown(spool.dispose);
      await expectLater(
        verifyCreatedDiskArchive(
          spool,
          [],
          format: 'hfsx',
          isCancelled: () => true,
        ),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(await spool.openRead().first, isNotEmpty);
    },
  );
}
