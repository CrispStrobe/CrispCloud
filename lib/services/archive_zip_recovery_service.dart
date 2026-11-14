// Copyright (c) 2026 CrispCloud contributors
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
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' as codecs;
import 'package:crypto/crypto.dart';
import 'package:koni_archive/koni_archive.dart' as koni;
import 'package:koni_codecs/koni_codecs.dart' as koni_codecs;

import 'archive_types.dart';
import 'archive_write_model.dart';

/// Recovery is deliberately separate from normal ZIP opening and rewriting.
/// Only a new, independently verified ZIP is returned; publication belongs to
/// the operation host. Neither function writes to or closes caller input.
enum ArchiveZipRecoveryPhase { scanning, recovering, verifying, publishing }

enum ArchiveZipRecoveryEntryStatus { recoverable, rejected }

enum ArchiveZipRecoveryReason {
  invalidHeader,
  truncated,
  encrypted,
  splitArchive,
  zip64,
  unsupportedMethod,
  unsupportedFlags,
  unsupportedEncoding,
  storedDataDescriptor,
  invalidDataDescriptor,
  invalidExtra,
  invalidData,
  checksumMismatch,
  sizeMismatch,
  invalidName,
  duplicateName,
  pathConflict,
  limitExceeded,
}

enum ArchiveZipRecoveryStopReason {
  endOfInput,
  centralDirectory,
  unrecognizedRecord,
  truncatedRecord,
  rejectedRecord,
  splitArchive,
  limitReached,
}

class ArchiveZipRecoveryCancelled extends ArchiveViewException {
  const ArchiveZipRecoveryCancelled() : super('ZIP recovery was cancelled.');
}

class ArchiveZipRecoveryProgress {
  const ArchiveZipRecoveryProgress(
    this.phase,
    this.completed,
    this.total, {
    this.path = '',
  });

  final ArchiveZipRecoveryPhase phase;
  final int completed;
  final int total;
  final String path;
}

/// One physically encountered local record. [offset] is the stable selection
/// identity inside the captured source, not a filename or list index.
class ArchiveZipRecoveryEntry {
  const ArchiveZipRecoveryEntry._({
    required this.offset,
    required this.name,
    required this.size,
    required this.compressedBytes,
    required this.method,
    required this.crc32,
    required this.isDirectory,
    required this.status,
    required this.reason,
    required this.modified,
    required this.usesDataDescriptor,
    required this.endOffset,
    required this._dataOffset,
    required this._sha256,
  });

  final int offset;
  final String name;
  final int size;
  final int compressedBytes;
  final int method;
  final int crc32;
  final bool isDirectory;
  final ArchiveZipRecoveryEntryStatus status;
  final ArchiveZipRecoveryReason? reason;
  final DateTime? modified;
  final bool usesDataDescriptor;
  final int endOffset;
  final int _dataOffset;
  final String? _sha256;

  bool get isRecoverable => status == ArchiveZipRecoveryEntryStatus.recoverable;

  ArchiveZipRecoveryEntry _reject(ArchiveZipRecoveryReason why) =>
      ArchiveZipRecoveryEntry._(
        offset: offset,
        name: name,
        size: size,
        compressedBytes: compressedBytes,
        method: method,
        crc32: crc32,
        isDirectory: isDirectory,
        status: ArchiveZipRecoveryEntryStatus.rejected,
        reason: why,
        modified: modified,
        usesDataDescriptor: usesDataDescriptor,
        endOffset: endOffset,
        dataOffset: _dataOffset,
        sha256: _sha256,
      );
}

/// An immutable review report over a private captured snapshot. It is safe to
/// keep this object while the user reviews entries or an operation is queued.
/// Releasing the report releases its snapshot; no source handle is retained.
class ArchiveZipRecoveryReport {
  ArchiveZipRecoveryReport._({
    required this.sourceName,
    required this.sourceSha256,
    required this.sourceBytes,
    required this.scannedBytes,
    required this.stopReason,
    required List<ArchiveZipRecoveryEntry> entries,
    required this._snapshot,
    required this._maxMemberBytes,
    required this._maxExpandedBytes,
  }) : entries = List.unmodifiable(entries);

  final String? sourceName;
  final String sourceSha256;
  final int sourceBytes;
  final int scannedBytes;
  final ArchiveZipRecoveryStopReason stopReason;
  final List<ArchiveZipRecoveryEntry> entries;
  final Uint8List _snapshot;
  final int _maxMemberBytes;
  final int _maxExpandedBytes;

  List<ArchiveZipRecoveryEntry> get recoverableEntries =>
      List.unmodifiable(entries.where((entry) => entry.isRecoverable));
}

/// A private candidate, already reopened and checked using the independent
/// Koni ZIP reader. It has no destination or overwrite authority.
class ArchiveZipRecoveryResult {
  ArchiveZipRecoveryResult._({
    required Uint8List bytes,
    required this.sha256,
    required this.sourceSha256,
    required List<ArchiveZipRecoveryEntry> entries,
  }) : bytes = bytes.asUnmodifiableView(),
       entries = List.unmodifiable(entries);

  final Uint8List bytes;
  final String sha256;
  final String sourceSha256;
  final List<ArchiveZipRecoveryEntry> entries;
}

/// Capture and scan a bounded, ordinary single-volume ZIP beginning at byte 0.
/// Stored and deflated local records need verified sizes and CRC. Deflated
/// data descriptors use the codec's actual end-of-stream and consumed input;
/// no search for a plausible following signature establishes a boundary.
///
/// The first unproven boundary stops the scan. Names that are unsafe, repeated
/// (including case differences), or collide as files/directories are excluded.
/// [source] remains caller-owned and open on success, failure and cancellation.
Future<ArchiveZipRecoveryReport> scanArchiveZipRecovery(
  koni.ByteSource source, {
  int maxSourceBytes = kArchiveReadLimit,
  int maxMemberBytes = kArchiveReadLimit,
  int maxExpandedBytes = kArchiveReadLimit,
  int maxEntries = 4096,
  int maxNameBytes = 1024 * 1024,
  FutureOr<void> Function()? validateUnchanged,
  Future<void> Function()? checkpoint,
  bool Function()? isCancelled,
  void Function(ArchiveZipRecoveryProgress)? onProgress,
}) async {
  _validateLimit(maxSourceBytes, 'maxSourceBytes');
  _validateLimit(maxMemberBytes, 'maxMemberBytes');
  _validateLimit(maxExpandedBytes, 'maxExpandedBytes');
  if (maxEntries <= 0 || maxEntries > 4096) {
    throw ArgumentError.value(maxEntries, 'maxEntries');
  }
  if (maxNameBytes <= 0 || maxNameBytes > 1024 * 1024) {
    throw ArgumentError.value(maxNameBytes, 'maxNameBytes');
  }
  final operation = _RecoveryOperation(checkpoint, isCancelled, onProgress);
  await operation.checkpoint();
  await validateUnchanged?.call();
  operation.check();
  final length = source.length;
  if (length < 0 || length > maxSourceBytes) {
    throw ArchiveViewException(
      'ZIP recovery input exceeds the $maxSourceBytes-byte limit.',
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
        'The ZIP source changed or was truncated during capture.',
      );
    }
    snapshot.setRange(offset, offset + count, bytes);
    hash.add(Uint8List.sublistView(snapshot, offset, offset + count));
    operation.progress(
      ArchiveZipRecoveryPhase.scanning,
      offset + count,
      length * 2,
    );
  }
  hash.close();
  await validateUnchanged?.call();
  operation.check();
  if (source.length != length) {
    throw const ArchiveViewException('The ZIP source changed during capture.');
  }
  return _ZipRecoveryScanner(
    snapshot,
    source.name,
    digest.value!,
    maxMemberBytes,
    maxExpandedBytes,
    maxEntries,
    maxNameBytes,
    operation,
  ).scan();
}

/// Recover the explicitly selected local records to a new stored ZIP. Null
/// [selectedOffsets] selects every recoverable record. Unknown, rejected, or
/// empty selections fail before producing a candidate.
Future<ArchiveZipRecoveryResult> recoverArchiveZip(
  ArchiveZipRecoveryReport report, {
  Set<int>? selectedOffsets,
  int maxOutputBytes = kArchiveReadLimit,
  Future<void> Function()? checkpoint,
  bool Function()? isCancelled,
  void Function(ArchiveZipRecoveryProgress)? onProgress,
}) async {
  _validateLimit(maxOutputBytes, 'maxOutputBytes');
  // Freeze the caller's review selection before the first awaited pause.
  final requested = selectedOffsets == null
      ? null
      : Set<int>.of(selectedOffsets);
  final operation = _RecoveryOperation(checkpoint, isCancelled, onProgress);
  await operation.checkpoint();
  final available = {for (final e in report.recoverableEntries) e.offset: e};
  final selected = requested ?? Set<int>.of(available.keys);
  if (selected.isEmpty ||
      selected.any((offset) => !available.containsKey(offset))) {
    throw const ArchiveViewException(
      'Select verified recoverable ZIP entries.',
    );
  }
  final entries = report.entries
      .where((e) => selected.contains(e.offset))
      .toList();
  final output = _RecoveryOutput(maxOutputBytes, operation.check);
  final encoder = codecs.ZipEncoder()..startEncode(output, level: 0);
  var expanded = 0;
  for (var index = 0; index < entries.length; index++) {
    await operation.checkpoint();
    final entry = entries[index];
    operation.progress(
      ArchiveZipRecoveryPhase.recovering,
      index,
      entries.length,
      entry.name,
    );
    final decoded = await _decodeKnown(
      report._snapshot,
      entry._dataOffset,
      entry.compressedBytes,
      entry.method,
      entry.size,
      report._maxMemberBytes,
      operation,
    );
    expanded += decoded.bytes.length;
    if (expanded > report._maxExpandedBytes ||
        decoded.crc32 != entry.crc32 ||
        decoded.sha256 != entry._sha256) {
      throw const ArchiveViewException(
        'The captured ZIP member failed revalidation.',
      );
    }
    final file = entry.isDirectory
        ? codecs.ArchiveFile.directory('${entry.name}/')
        : codecs.ArchiveFile.bytes(entry.name, decoded.bytes);
    file.compression = codecs.CompressionType.none;
    file.lastModTime =
        (entry.modified ?? DateTime(1980)).millisecondsSinceEpoch ~/ 1000;
    encoder.add(file);
    operation.check();
  }
  encoder.endEncode();
  final bytes = output.getBytes();
  await _verifyCandidate(bytes, entries, operation);
  final candidateHash = await _hashBytes(bytes, operation);
  return ArchiveZipRecoveryResult._(
    bytes: bytes,
    sha256: candidateHash,
    sourceSha256: report.sourceSha256,
    entries: entries,
  );
}

const _ioChunkSize = 64 * 1024;
const _inflateChunkSize = 8 * 1024;

int _min(int a, int b) => a < b ? a : b;

void _validateLimit(int limit, String name) {
  if (limit <= 0 || limit > kArchiveReadLimit) {
    throw ArgumentError.value(limit, name);
  }
}

class _RecoveryOperation {
  _RecoveryOperation(this.pause, this.isCancelled, this.onProgress);
  final Future<void> Function()? pause;
  final bool Function()? isCancelled;
  final void Function(ArchiveZipRecoveryProgress)? onProgress;

  void check() {
    if (isCancelled?.call() ?? false) throw const ArchiveZipRecoveryCancelled();
  }

  Future<void> checkpoint() async {
    check();
    await pause?.call();
    // Give UI cancellation and pauses an event-loop boundary even for memory
    // sources and synchronous codecs.
    await Future<void>.delayed(Duration.zero);
    check();
  }

  void progress(
    ArchiveZipRecoveryPhase phase,
    int completed,
    int total, [
    String path = '',
  ]) {
    check();
    onProgress?.call(
      ArchiveZipRecoveryProgress(phase, completed, total, path: path),
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

Future<String> _hashBytes(Uint8List bytes, _RecoveryOperation operation) async {
  final digest = _DigestSink();
  final hash = sha256.startChunkedConversion(digest);
  for (var offset = 0; offset < bytes.length; offset += _ioChunkSize) {
    await operation.checkpoint();
    hash.add(
      Uint8List.sublistView(
        bytes,
        offset,
        _min(offset + _ioChunkSize, bytes.length),
      ),
    );
  }
  hash.close();
  return digest.value!;
}

class _ZipRecoveryScanner {
  _ZipRecoveryScanner(
    this.bytes,
    this.sourceName,
    this.sourceHash,
    this.maxMemberBytes,
    this.maxExpandedBytes,
    this.maxEntries,
    this.maxNameBytes,
    this.operation,
  ) : data = ByteData.sublistView(bytes);

  final Uint8List bytes;
  final ByteData data;
  final String? sourceName;
  final String sourceHash;
  final int maxMemberBytes;
  final int maxExpandedBytes;
  final int maxEntries;
  final int maxNameBytes;
  final _RecoveryOperation operation;
  final entries = <ArchiveZipRecoveryEntry>[];
  var offset = 0;
  var expanded = 0;
  var nameBytes = 0;
  var stop = ArchiveZipRecoveryStopReason.endOfInput;

  int u16(int at) => data.getUint16(at, Endian.little);
  int u32(int at) => data.getUint32(at, Endian.little);

  Future<ArchiveZipRecoveryReport> scan() async {
    // A missing directory cannot prove that a source was ever complete. Where
    // a split suffix or a complete end record does provide positive split
    // evidence, refuse the whole source rather than recover one volume alone.
    if (_hasSplitEvidence()) {
      stop = ArchiveZipRecoveryStopReason.splitArchive;
      return _report();
    }
    while (offset < bytes.length) {
      await operation.checkpoint();
      operation.progress(
        ArchiveZipRecoveryPhase.scanning,
        bytes.length + offset,
        bytes.length * 2,
      );
      if (bytes.length - offset < 4) {
        stop = ArchiveZipRecoveryStopReason.truncatedRecord;
        break;
      }
      final signature = u32(offset);
      if (signature == 0x08074b50 || signature == 0x30304b50) {
        // The first signature is also the ordinary split-volume marker.
        // A standalone descriptor is never a trustworthy restart point.
        stop = ArchiveZipRecoveryStopReason.splitArchive;
        break;
      }
      if (signature == 0x02014b50 ||
          signature == 0x06054b50 ||
          signature == 0x06064b50 ||
          signature == 0x07064b50) {
        stop = ArchiveZipRecoveryStopReason.centralDirectory;
        if (signature == 0x06054b50 &&
            bytes.length - offset >= 22 &&
            (u16(offset + 4) != 0 || u16(offset + 6) != 0)) {
          stop = ArchiveZipRecoveryStopReason.splitArchive;
          _rejectAll(ArchiveZipRecoveryReason.splitArchive);
        }
        break;
      }
      if (signature != 0x04034b50) {
        stop = ArchiveZipRecoveryStopReason.unrecognizedRecord;
        break;
      }
      if (entries.length == maxEntries) {
        stop = ArchiveZipRecoveryStopReason.limitReached;
        break;
      }
      if (!await _record()) break;
    }
    _excludeNamespaceConflicts();
    return _report();
  }

  ArchiveZipRecoveryReport _report() {
    operation.progress(
      ArchiveZipRecoveryPhase.scanning,
      bytes.length + offset,
      bytes.length * 2,
    );
    return ArchiveZipRecoveryReport._(
      sourceName: sourceName,
      sourceSha256: sourceHash,
      sourceBytes: bytes.length,
      scannedBytes: offset,
      stopReason: stop,
      entries: entries,
      snapshot: bytes,
      maxMemberBytes: maxMemberBytes,
      maxExpandedBytes: maxExpandedBytes,
    );
  }

  bool _hasSplitEvidence() {
    final name = sourceName;
    if (name != null &&
        RegExp(
          r'\.(?:z\d{2,}|zip\.\d+)$',
          caseSensitive: false,
        ).hasMatch(name)) {
      return true;
    }
    final first = bytes.length > 65557 ? bytes.length - 65557 : 0;
    for (var at = bytes.length - 22; at >= first; at--) {
      if (u32(at) != 0x06054b50 || at + 22 + u16(at + 20) != bytes.length) {
        continue;
      }
      final disk = u16(at + 4);
      final directoryDisk = u16(at + 6);
      return disk != 0 || directoryDisk != 0;
    }
    return false;
  }

  Future<bool> _record() async {
    final start = offset;
    var name = '';
    var size = 0;
    var packed = 0;
    var method = 0;
    var crc = 0;
    var directory = false;
    var descriptor = false;
    var payload = start;
    var end = start;
    DateTime? modified;
    String? hash;
    ArchiveZipRecoveryReason? nameReason;

    void add(ArchiveZipRecoveryReason? reason) {
      entries.add(
        ArchiveZipRecoveryEntry._(
          offset: start,
          name: name,
          size: size,
          compressedBytes: packed,
          method: method,
          crc32: crc,
          isDirectory: directory,
          status: reason == null
              ? ArchiveZipRecoveryEntryStatus.recoverable
              : ArchiveZipRecoveryEntryStatus.rejected,
          reason: reason,
          modified: modified,
          usesDataDescriptor: descriptor,
          endOffset: end,
          dataOffset: payload,
          sha256: hash,
        ),
      );
    }

    try {
      if (bytes.length - start < 30) {
        throw const _RecordFailure(ArchiveZipRecoveryReason.truncated);
      }
      final version = u16(start + 4);
      final flags = u16(start + 6);
      method = u16(start + 8);
      modified = _dosTime(u16(start + 12), u16(start + 10));
      crc = u32(start + 14);
      packed = u32(start + 18);
      size = u32(start + 22);
      descriptor = flags & 8 != 0;
      final nameLength = u16(start + 26);
      final extraLength = u16(start + 28);
      payload = start + 30 + nameLength + extraLength;
      if (payload > bytes.length) {
        throw const _RecordFailure(ArchiveZipRecoveryReason.truncated);
      }
      nameBytes += nameLength;
      if (nameBytes > maxNameBytes || nameLength > 4096) {
        throw const _RecordFailure(ArchiveZipRecoveryReason.limitExceeded);
      }
      final encodedName = Uint8List.sublistView(
        bytes,
        start + 30,
        start + 30 + nameLength,
      );
      if (flags & 0x800 != 0) {
        try {
          name = utf8.decode(encodedName);
        } on FormatException {
          nameReason = ArchiveZipRecoveryReason.invalidName;
        }
      } else if (encodedName.any((byte) => byte >= 128)) {
        nameReason = ArchiveZipRecoveryReason.unsupportedEncoding;
      } else {
        name = ascii.decode(encodedName);
      }
      directory = name.endsWith('/');
      if (directory) name = name.substring(0, name.length - 1);
      if (nameReason == null && !_validName(name, directory)) {
        nameReason = ArchiveZipRecoveryReason.invalidName;
      }
      if (flags & (1 | 0x40 | 0x2000) != 0) {
        throw const _RecordFailure(ArchiveZipRecoveryReason.encrypted);
      }
      if (method != 0 && method != 8) {
        throw const _RecordFailure(ArchiveZipRecoveryReason.unsupportedMethod);
      }
      if (packed == 0xffffffff || size == 0xffffffff || version == 45) {
        throw const _RecordFailure(ArchiveZipRecoveryReason.zip64);
      }
      if (version != 10 && version != 20) {
        throw const _RecordFailure(ArchiveZipRecoveryReason.invalidHeader);
      }
      final allowedFlags = method == 8 ? 0x80e : 0x808;
      if (flags & ~allowedFlags != 0) {
        throw const _RecordFailure(ArchiveZipRecoveryReason.unsupportedFlags);
      }
      for (var extra = start + 30 + nameLength; extra < payload;) {
        if (payload - extra < 4 || u16(extra + 2) > payload - extra - 4) {
          throw const _RecordFailure(ArchiveZipRecoveryReason.invalidExtra);
        }
        final tag = u16(extra);
        if (tag == 1) {
          throw const _RecordFailure(ArchiveZipRecoveryReason.zip64);
        }
        if (tag == 0x9901 || tag == 0x0017) {
          throw const _RecordFailure(ArchiveZipRecoveryReason.encrypted);
        }
        extra += 4 + u16(extra + 2);
      }
      final available = _min(maxMemberBytes, maxExpandedBytes - expanded);
      if (available < 0 || size > available) {
        throw const _RecordFailure(ArchiveZipRecoveryReason.limitExceeded);
      }
      final _RecoveredPayload decoded;
      if (descriptor) {
        if (method != 8) {
          throw const _RecordFailure(
            ArchiveZipRecoveryReason.storedDataDescriptor,
          );
        }
        decoded = await _inflate(
          bytes,
          payload,
          bytes.length - payload,
          available,
          operation,
        );
        end = payload + decoded.consumed;
        final descriptorLength = _descriptorLength(
          end,
          decoded.crc32,
          decoded.consumed,
          decoded.bytes.length,
        );
        if (crc != 0 && crc != decoded.crc32 ||
            packed != 0 && packed != decoded.consumed ||
            size != 0 && size != decoded.bytes.length) {
          throw const _RecordFailure(ArchiveZipRecoveryReason.sizeMismatch);
        }
        crc = decoded.crc32;
        packed = decoded.consumed;
        size = decoded.bytes.length;
        end += descriptorLength;
      } else {
        end = payload + packed;
        if (end > bytes.length) {
          throw const _RecordFailure(ArchiveZipRecoveryReason.truncated);
        }
        decoded = await _decodeKnown(
          bytes,
          payload,
          packed,
          method,
          size,
          available,
          operation,
        );
        if (decoded.crc32 != crc) {
          throw const _RecordFailure(ArchiveZipRecoveryReason.checksumMismatch);
        }
      }
      hash = decoded.sha256;
      expanded += decoded.bytes.length;
      if (directory && size != 0) {
        nameReason = ArchiveZipRecoveryReason.invalidName;
      }
      add(nameReason);
      offset = end;
      return true;
    } on _RecordFailure catch (failure) {
      add(failure.reason);
      stop = switch (failure.reason) {
        ArchiveZipRecoveryReason.truncated =>
          ArchiveZipRecoveryStopReason.truncatedRecord,
        ArchiveZipRecoveryReason.limitExceeded =>
          ArchiveZipRecoveryStopReason.limitReached,
        _ => ArchiveZipRecoveryStopReason.rejectedRecord,
      };
      return false;
    }
  }

  int _descriptorLength(int at, int crc, int packed, int size) {
    final matches = <int>[];
    // A signatureless CRC may itself equal the optional signature. Check both
    // layouts against measured data and refuse any ambiguous interpretation.
    if (bytes.length - at >= 12 &&
        u32(at) == crc &&
        u32(at + 4) == packed &&
        u32(at + 8) == size) {
      matches.add(12);
    }
    if (bytes.length - at >= 16 &&
        u32(at) == 0x08074b50 &&
        u32(at + 4) == crc &&
        u32(at + 8) == packed &&
        u32(at + 12) == size) {
      matches.add(16);
    }
    if (matches.length != 1) {
      throw _RecordFailure(
        bytes.length - at < 12
            ? ArchiveZipRecoveryReason.truncated
            : ArchiveZipRecoveryReason.invalidDataDescriptor,
      );
    }
    return matches.single;
  }

  void _rejectAll(ArchiveZipRecoveryReason why) {
    for (var index = 0; index < entries.length; index++) {
      if (entries[index].isRecoverable) {
        entries[index] = entries[index]._reject(why);
      }
    }
  }

  void _excludeNamespaceConflicts() {
    final byName = <String, List<int>>{};
    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      if (_validName(entry.name, entry.isDirectory)) {
        byName.putIfAbsent(entry.name.toLowerCase(), () => []).add(index);
      }
    }
    for (final indices in byName.values) {
      if (indices.length > 1) {
        for (final index in indices) {
          entries[index] = entries[index]._reject(
            ArchiveZipRecoveryReason.duplicateName,
          );
        }
      }
    }
    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      if (!_validName(entry.name, entry.isDirectory)) continue;
      final parts = entry.name.toLowerCase().split('/');
      for (var count = 1; count < parts.length; count++) {
        final parents = byName[parts.take(count).join('/')];
        if (parents == null) continue;
        for (final parent in parents) {
          if (!entries[parent].isDirectory) {
            entries[parent] = entries[parent]._reject(
              ArchiveZipRecoveryReason.pathConflict,
            );
            entries[index] = entries[index]._reject(
              ArchiveZipRecoveryReason.pathConflict,
            );
          }
        }
      }
    }
  }
}

bool _validName(String name, bool directory) {
  try {
    validateArchiveWriteEntries([
      ArchiveWriteEntry(
        path: name,
        isDirectory: directory,
        size: 0,
        readChunks: directory ? null : () => const Stream.empty(),
      ),
    ]);
    return true;
  } on ArchiveViewException {
    return false;
  }
}

DateTime? _dosTime(int date, int time) {
  final year = 1980 + (date >> 9);
  final month = (date >> 5) & 15;
  final day = date & 31;
  final hour = time >> 11;
  final minute = (time >> 5) & 63;
  final second = (time & 31) * 2;
  if (month == 0 ||
      month > 12 ||
      day == 0 ||
      day > 31 ||
      hour > 23 ||
      minute > 59 ||
      second > 59) {
    return null;
  }
  final result = DateTime(year, month, day, hour, minute, second);
  return result.year == year &&
          result.month == month &&
          result.day == day &&
          result.hour == hour &&
          result.minute == minute &&
          result.second == second
      ? result
      : null;
}

class _RecordFailure implements Exception {
  const _RecordFailure(this.reason);
  final ArchiveZipRecoveryReason reason;
}

class _RecoveredPayload {
  const _RecoveredPayload(this.bytes, this.consumed, this.crc32, this.sha256);
  final Uint8List bytes;
  final int consumed;
  final int crc32;
  final String sha256;
}

Future<_RecoveredPayload> _decodeKnown(
  Uint8List source,
  int offset,
  int packed,
  int method,
  int size,
  int limit,
  _RecoveryOperation operation,
) async {
  if (size > limit) {
    throw const _RecordFailure(ArchiveZipRecoveryReason.limitExceeded);
  }
  if (offset < 0 ||
      packed < 0 ||
      offset > source.length ||
      packed > source.length - offset) {
    throw const _RecordFailure(ArchiveZipRecoveryReason.truncated);
  }
  if (method == 8) {
    final result = await _inflate(source, offset, packed, size, operation);
    if (result.bytes.length != size) {
      throw const _RecordFailure(ArchiveZipRecoveryReason.sizeMismatch);
    }
    if (result.consumed != packed) {
      throw const _RecordFailure(ArchiveZipRecoveryReason.invalidData);
    }
    return result;
  }
  if (method != 0 || size != packed) {
    throw const _RecordFailure(ArchiveZipRecoveryReason.sizeMismatch);
  }
  final bytes = Uint8List(size);
  var crc = 0;
  final digest = _DigestSink();
  final hash = sha256.startChunkedConversion(digest);
  for (var at = 0; at < size; at += _ioChunkSize) {
    await operation.checkpoint();
    final end = _min(at + _ioChunkSize, size);
    bytes.setRange(at, end, source, offset + at);
    final chunk = Uint8List.sublistView(bytes, at, end);
    crc = codecs.getCrc32(chunk, crc);
    hash.add(chunk);
  }
  hash.close();
  return _RecoveredPayload(bytes, packed, crc, digest.value!);
}

Future<_RecoveredPayload> _inflate(
  Uint8List source,
  int offset,
  int packedLimit,
  int outputLimit,
  _RecoveryOperation operation,
) async {
  final builder = BytesBuilder(copy: false);
  var crc = 0;
  final digest = _DigestSink();
  final hash = sha256.startChunkedConversion(digest);
  final inflater = koni_codecs.RawInflater(
    onOutput: (chunk) {
      operation.check();
      if (chunk.length > outputLimit - builder.length) {
        throw const _RecordFailure(ArchiveZipRecoveryReason.limitExceeded);
      }
      builder.add(chunk);
      crc = codecs.getCrc32(chunk, crc);
      hash.add(chunk);
    },
  );
  var consumed = 0;
  try {
    while (!inflater.isFinished && consumed < packedLimit) {
      await operation.checkpoint();
      final count = _min(_inflateChunkSize, packedLimit - consumed);
      consumed += inflater.addInput(
        Uint8List.sublistView(
          source,
          offset + consumed,
          offset + consumed + count,
        ),
      );
    }
    if (!inflater.isFinished) {
      throw const _RecordFailure(ArchiveZipRecoveryReason.truncated);
    }
    inflater.finish();
    consumed -= inflater.takeLeftoverBytes().length;
    hash.close();
    return _RecoveredPayload(builder.takeBytes(), consumed, crc, digest.value!);
  } on FormatException {
    throw const _RecordFailure(ArchiveZipRecoveryReason.invalidData);
  }
}

Future<void> _verifyCandidate(
  Uint8List bytes,
  List<ArchiveZipRecoveryEntry> expected,
  _RecoveryOperation operation,
) async {
  await operation.checkpoint();
  final source = koni.MemoryByteSource(bytes, name: 'recovered.zip');
  koni.ArchiveReader? reader;
  try {
    final format = await koni.builtInFormats.detect(source);
    if (format?.name != 'zip') {
      throw const ArchiveViewException('The recovered candidate is not a ZIP.');
    }
    reader = await koni.builtInFormats.openReader(
      source,
      format: format!,
      options: const koni.ArchiveReadOptions(
        maxEntrySize: kArchiveReadLimit,
        maxEntryCount: 4096,
        maxContainerDecodeSize: kArchiveReadLimit,
      ),
    );
    if (reader.entries.length != expected.length) {
      throw const ArchiveViewException(
        'The recovered ZIP entry count changed.',
      );
    }
    for (var index = 0; index < expected.length; index++) {
      await operation.checkpoint();
      final captured = expected[index];
      final entry = reader.entries[index];
      operation.progress(
        ArchiveZipRecoveryPhase.verifying,
        index,
        expected.length,
        captured.name,
      );
      if (entry.path != captured.name ||
          entry.uncompressedSize != captured.size ||
          entry.isEncrypted ||
          entry.pathEscapedRoot ||
          entry.isDirectory != captured.isDirectory ||
          !entry.isDirectory && !entry.isFile) {
        throw const ArchiveViewException('The recovered ZIP metadata changed.');
      }
      if (entry.isDirectory) continue;
      final digest = _DigestSink();
      final hash = sha256.startChunkedConversion(digest);
      var count = 0;
      await for (final chunk in reader.openRead(entry)) {
        await operation.checkpoint();
        if (chunk.length > captured.size - count) {
          throw const ArchiveViewException('The recovered ZIP member grew.');
        }
        count += chunk.length;
        hash.add(chunk);
      }
      hash.close();
      if (count != captured.size || digest.value != captured._sha256) {
        throw const ArchiveViewException(
          'The recovered ZIP content failed verification.',
        );
      }
    }
    operation.progress(
      ArchiveZipRecoveryPhase.verifying,
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

/// This writer sink bounds capacity as well as logical bytes. Geometric growth
/// never reserves more than the declared output limit.
class _RecoveryOutput extends codecs.OutputStream {
  _RecoveryOutput(this.limit, this.check)
    : _buffer = Uint8List(_min(limit, 32768)),
      super(byteOrder: codecs.ByteOrder.littleEndian);
  final int limit;
  final void Function() check;
  Uint8List _buffer;
  @override
  int length = 0;

  void _allow(int count) {
    check();
    if (count < 0 || count > limit - length) {
      throw const ArchiveViewException(
        'The recovered ZIP exceeds its output limit.',
      );
    }
    final required = length + count;
    if (required > _buffer.length) {
      final grown = _min(limit, _buffer.length * 2);
      final next = grown > required ? grown : required;
      _buffer = Uint8List(next)..setRange(0, length, _buffer);
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
