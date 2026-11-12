import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' as ar;
import 'package:crisp_cloud/services/archive_cab_reader.dart';
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import 'support/archive_cab_fixtures.dart';

const _text1 =
    '                          file 1 contents\nhello\nhello\nhello\n';
const _text2 =
    '                          file 2 contents\n'
    'hello\nhello\nhello\nhello\nhello\nhello\n';

class _TrackedSource implements koni.ByteSource {
  _TrackedSource(this.bytes, {this.lengthOverride});
  final Uint8List bytes;
  final int? lengthOverride;
  final reads = <({int offset, int length})>[];
  var closes = 0;
  var shortRead = false;
  Completer<void>? gate;
  @override
  String get name => 'test.cab';
  @override
  int get length => lengthOverride ?? bytes.length;
  @override
  Future<Uint8List> read(int offset, int length) async {
    if (closes > 0) throw StateError('Read after close');
    reads.add((offset: offset, length: length));
    await gate?.future;
    return Uint8List.sublistView(
      bytes,
      offset,
      offset + length - (shortRead && length > 0 ? 1 : 0),
    );
  }

  @override
  Future<void> close() async {
    closes++;
  }
}

Uint8List _single({int method = 0, List<int> data = const [1, 2, 3]}) =>
    cabFixture([
      CabFixtureFolder([CabFixtureFile('file.bin', data)], method: method),
    ]);
Future<ViewerArchive> _open(
  Uint8List bytes, {
  int memberLimit = 1024 * 1024,
  int folderLimit = 1024 * 1024,
}) => openCabArchive(
  koni.MemoryByteSource(bytes),
  maxMemberBytes: memberLimit,
  maxFolderBytes: folderLimit,
);
Uint8List _reference(String name) =>
    File('test/fixtures/archives/$name.cab').readAsBytesSync();
int _dataAt(Uint8List bytes) =>
    ByteData.sublistView(bytes).getUint32(36, Endian.little);
int _filesAt(Uint8List bytes) =>
    ByteData.sublistView(bytes).getUint32(16, Endian.little);

Future<void> _refused(
  Uint8List bytes, {
  int memberLimit = 1024 * 1024,
  int folderLimit = 1024 * 1024,
}) async {
  final source = _TrackedSource(bytes);
  await expectLater(
    openCabArchive(
      source,
      maxMemberBytes: memberLimit,
      maxFolderBytes: folderLimit,
    ),
    throwsA(isA<ArchiveViewException>()),
  );
  expect(source.closes, 1);
  expect(
    source.reads.every(
      (r) =>
          r.offset >= 0 &&
          r.length >= 0 &&
          r.offset + r.length <= source.length,
    ),
    isTrue,
  );
}

Uint8List _withPackedBlock(Uint8List base, List<int> packed) {
  final at = _dataAt(base);
  final result = Uint8List.fromList([...base.sublist(0, at + 8), ...packed]);
  ByteData.sublistView(result)
    ..setUint32(8, result.length, Endian.little)
    ..setUint32(at, 0, Endian.little)
    ..setUint16(at + 4, packed.length, Endian.little);
  return result;
}

void main() {
  for (final method in ['stored', 'mszip']) {
    test('reads independent Windows MakeCAB $method files', () async {
      final archive = await _open(_reference('reference-makecab-$method'));
      addTearDown(archive.close);
      expect(archive.formatName, 'cab');
      final content = <String, Uint8List>{};
      for (final member in archive.members.reversed) {
        content[member.name] = await archive.readMember(member);
      }
      expect(content['empty'], isEmpty);
      expect(utf8.decode(content['dir1/file1']!), _text1);
      expect(utf8.decode(content['dir2/file2']!), _text2);
      if (method == 'mszip') expect(content['zero'], Uint8List(33000));
      expect(archive.notices.join(' '), contains('signatures'));
    });
  }

  test(
    'MSZIP preserves the previous block dictionary with exact content',
    () async {
      final archive = await _open(_reference('reference-zlib-history'));
      addTearDown(archive.close);
      final history = await archive.readMember(archive.members.first);
      final dependent = await archive.readMember(archive.members.last);
      expect(history.length, 32768);
      final expected = BytesBuilder(copy: false);
      for (var i = 0; i < 1024; i++) {
        final number = ByteData(4)..setUint32(0, i, Endian.little);
        expected.add(crypto.sha256.convert(number.buffer.asUint8List()).bytes);
      }
      expect(history, expected.takeBytes());
      expect(dependent, [
        ...history.sublist(history.length - 2048),
        ...history.sublist(history.length - 2048),
        ...utf8.encode('CAB history survives block boundaries.\n'),
      ]);
    },
  );

  for (final method in [0, 1]) {
    test(
      'reads UTF-8 names, Windows paths and multiple $method blocks',
      () async {
        final data = List.generate(66000, (i) => i % 251);
        final archive = await _open(
          cabFixture([
            CabFixtureFolder([
              CabFixtureFile(r'docs\日本語.txt', data),
              const CabFixtureFile('empty.txt', []),
            ], method: method),
          ]),
        );
        addTearDown(archive.close);
        expect(archive.members.first.name, 'docs/日本語.txt');
        expect(archive.members.first.modified, DateTime(2024, 1, 2, 3, 4, 6));
        expect(await archive.readMember(archive.members.first), data);
        expect(await archive.readMember(archive.members.last), isEmpty);
        final streamed = await archive
            .openMember(archive.members.first, chunkSize: 123)
            .expand((chunk) => chunk)
            .toList();
        expect(streamed, data);
      },
    );
  }

  test(
    'multiple folders and concurrent out-of-order reads keep their own data',
    () async {
      final archive = await _open(
        cabFixture([
          const CabFixtureFolder([
            CabFixtureFile('a', [1, 2]),
          ], method: 1),
          const CabFixtureFolder([
            CabFixtureFile('b', [3, 4, 5]),
          ]),
          const CabFixtureFolder([
            CabFixtureFile('c', [6]),
          ], method: 1),
        ]),
      );
      addTearDown(archive.close);
      expect(
        await Future.wait(
          [
            2,
            0,
            1,
            0,
            2,
          ].map((index) => archive.readMember(archive.members[index])),
        ),
        [
          [6],
          [1, 2],
          [3, 4, 5],
          [1, 2],
          [6],
        ],
      );
    },
  );

  test(
    'unzoned wall-clock timestamps do not inherit host DST validity',
    () async {
      final bytes = _single();
      ByteData.sublistView(bytes)
        ..setUint16(
          _filesAt(bytes) + 10,
          (44 << 9) | (3 << 5) | 10,
          Endian.little,
        )
        ..setUint16(_filesAt(bytes) + 12, (2 << 11) | (30 << 5), Endian.little);
      final archive = await _open(bytes);
      addTearDown(archive.close);
      expect(await archive.readMember(archive.members.single), [1, 2, 3]);
    },
  );

  test(
    'listing is metadata-only and a folder is cached until another is read',
    () async {
      final bytes = _single(data: List.filled(40000, 42));
      final source = _TrackedSource(bytes);
      final archive = await openCabArchive(source, maxMemberBytes: 100000);
      final at = _dataAt(bytes);
      expect(
        source.reads.every(
          (r) =>
              r.offset + r.length <= at + 8 ||
              r.offset == at + 8 + 32768 && r.length == 8,
        ),
        isTrue,
      );
      expect(source.reads.any((r) => r.length >= 32768), isFalse);
      await archive.readMember(archive.members.single);
      final count = source.reads.length;
      await archive.readMember(archive.members.single);
      expect(source.reads.length, count);
      await archive.close();
      await archive.close();
      expect(source.closes, 1);
    },
  );

  for (final reserveSize in [1, 2, 3]) {
    test(
      'checksums cover $reserveSize reserved bytes and remainder byte order',
      () async {
        final bytes = cabFixture(
          [
            CabFixtureFolder([
              CabFixtureFile('x', List.generate(reserveSize + 4, (i) => i + 1)),
            ]),
          ],
          headerReserve: [1, 2, 3],
          folderReserve: [4],
          dataReserve: List.filled(reserveSize, 5),
        );
        final archive = await _open(bytes);
        addTearDown(archive.close);
        expect(
          await archive.readMember(archive.members.single),
          List.generate(reserveSize + 4, (i) => i + 1),
        );
      },
    );
  }

  test(
    'zero checksums are optional; nonzero checksum corruption fails on read',
    () async {
      final bytes = _single();
      final bad = Uint8List.fromList(bytes)..[bytes.length - 1] ^= 1;
      final archive = await _open(bad);
      addTearDown(archive.close);
      await expectLater(
        archive.readMember(archive.members.single),
        throwsA(isA<ArchiveViewException>()),
      );
      ByteData.sublistView(bad).setUint32(_dataAt(bad), 0, Endian.little);
      final unchecked = await _open(bad);
      addTearDown(unchecked.close);
      expect(await unchecked.readMember(unchecked.members.single), [1, 2, 2]);
    },
  );

  test(
    'empty cabinets and folders open without allocations from absent payloads',
    () async {
      for (final bytes in [
        cabFixture([]),
        cabFixture([
          const CabFixtureFolder([CabFixtureFile('empty', [])]),
        ]),
      ]) {
        final archive = await _open(bytes);
        addTearDown(archive.close);
        for (final member in archive.members) {
          expect(await archive.readMember(member), isEmpty);
        }
      }
    },
  );

  for (final name in [
    '../escape',
    '/absolute',
    r'C:\drive',
    r'\\host\share',
    'name:stream',
    'control\u0001',
    'a/../../escape',
  ]) {
    test('flags and blocks unsafe CAB name $name', () async {
      final archive = await _open(
        cabFixture([
          CabFixtureFolder([
            CabFixtureFile(name, [1]),
          ]),
        ]),
      );
      addTearDown(archive.close);
      expect(archive.members.single.pathEscapedRoot, isTrue);
      await expectLater(
        archive.readMember(archive.members.single),
        throwsA(isA<ArchiveViewException>()),
      );
    });
  }

  final malformed = <String, void Function(Uint8List)>{
    'magic': (b) => b[0] = 0,
    'reserved header word': (b) => b[4] = 1,
    'version': (b) => b[24] = 2,
    'previous cabinet': (b) => b[30] = 1,
    'next cabinet': (b) => b[30] = 2,
    'unknown flags': (b) => b[30] = 8,
    'cabinet index': (b) => b[34] = 1,
    'cabinet length beyond input': (b) =>
        ByteData.sublistView(b).setUint32(8, b.length + 1, Endian.little),
    'file table overlaps header': (b) =>
        ByteData.sublistView(b).setUint32(16, 20, Endian.little),
    'folder overlaps metadata': (b) =>
        ByteData.sublistView(b).setUint32(36, 40, Endian.little),
    'folder offset beyond input': (b) =>
        ByteData.sublistView(b).setUint32(36, b.length + 1, Endian.little),
    'Quantum compression': (b) => b[42] = 2,
    'LZX compression': (b) => b[42] = 3,
    'unknown compression option bits': (b) => b[43] = 1,
    'split file': (b) =>
        ByteData.sublistView(b)
            .setUint16(_filesAt(b) + 8, 0xfffd, Endian.little),
    'invalid folder reference': (b) => b[_filesAt(b) + 8] = 1,
    'member offset outside folder': (b) => b[_filesAt(b) + 4] = 4,
    'member size outside folder': (b) => b[_filesAt(b)] = 4,
    'file count beyond metadata': (b) => b[28] = 2,
    'block count beyond input': (b) => b[40] = 2,
    'split data block': (b) => b[_dataAt(b) + 6] = 0,
    'oversized decoded block': (b) =>
        ByteData.sublistView(b).setUint16(_dataAt(b) + 6, 32769, Endian.little),
    'oversized compressed block': (b) =>
        ByteData.sublistView(b).setUint16(_dataAt(b) + 4, 32781, Endian.little),
    'inconsistent stored length': (b) => b[_dataAt(b) + 4] = 2,
    'invalid attributes': (b) => b[_filesAt(b) + 14] = 0x10,
    'invalid date': (b) =>
        ByteData.sublistView(b).setUint16(_filesAt(b) + 10, 1, Endian.little),
    'invalid time': (b) =>
        ByteData.sublistView(b)
            .setUint16(_filesAt(b) + 12, 0xffff, Endian.little),
    'unterminated name': (b) => b[_dataAt(b) - 1] = 65,
    'invalid UTF-8 name': (b) => b[_filesAt(b) + 16] = 0xff,
    'empty name': (b) => b[_filesAt(b) + 16] = 0,
  };
  for (final mutation in malformed.entries) {
    test('rejects ${mutation.key} and releases its source', () async {
      final bytes = _single();
      mutation.value(bytes);
      await _refused(bytes);
    });
  }

  test(
    'refuses unspecified legacy filename codepages and oversized names',
    () async {
      for (final file in [
        const CabFixtureFile('café', [1], attributes: 0x20),
        CabFixtureFile('x' * (16 * 1024 + 1), [1]),
      ]) {
        await _refused(
          cabFixture([
            CabFixtureFolder([file]),
          ]),
        );
      }
    },
  );

  test('refuses overlapping folder ranges before reading payloads', () async {
    final bytes = cabFixture([
      const CabFixtureFolder([
        CabFixtureFile('a', [1, 2, 3]),
      ]),
      const CabFixtureFolder([
        CabFixtureFile('b', [4, 5, 6]),
      ]),
    ]);
    final data = ByteData.sublistView(bytes);
    data.setUint32(44, data.getUint32(36, Endian.little), Endian.little);
    await _refused(bytes);
  });

  test(
    'all truncated prefixes fail cleanly without reading beyond input',
    () async {
      final bytes = _single();
      for (var end = 0; end < bytes.length; end++) {
        await _refused(Uint8List.sublistView(bytes, 0, end));
      }
    },
  );

  test(
    'metadata and folder limits are checked before large allocation',
    () async {
      await _refused(_single(), folderLimit: 2);
      final bytes = _single();
      const size = 17 * 1024 * 1024;
      ByteData.sublistView(bytes)
        ..setUint32(8, size, Endian.little)
        ..setUint32(36, size - 100, Endian.little);
      final source = _TrackedSource(bytes, lengthOverride: size);
      await expectLater(
        openCabArchive(source, maxMemberBytes: 1),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(source.reads.every((r) => r.length < 100), isTrue);
      expect(source.closes, 1);
    },
  );

  test('a caller cannot raise the captured member limit', () async {
    final archive = await _open(_single(), memberLimit: 2);
    addTearDown(archive.close);
    await expectLater(
      archive.readMember(archive.members.single, maxBytes: 10),
      throwsA(isA<ArchiveViewException>()),
    );
  });

  test('short metadata and payload reads are rejected', () async {
    final bad = _TrackedSource(_single())..shortRead = true;
    await expectLater(
      openCabArchive(bad, maxMemberBytes: 1024),
      throwsA(isA<ArchiveViewException>()),
    );
    expect(bad.closes, 1);
    final source = _TrackedSource(_single());
    final archive = await openCabArchive(source, maxMemberBytes: 1024);
    addTearDown(archive.close);
    source.shortRead = true;
    await expectLater(
      archive.readMember(archive.members.single),
      throwsA(isA<ArchiveViewException>()),
    );
  });

  test(
    'closing during a pending read discards the result and closes once',
    () async {
      final source = _TrackedSource(_single());
      final archive = await openCabArchive(source, maxMemberBytes: 1024);
      source.gate = Completer<void>();
      final reading = archive.readMember(archive.members.single);
      final assertion = expectLater(
        reading,
        throwsA(isA<ArchiveViewException>()),
      );
      await Future<void>.delayed(Duration.zero);
      await archive.close();
      source.gate!.complete();
      await assertion;
      await archive.close();
      expect(source.closes, 1);
    },
  );

  final badMszip = <String, List<int> Function(List<int>)>{
    'missing signature': (b) => [0, ...b.skip(1)],
    'truncated stream': (b) => b.sublist(0, b.length - 1),
    'trailing data': (b) => [...b, 0],
    'invalid DEFLATE block type': (_) => [0x43, 0x4b, 7],
    'wrong decoded length': (_) => [
      0x43,
      0x4b,
      ...ar.Deflate([1, 2]).getBytes(),
    ],
    'expansion beyond declared length': (_) => [
      0x43,
      0x4b,
      ...ar.Deflate(Uint8List(1000000)).getBytes(),
    ],
  };
  for (final mutation in badMszip.entries) {
    test('rejects MSZIP ${mutation.key}', () async {
      final bytes = _single(method: 1);
      final at = _dataAt(bytes);
      final archive = await _open(
        _withPackedBlock(bytes, mutation.value(bytes.sublist(at + 8))),
      );
      addTearDown(archive.close);
      await expectLater(
        archive.readMember(archive.members.single),
        throwsA(isA<ArchiveViewException>()),
      );
    });
  }
}
