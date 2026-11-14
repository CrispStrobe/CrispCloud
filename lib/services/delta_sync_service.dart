// lib/services/delta_sync_service.dart
//
// Validated fixed-block plans and bounded native delta download preparation.
// Changed remote blocks and verified reusable local blocks reconstruct a
// complete private candidate through the existing native staged publisher.
// Upload planning remains available for diagnostics; raw remote block-write
// callbacks cannot establish a safe publication contract and are refused.
//
// Algorithm:
//   1. Split the file into fixed-size blocks (default 4 MB).
//   2. For each block compute an Adler-32 "weak" hash (fast, O(n)) and a
//      SHA-256 "strong" hash (collision-resistant).
//   3. Compare the local BlockMap against the previously stored remote
//      BlockMap to find changed blocks.
//   4. Bind every operation and final length to source and baseline maps.
//   5. Verify all reconstructed bytes, original destination and source version
//      before the native publisher enters its existing replacement boundary.
//
// Adler-32 rolling update allows O(1) advancement of a sliding window, but
// in practice we recompute per fixed block boundary so rolling is available
// for callers who implement rsync-style sliding-window search.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import 'file_operation_backend.dart';
import 'file_operation_content_strategy.dart';
import 'file_operation_service.dart';
import 'local_file_service.dart';
import 'log_service.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const int _kDefaultBlockSize = 4 * 1024 * 1024; // 4 MB
const int _kMinBlockSize = 64 * 1024; // 64 KB
const int _kMaxBlockSize = 64 * 1024 * 1024; // 64 MB
const int _kDeltaSyncMinSize =
    10 * 1024 * 1024; // 10 MB — below this not worth it

/// The admitted native delta profile has independent file, map and cache limits.
const int deltaMaxFileSize = 8 * 1024 * 1024 * 1024;
const int deltaMaxBlockCount = deltaMaxFileSize ~/ _kMinBlockSize;
const int deltaMaxCacheBytes = 32 * 1024 * 1024;

final _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

class DeltaSyncCancelled implements Exception {
  const DeltaSyncCancelled();

  @override
  String toString() => 'Delta preparation was cancelled.';
}

/// Opaque revision identity, never a claim that an ETag is a content digest.
/// [storageId] must identify the original endpoint/account/bucket namespace.
class BlockMapIdentity {
  const BlockMapIdentity({
    required this.storageId,
    required this.objectPath,
    required this.version,
    required this.totalSize,
  });

  final String storageId;
  final String objectPath;
  final String version;
  final int totalSize;

  void validate() {
    _validateText(storageId, 'storageId');
    _validateText(objectPath, 'objectPath');
    _validateText(version, 'version');
    _validateFileSize(totalSize);
  }

  bool matches(BlockMapIdentity other) {
    validate();
    other.validate();
    return storageId == other.storageId &&
        objectPath == other.objectPath &&
        version == other.version &&
        totalSize == other.totalSize;
  }

  Map<String, dynamic> toJson() {
    validate();
    return {
      'schemaVersion': 1,
      'storageId': storageId,
      'objectPath': objectPath,
      'version': version,
      'totalSize': totalSize,
    };
  }

  factory BlockMapIdentity.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != 1) {
      throw const FormatException('Unsupported block-map identity version.');
    }
    final identity = BlockMapIdentity(
      storageId: _jsonString(json, 'storageId'),
      objectPath: _jsonString(json, 'objectPath'),
      version: _jsonString(json, 'version'),
      totalSize: _jsonInt(json, 'totalSize'),
    );
    identity.validate();
    return identity;
  }
}

// Adler-32 modulus (largest prime below 2^16)
const int _kAdlerMod = 65521;

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

/// Signature for a single block of a file.
class BlockSignature {
  final int blockIndex;
  final int offset;
  final int size;

  /// Adler-32 rolling hash — fast pre-filter.
  final int weakHash;

  /// SHA-256 hex digest — collision-resistant confirmation.
  final String strongHash;

  const BlockSignature({
    required this.blockIndex,
    required this.offset,
    required this.size,
    required this.weakHash,
    required this.strongHash,
  });

  Map<String, dynamic> toJson() => {
    'blockIndex': blockIndex,
    'offset': offset,
    'size': size,
    'weakHash': weakHash,
    'strongHash': strongHash,
  };

  factory BlockSignature.fromJson(Map<String, dynamic> j) => BlockSignature(
    blockIndex: j['blockIndex'] as int,
    offset: j['offset'] as int,
    size: j['size'] as int,
    weakHash: j['weakHash'] as int,
    strongHash: j['strongHash'] as String,
  );

  @override
  bool operator ==(Object other) =>
      other is BlockSignature &&
      blockIndex == other.blockIndex &&
      offset == other.offset &&
      size == other.size &&
      weakHash == other.weakHash &&
      strongHash == other.strongHash;

  @override
  int get hashCode =>
      Object.hash(blockIndex, offset, size, weakHash, strongHash);

  @override
  String toString() =>
      'BlockSignature(#$blockIndex offset=$offset size=$size '
      'weak=0x${weakHash.toRadixString(16)} '
      'strong=${strongHash.length > 8 ? strongHash.substring(0, 8) : strongHash}…)';
}

/// Complete block map for a file: one [BlockSignature] per block.
class BlockMap {
  final String filePath;
  final int totalSize;
  final int blockSize;
  final int blockCount;
  final List<BlockSignature> signatures;
  final DateTime createdAt;
  final BlockMapIdentity? identity;
  // Transient provenance for a local source explicitly scanned in this
  // process. JSON paths alone never authorize reopening a host source file.
  final FileStat? _localSourceStamp;

  const BlockMap({
    required this.filePath,
    required this.totalSize,
    required this.blockSize,
    required this.blockCount,
    required this.signatures,
    required this.createdAt,
    this.identity,
  }) : _localSourceStamp = null;

  const BlockMap._captured({
    required this.filePath,
    required this.totalSize,
    required this.blockSize,
    required this.blockCount,
    required this.signatures,
    required this.createdAt,
    this.identity,
    required FileStat? sourceStamp,
  }) : _localSourceStamp = sourceStamp;

  void validate() {
    _validateText(filePath, 'filePath');
    _validateFileSize(totalSize);
    _validateBlockSize(blockSize);
    final expectedCount = (totalSize + blockSize - 1) ~/ blockSize;
    if (blockCount != expectedCount ||
        blockCount > deltaMaxBlockCount ||
        signatures.length != expectedCount) {
      throw const FormatException('Contradictory block-map count or length.');
    }
    for (var i = 0; i < signatures.length; i++) {
      final signature = signatures[i];
      final offset = i * blockSize;
      final expectedSize = totalSize - offset < blockSize
          ? totalSize - offset
          : blockSize;
      if (signature.blockIndex != i ||
          signature.offset != offset ||
          signature.size != expectedSize ||
          signature.weakHash < 0 ||
          signature.weakHash > 0xffffffff ||
          !_sha256Pattern.hasMatch(signature.strongHash)) {
        throw const FormatException('Invalid block-map span or signature.');
      }
    }
    identity?.validate();
    if (identity != null && identity!.totalSize != totalSize) {
      throw const FormatException('Block-map identity length does not match.');
    }
  }

  BlockMap withIdentity(BlockMapIdentity value) {
    validate();
    value.validate();
    final map = BlockMap(
      filePath: filePath,
      totalSize: totalSize,
      blockSize: blockSize,
      blockCount: blockCount,
      signatures: List.unmodifiable(signatures),
      createdAt: createdAt,
      identity: value,
    );
    map.validate();
    return map;
  }

  bool matchesIdentity(BlockMapIdentity expected) {
    validate();
    return identity?.matches(expected) ?? false;
  }

  Map<String, dynamic> toJson() {
    validate();
    return {
      'schemaVersion': 2,
      'filePath': filePath,
      'totalSize': totalSize,
      'blockSize': blockSize,
      'blockCount': blockCount,
      'signatures': signatures.map((s) => s.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      if (identity != null) 'identity': identity!.toJson(),
    };
  }

  /// Legacy maps remain useful for local planning, but have no remote identity.
  factory BlockMap.fromJson(Map<String, dynamic> j) {
    if (j.containsKey('schemaVersion') && j['schemaVersion'] != 2) {
      throw const FormatException('Unsupported block-map schema version.');
    }
    final signatures = j['signatures'];
    if (signatures is! List || signatures.length > deltaMaxBlockCount) {
      throw const FormatException('Invalid or excessive block-map signatures.');
    }
    final rawIdentity = j['identity'];
    if (rawIdentity != null && rawIdentity is! Map<String, dynamic>) {
      throw const FormatException('Invalid block-map identity.');
    }
    if (!j.containsKey('schemaVersion') && rawIdentity != null) {
      throw const FormatException('Legacy maps cannot declare a new identity.');
    }
    final map = BlockMap(
      filePath: _jsonString(j, 'filePath'),
      totalSize: _jsonInt(j, 'totalSize'),
      blockSize: _jsonInt(j, 'blockSize'),
      blockCount: _jsonInt(j, 'blockCount'),
      signatures: List.unmodifiable(
        signatures.map((entry) {
          if (entry is! Map<String, dynamic>) {
            throw const FormatException('Invalid block-map signature.');
          }
          return BlockSignature.fromJson(entry);
        }),
      ),
      createdAt: DateTime.parse(_jsonString(j, 'createdAt')),
      identity: rawIdentity == null
          ? null
          : BlockMapIdentity.fromJson(rawIdentity as Map<String, dynamic>),
    );
    map.validate();
    return map;
  }

  @override
  String toString() =>
      'BlockMap($filePath totalSize=$totalSize blockSize=$blockSize '
      'blocks=$blockCount)';
}

/// Result of comparing two block maps.
class DeltaResult {
  final String filePath;
  final int totalBlocks;

  /// Indices of blocks that differ between local and remote.
  final List<int> changedBlocks;
  final int unchangedBlocks;
  final int totalBytes;
  final int changedBytes;
  final int? previousSize;

  /// Validated snapshots supplied by [DeltaSyncService.compareBlockMaps].
  final BlockMap? sourceMap;
  final BlockMap? baselineMap;

  const DeltaResult({
    required this.filePath,
    required this.totalBlocks,
    required this.changedBlocks,
    required this.unchangedBlocks,
    required this.totalBytes,
    required this.changedBytes,
    this.previousSize,
    this.sourceMap,
    this.baselineMap,
  });

  bool get sizeChanged => previousSize != null && previousSize != totalBytes;
  bool get isIdentical => previousSize == totalBytes && changedBlocks.isEmpty;

  /// Percentage of bytes that do NOT need to be transferred (0–100).
  double get savingsPercent {
    if (totalBytes == 0) return 100.0;
    final saved = totalBytes - changedBytes;
    return (saved / totalBytes) * 100.0;
  }

  @override
  String toString() =>
      'DeltaResult($filePath changed=${changedBlocks.length}/$totalBlocks '
      'changedBytes=$changedBytes savings=${savingsPercent.toStringAsFixed(1)}%)';
}

/// Type of a block-level operation.
enum BlockOperationType { upload, download, skip }

/// Direction of a transfer plan.
enum TransferDirection { upload, download }

/// A single block-level read/write/skip operation.
class BlockOperation {
  final BlockOperationType type;
  final int blockIndex;
  final int offset;
  final int size;
  final String? expectedSha256;

  const BlockOperation({
    required this.type,
    required this.blockIndex,
    required this.offset,
    required this.size,
    this.expectedSha256,
  });

  @override
  String toString() =>
      'BlockOperation(${type.name} #$blockIndex offset=$offset size=$size)';
}

/// Complete plan for transferring changed blocks.
class BlockTransferPlan {
  final String filePath;
  final int blockSize;
  final List<int> changedBlockIndices;
  final int totalSize;
  final int transferSize;
  final List<BlockOperation> operations;
  final TransferDirection? direction;
  final BlockMap? sourceMap;
  final BlockMap? baselineMap;

  const BlockTransferPlan({
    required this.filePath,
    required this.blockSize,
    required this.changedBlockIndices,
    required this.totalSize,
    required this.transferSize,
    required this.operations,
    this.direction,
    this.sourceMap,
    this.baselineMap,
  });

  /// Savings vs a full file transfer (0–100).
  double get savingsPercent {
    if (totalSize == 0) return 100.0;
    return ((totalSize - transferSize) / totalSize) * 100.0;
  }

  @override
  String toString() =>
      'BlockTransferPlan($filePath changed=${changedBlockIndices.length} '
      'transferSize=$transferSize savings=${savingsPercent.toStringAsFixed(1)}%)';
}

// ---------------------------------------------------------------------------
// DeltaSyncService
// ---------------------------------------------------------------------------

class DeltaSyncService {
  static const _log = Log('DeltaSyncService');

  // -------------------------------------------------------------------------
  // Adler-32
  // -------------------------------------------------------------------------

  /// Compute Adler-32 checksum of [data].
  ///
  /// Reference: RFC 1950 §9.
  /// Known test vector: adler32("Wikipedia") == 0x11E60398
  int adler32(List<int> data) {
    int a = 1, b = 0;
    for (final byte in data) {
      a = (a + (byte & 0xFF)) % _kAdlerMod;
      b = (b + a) % _kAdlerMod;
    }
    return (b << 16) | a;
  }

  /// O(1) rolling Adler-32 update when a sliding window advances by one byte.
  ///
  /// [hash]      — current Adler-32 of the window [i .. i+blockSize-1].
  /// [oldByte]   — byte leaving the window (at position i).
  /// [newByte]   — byte entering the window (at position i + blockSize).
  /// [blockSize] — width of the sliding window.
  ///
  /// Derivation:
  ///   A = (a - oldByte + newByte)              mod M
  ///   B = (b - blockSize*oldByte + A - 1)      mod M
  int rollingAdler32Update(int hash, int oldByte, int newByte, int blockSize) {
    int a = hash & 0xFFFF;
    int b = (hash >> 16) & 0xFFFF;

    a = (a - (oldByte & 0xFF) + (newByte & 0xFF)) % _kAdlerMod;
    if (a < 0) a += _kAdlerMod;

    b = (b - blockSize * (oldByte & 0xFF) + a - 1) % _kAdlerMod;
    if (b < 0) b += _kAdlerMod;

    return (b << 16) | a;
  }

  // -------------------------------------------------------------------------
  // SHA-256
  // -------------------------------------------------------------------------

  /// Compute SHA-256 hex digest of [data].
  String sha256Hex(List<int> data) => sha256.convert(data).toString();

  // -------------------------------------------------------------------------
  // shouldUseDeltaSync
  // -------------------------------------------------------------------------

  /// Returns true when [fileSize] is large enough that computing block
  /// signatures pays off compared to a simple full-file transfer.
  bool shouldUseDeltaSync(int fileSize, {int minSize = _kDeltaSyncMinSize}) =>
      fileSize >= minSize;

  // -------------------------------------------------------------------------
  // computeBlockMap
  // -------------------------------------------------------------------------

  /// Scan [filePath] in [blockSize]-byte chunks and return a [BlockMap].
  ///
  /// Reads the file via [RandomAccessFile] so only one block lives in memory
  /// at a time.
  ///
  /// [onProgress] — called after each block: (processedBlocks, totalBlocks,
  /// processedBytes).
  Future<BlockMap> computeBlockMap(
    String filePath, {
    int blockSize = _kDefaultBlockSize,
    void Function(int processedBlocks, int totalBlocks, int processedBytes)?
    onProgress,
    Future<void> Function()? checkpoint,
    bool Function()? isCancelled,
  }) async {
    _validateBlockSize(blockSize);
    _validateText(filePath, 'filePath');
    Future<void> check() async {
      if (isCancelled?.call() ?? false) throw const DeltaSyncCancelled();
      await checkpoint?.call();
      if (isCancelled?.call() ?? false) throw const DeltaSyncCancelled();
    }

    await check();
    final file = File(filePath);
    final before = _regularFileStamp(filePath);
    final fileSize = before.size;
    _validateFileSize(fileSize);
    final blockCount = fileSize == 0
        ? 0
        : ((fileSize + blockSize - 1) ~/ blockSize);

    _log.debug(
      'computeBlockMap: $filePath '
      'size=$fileSize blocks=$blockCount blockSize=$blockSize',
    );

    final signatures = <BlockSignature>[];

    final raf = await file.open(mode: FileMode.read);
    try {
      if (await raf.length() != fileSize) {
        throw StateError('The file changed before block-map reading.');
      }
      for (int i = 0; i < blockCount; i++) {
        final offset = i * blockSize;
        final actualSize = (offset + blockSize > fileSize)
            ? (fileSize - offset)
            : blockSize;

        final buf = await _readExact(raf, actualSize, check);

        signatures.add(
          BlockSignature(
            blockIndex: i,
            offset: offset,
            size: actualSize,
            weakHash: adler32(buf),
            strongHash: sha256Hex(buf),
          ),
        );

        onProgress?.call(i + 1, blockCount, offset + actualSize);
      }
      await check();
      if (await raf.length() != fileSize ||
          !_sameFileStamp(before, _regularFileStamp(filePath))) {
        throw StateError('The file changed while its block map was read.');
      }
    } finally {
      await raf.close();
    }

    return BlockMap._captured(
      filePath: filePath,
      totalSize: fileSize,
      blockSize: blockSize,
      blockCount: blockCount,
      signatures: List.unmodifiable(signatures),
      createdAt: DateTime.now(),
      sourceStamp: before,
    );
  }

  // -------------------------------------------------------------------------
  // compareBlockMaps
  // -------------------------------------------------------------------------

  /// Compare [local] and [remote] block maps and return which blocks differ.
  ///
  /// A block is unchanged iff both weak and strong hashes match.
  /// Blocks that only exist in [local] (file grew) are marked changed.
  /// Remote-only trailing blocks require a final length change even when no
  /// retained content block differs. [DeltaResult.isIdentical] includes size.
  DeltaResult compareBlockMaps(BlockMap local, BlockMap remote) {
    final source = _snapshotMap(local);
    final baseline = _snapshotMap(remote);
    if (source.blockSize != baseline.blockSize) {
      throw const FormatException('Delta maps must use the same block size.');
    }

    final changedIndices = <int>[];
    int changedBytes = 0;

    for (final localSig in source.signatures) {
      final remoteSig = localSig.blockIndex < baseline.signatures.length
          ? baseline.signatures[localSig.blockIndex]
          : null;
      if (remoteSig == null ||
          localSig.offset != remoteSig.offset ||
          localSig.size != remoteSig.size ||
          localSig.weakHash != remoteSig.weakHash ||
          localSig.strongHash != remoteSig.strongHash) {
        changedIndices.add(localSig.blockIndex);
        changedBytes += localSig.size;
      }
    }

    return DeltaResult(
      filePath: source.filePath,
      totalBlocks: source.blockCount,
      changedBlocks: List.unmodifiable(changedIndices),
      unchangedBlocks: source.blockCount - changedIndices.length,
      totalBytes: source.totalSize,
      changedBytes: changedBytes,
      previousSize: baseline.totalSize,
      sourceMap: source,
      baselineMap: baseline,
    );
  }

  // -------------------------------------------------------------------------
  // createTransferPlan
  // -------------------------------------------------------------------------

  /// Turn a [DeltaResult] into an ordered list of [BlockOperation]s.
  ///
  /// Changed blocks receive an upload or download operation (depending on
  /// [direction]); all other blocks receive a skip operation.
  BlockTransferPlan createTransferPlan(
    DeltaResult deltaResult,
    TransferDirection direction,
    BlockMap localMap,
  ) {
    final recordedSource = deltaResult.sourceMap;
    final baseline = deltaResult.baselineMap;
    if (recordedSource == null || baseline == null) {
      throw const FormatException(
        'A transfer plan requires a validated source and baseline comparison.',
      );
    }
    final source = _snapshotMap(localMap);
    if (!_sameMapContents(source, recordedSource)) {
      throw const FormatException(
        'The transfer source differs from its comparison.',
      );
    }
    final expected = compareBlockMaps(source, baseline);
    if (!_sameIndices(expected.changedBlocks, deltaResult.changedBlocks) ||
        expected.previousSize != deltaResult.previousSize ||
        expected.totalBytes != deltaResult.totalBytes ||
        expected.totalBlocks != deltaResult.totalBlocks ||
        expected.unchangedBlocks != deltaResult.unchangedBlocks ||
        expected.changedBytes != deltaResult.changedBytes) {
      throw const FormatException(
        'The delta comparison was changed or is inconsistent.',
      );
    }
    final changedSet = Set<int>.from(deltaResult.changedBlocks);
    final ops = <BlockOperation>[];
    int transferSize = 0;

    for (final sig in source.signatures) {
      final isChanged = changedSet.contains(sig.blockIndex);
      final opType = !isChanged
          ? BlockOperationType.skip
          : direction == TransferDirection.upload
          ? BlockOperationType.upload
          : BlockOperationType.download;

      ops.add(
        BlockOperation(
          type: opType,
          blockIndex: sig.blockIndex,
          offset: sig.offset,
          size: sig.size,
          expectedSha256: sig.strongHash,
        ),
      );
      if (isChanged) transferSize += sig.size;
    }

    return BlockTransferPlan(
      filePath: source.filePath,
      blockSize: source.blockSize,
      changedBlockIndices: List.unmodifiable(deltaResult.changedBlocks),
      totalSize: source.totalSize,
      transferSize: transferSize,
      operations: List.unmodifiable(ops),
      direction: direction,
      sourceMap: source,
      baselineMap: expected.baselineMap,
    );
  }

  // -------------------------------------------------------------------------
  // applyDelta
  // -------------------------------------------------------------------------

  /// Reconstruct a download through the existing native staged publisher.
  ///
  /// This compatibility entry point uses the same scoped contents and renewed
  /// publication proofs as queued copies. It does not create a queue record,
  /// acquire path claims or authorize restart. The captured destination backend
  /// supplies its existing access scope and native check/rename boundary.
  ///
  /// Upload execution remains unavailable: a raw remote write callback cannot
  /// establish private staging, verification and conditional publication.
  Future<void> applyDelta(
    BlockTransferPlan plan,
    String localPath, {
    Future<List<int>> Function(int blockIndex, int offset, int size)?
    remoteReadBlock,
    Future<void> Function(int blockIndex, int offset, List<int> data)?
    remoteWriteBlock,
    void Function(int processedBlocks, int totalBlocks, int processedBytes)?
    onProgress,
    FileOperationBackend? destinationBackend,
    Future<void> Function()? revalidateSource,
    Future<void> Function()? checkpoint,
    bool Function()? isCancelled,
  }) => withPreparedDelta<void>(
    plan,
    localPath,
    destinationBackend: destinationBackend,
    remoteReadBlock: remoteReadBlock,
    revalidateSource: revalidateSource,
    checkpoint: checkpoint,
    isCancelled: isCancelled,
    onProgress: onProgress,
    consume: (contents) async {
      final prepared = contents as _PreparedDeltaContents;
      await prepared.backend.writePreparedFile(
        localPath,
        contents.openRead(),
        contents.length,
        replace: true,
        verifyStaged: contents.verifyStaged,
        checkpoint: (state) async {
          switch (state['phase']) {
            case 'committed':
              await contents.committed();
            case 'committing':
              await contents.revalidateBeforePublication();
            default:
              await prepared.check();
          }
        },
      );
    },
  );

  /// Hold the captured native access scope while one bound reconstruction is
  /// consumed by the ordinary staged copy writer.
  ///
  /// The returned contents are live only inside [consume]. Their complete
  /// logical stream may be opened once. [PreparedFileContents.verifyStaged]
  /// must precede [PreparedFileContents.revalidateBeforePublication], which
  /// must run after all awaited journal/control publication checkpoints. No
  /// awaited user callback may follow that final proof before publication.
  Future<T> withPreparedDelta<T>(
    BlockTransferPlan plan,
    String localPath, {
    required FileOperationBackend? destinationBackend,
    required Future<T> Function(PreparedFileContents contents) consume,
    FileItem? existingDestination,
    Future<List<int>> Function(int blockIndex, int offset, int size)?
    remoteReadBlock,
    Future<void> Function()? revalidateSource,
    Future<void> Function()? checkpoint,
    bool Function()? isCancelled,
    void Function(int processedBlocks, int totalBlocks, int processedBytes)?
    onProgress,
    Future<void> Function()? onCommitted,
  }) async {
    // Reject and freeze caller-owned plans before access, callbacks or staging.
    final execution = _validatedPlan(plan);
    if (execution.direction == TransferDirection.upload) {
      throw UnsupportedError(
        'Delta upload requires a separately qualified staged publication '
        'contract; direct block-write callbacks are unavailable.',
      );
    }
    final backend = _preparedBackend(destinationBackend);
    final source = execution.sourceMap!;
    final baseline = execution.baselineMap!;
    _validateReviewedDestination(existingDestination, localPath);
    if (source.identity == null && source._localSourceStamp == null) {
      throw const FormatException(
        'An unbound map cannot authorize opening its recorded source path.',
      );
    }
    _validateBaselinePath(baseline, localPath);
    if (source.identity != null && revalidateSource == null) {
      throw ArgumentError(
        'A remote delta source requires an awaited revision revalidation.',
      );
    }
    if (execution.operations.any(
          (op) => op.type == BlockOperationType.download,
        ) &&
        remoteReadBlock == null) {
      throw ArgumentError(
        'remoteReadBlock is required for changed download blocks.',
      );
    }

    Stream<List<int>> reconstruct(
      Future<void> Function() check,
      void Function() checkNow,
    ) async* {
      var processed = 0;
      var transferred = 0;
      await check();
      final reader = await File(localPath).open(mode: FileMode.read);
      try {
        for (final op in execution.operations) {
          await check();
          Uint8List bytes;
          if (op.type == BlockOperationType.download) {
            final received = await remoteReadBlock!(
              op.blockIndex,
              op.offset,
              op.size,
            );
            checkNow();
            if (received.length != op.size) {
              throw StateError(
                'The delta range did not have its exact requested length.',
              );
            }
            if (received.any((byte) => byte < 0 || byte > 255)) {
              throw StateError('A delta range contained invalid byte values.');
            }
            bytes = Uint8List.fromList(received);
          } else {
            await reader.setPosition(op.offset);
            bytes = await _readExact(reader, op.size, check);
          }
          final signature = source.signatures[op.blockIndex];
          if (sha256Hex(bytes) != op.expectedSha256 ||
              adler32(bytes) != signature.weakHash) {
            throw StateError(
              'A delta block does not match the captured source.',
            );
          }
          await check();
          yield bytes;
          if (op.type == BlockOperationType.download) transferred += op.size;
          processed++;
          onProgress?.call(processed, execution.operations.length, transferred);
        }
        await check();
      } finally {
        await reader.close();
      }
    }

    return _withPreparedContents(
      localPath,
      backend: backend,
      length: source.totalSize,
      destinationExists: true,
      existingDestination: existingDestination,
      baselineMap: baseline,
      knownSourceMap: source,
      sourceIdentity: source.identity,
      read: reconstruct,
      revalidateSource: revalidateSource,
      checkpoint: checkpoint,
      isCancelled: isCancelled,
      onCommitted: onCommitted,
      consume: consume,
    );
  }

  /// Verify a one-pass conditional remote download whose map is completed by
  /// reading its stream. [sourceMap] is called exactly once, after exact EOF.
  ///
  /// A supplied baseline must come from [computeBlockMap] in this process and
  /// name this destination. Otherwise an existing destination is scanned under
  /// the captured backend's scope. A new destination must remain absent through
  /// publication. This helper creates neither a journal nor a trust receipt;
  /// the provider must establish remote provenance and version-bound reads.
  Future<T> withPreparedVerifiedDownload<T>(
    String localPath, {
    required FileOperationBackend? destinationBackend,
    required BlockMapIdentity sourceIdentity,
    required Stream<List<int>> Function() openRead,
    required BlockMap Function() sourceMap,
    required Future<void> Function() revalidateSource,
    required Future<T> Function(PreparedFileContents contents) consume,
    required bool destinationExists,
    FileItem? existingDestination,
    BlockMap? baselineMap,
    Future<void> Function()? checkpoint,
    bool Function()? isCancelled,
    Future<void> Function()? onCommitted,
  }) async {
    sourceIdentity.validate();
    _validateText(localPath, 'destination path');
    final backend = _preparedBackend(destinationBackend);
    _validateReviewedDestination(existingDestination, localPath);
    final baseline = baselineMap == null ? null : _snapshotMap(baselineMap);
    if (!destinationExists &&
        (baseline != null || existingDestination != null)) {
      throw const FormatException(
        'An absent destination cannot have a baseline.',
      );
    }
    if (baseline != null) {
      _validateBaselinePath(baseline, localPath);
      if (baseline._localSourceStamp == null) {
        throw const FormatException(
          'A supplied destination baseline requires a current local scan.',
        );
      }
    }
    return _withPreparedContents(
      localPath,
      backend: backend,
      length: sourceIdentity.totalSize,
      destinationExists: destinationExists,
      existingDestination: existingDestination,
      baselineMap: baseline,
      sourceIdentity: sourceIdentity,
      completedSourceMap: sourceMap,
      read: (_, _) => openRead(),
      revalidateSource: revalidateSource,
      checkpoint: checkpoint,
      isCancelled: isCancelled,
      onCommitted: onCommitted,
      consume: consume,
    );
  }

  Future<T> _withPreparedContents<T>(
    String localPath, {
    required LocalOperationBackend backend,
    required int length,
    required bool destinationExists,
    required Stream<List<int>> Function(
      Future<void> Function() check,
      void Function() checkNow,
    )
    read,
    required Future<T> Function(PreparedFileContents contents) consume,
    FileItem? existingDestination,
    BlockMap? baselineMap,
    BlockMap? knownSourceMap,
    BlockMapIdentity? sourceIdentity,
    BlockMap Function()? completedSourceMap,
    Future<void> Function()? revalidateSource,
    Future<void> Function()? checkpoint,
    bool Function()? isCancelled,
    Future<void> Function()? onCommitted,
  }) async {
    final prepared = _PreparedDeltaContents(
      service: this,
      backend: backend,
      localPath: localPath,
      expectedLength: length,
      destinationExists: destinationExists,
      existingDestination: existingDestination,
      baseline: baselineMap,
      source: knownSourceMap,
      sourceIdentity: sourceIdentity,
      completedSourceMap: completedSourceMap,
      read: read,
      revalidateSource: revalidateSource,
      checkpoint: checkpoint,
      isCancelled: isCancelled,
      onCommitted: onCommitted,
    );
    try {
      await prepared.check();
      return await backend.service.withFileOperationAccess(
        destinationExists ? localPath : backend.paths.dirname(localPath),
        () async {
          await prepared.initialize();
          return consume(prepared);
        },
      );
    } finally {
      prepared.invalidate();
    }
  }

  BlockTransferPlan _validatedPlan(BlockTransferPlan plan) {
    final source = plan.sourceMap;
    final baseline = plan.baselineMap;
    final direction = plan.direction;
    if (source == null || baseline == null || direction == null) {
      throw const FormatException('Unbound delta transfer plan.');
    }
    final expected = createTransferPlan(
      compareBlockMaps(source, baseline),
      direction,
      source,
    );
    if (plan.filePath != expected.filePath ||
        plan.blockSize != expected.blockSize ||
        plan.totalSize != expected.totalSize ||
        plan.transferSize != expected.transferSize ||
        !_sameIndices(plan.changedBlockIndices, expected.changedBlockIndices) ||
        plan.operations.length != expected.operations.length) {
      throw const FormatException('Contradictory delta transfer plan.');
    }
    for (var i = 0; i < expected.operations.length; i++) {
      final actual = plan.operations[i];
      final wanted = expected.operations[i];
      if (actual.type != wanted.type ||
          actual.blockIndex != wanted.blockIndex ||
          actual.offset != wanted.offset ||
          actual.size != wanted.size ||
          actual.expectedSha256 != wanted.expectedSha256) {
        throw const FormatException(
          'Invalid delta operation or content binding.',
        );
      }
    }
    return expected;
  }

  Future<FileStat> _verifyLocalFile(
    String filePath,
    BlockMap expected,
    Future<void> Function() check,
  ) async {
    await check();
    final before = _regularFileStamp(filePath);
    if (before.size != expected.totalSize) {
      throw StateError('The delta file length differs from its captured map.');
    }
    final reader = await File(filePath).open(mode: FileMode.read);
    try {
      if (await reader.length() != expected.totalSize) {
        throw StateError('The delta file changed before verification.');
      }
      for (final signature in expected.signatures) {
        final bytes = await _readExact(reader, signature.size, check);
        if (sha256Hex(bytes) != signature.strongHash ||
            adler32(bytes) != signature.weakHash) {
          throw StateError(
            'The delta file contents differ from its captured map.',
          );
        }
      }
      await check();
      if (await reader.length() != expected.totalSize ||
          !_sameFileStamp(before, _regularFileStamp(filePath))) {
        throw StateError('The delta file changed while it was verified.');
      }
      return before;
    } finally {
      await reader.close();
    }
  }

  // -------------------------------------------------------------------------
  // estimateSavings
  // -------------------------------------------------------------------------

  /// Compute the percentage of bytes that would NOT need to be transferred
  /// if [localPath] were synced against [remoteBlockMap] (0 = full upload
  /// needed, 100 = file identical).
  Future<double> estimateSavings(
    String localPath,
    BlockMap remoteBlockMap,
  ) async {
    final localMap = await computeBlockMap(
      localPath,
      blockSize: remoteBlockMap.blockSize,
    );
    final delta = compareBlockMaps(localMap, remoteBlockMap);
    return delta.savingsPercent;
  }

  // -------------------------------------------------------------------------
  // Block map persistence
  // -------------------------------------------------------------------------

  /// Persist a bounded, versioned map using a flushed same-directory candidate.
  /// A failed write/rename never truncates a preceding usable cache.
  Future<void> saveBlockMap(BlockMap blockMap, String cachePath) async {
    final snapshot = _snapshotMap(blockMap);
    final bytes = utf8.encode(jsonEncode(snapshot.toJson()));
    if (bytes.length > deltaMaxCacheBytes) {
      throw const FormatException('Block-map cache exceeds its byte limit.');
    }
    final file = File(cachePath);
    await file.parent.create(recursive: true);
    final type = await FileSystemEntity.type(cachePath, followLinks: false);
    if (type != FileSystemEntityType.file &&
        type != FileSystemEntityType.notFound) {
      throw FileSystemException(
        'The block-map cache is not a regular file.',
        cachePath,
      );
    }
    final temporary = await file.parent.createTemp('.crisp-block-map-');
    try {
      final candidate = File(p.join(temporary.path, 'map.json'));
      await candidate.writeAsBytes(bytes, flush: true);
      final current = await FileSystemEntity.type(
        cachePath,
        followLinks: false,
      );
      if (current != FileSystemEntityType.file &&
          current != FileSystemEntityType.notFound) {
        throw FileSystemException(
          'The block-map cache changed type.',
          cachePath,
        );
      }
      await candidate.rename(cachePath);
    } finally {
      await temporary.delete(recursive: true);
    }
    _log.debug('saveBlockMap → $cachePath');
  }

  /// Load a [BlockMap] from [cachePath].  Returns null if the file does not
  /// exist or cannot be parsed.
  Future<BlockMap?> loadBlockMap(String cachePath) async {
    final file = File(cachePath);
    try {
      if (FileSystemEntity.typeSync(cachePath, followLinks: false) ==
          FileSystemEntityType.notFound) {
        return null;
      }
      final before = _regularFileStamp(cachePath);
      if (before.size > deltaMaxCacheBytes) return null;
      final bytes = BytesBuilder(copy: false);
      // The bound applies to actual reads as well as the initial size. A cache
      // that grows after stat cannot force an unbounded readAsString allocation.
      await for (final chunk in file.openRead(0, deltaMaxCacheBytes + 1)) {
        if (bytes.length + chunk.length > deltaMaxCacheBytes) return null;
        bytes.add(chunk);
      }
      if (!_sameFileStamp(before, _regularFileStamp(cachePath)) ||
          bytes.length != before.size) {
        return null;
      }
      final json = jsonDecode(utf8.decode(bytes.takeBytes()));
      if (json is! Map<String, dynamic>) return null;
      return BlockMap.fromJson(json);
    } catch (e) {
      _log.warn('loadBlockMap: failed to parse $cachePath: $e');
      return null;
    }
  }

  // -------------------------------------------------------------------------
  // Cache path helper
  // -------------------------------------------------------------------------

  /// Derive a stable cache path for a block map.
  ///
  /// [cacheDir] — root directory for cached block maps.
  /// [filePath] — remote path of the file.
  /// [provider] identifies the implementation; [storageId] additionally scopes
  /// remote caches to the captured endpoint/account/bucket. Legacy cache paths
  /// remain distinct and cannot acquire remote identity by filename alone.
  String blockMapCachePath(
    String cacheDir,
    String filePath,
    String provider, {
    String? storageId,
  }) {
    _validateText(filePath, 'filePath');
    _validateText(provider, 'provider');
    if (storageId != null) _validateText(storageId, 'storageId');
    final key = sha256Hex(
      utf8.encode(jsonEncode([2, provider, storageId, filePath])),
    );
    return p.join(cacheDir, 'block_maps', '$key.json');
  }
}

/// A live proof object, never a serialized execution or recovery authority.
class _PreparedDeltaContents implements PreparedFileContents {
  _PreparedDeltaContents({
    required this.service,
    required this.backend,
    required this.localPath,
    required this.expectedLength,
    required this.destinationExists,
    required this.read,
    this.existingDestination,
    this.baseline,
    this.source,
    this.sourceIdentity,
    this.completedSourceMap,
    this.revalidateSource,
    this.checkpoint,
    this.isCancelled,
    this.onCommitted,
  }) : backendIdentity = backend.identity;

  final DeltaSyncService service;
  final LocalOperationBackend backend;
  final Object backendIdentity;
  final String localPath;
  final int expectedLength;
  final bool destinationExists;
  final FileItem? existingDestination;
  final Stream<List<int>> Function(
    Future<void> Function() check,
    void Function() checkNow,
  )
  read;
  final BlockMapIdentity? sourceIdentity;
  final BlockMap Function()? completedSourceMap;
  final Future<void> Function()? revalidateSource;
  final Future<void> Function()? checkpoint;
  final bool Function()? isCancelled;
  final Future<void> Function()? onCommitted;
  BlockMap? baseline;
  BlockMap? source;
  FileStat? _originalStamp;
  String? _stagedPath;
  FileStat? _stagedStamp;
  bool _active = true;
  bool _initialized = false;
  bool _opened = false;
  bool _streamComplete = false;
  bool _verificationStarted = false;
  bool _verified = false;
  bool _publicationStarted = false;
  bool _publicationReady = false;
  bool _committed = false;

  void invalidate() => _active = false;

  void _ensureActive() {
    if (!_active) {
      throw StateError('Prepared delta contents have left their access scope.');
    }
  }

  void checkNow() {
    _ensureActive();
    if (isCancelled?.call() ?? false) throw const DeltaSyncCancelled();
    if (!backend.isCurrent || backend.identity != backendIdentity) {
      throw StateError(
        'The original delta destination is no longer available.',
      );
    }
  }

  Future<void> check() async {
    checkNow();
    await checkpoint?.call();
    checkNow();
  }

  Future<void> initialize() async {
    await check();
    if (destinationExists) {
      _assertReviewedDestination(_regularFileStamp(localPath));
      baseline ??= await service.computeBlockMap(
        localPath,
        checkpoint: check,
        isCancelled: isCancelled,
      );
      _validateBaselinePath(baseline!, localPath);
      final captured = baseline!._localSourceStamp;
      if (captured != null &&
          !_sameFileStamp(captured, _regularFileStamp(localPath))) {
        throw StateError('The captured delta destination changed.');
      }
      _originalStamp = await service._verifyLocalFile(
        localPath,
        baseline!,
        check,
      );
      if (captured != null && !_sameFileStamp(captured, _originalStamp!)) {
        throw StateError('The captured delta destination changed.');
      }
      _assertReviewedDestination(_originalStamp!);
    } else {
      _assertDestinationNow();
    }
    await _verifySource();
    _assertDestinationNow();
    _initialized = true;
  }

  @override
  int get length {
    _ensureActive();
    return expectedLength;
  }

  @override
  Stream<List<int>> openRead() {
    checkNow();
    if (!_initialized || _opened || _committed) {
      throw StateError('Prepared delta contents can be consumed only once.');
    }
    _opened = true;
    return _checkedContents();
  }

  Stream<List<int>> _checkedContents() async* {
    var received = 0;
    await check();
    _assertDestinationNow();
    await for (final chunk in read(check, checkNow)) {
      checkNow();
      if (chunk.length > _kMaxBlockSize ||
          chunk.length > expectedLength - received ||
          chunk.any((byte) => byte < 0 || byte > 255)) {
        throw StateError(
          'Prepared delta contents exceeded their byte contract.',
        );
      }
      // Own each provider buffer before any pause or asynchronous writer can
      // allow its producer to reuse it.
      final bytes = Uint8List.fromList(chunk);
      received += bytes.length;
      await check();
      yield bytes;
    }
    await check();
    if (received != expectedLength) {
      throw StateError(
        'Prepared delta contents ended before their exact length.',
      );
    }
    if (completedSourceMap != null) {
      final completed = _snapshotMap(completedSourceMap!());
      if (!completed.matchesIdentity(sourceIdentity!)) {
        throw StateError(
          'The completed map belongs to another remote revision.',
        );
      }
      source = completed;
    }
    if (source == null || source!.totalSize != expectedLength) {
      throw StateError('The prepared delta source map is incomplete.');
    }
    checkNow();
    _streamComplete = true;
  }

  @override
  Future<void> verifyStaged(FileItem staged) async {
    checkNow();
    if (!_streamComplete || _verificationStarted || _committed) {
      throw StateError(
        'A complete single-use stream is required for verification.',
      );
    }
    _verificationStarted = true;
    final path = staged.path;
    if (path == null ||
        staged.isFolder ||
        staged.isSymlink == true ||
        !backend.isRetainedStagePath(path, localPath)) {
      throw StateError(
        'The delta candidate is not a private native staged file.',
      );
    }
    _stagedPath = path;
    _stagedStamp = await service._verifyLocalFile(path, source!, check);
    await _verifyOriginal();
    await _verifySource();
    _assertFinalStamps();
    _verified = true;
  }

  @override
  Future<void> revalidateBeforePublication() async {
    checkNow();
    if (!_verified || _publicationStarted || _committed) {
      throw StateError(
        'Delta publication requires a fresh verified candidate.',
      );
    }
    _publicationStarted = true;
    // The caller has persisted its committing record and passed its final
    // pause gate. Re-read both files so time spent awaiting that durable
    // checkpoint cannot invalidate earlier content proofs.
    final candidate = await service._verifyLocalFile(
      _stagedPath!,
      source!,
      check,
    );
    if (!_sameFileStamp(_stagedStamp!, candidate)) {
      throw StateError('The delta candidate changed before publication.');
    }
    await _verifyOriginal();
    await _verifySource();
    // Only synchronous guards follow the last source revalidation. The native
    // publisher retains its documented non-CAS check/rename boundary.
    _assertFinalStamps();
    _publicationReady = true;
  }

  Future<void> _verifyOriginal() async {
    if (!destinationExists) {
      checkNow();
      _assertDestinationNow();
      return;
    }
    final current = await service._verifyLocalFile(localPath, baseline!, check);
    if (!_sameFileStamp(_originalStamp!, current)) {
      throw StateError('The delta destination changed during preparation.');
    }
  }

  Future<void> _verifySource() async {
    await check();
    final known = source;
    if (known != null && known.identity == null) {
      if (known._localSourceStamp == null ||
          !_sameFileStamp(
            known._localSourceStamp,
            _regularFileStamp(known.filePath),
          )) {
        throw StateError('The captured local delta source changed.');
      }
      await service._verifyLocalFile(known.filePath, known, check);
    }
    await revalidateSource?.call();
    checkNow();
  }

  void _assertDestinationNow() {
    if (destinationExists) {
      if (_originalStamp == null ||
          !_sameFileStamp(_originalStamp!, _regularFileStamp(localPath))) {
        throw StateError('The delta destination changed before publication.');
      }
    } else if (FileSystemEntity.typeSync(localPath, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw StateError('The new delta destination became occupied.');
    }
  }

  void _assertReviewedDestination(FileStat stamp) {
    final reviewed = existingDestination;
    if (reviewed != null &&
        (reviewed.size != stamp.size ||
            !reviewed.updatedAt!.isAtSameMomentAs(stamp.modified))) {
      throw StateError(
        'The reviewed delta destination changed before capture.',
      );
    }
  }

  void _assertFinalStamps() {
    checkNow();
    _assertDestinationNow();
    if (_stagedPath == null ||
        _stagedStamp == null ||
        !_sameFileStamp(_stagedStamp!, _regularFileStamp(_stagedPath!))) {
      throw StateError('Delta publication proof is no longer current.');
    }
    final known = source;
    if (known != null &&
        known.identity == null &&
        !_sameFileStamp(
          known._localSourceStamp!,
          _regularFileStamp(known.filePath),
        )) {
      throw StateError('The captured local delta source changed.');
    }
  }

  @override
  Future<void> committed() async {
    // A completed replacement is recorded even if cancellation/authentication
    // changes arrive in its acknowledgement. Auxiliary cache work cannot undo
    // the installation or turn it into a transfer failure.
    _ensureActive();
    if (!_publicationReady || _committed) {
      throw StateError('Delta publication has not been acknowledged once.');
    }
    _committed = true;
    try {
      await onCommitted?.call();
    } catch (error) {
      DeltaSyncService._log.warn(
        'Verified delta cache bookkeeping failed.',
        error,
      );
    }
  }
}

LocalOperationBackend _preparedBackend(FileOperationBackend? backend) {
  if (backend is! LocalOperationBackend ||
      !backend.supportsStagedVerification ||
      !backend.supportsRetainedStageCleanup) {
    throw UnsupportedError(
      'Delta downloads require a native local staged destination backend.',
    );
  }
  return backend;
}

void _validateBaselinePath(BlockMap baseline, String localPath) {
  _validateText(localPath, 'destination path');
  if (!p.equals(p.absolute(baseline.filePath), p.absolute(localPath))) {
    throw const FormatException(
      'The plan belongs to a different local destination.',
    );
  }
}

void _validateReviewedDestination(FileItem? reviewed, String localPath) {
  if (reviewed != null &&
      (reviewed.path == null ||
          !p.equals(p.absolute(reviewed.path!), p.absolute(localPath)) ||
          reviewed.isFolder ||
          reviewed.isSymlink == true ||
          reviewed.size == null ||
          reviewed.updatedAt == null)) {
    throw const FormatException(
      'Invalid reviewed native destination snapshot.',
    );
  }
}

void _validateText(String value, String name) {
  if (value.isEmpty || value.length > 8192 || value.contains('\u0000')) {
    throw FormatException('Invalid block-map $name.');
  }
}

void _validateFileSize(int value) {
  if (value < 0 || value > deltaMaxFileSize) {
    throw const FormatException('File size exceeds the bounded delta profile.');
  }
}

void _validateBlockSize(int value) {
  if (value < _kMinBlockSize || value > _kMaxBlockSize) {
    throw const FormatException(
      'Delta block size must be between 64 KiB and 64 MiB.',
    );
  }
}

int _jsonInt(Map<String, dynamic> json, String name) {
  final value = json[name];
  if (value is! int) throw FormatException('Invalid block-map $name.');
  return value;
}

String _jsonString(Map<String, dynamic> json, String name) {
  final value = json[name];
  if (value is! String) throw FormatException('Invalid block-map $name.');
  return value;
}

BlockMap _snapshotMap(BlockMap map) {
  map.validate();
  return BlockMap._captured(
    filePath: map.filePath,
    totalSize: map.totalSize,
    blockSize: map.blockSize,
    blockCount: map.blockCount,
    signatures: List.unmodifiable(map.signatures),
    createdAt: map.createdAt,
    identity: map.identity,
    sourceStamp: map._localSourceStamp,
  );
}

bool _sameMapContents(BlockMap first, BlockMap second) {
  first.validate();
  second.validate();
  if (first.filePath != second.filePath ||
      first.totalSize != second.totalSize ||
      first.blockSize != second.blockSize ||
      first.blockCount != second.blockCount ||
      (first.identity == null) != (second.identity == null) ||
      (first.identity != null && !first.identity!.matches(second.identity!))) {
    return false;
  }
  for (var i = 0; i < first.signatures.length; i++) {
    if (first.signatures[i] != second.signatures[i]) return false;
  }
  return true;
}

bool _sameIndices(List<int> first, List<int> second) {
  if (first.length != second.length) return false;
  for (var i = 0; i < first.length; i++) {
    if (first[i] != second[i]) return false;
  }
  return true;
}

FileStat _regularFileStamp(String path) {
  if (FileSystemEntity.typeSync(path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw FileSystemException(
      'Delta input must be an existing regular file.',
      path,
    );
  }
  final stamp = FileStat.statSync(path);
  if (stamp.type != FileSystemEntityType.file) {
    throw FileSystemException('Delta input changed type.', path);
  }
  return stamp;
}

bool _sameFileStamp(FileStat first, FileStat second) =>
    first.type == second.type &&
    first.size == second.size &&
    first.mode == second.mode &&
    first.modified == second.modified &&
    first.changed == second.changed;

Future<Uint8List> _readExact(
  RandomAccessFile reader,
  int length,
  Future<void> Function() check,
) async {
  final bytes = Uint8List(length);
  var consumed = 0;
  while (consumed < length) {
    await check();
    final count = await reader.readInto(bytes, consumed, length);
    if (count <= 0) {
      throw StateError('A delta file ended before its captured block length.');
    }
    consumed += count;
  }
  await check();
  return bytes;
}
