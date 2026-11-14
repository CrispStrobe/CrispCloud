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
// Original read-only implementation from published FAT on-disk structure facts.
// No filesystem implementation or specification text is incorporated.
// Source references and the admitted profile are in docs/archive-fat-profile.md.

import 'dart:convert';
import 'dart:typed_data';

import 'package:koni_archive/koni_archive.dart' as koni;

import 'archive_types.dart';

const _readBytes = 64 * 1024;
const _fatPageBytes = 4096;
const _fatCachePages = 256;
const _maxEntries = 100000;
const _maxMetadataBytes = 64 * 1024 * 1024;
const _maxDirectoryBytes = 32 * 1024 * 1024;
const _maxTextBytes = 16 * 1024 * 1024;
const _maxClusters = 1048576;
const _maxExtents = 100000;

/// Cancellation is not a corrupt-volume result and must not trigger fallback.
class ArchiveFatCancelledException extends ArchiveViewException {
  const ArchiveFatCancelledException()
    : super('FAT image reading was cancelled.');
}

/// Shared work allowance for FAT volumes opened inside one disk image.
///
/// Failed volume attempts also consume this allowance. Cluster-owner maps and
/// FAT pages are transient; this budget itself retains only integer counters.
class ArchiveFatTraversalBudget {
  ArchiveFatTraversalBudget({
    this.maxClusters = _maxClusters,
    this.maxExtents = _maxExtents,
  }) {
    _limitArgument(maxClusters, _maxClusters, 'maxClusters');
    _limitArgument(maxExtents, _maxExtents, 'maxExtents');
  }

  final int maxClusters, maxExtents;
  int _clusters = 0, _extents = 0;
  int get clustersVisited => _clusters;
  int get extentsCreated => _extents;
  int get remainingClusters => maxClusters - _clusters;
  int get remainingExtents => maxExtents - _extents;

  void _cluster() {
    if (_clusters >= maxClusters) _limit('Shared cluster traversal limit.');
    _clusters++;
  }

  void _extent() {
    if (_extents >= maxExtents) _limit('Shared allocation extent limit.');
    _extents++;
  }
}

Never _bad(String detail) => throw ArchiveViewException(
  'Invalid FAT image: $detail',
  code: ArchiveMessageCode.corrupt,
);
Never _unsupported(String detail) => throw ArchiveViewException(
  'Unsupported FAT image: $detail',
  code: ArchiveMessageCode.unsupported,
);
Never _limit(String detail) => throw ArchiveViewException(
  'FAT image resource limit: $detail',
  code: ArchiveMessageCode.archiveLimit,
);
void _limitArgument(int value, int ceiling, String name) {
  if (value <= 0 || value > ceiling) {
    throw ArgumentError.value(value, name, 'Expected 1 through $ceiling.');
  }
}

int _u16(Uint8List bytes, int at) =>
    ByteData.sublistView(bytes).getUint16(at, Endian.little);
int _u32(Uint8List bytes, int at) =>
    ByteData.sublistView(bytes).getUint32(at, Endian.little);
bool _jump(Uint8List bytes) =>
    bytes[0] == 0xe9 || (bytes[0] == 0xeb && bytes[2] == 0x90);
bool _powerOfTwo(int value) => value > 0 && value & (value - 1) == 0;
String _asciiField(Uint8List bytes, int start, int end) =>
    ascii.decode(bytes.sublist(start, end), allowInvalid: true);

/// A non-owning 512-byte recognition probe, not a validity or write grant.
/// An explicit FAT marker with a boot jump/signature reaches the full reader
/// even if its BPB is malformed. FAT variant selection never uses that marker.
Future<bool> hasFatVolumeRecognition(koni.ByteSource source) async {
  if (source.length < 512) return false;
  final boot = await source.read(0, 512);
  if (boot.length != 512 || _asciiField(boot, 3, 11) == 'EXFAT   ') {
    return false;
  }
  if (!_jump(boot) || boot[510] != 0x55 || boot[511] != 0xaa) return false;
  final marker = [_asciiField(boot, 54, 62), _asciiField(boot, 82, 90)];
  if (marker.any(
    (value) =>
        const ['FAT     ', 'FAT12   ', 'FAT16   ', 'FAT32   '].contains(value),
  )) {
    return true;
  }
  final sectorBytes = _u16(boot, 11);
  final sectorsPerCluster = boot[13];
  final total = _u16(boot, 19) != 0 ? _u16(boot, 19) : _u32(boot, 32);
  final fat16 = _u16(boot, 22);
  return const [512, 1024, 2048, 4096].contains(sectorBytes) &&
      _powerOfTwo(sectorsPerCluster) &&
      sectorsPerCluster <= 128 &&
      _u16(boot, 14) > 0 &&
      (boot[16] == 1 || boot[16] == 2) &&
      total > 0 &&
      ((fat16 > 0 && _u16(boot, 17) > 0) ||
          (fat16 == 0 && _u16(boot, 17) == 0 && _u32(boot, 36) > 0));
}

/// Opens a bounded, read-only FAT12/16/32 volume and owns [source].
///
/// All active chains are validated before a listing is returned. Payload reads
/// then follow immutable extents and never reread FAT allocation decisions.
/// Provider exceptions propagate unchanged; only format/profile errors use
/// [ArchiveViewException]. On every opening failure the owned source is closed.
Future<ViewerArchive> openFatArchive(
  koni.ByteSource source, {
  required int maxMemberBytes,
  int maxEntries = _maxEntries,
  int maxDirectoryBytes = _maxDirectoryBytes,
  int maxDepth = 64,
  int maxExtents = _maxExtents,
  int maxClusters = _maxClusters,
  int maxMetadataBytes = _maxMetadataBytes,
  int maxNameBytes = _maxTextBytes,
  int maxRetainedPathBytes = _maxTextBytes,
  ArchiveFatTraversalBudget? traversalBudget,
  bool Function()? isCancelled,
}) async {
  try {
    if (maxMemberBytes <= 0) {
      throw ArgumentError.value(maxMemberBytes, 'maxMemberBytes');
    }
    _limitArgument(maxEntries, _maxEntries, 'maxEntries');
    _limitArgument(maxDirectoryBytes, _maxDirectoryBytes, 'maxDirectoryBytes');
    _limitArgument(maxDepth, 64, 'maxDepth');
    _limitArgument(maxExtents, _maxExtents, 'maxExtents');
    _limitArgument(maxClusters, _maxClusters, 'maxClusters');
    _limitArgument(maxMetadataBytes, _maxMetadataBytes, 'maxMetadataBytes');
    _limitArgument(maxNameBytes, _maxTextBytes, 'maxNameBytes');
    _limitArgument(maxRetainedPathBytes, _maxTextBytes, 'maxRetainedPathBytes');
    return await _FatReader(
      source,
      maxMemberBytes: maxMemberBytes < kArchiveStreamingLimit
          ? maxMemberBytes
          : kArchiveStreamingLimit,
      maxEntries: maxEntries,
      maxDirectoryBytes: maxDirectoryBytes,
      maxDepth: maxDepth,
      maxExtents: maxExtents,
      maxClusters: maxClusters,
      maxMetadataBytes: maxMetadataBytes,
      maxNameBytes: maxNameBytes,
      maxRetainedPathBytes: maxRetainedPathBytes,
      budget: traversalBudget ?? ArchiveFatTraversalBudget(),
      isCancelled: isCancelled,
    ).open();
  } catch (_) {
    try {
      await source.close();
    } catch (_) {
      // Keep the original format, transport or cancellation failure.
    }
    rethrow;
  }
}

class _FatReader {
  _FatReader(
    this.source, {
    required this.maxMemberBytes,
    required this.maxEntries,
    required this.maxDirectoryBytes,
    required this.maxDepth,
    required this.maxExtents,
    required this.maxClusters,
    required this.maxMetadataBytes,
    required this.maxNameBytes,
    required this.maxRetainedPathBytes,
    required this.budget,
    this.isCancelled,
  });

  final koni.ByteSource source;
  final int maxMemberBytes, maxEntries, maxDirectoryBytes, maxDepth;
  final int maxExtents, maxClusters, maxMetadataBytes;
  final int maxNameBytes, maxRetainedPathBytes;
  final ArchiveFatTraversalBudget budget;
  final bool Function()? isCancelled;
  final _members = <ViewerArchiveMember>[];
  final _files = <_FatFile>[];
  final _claimed = <int>{};
  final _fatPages = <int, Uint8List>{};
  final _notices = <String>{
    'Read-only FAT filesystem. Allocation checks do not authenticate file '
        'contents and do not establish consistency of unreferenced clusters.',
    'Deleted records, free space, extended attributes and legacy OEM-only '
        'short names are not recovered. Files are exposed without FAT write '
        'or repair authority.',
  };
  late int _sectorBytes, _clusterBytes, _fatBytes, _fatStart, _dataStart;
  late int _fatBits, _clusterCount, _lastCluster, _volumeBytes;
  late int _fatCount, _activeFat;
  late bool _mirrored;
  var _metadataBytes = 0, _directoryBytes = 0, _nameBytes = 0, _pathBytes = 0;
  var _clusters = 0, _extents = 0, _work = 0;
  var _closed = false, _volumeLabelSeen = false;

  void _checkCancelled() {
    if (_closed || (isCancelled?.call() ?? false)) {
      throw const ArchiveFatCancelledException();
    }
  }

  Future<void> _checkpoint() async {
    _checkCancelled();
    if (++_work % 128 == 0) {
      await Future<void>.delayed(Duration.zero);
      _checkCancelled();
    }
  }

  Future<Uint8List> _read(
    int offset,
    int length, {
    bool metadata = true,
  }) async {
    await _checkpoint();
    if (length < 0 ||
        length > _readBytes ||
        offset < 0 ||
        offset > source.length ||
        length > source.length - offset) {
      _bad('A read leaves the bounded image.');
    }
    if (metadata) {
      if (length > maxMetadataBytes - _metadataBytes) {
        _limit('Metadata read bytes.');
      }
      _metadataBytes += length;
    }
    final result = await source.read(offset, length);
    _checkCancelled();
    if (result.length != length) _bad('Truncated image read.');
    return result;
  }

  Future<ViewerArchive> open() async {
    if (source.length < 512 || source.length > 9007199254740991) {
      _bad('The source length cannot contain an exact FAT boot sector.');
    }
    final boot = await _read(0, 512);
    if (_asciiField(boot, 3, 11) == 'EXFAT   ') {
      _unsupported('exFAT is outside the FAT12/16/32 profile.');
    }
    if (!_jump(boot) || boot[510] != 0x55 || boot[511] != 0xaa) {
      _bad('Missing boot jump or 55AA signature.');
    }
    _sectorBytes = _u16(boot, 11);
    if (!const [512, 1024, 2048, 4096].contains(_sectorBytes)) {
      _unsupported(
        'Logical sector size must be 512, 1024, 2048 or 4096 bytes.',
      );
    }
    final sectorsPerCluster = boot[13];
    if (!_powerOfTwo(sectorsPerCluster) || sectorsPerCluster > 128) {
      _bad('Invalid sectors-per-cluster value.');
    }
    _clusterBytes = _sectorBytes * sectorsPerCluster;
    if (_clusterBytes > 32768) _unsupported('Clusters larger than 32 KiB.');
    final reserved = _u16(boot, 14);
    _fatCount = boot[16];
    final rootEntries = _u16(boot, 17);
    final total16 = _u16(boot, 19), total32 = _u32(boot, 32);
    if (reserved == 0 ||
        (total16 == 0 && total32 == 0) ||
        (total16 != 0 && total32 != 0)) {
      _bad('Ambiguous total-sector count or empty reserved region.');
    }
    if (_fatCount != 1 && _fatCount != 2) {
      _unsupported('Only one or two FAT tables are admitted.');
    }
    final total = total16 != 0 ? total16 : total32;
    _volumeBytes = total * _sectorBytes;
    if (_volumeBytes > source.length) _bad('The BPB volume leaves the image.');
    final fat16 = _u16(boot, 22);
    final fatSectors = fat16 != 0 ? fat16 : _u32(boot, 36);
    if (fatSectors == 0) _bad('The allocation table is empty.');
    final rootBytes = rootEntries * 32;
    final rootSectors = (rootBytes + _sectorBytes - 1) ~/ _sectorBytes;
    final dataSector = reserved + _fatCount * fatSectors + rootSectors;
    if (dataSector >= total) {
      _bad('Metadata consumes the entire declared volume.');
    }
    _clusterCount = (total - dataSector) ~/ sectorsPerCluster;
    if (_clusterCount < 1) _bad('No data clusters.');
    _fatBits = _clusterCount < 4085 ? 12 : (_clusterCount < 65525 ? 16 : 32);
    _lastCluster = _clusterCount + 1;
    if (_fatBits == 32 && _lastCluster >= 0x0ffffff0) {
      _unsupported('FAT32 cluster count reaches reserved cluster indices.');
    }
    if ((_fatBits == 32 && (fat16 != 0 || rootEntries != 0 || total16 != 0)) ||
        (_fatBits != 32 &&
            (fat16 == 0 ||
                rootEntries == 0 ||
                rootBytes % _sectorBytes != 0))) {
      _bad('BPB layout disagrees with the cluster-count FAT variant.');
    }
    _fatBytes = fatSectors * _sectorBytes;
    final requiredFatBytes = ((_clusterCount + 2) * _fatBits + 7) ~/ 8;
    if (_fatBytes < requiredFatBytes) {
      _bad('The FAT cannot address all data clusters.');
    }
    _fatStart = reserved * _sectorBytes;
    _dataStart = dataSector * _sectorBytes;
    _activeFat = 0;
    _mirrored = true;
    var rootCluster = 0;
    if (_fatBits == 32) {
      if (_u16(boot, 42) != 0) {
        _unsupported('FAT32 filesystem version is not 0.0.');
      }
      final flags = _u16(boot, 40);
      if (flags & 0xff70 != 0) _unsupported('Unknown FAT32 extended flags.');
      _mirrored = flags & 0x80 == 0;
      if (!_mirrored) {
        _activeFat = flags & 15;
        if (_activeFat >= _fatCount) {
          _bad('Active FAT index leaves the table set.');
        }
        _notices.add(
          'FAT32 mirroring is disabled; allocation uses FAT '
          '${_activeFat + 1} only. Inactive tables are not used as fallbacks.',
        );
      }
      rootCluster = _u32(boot, 44);
      _checkCluster(rootCluster);
      await _fat32Hints(boot, reserved);
    }
    final media = boot[21];
    if (media != 0xf0 && (media < 0xf8 || media > 0xff)) {
      _bad('Invalid media descriptor.');
    }
    final first = await _fatEntry(0);
    if (first != ((_fatMask & ~255) | media)) {
      _bad('The FAT media entry disagrees with the BPB.');
    }
    final state = await _fatEntry(1);
    if (_fatBits == 12) {
      if (state < 0xff8) _bad('Invalid reserved FAT12 end entry.');
    } else {
      final clean = _fatBits == 16 ? 0x8000 : 0x08000000;
      final noError = _fatBits == 16 ? 0x4000 : 0x04000000;
      final fixed = _fatMask & ~(clean | noError);
      if (state & fixed != fixed) _bad('Invalid reserved FAT state entry.');
      if (state & clean == 0) {
        _notices.add(
          'The FAT volume is marked dirty (not cleanly dismounted). '
          'No repair or consistency guarantee follows from this listing.',
        );
      }
      if (state & noError == 0) {
        _notices.add('The FAT volume records an earlier disk I/O error.');
      }
    }
    _notices.add(
      'FAT$_fatBits; $_sectorBytes-byte sectors, '
      '$_clusterBytes-byte clusters. '
      '${_mirrored && _fatCount > 1 ? 'Traversed entries agree across both FATs.' : 'A single allocation table is authoritative.'}',
    );
    if (_volumeBytes < source.length) {
      _notices.add(
        'Bytes after the BPB-declared FAT volume are not interpreted.',
      );
    }
    final root = _fatBits == 32
        ? await _chain(rootCluster, directory: true)
        : _fixedRoot(_fatStart + _fatCount * _fatBytes, rootBytes);
    await _directory(root, '', rootCluster, 0, 0, true);
    _checkCancelled();
    // Allocation decisions are now immutable extents. Do not retain one FAT
    // cache and one potentially large ownership set per opened partition.
    _fatPages.clear();
    _claimed.clear();
    return ViewerArchive.reader(
      formatName: 'fat',
      maxStreamingMemberBytes: maxMemberBytes,
      members: _members,
      notices: _notices.toList(growable: false),
      read: (member, requested) async {
        _checkCancelled();
        final limit = requested < maxMemberBytes ? requested : maxMemberBytes;
        if (member.size > limit || member.size > kArchiveReadLimit) {
          _limit(
            'Buffered member reads are limited to '
            '${limit < kArchiveReadLimit ? limit : kArchiveReadLimit} bytes.',
          );
        }
        final output = Uint8List(member.size);
        var at = 0;
        await for (final bytes in _stream(_files[member.index], _readBytes)) {
          output.setRange(at, at + bytes.length, bytes);
          at += bytes.length;
        }
        return output;
      },
      streamReader: (member, chunkSize) =>
          _stream(_files[member.index], chunkSize),
      close: () async {
        _closed = true;
        _fatPages.clear();
        _claimed.clear();
        await source.close();
      },
    );
  }

  int get _fatMask =>
      _fatBits == 12 ? 0xfff : (_fatBits == 16 ? 0xffff : 0x0fffffff);
  int get _reservedStart =>
      _fatBits == 12 ? 0xff0 : (_fatBits == 16 ? 0xfff0 : 0x0ffffff0);
  int get _endStart => _reservedStart + 8;

  void _checkCluster(int cluster) {
    if (cluster < 2 || cluster > _lastCluster || cluster >= _reservedStart) {
      _bad(
        'A cluster reference is free, reserved, bad or outside the data region.',
      );
    }
  }

  Future<void> _fat32Hints(Uint8List boot, int reserved) async {
    final info = _u16(boot, 48);
    if (info == 0 || info == 0xffff) {
      _notices.add(
        'FAT32 FSInfo hints are absent and are not needed for reading.',
      );
    } else {
      if (info >= reserved) _bad('FSInfo pointer leaves the reserved region.');
      final bytes = await _read(info * _sectorBytes, 512);
      final signatures =
          _u32(bytes, 0) == 0x41615252 &&
          _u32(bytes, 484) == 0x61417272 &&
          _u32(bytes, 508) == 0xaa550000;
      final free = _u32(bytes, 488), next = _u32(bytes, 492);
      if (!signatures ||
          (free != 0xffffffff && free > _clusterCount) ||
          (next != 0xffffffff && (next < 2 || next > _lastCluster))) {
        _notices.add(
          'Invalid or out-of-range FAT32 FSInfo hints were ignored. '
          'File allocations come from the selected FAT, not free-space hints.',
        );
      }
    }
    final backup = _u16(boot, 50);
    if (backup == 0 || backup == 0xffff) {
      _notices.add('No FAT32 backup boot sector is used for reconstruction.');
      return;
    }
    if (backup >= reserved || backup == info) {
      _bad('Backup boot pointer leaves its reserved slot.');
    }
    final copy = await _read(backup * _sectorBytes, 512);
    var matches = copy[510] == 0x55 && copy[511] == 0xaa;
    for (var i = 11; i < 52; i++) {
      if (copy[i] != boot[i]) matches = false;
    }
    if (!matches) {
      _notices.add(
        'FAT32 backup boot metadata differs from the primary. '
        'Only the validated primary BPB is used; no backup repair is attempted.',
      );
    }
  }

  Future<Uint8List> _fatPage(int table, int page) async {
    final key = table * 4294967296 + page;
    final cached = _fatPages.remove(key);
    if (cached != null) {
      _fatPages[key] = cached;
      return cached;
    }
    final offset = page * _fatPageBytes;
    final count = _fatBytes - offset < _fatPageBytes
        ? _fatBytes - offset
        : _fatPageBytes;
    if (count <= 0) _bad('A FAT page leaves its allocation table.');
    final bytes = await _read(_fatStart + table * _fatBytes + offset, count);
    if (_fatPages.length == _fatCachePages) {
      _fatPages.remove(_fatPages.keys.first);
    }
    _fatPages[key] = bytes;
    return bytes;
  }

  Future<int> _tableEntry(int table, int cluster) async {
    final offset = _fatBits == 12
        ? cluster * 3 ~/ 2
        : cluster * (_fatBits ~/ 8);
    final count = _fatBits == 32 ? 4 : 2;
    if (offset > _fatBytes - count) {
      _bad('A FAT entry leaves its allocation table.');
    }
    var value = 0;
    for (var i = 0; i < count; i++) {
      final at = offset + i;
      final page = await _fatPage(table, at ~/ _fatPageBytes);
      // Multiplication keeps the unsigned high byte exact in JavaScript.
      value += page[at % _fatPageBytes] * (1 << (8 * i));
    }
    if (_fatBits == 12 && cluster.isOdd) value ~/= 16;
    return value & _fatMask;
  }

  Future<int> _fatEntry(int cluster) async {
    await _checkpoint();
    final value = await _tableEntry(_activeFat, cluster);
    if (_mirrored && _fatCount > 1) {
      final copy = await _tableEntry(1, cluster);
      if (copy != value) _bad('Mirrored FATs disagree at cluster $cluster.');
    }
    return value;
  }

  void _extent() {
    if (_extents >= maxExtents) _limit('Allocation extent count.');
    budget._extent();
    _extents++;
  }

  _FatFile _fixedRoot(int offset, int length) {
    if (length > maxDirectoryBytes - _directoryBytes) {
      _limit('Directory allocation bytes.');
    }
    _directoryBytes += length;
    _extent();
    return _FatFile(length, [_FatExtent(offset, length)]);
  }

  Future<_FatFile> _chain(
    int first, {
    int? size,
    bool directory = false,
  }) async {
    if (size == 0) {
      if (first != 0) {
        _bad('An empty regular file has an allocated cluster chain.');
      }
      return const _FatFile(0, []);
    }
    _checkCluster(first);
    final expected = size == null
        ? null
        : (size + _clusterBytes - 1) ~/ _clusterBytes;
    final extents = <_FatExtent>[];
    var cluster = first, count = 0;
    while (true) {
      await _checkpoint();
      _checkCluster(cluster);
      if (_clusters >= maxClusters) _limit('Cluster traversal count.');
      budget._cluster();
      _clusters++;
      if (!_claimed.add(cluster)) {
        _bad('A cluster chain loops or crosses another file/directory.');
      }
      if (directory) {
        if (_clusterBytes > maxDirectoryBytes - _directoryBytes) {
          _limit('Directory allocation bytes.');
        }
        _directoryBytes += _clusterBytes;
      }
      count++;
      final offset = _dataStart + (cluster - 2) * _clusterBytes;
      if (offset > _volumeBytes - _clusterBytes) {
        _bad('A cluster leaves the declared volume.');
      }
      if (extents.isNotEmpty &&
          extents.last.offset + extents.last.length == offset) {
        final previous = extents.removeLast();
        extents.add(
          _FatExtent(previous.offset, previous.length + _clusterBytes),
        );
      } else {
        _extent();
        extents.add(_FatExtent(offset, _clusterBytes));
      }
      final next = await _fatEntry(cluster);
      if (next >= _endStart) {
        if (expected != null && count != expected) {
          _bad('File chain is shorter than its declared size.');
        }
        break;
      }
      _checkCluster(next);
      if (expected != null && count >= expected) {
        _bad('File chain exceeds its declared size.');
      }
      cluster = next;
    }
    final logicalSize = size ?? count * _clusterBytes;
    var remaining = logicalSize;
    final trimmed = <_FatExtent>[];
    for (final extent in extents) {
      await _checkpoint();
      final length = extent.length < remaining ? extent.length : remaining;
      if (length > 0) trimmed.add(_FatExtent(extent.offset, length));
      remaining -= length;
    }
    if (remaining != 0) _bad('Allocation extent lengths disagree.');
    return _FatFile(logicalSize, List.unmodifiable(trimmed));
  }

  int _firstCluster(Uint8List entry) {
    final high = _u16(entry, 20);
    if (_fatBits != 32 && high != 0) {
      _bad('FAT12/16 directory entry has a high cluster word.');
    }
    return _u16(entry, 26) + high * 65536;
  }

  Future<void> _directory(
    _FatFile file,
    String prefix,
    int selfCluster,
    int parentCluster,
    int depth,
    bool root,
  ) async {
    if (depth > maxDepth) _limit('Directory depth.');
    final names = <String, int>{};
    _LongName? longName;
    var record = 0;
    for (final extent in file.extents) {
      for (var offset = 0; offset < extent.length;) {
        final count = extent.length - offset < _readBytes
            ? extent.length - offset
            : _readBytes;
        final bytes = await _read(extent.offset + offset, count);
        offset += count;
        for (var at = 0; at < bytes.length; at += 32, record++) {
          await _checkpoint();
          final entry = Uint8List.sublistView(bytes, at, at + 32);
          if (entry[0] == 0) {
            if (longName != null) {
              _bad('An orphan long-name sequence precedes directory end.');
            }
            if (!root && record < 2) _bad('Missing dot directory records.');
            return;
          }
          if (entry[0] == 0xe5) {
            if (longName != null) {
              _bad('An orphan long-name sequence precedes a deleted record.');
            }
            if (!root && record < 2) _bad('Missing dot directory records.');
            continue;
          }
          final attribute = entry[11];
          if (attribute & 0xc0 != 0) {
            _unsupported('Unknown directory attribute bits.');
          }
          if (attribute == 0x0f) {
            if (!root && record < 2) _bad('Missing dot directory records.');
            if (entry[0] & 0x40 != 0) {
              if (longName != null) _bad('Overlapping long-name sequences.');
              longName = _LongName(entry);
            } else {
              if (longName == null) {
                _bad('Long-name sequence has no final ordinal.');
              }
              longName.add(entry);
            }
            continue;
          }
          final first = _firstCluster(entry);
          final size = _u32(entry, 28);
          final directory = attribute & 0x10 != 0;
          final volume = attribute & 0x08 != 0;
          if (directory && volume) {
            _bad('A record is both a directory and a volume label.');
          }
          final dot =
              entry[0] == 0x2e &&
              ((entry[1] == 0x20 &&
                      entry.sublist(1, 11).every((b) => b == 0x20)) ||
                  (entry[1] == 0x2e &&
                      entry.sublist(2, 11).every((b) => b == 0x20)));
          if (dot) {
            final dotdot = entry[1] == 0x2e;
            if (root ||
                longName != null ||
                !directory ||
                size != 0 ||
                record != (dotdot ? 1 : 0) ||
                first != (dotdot ? parentCluster : selfCluster)) {
              _bad('Invalid dot or parent directory record.');
            }
            continue;
          }
          if (!root && record < 2) _bad('Missing dot directory records.');
          if (volume) {
            if (!root ||
                _volumeLabelSeen ||
                longName != null ||
                first != 0 ||
                size != 0) {
              _bad('Invalid or duplicate volume-label record.');
            }
            _volumeLabelSeen = true;
            continue;
          }
          if (entry[12] & ~0x18 != 0) {
            _unsupported('Unknown short-name case flags.');
          }
          final alias = _shortName(entry, requiredText: longName == null);
          final name = longName == null ? alias! : longName.finish(entry);
          longName = null;
          _component(name);
          final index = _members.length;
          if (index >= maxEntries) {
            throw const ArchiveViewException(
              'FAT directory entry limit exceeded.',
              code: ArchiveMessageCode.entryLimit,
            );
          }
          void claim(String key) {
            final other = names[key];
            if (other != null && other != index) {
              _bad('Duplicate or conflicting FAT names/aliases.');
            }
            names[key] = index;
          }

          for (final value in [name, if (alias != null) alias]) {
            claim('u:${value.toUpperCase()}');
            claim('l:${value.toLowerCase()}');
          }
          claim('s:${String.fromCharCodes(entry.take(11))}');
          final componentBytes = name.length * 2;
          if (componentBytes > maxNameBytes - _nameBytes) {
            _limit('Decoded filename component bytes.');
          }
          _nameBytes += componentBytes;
          final path = prefix.isEmpty ? name : '$prefix/$name';
          if (path.length > 4096) _limit('Individual member path length.');
          final pathBytes = path.length * 2;
          if (pathBytes > maxRetainedPathBytes - _pathBytes) {
            _limit('Retained full-path text bytes.');
          }
          _pathBytes += pathBytes;
          if (directory && size != 0) {
            _bad('A directory has a nonzero file-size field.');
          }
          final allocation = await _chain(
            first,
            size: directory ? null : size,
            directory: directory,
          );
          _members.add(
            ViewerArchiveMember(
              name: path,
              size: directory ? 0 : size,
              isFile: !directory,
              isEncrypted: false,
              modified: _timestamp(entry),
              pathEscapedRoot: false,
              index: index,
            ),
          );
          _files.add(directory ? const _FatFile(0, []) : allocation);
          if (directory) {
            await _directory(
              allocation,
              path,
              first,
              root ? 0 : selfCluster,
              depth + 1,
              false,
            );
          }
        }
      }
    }
    if (longName != null) {
      _bad('An orphan long-name sequence ends a directory chain.');
    }
    if (!root && record < 2) _bad('Missing dot directory records.');
  }

  String? _shortName(Uint8List entry, {required bool requiredText}) {
    if (entry[0] == 0x20) _bad('Empty short-name base.');
    final extended = entry[0] == 5 || entry.take(11).any((b) => b >= 128);
    // A Unicode LFN supplies the exposed name. Its OEM alias remains an opaque
    // checksum/identity value: a DBCS trailing byte can coincide with ASCII
    // punctuation or a lowercase letter. No code page or alias is invented.
    if (extended) {
      for (var i = 0; i < 11; i++) {
        if (entry[i] < 32 && !(i == 0 && entry[i] == 5)) {
          _bad('Invalid control byte in an OEM short-name alias.');
        }
      }
      if (requiredText) {
        _unsupported(
          'OEM short-name decoding needs a valid Unicode long name.',
        );
      }
      return null;
    }
    const illegal = {
      0x22,
      0x2a,
      0x2b,
      0x2c,
      0x2e,
      0x2f,
      0x3a,
      0x3b,
      0x3c,
      0x3d,
      0x3e,
      0x3f,
      0x5b,
      0x5c,
      0x5d,
      0x7c,
    };
    for (var i = 0; i < 11; i++) {
      final byte = entry[i];
      if (byte < 0x20 ||
          byte == 0x7f ||
          illegal.contains(byte) ||
          (byte >= 97 && byte <= 122)) {
        _bad('Invalid short-name alias bytes.');
      }
    }
    var base = ascii.decode(entry.sublist(0, 8)).trimRight();
    var extension = ascii.decode(entry.sublist(8, 11)).trimRight();
    if (entry[12] & 8 != 0) base = base.toLowerCase();
    if (entry[12] & 16 != 0) extension = extension.toLowerCase();
    return extension.isEmpty ? base : '$base.$extension';
  }

  DateTime? _timestamp(Uint8List entry) {
    final date = _u16(entry, 24), time = _u16(entry, 22);
    if (date == 0 && time == 0) return null;
    final year = 1980 + (date >> 9), month = (date >> 5) & 15, day = date & 31;
    final hour = time >> 11,
        minute = (time >> 5) & 63,
        second = (time & 31) * 2;
    if (month < 1 ||
        month > 12 ||
        day < 1 ||
        day > 31 ||
        hour > 23 ||
        minute > 59 ||
        second > 59) {
      _notices.add('Invalid FAT modification timestamps were omitted.');
      return null;
    }
    final value = DateTime(year, month, day, hour, minute, second);
    if (value.year != year ||
        value.month != month ||
        value.day != day ||
        value.hour != hour ||
        value.minute != minute ||
        value.second != second) {
      _notices.add('Unrepresentable FAT modification timestamps were omitted.');
      return null;
    }
    return value;
  }

  Stream<List<int>> _stream(_FatFile file, int requestedChunk) async* {
    _checkCancelled();
    if (file.size > maxMemberBytes) _limit('Member streaming allowance.');
    final chunk = requestedChunk < _readBytes ? requestedChunk : _readBytes;
    for (final extent in file.extents) {
      for (var at = 0; at < extent.length; at += chunk) {
        final count = extent.length - at < chunk ? extent.length - at : chunk;
        yield await _read(extent.offset + at, count, metadata: false);
      }
    }
    _checkCancelled();
  }
}

void _component(String name) {
  if (name.isEmpty ||
      name.length > 255 ||
      name == '.' ||
      name == '..' ||
      name.startsWith(' ') ||
      name.endsWith(' ') ||
      name.endsWith('.') ||
      name.codeUnits.any((c) => c < 32 || c == 127) ||
      name.contains(RegExp(r'[<>:"/\\|?*]'))) {
    _bad('Unsafe or noncanonical filename component.');
  }
  final stem = name.split('.').first.toUpperCase();
  if (const {'CON', 'PRN', 'AUX', 'NUL'}.contains(stem) ||
      RegExp(r'^(COM|LPT)[1-9]$').hasMatch(stem)) {
    _unsupported('Reserved device filename component.');
  }
}

class _LongName {
  _LongName(Uint8List first)
    : count = first[0] & 31,
      checksum = first[13],
      next = first[0] & 31 {
    if (count < 1 || count > 20 || first[0] != (0x40 | count)) {
      _bad('Invalid final long-name ordinal.');
    }
    units = Uint16List(count * 13);
    add(first, first: true);
  }

  final int count, checksum;
  int next;
  late final Uint16List units;
  void add(Uint8List entry, {bool first = false}) {
    if (next < 1 ||
        entry[0] != (first ? (0x40 | next) : next) ||
        entry[11] != 0x0f ||
        entry[13] != checksum ||
        _u16(entry, 26) != 0) {
      _bad('Invalid long-name order, checksum or cluster field.');
    }
    if (entry[12] != 0) _unsupported('Unknown long-name record type.');
    final positions = [1, 3, 5, 7, 9, 14, 16, 18, 20, 22, 24, 28, 30];
    for (var i = 0; i < positions.length; i++) {
      units[(next - 1) * 13 + i] = _u16(entry, positions[i]);
    }
    next--;
  }

  String finish(Uint8List shortEntry) {
    if (next != 0) _bad('Incomplete long-name sequence.');
    var expected = 0;
    for (var i = 0; i < 11; i++) {
      expected =
          ((expected ~/ 2) + (expected.isOdd ? 128 : 0) + shortEntry[i]) % 256;
    }
    if (expected != checksum) {
      _bad('Long-name checksum does not match its alias.');
    }
    final end = units.indexOf(0);
    final length = end < 0 ? units.length : end;
    if (length < 1 || length > 255 || length <= (count - 1) * 13) {
      _bad('Invalid long-name length or unnecessary continuation.');
    }
    if (end >= 0 && units.skip(end + 1).any((u) => u != 0xffff)) {
      _bad('Invalid long-name terminator padding.');
    }
    for (var i = 0; i < length; i++) {
      final unit = units[i];
      if (unit == 0xffff || unit == 0xfffe) {
        _bad('Invalid Unicode filename unit.');
      }
      if (unit >= 0xd800 && unit <= 0xdbff) {
        if (++i >= length || units[i] < 0xdc00 || units[i] > 0xdfff) {
          _bad('Unpaired Unicode filename surrogate.');
        }
      } else if (unit >= 0xdc00 && unit <= 0xdfff) {
        _bad('Unpaired Unicode filename surrogate.');
      }
    }
    return String.fromCharCodes(units.take(length));
  }
}

class _FatFile {
  const _FatFile(this.size, this.extents);
  final int size;
  final List<_FatExtent> extents;
}

class _FatExtent {
  const _FatExtent(this.offset, this.length);
  final int offset, length;
}
