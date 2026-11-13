/// Standalone native worker verification, without the Flutter launcher.
/// dart --packages=.dart_tool/package_config.json test/support/verify_archive_writer_worker.dart
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:crisp_cloud/models/archive_endpoint.dart';
import 'package:crisp_cloud/services/archive_compression_writer.dart';
import 'package:crisp_cloud/services/archive_dmg_reader.dart';
import 'package:crisp_cloud/services/archive_dmg_writer.dart';
import 'package:crisp_cloud/services/archive_hfs_reader.dart';
import 'package:crisp_cloud/services/archive_package_writers.dart';
import 'package:crisp_cloud/services/archive_output_spool.dart';
import 'package:crisp_cloud/services/archive_streamed_reader.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/archive_write_model.dart';
import 'package:crisp_cloud/services/archive_writer_worker.dart';
import 'package:crisp_cloud/services/archive_writer_worker_io.dart'
    show debugRunArchiveWriterWorker;
import 'package:koni_archive/koni_archive.dart' as koni;

void _require(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<Object> _failure(Future<void> action, String label) async {
  try {
    await action.timeout(const Duration(seconds: 10));
  } catch (error) {
    if (error is TimeoutException) rethrow;
    return error;
  }
  throw StateError('Expected failure: $label');
}

final _modified = DateTime.utc(2026, 11, 13, 1, 2, 4);
final _data = Uint8List.fromList(
  List.generate(700003, (index) => (index * 37) % 251),
);

ArchiveWriteEntry _entry(
  String name,
  List<int> bytes, {
  void Function()? onRead,
}) => ArchiveWriteEntry(
  path: name,
  isDirectory: false,
  size: bytes.length,
  modified: _modified,
  mode: 0x1a4,
  readChunks: () async* {
    onRead?.call();
    // Intentionally larger than the wire bound. ArchiveWriteEntry splits it.
    yield bytes;
  },
);

Future<Uint8List> _pack(
  ArchiveEndpointFormat format,
  List<ArchiveWriteEntry> entries, {
  bool streamed = true,
  int level = 6,
  String? password,
  bool encryptNames = false,
  koni.ArchiveCompression? entryCompression,
  ArchiveCpioFormat cpioFormat = ArchiveCpioFormat.newc,
  ArchiveRewriteInspection? source,
}) async {
  final output = BytesBuilder(copy: false);
  final current = Isolate.current.hashCode;
  await writeArchiveEntriesInWorker(
    format,
    entries,
    streamed: streamed,
    source: source,
    maxOutputBytes: streamed ? kArchiveStreamingLimit : 16 * 1024 * 1024,
    cpioFormat: cpioFormat,
    level: level,
    password: password,
    encryptNames: encryptNames,
    entryCompression: entryCompression,
    sink: (bytes) async {
      _require(
        Isolate.current.hashCode == current,
        'Sink left its owner isolate',
      );
      _require(bytes.length <= 256 * 1024, 'Unbounded worker output');
      output.add(bytes);
    },
  );
  return output.takeBytes();
}

Future<void> _checkBody(ViewerArchive archive, List<int> expected) async {
  try {
    final file = archive.members.singleWhere((entry) => entry.isFile);
    final actual = await archive.readMember(file);
    _require(actual.length == expected.length, 'Decoded member size differs');
    _require(
      sha256.convert(actual) == sha256.convert(expected),
      'Decoded hash differs',
    );
  } finally {
    await archive.close();
  }
}

Future<void> verifyArchiveWorkerRoundTrips() async {
  _require(supportsArchiveWriterWorker, 'Native worker unavailable');
  final current = Isolate.current.hashCode;
  for (final (format, name) in const [
    (ArchiveEndpointFormat.zip, 'data.zip'),
    (ArchiveEndpointFormat.sevenZip, 'data.7z'),
    (ArchiveEndpointFormat.tar, 'data.tar'),
    (ArchiveEndpointFormat.tarGzip, 'data.tgz'),
    (ArchiveEndpointFormat.rar, 'data.rar'),
    (ArchiveEndpointFormat.iso, 'data.iso'),
    (ArchiveEndpointFormat.dmg, 'data.dmg'),
  ]) {
    var reads = 0;
    final bytes = await _pack(format, [
      _entry(
        'Grüße.txt',
        _data,
        onRead: () {
          _require(
            Isolate.current.hashCode == current,
            'Source left its owner isolate',
          );
          reads++;
        },
      ),
      ArchiveWriteEntry(
        path: 'empty',
        isDirectory: true,
        size: 0,
        modified: _modified,
      ),
    ]);
    _require(
      reads == (format == ArchiveEndpointFormat.rar ? 2 : 1),
      '$name source pass count',
    );
    final opened = await openStreamedArchiveSource(
      koni.MemoryByteSource(bytes),
      name: name,
    );
    _require(
      opened.archive.members.where((entry) => !entry.isFile).length == 1,
      '$name empty directory',
    );
    await _checkBody(opened.archive, _data);
  }
  final raw = BytesBuilder(copy: false);
  await writeHfsArchiveInWorker(
    [_entry('data.bin', _data)],
    sink: (chunk) async {
      _require(chunk.length <= 256 * 1024, 'Unbounded HFSX output');
      raw.add(chunk);
    },
    maxOutputBytes: kArchiveStreamingLimit,
    volumeName: 'Worker volume',
  );
  final hfs = await openHfsArchiveWithMetadata(
    koni.MemoryByteSource(raw.takeBytes()),
    maxMemberBytes: kArchiveReadLimit,
  );
  _require(
    hfs.metadata.volumeName == 'Worker volume',
    'HFSX volume name changed',
  );
  await _checkBody(hfs.archive, _data);
}

Future<void> verifyArchiveWorkerBufferedOptions() async {
  for (final format in [
    ArchiveEndpointFormat.zip,
    ArchiveEndpointFormat.sevenZip,
  ]) {
    for (final method in [
      koni.ArchiveCompression.stored,
      koni.ArchiveCompression.deflate,
      if (format == ArchiveEndpointFormat.sevenZip)
        koni.ArchiveCompression.lzma2,
    ]) {
      final bytes = await _pack(
        format,
        [_entry('data.bin', _data)],
        streamed: false,
        level: method == koni.ArchiveCompression.stored ? 0 : 6,
        entryCompression: method,
        password: 'worker password',
        encryptNames: format == ArchiveEndpointFormat.sevenZip,
      );
      if (format == ArchiveEndpointFormat.zip) {
        final header = ByteData.sublistView(bytes);
        var actualMethod = header.getUint16(8, Endian.little);
        if (actualMethod == 99) {
          final start = 30 + header.getUint16(26, Endian.little);
          final end = start + header.getUint16(28, Endian.little);
          for (var at = start; at + 4 <= end;) {
            final tag = header.getUint16(at, Endian.little);
            final size = header.getUint16(at + 2, Endian.little);
            if (tag == 0x9901 && size == 7) {
              actualMethod = header.getUint16(at + 9, Endian.little);
            }
            at += 4 + size;
          }
        }
        _require(
          actualMethod == (method == koni.ArchiveCompression.stored ? 0 : 8),
          'ZIP changed the requested compression method',
        );
      }
      await _checkBody(
        await openViewerArchive(
          bytes,
          name: format == ArchiveEndpointFormat.zip ? 'data.zip' : 'data.7z',
          password: 'worker password',
        ),
        _data,
      );
    }
  }
  for (final profile in ArchiveCpioFormat.values) {
    final bytes = await _pack(
      ArchiveEndpointFormat.cpio,
      [_entry('data.bin', _data)],
      streamed: false,
      cpioFormat: profile,
    );
    await _checkBody(await openViewerArchive(bytes, name: 'data.cpio'), _data);
  }
  final gzip = BytesBuilder(copy: false);
  await writeArchiveEntriesInWorker(
    ArchiveEndpointFormat.gzip,
    [_entry('data.bin', _data)],
    sink: (chunk) async => gzip.add(chunk),
    maxOutputBytes: 4 * 1024 * 1024,
    compression: ArchiveCompressionKind.gzip,
    singlePayload: true,
    gzipHeader: Uint8List.fromList([0x1f, 0x8b, 8, 0, 4, 3, 2, 1, 0, 3]),
  );
  final packed = gzip.takeBytes();
  _require(
    packed[4] == 4 && packed[7] == 1,
    'Gzip header changed across isolate',
  );
  await _checkBody(await openViewerArchive(packed, name: 'data.gz'), _data);
}

Future<void> verifyArchiveWorkerPreservation() async {
  final original = await _pack(ArchiveEndpointFormat.dmg, [
    _entry('data.bin', _data),
  ]);
  final opened = await openStreamedDmgSource(koni.MemoryByteSource(original));
  try {
    final entries = [
      for (final member in opened.archive.members)
        ArchiveWriteEntry(
          path: member.name,
          isDirectory: !member.isFile,
          size: member.size,
          modified: member.modified,
          mode: member.posixMode,
          attributes: opened.inspection.attributes[member.name] ?? const {},
          readChunks: () => opened.archive.openMember(member),
        ),
    ];
    final rewritten = await _pack(
      ArchiveEndpointFormat.dmg,
      entries,
      source: opened.inspection,
    );
    final actual = await openStreamedDmgSource(
      koni.MemoryByteSource(rewritten),
    );
    verifyDmgRewritePreservation(
      entries,
      actual.inspection,
      source: opened.inspection,
    );
    await _checkBody(actual.archive, _data);
    final rejected = await _failure(
      writeArchiveEntriesInWorker(
        ArchiveEndpointFormat.dmg,
        entries,
        streamed: true,
        sink: (_) async => throw StateError('Forged proof reached the sink'),
        maxOutputBytes: kArchiveStreamingLimit,
        source: ArchiveRewriteInspection(
          container: {
            'dmg.profile': {'verified': true, 'hfs.profile': true},
          },
        ),
      ),
      'forged DMG preservation profile',
    );
    _require(
      rejected is ArchiveViewException,
      'Opaque profile rejection was lost',
    );
  } finally {
    await opened.archive.close();
  }
}

Future<void> verifyArchiveWorkerPauseAndBackpressure() async {
  final paused = Completer<void>();
  final resume = Completer<void>();
  var sourceChunks = 0, outputChunks = 0;
  final output = BytesBuilder(copy: false);
  final job = writeArchiveEntriesInWorker(
    ArchiveEndpointFormat.zip,
    [
      ArchiveWriteEntry(
        path: 'data.bin',
        isDirectory: false,
        size: _data.length,
        modified: _modified,
        readChunks: () async* {
          for (var offset = 0; offset < _data.length; offset += 65536) {
            sourceChunks++;
            final end = offset + 65536 < _data.length
                ? offset + 65536
                : _data.length;
            yield Uint8List.sublistView(_data, offset, end);
          }
        },
      ),
    ],
    streamed: true,
    level: 0,
    maxOutputBytes: 2 * 1024 * 1024,
    checkpoint: () async {
      if (sourceChunks >= 2 && !resume.isCompleted) {
        if (!paused.isCompleted) paused.complete();
        await resume.future;
      }
    },
    sink: (chunk) async {
      outputChunks++;
      output.add(chunk);
    },
  );
  await paused.future.timeout(const Duration(seconds: 10));
  final before = (sourceChunks, outputChunks);
  await Future<void>.delayed(const Duration(milliseconds: 30));
  _require(
    (sourceChunks, outputChunks) == before,
    'Paused worker continued pulling or emitting',
  );
  resume.complete();
  await job;
  await _checkBody(
    await openViewerArchive(output.takeBytes(), name: 'data.zip'),
    _data,
  );

  final waiting = Completer<void>();
  final release = Completer<void>();
  var calls = 0, sourceReads = 0;
  final blocked = writeArchiveEntriesInWorker(
    ArchiveEndpointFormat.tar,
    [_entry('data.bin', _data, onRead: () => sourceReads++)],
    streamed: true,
    maxOutputBytes: 2 * 1024 * 1024,
    sink: (_) async {
      calls++;
      if (calls == 1) {
        waiting.complete();
        await release.future;
      }
    },
  );
  await waiting.future.timeout(const Duration(seconds: 10));
  await Future<void>.delayed(const Duration(milliseconds: 30));
  _require(
    calls == 1 && sourceReads == 0,
    'Worker ignored output backpressure',
  );
  release.complete();
  await blocked;
}

Future<void> verifyArchiveWorkerCancellation() async {
  final started = Completer<void>();
  final cancelled = Completer<void>();
  final abort = Completer<void>();
  final never = Completer<void>();
  final source = StreamController<List<int>>(
    onListen: started.complete,
    onCancel: () {
      if (!cancelled.isCompleted) cancelled.complete();
      return never.future;
    },
  );
  final result = _failure(
    writeArchiveEntriesInWorker(
      ArchiveEndpointFormat.sevenZip,
      [
        ArchiveWriteEntry(
          path: 'stalled',
          isDirectory: false,
          size: 1,
          readChunks: () => source.stream,
        ),
      ],
      streamed: true,
      sink: (_) async {},
      maxOutputBytes: 1024 * 1024,
      cancellationFuture: abort.future,
    ),
    'stalled input cancellation',
  );
  await started.future.timeout(const Duration(seconds: 10));
  abort.complete();
  _require(await result is ArchiveViewException, 'Cancellation did not settle');
  await cancelled.future.timeout(const Duration(seconds: 10));
  never.complete();

  final paused = Completer<void>();
  final abortPause = Completer<void>();
  final pauseForever = Completer<void>();
  final pausedResult = _failure(
    writeArchiveEntriesInWorker(
      ArchiveEndpointFormat.zip,
      [_entry('data.bin', _data)],
      sink: (_) async {},
      maxOutputBytes: 2 * 1024 * 1024,
      checkpoint: () {
        if (!paused.isCompleted) paused.complete();
        return pauseForever.future;
      },
      cancellationFuture: abortPause.future,
    ),
    'cancel during pause',
  );
  await paused.future;
  abortPause.complete();
  _require(
    await pausedResult is ArchiveViewException,
    'Paused cancellation did not settle',
  );
  pauseForever.complete();

  var stop = false;
  final entered = Completer<void>();
  final stalled = StreamController<List<int>>(onListen: entered.complete);
  final booleanResult = _failure(
    writeArchiveEntriesInWorker(
      ArchiveEndpointFormat.zip,
      [
        ArchiveWriteEntry(
          path: 'stalled',
          isDirectory: false,
          size: 1,
          readChunks: () => stalled.stream,
        ),
      ],
      streamed: true,
      sink: (_) async {},
      maxOutputBytes: 1024 * 1024,
      isCancelled: () => stop,
    ),
    'boolean-only cancellation',
  );
  await entered.future.timeout(const Duration(seconds: 10));
  stop = true;
  _require(
    await booleanResult is ArchiveViewException,
    'Boolean cancellation was not polled',
  );
  await stalled.close();
}

void _unexpectedExit(Object? value) {
  final start = value as Map;
  File('${start['directory']}/orphan').writeAsBytesSync([1, 2, 3]);
  Isolate.exit();
}

void _unhandledCrash(Object? value) {
  final start = value as Map;
  File('${start['directory']}/orphan').writeAsBytesSync([4, 5, 6]);
  throw StateError('worker-crash-fixture');
}

void _invalidProtocol(Object? value) {
  final start = value as Map;
  (start['port'] as SendPort).send({'unexpected': true});
}

Future<Set<String>> _workerDirectories() async => {
  await for (final entity in Directory.systemTemp.list())
    if (entity is Directory &&
        entity.path
            .split(Platform.pathSeparator)
            .last
            .startsWith('crisp-archive-worker-'))
      entity.path,
};

Future<void> verifyArchiveWorkerFailures() async {
  final before = await _workerDirectories();
  for (final entryPoint in [
    _unexpectedExit,
    _unhandledCrash,
    _invalidProtocol,
  ]) {
    final error = await _failure(
      debugRunArchiveWriterWorker(
        entryPoint,
        sink: (_) async => throw StateError('Unexpected output'),
      ),
      'worker protocol/exit',
    );
    _require(error is ArchiveViewException, 'Worker fault was not reported');
  }
  for (final payload in [
    [1],
    [1, 2, 3],
    [256, -1],
  ]) {
    final error = await _failure(
      writeArchiveEntriesInWorker(
        ArchiveEndpointFormat.tar,
        [
          ArchiveWriteEntry(
            path: 'invalid',
            isDirectory: false,
            size: 2,
            readChunks: () => Stream.value(payload),
          ),
        ],
        streamed: true,
        sink: (_) async {},
        maxOutputBytes: 1024 * 1024,
      ),
      'invalid source bytes or length',
    );
    _require(error is ArchiveViewException, 'Source validation error was lost');
  }
  final sourceError = StateError('source-fixture-error');
  final actualSource = await _failure(
    writeArchiveEntriesInWorker(
      ArchiveEndpointFormat.sevenZip,
      [
        ArchiveWriteEntry(
          path: 'broken',
          isDirectory: false,
          size: 1,
          readChunks: () => Stream.error(sourceError),
        ),
      ],
      streamed: true,
      sink: (_) async {},
      maxOutputBytes: 1024 * 1024,
    ),
    'source error',
  );
  _require(
    identical(actualSource, sourceError),
    'Source error identity was replaced',
  );
  final sinkError = StateError('sink-fixture-error');
  final actualSink = await _failure(
    writeArchiveEntriesInWorker(
      ArchiveEndpointFormat.sevenZip,
      [_entry('data.bin', _data)],
      streamed: true,
      sink: (_) async => throw sinkError,
      maxOutputBytes: 1024 * 1024,
    ),
    'sink error',
  );
  _require(
    identical(actualSink, sinkError),
    'Sink error identity was replaced',
  );
  await _failure(
    writeArchiveEntriesInWorker(
      ArchiveEndpointFormat.tar,
      [_entry('data.bin', _data)],
      streamed: true,
      sink: (_) async {},
      maxOutputBytes: 511,
    ),
    'output bound',
  );
  final after = await _workerDirectories();
  _require(
    after.difference(before).isEmpty,
    'Worker private spool directory leaked',
  );
}

/// The packed fixture is deliberately small; this gate measures a real
/// >2 GiB input/member crossing the worker bridge, not a >2 GiB physical file.
Future<void> verifyArchiveWorkerLarge(String kind) async {
  final format = switch (kind) {
    'zip' => ArchiveEndpointFormat.zip,
    '7z' => ArchiveEndpointFormat.sevenZip,
    'tgz' => ArchiveEndpointFormat.tarGzip,
    _ => throw ArgumentError.value(kind, 'kind'),
  };
  const size = 2 * 1024 * 1024 * 1024 + 17;
  // Same independent Python/libarchive-qualified sentinel fixture as the
  // stored RAR receipt: first 0x43, last 0xa5, all intervening bytes zero.
  const expected =
      'b5c0eee7c54826eeb55e9625703f26d88693a678318e5a8534bfc570de17d5af';
  final spool = await ArchiveOutputSpool.create(
    maxBytes: kArchiveStreamingLimit,
  );
  final baseline = ProcessInfo.currentRss;
  var peak = baseline, heartbeats = 0, maxInput = 0, maxOutput = 0;
  final timer = Timer.periodic(const Duration(milliseconds: 20), (_) {
    heartbeats++;
    final current = ProcessInfo.currentRss;
    if (current > peak) peak = current;
  });
  final watch = Stopwatch()..start();
  try {
    await writeArchiveEntriesInWorker(
      format,
      [
        ArchiveWriteEntry(
          path: 'large.bin',
          isDirectory: false,
          size: size,
          modified: _modified,
          readChunks: () async* {
            final zeros = Uint8List(65536);
            for (var at = 0; at < size; at += zeros.length) {
              final length = size - at < zeros.length
                  ? size - at
                  : zeros.length;
              Uint8List chunk;
              if (at == 0 || at + length == size) {
                chunk = Uint8List(length);
                if (at == 0) chunk[0] = 0x43;
                if (at + length == size) chunk[length - 1] = 0xa5;
              } else {
                chunk = zeros;
              }
              if (chunk.length > maxInput) maxInput = chunk.length;
              yield chunk;
            }
          },
        ),
      ],
      streamed: true,
      maxOutputBytes: kArchiveStreamingLimit,
      sink: (chunk) async {
        if (chunk.length > maxOutput) maxOutput = chunk.length;
        _require(
          chunk.length <= 256 * 1024,
          'Large worker wire bound exceeded',
        );
        await spool.write(chunk);
      },
    );
    await spool.finish();
    final packedMilliseconds = watch.elapsedMilliseconds;
    final opened = await openStreamedArchiveSource(
      await spool.openByteSource(),
      name: 'worker.$kind',
    );
    var decoded = 0;
    try {
      final member = opened.archive.members.single;
      _require(member.size == size, 'Large worker declared size differs');
      final digest = await sha256
          .bind(
            opened.archive
                .openMember(member, maxBytes: kArchiveStreamingLimit)
                .map((chunk) {
                  _require(
                    chunk.length <= 256 * 1024,
                    'Large reader chunk exceeded bound',
                  );
                  decoded += chunk.length;
                  return chunk;
                }),
          )
          .single;
      _require(
        decoded == size && '$digest' == expected,
        'Large worker full hash differs',
      );
    } finally {
      await opened.archive.close();
    }
    _require(
      maxInput <= 65536 && maxOutput <= 256 * 1024,
      'Large bridge chunks unbounded',
    );
    _require(heartbeats > 0, 'Host event loop did not remain live');
    _require(
      peak - baseline < 512 * 1024 * 1024,
      'Worker memory growth exceeded 512 MiB',
    );
    // ignore: avoid_print
    print(
      jsonEncode({
        'check': 'large worker $kind',
        'result': 'PASS',
        'memberBytes': size,
        'packedBytes': spool.length,
        'sha256': expected,
        'packingMilliseconds': packedMilliseconds,
        'totalMilliseconds': watch.elapsedMilliseconds,
        'baselineRss': baseline,
        'sampledPeakRss': peak,
        'sampledGrowthRss': peak - baseline,
        'heartbeatTicks': heartbeats,
        'maxInputChunk': maxInput,
        'maxOutputChunk': maxOutput,
      }),
    );
  } finally {
    timer.cancel();
    await spool.dispose();
  }
}

Future<void> main(List<String> arguments) async {
  if (arguments.isNotEmpty) {
    for (final kind in arguments) {
      await verifyArchiveWorkerLarge(kind);
    }
    return;
  }
  final checks = <String, Future<void> Function()>{
    'streamed formats and HFSX': verifyArchiveWorkerRoundTrips,
    'buffered compression and protection options':
        verifyArchiveWorkerBufferedOptions,
    'opaque DMG preservation proof': verifyArchiveWorkerPreservation,
    'pause and bounded backpressure': verifyArchiveWorkerPauseAndBackpressure,
    'stalled input and paused cancellation': verifyArchiveWorkerCancellation,
    'protocol, crash and cleanup': verifyArchiveWorkerFailures,
  };
  for (final check in checks.entries) {
    final watch = Stopwatch()..start();
    await check.value();
    // ignore: avoid_print
    print(
      jsonEncode({
        'check': check.key,
        'result': 'PASS',
        'milliseconds': watch.elapsedMilliseconds,
      }),
    );
  }
}
