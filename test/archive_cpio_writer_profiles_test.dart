import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/services/archive_package_writers.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/archive_write_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/archive_package_writer_fixtures.dart';

const _profiles = {
  ArchiveCpioFormat.odc: ('070707', 'reference-odc.cpio'),
  ArchiveCpioFormat.binaryLittleEndian: (
    'binary-le',
    'reference-binary-le.cpio',
  ),
  ArchiveCpioFormat.binaryBigEndian: ('binary-be', 'reference-binary-be.cpio'),
};

Future<Uint8List> _write(
  ArchiveCpioFormat format,
  List<ArchiveWriteEntry> entries, {
  ArchiveRewriteInspection? source,
  int limit = 256 * 1024 * 1024,
  bool Function()? isCancelled,
}) => collectArchiveWrite(
  (sink) => writePackageArchive(
    'cpio',
    entries,
    sink: sink,
    source: source,
    cpioFormat: format,
    maxOutputBytes: limit,
    isCancelled: isCancelled,
  ),
  maxBytes: limit,
);

Future<PackageRewriteFixture> _open(Uint8List bytes) async {
  final fixture = await PackageRewriteFixture.open(bytes, 'cpio');
  addTearDown(fixture.close);
  return fixture;
}

ArchiveWriteEntry _change(
  ArchiveWriteEntry entry, {
  String? path,
  List<int>? bytes,
}) => ArchiveWriteEntry(
  path: path ?? entry.path,
  isDirectory: entry.isDirectory,
  size: bytes?.length ?? entry.size,
  mode: entry.mode,
  modified: entry.modified,
  attributes: entry.attributes,
  readChunks: bytes == null ? entry.openRead : () => Stream.value(bytes),
);

// Original, small specification-shaped records for mutation boundaries. Valid
// interoperability is checked separately using native-produced saved fixtures
// and fresh-output libarchive readback, not this fixture encoder alone.
Uint8List _fixture(
  ArchiveCpioFormat profile,
  List<({String name, List<int> bytes, List<int> fields})> records, {
  List<int>? trailer,
  int tail = 0,
}) {
  final output = BytesBuilder();
  final odc = profile == ArchiveCpioFormat.odc;
  final endian = profile == ArchiveCpioFormat.binaryLittleEndian
      ? Endian.little
      : Endian.big;
  for (final record in [
    ...records,
    (
      name: 'TRAILER!!!',
      bytes: <int>[],
      fields: trailer ?? [7, 13, 0, 3, 5, 1, 0, 123456789, 0, 0],
    ),
  ]) {
    final name = [...utf8.encode(record.name), 0];
    final fields = List<int>.of(record.fields)
      ..[8] = name.length
      ..[9] = record.bytes.length;
    if (odc) {
      const widths = [6, 6, 6, 6, 6, 6, 6, 11, 6, 11];
      output.add(ascii.encode('070707'));
      for (var i = 0; i < 10; i++) {
        output.add(
          ascii.encode(fields[i].toRadixString(8).padLeft(widths[i], '0')),
        );
      }
    } else {
      final words = [
        0x71c7,
        ...fields.take(7),
        fields[7] ~/ 65536,
        fields[7] % 65536,
        fields[8],
        fields[9] ~/ 65536,
        fields[9] % 65536,
      ];
      final header = ByteData(26);
      for (var i = 0; i < words.length; i++) {
        header.setUint16(i * 2, words[i], endian);
      }
      output.add(header.buffer.asUint8List());
    }
    output.add(name);
    if (!odc && output.length.isOdd) output.add([0]);
    output.add(record.bytes);
    if (!odc && output.length.isOdd) output.add([0]);
  }
  output.add(Uint8List(tail));
  return output.takeBytes();
}

List<int> _fields(int inode, {bool directory = false, int links = 1}) => [
  0x1234,
  inode,
  directory ? 0x41e8 : 0x81a0,
  123,
  456,
  links,
  0x2345,
  0x654321ab,
  0,
  0,
];

void main() {
  for (final profile in _profiles.entries) {
    final format = profile.key;
    final variant = profile.value.$1;
    group(variant, () {
      test(
        'creates streamed folders, Unicode names, odd files and empty files',
        () async {
          final date = DateTime.fromMillisecondsSinceEpoch(
            1700000000000,
            isUtc: true,
          );
          final payload = List<int>.generate(65536 + 333, (i) => i % 251);
          final bytes = await _write(format, [
            packageEntry(
              'docs',
              [],
              directory: true,
              mode: 0x1e8,
              modified: date,
              attributes: {'cpio.uid': 123, 'cpio.gid': 456},
            ),
            packageEntry(
              'docs/é日本語.txt',
              [1, 2, 3],
              mode: 0x1a0,
              modified: date,
              attributes: {'cpio.dev': 0x1234, 'cpio.rdev': 0x2345},
            ),
            packageEntry('empty', [], modified: date),
            packageEntry('payload.bin', payload, modified: date),
          ]);
          final opened = await _open(bytes);
          expect(opened.inspection.reason, isNull);
          expect(opened.inspection.container['cpio.variant'], variant);
          expect(opened.archive.members.map((m) => m.name), [
            'docs',
            'docs/é日本語.txt',
            'empty',
            'payload.bin',
          ]);
          expect(opened.archive.members.first.posixMode, 0x41e8);
          expect(opened.inspection.attributes['docs']!['cpio.uid'], 123);
          expect(opened.inspection.attributes['docs']!['cpio.gid'], 456);
          expect(
            opened.inspection.attributes['docs/é日本語.txt']!['cpio.dev'],
            0x1234,
          );
          expect(
            opened.inspection.attributes['docs/é日本語.txt']!['cpio.rdev'],
            0x2345,
          );
          expect(
            opened.archive.members.every((m) => m.modified == date),
            isTrue,
          );
          expect(await opened.archive.readMember(opened.archive.members[1]), [
            1,
            2,
            3,
          ]);
          expect(
            await opened.archive.readMember(opened.archive.members[2]),
            isEmpty,
          );
          expect(
            await opened.archive.readMember(opened.archive.members[3]),
            payload,
          );
          expect(await opened.repack(), bytes);
        },
      );

      test(
        'creates an empty archive in the requested physical profile',
        () async {
          final opened = await _open(await _write(format, []));
          expect(opened.inspection.reason, isNull);
          expect(opened.inspection.container['cpio.variant'], variant);
          expect(opened.archive.members, isEmpty);
        },
      );

      test('rewrites independent libarchive fixture byte for byte', () async {
        final bytes = File('test/fixtures/archives/${profile.value.$2}')
            .readAsBytesSync();
        final opened = await _open(bytes);
        expect(opened.inspection.reason, isNull);
        expect(opened.inspection.container['cpio.variant'], variant);
        expect(await opened.repack(), bytes);
      });

      test('source profile overrides creation choice through edits and repeated saves', () async {
        final bytes = File('test/fixtures/archives/${profile.value.$2}')
            .readAsBytesSync();
        final original = await _open(bytes);
        expect(original.inspection.reason, isNull);
        final selected = original.entries.indexWhere(
          (entry) => !entry.isDirectory,
        );
        final replacement = utf8.encode('Changed original content\n');
        final entries = [
          for (var i = 0; i < original.entries.length; i++)
            i == selected
                ? _change(
                    original.entries[i],
                    path: 'renamed.txt',
                    bytes: replacement,
                  )
                : original.entries[i],
          packageEntry('added', [4, 3, 2, 1]),
        ];
        final rebuilt = await _write(
          ArchiveCpioFormat.newc,
          entries,
          source: original.inspection,
        );
        final reopened = await _open(rebuilt);
        expect(reopened.inspection.reason, isNull);
        expect(reopened.inspection.container['cpio.variant'], variant);
        final member = reopened.archive.members.singleWhere(
          (m) => m.name == 'renamed.txt',
        );
        expect(await reopened.archive.readMember(member), replacement);
        final before =
            original.inspection.attributes[original.entries[selected].path]!;
        final after = reopened.inspection.attributes['renamed.txt']!;
        for (final key in [
          'cpio.ino',
          'cpio.dev',
          'cpio.rdev',
          'cpio.uid',
          'cpio.gid',
          'cpio.nlink',
        ]) {
          expect(after[key], before[key], reason: key);
        }
        expect(after['cpio.storedPath'], 'renamed.txt');
        expect(await reopened.repack(), rebuilt);
      });

      test('preserves root position, name spelling, trailer metadata and zero tail', () async {
        final input = _fixture(format, [
          (name: './first', bytes: [1, 2, 3], fields: _fields(1)),
          (
            name: './',
            bytes: <int>[],
            fields: _fields(2, directory: true, links: 3),
          ),
          (
            name: './docs/',
            bytes: <int>[],
            fields: _fields(3, directory: true, links: 2),
          ),
          (name: './docs/file', bytes: [4], fields: _fields(4)),
        ], tail: 511);
        final opened = await _open(input);
        expect(opened.inspection.reason, isNull);
        expect(opened.archive.members.map((m) => m.name), [
          'first',
          'docs',
          'docs/file',
        ]);
        expect(
          (opened.inspection.container['cpio.root'] as Map)['package.order'],
          1,
        );
        expect(opened.inspection.container['cpio.trailingPadding'], 511);
        expect(await opened.repack(), input);
      });

      test(
        'allocates a free inode when the original already uses the maximum',
        () async {
          final maximum = format == ArchiveCpioFormat.odc ? 0x3ffff : 0xffff;
          final opened = await _open(
            await _write(format, [
              packageEntry('original', [1], attributes: {'cpio.ino': maximum}),
            ]),
          );
          final rebuilt = await _write(format, [
            ...opened.entries,
            packageEntry('added', [2]),
          ], source: opened.inspection);
          final result = await _open(rebuilt);
          expect(result.inspection.reason, isNull);
          expect(
            result.inspection.attributes['original']!['cpio.ino'],
            maximum,
          );
          expect(result.inspection.attributes['added']!['cpio.ino'], 1);
        },
      );

      test(
        'rejects metadata overflow and incompatible fields before output',
        () async {
          final maximum = format == ArchiveCpioFormat.odc ? 0x3ffff : 0xffff;
          final bad = <ArchiveWriteEntry>[
            for (final key in [
              'cpio.uid',
              'cpio.gid',
              'cpio.dev',
              'cpio.rdev',
              'cpio.ino',
              'cpio.nlink',
            ])
              packageEntry('a', [1], attributes: {key: maximum + 1}),
            packageEntry('a', [1], attributes: {'cpio.variant': '070701'}),
            packageEntry('a', [1], attributes: {'cpio.devmajor': 1}),
            packageEntry('a', [1], attributes: {'cpio.uid': -1}),
            packageEntry('a', [1], attributes: {'cpio.nlink': 0}),
            packageEntry('a', [1], attributes: {'cpio.nlink': 2}),
            packageEntry('a', [1], attributes: {'cpio.storedPath': 42}),
            packageEntry('a', [1], mode: 0xa1ff),
            packageEntry('a', [1], modified: DateTime.utc(1969, 12, 31)),
            packageEntry('a', [
              1,
            ], modified: DateTime.fromMillisecondsSinceEpoch(1, isUtc: true)),
            packageEntry(
              'a',
              [1],
              modified: DateTime.fromMillisecondsSinceEpoch(
                (format == ArchiveCpioFormat.odc ? 0x200000000 : 0x100000000) *
                    1000,
                isUtc: true,
              ),
            ),
          ];
          for (final entry in bad) {
            var writes = 0;
            await expectLater(
              writePackageArchive(
                'cpio',
                [entry],
                cpioFormat: format,
                sink: (_) async {
                  writes++;
                },
              ),
              throwsA(isA<ArchiveViewException>()),
            );
            expect(
              writes,
              0,
              reason: '${entry.attributes}, ${entry.modified}, ${entry.mode}',
            );
          }
        },
      );

      test(
        'rejects duplicate device/inode identities on write and inspection',
        () async {
          await expectLater(
            _write(format, [
              packageEntry('a', [1], attributes: {'cpio.ino': 7}),
              packageEntry('b', [2], attributes: {'cpio.ino': 7}),
            ]),
            throwsA(isA<ArchiveViewException>()),
          );
          final opened = await _open(
            _fixture(format, [
              (name: 'a', bytes: [1], fields: _fields(7)),
              (name: 'b', bytes: [2], fields: _fields(7)),
            ]),
          );
          expect(opened.inspection.supported, isFalse);
        },
      );

      test(
        'leaves unsafe, linked and special metadata outside rewrite profile',
        () async {
          final records = [
            (name: '../outside', bytes: [1], fields: _fields(1)),
            (name: 'link', bytes: [1], fields: _fields(1, links: 2)),
            (name: 'special', bytes: [1], fields: _fields(1)..[2] = 0xa1ff),
            (name: './TRAILER!!!', bytes: [1], fields: _fields(1)),
          ];
          for (final record in records) {
            final opened = await _open(_fixture(format, [record]));
            expect(opened.inspection.supported, isFalse, reason: record.name);
          }
        },
      );

      test('preflights output limit and cancellation', () async {
        final bytes = await _write(format, [
          packageEntry('a', [1, 2, 3]),
        ]);
        await expectLater(
          _write(format, [
            packageEntry('a', [1, 2, 3]),
          ], limit: bytes.length - 1),
          throwsA(isA<ArchiveViewException>()),
        );
        expect(
          await _write(format, [
            packageEntry('a', [1, 2, 3]),
          ], limit: bytes.length),
          bytes,
        );
        await expectLater(
          _write(format, [], isCancelled: () => true),
          throwsA(isA<ArchiveViewException>()),
        );
      });

      test('detects a captured payload shrinking or growing', () async {
        for (final size in [0, 2]) {
          final entry = ArchiveWriteEntry(
            path: 'a',
            isDirectory: false,
            size: size,
            readChunks: () => Stream.value([1]),
          );
          await expectLater(
            _write(format, [entry]),
            throwsA(isA<ArchiveViewException>()),
          );
        }
      });

      test(
        'rejects a changed member profile or corrupt trailer during rewrite',
        () async {
          final original = await _open(
            await _write(format, [
              packageEntry('a', [1]),
            ]),
          );
          final badEntry = packageEntry(
            'a',
            [1],
            attributes: {
              ...original.entries.single.attributes,
              'cpio.variant': '070701',
            },
          );
          await expectLater(
            _write(format, [badEntry], source: original.inspection),
            throwsA(isA<ArchiveViewException>()),
          );
          for (final change in [
            {'cpio.trailerVariant': '070701'},
            {'cpio.trailingPadding': 65537},
            {
              'cpio.trailerFields': [0, 0, 0, 0, 0, 1, 0, 0, 11, 1],
            },
          ]) {
            final inspection = ArchiveRewriteInspection(
              container: {...original.inspection.container, ...change},
              attributes: original.inspection.attributes,
            );
            var writes = 0;
            await expectLater(
              writePackageArchive(
                'cpio',
                original.entries,
                source: inspection,
                sink: (_) async {
                  writes++;
                },
              ),
              throwsA(isA<ArchiveViewException>()),
            );
            expect(writes, 0);
          }
        },
      );
    });
  }

  test('newc remains default and refuses legacy device metadata', () async {
    final bytes = await _write(ArchiveCpioFormat.newc, [
      packageEntry('a', [1]),
    ]);
    expect(ascii.decode(bytes.sublist(0, 6)), '070701');
    await expectLater(
      _write(ArchiveCpioFormat.newc, [
        packageEntry('a', [1], attributes: {'cpio.dev': 1}),
      ]),
      throwsA(isA<ArchiveViewException>()),
    );
  });

  test('binary word ordering is high-word-first in both byte orders', () async {
    for (final format in [
      ArchiveCpioFormat.binaryLittleEndian,
      ArchiveCpioFormat.binaryBigEndian,
    ]) {
      final bytes = await _write(format, [
        packageEntry(
          'a',
          List.filled(0x10003, 7),
          modified: DateTime.fromMillisecondsSinceEpoch(
            0x12345678 * 1000,
            isUtc: true,
          ),
        ),
      ]);
      final little = format == ArchiveCpioFormat.binaryLittleEndian;
      expect(
        bytes.sublist(16, 20),
        little ? [0x34, 0x12, 0x78, 0x56] : [0x12, 0x34, 0x56, 0x78],
      );
      expect(bytes.sublist(22, 26), little ? [1, 0, 3, 0] : [0, 1, 0, 3]);
    }
  });

  test('odc high field values preserve all 18 and 33 bits', () async {
    final bytes = await _write(ArchiveCpioFormat.odc, [
      packageEntry(
        'a',
        [1],
        modified: DateTime.fromMillisecondsSinceEpoch(
          0x1ffffffff * 1000,
          isUtc: true,
        ),
        attributes: {
          'cpio.ino': 0x3ffff,
          'cpio.uid': 0x3ffff,
          'cpio.gid': 0x3ffff,
          'cpio.dev': 0x3ffff,
          'cpio.rdev': 0x3ffff,
        },
      ),
    ]);
    final opened = await _open(bytes);
    expect(opened.inspection.reason, isNull);
    expect(opened.inspection.attributes['a']!['cpio.uid'], 0x3ffff);
    expect(
      opened.archive.members.single.modified!.millisecondsSinceEpoch,
      0x1ffffffff * 1000,
    );
    expect(await opened.repack(), bytes);
  });
}
