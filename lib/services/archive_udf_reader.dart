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
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//
// Original implementation of ECMA-167 (3rd ed.), parts 2-4, and the physical
// partition profile of UDF 1.02/1.50/2.00/2.01. No third-party implementation
// code is incorporated. Specification links and exact scope are documented in
// docs/archive-udf-profile.md.

import 'dart:convert';
import 'dart:typed_data';

import 'package:koni_archive/koni_archive.dart' as koni;

import 'archive_types.dart';

const _blockBytes = 2048;
const _readChunkBytes = 64 * 1024;
const _maxRetainedPathBytes = 16 * 1024 * 1024;

/// Non-owning, bounded recognition of NSR02/NSR03 after BEA01. ISO descriptors
/// may precede the extended area in a bridge image. This does not authorize
/// reading or writing: [openUdfArchive] validates the remaining structures.
Future<bool> hasUdfVolumeRecognition(koni.ByteSource source) async {
  var extended = false;
  for (var sector = 16; sector < 144; sector++) {
    final offset = sector * _blockBytes;
    if (offset > source.length - 7) return false;
    final bytes = await source.read(offset, 7);
    if (bytes.length != 7) return false;
    final id = ascii.decode(bytes.sublist(1, 6), allowInvalid: true);
    if (id == 'CD001' && !extended) continue;
    if (bytes[0] != 0 || bytes[6] != 1) return false;
    if (id == 'BEA01' && !extended) {
      extended = true;
    } else if ((id == 'NSR02' || id == 'NSR03') && extended) {
      return true;
    } else if (id != 'BOOT2') {
      return false;
    }
  }
  return false;
}

/// Read-only physical-partition UDF with lazy, bounded member reads.
/// The returned archive owns [source], including when opening fails.
/// [maxRetainedPathBytes] may lower the fixed 16 MiB aggregate full-path budget;
/// accounting charges two bytes per UTF-16 code unit, including repeated prefixes.
Future<ViewerArchive> openUdfArchive(
  koni.ByteSource source, {
  required int maxMemberBytes,
  int maxEntries = 100000,
  int maxDirectoryBytes = 32 * 1024 * 1024,
  int maxDepth = 64,
  int maxExtents = 100000,
  int maxMetadataBytes = 64 * 1024 * 1024,
  int maxRetainedPathBytes = _maxRetainedPathBytes,
}) async {
  try {
    if ([
      maxMemberBytes,
      maxEntries,
      maxDirectoryBytes,
      maxDepth,
      maxExtents,
      maxMetadataBytes,
      maxRetainedPathBytes,
    ].any((limit) => limit <= 0)) {
      throw ArgumentError('UDF reader limits must be positive.');
    }
    if (maxRetainedPathBytes > _maxRetainedPathBytes) {
      throw ArgumentError.value(
        maxRetainedPathBytes,
        'maxRetainedPathBytes',
        'The aggregate full-path budget cannot exceed 16 MiB.',
      );
    }
    return await _UdfReader(
      source,
      maxMemberBytes,
      maxEntries,
      maxDirectoryBytes,
      maxDepth,
      maxExtents,
      maxMetadataBytes,
      maxRetainedPathBytes,
    ).open();
  } catch (error) {
    await source.close();
    if (error is ArchiveViewException || error is ArgumentError) rethrow;
    throw ArchiveViewException('Could not read the UDF image: $error');
  }
}

class _UdfReader {
  _UdfReader(
    this.source,
    this.maxMemberBytes,
    this.maxEntries,
    this.maxDirectoryBytes,
    this.maxDepth,
    this.maxExtents,
    this.maxMetadataBytes,
    this.maxRetainedPathBytes,
  );

  final koni.ByteSource source;
  final int maxMemberBytes, maxEntries, maxDirectoryBytes, maxDepth;
  final int maxExtents, maxMetadataBytes;
  final int maxRetainedPathBytes;
  var _metadataBytes = 0;
  var _directoryBytes = 0;
  var _extentCount = 0;
  var _nameBytes = 0;
  var _retainedPathBytes = 0;
  var _readCount = 0;
  var _identifierCount = 0;
  var _revision = 0;
  final _partitions = <_Partition>[];
  final _members = <ViewerArchiveMember>[];
  final _files = <_File>[];
  final _cache = <String, _File>{};
  final _directories = <String>{};
  final _paths = <String>{};
  final _notices = <String>{
    'Read-only UDF physical partitions. Descriptor checks do not authenticate '
        'file contents; UDF has no general file-content checksum.',
    'Permissions and modification times are listed when representable. '
        'Extended attributes and alternate streams are not restored.',
  };

  Never _bad(String detail) =>
      throw ArchiveViewException('Invalid UDF image: $detail');
  Never _unsupported(String detail) =>
      throw ArchiveViewException('Unsupported UDF image: $detail');
  int _u16(Uint8List bytes, int at) =>
      ByteData.sublistView(bytes).getUint16(at, Endian.little);
  int _u32(Uint8List bytes, int at) =>
      ByteData.sublistView(bytes).getUint32(at, Endian.little);
  int _size64(Uint8List bytes, int at) {
    // Use explicit halves rather than getUint64: compiled JavaScript must not
    // round a malicious large declaration into an allowed logical length.
    final low = _u32(bytes, at);
    final high = _u32(bytes, at + 4);
    if (high > 2 || (high == 2 && low != 0)) {
      _unsupported('A logical file exceeds the 8 GiB profile.');
    }
    return high * 4294967296 + low;
  }

  Future<Uint8List> _read(
    int offset,
    int length, {
    bool metadata = true,
  }) async {
    if (offset < 0 ||
        length < 0 ||
        offset > source.length ||
        length > source.length - offset) {
      _bad('An extent leaves the image.');
    }
    if (metadata) {
      if (length > maxMetadataBytes - _metadataBytes) {
        _bad('Metadata read limit exceeded.');
      }
      _metadataBytes += length;
    }
    final output = Uint8List(length);
    for (var done = 0; done < length;) {
      if (++_readCount % 128 == 0) await Future<void>.delayed(Duration.zero);
      final count = length - done < _readChunkBytes
          ? length - done
          : _readChunkBytes;
      final bytes = await source.read(offset + done, count);
      if (bytes.length != count) _bad('The image is truncated.');
      output.setRange(done, done + count, bytes);
      done += count;
    }
    return output;
  }

  int _crc(Uint8List bytes, int begin, int end) {
    var crc = 0;
    for (var i = begin; i < end; i++) {
      crc ^= bytes[i] << 8;
      for (var bit = 0; bit < 8; bit++) {
        crc = ((crc << 1) ^ (crc & 0x8000 == 0 ? 0 : 0x1021)) & 0xffff;
      }
    }
    return crc;
  }

  void _tag(
    Uint8List bytes,
    int id,
    int location,
    int length, {
    bool allocationExtent = false,
  }) {
    if (length < 16 || length > bytes.length || _u16(bytes, 0) != id) {
      _bad('A descriptor has the wrong type or length.');
    }
    if (!const [2, 3].contains(_u16(bytes, 2))) {
      _unsupported('Unknown descriptor version.');
    }
    var sum = 0;
    for (var i = 0; i < 16; i++) {
      if (i != 4) sum += bytes[i];
    }
    if ((sum & 255) != bytes[4] || bytes[5] != 0) {
      _bad('Descriptor tag checksum or reserved byte.');
    }
    if (_u32(bytes, 12) != location) {
      _bad('Descriptor tag location disagrees with its address.');
    }
    final crcLength = _u16(bytes, 10);
    if (crcLength != length - 16 && !(allocationExtent && crcLength == 8)) {
      _bad('Descriptor CRC does not cover its required fields.');
    }
    if (_crc(bytes, 16, 16 + crcLength) != _u16(bytes, 8)) {
      _bad('Descriptor CRC mismatch.');
    }
  }

  String _identifier(Uint8List bytes, int at, int count) {
    final end = bytes.indexOf(0, at);
    return ascii.decode(
      bytes.sublist(at, end < 0 || end > at + count ? at + count : end),
      allowInvalid: true,
    );
  }

  void _charset(Uint8List bytes, int at) {
    if (bytes[at] != 0 ||
        _identifier(bytes, at + 1, 63) != 'OSTA Compressed Unicode') {
      _unsupported('Only the OSTA CS0 character set is supported.');
    }
  }

  int _domain(Uint8List bytes, int at) {
    if (_identifier(bytes, at + 1, 23) != '*OSTA UDF Compliant') {
      _unsupported('The logical volume is outside the OSTA UDF domain.');
    }
    final revision = _u16(bytes, at + 24);
    if (!const [0x102, 0x150, 0x200, 0x201].contains(revision)) {
      _unsupported(
        'UDF revision ${revision.toRadixString(16)} is outside the 1.02/1.50/2.00/2.01 profile.',
      );
    }
    return revision;
  }

  Future<void> _recognition() async {
    var extended = false;
    var nsr = false;
    for (var sector = 16; sector < 144; sector++) {
      final bytes = await _read(sector * _blockBytes, 7);
      final id = ascii.decode(bytes.sublist(1, 6), allowInvalid: true);
      if (!extended && id == 'CD001') continue;
      if (bytes[0] != 0 || bytes[6] != 1) {
        _bad('Invalid volume recognition descriptor.');
      }
      if (id == 'BEA01' && !extended) {
        extended = true;
      } else if ((id == 'NSR02' || id == 'NSR03') && extended && !nsr) {
        nsr = true;
      } else if (id == 'TEA01' && extended && nsr) {
        return;
      } else if (id != 'BOOT2') {
        _bad('Incomplete or ambiguous UDF volume recognition sequence.');
      }
    }
    _bad('Volume recognition sequence limit exceeded.');
  }

  void _volumeExtent(int location, int length) {
    if (location < 16 ||
        length <= 0 ||
        length > 1024 * 1024 ||
        length % _blockBytes != 0 ||
        location * _blockBytes > source.length - length) {
      _bad('Volume descriptor extent is invalid or exceeds 1 MiB.');
    }
  }

  Future<ViewerArchive> open() async {
    if (source.length < 257 * _blockBytes || source.length > 9007199254740991) {
      _bad('The image length is outside the supported range.');
    }
    await _recognition();
    // This is a reader, not an anchor-reconstruction tool: never silently select
    // a backup anchor or reserve sequence after corruption of the main one.
    final anchor = await _read(256 * _blockBytes, _blockBytes);
    _tag(anchor, 2, 256, 512);
    final sequenceLength = _u32(anchor, 16);
    final sequenceLocation = _u32(anchor, 20);
    _volumeExtent(sequenceLocation, sequenceLength);
    Uint8List? primary, logical;
    final partitions = <int, _Partition>{};
    var terminated = false;
    for (var i = 0; i < sequenceLength ~/ _blockBytes; i++) {
      final location = sequenceLocation + i;
      final bytes = await _read(location * _blockBytes, _blockBytes);
      final id = _u16(bytes, 0);
      if (id == 3) _unsupported('Chained volume descriptor sequences.');
      var size = 512;
      if (id == 6) {
        final mapBytes = _u32(bytes, 264);
        if (mapBytes > _blockBytes - 440) {
          _unsupported('Oversized partition map table.');
        }
        size = 440 + mapBytes;
      } else if (id == 7) {
        final count = _u32(bytes, 20);
        if (count > (_blockBytes - 24) ~/ 8) {
          _unsupported('Oversized unallocated-space descriptor.');
        }
        size = 24 + count * 8;
      } else if (!const [1, 4, 5, 8].contains(id)) {
        _unsupported('Unknown volume descriptor $id.');
      }
      _tag(bytes, id, location, size);
      if (id == 8) {
        terminated = true;
        break;
      }
      if (id == 1) {
        if (primary != null) {
          _unsupported('Multiple primary volume descriptors.');
        }
        if (_u16(bytes, 56) != 1 || _u16(bytes, 58) != 1) {
          _unsupported('Multi-volume images.');
        }
        primary = bytes;
      } else if (id == 5) {
        final number = _u16(bytes, 22);
        if (partitions.containsKey(number) || partitions.length >= 32) {
          _unsupported('Repeated or too many physical partitions.');
        }
        if (_u16(bytes, 20) != 1 ||
            !const ['+NSR02', '+NSR03'].contains(_identifier(bytes, 25, 23))) {
          _unsupported('Unallocated or non-UDF physical partition.');
        }
        final start = _u32(bytes, 188);
        final blocks = _u32(bytes, 192);
        if (start < 16 ||
            blocks == 0 ||
            (start + blocks) * _blockBytes > source.length) {
          _bad('Partition leaves the image.');
        }
        partitions[number] = _Partition(start, blocks);
      } else if (id == 6) {
        if (logical != null) {
          _unsupported('Multiple logical volume descriptors.');
        }
        logical = bytes;
      }
    }
    if (!terminated || primary == null || logical == null) {
      _bad('Incomplete main volume descriptor sequence.');
    }
    if (_u32(logical, 212) != _blockBytes) {
      _unsupported('Only 2048-byte logical blocks are supported.');
    }
    _charset(logical, 20);
    _revision = _domain(logical, 216);
    final mapCount = _u32(logical, 268);
    final mapLength = _u32(logical, 264);
    if (mapCount < 1 || mapCount > 32) {
      _unsupported('Partition map count outside 1–32.');
    }
    var at = 440;
    final used = <int>{};
    for (var i = 0; i < mapCount; i++) {
      if (at > 440 + mapLength - 2) _bad('Truncated partition map.');
      if (logical[at] != 1) {
        _unsupported(
          'Virtual, sparable, metadata and other Type 2 partition maps.',
        );
      }
      if (logical[at + 1] != 6 || at + 6 > 440 + mapLength) {
        _bad('Invalid Type 1 partition map.');
      }
      if (_u16(logical, at + 2) != 1) {
        _unsupported('Partition map references another volume.');
      }
      final number = _u16(logical, at + 4);
      final partition = partitions[number];
      if (partition == null || !used.add(number)) {
        _bad('Missing or repeated mapped physical partition.');
      }
      _partitions.add(partition);
      at += 6;
    }
    if (logical.sublist(at, 440 + mapLength).any((byte) => byte != 0)) {
      _bad('Unexpected partition-map bytes.');
    }
    final sorted = [..._partitions]..sort((a, b) => a.start.compareTo(b.start));
    for (var i = 1; i < sorted.length; i++) {
      if (sorted[i - 1].start + sorted[i - 1].blocks > sorted[i].start) {
        _bad('Physical partitions overlap.');
      }
    }
    await _integrity(logical);
    final fileSetAddress = _longAddress(logical, 248);
    if (fileSetAddress.length < 512 ||
        fileSetAddress.length > 1024 * 1024 ||
        (fileSetAddress.length != 512 &&
            fileSetAddress.length % _blockBytes != 0)) {
      _unsupported('Oversized or unaligned file-set descriptor sequence.');
    }
    _physical(
      fileSetAddress.partition,
      fileSetAddress.block,
      fileSetAddress.length,
    );
    Uint8List? fileSet;
    for (
      var offset = 0;
      offset < fileSetAddress.length;
      offset += _blockBytes
    ) {
      final block = fileSetAddress.block + offset ~/ _blockBytes;
      final count = fileSetAddress.length - offset < _blockBytes
          ? fileSetAddress.length - offset
          : _blockBytes;
      final bytes = await _readAddress(
        _Address(fileSetAddress.partition, block, count),
        count,
      );
      final id = _u16(bytes, 0);
      if (id == 8) {
        _tag(bytes, 8, block, 512);
        break;
      }
      if (id != 256) _bad('Unknown descriptor in the file-set sequence.');
      if (fileSet != null) _unsupported('Multiple file sets.');
      _tag(bytes, 256, block, 512);
      fileSet = bytes;
    }
    if (fileSet == null) _bad('Missing file-set descriptor.');
    _charset(fileSet, 240);
    if (_domain(fileSet, 416) != _revision) {
      _bad('File-set and logical-volume UDF revisions disagree.');
    }
    if (_u32(fileSet, 448) != 0 || _u32(fileSet, 464) != 0) {
      _unsupported('Chained file sets or system streams.');
    }
    final rootAddress = _longAddress(fileSet, 400);
    final root = await _file(rootAddress);
    if (root.type != 4) _bad('The root ICB is not a directory.');
    await _directory(root, '', rootAddress, 0);
    return ViewerArchive.reader(
      formatName: 'udf',
      maxStreamingMemberBytes: maxMemberBytes,
      members: _members,
      notices: _notices.toList(growable: false),
      read: (member, requested) async {
        final requestedLimit = requested < maxMemberBytes
            ? requested
            : maxMemberBytes;
        final limit = requestedLimit < kArchiveReadLimit
            ? requestedLimit
            : kArchiveReadLimit;
        if (member.size > limit) {
          throw ArchiveViewException(
            'UDF entry exceeds the $limit-byte read limit.',
          );
        }
        return _contents(_files[member.index], metadata: false);
      },
      streamReader: (member, chunkSize) =>
          _stream(_files[member.index], chunkSize),
      close: source.close,
    );
  }

  Future<void> _integrity(Uint8List logical) async {
    final length = _u32(logical, 432);
    final location = _u32(logical, 436);
    _volumeExtent(location, length);
    Uint8List? last;
    for (var i = 0; i < length ~/ _blockBytes; i++) {
      final bytes = await _read((location + i) * _blockBytes, _blockBytes);
      final id = _u16(bytes, 0);
      if (id == 0) break; // unused capacity after the final recorded LVID
      if (id == 8) {
        _tag(bytes, 8, location + i, 512);
        break;
      }
      if (id != 9) _bad('Invalid logical volume integrity sequence.');
      final count = _u32(bytes, 72);
      final implementationLength = _u32(bytes, 76);
      if (count != _partitions.length ||
          implementationLength < 46 ||
          implementationLength > _blockBytes - 80 - count * 8) {
        _bad('Invalid integrity descriptor dimensions.');
      }
      _tag(bytes, 9, location + i, 80 + count * 8 + implementationLength);
      if (_u32(bytes, 32) != 0) _unsupported('Chained integrity sequences.');
      final minRead = _u16(bytes, 80 + count * 8 + 40);
      if (!const [0x102, 0x150, 0x200, 0x201].contains(minRead)) {
        _unsupported('Unsupported minimum UDF read revision.');
      }
      if (_u32(bytes, 28) > 1) _bad('Unknown integrity state.');
      last = bytes;
    }
    if (last == null) _bad('Missing logical volume integrity descriptor.');
    if (_u32(last, 28) == 0) {
      _notices.add(
        'The UDF volume is marked open. Its metadata may be inconsistent; no repair or replay is performed.',
      );
    }
  }

  _Address _longAddress(Uint8List bytes, int at) {
    final rawLength = _u32(bytes, at);
    if (rawLength ~/ 1073741824 != 0 || rawLength == 0) {
      _bad('Expected a recorded ICB extent.');
    }
    if (_u16(bytes, at + 10) != 0) {
      _bad('Recorded ICB extent flags must be zero.');
    }
    return _Address(_u16(bytes, at + 8), _u32(bytes, at + 4), rawLength);
  }

  int _physical(int partition, int block, int length) {
    if (partition < 0 || partition >= _partitions.length) {
      _bad('Unknown partition reference.');
    }
    final value = _partitions[partition];
    if (block < 0 ||
        block >= value.blocks ||
        length < 0 ||
        length > (value.blocks - block) * _blockBytes) {
      _bad('Allocation leaves its physical partition.');
    }
    return (value.start + block) * _blockBytes;
  }

  Future<Uint8List> _readAddress(_Address address, int length) =>
      _read(_physical(address.partition, address.block, length), length);

  Future<_File> _file(_Address address) async {
    if (address.length < 176 || address.length > _blockBytes) {
      _unsupported('ICBs must fit one logical block.');
    }
    final cached = _cache[address.key];
    if (cached != null) {
      if (cached.address.length != address.length) {
        _bad('Conflicting references to one ICB.');
      }
      return cached;
    }
    final bytes = await _readAddress(address, address.length);
    final id = _u16(bytes, 0);
    if (id != 261 && id != 266) {
      _unsupported('Indirect, terminal or unknown ICB entries.');
    }
    final extended = id == 266;
    if (extended && _revision < 0x200) {
      _unsupported('Extended file entries before UDF 2.00.');
    }
    final fixed = extended ? 216 : 176;
    if (bytes.length < fixed) _bad('Truncated file entry.');
    final eaLength = _u32(bytes, fixed - 8);
    final adLength = _u32(bytes, fixed - 4);
    if (eaLength > bytes.length - fixed ||
        adLength > bytes.length - fixed - eaLength) {
      _bad('File entry variable fields leave the ICB.');
    }
    _tag(bytes, id, address.block, fixed + eaLength + adLength);
    if (_u16(bytes, 20) != 4 || _u16(bytes, 24) != 1) {
      _unsupported('Only ICB strategy 4 is supported.');
    }
    if (_u32(bytes, 16) != 0 || _u16(bytes, 22) != 0 || bytes[26] != 0) {
      _bad('Invalid strategy-4 ICB parameters or reserved byte.');
    }
    final flags = _u16(bytes, 34);
    final type = bytes[27];
    if ((flags & 0xf800) != 0 ||
        !const [4, 5, 6, 7, 8, 9, 10, 12].contains(type)) {
      _unsupported('Transformed, versioned, stream or unknown file entry.');
    }
    if (bytes[50] != 0 || bytes[51] != 0 || _u32(bytes, 52) != 0) {
      _unsupported('Record-oriented files.');
    }
    final size = _size64(bytes, 56);
    if (extended && (_u32(bytes, 152) != 0 || _size64(bytes, 64) != size)) {
      _unsupported('Named streams.');
    }
    final adType = flags & 7;
    final dataAt = fixed + eaLength;
    final extents = <_Extent>[];
    Uint8List? embedded;
    if (adType == 3) {
      if (adLength != size) {
        _bad('Embedded contents do not match the information length.');
      }
      embedded = Uint8List.fromList(bytes.sublist(dataAt, dataAt + adLength));
    } else if (adType == 0 || adType == 1) {
      await _allocations(
        bytes.sublist(dataAt, dataAt + adLength),
        address.partition,
        adType,
        extents,
        <String>{},
        0,
      );
      var total = 0;
      for (var i = 0; i < extents.length; i++) {
        final extent = extents[i];
        if (i + 1 != extents.length && extent.length % _blockBytes != 0) {
          _bad('A nonfinal allocation is not block aligned.');
        }
        total += extent.length;
      }
      if (total < size ||
          total - size >= _blockBytes ||
          (size == 0 && total != 0)) {
        _bad('Allocation lengths disagree with the information length.');
      }
      if (total > size && extents.isNotEmpty) {
        final last = extents.removeLast();
        final keep = last.length - (total - size);
        if (keep <= 0) _bad('An allocation lies beyond the logical end.');
        extents.add(_Extent(last.partition, last.block, keep, last.recorded));
      }
    } else {
      _unsupported('Extended or unknown allocation descriptors.');
    }
    if (type == 4 && extents.any((extent) => !extent.recorded)) {
      _unsupported('Sparse directories.');
    }
    final file = _File(
      address,
      type,
      size,
      extents,
      embedded,
      _timestamp(bytes, extended ? 92 : 84),
      _mode(_u32(bytes, 44), flags, type),
    );
    _cache[address.key] = file;
    return file;
  }

  Future<void> _allocations(
    Uint8List bytes,
    int partition,
    int type,
    List<_Extent> extents,
    Set<String> seen,
    int depth,
  ) async {
    final width = type == 0 ? 8 : 16;
    if (bytes.length % width != 0) _bad('Partial allocation descriptor.');
    if (depth > 256) _bad('Allocation continuation depth exceeded.');
    for (var at = 0; at < bytes.length; at += width) {
      if (++_extentCount > maxExtents || extents.length >= 4096) {
        _bad('Allocation descriptor limit exceeded.');
      }
      final rawLength = _u32(bytes, at);
      final kind = rawLength ~/ 1073741824;
      final length = rawLength % 1073741824;
      final block = _u32(bytes, at + 4);
      final part = type == 0 ? partition : _u16(bytes, at + 8);
      if (type == 1) {
        final flags = _u16(bytes, at + 10);
        if (flags > 1 || (flags == 1 && kind != 1)) {
          _bad('Invalid long allocation reserved or erased flags.');
        }
      }
      if (length == 0) {
        if (kind != 0 || block != 0 || (type == 1 && part != 0)) {
          _bad('Invalid empty allocation.');
        }
        if (bytes.sublist(at).any((byte) => byte != 0)) {
          _bad('Nonempty data after an empty allocation.');
        }
        return;
      }
      if (kind == 3) {
        if (at + width != bytes.length || length < 24 || length > _blockBytes) {
          _bad('Invalid allocation continuation.');
        }
        final address = _Address(part, block, length);
        if (!seen.add(address.key)) _bad('Allocation continuation loop.');
        final continuation = await _readAddress(address, length);
        final adLength = _u32(continuation, 20);
        if (adLength > length - 24) {
          _bad('Allocation continuation length leaves its extent.');
        }
        _tag(continuation, 258, block, 24 + adLength, allocationExtent: true);
        await _allocations(
          continuation.sublist(24, 24 + adLength),
          part,
          type,
          extents,
          seen,
          depth + 1,
        );
      } else {
        if (kind == 2) {
          if (block != 0) {
            _bad('An unallocated sparse extent has a physical address.');
          }
          if (part >= _partitions.length) {
            _bad('Unknown sparse partition reference.');
          }
        } else {
          _physical(part, block, length);
        }
        extents.add(_Extent(part, block, length, kind == 0));
      }
    }
  }

  Future<Uint8List> _contents(_File file, {required bool metadata}) async {
    if (file.embedded != null) return Uint8List.fromList(file.embedded!);
    final bytes = Uint8List(file.size);
    var at = 0;
    for (final extent in file.extents) {
      if (extent.recorded) {
        bytes.setRange(
          at,
          at + extent.length,
          await _read(
            _physical(extent.partition, extent.block, extent.length),
            extent.length,
            metadata: metadata,
          ),
        );
      }
      at += extent.length;
    }
    return bytes;
  }

  Stream<List<int>> _stream(_File file, int requestedChunk) async* {
    if (file.size > maxMemberBytes) {
      throw ArchiveViewException(
        'UDF entry exceeds the $maxMemberBytes-byte read limit.',
      );
    }
    final chunk = requestedChunk < _readChunkBytes
        ? requestedChunk
        : _readChunkBytes;
    if (file.embedded != null) {
      for (var at = 0; at < file.size; at += chunk) {
        final end = at + chunk < file.size ? at + chunk : file.size;
        yield Uint8List.fromList(file.embedded!.sublist(at, end));
      }
      return;
    }
    for (final extent in file.extents) {
      for (var at = 0; at < extent.length; at += chunk) {
        final count = extent.length - at < chunk ? extent.length - at : chunk;
        yield extent.recorded
            ? await _read(
                _physical(extent.partition, extent.block, extent.length) + at,
                count,
                metadata: false,
              )
            : Uint8List(count);
      }
    }
  }

  int _directoryLocation(_File file, int offset) {
    if (file.embedded != null) return file.address.block;
    var remaining = offset;
    for (final extent in file.extents) {
      if (remaining < extent.length) {
        return extent.block + remaining ~/ _blockBytes;
      }
      remaining -= extent.length;
    }
    _bad('Directory descriptor leaves its allocations.');
  }

  Future<void> _directory(
    _File directory,
    String prefix,
    _Address parent,
    int depth,
  ) async {
    if (depth > maxDepth || !_directories.add(directory.address.key)) {
      _bad('Directory depth or cycle limit exceeded.');
    }
    if (directory.size > maxDirectoryBytes - _directoryBytes) {
      _bad('Directory byte limit exceeded.');
    }
    _directoryBytes += directory.size;
    final bytes = await _contents(directory, metadata: true);
    var at = 0;
    var parentSeen = false;
    final pending = <(_File, String)>[];
    while (at < bytes.length) {
      if (++_identifierCount % 256 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      if (bytes.length - at < 38) _bad('Truncated file identifier descriptor.');
      final nameLength = bytes[at + 19];
      final implementationLength = _u16(bytes, at + 36);
      final unpadded = 38 + implementationLength + nameLength;
      final length = (unpadded + 3) ~/ 4 * 4;
      if ((implementationLength != 0 && implementationLength < 32) ||
          implementationLength % 4 != 0 ||
          length > _blockBytes ||
          length > bytes.length - at) {
        _bad('Invalid file identifier dimensions.');
      }
      final descriptor = Uint8List.sublistView(bytes, at, at + length);
      _tag(descriptor, 257, _directoryLocation(directory, at), length);
      if (_u16(descriptor, 16) != 1 ||
          descriptor[18] & 0xe0 != 0 ||
          descriptor.sublist(unpadded).any((byte) => byte != 0)) {
        _bad('Invalid file identifier version, flags or padding.');
      }
      final flags = descriptor[18];
      if (flags & 0x10 != 0) _unsupported('Metadata stream identifiers.');
      if (flags & 8 != 0) {
        if (at != 0 || parentSeen || nameLength != 0 || flags & 6 != 2) {
          _bad('Invalid parent directory identifier.');
        }
        final address = _longAddress(descriptor, 20);
        if (address.key != parent.key) {
          _bad('Parent directory identifier points elsewhere.');
        }
        parentSeen = true;
      } else if (flags & 4 == 0) {
        if (!parentSeen) _bad('Directory lacks its initial parent identifier.');
        final name = _name(
          descriptor.sublist(38 + implementationLength, unpadded),
        );
        _nameBytes += name.length * 2;
        if (_nameBytes > 16 * 1024 * 1024) {
          _bad('Filename byte limit exceeded.');
        }
        final path = prefix.isEmpty ? name : '$prefix/$name';
        if (path.length > 4096) {
          _bad('Duplicate or oversized member path.');
        }
        final pathBytes = path.length * 2;
        if (pathBytes > maxRetainedPathBytes - _retainedPathBytes) {
          _bad('Retained full-path text limit exceeded.');
        }
        if (!_paths.add(path)) {
          _bad('Duplicate or oversized member path.');
        }
        _retainedPathBytes += pathBytes;
        if (_members.length >= maxEntries) _bad('Entry limit exceeded.');
        final file = await _file(_longAddress(descriptor, 20));
        if ((flags & 2 != 0) != (file.type == 4)) {
          _bad('Directory and ICB file types disagree.');
        }
        final special = file.type != 4 && file.type != 5;
        if (special) {
          _notices.add(
            'Symbolic links and special entries are listed but cannot be extracted as files.',
          );
        }
        _members.add(
          ViewerArchiveMember(
            name: path,
            size: file.type == 4 ? 0 : file.size,
            isFile: file.type != 4,
            isEncrypted: false,
            isSpecial: special,
            modified: file.modified,
            posixMode: file.mode,
            pathEscapedRoot: false,
            index: _members.length,
          ),
        );
        _files.add(file);
        if (file.type == 4) pending.add((file, path));
      }
      at += length;
    }
    if (!parentSeen) _bad('Empty directory lacks its parent identifier.');
    for (final (file, path) in pending) {
      await _directory(file, path, directory.address, depth + 1);
    }
  }

  String _name(Uint8List bytes) {
    if (bytes.length < 2 || !const [8, 16].contains(bytes[0])) {
      _unsupported('Unknown OSTA filename compression ID.');
    }
    final units = <int>[];
    if (bytes[0] == 8) {
      units.addAll(bytes.sublist(1));
    } else {
      if (bytes.length.isEven) _bad('Partial 16-bit filename code unit.');
      for (var at = 1; at < bytes.length; at += 2) {
        final unit = bytes[at] * 256 + bytes[at + 1];
        if (unit >= 0xd800 && unit <= 0xdfff) {
          _unsupported('Surrogate filename code units.');
        }
        units.add(unit);
      }
    }
    final name = String.fromCharCodes(units);
    if (name == '.' ||
        name == '..' ||
        units.any(
          (unit) =>
              unit == 0 ||
              unit == 47 ||
              unit == 92 ||
              unit == 0xfeff ||
              unit == 0xfffe ||
              unit == 0xffff,
        )) {
      _bad('Unsafe or invalid filename component.');
    }
    return name;
  }

  int? _mode(int permissions, int flags, int type) {
    if (permissions & ~0x7fff != 0) return null;
    final kinds = {
      4: 0x4000,
      5: 0x8000,
      6: 0x6000,
      7: 0x2000,
      9: 0x1000,
      10: 0xc000,
      12: 0xa000,
    };
    final kind = kinds[type];
    if (kind == null) return null;
    return kind |
        (permissions & 7) |
        ((permissions >> 5) & 7) << 3 |
        ((permissions >> 10) & 7) << 6 |
        (flags & 0x40 != 0 ? 0x800 : 0) |
        (flags & 0x80 != 0 ? 0x400 : 0) |
        (flags & 0x100 != 0 ? 0x200 : 0);
  }

  DateTime? _timestamp(Uint8List bytes, int at) {
    final typeAndZone = _u16(bytes, at);
    final type = typeAndZone >> 12;
    var zone = typeAndZone & 0xfff;
    if (zone >= 2048) zone -= 4096;
    if (type > 1 || zone < -1440 || zone > 1440) return null;
    final year = _u16(bytes, at + 2),
        month = bytes[at + 4],
        day = bytes[at + 5];
    final hour = bytes[at + 6], minute = bytes[at + 7], second = bytes[at + 8];
    if (year < 1 ||
        month < 1 ||
        month > 12 ||
        day < 1 ||
        day > 31 ||
        hour > 23 ||
        minute > 59 ||
        second > 59 ||
        bytes[at + 9] > 99 ||
        bytes[at + 10] > 99 ||
        bytes[at + 11] > 99) {
      return null;
    }
    final microseconds =
        bytes[at + 9] * 10000 + bytes[at + 10] * 100 + bytes[at + 11];
    final value = DateTime.utc(
      year,
      month,
      day,
      hour,
      minute,
      second,
      0,
      microseconds,
    );
    if (value.month != month || value.day != day) return null;
    return value.subtract(Duration(minutes: type == 0 ? 0 : zone));
  }
}

class _Partition {
  const _Partition(this.start, this.blocks);
  final int start, blocks;
}

class _Address {
  const _Address(this.partition, this.block, this.length);
  final int partition, block, length;
  String get key => '$partition:$block';
}

class _Extent {
  const _Extent(this.partition, this.block, this.length, this.recorded);
  final int partition, block, length;
  final bool recorded;
}

class _File {
  const _File(
    this.address,
    this.type,
    this.size,
    this.extents,
    this.embedded,
    this.modified,
    this.mode,
  );
  final _Address address;
  final int type, size;
  final List<_Extent> extents;
  final Uint8List? embedded;
  final DateTime? modified;
  final int? mode;
}
