import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:crisp_cloud/services/archive_rar_metadata_reader.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import 'support/archive_external_packer_fixtures.dart';

// Small independent format builder: no production RAR header/time encoder is
// used here. All field layouts follow the vendor's public RAR5 technote.
const _magic = [0x52, 0x61, 0x72, 0x21, 0x1a, 7, 1, 0];
List<int> _v(int value) {
  final bytes = <int>[];
  do {
    final low = value & 127;
    value >>= 7;
    bytes.add(low | (value == 0 ? 0 : 128));
  } while (value != 0);
  return bytes;
}

List<int> _u32(int value) => [
  for (var i = 0; i < 4; i++) (value >> (i * 8)) & 255,
];
List<int> _u64(int value) => [
  for (var i = 0; i < 8; i++) (value >> (i * 8)) & 255,
];
List<int> _extra(int type, List<int> data) {
  final body = [..._v(type), ...data];
  return [..._v(body.length), ...body];
}

Uint8List _header(
  int type,
  List<int> fields, {
  List<int> extra = const [],
  int? dataSize,
  int flags = 0,
}) {
  final body = [
    ..._v(type),
    ..._v(flags | (extra.isEmpty ? 0 : 1) | (dataSize == null ? 0 : 2)),
    if (extra.isNotEmpty) ..._v(extra.length),
    if (dataSize != null) ..._v(dataSize),
    ...fields,
    ...extra,
  ];
  final checked = [..._v(body.length), ...body];
  return Uint8List.fromList([..._u32(getCrc32(checked)), ...checked]);
}

final _main = _header(1, [0]);
final _end = _header(5, [0]);

class _Fixture {
  _Fixture({
    this.name = 'folder/雪.txt',
    this.seconds = 1704164645,
    this.nanoseconds = 123456789,
    this.directory = false,
    this.baseTime = false,
    this.timeExtra = true,
    this.extraRecords = const [],
    this.packedSize,
    this.mode = 0x1a0,
    this.windowsTime = false,
    this.payload = const [1, 2, 3],
    this.headerType = 2,
    this.encrypted = false,
  });
  final String name;
  final int seconds, nanoseconds, mode, headerType;
  final bool directory, baseTime, timeExtra, windowsTime, encrypted;
  final int? packedSize;
  final List<int> payload, extraRecords;
  int get size => directory ? 0 : packedSize ?? payload.length;
  int get crc => directory ? 0 : getCrc32(payload);
  DateTime get time => DateTime.fromMicrosecondsSinceEpoch(
    seconds * 1000000 + nanoseconds ~/ 1000,
    isUtc: true,
  );
  Uint8List get header {
    final nameBytes = utf8.encode(name);
    final times = windowsTime
        ? [
            2,
            ..._u64(
              116444736000000000 + seconds * 10000000 + nanoseconds ~/ 100,
            ),
          ]
        : [0x13, ..._u32(seconds), ..._u32(nanoseconds)];
    return _header(
      headerType,
      [
        directory ? (baseTime ? 7 : 5) : (baseTime ? 6 : 4),
        ..._v(size),
        ..._v((directory ? 0x4000 : 0x8000) | mode),
        if (baseTime) ..._u32(seconds),
        ..._u32(crc),
        ..._v(packedSize == null ? 0 : 3 << 7),
        1,
        ..._v(nameBytes.length),
        ...nameBytes,
      ],
      dataSize: size,
      extra: [
        if (timeExtra) ..._extra(3, times),
        if (encrypted) ..._extra(1, [0]),
        ...extraRecords,
      ],
    );
  }

  koni.ArchiveEntry get entry {
    final normalized = koni.normalizeEntryPath(name);
    return koni.ArchiveEntry(
      path: normalized.path,
      pathEscapedRoot: normalized.escapedRoot,
      type: directory
          ? koni.ArchiveEntryType.directory
          : koni.ArchiveEntryType.file,
      uncompressedSize: size,
      compressedSize: size,
      crc32: crc,
      posixMode: mode,
      isEncrypted: encrypted,
      modified: baseTime
          ? DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true)
          : null,
    );
  }
}

Uint8List _archive(
  List<_Fixture> files, {
  bool end = true,
  List<int> main = const [],
}) => Uint8List.fromList([
  ..._magic,
  ...(main.isEmpty ? _main : main),
  for (final file in files) ...[
    ...file.header,
    if (!file.directory) ...file.payload,
  ],
  if (end) ..._end,
]);

class _SparseSource implements koni.ByteSource {
  _SparseSource(this.length, this.regions);
  @override
  final int length;
  final Map<int, Uint8List> regions;
  int maximumRead = 0;
  bool closed = false;
  @override
  String? get name => 'bounded.rar';
  @override
  Future<Uint8List> read(int offset, int length) async {
    maximumRead = length > maximumRead ? length : maximumRead;
    for (final entry in regions.entries) {
      if (offset >= entry.key &&
          offset + length <= entry.key + entry.value.length) {
        return Uint8List.sublistView(
          entry.value,
          offset - entry.key,
          offset - entry.key + length,
        );
      }
    }
    throw StateError('Metadata reader touched a payload range.');
  }

  @override
  Future<void> close() async => closed = true;
}

void main() {
  Future<List<DateTime?>?> read(
    List<_Fixture> fixtures, {
    Uint8List? bytes,
    List<koni.ArchiveEntry>? entries,
  }) => readRar5ModifiedTimes(
    koni.MemoryByteSource(bytes ?? _archive(fixtures)),
    entries ??
        fixtures
            .where((file) => file.headerType == 2)
            .map((file) => file.entry)
            .toList(),
  );
  final corrupt = throwsA(isA<ArchiveViewException>());

  test(
    'Unix nanoseconds are exposed at exact DateTime microsecond precision',
    () async {
      final file = _Fixture();
      expect(await read([file]), [file.time]);
    },
  );
  test(
    'Windows FILETIME and base-header fallback are both supported',
    () async {
      final precise = _Fixture(windowsTime: true, nanoseconds: 123456700);
      final basic = _Fixture(
        name: 'second',
        timeExtra: false,
        baseTime: true,
        nanoseconds: 0,
      );
      expect(await read([precise, basic]), [precise.time, basic.time]);
    },
  );
  test(
    'time extras override the lower precision optional base-header time',
    () async {
      final file = _Fixture(baseTime: true);
      expect(await read([file]), [file.time]);
    },
  );
  test(
    'duplicate normalized names remain bound by ordered member index',
    () async {
      final first = _Fixture(name: 'duplicate', seconds: 1704164645);
      final second = _Fixture(name: 'duplicate', seconds: 1704164646);
      expect(await read([first, second]), [first.time, second.time]);
    },
  );
  test('unsafe-path status is retained rather than normalized away', () async {
    final file = _Fixture(name: '../../escape');
    expect(file.entry.pathEscapedRoot, isTrue);
    expect(await read([file]), [file.time]);
    final safe = _Fixture(name: 'escape');
    await expectLater(read([file], entries: [safe.entry]), corrupt);
  });
  test(
    'service blocks cannot steal the time of a following ordinary member',
    () async {
      final service = _Fixture(name: 'QO', headerType: 3, seconds: 1);
      final file = _Fixture();
      expect(await read([service, file]), [file.time]);
    },
  );
  test(
    'unknown bounded extra records are skipped without granting a writer',
    () async {
      final file = _Fixture(extraRecords: _extra(0x7f, [1, 2, 3]));
      expect(await read([file]), [file.time]);
    },
  );
  test(
    'clear metadata for an encrypted member keeps encryption binding intact',
    () async {
      final file = _Fixture(encrypted: true);
      expect(await read([file]), [file.time]);
      await expectLater(read([file], entries: [_Fixture().entry]), corrupt);
    },
  );
  test('directories have the same exact timestamp handling', () async {
    final directory = _Fixture(name: 'empty/', directory: true, mode: 0x1c0);
    expect(await read([directory]), [directory.time]);
  });
  test(
    'changed ordered names, sizes, modes and entry counts fail binding',
    () async {
      final file = _Fixture();
      for (final wrong in [
        _Fixture(name: 'other'),
        _Fixture(mode: 0x180),
        _Fixture(payload: [1, 2, 3, 4]),
        _Fixture(directory: true),
      ]) {
        await expectLater(read([file], entries: [wrong.entry]), corrupt);
      }
      await expectLater(read([file], entries: []), corrupt);
      await expectLater(
        read([file], entries: [file.entry, file.entry]),
        corrupt,
      );
    },
  );
  test(
    'duplicate or invalid high-precision time records are rejected',
    () async {
      await expectLater(
        read([
          _Fixture(extraRecords: _extra(3, [3, ..._u32(1)])),
        ]),
        corrupt,
      );
      await expectLater(read([_Fixture(nanoseconds: 1000000000)]), corrupt);
      await expectLater(
        read([
          _Fixture(extraRecords: [0]),
        ]),
        corrupt,
      );
    },
  );
  test(
    'header checksums and every truncation after the signature fail closed',
    () async {
      final file = _Fixture();
      final bytes = _archive([file]);
      final bad = Uint8List.fromList(bytes);
      bad[8] ^= 1;
      await expectLater(read([file], bytes: bad), corrupt);
      for (var cut = 8; cut < bytes.length; cut++) {
        await expectLater(
          read([file], bytes: Uint8List.sublistView(bytes, 0, cut)),
          corrupt,
          reason: 'cut at $cut',
        );
      }
    },
  );
  test('trailing bytes and a missing end header are rejected', () async {
    final file = _Fixture();
    await expectLater(
      read([file], bytes: _archive([file], end: false)),
      corrupt,
    );
    await expectLater(
      read(
        [file],
        bytes: Uint8List.fromList([
          ..._archive([file]),
          0,
        ]),
      ),
      corrupt,
    );
  });
  test('RAR4, encrypted headers and volume metadata preserve existing decoder behavior', () async {
    expect(
      await readRar5ModifiedTimes(
        koni.MemoryByteSource(
          Uint8List.fromList([0x52, 0x61, 0x72, 0x21, 0x1a, 7, 0, 0]),
        ),
        [],
      ),
      isNull,
    );
    expect(
      await read(
        [],
        bytes: Uint8List.fromList([
          ..._magic,
          ..._header(4, [0]),
        ]),
      ),
      isNull,
    );
    expect(await read([], bytes: _archive([], main: _header(1, [1]))), isNull);
  });
  test('unknown non-skippable structural blocks leave the existing reader in charge', () async {
    expect(
      await read(
        [],
        bytes: Uint8List.fromList([
          ..._magic,
          ..._main,
          ..._header(60, []),
          ..._end,
        ]),
      ),
      isNull,
    );
  });
  test('compressed payloads are skipped positionally without allocating or reading them', () async {
    final file = _Fixture(packedSize: 80 * 1024 * 1024);
    final fileStart = _magic.length + _main.length;
    final endStart = fileStart + file.header.length + file.size;
    final source = _SparseSource(endStart + _end.length, {
      0: Uint8List.fromList(_magic),
      8: _main,
      fileStart: file.header,
      endStart: _end,
    });
    expect(await readRar5ModifiedTimes(source, [file.entry]), [file.time]);
    expect(source.maximumRead, lessThan(1024));
    expect(source.closed, isFalse);
  });
  test(
    'total metadata budget prevents an unbounded sequence of skippable headers',
    () async {
      final block = _header(60, List.filled(2 * 1024 * 1024 - 16, 0), flags: 4);
      var next = 8 + _main.length;
      final regions = <int, Uint8List>{0: Uint8List.fromList(_magic), 8: _main};
      for (var i = 0; i < 9; i++) {
        regions[next] = block;
        next += block.length;
      }
      regions[next] = _end;
      final source = _SparseSource(next + _end.length, regions);
      await expectLater(readRar5ModifiedTimes(source, []), corrupt);
      expect(source.maximumRead, lessThanOrEqualTo(2 * 1024 * 1024));
      expect(source.closed, isFalse);
    },
  );
  test('cancellation leaves the borrowed source open', () async {
    final source = _SparseSource(8, {0: Uint8List.fromList(_magic)});
    await expectLater(
      readRar5ModifiedTimes(source, [], isCancelled: () => true),
      corrupt,
    );
    expect(source.closed, isFalse);
    expect(source.maximumRead, 0);
  });
  test(
    'public viewer integrates the time overlay and still validates payload CRC',
    () async {
      final file = _Fixture(name: 'report.txt');
      final archive = await openViewerArchive(
        _archive([file]),
        name: 'example.rar',
      );
      try {
        expect(archive.members.single.modified, file.time);
        expect(await archive.readMember(archive.members.single), file.payload);
      } finally {
        await archive.close();
      }
      final bytes = _archive([file]);
      bytes[8 + _main.length + file.header.length] ^= 1;
      final damaged = await openViewerArchive(bytes, name: 'example.rar');
      try {
        await expectLater(damaged.readMember(damaged.members.single), corrupt);
      } finally {
        await damaged.close();
      }
    },
  );

  test(
    'unmodified vendor compressed RAR5 exposes precise UTC time and content',
    () async {
      final archive = await openViewerArchive(
        rarPlainMetadataFixture(),
        name: 'vendor.rar',
      );
      try {
        expect(archive.members.single.name, 'precise-雪.txt');
        expect(archive.members.single.modified, rarMetadataFixtureTime);
        expect(archive.members.single.posixMode, 0x1a0);
        expect(
          utf8.decode(await archive.readMember(archive.members.single)),
          rarMetadataFixtureText,
        );
      } finally {
        await archive.close();
      }
    },
  );
  test('member-encrypted RAR5 overlays only visible metadata and retains password handling', () async {
    final bytes = rarEncryptedMetadataFixture();
    final locked = await openViewerArchive(bytes, name: 'encrypted.rar');
    try {
      expect(locked.members.single.modified, rarMetadataFixtureTime);
      expect(locked.members.single.isEncrypted, isTrue);
      await expectLater(
        locked.readMember(locked.members.single),
        throwsA(isA<ArchivePasswordRequiredException>()),
      );
    } finally {
      await locked.close();
    }
    final opened = await openViewerArchive(
      bytes,
      name: 'encrypted.rar',
      password: rarMetadataFixturePassword,
    );
    try {
      expect(opened.members.single.modified, rarMetadataFixtureTime);
      expect(
        utf8.decode(await opened.readMember(opened.members.single)),
        rarMetadataFixtureText,
      );
    } finally {
      await opened.close();
    }
    final wrong = await openViewerArchive(
      bytes,
      name: 'encrypted.rar',
      password: 'wrong-fixture-password',
    );
    try {
      await expectLater(
        wrong.readMember(wrong.members.single),
        throwsA(
          isA<ArchivePasswordRequiredException>().having(
            (e) => e.wrongPassword,
            'wrongPassword',
            isTrue,
          ),
        ),
      );
    } finally {
      await wrong.close();
    }
  });
  test('encrypted RAR5 headers stay with the password decoder', () async {
    final bytes = rarHiddenMetadataFixture();
    await expectLater(
      openViewerArchive(bytes, name: 'hidden.rar'),
      throwsA(isA<ArchivePasswordRequiredException>()),
    );
    await expectLater(
      openViewerArchive(
        bytes,
        name: 'hidden.rar',
        password: 'wrong-fixture-password',
      ),
      throwsA(
        isA<ArchivePasswordRequiredException>().having(
          (e) => e.wrongPassword,
          'wrongPassword',
          isTrue,
        ),
      ),
    );
    final opened = await openViewerArchive(
      bytes,
      name: 'hidden.rar',
      password: rarMetadataFixturePassword,
    );
    try {
      expect(opened.members.single.name, 'precise-雪.txt');
      expect(
        utf8.decode(await opened.readMember(opened.members.single)),
        rarMetadataFixtureText,
      );
    } finally {
      await opened.close();
    }
  });
}
