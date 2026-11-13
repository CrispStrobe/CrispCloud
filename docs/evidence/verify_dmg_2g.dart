// Standalone native codec evidence; this does not run the Flutter app or publish.
// From a resolved CrispCloud checkout, with TMPDIR on a volume having >=6 GiB free:
// dart --packages=.dart_tool/package_config.json path/to/verify_dmg_2g.dart \
//   --output=/absolute/path/verify_dmg_2g.json --revision=<tested-source-commit>
// The output path must be outside the private, empty TMPDIR used by this probe.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:crisp_cloud/services/archive_dmg_reader.dart';
import 'package:crisp_cloud/services/archive_dmg_writer.dart';
import 'package:crisp_cloud/services/archive_output_spool.dart';
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:crisp_cloud/services/archive_write_model.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

const _payloadBytes = 2 * 1024 * 1024 * 1024 + 4097;
const _chunkBytes = 256 * 1024;
const _udifChunkBytes = 1024 * 1024;

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

class _DigestResult implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

class _TrackedSource implements koni.ByteSource {
  _TrackedSource(this.delegate);
  final koni.ByteSource delegate;
  int reads = 0, bytes = 0, maxRequest = 0, closes = 0;
  @override
  int get length => delegate.length;
  @override
  String? get name => delegate.name;
  @override
  Future<Uint8List> read(int offset, int count) async {
    reads++;
    bytes += count;
    if (count > maxRequest) maxRequest = count;
    _require(count <= 16 * 1024 * 1024, 'Unbounded positional source read.');
    return delegate.read(offset, count);
  }

  @override
  Future<void> close() async {
    closes++;
    await delegate.close();
  }

  Future<void> verifyClosed() async {
    _require(closes == 1, 'The reader did not close its source exactly once.');
    var rejected = false;
    try {
      await delegate.read(0, 1);
    } on StateError {
      rejected = true;
    }
    _require(rejected, 'The source still permits reads after archive close.');
  }

  Map<String, Object> toJson() => {
    'logicalLength': length,
    'readCalls': reads,
    'requestedBytes': bytes,
    'maxPositionalReadBytes': maxRequest,
    'closeCalls': closes,
  };
}

Future<void> main(List<String> args) async {
  final arguments = <String, String>{};
  for (final arg in args) {
    final equals = arg.indexOf('=');
    if (!arg.startsWith('--') || equals < 3) {
      throw ArgumentError('Expected --output=<path> and --revision=<commit>.');
    }
    arguments[arg.substring(2, equals)] = arg.substring(equals + 1);
  }
  final outputPath = arguments['output'];
  final revision = arguments['revision'];
  _require(
    outputPath != null && outputPath.startsWith('/') && revision != null,
    'Pass an absolute --output path and the tested --revision.',
  );
  final tempRoot = Directory.systemTemp;
  _require(
    !(await tempRoot.list().toList()).isNotEmpty,
    'Use a dedicated empty TMPDIR so cleanup can be verified precisely.',
  );
  final result = <String, Object?>{
    'probe': 'native DMG create / reopen / rewrite / reopen over 2 GiB',
    'scope':
        'Production codecs and file spools only; no Flutter or publication.',
    'testedSourceRevision': revision,
    'runtime': Platform.version.split('\n').first,
    'os': Platform.operatingSystem,
    'startedUtc': DateTime.now().toUtc().toIso8601String(),
    'memberBytes': _payloadBytes,
    'resourceLimitBytes': kArchiveStreamingLimit,
    'fixture': {
      'blockBytes': _chunkBytes,
      'lcgSeed': '0x43524953',
      'lcgMultiplier': 1664525,
      'lcgIncrement': 1013904223,
      'lcgOutput': 'high byte of each 32-bit state',
      'repeatBlock': true,
      'firstFourBytes': [0x11, 0x22, 0x33, 0x44],
      'lastFourBytes': [0x55, 0x66, 0x77, 0x88],
    },
  };
  final totalWatch = Stopwatch()..start();
  final times = <String, int>{};
  var phase = 'prepare';
  var cancelled = false;
  final deadline = Timer(const Duration(minutes: 14), () {
    cancelled = true;
  });
  void check() {
    if (cancelled) throw StateError('The 14-minute probe deadline expired.');
  }

  final initialRss = ProcessInfo.currentRss;
  var peakRss = initialRss, rssSamples = 0;
  final rssTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
    rssSamples++;
    final rss = ProcessInfo.currentRss;
    if (rss > peakRss) peakRss = rss;
  });
  ArchiveOutputSpool? originalSpool, candidateSpool;
  StreamedDmgOpen? original, candidate;
  _TrackedSource? originalSource, candidateSource;
  var generatedBytes = 0, rewrittenBytes = 0, verifiedBytes = 0;
  var maxInputChunk = 0, maxWriterChunk = 0, maxReadChunk = 0;
  var sourceOpens = 0, rewriteOpens = 0;
  String? expectedSha;
  final progress = Timer.periodic(const Duration(seconds: 5), (_) {
    stdout.writeln(
      jsonEncode({
        'phase': phase,
        'elapsedMs': totalWatch.elapsedMilliseconds,
        'originalOutputBytes': originalSpool?.length ?? 0,
        'candidateOutputBytes': candidateSpool?.length ?? 0,
        'generatedBytes': generatedBytes,
        'rewrittenBytes': rewrittenBytes,
        'verifiedBytes': verifiedBytes,
      }),
    );
  });

  Future<T> measure<T>(String label, Future<T> Function() action) async {
    phase = label;
    final watch = Stopwatch()..start();
    try {
      check();
      return await action();
    } finally {
      times[label] = watch.elapsedMilliseconds;
      stdout.writeln(
        jsonEncode({
          'completedPhase': label,
          'elapsedMs': watch.elapsedMilliseconds,
        }),
      );
    }
  }

  try {
    final block = Uint8List(_chunkBytes);
    var state = 0x43524953;
    for (var index = 0; index < block.length; index++) {
      state = (state * 1664525 + 1013904223) & 0xffffffff;
      block[index] = state >> 24;
    }
    Stream<List<int>> generatedPayload() async* {
      sourceOpens++;
      _require(sourceOpens == 1, 'Creation unexpectedly reopened its input.');
      final digest = _DigestResult();
      final hash = sha256.startChunkedConversion(digest);
      try {
        for (var at = 0; at < _payloadBytes; at += block.length) {
          check();
          final left = _payloadBytes - at;
          final count = left < block.length ? left : block.length;
          Uint8List chunk = Uint8List.sublistView(block, 0, count);
          if (at == 0 || at + count == _payloadBytes) {
            chunk = Uint8List.fromList(chunk);
            if (at == 0) chunk.setRange(0, 4, [0x11, 0x22, 0x33, 0x44]);
            if (at + count == _payloadBytes) {
              chunk.setRange(count - 4, count, [0x55, 0x66, 0x77, 0x88]);
            }
          }
          if (chunk.length > maxInputChunk) maxInputChunk = chunk.length;
          hash.add(chunk);
          generatedBytes += chunk.length;
          yield chunk;
        }
      } finally {
        hash.close();
      }
      _require(generatedBytes == _payloadBytes, 'Generated size mismatch.');
      expectedSha = digest.value!.toString();
    }

    final modified = DateTime.utc(2026, 11, 12, 1, 2, 3);
    final initialEntries = [
      ArchiveWriteEntry(
        path: 'payload.bin',
        isDirectory: false,
        size: _payloadBytes,
        mode: 0x81a4,
        modified: modified,
        readChunks: generatedPayload,
      ),
      ArchiveWriteEntry(
        path: 'delete-me.txt',
        isDirectory: false,
        size: 4,
        mode: 0x81a4,
        modified: modified,
        readChunks: () => Stream.value([1, 2, 3, 4]),
      ),
      ArchiveWriteEntry(
        path: 'empty-folder',
        isDirectory: true,
        size: 0,
        mode: 0x41ed,
        modified: modified,
      ),
    ];
    originalSpool = await ArchiveOutputSpool.create(
      maxBytes: kArchiveStreamingLimit,
    );
    await measure('createRawDmg', () async {
      await writeDmgArchive(
        initialEntries,
        compress: false,
        volumeName: 'CrispCloud Large Verification',
        maxOutputBytes: kArchiveStreamingLimit,
        isCancelled: () => cancelled,
        sink: (chunk) async {
          check();
          if (chunk.length > maxWriterChunk) maxWriterChunk = chunk.length;
          _require(chunk.length <= _udifChunkBytes, 'Unbounded UDIF output.');
          await originalSpool!.write(chunk);
        },
      );
      await originalSpool!.finish();
    });
    _require(expectedSha != null, 'The creation payload hash is incomplete.');
    _require(
      originalSpool.length > 2 * 1024 * 1024 * 1024,
      'The original outer DMG did not exceed 2 GiB.',
    );
    result['originalContainerBytes'] = originalSpool.length;
    result['expectedPayloadSha256'] = expectedSha;

    originalSource = _TrackedSource(await originalSpool.openByteSource());
    original = await measure(
      'openOriginalAndVerifyCanonicalProfileAndCrc',
      () => openStreamedDmgSource(
        originalSource!,
        maxBytes: kArchiveStreamingLimit,
        isCancelled: () => cancelled,
      ),
    );
    _require(original!.inspection.supported, 'Original DMG is read-only.');
    _require(
      original!.archive.maxStreamingMemberBytes == kArchiveStreamingLimit,
      'Original reader did not advertise its streaming limit.',
    );
    verifyDmgRewritePreservation(initialEntries, original!.inspection);
    final payload = original!.archive.members.singleWhere(
      (member) => member.name == 'payload.bin',
    );
    _require(
      payload.size == _payloadBytes &&
          payload.modified == modified &&
          payload.posixMode == 0x81a4,
      'Original payload metadata differs.',
    );
    final folder = original!.archive.members.singleWhere(
      (member) => member.name == 'empty-folder',
    );

    Stream<List<int>> capturedPayload() async* {
      rewriteOpens++;
      _require(rewriteOpens == 1, 'Rewrite unexpectedly reopened its input.');
      final digest = _DigestResult();
      final hash = sha256.startChunkedConversion(digest);
      try {
        await for (final chunk in original!.archive.openMember(
          payload,
          maxBytes: kArchiveStreamingLimit,
          chunkSize: _chunkBytes,
        )) {
          check();
          _require(
            chunk.length <= _chunkBytes,
            'Unbounded original member read.',
          );
          if (chunk.length > maxReadChunk) maxReadChunk = chunk.length;
          hash.add(chunk);
          rewrittenBytes += chunk.length;
          yield chunk;
        }
      } finally {
        hash.close();
      }
      _require(
        rewrittenBytes == _payloadBytes &&
            digest.value.toString() == expectedSha,
        'The reopened original payload differs from its captured source.',
      );
      result['rewriteInputPayloadSha256'] = digest.value.toString();
    }

    final addedBytes = Uint8List.fromList(
      utf8.encode('Added after DMG open.\n'),
    );
    final entries = [
      ArchiveWriteEntry(
        path: 'renamed.bin',
        isDirectory: false,
        size: payload.size,
        mode: payload.posixMode,
        modified: payload.modified,
        attributes: original!.inspection.attributes[payload.name]!,
        readChunks: capturedPayload,
      ),
      ArchiveWriteEntry(
        path: folder.name,
        isDirectory: true,
        size: 0,
        mode: folder.posixMode,
        modified: folder.modified,
        attributes: original!.inspection.attributes[folder.name]!,
      ),
      ArchiveWriteEntry(
        path: 'added.txt',
        isDirectory: false,
        size: addedBytes.length,
        mode: 0x8180,
        modified: DateTime.utc(2026, 11, 13, 1, 2, 3),
        readChunks: () => Stream.value(addedBytes),
      ),
    ];
    candidateSpool = await ArchiveOutputSpool.create(
      maxBytes: kArchiveStreamingLimit,
    );
    await measure('rewriteWithDefaultZlibSelection', () async {
      await writeDmgArchive(
        entries,
        source: original!.inspection,
        // Existing volume metadata must override this creation-only default.
        volumeName: 'This label must not replace the original',
        maxOutputBytes: kArchiveStreamingLimit,
        isCancelled: () => cancelled,
        sink: (chunk) async {
          check();
          if (chunk.length > maxWriterChunk) maxWriterChunk = chunk.length;
          _require(chunk.length <= _udifChunkBytes, 'Unbounded UDIF output.');
          await candidateSpool!.write(chunk);
        },
      );
      await candidateSpool!.finish();
    });
    _require(
      originalSource.closes == 0,
      'The original source closed while the rewrite depended on it.',
    );
    _require(
      candidateSpool.length > 2 * 1024 * 1024 * 1024,
      'The rewritten outer DMG did not exceed 2 GiB.',
    );
    result['rewrittenContainerBytes'] = candidateSpool.length;

    candidateSource = _TrackedSource(await candidateSpool.openByteSource());
    candidate = await measure(
      'openCandidateAndVerifyCanonicalProfileAndCrc',
      () => openStreamedDmgSource(
        candidateSource!,
        maxBytes: kArchiveStreamingLimit,
        isCancelled: () => cancelled,
      ),
    );
    _require(candidate!.inspection.supported, 'Candidate DMG is read-only.');
    verifyDmgRewritePreservation(
      entries,
      candidate!.inspection,
      source: original!.inspection,
    );
    result['metadataPreservationVerified'] = true;
    final actualNames = candidate!.archive.members.map((m) => m.name).toSet();
    _require(
      actualNames.length == 3 &&
          actualNames.containsAll(['renamed.bin', 'empty-folder', 'added.txt']),
      'The final namespace does not exactly match rename/add/delete.',
    );
    result['rewrittenMemberNames'] = actualNames.toList()..sort();
    final renamed = candidate!.archive.members.singleWhere(
      (member) => member.name == 'renamed.bin',
    );
    _require(
      renamed.size == _payloadBytes &&
          renamed.modified == modified &&
          renamed.posixMode == payload.posixMode,
      'Rewritten payload metadata differs.',
    );
    await measure('fullReopenedCandidatePayloadSha256', () async {
      final digest = _DigestResult();
      final hash = sha256.startChunkedConversion(digest);
      try {
        await for (final chunk in candidate!.archive.openMember(
          renamed,
          maxBytes: kArchiveStreamingLimit,
          chunkSize: _chunkBytes,
        )) {
          check();
          _require(
            chunk.length <= _chunkBytes,
            'Unbounded reopened member read.',
          );
          if (chunk.length > maxReadChunk) maxReadChunk = chunk.length;
          verifiedBytes += chunk.length;
          hash.add(chunk);
        }
      } finally {
        hash.close();
      }
      _require(
        verifiedBytes == _payloadBytes &&
            digest.value.toString() == expectedSha,
        'Reopened payload hash differs.',
      );
      result['reopenedPayloadSha256'] = digest.value.toString();
    });
    final added = candidate!.archive.members.singleWhere(
      (member) => member.name == 'added.txt',
    );
    final addedSha = await sha256
        .bind(candidate!.archive.openMember(added))
        .single;
    _require(addedSha == sha256.convert(addedBytes), 'Added payload differs.');
    _require(
      added.posixMode == 0x8180 &&
          added.modified == DateTime.utc(2026, 11, 13, 1, 2, 3),
      'Added member metadata differs.',
    );

    await original!.archive.close();
    await original!.archive.close();
    await candidate!.archive.close();
    await candidate!.archive.close();
    await originalSource.verifyClosed();
    await candidateSource.verifyClosed();
    result['sourcesClosedExactlyOnceAndRejectFurtherReads'] = true;
    result['status'] = 'passed';
  } catch (error, stack) {
    result['status'] = 'failed';
    result['failedPhase'] = phase;
    result['error'] = error.toString();
    result['stack'] = stack.toString();
    exitCode = 1;
  } finally {
    phase = 'cleanup';
    final cleanupWatch = Stopwatch()..start();
    final cleanupErrors = <String>[];
    for (final archive in [candidate?.archive, original?.archive]) {
      try {
        await archive?.close();
      } catch (error) {
        cleanupErrors.add(error.toString());
      }
    }
    for (final spool in [candidateSpool, originalSpool]) {
      try {
        await spool?.dispose();
      } catch (error) {
        cleanupErrors.add(error.toString());
      }
    }
    final leftovers = await tempRoot.list().toList();
    result['temporaryStorageCleaned'] =
        leftovers.isEmpty && cleanupErrors.isEmpty;
    if (leftovers.isNotEmpty || cleanupErrors.isNotEmpty) {
      result['status'] = 'failed';
      result['cleanupErrors'] = cleanupErrors;
      result['leftoverTemporaryPaths'] = leftovers.map((e) => e.path).toList();
      exitCode = 1;
    }
    times['cleanup'] = cleanupWatch.elapsedMilliseconds;
    deadline.cancel();
    progress.cancel();
    rssTimer.cancel();
    result.addAll({
      'completedUtc': DateTime.now().toUtc().toIso8601String(),
      'totalElapsedMs': totalWatch.elapsedMilliseconds,
      'phaseElapsedMs': times,
      'originalSource': originalSource?.toJson(),
      'candidateSource': candidateSource?.toJson(),
      'generatedInputBytes': generatedBytes,
      'originalPayloadReadForRewriteBytes': rewrittenBytes,
      'reopenedPayloadReadBytes': verifiedBytes,
      'maxGeneratedChunkBytes': maxInputChunk,
      'maxWriterSinkChunkBytes': maxWriterChunk,
      'maxMemberReadChunkBytes': maxReadChunk,
      'sourceGeneratorOpens': sourceOpens,
      'rewriteMemberOpens': rewriteOpens,
      'initialResidentBytes': initialRss,
      'sampledPeakResidentBytes': peakRss,
      'sampledResidentGrowthBytes': peakRss - initialRss,
      'residentSampleCount': rssSamples,
      'residentSamplingIntervalMs': 50,
      'residentNote':
          'Sampled process RSS includes JIT/runtime; not a memory ceiling.',
    });
    await File(outputPath!).writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(result)}\n',
      flush: true,
    );
    stdout.writeln(jsonEncode(result));
  }
}
