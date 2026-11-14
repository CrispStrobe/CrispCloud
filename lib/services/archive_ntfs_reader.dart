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
// Original read-only implementation of the published NTFS on-disk format.
// No ntfs-3g, Linux, or other copyleft implementation code is incorporated.
// Specification links and the admitted profile: docs/archive-ntfs-profile.md.

import 'dart:convert';
import 'dart:typed_data';

import 'package:koni_archive/koni_archive.dart' as koni;

import 'archive_types.dart';

const _maxEntries = 100000;
const _maxClusters = 1048576;
const _maxExtents = 100000;
const _maxMetadataBytes = 64 * 1024 * 1024;
const _maxDirectoryBytes = 32 * 1024 * 1024;
const _maxPathBytes = 16 * 1024 * 1024;
const _maxExact = 9007199254740991;
const _readBytes = 64 * 1024;

class ArchiveNtfsCancelledException extends ArchiveViewException {
  const ArchiveNtfsCancelledException()
    : super('NTFS image reading was cancelled.');
}

/// Shared allocation/traversal allowances for NTFS children of a disk image.
/// Failed attempts consume the allowance too; no image data is retained here.
class ArchiveNtfsTraversalBudget {
  ArchiveNtfsTraversalBudget({
    this.maxClusters = _maxClusters,
    this.maxExtents = _maxExtents,
  }) {
    _argument(maxClusters, _maxClusters, 'maxClusters');
    _argument(maxExtents, _maxExtents, 'maxExtents');
  }

  final int maxClusters, maxExtents;
  var _clusters = 0, _extents = 0;
  int get clustersVisited => _clusters;
  int get extentsCreated => _extents;
  int get remainingClusters => maxClusters - _clusters;
  int get remainingExtents => maxExtents - _extents;

  void _cluster() {
    if (_clusters >= maxClusters) _limit('Shared allocated-cluster traversal.');
    _clusters++;
  }

  void _extent() {
    if (_extents >= maxExtents) _limit('Shared extent count.');
    _extents++;
  }
}

Never _bad(String message) => throw ArchiveViewException(
  'Invalid NTFS image: $message', code: ArchiveMessageCode.corrupt,
);
Never _unsupported(String message) => throw ArchiveViewException(
  'Unsupported NTFS image: $message', code: ArchiveMessageCode.unsupported,
);
Never _limit(String message) => throw ArchiveViewException(
  'NTFS image resource limit: $message', code: ArchiveMessageCode.archiveLimit,
);
void _argument(int value, int ceiling, String name) {
  if (value <= 0 || value > ceiling) {
    throw ArgumentError.value(value, name, 'Expected 1 through $ceiling.');
  }
}

/// A non-owning OEM-signature probe. It deliberately makes no geometry claim.
Future<bool> hasNtfsVolumeRecognition(koni.ByteSource source) async {
  if (source.length < 11 || source.length > _maxExact) return false;
  final bytes = await source.read(3, 8);
  if (bytes.length != 8) _bad('Truncated OEM signature read.');
  const signature = [0x4e, 0x54, 0x46, 0x53, 0x20, 0x20, 0x20, 0x20];
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) return false;
  }
  return true;
}

/// Owns [source] on success and failure; validates the full reachable namespace
/// and its allocation mappings before publishing any member.
Future<ViewerArchive> openNtfsArchive(
  koni.ByteSource source, {
  required int maxMemberBytes,
  int maxEntries = _maxEntries,
  int maxDirectoryBytes = _maxDirectoryBytes,
  int maxDepth = 64,
  int maxExtents = _maxExtents,
  int maxClusters = _maxClusters,
  int maxMetadataBytes = _maxMetadataBytes,
  int maxRetainedPathBytes = _maxPathBytes,
  ArchiveNtfsTraversalBudget? traversalBudget,
  bool Function()? isCancelled,
}) async {
  _NtfsReader? reader;
  try {
    _argument(maxMemberBytes, kArchiveStreamingLimit, 'maxMemberBytes');
    _argument(maxEntries, _maxEntries, 'maxEntries');
    _argument(maxDirectoryBytes, _maxDirectoryBytes, 'maxDirectoryBytes');
    _argument(maxDepth, 64, 'maxDepth');
    _argument(maxExtents, _maxExtents, 'maxExtents');
    _argument(maxClusters, _maxClusters, 'maxClusters');
    _argument(maxMetadataBytes, _maxMetadataBytes, 'maxMetadataBytes');
    _argument(maxRetainedPathBytes, _maxPathBytes, 'maxRetainedPathBytes');
    reader = _NtfsReader(
      source, maxMemberBytes, maxEntries, maxDirectoryBytes, maxDepth,
      maxExtents, maxClusters, maxMetadataBytes, maxRetainedPathBytes,
      traversalBudget ?? ArchiveNtfsTraversalBudget(), isCancelled,
    );
    return await reader.open();
  } catch (_) {
    try {
      if (reader == null) { await source.close(); }
      else { await reader.close(); }
    } catch (_) { /* Preserve the original failure, including provider identity. */ }
    rethrow;
  }
}

class _NtfsReader {
  _NtfsReader(
    this.source, this.maxMemberBytes, this.maxEntries, this.maxDirectoryBytes,
    this.maxDepth, this.maxExtents, this.maxClusters, this.maxMetadataBytes,
    this.maxRetainedPathBytes, this.budget, this.isCancelled,
  ) : sourceLength = source.length;

  final koni.ByteSource source;
  final int sourceLength;
  final int maxMemberBytes, maxEntries, maxDirectoryBytes, maxDepth;
  final int maxExtents, maxClusters, maxMetadataBytes, maxRetainedPathBytes;
  final ArchiveNtfsTraversalBudget budget;
  final bool Function()? isCancelled;
  var _closed = false;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await source.close();
  }

  Future<ViewerArchive> open() async {
    if (_closed || (isCancelled?.call() ?? false)) {
      throw const ArchiveNtfsCancelledException();
    }
    _unsupported('The bounded NTFS reader is being implemented.');
  }
}
