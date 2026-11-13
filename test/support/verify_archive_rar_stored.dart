/// Offline VM probe for the independent RAR5 Store profile.
/// dart --packages=.dart_tool/package_config.json test/support/verify_archive_rar_stored.dart [--oracle] [--large]
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:crypto/crypto.dart';
import 'package:crisp_cloud/services/archive_rar_stored_format.dart';
import 'package:crisp_cloud/services/archive_rar_stored_reader.dart';
import 'package:crisp_cloud/services/archive_rar_stored_writer.dart';
import 'package:crisp_cloud/services/archive_streaming_unsupported.dart';
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:crisp_cloud/services/archive_write_model.dart';
import 'package:koni_archive/koni_archive.dart' as koni;
import 'package:koni_archive/io.dart' as koni_io;

void _require(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> _reject(Future<void> Function() work, String message) async {
  try {
    await work();
  } on ArchiveViewException {
    return;
  }
  throw StateError('Expected RAR rejection: $message');
}

final _modified = DateTime.utc(2026, 11, 13, 1, 2, 3, 123, 456);

ArchiveWriteEntry _entry(
  String name,
  List<int> data, {
  DateTime? modified,
  int? mode = 0x1a4,
  Map<String, Object?> attributes = const {},
}) => ArchiveWriteEntry(
  path: name,
  isDirectory: false,
  size: data.length,
  modified: modified ?? _modified,
  mode: mode,
  attributes: attributes,
  readChunks: () async* {
    for (var at = 0; at < data.length; at += 17003) {
      final end = at + 17003 < data.length ? at + 17003 : data.length;
      yield Uint8List.fromList(data.sublist(at, end));
    }
  },
);

Future<Uint8List> _pack(
  List<ArchiveWriteEntry> entries, {
  ArchiveRewriteInspection? source,
}) async {
  final bytes = BytesBuilder(copy: false);
  await writeStoredRarArchive(
    entries,
    sink: (chunk) async {
      _require(chunk.length <= rarStoredChunkBytes, 'Unbounded RAR sink chunk');
      bytes.add(chunk);
    },
    maxOutputBytes: kArchiveStreamingLimit,
    source: source,
  );
  return bytes.takeBytes();
}

Future<void> verifyRarStoredRoundTrips({bool oracle = false}) async {
  final payload = Uint8List.fromList(
    List.generate(700003, (i) => (i * 37) % 251),
  );
  final entries = [
    _entry('docs/Grüße 🚀.txt', payload, mode: 0x1e8),
    _entry(r"literal $(); 'quote' [a].txt", [1, 2, 3]),
    _entry('empty.bin', []),
    ArchiveWriteEntry(
      path: 'empty-dir',
      isDirectory: true,
      size: 0,
      mode: 0x1ed,
      modified: _modified,
    ),
    _entry('historical.txt', [
      9,
    ], modified: DateTime.utc(1900, 1, 2, 3, 4, 5, 678, 901)),
  ];
  final bytes = await _pack(entries);
  final source = _MemorySource(bytes);
  final inspection = await inspectStoredRarRewriteSource(source);
  _require(
    inspection.supported && source.closes == 0,
    'Inspection did not borrow/preserve source',
  );
  verifyStoredRarPreservation(entries, inspection);
  source.readBytes = 0;
  final opened = await openStoredRarArchive(source);
  _require(source.readBytes < 8192, 'RAR indexing read member payload');
  try {
    _require(
      opened.maxStreamingMemberBytes == kArchiveStreamingLimit,
      'Stream allowance missing',
    );
    _require(opened.members.length == entries.length, 'Wrong RAR member count');
    for (var index = 0; index < entries.length; index++) {
      final wanted = entries[index];
      final actual = opened.members[index];
      _require(
        actual.name == wanted.path &&
            actual.size == wanted.size &&
            actual.isFile != wanted.isDirectory &&
            actual.modified == wanted.modified &&
            (actual.posixMode! & 0xfff) == wanted.mode,
        'RAR member metadata mismatch',
      );
      if (actual.isFile) {
        _require(
          await sha256.bind(opened.openMember(actual)).single ==
              await sha256.bind(wanted.openRead()).single,
          'RAR payload hash mismatch',
        );
      }
    }
  } finally {
    await opened.close();
  }
  _require(source.closes == 1, 'Owned RAR source was not closed exactly once');

  final rewritten = [
    _entry(
      'renamed/Grüße 🚀.txt',
      payload,
      mode: 0x1c0,
      attributes: inspection.attributes[entries.first.path]!,
    ),
    _entry('empty.bin', [
      4,
      5,
      6,
    ], attributes: inspection.attributes['empty.bin']!),
    ArchiveWriteEntry(
      path: 'new-directory',
      isDirectory: true,
      size: 0,
      mode: 0x1e8,
    ),
    _entry('new-directory/added.txt', [7, 8]),
  ];
  final changed = await _pack(rewritten, source: inspection);
  verifyStoredRarPreservation(
    rewritten,
    await inspectStoredRarRewriteSource(_MemorySource(changed)),
    source: inspection,
  );
  final changedArchive = await openStoredRarArchive(_MemorySource(changed));
  try {
    _require(
      changedArchive.members.map((e) => e.name).join('|') ==
          rewritten.map((e) => e.path).join('|'),
      'RAR rename/add/delete namespace mismatch',
    );
    for (var index = 0; index < rewritten.length; index++) {
      if (!rewritten[index].isDirectory) {
        _require(
          await sha256
                  .bind(
                    changedArchive.openMember(changedArchive.members[index]),
                  )
                  .single ==
              await sha256.bind(rewritten[index].openRead()).single,
          'RAR replacement mismatch',
        );
      }
    }
  } finally {
    await changedArchive.close();
  }
  if (oracle) {
    final directory = await Directory.systemTemp.createTemp(
      'rar-store-oracle-',
    );
    try {
      for (final item in [
        (bytes, entries, 'created'),
        (changed, rewritten, 'rewritten'),
      ]) {
        final file = File('${directory.path}/${item.$3}.rar');
        await file.writeAsBytes(item.$1);
        await _oracle(file, await _manifest(item.$2));
      }
    } finally {
      await directory.delete(recursive: true);
    }
  }
  stdout.writeln(
    'PASS RAR5 Store creation, rename/add/replace/delete, Unicode, empty entries, exact modes/times',
  );
}

Future<void> verifyRarStoredMetadata({bool oracle = false}) async {
  final seconds = _modified.microsecondsSinceEpoch ~/ 1000000;
  final exact = RarStoredTimes(
    0x1f,
    {
      'mtime': BigInt.from(seconds),
      'ctime': BigInt.from(seconds - 10),
      'atime': BigInt.from(seconds + 10),
    },
    {'mtime': 123456789, 'ctime': 987654321, 'atime': 100000001},
  );
  final cases = [
    exact,
    RarStoredTimes(0xe, {
      'mtime':
          BigInt.from(_modified.microsecondsSinceEpoch) * BigInt.from(10) +
          BigInt.from(116444736000000007),
      'ctime': BigInt.from(130000000000000003),
      'atime': BigInt.from(130000000000000009),
    }, const {}),
  ];
  for (final times in cases) {
    final bytes = _manual(extra: rarStoredExtra(3, times.encode()));
    final source = _MemorySource(bytes);
    final before = await inspectStoredRarRewriteSource(source);
    _require(
      before.supported,
      'Known time metadata was refused: ${before.reason}',
    );
    final archive = await openStoredRarArchive(source);
    final entry = archive.members.single;
    try {
      final entries = [
        _entry(
          'renamed.txt',
          [8, 7, 6],
          modified: entry.modified!.toLocal(),
          mode: entry.posixMode,
          attributes: before.attributes[entry.name]!,
        ),
      ];
      final output = await _pack(entries, source: before);
      final after = await inspectStoredRarRewriteSource(_MemorySource(output));
      _require(after.supported, 'Rewritten time metadata was refused');
      _require(
        jsonEncode(after.attributes['renamed.txt']!['rar5.times']) ==
            jsonEncode(before.attributes[entry.name]!['rar5.times']),
        'Submicrosecond/creation/access time lost',
      );
      final verificationEntries = [
        ArchiveWriteEntry(
          path: entries.single.path,
          isDirectory: false,
          size: entries.single.size,
          modified: entries.single.modified,
          mode: entries.single.mode,
          attributes: entries.single.attributes,
          readChunks: () =>
              throw StateError('Metadata verification read payload'),
        ),
      ];
      verifyStoredRarPreservation(verificationEntries, after, source: before);
      final actual = after.attributes['renamed.txt']!;
      for (final change in <String, Object?>{
        'rar5.hostOs': 0,
        'rar5.attributes': (actual['rar5.attributes']! as int) ^ 1,
        'rar5.compression': 0x400,
        'rar5.hasCrc': false,
        'rar5.trailingSlash': true,
        'rar5.headerMtime': (actual['rar5.headerMtime']! as int) + 1,
        'rar5.times': {
          ...actual['rar5.times']! as Map,
          'ctime': (times.values['ctime']! + BigInt.one).toString(),
        },
      }.entries) {
        await _reject(() async {
          verifyStoredRarPreservation(
            verificationEntries,
            ArchiveRewriteInspection(
              container: after.container,
              attributes: {
                'renamed.txt': {...actual, change.key: change.value},
              },
            ),
            source: before,
          );
        }, 'Metadata verifier must detect changed ${change.key}');
      }
      await _reject(() async {
        verifyStoredRarPreservation(
          verificationEntries,
          ArchiveRewriteInspection(
            container: {...after.container, 'unexpected': true},
            attributes: after.attributes,
          ),
          source: before,
        );
      }, 'Metadata verifier must detect changed container profile');
      if (oracle) {
        final directory = await Directory.systemTemp.createTemp(
          'rar-store-meta-',
        );
        try {
          final file = File('${directory.path}/timestamps-${times.flags}.rar');
          await file.writeAsBytes(output);
          await _oracle(file, await _manifest(entries));
        } finally {
          await directory.delete(recursive: true);
        }
      }
    } finally {
      await archive.close();
    }
  }
  final before = await inspectStoredRarRewriteSource(
    _MemorySource(_manual(extra: rarStoredExtra(3, exact.encode()))),
  );
  final changedTime = DateTime.utc(2026, 11, 14, 1, 2, 3, 444, 555);
  final output = await _pack([
    _entry(
      'file.txt',
      [1, 2, 3],
      modified: changedTime,
      attributes: before.attributes['file.txt']!,
    ),
  ], source: before);
  final after = await inspectStoredRarRewriteSource(_MemorySource(output));
  final oldTimes = before.attributes['file.txt']!['rar5.times']! as Map;
  final newTimes = after.attributes['file.txt']!['rar5.times']! as Map;
  _require(
    newTimes['mtimeNs'] == 444555000 &&
        newTimes['ctimeNs'] == oldTimes['ctimeNs'] &&
        newTimes['atimeNs'] == oldTimes['atimeNs'],
    'Mtime edit changed unrelated exact timestamps',
  );
  await _reject(() async {
    await _pack([
      _entry(
        'file.txt',
        [1, 2, 3],
        modified: DateTime.utc(1900),
        attributes: before.attributes['file.txt']!,
      ),
    ], source: before);
  }, 'Changing Unix time representation must not discard creation nanoseconds');
  final windows = _manual(host: 0, mode: 0x21);
  final windowsSource = _MemorySource(windows);
  final windowsPolicy = await inspectStoredRarRewriteSource(windowsSource);
  final windowsArchive = await openStoredRarArchive(windowsSource);
  try {
    final rewritten = await _pack([
      _entry(
        'windows.txt',
        [1, 2, 3],
        mode: null,
        modified: windowsArchive.members.single.modified,
        attributes: windowsPolicy.attributes['file.txt']!,
      ),
    ], source: windowsPolicy);
    final policy = await inspectStoredRarRewriteSource(
      _MemorySource(rewritten),
    );
    _require(
      policy.attributes['windows.txt']!['rar5.attributes'] == 0x21,
      'Windows attributes lost',
    );
  } finally {
    await windowsArchive.close();
  }
  stdout.writeln(
    'PASS RAR5 exact timestamp/Windows attribute preservation, metadata-only verifier and explicit edits',
  );
}

Future<void> verifyRarStoredGuards() async {
  for (final bytes in [
    _manual(compression: 0x80),
    _manual(mainFlags: 4),
    _manual(mainFlags: 1),
    _manual(extra: rarStoredExtra(1, Uint8List(0))),
  ]) {
    final source = _MemorySource(bytes);
    try {
      await openStoredRarArchive(source);
      throw StateError('Unsupported RAR profile was accepted');
    } on ArchiveStreamingUnsupported {
      _require(source.closes == 1, 'Failed RAR open leaked source');
    }
    final borrowed = _MemorySource(bytes);
    final policy = await inspectStoredRarRewriteSource(borrowed);
    _require(
      !policy.supported && borrowed.closes == 0,
      'Unsupported inspection contract failed',
    );
  }
  for (final bytes in [
    _manual(mainFlags: 8),
    _manual(mainFlags: 16),
    _manual(extra: rarStoredExtra(99, Uint8List.fromList([1]))),
    _manual(service: true),
    _manual(trailing: true),
    _manual(name: '../escape'),
    _manual(mode: 0xa1ff),
    _manual(mode: 0x89a4),
  ]) {
    final policy = await inspectStoredRarRewriteSource(_MemorySource(bytes));
    _require(!policy.supported, 'Unpreservable RAR metadata was accepted');
    var emitted = 0;
    await _reject(
      () => writeStoredRarArchive(
        [
          _entry('safe.txt', [1]),
        ],
        sink: (chunk) async {
          emitted += chunk.length;
        },
        maxOutputBytes: kArchiveStreamingLimit,
        source: policy,
      ),
      'Unpreservable source rewrite',
    );
    _require(emitted == 0, 'Rejected metadata emitted output');
  }
  final good = _manual();
  final corruptHeader = Uint8List.fromList(good)..[8] ^= 1;
  await _reject(() async {
    await openStoredRarArchive(_MemorySource(corruptHeader));
  }, 'Header CRC');
  await _reject(() async {
    await openStoredRarArchive(_MemorySource(good.sublist(0, good.length - 1)));
  }, 'Truncated footer');
  final corruptBody = Uint8List.fromList(good)
    ..[good.length - rarStoredHeader(5, rarStoredVint(0)).length - 1] ^= 1;
  final damaged = await openStoredRarArchive(_MemorySource(corruptBody));
  try {
    await _reject(() async {
      await damaged.openMember(damaged.members.single).drain<void>();
    }, 'Data CRC at EOF');
  } finally {
    await damaged.close();
  }
  var reads = 0, output = 0;
  await _reject(
    () => writeStoredRarArchive(
      [
        ArchiveWriteEntry(
          path: 'too-large.bin',
          isDirectory: false,
          size: kArchiveStreamingLimit,
          readChunks: () {
            reads++;
            return const Stream.empty();
          },
        ),
      ],
      sink: (chunk) async {
        output += chunk.length;
      },
      maxOutputBytes: kArchiveStreamingLimit,
    ),
    'Size preflight',
  );
  _require(reads == 0 && output == 0, 'Oversize preflight performed IO');
  for (final data in [
    [1],
    [1, 2, 3],
  ]) {
    await _reject(() async {
      await _pack([
        ArchiveWriteEntry(
          path: 'length.bin',
          isDirectory: false,
          size: 2,
          readChunks: () => Stream.value(data),
        ),
      ]);
    }, 'Short/growing source');
  }
  var opened = 0;
  await _reject(() async {
    await _pack([
      ArchiveWriteEntry(
        path: 'changed.bin',
        isDirectory: false,
        size: 2,
        readChunks: () => Stream.value(++opened == 1 ? [1, 2] : [1, 3]),
      ),
    ]);
  }, 'Changed second pass');
  _require(opened == 2, 'Writer did not use exactly two source passes');
  var cancelled = false, closed = false;
  await _reject(
    () => writeStoredRarArchive(
      [
        ArchiveWriteEntry(
          path: 'cancel.bin',
          isDirectory: false,
          size: 1000000,
          readChunks: () async* {
            try {
              yield Uint8List(65536);
              cancelled = true;
              yield Uint8List(65536);
            } finally {
              closed = true;
            }
          },
        ),
      ],
      sink: (_) async {},
      maxOutputBytes: kArchiveStreamingLimit,
      isCancelled: () => cancelled,
    ),
    'Cancellation',
  );
  _require(closed, 'Cancelled source stream did not close');
  final borrowed = _MemorySource(good);
  await _reject(() async {
    await inspectStoredRarRewriteSource(borrowed, isCancelled: () => true);
  }, 'Inspection cancellation must propagate');
  _require(borrowed.closes == 0, 'Cancelled inspection closed borrowed source');
  var inSink = false, filePasses = 0;
  await writeStoredRarArchive(
    [
      ArchiveWriteEntry(
        path: 'bounded.bin',
        isDirectory: false,
        size: 700003,
        readChunks: () {
          filePasses++;
          return Stream.value(Uint8List(700003));
        },
      ),
      ArchiveWriteEntry(path: 'directory', isDirectory: true, size: 0),
    ],
    sink: (chunk) async {
      _require(
        !inSink && chunk.length <= rarStoredChunkBytes,
        'Sink backpressure/chunk bound failed',
      );
      inSink = true;
      await Future<void>.delayed(Duration.zero);
      inSink = false;
    },
    maxOutputBytes: kArchiveStreamingLimit,
  );
  _require(filePasses == 2, 'Directory caused a source pass');
  stdout.writeln(
    'PASS RAR5 fallback, metadata/path refusal, corruption, bounds, changed source, cancellation/backpressure',
  );
}

Uint8List _manual({
  int mainFlags = 0,
  int compression = 0,
  int host = 1,
  int mode = 0x81a4,
  String name = 'file.txt',
  Uint8List? extra,
  bool service = false,
  bool trailing = false,
}) {
  final data = Uint8List.fromList([1, 2, 3]);
  final nameBytes = utf8.encode(name);
  final fields = BytesBuilder(copy: false)
    ..add(rarStoredVint(6))
    ..add(rarStoredVint(data.length))
    ..add(rarStoredVint(mode))
    ..add(rarStoredUint32(_modified.microsecondsSinceEpoch ~/ 1000000))
    ..add(rarStoredUint32(getCrc32(data)))
    ..add(rarStoredVint(compression))
    ..add(rarStoredVint(host))
    ..add(rarStoredVint(nameBytes.length))
    ..add(nameBytes);
  return (BytesBuilder(copy: false)
        ..add(rarStoredSignature)
        ..add(rarStoredHeader(1, rarStoredVint(mainFlags)))
        ..add(
          rarStoredHeader(
            2,
            fields.takeBytes(),
            extra: extra,
            dataSize: data.length,
          ),
        )
        ..add(data)
        ..add(service ? rarStoredHeader(3, Uint8List(0)) : [])
        ..add(rarStoredHeader(5, rarStoredVint(0)))
        ..add(trailing ? [0xff] : []))
      .takeBytes();
}

Future<Map<String, Object?>> _manifest(List<ArchiveWriteEntry> entries) async =>
    {
      for (final entry in entries)
        entry.path: {
          'size': entry.size,
          'directory': entry.isDirectory,
          'mode': entry.mode,
          'mtimeMicros': entry.modified?.microsecondsSinceEpoch,
          if (entry.attributes['rar5.times'] != null)
            'rar5Times': entry.attributes['rar5.times'],
          if (!entry.isDirectory)
            'sha256': (await sha256.bind(entry.openRead()).single).toString(),
        },
    };

Future<void> _oracle(File file, Map<String, Object?> expected) async {
  final manifest = File('${file.path}.json');
  await manifest.writeAsString(jsonEncode(expected));
  final result = await Process.run('python3', [
    'test/support/check_archive_rar_stored.py',
    file.path,
    manifest.path,
  ]);
  if (result.exitCode != 0) {
    throw StateError(
      'RAR libarchive oracle failed: ${result.stdout}\n${result.stderr}',
    );
  }
  stdout.write(result.stdout);
}

class _MemorySource implements koni.ByteSource {
  _MemorySource(List<int> bytes) : bytes = Uint8List.fromList(bytes);
  final Uint8List bytes;
  int closes = 0, readBytes = 0;
  @override
  int get length => bytes.length;
  @override
  String get name => 'probe.rar';
  @override
  Future<Uint8List> read(int offset, int count) async {
    if (closes != 0) throw StateError('Source is closed');
    _require(count <= rarStoredMaxHeaderBytes, 'Unbounded RAR positional read');
    readBytes += count;
    return Uint8List.fromList(bytes.sublist(offset, offset + count));
  }

  @override
  Future<void> close() async {
    closes++;
  }
}

Future<void> verifyRarStoredLarge({bool oracle = false}) async {
  const size = 2 * 1024 * 1024 * 1024 + 17;
  final directory = await Directory.systemTemp.createTemp('rar-store-large-');
  final file = File('${directory.path}/large.rar');
  final entry = ArchiveWriteEntry(
    path: 'large.bin',
    isDirectory: false,
    size: size,
    modified: _modified,
    mode: 0x1a4,
    readChunks: () => _largePayload(size),
  );
  final entries = [
    entry,
    _entry('tail.txt', [0x55, 0xaa]),
  ];
  final baseline = ProcessInfo.currentRss;
  var peak = baseline, heartbeats = 0, maxChunk = 0;
  final timer = Timer.periodic(const Duration(milliseconds: 20), (_) {
    final rss = ProcessInfo.currentRss;
    if (rss > peak) peak = rss;
    heartbeats++;
  });
  final clock = Stopwatch()..start();
  try {
    final writer = await file.open(mode: FileMode.write);
    try {
      await writeStoredRarArchive(
        entries,
        sink: (chunk) async {
          if (chunk.length > maxChunk) maxChunk = chunk.length;
          await writer.writeFrom(chunk);
        },
        maxOutputBytes: kArchiveStreamingLimit,
      );
      await writer.flush();
    } finally {
      await writer.close();
    }
    final writingMilliseconds = clock.elapsedMilliseconds;
    final packedBytes = await file.length();
    _require(
      packedBytes > 0x80000000,
      'Large RAR container did not cross 2 GiB',
    );
    final source = await koni_io.FileByteSource.open(file.path);
    final policy = await inspectStoredRarRewriteSource(source);
    _require(policy.supported, 'Large RAR inspection failed');
    final archive = await openStoredRarArchive(source);
    String digest;
    try {
      _require(
        archive.members[0].size == size &&
            archive.members[1].name == 'tail.txt',
        'Large RAR sizes or following member offsets failed',
      );
      await _reject(() async {
        await archive.readMember(archive.members.first);
      }, 'Large member preview cap');
      var received = 0;
      final hash = await sha256
          .bind(
            archive
                .openMember(
                  archive.members.first,
                  maxBytes: kArchiveStreamingLimit,
                )
                .map((chunk) {
                  received += chunk.length;
                  _require(
                    chunk.length <= rarStoredChunkBytes,
                    'Large RAR read chunk too large',
                  );
                  return chunk;
                }),
          )
          .single;
      digest = hash.toString();
      _require(received == size, 'Large RAR truncated read');
      _require(
        (await archive.readMember(archive.members[1])).join(',') == '85,170',
        'Following member payload was damaged',
      );
    } finally {
      await archive.close();
    }
    final readingMilliseconds = clock.elapsedMilliseconds - writingMilliseconds;
    if (oracle) {
      await _oracle(file, {
        'large.bin': {
          'size': size,
          'directory': false,
          'mode': 0x1a4,
          'mtimeMicros': _modified.microsecondsSinceEpoch,
          'sha256': digest,
          'sentinelZeros': true,
        },
        'tail.txt': {
          'size': 2,
          'directory': false,
          'mode': 0x1a4,
          'mtimeMicros': _modified.microsecondsSinceEpoch,
          'sha256': sha256.convert([0x55, 0xaa]).toString(),
        },
      });
    }
    timer.cancel();
    _require(
      maxChunk <= rarStoredChunkBytes && peak - baseline < 512 * 1024 * 1024,
      'Large RAR writer/reader exceeded its memory budget',
    );
    stdout.writeln(
      jsonEncode({
        'result': 'PASS RAR5 Store >2 GiB',
        'memberBytes': size,
        'packedBytes': packedBytes,
        'sha256': digest,
        'writingMilliseconds': writingMilliseconds,
        'readingMilliseconds': readingMilliseconds,
        'rssBaselineBytes': baseline,
        'rssPeakBytes': peak,
        'rssGrowthBytes': peak - baseline,
        'heartbeatTicks': heartbeats,
        'maxOutputChunkBytes': maxChunk,
      }),
    );
  } finally {
    timer.cancel();
    await directory.delete(recursive: true);
  }
}

Stream<List<int>> _largePayload(int size) async* {
  final zeros = Uint8List(256 * 1024);
  var offset = 0;
  while (offset < size) {
    final count = size - offset < zeros.length ? size - offset : zeros.length;
    if (offset == 0 || offset + count == size) {
      final chunk = Uint8List(count);
      if (offset == 0) chunk[0] = 0x43;
      if (offset + count == size) chunk[count - 1] = 0xa5;
      yield chunk;
    } else {
      yield zeros;
    }
    offset += count;
  }
}

Future<void> main(List<String> args) async {
  await verifyRarStoredRoundTrips(oracle: args.contains('--oracle'));
  await verifyRarStoredMetadata(oracle: args.contains('--oracle'));
  await verifyRarStoredGuards();
  if (args.contains('--large')) {
    await verifyRarStoredLarge(oracle: args.contains('--oracle'));
  }
}
