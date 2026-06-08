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

import 'log_service.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const int _kDefaultBlockSize = 4 * 1024 * 1024;  // 4 MB
const int _kMinBlockSize     = 64 * 1024;          // 64 KB
const int _kMaxBlockSize     = 64 * 1024 * 1024;  // 64 MB
const int _kDeltaSyncMinSize = 10 * 1024 * 1024;  // 10 MB — below this not worth it

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
    'offset':     offset,
    'size':       size,
    'weakHash':   weakHash,
    'strongHash': strongHash,
  };

  factory BlockSignature.fromJson(Map<String, dynamic> j) => BlockSignature(
    blockIndex: j['blockIndex'] as int,
    offset:     j['offset']     as int,
    size:       j['size']       as int,
    weakHash:   j['weakHash']   as int,
    strongHash: j['strongHash'] as String,
  );

  @override
  bool operator ==(Object other) =>
      other is BlockSignature &&
      blockIndex == other.blockIndex &&
      offset     == other.offset     &&
      size       == other.size       &&
      weakHash   == other.weakHash   &&
      strongHash == other.strongHash;

  @override
  int get hashCode =>
      Object.hash(blockIndex, offset, size, weakHash, strongHash);

  @override
  String toString() =>
      'BlockSignature(#$blockIndex offset=$offset size=$size '
      'weak=0x${weakHash.toRadixString(16)} '
      'strong=${strongHash.substring(0, 8)}…)';
}

/// Complete block map for a file: one [BlockSignature] per block.
class BlockMap {
  final String filePath;
  final int totalSize;
  final int blockSize;
  final int blockCount;
  final List<BlockSignature> signatures;
  final DateTime createdAt;

  const BlockMap({
    required this.filePath,
    required this.totalSize,
    required this.blockSize,
    required this.blockCount,
    required this.signatures,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'filePath':   filePath,
    'totalSize':  totalSize,
    'blockSize':  blockSize,
    'blockCount': blockCount,
    'signatures': signatures.map((s) => s.toJson()).toList(),
    'createdAt':  createdAt.toIso8601String(),
  };

  factory BlockMap.fromJson(Map<String, dynamic> j) => BlockMap(
    filePath:   j['filePath']   as String,
    totalSize:  j['totalSize']  as int,
    blockSize:  j['blockSize']  as int,
    blockCount: j['blockCount'] as int,
    signatures: (j['signatures'] as List<dynamic>)
        .map((e) => BlockSignature.fromJson(e as Map<String, dynamic>))
        .toList(),
    createdAt: DateTime.parse(j['createdAt'] as String),
  );

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

  const DeltaResult({
    required this.filePath,
    required this.totalBlocks,
    required this.changedBlocks,
    required this.unchangedBlocks,
    required this.totalBytes,
    required this.changedBytes,
  });

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

  const BlockOperation({
    required this.type,
    required this.blockIndex,
    required this.offset,
    required this.size,
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

  const BlockTransferPlan({
    required this.filePath,
    required this.blockSize,
    required this.changedBlockIndices,
    required this.totalSize,
    required this.transferSize,
    required this.operations,
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
      b = (b + a)             % _kAdlerMod;
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
  }) async {
    assert(
      blockSize >= _kMinBlockSize && blockSize <= _kMaxBlockSize,
      'blockSize must be between $_kMinBlockSize and $_kMaxBlockSize',
    );

    final file      = File(filePath);
    final fileSize  = await file.length();
    final blockCount = fileSize == 0
        ? 0
        : ((fileSize + blockSize - 1) ~/ blockSize);

    _log.debug('computeBlockMap: $filePath '
        'size=$fileSize blocks=$blockCount blockSize=$blockSize');

    final signatures = <BlockSignature>[];

    if (fileSize > 0) {
      final raf = await file.open(mode: FileMode.read);
      try {
        for (int i = 0; i < blockCount; i++) {
          final offset     = i * blockSize;
          final actualSize = (offset + blockSize > fileSize)
              ? (fileSize - offset)
              : blockSize;

          final buf = Uint8List(actualSize);
          await raf.readInto(buf);

          signatures.add(BlockSignature(
            blockIndex: i,
            offset:     offset,
            size:       actualSize,
            weakHash:   adler32(buf),
            strongHash: sha256Hex(buf),
          ));

          onProgress?.call(i + 1, blockCount, offset + actualSize);
        }
      } finally {
        await raf.close();
      }
    }

    return BlockMap(
      filePath:   filePath,
      totalSize:  fileSize,
      blockSize:  blockSize,
      blockCount: blockCount,
      signatures: signatures,
      createdAt:  DateTime.now(),
    );
  }

  // -------------------------------------------------------------------------
  // compareBlockMaps
  // -------------------------------------------------------------------------

  /// Compare [local] and [remote] block maps and return which blocks differ.
  ///
  /// A block is unchanged iff both weak and strong hashes match.
  /// Blocks that only exist in [local] (file grew) are marked changed.
  /// Blocks that only exist in [remote] (file shrank) are ignored.
  DeltaResult compareBlockMaps(BlockMap local, BlockMap remote) {
    final remoteByIndex = <int, BlockSignature>{
      for (final s in remote.signatures) s.blockIndex: s,
    };

    final changedIndices = <int>[];
    int changedBytes = 0;

    for (final localSig in local.signatures) {
      final remoteSig = remoteByIndex[localSig.blockIndex];
      if (remoteSig == null ||
          localSig.weakHash   != remoteSig.weakHash ||
          localSig.strongHash != remoteSig.strongHash) {
        changedIndices.add(localSig.blockIndex);
        changedBytes += localSig.size;
      }
    }

    return DeltaResult(
      filePath:        local.filePath,
      totalBlocks:     local.blockCount,
      changedBlocks:   changedIndices,
      unchangedBlocks: local.blockCount - changedIndices.length,
      totalBytes:      local.totalSize,
      changedBytes:    changedBytes,
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
    final changedSet = Set<int>.from(deltaResult.changedBlocks);
    final ops        = <BlockOperation>[];
    int transferSize = 0;

    for (final sig in localMap.signatures) {
      final isChanged = changedSet.contains(sig.blockIndex);
      final opType    = !isChanged
          ? BlockOperationType.skip
          : direction == TransferDirection.upload
              ? BlockOperationType.upload
              : BlockOperationType.download;

      ops.add(BlockOperation(
        type:       opType,
        blockIndex: sig.blockIndex,
        offset:     sig.offset,
        size:       sig.size,
      ));
      if (isChanged) transferSize += sig.size;
    }

    return BlockTransferPlan(
      filePath:            localMap.filePath,
      blockSize:           localMap.blockSize,
      changedBlockIndices: deltaResult.changedBlocks.toList(),
      totalSize:           localMap.totalSize,
      transferSize:        transferSize,
      operations:          ops,
    );
  }

  // -------------------------------------------------------------------------
  // applyDelta
  // -------------------------------------------------------------------------

  /// Execute [plan] against [localPath].
  ///
  /// Upload plan: reads changed blocks from [localPath] → calls
  /// [remoteWriteBlock].
  ///
  /// Download plan: calls [remoteReadBlock] → writes bytes into [localPath]
  /// at the correct offset; skip blocks are left untouched.
  ///
  /// [remoteReadBlock]  — `(blockIndex, offset, size) → Future<List<int>>`
  /// [remoteWriteBlock] — `(blockIndex, offset, data) → Future<void>`
  /// [onProgress]       — `(processedBlocks, totalBlocks, processedBytes)`
  Future<void> applyDelta(
    BlockTransferPlan plan,
    String localPath, {
    Future<List<int>> Function(int blockIndex, int offset, int size)?
        remoteReadBlock,
    Future<void> Function(int blockIndex, int offset, List<int> data)?
        remoteWriteBlock,
    void Function(int processedBlocks, int totalBlocks, int processedBytes)?
        onProgress,
  }) async {
    final totalOps     = plan.operations.length;
    int processed      = 0;
    int processedBytes = 0;

    final hasUploads   = plan.operations
        .any((op) => op.type == BlockOperationType.upload);
    final hasDownloads = plan.operations
        .any((op) => op.type == BlockOperationType.download);

    if (hasUploads && remoteWriteBlock == null) {
      throw ArgumentError(
          'remoteWriteBlock must be provided for upload plans');
    }
    if (hasDownloads && remoteReadBlock == null) {
      throw ArgumentError(
          'remoteReadBlock must be provided for download plans');
    }

    // -- UPLOAD --
    if (hasUploads) {
      final raf = await File(localPath).open(mode: FileMode.read);
      try {
        for (final op in plan.operations) {
          if (op.type == BlockOperationType.upload) {
            await raf.setPosition(op.offset);
            final buf = Uint8List(op.size);
            await raf.readInto(buf);
            await remoteWriteBlock!(op.blockIndex, op.offset, buf);
            processedBytes += op.size;
          }
          processed++;
          onProgress?.call(processed, totalOps, processedBytes);
        }
      } finally {
        await raf.close();
      }
      return;
    }

    // -- DOWNLOAD --
    if (hasDownloads) {
      final file = File(localPath);
      if (!file.existsSync()) {
        await file.create(recursive: true);
      }
      // Use append mode to avoid truncating the file — setPosition still
      // works for random-access writes, and existing unchanged blocks are
      // preserved.
      final raf = await file.open(mode: FileMode.append);
      try {
        for (final op in plan.operations) {
          if (op.type == BlockOperationType.download) {
            final data =
                await remoteReadBlock!(op.blockIndex, op.offset, op.size);
            await raf.setPosition(op.offset);
            await raf.writeFrom(data);
            processedBytes += data.length;
          }
          processed++;
          onProgress?.call(processed, totalOps, processedBytes);
        }
      } finally {
        await raf.close();
      }
      return;
    }

    // -- ALL SKIPS (file identical) --
    for (final op in plan.operations) {
      // Explicitly reference op to avoid lint warning.
      assert(op.type == BlockOperationType.skip);
      processed++;
      onProgress?.call(processed, totalOps, processedBytes);
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
    final localMap =
        await computeBlockMap(localPath, blockSize: remoteBlockMap.blockSize);
    final delta = compareBlockMaps(localMap, remoteBlockMap);
    return delta.savingsPercent;
  }

  // -------------------------------------------------------------------------
  // Block map persistence
  // -------------------------------------------------------------------------

  /// Persist [blockMap] as a pretty-printed JSON file at [cachePath].
  Future<void> saveBlockMap(BlockMap blockMap, String cachePath) async {
    final file = File(cachePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(blockMap.toJson()),
      flush: true,
    );
    _log.debug('saveBlockMap → $cachePath');
  }

  /// Load a [BlockMap] from [cachePath].  Returns null if the file does not
  /// exist or cannot be parsed.
  Future<BlockMap?> loadBlockMap(String cachePath) async {
    final file = File(cachePath);
    if (!file.existsSync()) return null;
    try {
      final raw  = await file.readAsString();
      final json = jsonDecode(raw) as Map<String, dynamic>;
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
  /// [provider] — storage provider name (prevents cross-provider collisions).
  String blockMapCachePath(
      String cacheDir, String filePath, String provider) {
    final key = sha256Hex(utf8.encode('$provider:$filePath'));
    return p.join(cacheDir, 'block_maps', '$key.json');
  }
}
