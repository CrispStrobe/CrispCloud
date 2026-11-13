import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' as ar;
import 'package:crypto/crypto.dart';
import 'package:crisp_cloud/services/archive_dmg_reader.dart';
import 'package:crisp_cloud/services/archive_dmg_writer.dart';
import 'package:crisp_cloud/services/archive_hfs_reader.dart';
import 'package:crisp_cloud/services/archive_hfs_writer.dart';
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:crisp_cloud/services/archive_write_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import 'support/dmg_fixture.dart';

ArchiveWriteEntry _file(String path, List<int> bytes, {int? mode}) =>
    ArchiveWriteEntry(
      path: path,
      isDirectory: false,
      size: bytes.length,
      modified: DateTime.utc(2024, 4, 5, 6, 7, 8),
      mode: mode,
      readChunks: () => Stream.value(bytes),
    );

Future<Uint8List> _hfs(List<ArchiveWriteEntry> entries) =>
    collectArchiveWrite((sink) => writeHfsArchive(entries, sink: sink));

void main() {
  test(
    'empty fresh HFSX volume has matching alternate header and opens',
    () async {
      final bytes = await _hfs([]);
      expect(bytes.length, 8 * 1024 * 1024);
      expect(
        bytes.sublist(1024, 1536),
        bytes.sublist(bytes.length - 1024, bytes.length - 512),
      );
      final archive = await openHfsArchive(
        koni.MemoryByteSource(bytes),
        maxMemberBytes: 1024,
      );
      addTearDown(archive.close);
      expect(archive.formatName, 'hfsx');
      expect(archive.members, isEmpty);
    },
  );

  test(
    'HFSX creates indexed catalogs, implicit folders, Unicode, modes and dates',
    () async {
      final entries = [
        _file(
          'café/資料/hello.txt',
          utf8.encode('Unicode payload'),
          mode: 0x81ed,
        ),
        _file('Case.txt', [1]),
        _file('case.txt', [2]),
        _file('한글-😀.txt', [3]),
        _file('empty', []),
        ArchiveWriteEntry(path: 'empty-folder', isDirectory: true, size: 0),
        for (var i = 0; i < 180; i++)
          _file('many/file-$i.txt', utf8.encode('$i')),
      ];
      final bytes = await _hfs(entries);
      final archive = await openHfsArchive(
        koni.MemoryByteSource(bytes),
        maxMemberBytes: 1024,
      );
      addTearDown(archive.close);
      for (final entry in entries.where((entry) => !entry.isDirectory)) {
        final member = archive.members.singleWhere(
          (member) => member.name == normalizeHfsArchivePath(entry.path),
        );
        expect(
          await archive.readMember(member),
          await entry.read(),
          reason: entry.path,
        );
        expect(member.modified, entry.modified);
      }
      expect(
        archive.members
            .singleWhere((m) => m.name.endsWith('hello.txt'))
            .posixMode,
        0x81ed,
      );
      expect(
        archive.members.singleWhere((m) => m.name == 'empty-folder').isFile,
        isFalse,
      );
      expect(archive.members.where((m) => !m.isFile).length, 4);
    },
  );

  test(
    'normalization uses frozen HFS rules instead of current generic NFD',
    () {
      expect(
        normalizeHfsArchivePath('café/Å-Å-豈-한글-😀'),
        'cafe\u0301/A\u030a-Å-豈-\u1112\u1161\u11ab\u1100\u1173\u11af-😀',
      );
      expect(normalizeHfsArchivePath('a\u0315\u0300'), 'a\u0300\u0315');
      // Balinese characters were added after Unicode 3.2; modern NFD decomposes
      // this character, but HFS's frozen table must leave it alone.
      expect(normalizeHfsArchivePath('\u1b06'), '\u1b06');
      expect(normalizeHfsArchivePath('\u212b'), '\u212b');
      expect(
        () => normalizeHfsArchivePath('\ud800'),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(
        () => normalizeHfsArchivePath('é' * 128),
        throwsA(isA<ArchiveViewException>()),
      );
    },
  );

  test(
    'normalized collisions are rejected before reading or emitting data',
    () async {
      var reads = 0, writes = 0;
      ArchiveWriteEntry entry(String path) => ArchiveWriteEntry(
        path: path,
        isDirectory: false,
        size: 0,
        readChunks: () {
          reads++;
          return const Stream.empty();
        },
      );
      await expectLater(
        writeHfsArchive(
          [entry('é'), entry('e\u0301')],
          sink: (_) async {
            writes++;
          },
        ),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(reads, 0);
      expect(writes, 0);
    },
  );

  for (final bad in [
    _file('../escape', []),
    _file('a:b', []),
    _file('link', [], mode: 0xa1ff),
    ArchiveWriteEntry(
      path: 'resource-fork',
      isDirectory: false,
      size: 0,
      attributes: {'resourceFork': true},
      readChunks: () => const Stream.empty(),
    ),
    ArchiveWriteEntry(
      path: 'future',
      isDirectory: false,
      size: 0,
      modified: DateTime.utc(2100),
      readChunks: () => const Stream.empty(),
    ),
  ]) {
    test('rejects unsupported input ${bad.path} before sink output', () async {
      var writes = 0;
      await expectLater(
        writeHfsArchive(
          [bad],
          sink: (_) async {
            writes++;
          },
        ),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(writes, 0);
    });
  }

  for (final bytes in [
    [1],
    [1, 2, 3],
  ]) {
    test(
      'rejects a captured file with ${bytes.length} bytes against two declared',
      () async {
        final entry = ArchiveWriteEntry(
          path: 'changed',
          isDirectory: false,
          size: 2,
          readChunks: () => Stream.value(bytes),
        );
        await expectLater(
          writeHfsArchive([entry], sink: (_) async {}),
          throwsA(isA<ArchiveViewException>()),
        );
      },
    );
  }

  test(
    'HFS output budget is checked before any bytes or source reads',
    () async {
      var writes = 0;
      await expectLater(
        writeHfsArchive(
          [],
          maxOutputBytes: 8 * 1024 * 1024 - 1,
          sink: (_) async {
            writes++;
          },
        ),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(writes, 0);
    },
  );

  test(
    'cancellation and sink backpressure prevent further member reads',
    () async {
      var reads = 0, writes = 0, cancel = false;
      final blocked = Completer<void>();
      final entry = ArchiveWriteEntry(
        path: 'pending',
        isDirectory: false,
        size: 1,
        readChunks: () {
          reads++;
          return Stream.value([1]);
        },
      );
      final job = writeHfsArchive(
        [entry],
        isCancelled: () => cancel,
        sink: (_) async {
          writes++;
          await blocked.future;
        },
      );
      final failure = expectLater(job, throwsA(isA<ArchiveViewException>()));
      await Future<void>.delayed(Duration.zero);
      expect(reads, 0);
      expect(writes, 1);
      cancel = true;
      blocked.complete();
      await failure;
      expect(reads, 0);
      expect(writes, 1);
    },
  );

  test('bounded HFS/DMG partition views remain read-only when a caller supplies a fabricated rewrite inspection', () async {
    final archive = ViewerArchive.direct(
      formatName: 'hfsx',
      name: 'data',
      data: Uint8List(0),
    );
    addTearDown(archive.close);
    expect((await inspectHfsRewrite(Uint8List(0), archive)).supported, isFalse);
    expect((await inspectDmgRewrite(Uint8List(0), archive)).supported, isFalse);
    final source = ArchiveRewriteInspection();
    await expectLater(
      writeHfsArchive([], source: source, sink: (_) async {}),
      throwsA(isA<ArchiveViewException>()),
    );
    await expectLater(
      writeDmgArchive([], source: source, sink: (_) async {}),
      throwsA(isA<ArchiveViewException>()),
    );
  });

  for (final compressed in [true, false]) {
    test(
      'DMG ${compressed ? 'zlib' : 'raw'} output has valid CRCs and readable HFSX files',
      () async {
        final bytes = await collectArchiveWrite(
          (sink) => writeDmgArchive(
            [_file('docs/hello.txt', utf8.encode('hello disk'))],
            sink: sink,
            compress: compressed,
          ),
        );
        final trailer = ByteData.sublistView(bytes, bytes.length - 512);
        final xmlOffset = trailer.getUint64(216);
        final xmlLength = trailer.getUint64(224);
        expect(
          trailer.getUint32(88),
          ar.getCrc32(Uint8List.sublistView(bytes, 0, xmlOffset)),
        );
        final xml = utf8.decode(
          bytes.sublist(xmlOffset, xmlOffset + xmlLength),
        );
        final table = base64.decode(
          RegExp(r'<data>([^<]+)</data>').firstMatch(xml)!.group(1)!,
        );
        final t = ByteData.sublistView(table);
        final checksum = Uint8List(4);
        ByteData.sublistView(checksum).setUint32(0, t.getUint32(72));
        expect(trailer.getUint32(360), ar.getCrc32(checksum));
        final archive = await openDmgArchive(
          koni.MemoryByteSource(bytes),
          maxMemberBytes: 16 * 1024 * 1024,
        );
        addTearDown(archive.close);
        final file = archive.members.singleWhere(
          (m) => m.name.endsWith('/hello.txt'),
        );
        expect(utf8.decode(await archive.readMember(file)), 'hello disk');
        final raw = archive.members.singleWhere(
          (m) => m.name.startsWith('partitions/'),
        );
        final crc = await archive
            .openMember(raw, chunkSize: 16381)
            .fold<int>(0, (crc, chunk) => ar.getCrc32(chunk, crc));
        expect(crc, t.getUint32(72));
      },
    );
  }

  test(
    'DMG compressed output limit also accounts for XML and trailer',
    () async {
      var written = 0;
      await expectLater(
        writeDmgArchive(
          [],
          maxOutputBytes: 1024,
          sink: (bytes) async {
            written += bytes.length;
          },
        ),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(written, lessThanOrEqualTo(1024));
    },
  );

  test('streamed native DMG partition CRC excludes BLOCK_IGNORE', () async {
    final bytes = File('test/fixtures/archives/native-hfsplus.dmg')
        .readAsBytesSync();
    final archive = await openDmgArchive(
      koni.MemoryByteSource(bytes),
      maxMemberBytes: 16 * 1024 * 1024,
    );
    addTearDown(archive.close);
    for (final member in archive.members.where(
      (m) => m.name.startsWith('partitions/'),
    )) {
      final streamed = await sha256
          .bind(archive.openMember(member, chunkSize: 32771))
          .single;
      expect(
        streamed,
        sha256.convert(await archive.readMember(member)),
        reason: member.name,
      );
    }
  });

  test('streamed DMG partition surfaces a CRC failure at completion', () async {
    final fixture = DmgFixture(Uint8List(1024)..[900] = 7);
    ByteData.sublistView(fixture.table).setUint32(72, 0x12345678);
    fixture.rebuild();
    final archive = await openDmgArchive(
      koni.MemoryByteSource(fixture.bytes),
      maxMemberBytes: 4096,
    );
    addTearDown(archive.close);
    await expectLater(
      archive.openMember(archive.members.single, chunkSize: 513).drain<void>(),
      throwsA(isA<ArchiveViewException>()),
    );
  });

  test(
    'disk writers and positional readers stream a file larger than 64 MiB',
    () async {
      const size = 65 * 1024 * 1024 + 333;
      final block = Uint8List.fromList(List.generate(65536, (i) => i % 251));
      Stream<List<int>> contents() async* {
        for (var at = 0; at < size; at += block.length) {
          final count = size - at < block.length ? size - at : block.length;
          yield Uint8List.sublistView(block, 0, count);
        }
      }

      final expected = await sha256.bind(contents()).single;
      final entry = ArchiveWriteEntry(
        path: 'large.bin',
        isDirectory: false,
        size: size,
        readChunks: contents,
      );
      final dir = await Directory.systemTemp.createTemp('crisp-disk-writer-');
      addTearDown(() => dir.delete(recursive: true));
      for (final dmg in [false, true]) {
        final file = File('${dir.path}/large.${dmg ? 'dmg' : 'hfs'}');
        final output = await file.open(mode: FileMode.write);
        var maxWrite = 0;
        Future<void> sink(List<int> bytes) async {
          if (bytes.length > maxWrite) maxWrite = bytes.length;
          await output.writeFrom(bytes);
        }

        try {
          if (dmg) {
            await writeDmgArchive([entry], sink: sink);
          } else {
            await writeHfsArchive([entry], sink: sink);
          }
        } finally {
          await output.close();
        }
        expect(maxWrite, lessThanOrEqualTo(1024 * 1024));
        final source = await _DiskSource.open(file);
        final archive = dmg
            ? await openDmgArchive(source, maxMemberBytes: size)
            : await openHfsArchive(source, maxMemberBytes: size);
        final member = archive.members.singleWhere(
          (m) => m.name.endsWith('large.bin'),
        );
        await expectLater(
          archive.readMember(member),
          throwsA(isA<ArchiveViewException>()),
        );
        final actual = await sha256
            .bind(
              archive.openMember(member, maxBytes: size, chunkSize: 192 * 1024),
            )
            .single;
        expect(actual, expected);
        expect(source.maxRead, lessThanOrEqualTo(1024 * 1024));
        await archive.close();
        expect(source.closed, isTrue);
        final limited = dmg
            ? await openDmgArchive(
                await _DiskSource.open(file),
                maxMemberBytes: size - 1,
              )
            : await openHfsArchive(
                await _DiskSource.open(file),
                maxMemberBytes: size - 1,
              );
        final oversized = limited.members.singleWhere(
          (m) => m.name.endsWith('large.bin'),
        );
        await expectLater(
          limited.openMember(oversized, maxBytes: size).drain<void>(),
          throwsA(isA<ArchiveViewException>()),
        );
        await limited.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

class _DiskSource implements koni.ByteSource {
  _DiskSource(this.file, this.length);
  static Future<_DiskSource> open(File file) async =>
      _DiskSource(await file.open(), await file.length());
  final RandomAccessFile file;
  @override
  final int length;
  @override
  String get name => 'disk-test';
  int maxRead = 0;
  bool closed = false;
  @override
  Future<Uint8List> read(int offset, int length) async {
    if (length > maxRead) maxRead = length;
    await file.setPosition(offset);
    return file.read(length);
  }

  @override
  Future<void> close() async {
    closed = true;
    await file.close();
  }
}
