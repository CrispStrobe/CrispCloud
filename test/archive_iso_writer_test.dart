import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/services/archive_iso_reader.dart';
import 'package:crisp_cloud/services/archive_iso_writer.dart';
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:crisp_cloud/services/archive_write_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import 'support/archive_iso_fixtures.dart';

final _date = DateTime.utc(2026, 11, 12, 9, 15, 30);

ArchiveWriteEntry _file(
  String path, [
  List<int> bytes = const [0, 1, 2, 255],
  int mode = 0x81a4,
]) => ArchiveWriteEntry(
  path: path,
  isDirectory: false,
  size: bytes.length,
  modified: _date,
  mode: mode,
  readChunks: () => Stream.value(bytes),
);

ArchiveWriteEntry _directory(String path, {int mode = 0x41ed}) =>
    ArchiveWriteEntry(
      path: path,
      isDirectory: true,
      size: 0,
      modified: _date,
      mode: mode,
    );

Future<Uint8List> _write(
  List<ArchiveWriteEntry> entries, {
  ArchiveRewriteInspection? source,
}) => collectArchiveWrite(
  (sink) => writeIsoArchive(entries, sink: sink, source: source),
);

Future<ViewerArchive> _open(Uint8List bytes) => openIsoArchive(
  koni.MemoryByteSource(bytes),
  maxMemberBytes: 2 * 1024 * 1024 * 1024,
);

List<ArchiveWriteEntry> _rewriteEntries(
  ViewerArchive archive,
  ArchiveRewriteInspection inspection,
) => [
  for (final member in archive.members)
    ArchiveWriteEntry(
      path: member.name,
      isDirectory: !member.isFile,
      size: member.size,
      modified: member.modified,
      mode: member.posixMode,
      attributes: inspection.attributes[member.name] ?? {},
      readChunks: () =>
          archive.openMember(member, maxBytes: 2 * 1024 * 1024 * 1024),
    ),
];

int _little32(Uint8List data, int offset) =>
    ByteData.sublistView(data).getUint32(offset, Endian.little);

void main() {
  group('streaming data ISO writer', () {
    test('creates an empty interoperable data volume', () async {
      final bytes = await _write([]);
      expect(bytes.length % 2048, 0);
      expect(
        ascii.decode(bytes.sublist(16 * 2048 + 1, 16 * 2048 + 6)),
        'CD001',
      );
      expect(bytes[17 * 2048], 2);
      expect(bytes[18 * 2048], 255);
      final archive = await _open(bytes);
      addTearDown(archive.close);
      expect(archive.members, isEmpty);
      expect((await inspectIsoRewrite(bytes, archive)).supported, isTrue);
    });

    test('retains exact Unicode, non-BMP and long Rock Ridge names', () async {
      final long = 'long-${'é' * 190}.txt';
      final entries = [
        _directory('empty'),
        _directory('文書', mode: 0x41c0),
        _file('文書/日本語.txt', utf8.encode('日本語の本文'), 0x8180),
        _file(long),
        _file('emoji-🌍.txt'),
        _file('zero.bin', []),
      ];
      final bytes = await _write(entries);
      final archive = await _open(bytes);
      addTearDown(archive.close);
      expect(
        archive.members.map((member) => member.name),
        unorderedEquals(entries.map((entry) => entry.path)),
      );
      for (final expected in entries) {
        final actual = archive.members.singleWhere(
          (member) => member.name == expected.path,
        );
        expect(actual.isFile, !expected.isDirectory);
        expect(actual.posixMode, expected.mode);
        expect(actual.modified, _date);
        if (actual.isFile) {
          expect(await archive.readMember(actual), await expected.read());
        }
      }
      final inspection = await inspectIsoRewrite(bytes, archive);
      expect(inspection.reason, isNull);
      final rewritten = await _write(
        _rewriteEntries(archive, inspection),
        source: inspection,
      );
      expect(rewritten, bytes);
    });

    test(
      'has a separately readable Joliet hierarchy with safe alternatives',
      () async {
        final long = 'l' * 180;
        final bytes = await _write([
          _file('日本語.txt'),
          _file(long),
          _file('🌍'),
          _file('world'),
        ]);
        final primaryRoot = _little32(bytes, 16 * 2048 + 158) * 2048;
        // Hide SP from this browsing pass to select only the alternate tree.
        final alternate = Uint8List.fromList(bytes)..[primaryRoot + 34] = 0;
        final reader = await _open(alternate);
        addTearDown(reader.close);
        expect(
          reader.members.map((member) => member.name),
          contains('日本語.txt'),
        );
        expect(reader.members.map((member) => member.name).toSet().length, 4);
        expect(
          reader.members.every((member) => member.name.length <= 64),
          isTrue,
        );
        for (final member in reader.members) {
          expect(await reader.readMember(member), [0, 1, 2, 255]);
        }
      },
    );

    test(
      'creates implicit directories and multiple directory sectors',
      () async {
        final entries = [
          for (var i = 0; i < 300; i++) _file('parent/sub/file-$i.txt'),
        ];
        final bytes = await _write(entries);
        final reader = await _open(bytes);
        addTearDown(reader.close);
        expect(reader.members.length, 302);
        expect(
          reader.members
              .where((member) => !member.isFile)
              .map((member) => member.name),
          ['parent', 'parent/sub'],
        );
        expect((await inspectIsoRewrite(bytes, reader)).reason, isNull);
      },
    );

    test('is deterministic and separates colliding alternate names', () async {
      final entries = [
        _file('readme'),
        _file('README'),
        _file('réadme'),
        _file('rèadme'),
      ];
      final first = await _write(entries);
      expect(await _write(entries.reversed.toList()), first);
      final reader = await _open(first);
      addTearDown(reader.close);
      expect(
        reader.members.map((member) => member.name),
        unorderedEquals(entries.map((entry) => entry.path)),
      );
      expect((await inspectIsoRewrite(first, reader)).reason, isNull);
    });

    test(
      'streams an 80 MiB payload and reads it back without a full buffer',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'iso_writer_large_',
        );
        addTearDown(() => directory.delete(recursive: true));
        final file = File('${directory.path}/large.iso');
        final output = await file.open(mode: FileMode.write);
        const length = 80 * 1024 * 1024;
        var sourceChunks = 0;
        var maxSinkChunk = 0;
        final piece = Uint8List(64 * 1024)..fillRange(0, 64 * 1024, 0x5a);
        await writeIsoArchive(
          [
            ArchiveWriteEntry(
              path: 'large.bin',
              isDirectory: false,
              size: length,
              readChunks: () async* {
                for (var at = 0; at < length; at += piece.length) {
                  sourceChunks++;
                  yield piece;
                }
              },
            ),
          ],
          sink: (bytes) async {
            if (bytes.length > maxSinkChunk) maxSinkChunk = bytes.length;
            await output.writeFrom(bytes);
          },
        );
        await output.close();
        expect(sourceChunks, length ~/ piece.length);
        expect(maxSinkChunk, lessThanOrEqualTo(256 * 1024));
        final source = await _FileSource.open(file);
        final reader = await openIsoArchive(source, maxMemberBytes: length);
        addTearDown(reader.close);
        final member = reader.members.single;
        expect(member.size, length);
        expect(source.maxRequest, lessThan(length));
        var received = 0;
        await for (final bytes in reader.openMember(member, maxBytes: length)) {
          expect(bytes.length, lessThanOrEqualTo(256 * 1024));
          expect(bytes.every((byte) => byte == 0x5a), isTrue);
          received += bytes.length;
        }
        expect(received, length);
        expect(source.maxRequest, lessThanOrEqualTo(256 * 1024));
        await expectLater(
          reader.readMember(member),
          throwsA(isA<ArchiveViewException>()),
        );
      },
    );

    test(
      'preflights oversized layouts before opening a stream or sink',
      () async {
        var read = false;
        var emitted = false;
        final entry = ArchiveWriteEntry(
          path: 'large.bin',
          isDirectory: false,
          size: 100000,
          readChunks: () {
            read = true;
            return const Stream.empty();
          },
        );
        await expectLater(
          writeIsoArchive(
            [entry],
            maxOutputBytes: 60000,
            sink: (_) async {
              emitted = true;
            },
          ),
          throwsA(isA<ArchiveViewException>()),
        );
        expect(read, isFalse);
        expect(emitted, isFalse);
      },
    );

    for (final path in [
      '../escape',
      '/absolute',
      'drive:c',
      'a\\b',
      'a//b',
      'a/./b',
      'bad\u0000name',
    ]) {
      test('rejects unsafe path $path', () async {
        await expectLater(
          _write([_file(path)]),
          throwsA(isA<ArchiveViewException>()),
        );
      });
    }

    test('rejects duplicate, prefix, special and deep entries', () async {
      for (final entries in [
        [_file('same'), _file('same')],
        [_file('parent'), _file('parent/child')],
        [_file('link', [], 0xa1ff)],
        [_file('${List.filled(8, 'd').join('/')}/file')],
      ]) {
        await expectLater(
          _write(entries),
          throwsA(isA<ArchiveViewException>()),
        );
      }
    });

    test(
      'rejects out-of-range dates and unsupported source inspections',
      () async {
        final entry = ArchiveWriteEntry(
          path: 'file',
          isDirectory: false,
          size: 0,
          modified: DateTime.utc(2200),
          readChunks: () => const Stream.empty(),
        );
        await expectLater(
          _write([entry]),
          throwsA(isA<ArchiveViewException>()),
        );
        await expectLater(
          _write(
            [],
            source: ArchiveRewriteInspection(reason: 'bootable image'),
          ),
          throwsA(isA<ArchiveViewException>()),
        );
        await expectLater(
          _write([], source: ArchiveRewriteInspection()),
          throwsA(isA<ArchiveViewException>()),
        );
      },
    );

    test('rejects short and growing captured file streams', () async {
      for (final content in [
        [1],
        [1, 2, 3],
      ]) {
        final entry = ArchiveWriteEntry(
          path: 'file',
          isDirectory: false,
          size: 2,
          readChunks: () => Stream.value(content),
        );
        await expectLater(
          _write([entry]),
          throwsA(isA<ArchiveViewException>()),
        );
      }
    });

    test(
      'cancellation stops before output and between payload chunks',
      () async {
        var emitted = 0;
        await expectLater(
          writeIsoArchive(
            [_file('file')],
            isCancelled: () => true,
            sink: (_) async {
              emitted++;
            },
          ),
          throwsA(isA<ArchiveViewException>()),
        );
        expect(emitted, 0);
        var cancelled = false;
        final entry = ArchiveWriteEntry(
          path: 'large',
          isDirectory: false,
          size: 512 * 1024,
          readChunks: () async* {
            yield Uint8List(256 * 1024);
            yield Uint8List(256 * 1024);
          },
        );
        await expectLater(
          writeIsoArchive(
            [entry],
            isCancelled: () => cancelled,
            sink: (bytes) async {
              if (bytes.length == 256 * 1024) cancelled = true;
            },
          ),
          throwsA(isA<ArchiveViewException>()),
        );
      },
    );
  });

  group('ISO rewrite inspection', () {
    test('preserves an independent root ER continuation after rejecting vendor metadata', () async {
      final original = independentLibarchiveIso();
      final vendor = await _open(original);
      addTearDown(vendor.close);
      expect(
        (await inspectIsoRewrite(original, vendor)).reason,
        contains('unmodeled data'),
      );
      // The reference tool also writes an unreferenced INFO provenance block.
      // Removing that one block creates a separate supported-profile test
      // fixture; production inspection must refuse the unchanged original.
      expect(ascii.decode(original.sublist(19 * 2048, 19 * 2048 + 5)), 'INFO ');
      original.fillRange(19 * 2048, 20 * 2048, 0);
      final reader = await _open(original);
      addTearDown(reader.close);
      final inspection = await inspectIsoRewrite(original, reader);
      expect(inspection.reason, isNull);
      final result = await _write(
        _rewriteEntries(reader, inspection),
        source: inspection,
      );
      final opened = await _open(result);
      addTearDown(opened.close);
      expect(
        opened.members.map((member) => member.name),
        unorderedEquals(reader.members.map((member) => member.name)),
      );
      for (final member in opened.members.where((member) => member.isFile)) {
        final old = reader.members.singleWhere(
          (entry) => entry.name == member.name,
        );
        expect(member.posixMode, old.posixMode);
        expect(member.modified, old.modified);
        expect(await opened.readMember(member), await reader.readMember(old));
      }
      expect((await inspectIsoRewrite(result, opened)).reason, isNull);
    });

    test('keeps multiple long-name continuations sector-contained beside their directory', () async {
      final names = [for (var i = 0; i < 8; i++) 'name-$i-${'é' * 400}.txt'];
      final bytes = await _write([for (final name in names) _file(name)]);
      final root = _little32(bytes, 16 * 2048 + 158) * 2048;
      final rootSize = _little32(bytes, 16 * 2048 + 166);
      final jolietRoot = _little32(bytes, 17 * 2048 + 158) * 2048;
      var continuations = 0;
      for (var at = root; at < root + rootSize;) {
        if (bytes[at] == 0) {
          at = (at ~/ 2048 + 1) * 2048;
          continue;
        }
        final end = at + bytes[at];
        final nameLength = bytes[at + 32];
        var field = at + 33 + nameLength + (nameLength.isEven ? 1 : 0);
        while (field + 4 <= end && bytes[field] != 0) {
          final tag = ascii.decode(bytes.sublist(field, field + 2));
          // Older independent readers treat ST as ending global RR support.
          expect(tag, isNot('ST'));
          if (tag == 'CE') {
            final block = _little32(bytes, field + 4) * 2048;
            final offset = _little32(bytes, field + 12);
            final length = _little32(bytes, field + 20);
            expect(block, greaterThanOrEqualTo(root + rootSize));
            expect(block + offset + length, lessThanOrEqualTo(jolietRoot));
            expect(offset + length, lessThanOrEqualTo(2048));
            continuations++;
          }
          field += bytes[field + 2];
        }
        at = end;
      }
      expect(continuations, names.length);
      final reader = await _open(bytes);
      addTearDown(reader.close);
      expect(
        reader.members.map((member) => member.name),
        unorderedEquals(names),
      );
      expect((await inspectIsoRewrite(bytes, reader)).reason, isNull);
    });

    test(
      'accepts an independent ordinary ISO and retains its timezone and labels',
      () async {
        final fixture = IsoFixture();
        final label = ascii.encode('EXAMPLE_VOLUME'.padRight(32));
        fixture.bytes.setAll(16 * 2048 + 40, label);
        final reader = await _open(fixture.bytes);
        addTearDown(reader.close);
        final inspection = await inspectIsoRewrite(fixture.bytes, reader);
        expect(inspection.reason, isNull);
        final bytes = await _write(
          _rewriteEntries(reader, inspection),
          source: inspection,
        );
        expect(bytes.sublist(16 * 2048 + 40, 16 * 2048 + 72), label);
        final result = await _open(bytes);
        addTearDown(result.close);
        for (final member in result.members) {
          expect(member.modified, _date);
          if (member.isFile) {
            expect(
              await result.readMember(member),
              await reader.readMember(
                reader.members.singleWhere((old) => old.name == member.name),
              ),
            );
          }
        }
        expect((await inspectIsoRewrite(bytes, result)).reason, isNull);
      },
    );

    test(
      'preserves Rock Ridge ownership across serialized inspection metadata',
      () async {
        final fixture = IsoFixture(
          rockRidgeName: 'héllo.txt',
          rockRidgeContinuation: true,
        );
        final reader = await _open(fixture.bytes);
        addTearDown(reader.close);
        final inspection = await inspectIsoRewrite(fixture.bytes, reader);
        expect(inspection.reason, isNull);
        expect(inspection.attributes['héllo.txt']?['iso.uid'], 1000);
        final encoded = jsonDecode(
          jsonEncode({
            'container': inspection.container,
            'attributes': inspection.attributes,
          }),
        ) as Map<String, dynamic>;
        final restored = ArchiveRewriteInspection(
          container: Map<String, Object?>.from(encoded['container'] as Map),
          attributes: {
            for (final item in (encoded['attributes'] as Map).entries)
              item.key as String: Map<String, Object?>.from(item.value as Map),
          },
        );
        final bytes = await _write(
          _rewriteEntries(reader, restored),
          source: restored,
        );
        final result = await _open(bytes);
        addTearDown(result.close);
        final checked = await inspectIsoRewrite(bytes, result);
        expect(checked.reason, isNull);
        expect(checked.attributes['héllo.txt']?['iso.uid'], 1000);
        expect(checked.attributes['héllo.txt']?['iso.gid'], 1000);
      },
    );

    test('supports add, replace, remove and rename while retaining source volume metadata', () async {
      final original = await _write([
        _file('keep.txt'),
        _file('remove.txt'),
        _file('old.txt'),
        _directory('empty'),
      ]);
      final reader = await _open(original);
      addTearDown(reader.close);
      final inspection = await inspectIsoRewrite(original, reader);
      final entries = _rewriteEntries(reader, inspection)
          .where(
            (entry) => entry.path != 'remove.txt' && entry.path != 'old.txt',
          )
          .toList();
      final old = reader.members.singleWhere(
        (entry) => entry.name == 'old.txt',
      );
      entries.add(
        ArchiveWriteEntry(
          path: 'renamed.txt',
          isDirectory: false,
          size: old.size,
          modified: old.modified,
          mode: old.posixMode,
          attributes: inspection.attributes[old.name]!,
          readChunks: () => reader.openMember(old),
        ),
      );
      entries.add(_file('new/file.txt', utf8.encode('new data')));
      final bytes = await _write(entries, source: inspection);
      final result = await _open(bytes);
      addTearDown(result.close);
      expect(
        result.members.map((member) => member.name),
        unorderedEquals([
          'keep.txt',
          'empty',
          'renamed.txt',
          'new',
          'new/file.txt',
        ]),
      );
      expect((await inspectIsoRewrite(bytes, result)).reason, isNull);
      final alternate = Uint8List.fromList(bytes);
      final root = _little32(alternate, 16 * 2048 + 158) * 2048;
      alternate[root + 34] = 0;
      final joliet = await _open(alternate);
      addTearDown(joliet.close);
      expect(
        joliet.members.map((member) => member.name),
        contains('renamed.txt'),
      );
      expect(
        joliet.members.map((member) => member.name),
        isNot(contains('old.txt')),
      );
    });

    for (final mutation in <String, void Function(Uint8List)>{
      'hybrid System Area': (bytes) => bytes[510] = 0x55,
      'boot descriptor': (bytes) => bytes[17 * 2048] = 0,
      'application-use data': (bytes) => bytes[16 * 2048 + 883] = 1,
      'unmodeled directory extension': (bytes) {
        final root = _little32(bytes, 16 * 2048 + 158) * 2048;
        bytes[root + 41] = 0x5a;
        bytes[root + 42] = 0x5a;
      },
      'path table divergence': (bytes) {
        final path = _little32(bytes, 16 * 2048 + 140) * 2048;
        bytes[path + 6] = 2;
      },
    }.entries) {
      test('refuses ${mutation.key}', () async {
        final bytes = await _write([_file('file')]);
        final reader = await _open(bytes);
        addTearDown(reader.close);
        mutation.value(bytes);
        expect((await inspectIsoRewrite(bytes, reader)).supported, isFalse);
      });
    }

    test(
      'refuses appended sessions or UDF data outside the selected tree',
      () async {
        final bytes = await _write([_file('file')]);
        final reader = await _open(bytes);
        addTearDown(reader.close);
        final appended = Uint8List(bytes.length + 2048)
          ..setAll(0, bytes)
          ..setAll(bytes.length + 1, ascii.encode('NSR02'));
        expect((await inspectIsoRewrite(appended, reader)).supported, isFalse);
      },
    );

    test(
      'refuses unrepresentable links and diverging alternate trees',
      () async {
        final fixture = IsoFixture(symbolicLink: true);
        final reader = await _open(fixture.bytes);
        addTearDown(reader.close);
        expect(
          (await inspectIsoRewrite(fixture.bytes, reader)).supported,
          isFalse,
        );
        final different = IsoFixture(
          rockRidgeName: 'hello.txt',
          jolietName: 'different.txt',
        );
        final other = await _open(different.bytes);
        addTearDown(other.close);
        // This fixture's primary hierarchy also contains an EMPTY directory
        // omitted from Joliet; preservation must account for that difference.
        expect(
          (await inspectIsoRewrite(different.bytes, other)).supported,
          isFalse,
        );
      },
    );

    test('refuses a browsing handle for a different hierarchy', () async {
      final first = await _write([_file('first')]);
      final second = await _write([_file('second')]);
      final reader = await _open(first);
      addTearDown(reader.close);
      expect((await inspectIsoRewrite(second, reader)).supported, isFalse);
    });
  });
}

class _FileSource implements koni.ByteSource {
  _FileSource(this.file, this.length);
  static Future<_FileSource> open(File path) async =>
      _FileSource(await path.open(), await path.length());
  final RandomAccessFile file;
  @override
  final int length;
  @override
  String? get name => 'large.iso';
  int maxRequest = 0;
  @override
  Future<Uint8List> read(int offset, int length) async {
    if (length > maxRequest) maxRequest = length;
    await file.setPosition(offset);
    return file.read(length);
  }

  @override
  Future<void> close() async {
    await file.close();
  }
}
