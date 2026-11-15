// Copyright (c) 2026 CrispCloud contributors
// SPDX-License-Identifier: MIT
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' as codecs;
import 'package:crypto/crypto.dart';
import 'package:koni_archive/koni_archive.dart' as koni;
import 'package:koni_codecs/koni_codecs.dart' as koni_codecs;

import 'archive_types.dart';

enum ArchivePngCarvingPhase { scanning, recovering, verifying, publishing }

enum ArchivePngCarvingStatus { recoverable, rejected, unsupported }

enum ArchivePngCarvingReason {
  truncated,
  invalidHeader,
  invalidChunk,
  chunkOrder,
  checksumMismatch,
  invalidZlib,
  scanlineSize,
  invalidFilter,
  indexedColor,
  interlaced,
  bitDepth,
  animation,
  unsupportedChunk,
  unsupportedCompression,
  overlappingCandidate,
  limitExceeded,
}

enum ArchivePngCarvingStopReason { endOfInput, candidateLimit, workLimit }

String pngCarvingReasonDescription(
  ArchivePngCarvingReason? reason,
) => switch (reason) {
  null => 'PNG structure, chunk checksums and image data verified.',
  ArchivePngCarvingReason.truncated => 'Truncated PNG header or chunk.',
  ArchivePngCarvingReason.invalidHeader => 'Invalid PNG image header.',
  ArchivePngCarvingReason.invalidChunk => 'Invalid PNG chunk content.',
  ArchivePngCarvingReason.chunkOrder => 'Invalid or repeated PNG chunk order.',
  ArchivePngCarvingReason.checksumMismatch => 'PNG chunk checksum mismatch.',
  ArchivePngCarvingReason.invalidZlib => 'Incomplete or invalid PNG zlib data.',
  ArchivePngCarvingReason.scanlineSize =>
    'Decoded PNG scanline size does not match its dimensions.',
  ArchivePngCarvingReason.invalidFilter =>
    'PNG scanline uses an invalid filter.',
  ArchivePngCarvingReason.indexedColor =>
    'Indexed-color PNG recovery is outside this profile.',
  ArchivePngCarvingReason.interlaced =>
    'Interlaced PNG recovery is outside this profile.',
  ArchivePngCarvingReason.bitDepth => 'Only 8-bit PNG samples are supported.',
  ArchivePngCarvingReason.animation =>
    'Animated PNG recovery is outside this profile.',
  ArchivePngCarvingReason.unsupportedChunk =>
    'This PNG contains a chunk outside the supported profile.',
  ArchivePngCarvingReason.unsupportedCompression =>
    'Only the PNG zlib profile with a 32 KiB window is supported.',
  ArchivePngCarvingReason.overlappingCandidate =>
    'Signature lies inside an earlier verified PNG range.',
  ArchivePngCarvingReason.limitExceeded =>
    'PNG validation reached a resource limit.',
};

String pngCarvingStopDescription(ArchivePngCarvingStopReason reason) =>
    switch (reason) {
      ArchivePngCarvingStopReason.endOfInput =>
        'The complete captured input was searched for PNG signatures.',
      ArchivePngCarvingStopReason.candidateLimit =>
        'Candidate limit reached; the remaining source range was not searched.',
      ArchivePngCarvingStopReason.workLimit => 'Validation work limit reached; the remaining source range was not searched.',
    };

class ArchivePngCarvingCancelled extends ArchiveViewException {
  const ArchivePngCarvingCancelled() : super('PNG carving was cancelled.');
}

class ArchivePngCarvingProgress {
  const ArchivePngCarvingProgress(
    this.phase,
    this.completed,
    this.total, {
    this.path = '',
  });
  final ArchivePngCarvingPhase phase;
  final int completed;
  final int total;
  final String path;
}

/// A signature occurrence in the captured source. A rejected candidate's
/// [endOffset] is only the inspected boundary, not a proven recoverable range.
class ArchivePngCarvingCandidate {
  const ArchivePngCarvingCandidate._({
    required this.offset,
    required this.endOffset,
    required this.status,
    required this.reason,
    this.sha256,
    this.width,
    this.height,
  });
  final int offset;
  final int endOffset;
  final ArchivePngCarvingStatus status;
  final ArchivePngCarvingReason? reason;
  final String? sha256;
  final int? width;
  final int? height;

  int get size => endOffset - offset;
  String get name => 'png-${offset.toString().padLeft(10, '0')}.png';
  bool get isRecoverable => status == ArchivePngCarvingStatus.recoverable;
}

/// The review owns a private immutable capture, with no live source handle or
/// publication authority. Original filenames and fragmentation are unknown.
class ArchivePngCarvingReport {
  ArchivePngCarvingReport._({
    required this.sourceName,
    required this.sourceSha256,
    required this.sourceBytes,
    required this.scannedBytes,
    required this.stopReason,
    required List<ArchivePngCarvingCandidate> candidates,
    required Uint8List snapshot,
  }) : candidates = List.unmodifiable(candidates),
       _snapshot = snapshot;

  final String? sourceName;
  final String sourceSha256;
  final int sourceBytes;
  final int scannedBytes;
  final ArchivePngCarvingStopReason stopReason;
  final List<ArchivePngCarvingCandidate> candidates;
  final Uint8List _snapshot;

  List<ArchivePngCarvingCandidate> get recoverableCandidates =>
      List.unmodifiable(
        candidates.where((candidate) => candidate.isRecoverable),
      );
}

class ArchivePngCarvingResult {
  ArchivePngCarvingResult._({
    required Uint8List bytes,
    required this.sha256,
    required this.sourceSha256,
    required List<ArchivePngCarvingCandidate> candidates,
  }) : bytes = bytes.asUnmodifiableView(),
       candidates = List.unmodifiable(candidates);

  final Uint8List bytes;
  final String sha256;
  final String sourceSha256;
  final List<ArchivePngCarvingCandidate> candidates;
}

/// Capture and search a caller-owned source, including signatures spanning
/// positional read boundaries. Every read must complete exactly: unreadable
/// regions are never replaced with zeros or represented as successfully read.
///
/// The initial profile admits noninterlaced, 8-bit grayscale, RGB, gray-alpha
/// and RGBA images. Known ancillary chunks receive bounded structural checks;
/// compressed metadata, unknown chunks, animation and other profiles decline.
/// All chunk CRCs, complete zlib framing, Adler-32, exact decoded row lengths
/// and filter bytes must pass. No footer search establishes a PNG boundary.
Future<ArchivePngCarvingReport> scanArchivePngCarving(
  koni.ByteSource source, {
  int maxSourceBytes = kArchiveReadLimit,
  int maxImageBytes = kArchiveReadLimit,
  int maxExpandedBytes = kArchiveReadLimit,
  int maxCandidates = 1024,
  int maxChunks = 32768,
  int maxValidationBytes = 128 * 1024 * 1024,
  FutureOr<void> Function()? validateUnchanged,
  Future<void> Function()? checkpoint,
  bool Function()? isCancelled,
  void Function(ArchivePngCarvingProgress)? onProgress,
}) async {
  _validateLimit(maxSourceBytes, 'maxSourceBytes', kArchiveReadLimit);
  _validateLimit(maxImageBytes, 'maxImageBytes', kArchiveReadLimit);
  _validateLimit(maxExpandedBytes, 'maxExpandedBytes', kArchiveReadLimit);
  _validateLimit(maxCandidates, 'maxCandidates', 1024);
  _validateLimit(maxChunks, 'maxChunks', 32768);
  _validateLimit(maxValidationBytes, 'maxValidationBytes', 128 * 1024 * 1024);
  final operation = _CarvingOperation(checkpoint, isCancelled, onProgress);
  await operation.checkpoint();
  await validateUnchanged?.call();
  operation.check();
  final length = source.length;
  if (length < 0 || length > maxSourceBytes) {
    throw ArchiveViewException(
      'PNG carving input exceeds the $maxSourceBytes-byte limit.',
    );
  }
  final snapshot = Uint8List(length);
  final digest = _DigestSink();
  final hash = sha256.startChunkedConversion(digest);
  for (var offset = 0; offset < length; offset += _ioChunkSize) {
    await operation.checkpoint();
    final count = _min(_ioChunkSize, length - offset);
    final bytes = await source.read(offset, count);
    operation.check();
    if (bytes.length != count || source.length != length) {
      throw const ArchiveViewException(
        'The carving source changed or was truncated during capture.',
      );
    }
    snapshot.setRange(offset, offset + count, bytes);
    hash.add(Uint8List.sublistView(snapshot, offset, offset + count));
    operation.progress(
      ArchivePngCarvingPhase.scanning,
      offset + count,
      length * 2,
    );
  }
  hash.close();
  await validateUnchanged?.call();
  operation.check();
  if (source.length != length) {
    throw const ArchiveViewException(
      'The carving source changed during capture.',
    );
  }
  final candidates = <ArchivePngCarvingCandidate>[];
  final budget = _ValidationBudget(
    maxValidationBytes,
    maxExpandedBytes,
    maxChunks,
  );
  var offset = 0;
  var verifiedEnd = 0;
  var stop = ArchivePngCarvingStopReason.endOfInput;
  while (offset <= length - _signature.length) {
    if (offset % _ioChunkSize == 0) {
      await operation.checkpoint();
      operation.progress(
        ArchivePngCarvingPhase.scanning,
        length + offset,
        length * 2,
      );
    }
    if (!_signatureAt(snapshot, offset)) {
      offset++;
      continue;
    }
    if (candidates.length == maxCandidates) {
      stop = ArchivePngCarvingStopReason.candidateLimit;
      break;
    }
    if (offset < verifiedEnd) {
      candidates.add(
        ArchivePngCarvingCandidate._(
          offset: offset,
          endOffset: offset + _signature.length,
          status: ArchivePngCarvingStatus.rejected,
          reason: ArchivePngCarvingReason.overlappingCandidate,
        ),
      );
    } else {
      final parser = _PngCandidateParser(
        snapshot,
        offset,
        maxImageBytes,
        budget,
        operation,
      );
      final candidate = await parser.parse();
      candidates.add(candidate);
      if (candidate.isRecoverable) verifiedEnd = candidate.endOffset;
      if (budget.exhausted) {
        stop = ArchivePngCarvingStopReason.workLimit;
        break;
      }
    }
    offset++;
  }
  final scanned = stop == ArchivePngCarvingStopReason.endOfInput
      ? length
      : offset;
  operation.progress(
    ArchivePngCarvingPhase.scanning,
    length + scanned,
    length * 2,
  );
  // A source name is informational only, never an output path or ZIP entry.
  final sourceName = source.name;
  return ArchivePngCarvingReport._(
    sourceName: sourceName == null || sourceName.length <= 4096
        ? sourceName
        : sourceName.substring(0, 4096),
    sourceSha256: digest.value!,
    sourceBytes: length,
    scannedBytes: scanned,
    stopReason: stop,
    candidates: candidates,
    snapshot: snapshot,
  );
}

/// Recheck selected private capture ranges and build a separate stored ZIP
/// containing PNG files plus recovery-report.json. Selection is frozen before
/// the first await. A distinct Koni reader verifies every ZIP entry and digest.
/// Publication, source revalidation and overwrite policy belong to the host.
Future<ArchivePngCarvingResult> recoverArchivePngCarving(
  ArchivePngCarvingReport report, {
  required Set<int> selectedOffsets,
  int maxOutputBytes = kArchiveReadLimit,
  Future<void> Function()? checkpoint,
  bool Function()? isCancelled,
  void Function(ArchivePngCarvingProgress)? onProgress,
}) async {
  _validateLimit(maxOutputBytes, 'maxOutputBytes', kArchiveReadLimit);
  final selected = Set<int>.of(selectedOffsets);
  final operation = _CarvingOperation(checkpoint, isCancelled, onProgress);
  await operation.checkpoint();
  final available = {for (final c in report.recoverableCandidates) c.offset: c};
  if (selected.isEmpty ||
      selected.any((offset) => !available.containsKey(offset))) {
    throw const ArchiveViewException(
      'Select verified recoverable PNG candidates.',
    );
  }
  final candidates = report.candidates
      .where((c) => selected.contains(c.offset))
      .toList();
  final expected = <_ExpectedFile>[];
  final output = _CarvingOutput(maxOutputBytes, operation.check);
  final encoder = codecs.ZipEncoder()..startEncode(output, level: 0);
  for (var index = 0; index < candidates.length; index++) {
    await operation.checkpoint();
    final candidate = candidates[index];
    operation.progress(
      ArchivePngCarvingPhase.recovering,
      index,
      candidates.length,
      candidate.name,
    );
    final bytes = Uint8List.sublistView(
      report._snapshot,
      candidate.offset,
      candidate.endOffset,
    );
    if (await _hashBytes(bytes, operation) != candidate.sha256) {
      throw const ArchiveViewException(
        'The captured PNG candidate failed revalidation.',
      );
    }
    final file = codecs.ArchiveFile.bytes(candidate.name, bytes)
      ..compression = codecs.CompressionType.none
      ..lastModTime = DateTime.utc(1980).millisecondsSinceEpoch ~/ 1000;
    encoder.add(file);
    expected.add(
      _ExpectedFile(candidate.name, bytes.length, candidate.sha256!),
    );
    operation.check();
  }
  final reportBytes = Uint8List.fromList(
    utf8.encode(
      '${const JsonEncoder.withIndent('  ').convert(_reportJson(report, selected))}\n',
    ),
  );
  encoder.add(
    codecs.ArchiveFile.bytes('recovery-report.json', reportBytes)
      ..compression = codecs.CompressionType.none
      ..lastModTime = DateTime.utc(1980).millisecondsSinceEpoch ~/ 1000,
  );
  expected.add(
    _ExpectedFile(
      'recovery-report.json',
      reportBytes.length,
      await _hashBytes(reportBytes, operation),
    ),
  );
  encoder.endEncode();
  final bytes = output.getBytes();
  await _verifyCandidate(bytes, expected, operation);
  return ArchivePngCarvingResult._(
    bytes: bytes,
    sha256: await _hashBytes(bytes, operation),
    sourceSha256: report.sourceSha256,
    candidates: candidates,
  );
}

Map<String, Object?> _reportJson(
  ArchivePngCarvingReport report,
  Set<int> selected,
) {
  final unclaimed = <Map<String, int>>[];
  var end = 0;
  for (final candidate in report.candidates.where(
    (c) => selected.contains(c.offset),
  )) {
    if (end < candidate.offset)
      unclaimed.add({'start': end, 'endExclusive': candidate.offset});
    end = candidate.endOffset;
  }
  if (end < report.sourceBytes)
    unclaimed.add({'start': end, 'endExclusive': report.sourceBytes});
  return {
    'schema': 'crispcloud.png-carving.v1',
    'profile': 'png-8bit-noninterlaced-v1',
    'sourceSha256': report.sourceSha256,
    'source': {
      'name': report.sourceName,
      'bytes': report.sourceBytes,
      'sha256': report.sourceSha256,
    },
    'offsetCoordinateSystem': 'captured source bytes; zero-based; endExclusive',
    'scannedBytes': report.scannedBytes,
    'stopReason': report.stopReason.name,
    'unreadableRanges': <Object>[],
    'unscannedRanges': [
      if (report.scannedBytes < report.sourceBytes)
        {'start': report.scannedBytes, 'endExclusive': report.sourceBytes},
    ],
    'unclaimedRanges': unclaimed,
    'candidates': [
      for (final c in report.candidates)
        {
          'offset': c.offset,
          'endExclusive': c.endOffset,
          'rangeValidated': c.isRecoverable,
          'status': c.status.name,
          'reason': c.reason?.name,
          'finding': pngCarvingReasonDescription(c.reason),
          'selected': selected.contains(c.offset),
          'outputName': selected.contains(c.offset) ? c.name : null,
          'sha256': c.sha256,
          'width': c.width,
          'height': c.height,
        },
    ],
    'limitations': [
      'Only contiguous supported PNG candidates are recovered; source bytes are not repaired.',
      'Original names, directories, timestamps and arbitrary fragmentation are not recovered.',
      'Unclaimed ranges are not evidence of missing files or successfully read zero sectors.',
      'Unreadable input aborts capture; no missing range is replaced with zero bytes.',
      'Checksums and hashes establish byte integrity, not authenticity or image meaning.',
      'Unknown chunks and compressed ancillary metadata are outside this profile.',
    ],
  };
}

const _signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
const _ioChunkSize = 64 * 1024;
const _inflateChunkSize = 8 * 1024;
int _min(int a, int b) => a < b ? a : b;

bool _signatureAt(Uint8List bytes, int offset) {
  if (bytes[offset] != 137) return false;
  for (var i = 1; i < _signature.length; i++) {
    if (bytes[offset + i] != _signature[i]) return false;
  }
  return true;
}

void _validateLimit(int value, String name, int maximum) {
  if (value <= 0 || value > maximum) throw ArgumentError.value(value, name);
}

class _CarvingOperation {
  _CarvingOperation(this.pause, this.isCancelled, this.onProgress);
  final Future<void> Function()? pause;
  final bool Function()? isCancelled;
  final void Function(ArchivePngCarvingProgress)? onProgress;
  void check() {
    if (isCancelled?.call() ?? false) throw const ArchivePngCarvingCancelled();
  }

  Future<void> checkpoint() async {
    check();
    await pause?.call();
    await Future<void>.delayed(Duration.zero);
    check();
  }

  void progress(
    ArchivePngCarvingPhase phase,
    int completed,
    int total, [
    String path = '',
  ]) {
    check();
    onProgress?.call(
      ArchivePngCarvingProgress(phase, completed, total, path: path),
    );
    check();
  }
}

class _DigestSink implements Sink<Digest> {
  String? value;
  @override
  void add(Digest digest) => value = digest.toString();
  @override
  void close() {}
}

Future<String> _hashBytes(Uint8List bytes, _CarvingOperation operation) async {
  final digest = _DigestSink();
  final hash = sha256.startChunkedConversion(digest);
  for (var offset = 0; offset < bytes.length; offset += _ioChunkSize) {
    await operation.checkpoint();
    hash.add(
      Uint8List.sublistView(
        bytes,
        offset,
        _min(bytes.length, offset + _ioChunkSize),
      ),
    );
  }
  hash.close();
  return digest.value!;
}

class _CandidateFailure implements Exception {
  const _CandidateFailure(this.reason);
  final ArchivePngCarvingReason reason;
}

class _ValidationBudget {
  _ValidationBudget(
    this.workRemaining,
    this.expandedRemaining,
    this.chunksRemaining,
  );
  int workRemaining;
  int expandedRemaining;
  int chunksRemaining;
  bool exhausted = false;
  void charge(int work, {int expanded = 0, bool chunk = false}) {
    if (work > workRemaining ||
        expanded > expandedRemaining ||
        chunk && chunksRemaining == 0) {
      exhausted = true;
      throw const _CandidateFailure(ArchivePngCarvingReason.limitExceeded);
    }
    workRemaining -= work;
    expandedRemaining -= expanded;
    if (chunk) chunksRemaining--;
  }
}

class _PngCandidateParser {
  _PngCandidateParser(
    this.bytes,
    this.start,
    this.imageLimit,
    this.budget,
    this.operation,
  ) : data = ByteData.sublistView(bytes),
      cursor = start + 8;
  final Uint8List bytes;
  final ByteData data;
  final int start;
  final int imageLimit;
  final _ValidationBudget budget;
  final _CarvingOperation operation;
  int cursor;
  int? width;
  int? height;
  int color = -1;
  int stride = 0;
  int expandedSize = 0;
  int chunks = 0;
  bool sawIdat = false;
  bool endedIdat = false;
  bool sawPalette = false;
  final seen = <String>{};
  final packed = BytesBuilder(copy: false);

  Never fail(ArchivePngCarvingReason reason) => throw _CandidateFailure(reason);
  int u32(int at) => data.getUint32(at, Endian.big);
  int u16(int at) => data.getUint16(at, Endian.big);

  Future<ArchivePngCarvingCandidate> parse() async {
    try {
      while (true) {
        await operation.checkpoint();
        if (bytes.length - cursor < 12) fail(ArchivePngCarvingReason.truncated);
        final length = u32(cursor);
        if (length > 0x7fffffff || length > bytes.length - cursor - 12) {
          fail(ArchivePngCarvingReason.truncated);
        }
        if (length + 12 > imageLimit - (cursor - start))
          fail(ArchivePngCarvingReason.limitExceeded);
        if (++chunks > 4096) fail(ArchivePngCarvingReason.limitExceeded);
        budget.charge(12, chunk: true);
        final kindBytes = Uint8List.sublistView(bytes, cursor + 4, cursor + 8);
        if (kindBytes.any(
              (c) => !(c >= 65 && c <= 90 || c >= 97 && c <= 122),
            ) ||
            kindBytes[2] & 32 != 0) {
          fail(ArchivePngCarvingReason.invalidChunk);
        }
        final kind = String.fromCharCodes(kindBytes);
        final payload = cursor + 8;
        final end = cursor + length + 12;
        var crc = 0;
        for (var at = cursor + 4; at < end - 4; at += _ioChunkSize) {
          await operation.checkpoint();
          final to = _min(at + _ioChunkSize, end - 4);
          budget.charge(to - at);
          crc = codecs.getCrc32(Uint8List.sublistView(bytes, at, to), crc);
        }
        if (crc != u32(end - 4)) fail(ArchivePngCarvingReason.checksumMismatch);
        cursor = end;
        if (chunks == 1 && kind != 'IHDR')
          fail(ArchivePngCarvingReason.chunkOrder);
        if (kind != 'IDAT' && kind != 'tEXt' && !seen.add(kind))
          fail(ArchivePngCarvingReason.chunkOrder);
        if (sawIdat && kind != 'IDAT') endedIdat = true;
        if (kind == 'IHDR') {
          if (chunks != 1 || length != 13)
            fail(ArchivePngCarvingReason.invalidHeader);
          _header(payload);
        } else if (kind == 'IDAT') {
          if (endedIdat) fail(ArchivePngCarvingReason.chunkOrder);
          sawIdat = true;
          // One private compressed capture per candidate, bounded by the source.
          packed.add(Uint8List.sublistView(bytes, payload, payload + length));
        } else if (kind == 'IEND') {
          if (!sawIdat || length != 0) fail(ArchivePngCarvingReason.chunkOrder);
          await _validateImageData(packed.takeBytes());
          return ArchivePngCarvingCandidate._(
            offset: start,
            endOffset: end,
            status: ArchivePngCarvingStatus.recoverable,
            reason: null,
            sha256: await _hashBytes(
              Uint8List.sublistView(bytes, start, end),
              operation,
            ),
            width: width,
            height: height,
          );
        } else if (kind == 'acTL' || kind == 'fcTL' || kind == 'fdAT') {
          fail(ArchivePngCarvingReason.animation);
        } else {
          _ancillary(kind, payload, length);
        }
      }
    } on _CandidateFailure catch (failure) {
      return ArchivePngCarvingCandidate._(
        offset: start,
        endOffset: cursor,
        status: _unsupported.contains(failure.reason)
            ? ArchivePngCarvingStatus.unsupported
            : ArchivePngCarvingStatus.rejected,
        reason: failure.reason,
        width: width,
        height: height,
      );
    }
  }

  void _header(int at) {
    width = u32(at);
    height = u32(at + 4);
    final depth = bytes[at + 8];
    color = bytes[at + 9];
    final compression = bytes[at + 10];
    final filter = bytes[at + 11];
    final interlace = bytes[at + 12];
    final depths = switch (color) {
      0 => const [1, 2, 4, 8, 16],
      2 || 4 || 6 => const [8, 16],
      3 => const [1, 2, 4, 8],
      _ => const <int>[],
    };
    if (width == 0 ||
        height == 0 ||
        width! > 0x7fffffff ||
        height! > 0x7fffffff ||
        !depths.contains(depth) ||
        compression != 0 ||
        filter != 0 ||
        interlace > 1) {
      fail(ArchivePngCarvingReason.invalidHeader);
    }
    if (color == 3) fail(ArchivePngCarvingReason.indexedColor);
    if (interlace != 0) fail(ArchivePngCarvingReason.interlaced);
    if (depth != 8) fail(ArchivePngCarvingReason.bitDepth);
    final channels = switch (color) {
      0 => 1,
      2 => 3,
      4 => 2,
      _ => 4,
    };
    if (width! > (imageLimit - 1) ~/ channels)
      fail(ArchivePngCarvingReason.limitExceeded);
    stride = width! * channels + 1;
    if (height! > imageLimit ~/ stride)
      fail(ArchivePngCarvingReason.limitExceeded);
    expandedSize = stride * height!;
  }

  void _ancillary(String kind, int at, int length) {
    void beforeData() {
      if (sawIdat) fail(ArchivePngCarvingReason.chunkOrder);
    }

    void beforePalette() {
      beforeData();
      if (sawPalette) fail(ArchivePngCarvingReason.chunkOrder);
    }

    void exact(int expected) {
      if (length != expected) fail(ArchivePngCarvingReason.invalidChunk);
    }

    switch (kind) {
      case 'PLTE':
        beforeData();
        if (color == 0 ||
            color == 4 ||
            seen.contains('bKGD') ||
            seen.contains('tRNS'))
          fail(ArchivePngCarvingReason.chunkOrder);
        if (length == 0 || length > 768 || length % 3 != 0)
          fail(ArchivePngCarvingReason.invalidChunk);
        sawPalette = true;
      case 'gAMA':
        beforePalette();
        exact(4);
        if (u32(at) == 0) fail(ArchivePngCarvingReason.invalidChunk);
      case 'cHRM':
        beforePalette();
        exact(32);
        for (var i = 0; i < 32; i += 8) {
          if (u32(at + i) > 100000 || u32(at + i + 4) > 100000 - u32(at + i))
            fail(ArchivePngCarvingReason.invalidChunk);
        }
      case 'sRGB':
        beforePalette();
        exact(1);
        if (bytes[at] > 3) fail(ArchivePngCarvingReason.invalidChunk);
      case 'sBIT':
        beforePalette();
        exact(switch (color) {
          0 => 1,
          2 => 3,
          4 => 2,
          _ => 4,
        });
        for (var i = 0; i < length; i++) {
          if (bytes[at + i] == 0 || bytes[at + i] > 8)
            fail(ArchivePngCarvingReason.invalidChunk);
        }
      case 'pHYs':
        beforeData();
        exact(9);
        if (bytes[at + 8] > 1) fail(ArchivePngCarvingReason.invalidChunk);
      case 'bKGD':
      case 'tRNS':
        beforeData();
        if (kind == 'tRNS' && (color == 4 || color == 6))
          fail(ArchivePngCarvingReason.invalidChunk);
        exact(color == 0 || color == 4 ? 2 : 6);
        for (var i = 0; i < length; i += 2) {
          if (u16(at + i) > 255) fail(ArchivePngCarvingReason.invalidChunk);
        }
      case 'tIME':
        exact(7);
        final year = u16(at);
        final month = bytes[at + 2];
        final day = bytes[at + 3];
        if (year == 0 ||
            month < 1 ||
            month > 12 ||
            day < 1 ||
            day > 31 ||
            bytes[at + 4] > 23 ||
            bytes[at + 5] > 59 ||
            bytes[at + 6] > 60)
          fail(ArchivePngCarvingReason.invalidChunk);
        if (DateTime.utc(year, month, day).day != day)
          fail(ArchivePngCarvingReason.invalidChunk);
      case 'tEXt':
        final content = Uint8List.sublistView(bytes, at, at + length);
        final separator = content.indexOf(0);
        if (separator < 1 ||
            separator > 79 ||
            content[0] == 32 ||
            content[separator - 1] == 32)
          fail(ArchivePngCarvingReason.invalidChunk);
        for (var i = 0; i < separator; i++) {
          final c = content[i];
          if (!(c >= 32 && c <= 126 || c >= 161) ||
              c == 32 && i > 0 && content[i - 1] == 32)
            fail(ArchivePngCarvingReason.invalidChunk);
        }
        if (content.indexOf(0, separator + 1) != -1)
          fail(ArchivePngCarvingReason.invalidChunk);
      default:
        fail(ArchivePngCarvingReason.unsupportedChunk);
    }
  }

  Future<void> _validateImageData(Uint8List compressed) async {
    if (compressed.length < 6) fail(ArchivePngCarvingReason.invalidZlib);
    final cmf = compressed[0];
    final flags = compressed[1];
    if (cmf & 15 != 8 ||
        cmf >> 4 > 7 ||
        (cmf * 256 + flags) % 31 != 0 ||
        flags & 32 != 0)
      fail(ArchivePngCarvingReason.invalidZlib);
    // RawInflater enforces the DEFLATE 32 KiB distance ceiling. A smaller
    // advertised zlib window needs a separate decoder contract and declines.
    if (cmf != 0x78) fail(ArchivePngCarvingReason.unsupportedCompression);
    final packedLength = compressed.length - 6;
    var decoded = 0;
    var adlerA = 1;
    var adlerB = 0;
    final inflater = koni_codecs.RawInflater(
      onOutput: (chunk) {
        operation.check();
        if (chunk.length > expandedSize - decoded)
          fail(ArchivePngCarvingReason.scanlineSize);
        budget.charge(chunk.length, expanded: chunk.length);
        for (var i = 0; i < chunk.length; i++) {
          final byte = chunk[i];
          if ((decoded + i) % stride == 0 && byte > 4)
            fail(ArchivePngCarvingReason.invalidFilter);
          adlerA = (adlerA + byte) % 65521;
          adlerB = (adlerB + adlerA) % 65521;
        }
        decoded += chunk.length;
      },
    );
    var consumed = 0;
    try {
      while (!inflater.isFinished && consumed < packedLength) {
        await operation.checkpoint();
        final count = _min(_inflateChunkSize, packedLength - consumed);
        budget.charge(count);
        final used = inflater.addInput(
          Uint8List.sublistView(compressed, 2 + consumed, 2 + consumed + count),
        );
        if (used <= 0 && !inflater.isFinished)
          fail(ArchivePngCarvingReason.invalidZlib);
        consumed += used;
      }
      if (!inflater.isFinished) fail(ArchivePngCarvingReason.invalidZlib);
      inflater.finish();
      consumed -= inflater.takeLeftoverBytes().length;
    } on FormatException {
      fail(ArchivePngCarvingReason.invalidZlib);
    }
    if (consumed != packedLength) fail(ArchivePngCarvingReason.invalidZlib);
    if (decoded != expandedSize) fail(ArchivePngCarvingReason.scanlineSize);
    final checksum = ByteData.sublistView(compressed)
        .getUint32(compressed.length - 4, Endian.big);
    if (adlerB * 65536 + adlerA != checksum)
      fail(ArchivePngCarvingReason.invalidZlib);
  }
}

const _unsupported = <ArchivePngCarvingReason>{
  ArchivePngCarvingReason.indexedColor,
  ArchivePngCarvingReason.interlaced,
  ArchivePngCarvingReason.bitDepth,
  ArchivePngCarvingReason.animation,
  ArchivePngCarvingReason.unsupportedChunk,
  ArchivePngCarvingReason.unsupportedCompression,
};

class _ExpectedFile {
  const _ExpectedFile(this.name, this.size, this.sha256);
  final String name;
  final int size;
  final String sha256;
}

Future<void> _verifyCandidate(
  Uint8List bytes,
  List<_ExpectedFile> expected,
  _CarvingOperation operation,
) async {
  await operation.checkpoint();
  final source = koni.MemoryByteSource(bytes, name: 'carved.zip');
  koni.ArchiveReader? reader;
  try {
    final format = await koni.builtInFormats.detect(source);
    if (format?.name != 'zip')
      throw const ArchiveViewException('The carved candidate is not a ZIP.');
    reader = await koni.builtInFormats.openReader(
      source,
      format: format!,
      options: const koni.ArchiveReadOptions(
        maxEntrySize: kArchiveReadLimit,
        maxEntryCount: 1025,
        maxContainerDecodeSize: kArchiveReadLimit,
      ),
    );
    if (reader.entries.length != expected.length)
      throw const ArchiveViewException('The carved ZIP entry count changed.');
    for (var index = 0; index < expected.length; index++) {
      await operation.checkpoint();
      final captured = expected[index];
      final entry = reader.entries[index];
      operation.progress(
        ArchivePngCarvingPhase.verifying,
        index,
        expected.length,
        captured.name,
      );
      if (entry.path != captured.name ||
          entry.uncompressedSize != captured.size ||
          entry.isEncrypted ||
          entry.pathEscapedRoot ||
          !entry.isFile ||
          entry.isDirectory) {
        throw const ArchiveViewException('The carved ZIP metadata changed.');
      }
      final digest = _DigestSink();
      final hash = sha256.startChunkedConversion(digest);
      var count = 0;
      await for (final chunk in reader.openRead(entry)) {
        await operation.checkpoint();
        if (chunk.length > captured.size - count)
          throw const ArchiveViewException('The carved ZIP member grew.');
        count += chunk.length;
        hash.add(chunk);
      }
      hash.close();
      if (count != captured.size || digest.value != captured.sha256)
        throw const ArchiveViewException(
          'The carved ZIP content failed verification.',
        );
    }
    operation.progress(
      ArchivePngCarvingPhase.verifying,
      expected.length,
      expected.length,
    );
  } finally {
    try {
      await reader?.close();
    } finally {
      await source.close();
    }
  }
}

/// Bounds allocated capacity and written length before ZIP encoding writes.
class _CarvingOutput extends codecs.OutputStream {
  _CarvingOutput(this.limit, this.check)
    : _buffer = Uint8List(_min(limit, 32768)),
      super(byteOrder: codecs.ByteOrder.littleEndian);
  final int limit;
  final void Function() check;
  Uint8List _buffer;
  @override
  int length = 0;
  void _allow(int count) {
    check();
    if (count < 0 || count > limit - length)
      throw const ArchiveViewException(
        'The carved ZIP exceeds its output limit.',
      );
    final required = length + count;
    if (required > _buffer.length) {
      final grown = _min(limit, _buffer.length * 2);
      _buffer = Uint8List(grown > required ? grown : required)
        ..setRange(0, length, _buffer);
    }
  }

  @override
  void reserve(int total) {
    if (total > length) _allow(total - length);
  }

  @override
  void clear() => length = 0;
  @override
  void flush() => check();
  @override
  void writeByte(int value) {
    _allow(1);
    _buffer[length++] = value;
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    final count = length ?? bytes.length;
    _allow(count);
    _buffer.setRange(this.length, this.length + count, bytes);
    this.length += count;
  }

  @override
  void writeStream(codecs.InputStream stream) {
    final at = stream.position;
    _allow(stream.length);
    try {
      while (!stream.isEOS) {
        writeBytes(
          stream.readBytes(_min(stream.length, _ioChunkSize)).toUint8List(),
        );
      }
    } finally {
      stream.setPosition(at);
    }
  }

  @override
  Uint8List subset(int start, [int? end]) {
    final from = start < 0 ? length + start : start;
    final to = end == null
        ? length
        : end < 0
        ? length + end
        : end;
    return Uint8List.sublistView(_buffer, from, to);
  }

  @override
  Uint8List getBytes() => Uint8List.fromList(subset(0, length));
}
