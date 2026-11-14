// Copyright 2026 CrispCloud contributors
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
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//
// Original read-only implementation of published ext on-disk structure facts.
// No Linux or e2fsprogs implementation code is incorporated.
// Specification links and admitted profile: docs/archive-ext-profile.md.

import 'dart:convert';
import 'dart:typed_data';

import 'package:koni_archive/koni_archive.dart' as koni;

import 'archive_types.dart';

const _maxEntries = 100000;
const _maxBlocks = 1048576;
const _maxExtents = 100000;
const _maxMetadataBytes = 64 * 1024 * 1024;
const _maxDirectoryBytes = 32 * 1024 * 1024;
const _maxPathBytes = 16 * 1024 * 1024;
const _maxExact = 9007199254740991;
const _readBytes = 64 * 1024;

class ArchiveExtCancelledException extends ArchiveViewException {
  const ArchiveExtCancelledException()
    : super('Ext image reading was cancelled.');
}

/// A shared allowance for all ext children of one bounded disk image.
/// Failed openings consume work too; counters retain no image data.
class ArchiveExtTraversalBudget {
  ArchiveExtTraversalBudget({
    this.maxBlocks = _maxBlocks,
    this.maxExtents = _maxExtents,
  }) {
    _argument(maxBlocks, _maxBlocks, 'maxBlocks');
    _argument(maxExtents, _maxExtents, 'maxExtents');
  }

  final int maxBlocks, maxExtents;
  var _blocks = 0, _extents = 0;
  int get blocksVisited => _blocks;
  int get extentsCreated => _extents;
  int get remainingBlocks => maxBlocks - _blocks;
  int get remainingExtents => maxExtents - _extents;

  void _block() {
    if (_blocks >= maxBlocks) _limit('Shared allocated-block traversal limit.');
    _blocks++;
  }

  void _extent() {
    if (_extents >= maxExtents) _limit('Shared extent limit.');
    _extents++;
  }
}

Never _bad(String message) => throw ArchiveViewException(
  'Invalid ext image: $message', code: ArchiveMessageCode.corrupt,
);
Never _unsupported(String message) => throw ArchiveViewException(
  'Unsupported ext image: $message', code: ArchiveMessageCode.unsupported,
);
Never _limit(String message) => throw ArchiveViewException(
  'Ext image resource limit: $message', code: ArchiveMessageCode.archiveLimit,
);
void _argument(int value, int ceiling, String name) {
  if (value <= 0 || value > ceiling) {
    throw ArgumentError.value(value, name, 'Expected 1 through $ceiling.');
  }
}
int _u16(Uint8List b, int at) => ByteData.sublistView(b).getUint16(at, Endian.little);
int _u32(Uint8List b, int at) => ByteData.sublistView(b).getUint32(at, Endian.little);
int _wide(int low, int high, {int ceiling = _maxExact}) {
  if (high > ceiling ~/ 4294967296 ||
      (high == ceiling ~/ 4294967296 && low > ceiling % 4294967296)) {
    _unsupported('An integer exceeds the exact supported range.');
  }
  return high * 4294967296 + low;
}

/// A non-owning two-byte signature probe; full opening validates the volume.
Future<bool> hasExtVolumeRecognition(koni.ByteSource source) async {
  if (source.length < 1082 || source.length > _maxExact) return false;
  final bytes = await source.read(1080, 2);
  if (bytes.length != 2) _bad('Truncated superblock signature read.');
  return bytes[0] == 0x53 && bytes[1] == 0xef;
}

/// Owns [source] on success and failure. Only clean, explicitly admitted ext
/// profiles are opened; immutable allocations are validated before publication.
Future<ViewerArchive> openExtArchive(
  koni.ByteSource source, {
  required int maxMemberBytes,
  int maxEntries = _maxEntries,
  int maxDirectoryBytes = _maxDirectoryBytes,
  int maxDepth = 64,
  int maxExtents = _maxExtents,
  int maxBlocks = _maxBlocks,
  int maxMetadataBytes = _maxMetadataBytes,
  int maxRetainedPathBytes = _maxPathBytes,
  ArchiveExtTraversalBudget? traversalBudget,
  bool Function()? isCancelled,
}) async {
  _ExtReader? reader;
  try {
    _argument(maxMemberBytes, kArchiveStreamingLimit, 'maxMemberBytes');
    _argument(maxEntries, _maxEntries, 'maxEntries');
    _argument(maxDirectoryBytes, _maxDirectoryBytes, 'maxDirectoryBytes');
    _argument(maxDepth, 64, 'maxDepth');
    _argument(maxExtents, _maxExtents, 'maxExtents');
    _argument(maxBlocks, _maxBlocks, 'maxBlocks');
    _argument(maxMetadataBytes, _maxMetadataBytes, 'maxMetadataBytes');
    _argument(maxRetainedPathBytes, _maxPathBytes, 'maxRetainedPathBytes');
    reader = _ExtReader(source, maxMemberBytes, maxEntries, maxDirectoryBytes,
      maxDepth, maxExtents, maxBlocks, maxMetadataBytes, maxRetainedPathBytes,
      traversalBudget ?? ArchiveExtTraversalBudget(), isCancelled);
    return await reader.open();
  } catch (_) {
    try {
      if (reader == null) { await source.close(); } else { await reader.close(); }
    } catch (_) { /* The original provider, cancellation or format failure wins. */ }
    rethrow;
  }
}

class _ExtReader {
  _ExtReader(this.source, this.maxMemberBytes, this.maxEntries,
    this.maxDirectoryBytes, this.maxDepth, this.maxExtents, this.maxBlocks,
    this.maxMetadataBytes, this.maxRetainedPathBytes, this.budget,
    this.isCancelled);

  final koni.ByteSource source;
  final int maxMemberBytes, maxEntries, maxDirectoryBytes, maxDepth;
  final int maxExtents, maxBlocks, maxMetadataBytes, maxRetainedPathBytes;
  final ArchiveExtTraversalBudget budget;
  final bool Function()? isCancelled;
  var _closed = false;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await source.close();
  }

  Future<ViewerArchive> open() async {
    // The implementation is being checkpointed before integration qualification.
    _unsupported('Reader implementation checkpoint is not yet complete.');
  }
}
