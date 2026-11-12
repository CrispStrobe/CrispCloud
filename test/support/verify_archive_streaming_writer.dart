/// Standalone VM verification; no Flutter engine or package resolution needed.
/// dart --packages=.dart_tool/package_config.json test/support/verify_archive_streaming_writer.dart [--oracle] [--large] [--zip64-large]
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:crisp_cloud/models/archive_endpoint.dart';
import 'package:crisp_cloud/services/archive_compression_writer.dart';
import 'package:crisp_cloud/services/archive_streaming_writer.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/archive_write_model.dart';

void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> _reject(Future<void> Function() work, String description) async {
  try {
    await work();
  } on ArchiveViewException {
    return;
  }
  throw StateError('Expected rejection: $description');
}

final _modified = DateTime.utc(2026, 11, 12, 1, 2, 3);

ArchiveWriteEntry _entry(String path, List<int> data, {int mode = 0x1a0}) =>
    ArchiveWriteEntry(
      path: path,
      isDirectory: false,
      size: data.length,
      modified: _modified,
      mode: mode,
      readChunks: () async* {
        for (var at = 0; at < data.length; at += 333333) {
          yield data.sublist(at, min(at + 333333, data.length));
        }
      },
    );

Future<Uint8List> _packed(
  ArchiveEndpointFormat format,
  List<ArchiveWriteEntry> entries, {
  int level = 6,
  Uint8List? gzipHeader,
}) async {
  final output = BytesBuilder(copy: false);
  await writeStreamingArchiveEntries(
    format,
    entries,
    sink: (bytes) async {
      require(bytes.length <= 256 * 1024, 'Unbounded writer output chunk');
      output.add(bytes);
    },
    maxOutputBytes: kArchiveStreamingLimit,
    level: level,
    gzipHeader: gzipHeader,
  );
  return output.takeBytes();
}

Future<void> verifyArchiveStreamingRoundTrips({bool oracle = false}) async {
  final random = Random(314159);
  final randomData = Uint8List.fromList(
    List.generate(700003, (_) => random.nextInt(256)),
  );
  final repeated = Uint8List.fromList(
    List.generate(900017, (index) => index % 251),
  );
  final entries = [
    _entry('docs/Grüße.txt', randomData),
    _entry('repeated.bin', repeated, mode: 0x1ed),
    _entry('empty.txt', []),
    ArchiveWriteEntry(
      path: 'empty-dir',
      isDirectory: true,
      size: 0,
      mode: 0x1e8,
      modified: _modified,
    ),
  ];
  final directory = await Directory.systemTemp.createTemp(
    'crisp-writer-check-',
  );
  try {
    final cases = [
      (ArchiveEndpointFormat.zip, 'deflated.zip', 6),
      (ArchiveEndpointFormat.zip, 'stored.zip', 0),
      (ArchiveEndpointFormat.sevenZip, 'compressed.7z', 6),
      (ArchiveEndpointFormat.sevenZip, 'fast.7z', 1),
      (ArchiveEndpointFormat.sevenZip, 'maximum.7z', 9),
      (ArchiveEndpointFormat.sevenZip, 'stored.7z', 0),
      (ArchiveEndpointFormat.tar, 'plain.tar', 6),
      (ArchiveEndpointFormat.tarGzip, 'compressed.tgz', 6),
    ];
    final manifest = <Map<String, Object?>>[];
    for (final (format, name, level) in cases) {
      final packed = await _packed(format, entries, level: level);
      final archive = await openViewerArchive(packed, name: name);
      try {
        require(archive.members.length == 4, '$name namespace length');
        for (final entry in entries) {
          final member = archive.members.singleWhere(
            (m) => m.name == entry.path,
          );
          require(member.isFile != entry.isDirectory, '$name member kind');
          require(member.size == entry.size, '$name member size');
          require(
            member.modified?.toUtc() == _modified,
            '$name modification time',
          );
          require(
            (member.posixMode! & 0xfff) == entry.mode,
            '$name POSIX mode',
          );
          if (!entry.isDirectory) {
            final actual = await archive.readMember(member);
            final expected = await entry.read();
            require(
              sha256.convert(actual) == sha256.convert(expected),
              '$name content',
            );
          }
        }
      } finally {
        await archive.close();
      }
      if (oracle) {
        await File('${directory.path}/$name').writeAsBytes(packed);
        manifest.add({
          'archive': name,
          'members': [
            for (final entry in entries)
              {
                'path': entry.path,
                'size': entry.size,
                'directory': entry.isDirectory,
                'mode': entry.mode,
                'mtime': _modified.millisecondsSinceEpoch ~/ 1000,
                if (!entry.isDirectory)
                  'sha256': sha256.convert(await entry.read()).toString(),
              },
          ],
        });
      }
    }
    final originalHeader = Uint8List.fromList([
      0x1f,
      0x8b,
      8,
      0x18,
      0x78,
      0x56,
      0x34,
      0x12,
      0,
      3,
      ...latin1.encode('original-name.tar'),
      0,
      ...latin1.encode('retained comment'),
      0,
    ]);
    final gzipBytes = await _packed(ArchiveEndpointFormat.gzip, [
      _entry('data.bin', repeated),
    ], gzipHeader: originalHeader);
    require(
      base64.encode(archiveGzipHeader(gzipBytes)) ==
          base64.encode(originalHeader),
      'Gzip header preservation',
    );
    require(
      sha256.convert(gzip.decode(gzipBytes)) == sha256.convert(repeated),
      'Gzip payload',
    );
    if (oracle) await _oracle(directory, manifest);
  } finally {
    await directory.delete(recursive: true);
  }
}

Future<void> verifyArchiveStreamingGuards() async {
  for (final format in const [
    ArchiveEndpointFormat.zip,
    ArchiveEndpointFormat.sevenZip,
    ArchiveEndpointFormat.tarGzip,
  ]) {
    var reads = 0, writes = 0;
    ArchiveWriteEntry entry(String path, int size) => ArchiveWriteEntry(
      path: path,
      isDirectory: false,
      size: size,
      readChunks: () async* {
        reads++;
        yield [1, 2];
      },
    );
    Future<void> pack(List<ArchiveWriteEntry> entries, {String? password}) =>
        writeStreamingArchiveEntries(
          format,
          entries,
          sink: (_) async => writes++,
          maxOutputBytes: kArchiveStreamingLimit,
          password: password,
        );
    await _reject(() => pack([entry('../escape', 2)]), 'unsafe path');
    await _reject(
      () => pack([entry('huge', kArchiveStreamingLimit + 1)]),
      'logical bound',
    );
    await _reject(
      () => pack([entry('protected', 2)], password: 'secret'),
      'encryption fallback',
    );
    require(reads == 0 && writes == 0, 'Rejected before read or write');
    await _reject(() => pack([entry('short', 3)]), 'truncated source');
    await _reject(() => pack([entry('growing', 1)]), 'growing source');
    var cancelled = false, sourceClosed = false;
    final cancelledEntry = ArchiveWriteEntry(
      path: 'cancel.bin',
      isDirectory: false,
      size: 512 * 1024,
      readChunks: () async* {
        try {
          yield Uint8List(256 * 1024);
          cancelled = true;
          yield Uint8List(256 * 1024);
        } finally {
          sourceClosed = true;
        }
      },
    );
    await _reject(
      () => writeStreamingArchiveEntries(
        format,
        [cancelledEntry],
        sink: (_) async {},
        maxOutputBytes: kArchiveStreamingLimit,
        isCancelled: () => cancelled,
      ),
      'cancellation',
    );
    require(sourceClosed, 'Cancelled source stream was closed');
    await _reject(
      () => writeStreamingArchiveEntries(
        format,
        [
          _entry('limit', [1, 2, 3]),
        ],
        sink: (_) async {},
        maxOutputBytes: 10,
      ),
      'packed output bound',
    );
  }
  var sourceRead = false;
  final blocked = Completer<void>();
  final sinkEntered = Completer<void>();
  final writing = writeStreamingArchiveEntries(
    ArchiveEndpointFormat.zip,
    [
      ArchiveWriteEntry(
        path: 'backpressure',
        isDirectory: false,
        size: 1,
        readChunks: () async* {
          sourceRead = true;
          yield [42];
        },
      ),
    ],
    sink: (_) async {
      if (!sinkEntered.isCompleted) sinkEntered.complete();
      await blocked.future;
    },
    maxOutputBytes: 4096,
  );
  await sinkEntered.future;
  await Future<void>.delayed(Duration.zero);
  require(!sourceRead, 'Writer consumed source behind a blocked sink');
  blocked.complete();
  await writing;
}

Future<void> verifyArchiveStreamingZip64({bool oracle = false}) async {
  final packed = await _packed(ArchiveEndpointFormat.zip, [
    for (var index = 0; index < 65536; index++)
      ArchiveWriteEntry(path: 'd$index', isDirectory: true, size: 0),
  ]);
  final footer = ByteData.sublistView(packed);
  require(
    footer.getUint32(packed.length - 42, Endian.little) == 0x07064b50,
    'ZIP64 locator',
  );
  require(
    footer.getUint64(packed.length - 98 + 32, Endian.little) == 65536,
    'ZIP64 count',
  );
  if (oracle) {
    final directory = await Directory.systemTemp.createTemp(
      'crisp-zip64-check-',
    );
    try {
      final file = File('${directory.path}/zip64.zip');
      await file.writeAsBytes(packed);
      final result = await Process.run('python3', [
        '-c',
        'import sys,zipfile; z=zipfile.ZipFile(sys.argv[1]); assert len(z.infolist())==65536; assert z.testzip() is None; print("PASS ZIP64 65536 entries")',
        file.path,
      ]);
      require(result.exitCode == 0, '${result.stderr}');
      stdout.write(result.stdout);
    } finally {
      await directory.delete(recursive: true);
    }
  }
  final firstHeader = BytesBuilder();
  final entry = ArchiveWriteEntry(
    path: 'over-4g.bin',
    isDirectory: false,
    size: 0x100000001,
    readChunks: () async* {
      throw const ArchiveViewException('End preflight probe');
    },
  );
  await _reject(
    () => writeStreamingArchiveEntries(
      ArchiveEndpointFormat.zip,
      [entry],
      sink: (bytes) async => firstHeader.add(bytes),
      maxOutputBytes: kArchiveStreamingLimit,
    ),
    'ZIP64 entry header preflight probe',
  );
  final local = ByteData.sublistView(firstHeader.takeBytes());
  require(local.getUint16(4, Endian.little) == 45, 'ZIP64 version');
  require(
    local.getUint32(22, Endian.little) == 0xffffffff,
    'ZIP64 local size marker',
  );
}

Future<void> verifyArchiveStreamingLarge({
  bool oracle = false,
  int length = 2 * 1024 * 1024 * 1024 + 17,
  List<ArchiveEndpointFormat>? formats,
}) async {
  final block = Uint8List(256 * 1024);
  final directory = await Directory.systemTemp.createTemp(
    'crisp-large-writer-',
  );
  try {
    final manifest = <Map<String, Object?>>[];
    for (final (format, name) in [
      (ArchiveEndpointFormat.zip, 'large.zip'),
      (ArchiveEndpointFormat.tarGzip, 'large.tgz'),
      (ArchiveEndpointFormat.sevenZip, 'large.7z'),
    ]) {
      if (formats != null && !formats.contains(format)) continue;
      var readBytes = 0, maxChunk = 0;
      final originalRss = ProcessInfo.currentRss;
      var peakRss = originalRss;
      final timer = Timer.periodic(const Duration(milliseconds: 20), (_) {
        peakRss = max(peakRss, ProcessInfo.currentRss);
      });
      final file = File('${directory.path}/$name');
      final output = await file.open(mode: FileMode.write);
      final watch = Stopwatch()..start();
      try {
        await writeStreamingArchiveEntries(
          format,
          [
            ArchiveWriteEntry(
              path: 'large.bin',
              isDirectory: false,
              size: length,
              modified: _modified,
              mode: 0x1a4,
              readChunks: () async* {
                while (readBytes < length) {
                  final take = min(block.length, length - readBytes);
                  readBytes += take;
                  yield Uint8List.sublistView(block, 0, take);
                }
              },
            ),
          ],
          sink: (bytes) async {
            maxChunk = max(maxChunk, bytes.length);
            await output.writeFrom(bytes);
          },
          maxOutputBytes: kArchiveStreamingLimit,
        );
      } finally {
        timer.cancel();
        await output.close();
      }
      require(readBytes == length, '$name did not consume the >2GiB source');
      require(maxChunk <= 256 * 1024, '$name unbounded output');
      // A regression to whole-file buffering cannot fit this bound.
      require(
        peakRss - originalRss < 384 * 1024 * 1024,
        '$name memory grew with payload',
      );
      stdout.writeln(
        'PASS $name: $readBytes payload bytes, ${await file.length()} packed bytes, ${watch.elapsedMilliseconds} ms, RSS growth ${peakRss - originalRss}, max chunk $maxChunk',
      );
      manifest.add({
        'archive': name,
        'members': [
          {
            'path': 'large.bin',
            'size': length,
            'directory': false,
            'mode': 0x1a4,
            'mtime': _modified.millisecondsSinceEpoch ~/ 1000,
            'zeros': true,
          },
        ],
      });
    }
    if (oracle) await _oracle(directory, manifest);
  } finally {
    await directory.delete(recursive: true);
  }
}

Future<void> _oracle(
  Directory directory,
  List<Map<String, Object?>> cases,
) async {
  final manifest = File('${directory.path}/manifest.json');
  await manifest.writeAsString(jsonEncode(cases));
  final result = await Process.run('python3', [
    'test/support/check_archive_streaming_writer.py',
    directory.path,
  ]);
  require(
    result.exitCode == 0,
    'Independent archive verification failed: ${result.stdout}\n${result.stderr}',
  );
  stdout.write(result.stdout);
}

Future<void> main(List<String> args) async {
  final oracle = args.contains('--oracle');
  await verifyArchiveStreamingRoundTrips(oracle: oracle);
  stdout.writeln(
    'PASS streamed ZIP/7z/TAR/TGZ/GZIP content and metadata round trips',
  );
  await verifyArchiveStreamingGuards();
  stdout.writeln('PASS size/path/encryption/cancellation/backpressure guards');
  await verifyArchiveStreamingZip64(oracle: oracle);
  stdout.writeln('PASS ZIP64 record/count and >4GiB member preflight');
  if (args.contains('--large')) {
    await verifyArchiveStreamingLarge(oracle: oracle);
  }
  if (args.contains('--zip64-large')) {
    await verifyArchiveStreamingLarge(
      oracle: oracle,
      length: 4 * 1024 * 1024 * 1024 + 17,
      formats: [ArchiveEndpointFormat.zip],
    );
  }
}
