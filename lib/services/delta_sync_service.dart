// lib/services/delta_sync_service.dart
//
// Block-level delta sync for large files (VeraCrypt containers, disk images,
// database files, etc.).  Instead of re-uploading an entire file when only a
// few sectors changed, this service identifies which 4 MB blocks differ
// between a local copy and the remote, then transfers only those blocks.
//
// Algorithm:
//   1. Split the file into fixed-size blocks (default 4 MB).
//   2. For each block compute an Adler-32 "weak" hash (fast, O(n)) and a
//      SHA-256 "strong" hash (collision-resistant).
//   3. Compare the local BlockMap against the previously stored remote
//      BlockMap to find changed blocks.
//   4. Produce a BlockTransferPlan that lists only the changed blocks.
//   5. Execute the plan via caller-supplied read/write callbacks so the
//      service remains storage-provider-agnostic.
//
// Adler-32 rolling update allows O(1) advancement of a sliding window, but
// in practice we recompute per fixed block boundary so rolling is available
// for callers who implement rsync-style sliding-window search.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'file_operation_backend.dart';
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

  const BlockMap({
    required this.filePath,
    required this.totalSize,
    required this.blockSize,
    required this.blockCount,
    required this.signatures,
    required this.createdAt,
    this.identity,
  });

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

    return BlockMap(
      filePath: filePath,
      totalSize: fileSize,
      blockSize: blockSize,
      blockCount: blockCount,
      signatures: List.unmodifiable(signatures),
      createdAt: DateTime.now(),
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
  /// Every block, including reused local blocks, must match the bound source
  /// map. The complete private candidate and the original destination are
  /// verified before replacement. Empty/all-skip plans still apply final size.
  /// A source with a remote identity requires [revalidateSource]; an unbound
  /// local map is rechecked against its named local source instead.
  ///
  /// [destinationBackend] must be a current [LocalOperationBackend] with staged
  /// verification. Its existing local check/rename boundary is not an atomic
  /// compare-and-swap against external writers. This method adds no durable
  /// queue record, resume token or path reservation by itself.
  ///
  /// Cancellation is cooperative at read and verification boundaries. Once
  /// replacement is acknowledged, late cancellation does not undo success.
  /// Upload planning is available, but raw [remoteWriteBlock] callbacks cannot
  /// establish private staging, final verification and conditional publication;
  /// upload execution is refused before invoking any callback.
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
  }) async {
    // Freeze caller-owned collections and reject contradictory plans before
    // acquiring access, running callbacks, or creating a staging directory.
    final execution = _validatedPlan(plan);
    if (execution.direction == TransferDirection.upload) {
      throw UnsupportedError(
        'Delta upload requires a separately qualified staged publication '
        'contract; direct block-write callbacks are unavailable.',
      );
    }
    final backend = destinationBackend;
    if (backend is! LocalOperationBackend ||
        !backend.supportsStagedVerification) {
      throw UnsupportedError(
        'Delta downloads require a native local staged destination backend.',
      );
    }
    final source = execution.sourceMap!;
    final baseline = execution.baselineMap!;
    if (!p.equals(p.absolute(baseline.filePath), p.absolute(localPath))) {
      throw const FormatException(
        'The plan belongs to a different local destination.',
      );
    }
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
    final backendIdentity = backend.identity;
    void checkNow() {
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

    Future<void> verifySource() async {
      await check();
      if (source.identity == null) {
        await _verifyLocalFile(source.filePath, source, check);
      }
      await revalidateSource?.call();
      checkNow();
    }

    await check();
    await backend.service.withFileOperationAccess(localPath, () async {
      final originalStamp = await _verifyLocalFile(localPath, baseline, check);
      await verifySource();
      var processed = 0;
      var transferred = 0;
      String? stagedPath;
      FileStat? stagedStamp;

      Stream<List<int>> reconstructed() async* {
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
              // Own bytes across asynchronous publication; providers may reuse
              // their response buffers after returning from the callback.
              if (received.any((byte) => byte < 0 || byte > 255)) {
                throw StateError(
                  'A delta range contained invalid byte values.',
                );
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
            onProgress?.call(
              processed,
              execution.operations.length,
              transferred,
            );
          }
          await check();
        } finally {
          await reader.close();
        }
      }

      await backend.writePreparedFile(
        localPath,
        reconstructed(),
        source.totalSize,
        replace: true,
        verifyStaged: (staged) async {
          final path = staged.path;
          if (path == null || staged.isFolder || staged.isSymlink == true) {
            throw StateError(
              'The delta candidate is not a regular staged file.',
            );
          }
          stagedPath = path;
          stagedStamp = await _verifyLocalFile(path, source, check);
          final currentOriginal = await _verifyLocalFile(
            localPath,
            baseline,
            check,
          );
          if (!_sameFileStamp(originalStamp, currentOriginal)) {
            throw StateError(
              'The delta destination changed during preparation.',
            );
          }
          await verifySource();
          // No awaited pause/checkpoint follows these final proofs. Recheck
          // both metadata stamps after all callbacks and source revalidation.
          checkNow();
          if (!_sameFileStamp(originalStamp, _regularFileStamp(localPath)) ||
              !_sameFileStamp(stagedStamp!, _regularFileStamp(path))) {
            throw StateError(
              'The delta destination or candidate changed before publication.',
            );
          }
        },
        checkpoint: (state) async {
          final phase = state['phase'];
          if (phase == 'committed') return;
          if (phase == 'committing') {
            // The backend is about to enter its existing rename boundary. Do
            // not insert an awaited user pause after candidate verification.
            checkNow();
            if (stagedPath == null ||
                stagedStamp == null ||
                !_sameFileStamp(originalStamp, _regularFileStamp(localPath)) ||
                !_sameFileStamp(stagedStamp!, _regularFileStamp(stagedPath!))) {
              throw StateError('Delta publication proof is no longer current.');
            }
            return;
          }
          await check();
        },
      );
    });
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
  return BlockMap(
    filePath: map.filePath,
    totalSize: map.totalSize,
    blockSize: map.blockSize,
    blockCount: map.blockCount,
    signatures: List.unmodifiable(map.signatures),
    createdAt: map.createdAt,
    identity: map.identity,
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
