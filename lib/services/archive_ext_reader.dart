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
  'Invalid ext image: $message',
  code: ArchiveMessageCode.corrupt,
);
Never _unsupported(String message) => throw ArchiveViewException(
  'Unsupported ext image: $message',
  code: ArchiveMessageCode.unsupported,
);
Never _limit(String message) => throw ArchiveViewException(
  'Ext image resource limit: $message',
  code: ArchiveMessageCode.archiveLimit,
);
void _argument(int value, int ceiling, String name) {
  if (value <= 0 || value > ceiling) {
    throw ArgumentError.value(value, name, 'Expected 1 through $ceiling.');
  }
}

int _u16(Uint8List b, int at) =>
    ByteData.sublistView(b).getUint16(at, Endian.little);
int _u32(Uint8List b, int at) =>
    ByteData.sublistView(b).getUint32(at, Endian.little);
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
    reader = _ExtReader(
      source,
      maxMemberBytes,
      maxEntries,
      maxDirectoryBytes,
      maxDepth,
      maxExtents,
      maxBlocks,
      maxMetadataBytes,
      maxRetainedPathBytes,
      traversalBudget ?? ArchiveExtTraversalBudget(),
      isCancelled,
    );
    return await reader.open();
  } catch (_) {
    try {
      if (reader == null) {
        await source.close();
      } else {
        await reader.close();
      }
    } catch (_) {
      /* The original provider, cancellation or format failure wins. */
    }
    rethrow;
  }
}

class _ExtReader {
  _ExtReader(
    this.source,
    this.maxMemberBytes,
    this.maxEntries,
    this.maxDirectoryBytes,
    this.maxDepth,
    this.maxExtents,
    this.maxBlocks,
    this.maxMetadataBytes,
    this.maxRetainedPathBytes,
    this.budget,
    this.isCancelled,
  );

  final koni.ByteSource source;
  final int maxMemberBytes, maxEntries, maxDirectoryBytes, maxDepth;
  final int maxExtents, maxBlocks, maxMetadataBytes, maxRetainedPathBytes;
  final ArchiveExtTraversalBudget budget;
  final bool Function()? isCancelled;
  var _closed = false;
  var _metadataBytes = 0, _directoryBytes = 0, _pathBytes = 0;
  var _blocksVisited = 0, _extentsCreated = 0, _work = 0;
  late int _blockBytes, _blocks, _inodes, _blocksPerGroup, _inodesPerGroup;
  late int _inodeSize, _firstData, _groupCount, _descSize, _firstInode;
  late int _compat, _incompat, _roCompat, _seed;
  late bool _metadataCsum, _gdtCsum, _is64;
  late Uint8List _uuid;
  final _groups = <_Group>[];
  final _fixed = <_Range>[];
  final _claimed = <int>{};
  final _bitmaps = <int, Uint8List>{};
  final _inodeCache = <int, _Inode>{};
  final _directories = <int>{};
  final _references = <int, int>{};
  final _paths = <String>{};
  final _members = <ViewerArchiveMember>[];
  final _files = <_Inode>[];
  final _notices = <String>{
    'Read-only ext filesystem. Allocation and metadata checks do not '
        'authenticate file contents or establish consistency of unreferenced inodes.',
    'Symbolic links and special files are metadata only. Permissions and '
        'modification times are listed; ownership and extended attributes '
        'are not restored. Journal replay and filesystem repair are not performed.',
  };

  void _cancel() {
    if (_closed || (isCancelled?.call() ?? false)) {
      throw const ArchiveExtCancelledException();
    }
  }

  Future<void> _checkpoint() async {
    _cancel();
    if (++_work > 4194304) _limit('Metadata traversal work.');
    if (_work % 256 == 0) {
      await Future<void>.delayed(Duration.zero);
      _cancel();
    }
  }

  Future<Uint8List> _read(
    int offset,
    int length, {
    bool metadata = true,
  }) async {
    await _checkpoint();
    if (offset < 0 ||
        length < 0 ||
        length > _readBytes ||
        offset > source.length ||
        length > source.length - offset) {
      _bad('A read leaves the bounded image.');
    }
    if (metadata) {
      if (length > maxMetadataBytes - _metadataBytes)
        _limit('Metadata read bytes.');
      _metadataBytes += length;
    }
    final bytes = await source.read(offset, length);
    _cancel();
    if (bytes.length != length) _bad('Truncated image read.');
    return bytes;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _bitmaps.clear();
    _claimed.clear();
    _inodeCache.clear();
    await source.close();
  }

  Future<ViewerArchive> open() async {
    if (source.length < 2048 || source.length > _maxExact) {
      _bad('The source cannot contain an exact ext superblock.');
    }
    final sb = await _read(1024, 1024);
    if (_u16(sb, 56) != 0xef53) _bad('Missing ext superblock signature.');
    final revision = _u32(sb, 76);
    if (revision > 1 || _u32(sb, 72) != 0) {
      _unsupported(
        'Only original/dynamic Linux ext inode layouts are admitted.',
      );
    }
    _compat = revision == 0 ? 0 : _u32(sb, 92);
    _incompat = revision == 0 ? 0 : _u32(sb, 96);
    _roCompat = revision == 0 ? 0 : _u32(sb, 100);
    if (_u16(sb, 58) != 1 || _incompat & 4 != 0 || _u32(sb, 232) != 0) {
      _unsupported(
        'The filesystem is not clean or requires journal/orphan recovery.',
      );
    }
    if (_compat & ~0x3c != 0 ||
        _incompat & ~0x22c2 != 0 ||
        _roCompat & ~0x47b != 0) {
      _unsupported('Unknown or excluded filesystem feature flags.');
    }
    _metadataCsum = _roCompat & 0x400 != 0;
    _gdtCsum = _roCompat & 0x10 != 0;
    _is64 = _incompat & 0x80 != 0;
    if (_metadataCsum && _gdtCsum)
      _bad('Conflicting metadata checksum features.');
    if (_incompat & 0x2000 != 0 && !_metadataCsum) {
      _bad('A checksum seed is declared without metadata checksums.');
    }
    _uuid = Uint8List.fromList(sb.sublist(104, 120));
    _seed = _incompat & 0x2000 != 0
        ? _u32(sb, 624)
        : _crc32c(0xffffffff, _uuid);
    if (_metadataCsum) {
      if (sb[373] != 1)
        _unsupported('Only CRC32c metadata checksums are admitted.');
      if (_crc32c(0xffffffff, sb, end: 1020) != _u32(sb, 1020)) {
        _bad('Superblock checksum mismatch.');
      }
    }
    final logBlock = _u32(sb, 24);
    if (logBlock > 2)
      _unsupported('Only 1024, 2048 and 4096-byte blocks are admitted.');
    _blockBytes = 1024 * (1 << logBlock);
    if (_u32(sb, 28) != logBlock || _u32(sb, 36) != _u32(sb, 32)) {
      _unsupported('Fragment or cluster geometry differs from block geometry.');
    }
    _firstData = _u32(sb, 20);
    if (_firstData != (_blockBytes == 1024 ? 1 : 0)) {
      _bad('Unexpected first data block.');
    }
    _blocks = _wide(
      _u32(sb, 4),
      _is64 ? _u32(sb, 336) : 0,
      ceiling: _maxExact ~/ _blockBytes,
    );
    if (!_is64 && _u32(sb, 336) != 0)
      _bad('High block count without 64bit feature.');
    if (_blocks <= _firstData || _blocks > source.length ~/ _blockBytes) {
      _bad('Declared filesystem leaves the image.');
    }
    _blocksPerGroup = _u32(sb, 32);
    _inodesPerGroup = _u32(sb, 40);
    _inodes = _u32(sb, 0);
    _inodeSize = revision == 0 ? 128 : _u16(sb, 88);
    _firstInode = revision == 0 ? 11 : _u32(sb, 84);
    if (_blocksPerGroup <= 0 ||
        _blocksPerGroup > _blockBytes * 8 ||
        _blocksPerGroup % 8 != 0 ||
        _inodesPerGroup <= 0 ||
        _inodesPerGroup > _blockBytes * 8 ||
        _inodesPerGroup % 8 != 0 ||
        _inodeSize < 128 ||
        _inodeSize > _blockBytes ||
        _inodeSize & (_inodeSize - 1) != 0 ||
        _inodesPerGroup * _inodeSize % _blockBytes != 0 ||
        _firstInode < 11 ||
        _firstInode > _inodes) {
      _bad('Invalid block-group or inode geometry.');
    }
    _groupCount =
        (_blocks - _firstData + _blocksPerGroup - 1) ~/ _blocksPerGroup;
    if (_groupCount > 8192) _limit('Block-group count.');
    if (_inodes <= (_groupCount - 1) * _inodesPerGroup ||
        _inodes > _groupCount * _inodesPerGroup) {
      _bad('Inode and block group counts disagree.');
    }
    _descSize = _is64 ? _u16(sb, 254) : 32;
    if (_descSize != (_is64 ? 64 : 32)) {
      _unsupported('Only 32-byte and 64-byte group descriptors are admitted.');
    }
    if (_u16(sb, 90) != 0)
      _bad('The primary superblock has a nonzero group number.');
    if (_u32(sb, 228) != 0) _unsupported('External journals are not admitted.');
    final tableBlocks =
        (_groupCount * _descSize + _blockBytes - 1) ~/ _blockBytes;
    final reservedGdt = _u16(sb, 206);
    if (reservedGdt != 0 && _compat & 0x10 == 0) {
      _bad('Reserved descriptor blocks lack the resize feature.');
    }
    if (_blockBytes == 1024) _reserve(0, 1);
    for (var group = 0; group < _groupCount; group++) {
      await _checkpoint();
      if (_hasSuper(group)) {
        _reserve(
          _firstData + group * _blocksPerGroup,
          1 + tableBlocks + reservedGdt,
        );
      }
      final descriptor = await _read(
        (_firstData + 1) * _blockBytes + group * _descSize,
        _descSize,
      );
      _checkDescriptor(descriptor, group);
      final blockBitmap = _wide(
        _u32(descriptor, 0),
        _is64 ? _u32(descriptor, 32) : 0,
      );
      final inodeBitmap = _wide(
        _u32(descriptor, 4),
        _is64 ? _u32(descriptor, 36) : 0,
      );
      final inodeTable = _wide(
        _u32(descriptor, 8),
        _is64 ? _u32(descriptor, 40) : 0,
      );
      final flags = _u16(descriptor, 18);
      if (flags & ~7 != 0 || (flags & 3 != 0 && !_gdtCsum && !_metadataCsum)) {
        _bad('Unknown or unchecked group initialization flags.');
      }
      if (_u32(descriptor, 20) != 0 || (_is64 && _u32(descriptor, 52) != 0)) {
        _unsupported('Snapshot exclusion bitmaps are not admitted.');
      }
      final tableLength = _inodesPerGroup * _inodeSize ~/ _blockBytes;
      if (_incompat & 0x200 == 0) {
        final start = _firstData + group * _blocksPerGroup;
        final end = start + _blocksPerGroup < _blocks
            ? start + _blocksPerGroup
            : _blocks;
        if (blockBitmap < start ||
            blockBitmap >= end ||
            inodeBitmap < start ||
            inodeBitmap >= end ||
            inodeTable < start ||
            inodeTable > end - tableLength) {
          _bad('Group metadata leaves its group without flex_bg.');
        }
      }
      _reserve(blockBitmap, 1);
      _reserve(inodeBitmap, 1);
      _reserve(inodeTable, tableLength);
      _groups.add(
        _Group(
          blockBitmap,
          inodeBitmap,
          inodeTable,
          flags,
          _u16(descriptor, 24) + (_is64 ? _u16(descriptor, 56) * 65536 : 0),
          _u16(descriptor, 26) + (_is64 ? _u16(descriptor, 58) * 65536 : 0),
        ),
      );
    }
    _fixed.sort((a, b) => a.start.compareTo(b.start));
    for (var i = 1; i < _fixed.length; i++) {
      if (_fixed[i].start < _fixed[i - 1].end)
        _bad('Overlapping filesystem metadata regions.');
    }
    // Reserve the internal journal allocation before any namespace allocation.
    // A clean state does not permit exposing journal blocks as an ordinary file.
    if (_compat & 4 != 0) {
      final journalNumber = _u32(sb, 224);
      if (journalNumber < 1 ||
          journalNumber >= _firstInode ||
          journalNumber == 2) {
        _bad('Invalid internal journal inode.');
      }
      final journal = await _inode(journalNumber);
      if (!journal.regular)
        _bad('The internal journal is not a regular inode.');
      await _map(journal);
    } else if (_u32(sb, 224) != 0) {
      _bad('Journal inode without the journal feature.');
    }
    final root = await _inode(2);
    if (!root.directory) _bad('Root inode is not a directory.');
    await _directory(root, '', 2, 0);
    _cancel();
    _notices.add(
      '${_incompat & 0x40 != 0 ? 'ext4' : (_compat & 4 != 0 ? 'ext3' : 'ext2')}; '
      '$_blockBytes-byte blocks; ${_metadataCsum ? 'CRC32c metadata' : (_gdtCsum ? 'group descriptor CRC16' : 'no metadata checksum')} validation.',
    );
    _bitmaps.clear();
    _claimed.clear();
    _inodeCache.clear();
    return ViewerArchive.reader(
      formatName: 'ext',
      members: _members,
      notices: _notices.toList(),
      maxStreamingMemberBytes: maxMemberBytes,
      close: close,
      read: (member, maxBytes) async {
        final output = BytesBuilder(copy: false);
        await for (final chunk in _stream(_files[member.index], _readBytes)) {
          output.add(chunk);
        }
        return output.takeBytes();
      },
      streamReader: (member, chunkSize) =>
          _stream(_files[member.index], chunkSize),
    );
  }

  bool _hasSuper(int group) {
    if (_roCompat & 1 == 0 || group < 2) return true;
    for (final base in [3, 5, 7]) {
      var value = group;
      while (value > 1 && value % base == 0) {
        value ~/= base;
      }
      if (value == 1) return true;
    }
    return false;
  }

  void _reserve(int first, int count) {
    if (first < 0 ||
        count <= 0 ||
        first >= _blocks ||
        count > _blocks - first) {
      _bad('A metadata region leaves the filesystem.');
    }
    _fixed.add(_Range(first, first + count));
  }

  bool _isFixed(int block) {
    var low = 0, high = _fixed.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (_fixed[middle].start <= block) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low > 0 && block < _fixed[low - 1].end;
  }

  void _checkDescriptor(Uint8List bytes, int number) {
    if (!_metadataCsum && !_gdtCsum) return;
    final expected = _u16(bytes, 30);
    final ordinal = _little32(number);
    if (_metadataCsum) {
      final copy = Uint8List.fromList(bytes)
        ..[30] = 0
        ..[31] = 0;
      if ((_crc32c(_crc32c(_seed, ordinal), copy) & 65535) != expected) {
        _bad('Group descriptor checksum mismatch.');
      }
    } else {
      var crc = _crc16(_crc16(65535, _uuid), ordinal);
      crc = _crc16(crc, bytes, end: 30);
      crc = _crc16(crc, bytes, start: 32);
      if (crc != expected) _bad('Group descriptor CRC16 mismatch.');
    }
  }

  Future<Uint8List> _bitmap(int groupNumber, bool inode) async {
    final key = groupNumber * 2 + (inode ? 1 : 0);
    final cached = _bitmaps.remove(key);
    if (cached != null) {
      _bitmaps[key] = cached;
      return cached;
    }
    final group = _groups[groupNumber];
    if (group.flags & (inode ? 1 : 2) != 0) {
      _bad('A referenced allocation belongs to an uninitialized bitmap.');
    }
    final bytes = await _read(
      (inode ? group.inodeBitmap : group.blockBitmap) * _blockBytes,
      _blockBytes,
    );
    if (_metadataCsum) {
      final checksum = _crc32c(
        _seed,
        bytes,
        end: (inode ? _inodesPerGroup : _blocksPerGroup) ~/ 8,
      );
      final expected = inode
          ? group.inodeBitmapChecksum
          : group.blockBitmapChecksum;
      if ((_is64 ? checksum : checksum & 65535) != expected)
        _bad('Allocation bitmap checksum mismatch.');
    }
    if (_bitmaps.length == 128) _bitmaps.remove(_bitmaps.keys.first);
    _bitmaps[key] = bytes;
    return bytes;
  }

  Future<void> _claim(int block) async {
    await _checkpoint();
    if (block < _firstData || block >= _blocks || block == 0) {
      _bad('An allocated block leaves the filesystem.');
    }
    if (_isFixed(block)) _bad('File allocation overlaps filesystem metadata.');
    if (_blocksVisited >= maxBlocks) _limit('Allocated-block traversal.');
    budget._block();
    _blocksVisited++;
    if (!_claimed.add(block)) _bad('Cross-linked or repeated allocated block.');
    final relative = block - _firstData;
    final map = await _bitmap(relative ~/ _blocksPerGroup, false);
    final bit = relative % _blocksPerGroup;
    if (map[bit ~/ 8] & (1 << (bit % 8)) == 0) {
      _bad('A referenced block is marked free.');
    }
  }

  Future<_Inode> _inode(int number) async {
    await _checkpoint();
    final cached = _inodeCache[number];
    if (cached != null) return cached;
    if (number < 1 || number > _inodes) _bad('Inode number leaves the table.');
    if (_inodeCache.length > maxEntries + 1) _limit('Retained inode records.');
    final groupNumber = (number - 1) ~/ _inodesPerGroup;
    final index = (number - 1) % _inodesPerGroup;
    final map = await _bitmap(groupNumber, true);
    if (map[index ~/ 8] & (1 << (index % 8)) == 0)
      _bad('A referenced inode is marked free.');
    final bytes = await _read(
      _groups[groupNumber].inodeTable * _blockBytes + index * _inodeSize,
      _inodeSize,
    );
    final extra = _inodeSize > 128 ? _u16(bytes, 128) : 0;
    if (extra > _inodeSize - 128 || extra % 4 != 0)
      _bad('Invalid extra inode size.');
    final generation = _u32(bytes, 100);
    final seed = _crc32c(
      _crc32c(_seed, _little32(number)),
      _little32(generation),
    );
    if (_metadataCsum) {
      final copy = Uint8List.fromList(bytes);
      final high = extra >= 4;
      final expected = _u16(bytes, 124) + (high ? _u16(bytes, 130) * 65536 : 0);
      copy[124] = 0;
      copy[125] = 0;
      if (high) {
        copy[130] = 0;
        copy[131] = 0;
      }
      final actual = _crc32c(seed, copy);
      if ((high ? actual : actual & 65535) != expected)
        _bad('Inode checksum mismatch.');
    }
    final mode = _u16(bytes, 0), type = mode & 0xf000;
    if (!const [
          0x1000,
          0x2000,
          0x4000,
          0x6000,
          0x8000,
          0xa000,
          0xc000,
        ].contains(type) ||
        _u16(bytes, 26) == 0 ||
        _u32(bytes, 20) != 0) {
      _bad('A live inode has invalid mode, link count or deletion time.');
    }
    final flags = _u32(bytes, 32);
    const allowedFlags =
        0x4fc4fb; // Harmless policy flags, huge/extents, preallocation.
    if (flags & ~allowedFlags != 0) {
      _unsupported('Indexed directories or excluded inode data features.');
    }
    if (flags & 0x80000 != 0 && _incompat & 0x40 == 0)
      _bad('Extent inode without filesystem extent feature.');
    if (flags & 0x40000 != 0 && _roCompat & 8 == 0)
      _bad('Huge inode without huge-file feature.');
    if (_u32(bytes, 104) != 0 || _u16(bytes, 118) != 0) {
      _unsupported('External extended-attribute blocks are not admitted.');
    }
    if (_u32(bytes, 112) != 0)
      _unsupported('Fragment-addressed inodes are not admitted.');
    final highSize = _u32(bytes, 108);
    if (highSize != 0 && type != 0x8000)
      _unsupported('Large non-regular inode size.');
    if (highSize != 0 && _roCompat & 2 == 0)
      _bad('Large inode lacks the large-file feature.');
    final size = _wide(
      _u32(bytes, 4),
      highSize,
      ceiling: kArchiveStreamingLimit,
    );
    final inode = _Inode(
      number,
      mode,
      flags,
      size,
      _u16(bytes, 26),
      seed,
      Uint8List.fromList(bytes.sublist(40, 100)),
      _modified(bytes, extra),
    );
    _inodeCache[number] = inode;
    return inode;
  }

  DateTime? _modified(Uint8List bytes, int extraSize) {
    final raw = _u32(bytes, 16);
    var seconds = raw >= 2147483648 ? raw - 4294967296 : raw;
    var nanos = 0;
    if (extraSize >= 12) {
      final extra = _u32(bytes, 136);
      seconds += (extra & 3) * 4294967296;
      nanos = extra >>> 2;
      if (nanos > 999999999) {
        _notices.add('An invalid ext modification timestamp was omitted.');
        return null;
      }
    }
    return DateTime.fromMicrosecondsSinceEpoch(
      seconds * 1000000 + nanos ~/ 1000,
      isUtc: true,
    );
  }

  void _extent() {
    if (_extentsCreated >= maxExtents) _limit('Allocation extent count.');
    budget._extent();
    _extentsCreated++;
  }

  Future<void> _map(_Inode inode) async {
    if (inode.spans != null) return;
    final spans = <_Span>[];
    if (inode.flags & 0x80000 != 0) {
      await _extentNode(inode, inode.blockMap, null, 0, 4294967296, spans);
    } else {
      final entries = _blockBytes ~/ 4;
      var logical = 0;
      for (var index = 0; index < 15; index++) {
        final depth = index < 12 ? 0 : index - 11;
        var coverage = 1;
        for (var level = 0; level < depth; level++) {
          coverage *= entries;
        }
        await _indirect(
          _u32(inode.blockMap, index * 4),
          depth,
          logical,
          coverage,
          inode,
          spans,
        );
        logical += coverage;
      }
      if (inode.size > logical * _blockBytes)
        _bad('Inode size exceeds classic addressing.');
    }
    final complete = <_Span>[];
    var cursor = 0;
    void add(int start, int length, int? physical) {
      if (length == 0) return;
      if (complete.isNotEmpty) {
        final last = complete.last;
        if (last.start + last.length == start &&
            ((last.physical == null && physical == null) ||
                (last.physical != null &&
                    physical != null &&
                    last.physical! + last.length == physical))) {
          complete[complete.length - 1] = _Span(
            last.start,
            last.length + length,
            last.physical,
          );
          return;
        }
      }
      _extent();
      complete.add(_Span(start, length, physical));
    }

    for (final span in spans) {
      if (span.start < cursor) _bad('Overlapping logical file extents.');
      if (span.start >= inode.size) break;
      if (span.start > cursor) add(cursor, span.start - cursor, null);
      final length = span.length < inode.size - span.start
          ? span.length
          : inode.size - span.start;
      add(span.start, length, span.physical);
      cursor = span.start + length;
    }
    if (cursor < inode.size) add(cursor, inode.size - cursor, null);
    inode.spans = List.unmodifiable(complete);
  }

  Future<void> _indirect(
    int physical,
    int depth,
    int logical,
    int coverage,
    _Inode inode,
    List<_Span> spans,
  ) async {
    await _checkpoint();
    if (physical == 0) return;
    await _claim(physical);
    if (depth == 0) {
      _extent();
      spans.add(
        _Span(logical * _blockBytes, _blockBytes, physical * _blockBytes),
      );
      return;
    }
    final bytes = await _read(physical * _blockBytes, _blockBytes);
    final childCoverage = coverage ~/ (_blockBytes ~/ 4);
    for (var i = 0; i < _blockBytes ~/ 4; i++) {
      await _indirect(
        _u32(bytes, i * 4),
        depth - 1,
        logical + i * childCoverage,
        childCoverage,
        inode,
        spans,
      );
    }
  }

  Future<void> _extentNode(
    _Inode inode,
    Uint8List bytes,
    int? expectedDepth,
    int lower,
    int upper,
    List<_Span> spans,
  ) async {
    await _checkpoint();
    if (_u16(bytes, 0) != 0xf30a) _bad('Invalid extent-tree magic.');
    final count = _u16(bytes, 2),
        capacity = _u16(bytes, 4),
        depth = _u16(bytes, 6);
    final root = expectedDepth == null;
    final maximum = root ? 4 : (_blockBytes - 12) ~/ 12;
    if (capacity != maximum ||
        count > capacity ||
        depth > 5 ||
        (expectedDepth != null && depth != expectedDepth) ||
        (depth > 0 && count == 0)) {
      _bad('Invalid extent-tree capacity, depth or entry count.');
    }
    if (!root && _metadataCsum) {
      final tail = 12 + capacity * 12;
      if (_crc32c(inode.seed, bytes, end: tail) != _u32(bytes, tail)) {
        _bad('Extent-tree checksum mismatch.');
      }
    }
    var previous = lower;
    for (var i = 0; i < count; i++) {
      final at = 12 + i * 12;
      final logical = _u32(bytes, at);
      if (logical < lower ||
          logical < previous ||
          logical >= upper ||
          (i > 0 && logical == previous && depth > 0)) {
        _bad('Unordered or out-of-range extent-tree keys.');
      }
      if (depth == 0) {
        final encoded = _u16(bytes, at + 4);
        final length = encoded > 32768 ? encoded - 32768 : encoded;
        final physical = _wide(_u32(bytes, at + 8), _u16(bytes, at + 6));
        if (length == 0 ||
            length > upper - logical ||
            physical == 0 ||
            physical >= _blocks ||
            length > _blocks - physical) {
          _bad('An extent leaves its logical or physical range.');
        }
        for (var block = 0; block < length; block++) {
          await _claim(physical + block);
        }
        _extent();
        spans.add(
          _Span(
            logical * _blockBytes,
            length * _blockBytes,
            encoded > 32768 ? null : physical * _blockBytes,
          ),
        );
        previous = logical + length;
      } else {
        final next = i + 1 < count ? _u32(bytes, at + 12) : upper;
        if (next <= logical || next > upper || _u16(bytes, at + 10) != 0) {
          _bad('Invalid extent index interval or reserved field.');
        }
        final physical = _wide(_u32(bytes, at + 4), _u16(bytes, at + 8));
        await _claim(physical);
        final child = await _read(physical * _blockBytes, _blockBytes);
        await _extentNode(inode, child, depth - 1, logical, next, spans);
        previous = logical;
      }
    }
  }

  Future<void> _directory(
    _Inode inode,
    String prefix,
    int parent,
    int depth,
  ) async {
    if (depth > maxDepth) _limit('Directory depth.');
    if (!_directories.add(inode.number))
      _bad('Directory cycle or repeated directory inode.');
    if (inode.size <= 0 || inode.size % _blockBytes != 0)
      _bad('Invalid directory size.');
    if (inode.size > maxDirectoryBytes - _directoryBytes)
      _limit('Directory bytes.');
    _directoryBytes += inode.size;
    await _map(inode);
    final names = <String>{};
    var recordNumber = 0;
    for (final span in inode.spans!) {
      if (span.physical == null) _bad('Sparse or unwritten directory block.');
      for (var done = 0; done < span.length; done += _blockBytes) {
        final bytes = await _read(span.physical! + done, _blockBytes);
        final end = _metadataCsum ? _blockBytes - 12 : _blockBytes;
        if (_metadataCsum) {
          if (_u32(bytes, end) != 0 ||
              _u16(bytes, end + 4) != 12 ||
              bytes[end + 6] != 0 ||
              bytes[end + 7] != 0xde ||
              _crc32c(inode.seed, bytes, end: end) != _u32(bytes, end + 8)) {
            _bad('Directory checksum tail or checksum mismatch.');
          }
        }
        for (var at = 0; at < end; recordNumber++) {
          await _checkpoint();
          if (end - at < 8) _bad('Truncated directory entry.');
          final number = _u32(bytes, at), length = _u16(bytes, at + 4);
          final nameLength = _incompat & 2 != 0
              ? bytes[at + 6]
              : _u16(bytes, at + 6);
          final type = _incompat & 2 != 0 ? bytes[at + 7] : 0;
          if (length < 8 ||
              length % 4 != 0 ||
              length > end - at ||
              nameLength > 255 ||
              nameLength > length - 8 ||
              type > 7) {
            _bad('Invalid directory record length or type.');
          }
          final nameBytes = Uint8List.sublistView(
            bytes,
            at + 8,
            at + 8 + nameLength,
          );
          at += length;
          if (number == 0) {
            if (recordNumber < 2) _bad('Missing dot directory entries.');
            continue;
          }
          String name;
          try {
            name = utf8.decode(nameBytes);
          } on FormatException {
            _unsupported('Filename bytes are not valid UTF-8.');
          }
          if (recordNumber < 2) {
            if (name != (recordNumber == 0 ? '.' : '..') ||
                number != (recordNumber == 0 ? inode.number : parent) ||
                (type != 0 && type != 2)) {
              _bad('Invalid self or parent directory entry.');
            }
            continue;
          }
          _component(name);
          if (!names.add(name)) _bad('Duplicate directory name.');
          if (number < _firstInode)
            _bad('A directory exposes a reserved inode.');
          if (_members.length >= maxEntries) _limit('Directory entry count.');
          final path = prefix.isEmpty ? name : '$prefix/$name';
          if (path.length > 4096 ||
              path.length * 2 > maxRetainedPathBytes - _pathBytes) {
            _limit('Retained full-path text.');
          }
          _pathBytes += path.length * 2;
          if (!_paths.add(path)) _bad('Duplicate complete path.');
          final child = await _inode(number);
          if (type != 0 && type != child.directoryType)
            _bad('Directory and inode file types disagree.');
          final references = (_references[number] ?? 0) + 1;
          _references[number] = references;
          if (!child.directory && references > child.links)
            _bad('Observed links exceed inode link count.');
          if (child.regular) await _map(child);
          _members.add(
            ViewerArchiveMember(
              name: path,
              size: child.directory ? 0 : child.size,
              isFile: !child.directory,
              isSpecial: !child.directory && !child.regular,
              isEncrypted: false,
              modified: child.modified,
              posixMode: child.mode,
              pathEscapedRoot: false,
              index: _members.length,
            ),
          );
          _files.add(child);
          if (child.directory)
            await _directory(child, path, inode.number, depth + 1);
        }
      }
    }
    if (recordNumber < 2) _bad('Missing dot directory entries.');
  }

  Stream<List<int>> _stream(_Inode inode, int requestedChunk) async* {
    _cancel();
    if (!inode.regular || inode.spans == null)
      _bad('Only mapped regular files can be read.');
    if (inode.size > maxMemberBytes) _limit('Member streaming allowance.');
    final chunk = requestedChunk < _readBytes ? requestedChunk : _readBytes;
    for (final span in inode.spans!) {
      for (var done = 0; done < span.length; done += chunk) {
        _cancel();
        final count = span.length - done < chunk ? span.length - done : chunk;
        if (span.physical == null) {
          await _checkpoint();
          yield Uint8List(count);
        } else {
          yield await _read(span.physical! + done, count, metadata: false);
        }
      }
    }
    _cancel();
  }
}

void _component(String name) {
  if (name.isEmpty ||
      name == '.' ||
      name == '..' ||
      name.codeUnits.any((c) => c < 32 || c == 127) ||
      name.contains('/') ||
      name.contains('\\') ||
      RegExp(r'^[A-Za-z]:').hasMatch(name)) {
    _bad('Unsafe filename component.');
  }
}

class _Range {
  const _Range(this.start, this.end);
  final int start, end;
}

class _Group {
  const _Group(
    this.blockBitmap,
    this.inodeBitmap,
    this.inodeTable,
    this.flags,
    this.blockBitmapChecksum,
    this.inodeBitmapChecksum,
  );
  final int blockBitmap, inodeBitmap, inodeTable, flags;
  final int blockBitmapChecksum, inodeBitmapChecksum;
}

class _Span {
  const _Span(this.start, this.length, this.physical);
  final int start, length;
  final int? physical;
}

class _Inode {
  _Inode(
    this.number,
    this.mode,
    this.flags,
    this.size,
    this.links,
    this.seed,
    this.blockMap,
    this.modified,
  );
  final int number, mode, flags, size, links, seed;
  final Uint8List blockMap;
  final DateTime? modified;
  List<_Span>? spans;
  bool get regular => mode & 0xf000 == 0x8000;
  bool get directory => mode & 0xf000 == 0x4000;
  int get directoryType => switch (mode & 0xf000) {
    0x8000 => 1,
    0x4000 => 2,
    0x2000 => 3,
    0x6000 => 4,
    0x1000 => 5,
    0xc000 => 6,
    0xa000 => 7,
    _ => 0,
  };
}

Uint8List _little32(int value) {
  final bytes = Uint8List(4);
  ByteData.sublistView(bytes).setUint32(0, value, Endian.little);
  return bytes;
}

final _crcTable = List<int>.generate(256, (index) {
  var value = index;
  for (var bit = 0; bit < 8; bit++) {
    value = (value >>> 1) ^ (value & 1 == 0 ? 0 : 0x82f63b78);
  }
  return value & 0xffffffff;
}, growable: false);
int _crc32c(int seed, Uint8List bytes, {int start = 0, int? end}) {
  var value = seed;
  for (var i = start; i < (end ?? bytes.length); i++) {
    value = (value >>> 8) ^ _crcTable[(value ^ bytes[i]) & 255];
  }
  return value & 0xffffffff;
}

int _crc16(int seed, Uint8List bytes, {int start = 0, int? end}) {
  var value = seed;
  for (var i = start; i < (end ?? bytes.length); i++) {
    value ^= bytes[i];
    for (var bit = 0; bit < 8; bit++) {
      value = (value >> 1) ^ (value & 1 == 0 ? 0 : 0xa001);
    }
  }
  return value & 65535;
}
