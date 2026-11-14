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

  void _clustersFor(int count) {
    if (count > remainingClusters)
      _limit('Shared allocated-cluster traversal.');
    _clusters += count;
  }

  void _extent() {
    if (_extents >= maxExtents) _limit('Shared extent count.');
    _extents++;
  }
}

Never _bad(String message) => throw ArchiveViewException(
  'Invalid NTFS image: $message',
  code: ArchiveMessageCode.corrupt,
);
Never _unsupported(String message) => throw ArchiveViewException(
  'Unsupported NTFS image: $message',
  code: ArchiveMessageCode.unsupported,
);
Never _limit(String message) => throw ArchiveViewException(
  'NTFS image resource limit: $message',
  code: ArchiveMessageCode.archiveLimit,
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
      source,
      maxMemberBytes,
      maxEntries,
      maxDirectoryBytes,
      maxDepth,
      maxExtents,
      maxClusters,
      maxMetadataBytes,
      maxRetainedPathBytes,
      traversalBudget ?? ArchiveNtfsTraversalBudget(),
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
      /* Preserve the original failure, including provider identity. */
    }
    rethrow;
  }
}

int _u16(Uint8List b, int at) =>
    ByteData.sublistView(b).getUint16(at, Endian.little);
int _u32(Uint8List b, int at) =>
    ByteData.sublistView(b).getUint32(at, Endian.little);
int _u64(Uint8List b, int at, {int ceiling = _maxExact}) {
  final low = _u32(b, at), high = _u32(b, at + 4);
  if (high > ceiling ~/ 4294967296 ||
      (high == ceiling ~/ 4294967296 && low > ceiling % 4294967296)) {
    _unsupported('An integer exceeds the exact supported range.');
  }
  return high * 4294967296 + low;
}

bool _powerOfTwo(int n) => n > 0 && (n & (n - 1)) == 0;
bool _sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Decode without ever forming a possibly inexact 64-bit FILETIME tick value.
DateTime _fileTime(Uint8List bytes, int offset) {
  final low = _u32(bytes, offset), high = _u32(bytes, offset + 4);
  final millis =
      high ~/ 10000 * 4294967296 +
      (high % 10000 * 4294967296 + low) ~/ 10000 -
      11644473600000;
  return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
}

String _utf16(Uint8List bytes, int offset, int units) {
  if (offset < 0 ||
      units < 0 ||
      offset > bytes.length ||
      units > (bytes.length - offset) ~/ 2) {
    _bad('A UTF-16 name leaves its attribute.');
  }
  final result = <int>[];
  for (var i = 0; i < units; i++) {
    final value = _u16(bytes, offset + i * 2);
    if (value >= 0xd800 && value <= 0xdbff) {
      if (++i >= units) _bad('An unpaired UTF-16 high surrogate.');
      final next = _u16(bytes, offset + i * 2);
      if (next < 0xdc00 || next > 0xdfff) {
        _bad('An invalid UTF-16 surrogate pair.');
      }
      result.add(0x10000 + (value - 0xd800) * 1024 + next - 0xdc00);
    } else {
      if (value >= 0xdc00 && value <= 0xdfff) {
        _bad('An unpaired UTF-16 low surrogate.');
      }
      result.add(value);
    }
  }
  return String.fromCharCodes(result);
}

void _component(String name, {bool rootDot = false}) {
  if (name.isEmpty ||
      name == '..' ||
      (!rootDot && name == '.') ||
      name.contains('/') ||
      name.contains('\\') ||
      name.contains(':') ||
      name.runes.any((r) => r < 32 || r == 127)) {
    _unsupported('A filename cannot be represented as a safe archive path.');
  }
}

class _Reference {
  const _Reference(this.number, this.sequence);
  final int number, sequence;
  factory _Reference.read(Uint8List b, int at) =>
      _Reference(_u32(b, at) + _u16(b, at + 4) * 4294967296, _u16(b, at + 6));
  bool matches(_Record record) =>
      number == record.number && sequence == record.sequence;
  bool same(_Reference other) =>
      number == other.number && sequence == other.sequence;
}

class _FileName {
  const _FileName(this.parent, this.name, this.namespace, this.flags);
  final _Reference parent;
  final String name;
  final int namespace, flags;
  bool same(_FileName other) =>
      parent.same(other.parent) &&
      name == other.name &&
      namespace == other.namespace;
}

class _Run {
  const _Run(this.vcn, this.count, this.lcn);
  final int vcn, count;
  final int? lcn;
}

class _Data {
  _Data.resident(Uint8List value)
    : resident = Uint8List.fromList(value),
      size = value.length,
      initialized = value.length,
      allocated = value.length,
      runs = const [],
      sparse = false;
  _Data.mapped(
    this.size,
    this.initialized,
    this.allocated,
    List<_Run> mappings,
    this.sparse,
  ) : resident = null,
      runs = List<_Run>.unmodifiable(mappings);
  final Uint8List? resident;
  final int size, initialized, allocated;
  final List<_Run> runs;
  final bool sparse;
}

class _Attribute {
  const _Attribute(this.type, this.name, this.instance, this.value);
  final int type, instance;
  final String name;
  final _Data value;
}

class _Record {
  _Record(
    this.number,
    this.sequence,
    this.links,
    this.flags,
    this.attributes,
    this.names,
    this.modified,
    this.fileFlags,
  );
  final int number, sequence, links, flags, fileFlags;
  final List<_Attribute> attributes;
  final List<_FileName> names;
  final DateTime? modified;
  bool get directory => flags & 2 != 0;
  _Data? attribute(int type, [String name = '']) {
    for (final attr in attributes) {
      if (attr.type == type && attr.name == name) return attr.value;
    }
    return null;
  }
}

class _Claim {
  const _Claim(this.start, this.count, this.owner);
  final int start, count;
  final String owner;
}

class _IndexEntry {
  const _IndexEntry(this.reference, this.name);
  final _Reference reference;
  final _FileName name;
}

const _systemNames = <int, String>{
  0: r'$MFT',
  1: r'$MFTMirr',
  2: r'$LogFile',
  3: r'$Volume',
  4: r'$AttrDef',
  6: r'$Bitmap',
  7: r'$Boot',
  8: r'$BadClus',
  9: r'$Secure',
  10: r'$UpCase',
  11: r'$Extend',
};

class _NtfsReader {
  _NtfsReader(
    this.source,
    this.maxMemberBytes,
    this.maxEntries,
    this.maxDirectoryBytes,
    this.maxDepth,
    this.maxExtents,
    this.maxClusters,
    this.maxMetadataBytes,
    this.maxRetainedPathBytes,
    this.budget,
    this.isCancelled,
  ) : sourceLength = source.length;

  final koni.ByteSource source;
  final int sourceLength;
  final int maxMemberBytes, maxEntries, maxDirectoryBytes, maxDepth;
  final int maxExtents, maxClusters, maxMetadataBytes, maxRetainedPathBytes;
  final ArchiveNtfsTraversalBudget budget;
  final bool Function()? isCancelled;
  var _closed = false;
  var _metadataBytes = 0, _directoryBytes = 0, _pathBytes = 0;
  var _clustersVisited = 0, _extentsCreated = 0, _work = 0;
  var _namespaceEntries = 0;
  late int _sectorBytes, _clusterBytes, _recordBytes, _indexBytes;
  late int _volumeBytes, _clusters, _mftLcn, _mirrorLcn, _recordCount;
  late _Data _mft, _mftBitmap, _volumeBitmap;
  final _records = <int, _Record>{};
  final _claims = <_Claim>[];
  final _bitmapPages = <(_Data, int), Uint8List>{};
  final _directories = <int>{};
  final _systemRecords = <int>{};
  final _publicRecords = <int>{};
  final _publicLinks = <int, int>{};
  final _paths = <String>{};
  final _members = <ViewerArchiveMember>[];
  final _files = <_Data?>[];
  final _notices = <String>[
    'Read-only NTFS filesystem. The reachable namespace, metadata mappings '
        'and referenced allocations are checked. These checks do not '
        'authenticate file contents or establish consistency of unreferenced records.',
    'NTFS system records and the system metadata directory are omitted. '
        'Security descriptors, ownership, extended attributes and DOS aliases '
        'are not restored. Journal replay and filesystem repair are not performed.',
  ];

  void _cancel() {
    if (_closed || (isCancelled?.call() ?? false)) {
      throw const ArchiveNtfsCancelledException();
    }
    if (source.length != sourceLength) {
      _bad('The source length changed while reading the image.');
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
    bool boot = false,
  }) async {
    await _checkpoint();
    final bound = boot ? sourceLength : _volumeBytes;
    if (offset < 0 ||
        length < 0 ||
        length > _readBytes ||
        offset > bound ||
        length > bound - offset) {
      _bad('A read leaves the bounded volume.');
    }
    if (metadata) {
      if (length > maxMetadataBytes - _metadataBytes) {
        _limit('Metadata bytes read.');
      }
      _metadataBytes += length;
    }
    final bytes = await source.read(offset, length);
    _cancel();
    if (bytes.length != length) _bad('Truncated image read.');
    // Providers may lend the same backing storage on successive range reads.
    return Uint8List.fromList(bytes);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _records.clear();
    _claims.clear();
    _bitmapPages.clear();
    await source.close();
  }

  Future<ViewerArchive> open() async {
    if (sourceLength < 1024 || sourceLength > _maxExact) {
      _bad('The source cannot contain a supported NTFS volume.');
    }
    await _boot();
    final first = await _read(_mftLcn * _clusterBytes, _recordBytes);
    final record0 = await _parseRecord(first, 0);
    _records[0] = record0;
    _systemRecords.add(0);
    _mft = _required(record0, 0x80);
    if (_mft.resident != null ||
        _mft.sparse ||
        _mft.runs.isEmpty ||
        _mft.runs.first.lcn != _mftLcn ||
        _mft.initialized != _mft.size ||
        _mft.size < 16 * _recordBytes ||
        _mft.size % _recordBytes != 0) {
      _bad('The MFT bootstrap mapping or initialized length is invalid.');
    }
    _recordCount = _mft.size ~/ _recordBytes;
    _mftBitmap = _required(record0, 0xb0);
    _plainMetadata(_mftBitmap, 'MFT bitmap');
    if (_mftBitmap.size < (_recordCount + 7) ~/ 8 ||
        !await _bit(_mftBitmap, 0)) {
      _bad('The MFT allocation bitmap does not cover its records.');
    }
    final mappedFirst = await _dataRead(_mft, 0, _recordBytes);
    if (!_sameBytes(first, mappedFirst)) {
      _bad('The bootstrap MFT record disagrees with its own mapping.');
    }

    final volume = await _record(3);
    final information = _required(volume, 0x70);
    final info = information.resident;
    if (info == null || info.length != 12) {
      _bad('The volume information attribute is malformed.');
    }
    if (info[8] != 3 || (info[9] != 0 && info[9] != 1)) {
      _unsupported('Only NTFS 3.0 and 3.1 are admitted.');
    }
    if (_u16(info, 10) != 0) {
      _unsupported(
        'The volume is dirty or requires an excluded maintenance operation.',
      );
    }

    final bitmapRecord = await _record(6);
    _volumeBitmap = _required(bitmapRecord, 0x80);
    _plainMetadata(_volumeBitmap, 'volume allocation bitmap');
    if (_volumeBitmap.size < (_clusters + 7) ~/ 8) {
      _bad('The volume allocation bitmap is too short.');
    }
    // Reserved records include metadata not otherwise reached by a public file.
    for (var number = 0; number < 16; number++) {
      await _checkpoint();
      if (await _bit(_mftBitmap, number)) {
        await _record(number);
        if (number != 5) _systemRecords.add(number);
      } else if (_systemNames.containsKey(number) || number == 5) {
        _bad('A required system record is marked unallocated.');
      }
    }
    await _systemMappings();
    final root = await _record(5);
    if (!root.directory) _bad('The root record is not a directory.');
    await _walk(root, '', 0, system: false);
    for (final item in _publicLinks.entries) {
      if (item.value > _records[item.key]!.links) {
        _bad('Directory links exceed the record link count.');
      }
    }
    await _verifyClaims();
    _cancel();
    final files = List<_Data?>.unmodifiable(_files);
    _records.clear();
    _claims.clear();
    _bitmapPages.clear();
    _paths.clear();
    _directories.clear();
    _systemRecords.clear();
    _publicRecords.clear();
    _publicLinks.clear();
    return ViewerArchive.reader(
      formatName: 'ntfs',
      members: _members,
      notices: _notices,
      maxStreamingMemberBytes: maxMemberBytes,
      close: close,
      read: (member, allowance) async {
        _cancel();
        if (member.size > kArchiveReadLimit ||
            member.size > allowance ||
            member.size > maxMemberBytes) {
          _limit(
            'Buffered member reads are limited to 64 MiB and the caller allowance.',
          );
        }
        final bytes = Uint8List(member.size);
        var at = 0;
        await for (final part in _stream(files[member.index]!, _readBytes)) {
          bytes.setRange(at, at + part.length, part);
          at += part.length;
        }
        return bytes;
      },
      streamReader: (member, chunkSize) =>
          _stream(files[member.index]!, chunkSize),
    );
  }

  Future<void> _boot() async {
    final boot = await _read(0, 512, boot: true);
    if (!_sameBytes(
          Uint8List.fromList(boot.sublist(3, 11)),
          Uint8List.fromList(ascii.encode('NTFS    ')),
        ) ||
        boot[510] != 0x55 ||
        boot[511] != 0xaa ||
        (boot[0] != 0xeb && boot[0] != 0xe9)) {
      _bad('The boot sector signature is invalid.');
    }
    _sectorBytes = _u16(boot, 11);
    final sectorsPerCluster = boot[13];
    if (_sectorBytes < 512 ||
        _sectorBytes > 4096 ||
        !_powerOfTwo(_sectorBytes) ||
        !_powerOfTwo(sectorsPerCluster) ||
        sectorsPerCluster > 128) {
      _unsupported(
        'Only 512–4096-byte sectors and ordinary power-of-two cluster geometry are admitted.',
      );
    }
    _clusterBytes = _sectorBytes * sectorsPerCluster;
    if (_clusterBytes > 65536) _unsupported('Clusters larger than 64 KiB.');
    for (final index in [14, 15, 16, 17, 18, 19, 20, 22, 23, 32, 33, 34, 35]) {
      if (boot[index] != 0) _bad('Nonzero reserved NTFS boot geometry.');
    }
    final sectors = _u64(boot, 40, ceiling: _maxExact ~/ _sectorBytes - 1);
    // NTFS stores the sector count excluding its final backup boot sector.
    if (sectors < 16 || sectors + 1 > sourceLength ~/ _sectorBytes) {
      _bad('The declared NTFS volume leaves the source.');
    }
    _volumeBytes = (sectors + 1) * _sectorBytes;
    _clusters = sectors ~/ sectorsPerCluster;
    _mftLcn = _u64(boot, 48, ceiling: _clusters);
    _mirrorLcn = _u64(boot, 56, ceiling: _clusters);
    if (_mftLcn <= 0 ||
        _mftLcn >= _clusters ||
        _mirrorLcn <= 0 ||
        _mirrorLcn >= _clusters ||
        _mftLcn == _mirrorLcn) {
      _bad('Invalid MFT or mirror cluster.');
    }
    _recordBytes = _recordSize(boot[64]);
    _indexBytes = _recordSize(boot[68]);
    final backup = await _read(sectors * _sectorBytes, 512);
    if (!_sameBytes(boot, backup)) {
      _bad('The primary and backup boot sectors disagree.');
    }
  }

  int _recordSize(int encoding) {
    final signed = encoding >= 128 ? encoding - 256 : encoding;
    final int bytes;
    if (signed < 0) {
      if (signed < -16 || signed > -9) {
        _unsupported('Record sizes outside 512 bytes through 64 KiB.');
      }
      bytes = 1 << -signed;
    } else {
      if (signed == 0 ||
          !_powerOfTwo(signed) ||
          signed > 65536 ~/ _clusterBytes) {
        _unsupported('Invalid or oversized record-size encoding.');
      }
      bytes = signed * _clusterBytes;
    }
    if (bytes < 512 || bytes > 65536 || !_powerOfTwo(bytes)) {
      _unsupported('Record sizes outside 512 bytes through 64 KiB.');
    }
    return bytes;
  }

  Uint8List _fixup(Uint8List raw, String signature, int headerMinimum) {
    if (raw.length < 512 ||
        raw.length % 512 != 0 ||
        raw[0] != signature.codeUnitAt(0) ||
        raw[1] != signature.codeUnitAt(1) ||
        raw[2] != signature.codeUnitAt(2) ||
        raw[3] != signature.codeUnitAt(3)) {
      _bad('Invalid $signature multisector record.');
    }
    final offset = _u16(raw, 4), count = _u16(raw, 6);
    if (offset < headerMinimum ||
        offset % 2 != 0 ||
        count != raw.length ~/ 512 + 1 ||
        offset > 510 - count * 2) {
      _bad('Invalid $signature update-sequence array bounds.');
    }
    final fixed = Uint8List.fromList(raw), sequence = _u16(raw, offset);
    if (sequence == 0) _bad('Zero $signature update-sequence number.');
    for (var index = 1; index < count; index++) {
      final tail = index * 512 - 2;
      if (_u16(raw, tail) != sequence) {
        _bad('A $signature update-sequence fixup does not match.');
      }
      fixed[tail] = raw[offset + index * 2];
      fixed[tail + 1] = raw[offset + index * 2 + 1];
    }
    return fixed;
  }

  Future<_Record> _record(int number, [_Reference? reference]) async {
    await _checkpoint();
    if (number < 0 || number >= _recordCount) {
      _bad('A file reference leaves the MFT.');
    }
    var record = _records[number];
    if (record == null) {
      if (_records.length >= _maxEntries + 32) _limit('File-record count.');
      if (!await _bit(_mftBitmap, number)) {
        _bad('A referenced file record is marked unallocated.');
      }
      record = await _parseRecord(
        await _dataRead(_mft, number * _recordBytes, _recordBytes),
        number,
      );
      _records[number] = record;
    }
    if (reference != null && !reference.matches(record)) {
      _bad('A file reference has a stale sequence number.');
    }
    return record;
  }

  Future<_Record> _parseRecord(Uint8List raw, int number) async {
    final b = _fixup(raw, 'FILE', 42);
    final sequence = _u16(b, 16), links = _u16(b, 18);
    final first = _u16(b, 20), flags = _u16(b, 22);
    final used = _u32(b, 24), allocated = _u32(b, 28);
    if (sequence == 0 ||
        flags & 1 == 0 ||
        allocated != _recordBytes ||
        used > allocated ||
        first < 48 ||
        first % 8 != 0 ||
        first < _u16(b, 4) + _u16(b, 6) * 2 ||
        first > used - 8) {
      _bad('Invalid allocated FILE record header.');
    }
    if (flags & ~0xf != 0) {
      _unsupported('Unknown FILE record flags.');
    }
    if (_u32(b, 32) != 0 || _u32(b, 36) != 0) {
      _unsupported('Extension FILE records and attribute lists are excluded.');
    }
    if (_u16(b, 4) >= 48 && _u32(b, 44) != number) {
      _bad('The FILE record number disagrees with its MFT position.');
    }
    final attributes = <_Attribute>[];
    final names = <_FileName>[];
    final instances = <int>{}, keys = <(int, String)>{};
    DateTime? modified;
    var fileFlags = 0, cursor = first, previousType = 0, terminated = false;
    while (cursor <= used - 4) {
      await _checkpoint();
      final type = _u32(b, cursor);
      if (type == 0xffffffff) {
        terminated = true;
        break;
      }
      if (cursor > used - 24) _bad('Truncated attribute record.');
      final length = _u32(b, cursor + 4);
      if (length < 24 ||
          length % 8 != 0 ||
          length > used - cursor ||
          type < previousType ||
          type < 0x10 ||
          type > 0x100 ||
          type % 16 != 0) {
        _bad('Invalid attribute ordering, type, or record length.');
      }
      previousType = type;
      if (type == 0x20) {
        _unsupported('Attribute lists and extension records are excluded.');
      }
      if (type == 0xc0 || type == 0xf0 || type == 0x100) {
        _unsupported(
          'Reparse points, property sets, and logged utility streams are excluded.',
        );
      }
      final form = b[cursor + 8], nameUnits = b[cursor + 9];
      final nameAt = _u16(b, cursor + 10), attrFlags = _u16(b, cursor + 12);
      final instance = _u16(b, cursor + 14);
      if (form > 1 || !instances.add(instance)) {
        _bad('Invalid attribute form or duplicate instance.');
      }
      if (attrFlags & ~0x8000 != 0) {
        _unsupported('Compressed, encrypted, or unknown attribute flags.');
      }
      final minimum = form == 0 ? 24 : (attrFlags & 0x8000 != 0 ? 72 : 64);
      if (length < minimum ||
          (nameUnits > 0 &&
              (nameAt < minimum ||
                  nameAt % 2 != 0 ||
                  nameAt > length ||
                  nameUnits * 2 > length - nameAt))) {
        _bad('An attribute name or header leaves its record.');
      }
      final name = nameUnits == 0 ? '' : _utf16(b, cursor + nameAt, nameUnits);
      if (name.contains('\u0000')) _bad('An attribute name contains a NUL.');
      if (type != 0x30 && !keys.add((type, name))) {
        _unsupported(
          'Multiple records for the same attribute require an excluded layout.',
        );
      }
      final _Data value;
      if (form == 0) {
        if (attrFlags != 0) _bad('A resident attribute has nonresident flags.');
        final size = _u32(b, cursor + 16), offset = _u16(b, cursor + 20);
        if (offset < minimum ||
            offset > length ||
            size > length - offset ||
            (nameUnits > 0 && offset < nameAt + nameUnits * 2)) {
          _bad('A resident value overlaps its header or leaves its attribute.');
        }
        value = _Data.resident(
          Uint8List.sublistView(b, cursor + offset, cursor + offset + size),
        );
      } else {
        value = await _mapping(
          b,
          cursor,
          length,
          minimum,
          nameAt,
          nameUnits,
          attrFlags,
          number,
          type,
          name,
        );
      }
      attributes.add(_Attribute(type, name, instance, value));
      if (type == 0x10) {
        final resident = value.resident;
        if (name.isNotEmpty ||
            resident == null ||
            (resident.length != 48 && resident.length != 72)) {
          _bad('Malformed standard information.');
        }
        modified = _fileTime(resident, 8);
        fileFlags = _u32(resident, 32);
        if (fileFlags & (0x400 | 0x800 | 0x4000) != 0) {
          _unsupported('Reparse, compressed, or encrypted files are excluded.');
        }
      } else if (type == 0x30) {
        if (name.isNotEmpty || value.resident == null) {
          _bad('A filename is named or nonresident.');
        }
        final fileName = _filename(value.resident!, rootDot: number == 5);
        if (names.any(fileName.same)) _bad('Duplicate filename attributes.');
        names.add(fileName);
      } else if ((type == 0x40 ||
              type == 0x60 ||
              type == 0x70 ||
              type == 0x90 ||
              type == 0xd0) &&
          value.resident == null) {
        _unsupported('A normally resident metadata attribute is nonresident.');
      }
      cursor += length;
    }
    if (!terminated) _bad('Missing attribute terminator.');
    if (number < 12 || number >= 16) {
      if (modified == null || links == 0 || names.isEmpty) {
        _bad('FILE record $number lacks standard information, a name, or links.');
      }
    }
    return _Record(
      number,
      sequence,
      links,
      flags,
      List<_Attribute>.unmodifiable(attributes),
      List<_FileName>.unmodifiable(names),
      modified,
      fileFlags,
    );
  }

  Future<_Data> _mapping(
    Uint8List b,
    int at,
    int length,
    int minimum,
    int nameAt,
    int nameUnits,
    int flags,
    int recordNumber,
    int type,
    String name,
  ) async {
    if (_u64(b, at + 16) != 0) {
      _unsupported('Attribute extents outside the base record are excluded.');
    }
    final emptyHighest =
        _u32(b, at + 24) == 0xffffffff && _u32(b, at + 28) == 0xffffffff;
    final highest = emptyHighest
        ? -1
        : _u64(b, at + 24, ceiling: _maxExact ~/ _clusterBytes - 1);
    final runOffset = _u16(b, at + 32), compressionUnit = _u16(b, at + 34);
    final allocated = _u64(b, at + 40), size = _u64(b, at + 48);
    final initialized = _u64(b, at + 56);
    final sparse = flags & 0x8000 != 0;
    final badClusters = recordNumber == 8 && type == 0x80 && name == r'$Bad';
    if (runOffset < minimum ||
        runOffset >= length ||
        (nameUnits > 0 && runOffset < nameAt + nameUnits * 2) ||
        initialized > size ||
        size > allocated ||
        allocated % _clusterBytes != 0 ||
        allocated ~/ _clusterBytes != highest + 1) {
      _bad('Invalid nonresident lengths, extent bounds, or mapping offset.');
    }
    if ((!sparse && compressionUnit != 0) ||
        (sparse && compressionUnit != 0 && compressionUnit != 4)) {
      _unsupported('An excluded compression-unit layout.');
    }
    if (sparse && type != 0x80) {
      _unsupported('Sparse non-DATA attributes are excluded.');
    }
    final runs = <_Run>[];
    var cursor = at + runOffset, vcn = 0, previousLcn = 0;
    var physical = 0, terminated = false;
    while (cursor < at + length) {
      await _checkpoint();
      final header = b[cursor++];
      if (header == 0) {
        terminated = true;
        break;
      }
      final countBytes = header & 15, offsetBytes = header >> 4;
      if (countBytes == 0 ||
          countBytes > 8 ||
          offsetBytes > 8 ||
          countBytes + offsetBytes > at + length - cursor) {
        _bad('Malformed mapping-pair widths.');
      }
      final count = _varint(
        b,
        cursor,
        countBytes,
        signed: false,
        ceiling: highest + 1 - vcn,
      );
      cursor += countBytes;
      if (count <= 0 || count > highest + 1 - vcn) {
        _bad(
          'A mapping pair has zero length or leaves its virtual allocation.',
        );
      }
      int? lcn;
      if (offsetBytes == 0) {
        if (!sparse && !badClusters) {
          _bad('An unflagged DATA or metadata stream contains a sparse run.');
        }
      } else {
        final delta = _varint(
          b,
          cursor,
          offsetBytes,
          signed: true,
          ceiling: _clusters,
        );
        lcn = previousLcn + delta;
        if (lcn < 0 || lcn >= _clusters || count > _clusters - lcn) {
          _bad('A physical run leaves the volume.');
        }
        if (badClusters) {
          _unsupported('Volumes with recorded bad clusters are excluded.');
        }
        if (lcn == 0 && !(recordNumber == 7 && type == 0x80 && name.isEmpty)) {
          _bad('An allocation aliases the boot cluster.');
        }
        previousLcn = lcn;
        physical += count;
        _claim(lcn, count, '$recordNumber:$type:$name');
      }
      cursor += offsetBytes;
      _extent();
      runs.add(_Run(vcn, count, lcn));
      vcn += count;
    }
    if (!terminated || vcn != highest + 1) {
      _bad(
        'A runlist is unterminated or does not cover its declared VCN range.',
      );
    }
    if (sparse && _u64(b, at + 64) != physical * _clusterBytes) {
      _bad('Sparse physical allocation does not match its mapped runs.');
    }
    if (badClusters &&
        (initialized != 0 || size != _clusters * _clusterBytes)) {
      _unsupported('An unexpected system bad-cluster stream layout.');
    }
    return _Data.mapped(size, initialized, allocated, runs, sparse);
  }

  int _varint(
    Uint8List b,
    int at,
    int width, {
    required bool signed,
    required int ceiling,
  }) {
    final negative = signed && b[at + width - 1] & 0x80 != 0;
    var value = 0;
    for (var i = width - 1; i >= 0; i--) {
      final digit = negative ? 255 - b[at + i] : b[at + i];
      if (value > (ceiling - digit) ~/ 256 || ceiling < digit) {
        _bad('A mapping-pair integer exceeds its bounded range.');
      }
      value = value * 256 + digit;
    }
    if (negative) {
      if (value >= ceiling) {
        _bad('A negative mapping-pair offset exceeds its range.');
      }
      return -value - 1;
    }
    return value;
  }

  void _extent() {
    if (_extentsCreated >= maxExtents) _limit('Extent count.');
    budget._extent();
    _extentsCreated++;
  }

  void _claim(int start, int count, String owner) {
    if (count > maxClusters - _clustersVisited ||
        count > budget.remainingClusters) {
      _limit('Allocated-cluster traversal.');
    }
    _clustersVisited += count;
    budget._clustersFor(count);
    _claims.add(_Claim(start, count, owner));
  }

  _Data _required(_Record record, int type, [String name = '']) {
    final value = record.attribute(type, name);
    if (value == null) {
      _bad('A required system or directory attribute is missing.');
    }
    return value;
  }

  void _plainMetadata(_Data value, String label) {
    if (value.sparse ||
        value.initialized != value.size ||
        value.runs.any((run) => run.lcn == null)) {
      _unsupported('Sparse or uninitialized $label.');
    }
  }

  _FileName _filename(Uint8List b, {bool rootDot = false}) {
    if (b.length < 66 ||
        b[64] == 0 ||
        b[65] > 3 ||
        b.length != 66 + b[64] * 2) {
      _bad('Malformed filename value.');
    }
    final parent = _Reference.read(b, 0);
    if (parent.sequence == 0) _bad('A filename has a zero parent sequence.');
    final name = _utf16(b, 66, b[64]);
    _component(name, rootDot: rootDot);
    final flags = _u32(b, 56);
    if (flags & (0x400 | 0x800 | 0x4000) != 0) {
      _unsupported('Reparse, compressed, or encrypted filename metadata.');
    }
    return _FileName(parent, name, b[65], flags);
  }

  Future<Uint8List> _dataRead(
    _Data data,
    int offset,
    int length, {
    bool metadata = true,
  }) async {
    await _checkpoint();
    if (offset < 0 ||
        length < 0 ||
        length > _readBytes ||
        offset > data.size ||
        length > data.size - offset) {
      _bad('A stream read leaves its declared size.');
    }
    final resident = data.resident;
    if (resident != null) {
      return Uint8List.fromList(resident.sublist(offset, offset + length));
    }
    final result = Uint8List(length);
    var copied = 0;
    while (copied < length) {
      await _checkpoint();
      final position = offset + copied;
      if (position >= data.initialized) break;
      final vcn = position ~/ _clusterBytes;
      var lo = 0, hi = data.runs.length;
      while (lo < hi) {
        final mid = (lo + hi) ~/ 2;
        if (data.runs[mid].vcn <= vcn) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      if (lo == 0) _bad('An initialized byte is unmapped.');
      final run = data.runs[lo - 1];
      final runEnd = (run.vcn + run.count) * _clusterBytes;
      if (position >= runEnd) {
        _bad('An initialized byte falls between extents.');
      }
      var amount = length - copied;
      if (amount > runEnd - position) amount = runEnd - position;
      if (amount > data.initialized - position) {
        amount = data.initialized - position;
      }
      final lcn = run.lcn;
      if (lcn != null) {
        final bytes = await _read(
          lcn * _clusterBytes + position - run.vcn * _clusterBytes,
          amount,
          metadata: metadata,
        );
        result.setRange(copied, copied + amount, bytes);
      }
      copied += amount;
    }
    return result;
  }

  Stream<Uint8List> _stream(_Data data, int chunkSize) async* {
    final chunk = chunkSize > _readBytes ? _readBytes : chunkSize;
    for (var at = 0; at < data.size;) {
      _cancel();
      final length = data.size - at < chunk ? data.size - at : chunk;
      yield await _dataRead(data, at, length, metadata: false);
      at += length;
    }
    _cancel();
  }

  Future<bool> _bit(_Data bitmap, int bit) async {
    if (bit < 0 || bit ~/ 8 >= bitmap.size) {
      _bad('An allocation bit leaves its bitmap.');
    }
    final byte = bit ~/ 8, page = byte ~/ 4096;
    final key = (bitmap, page);
    var bytes = _bitmapPages[key];
    if (bytes == null) {
      final at = page * 4096;
      bytes = await _dataRead(
        bitmap,
        at,
        bitmap.size - at < 4096 ? bitmap.size - at : 4096,
      );
      if (_bitmapPages.length >= 128) {
        _bitmapPages.remove(_bitmapPages.keys.first);
      }
      _bitmapPages[key] = bytes;
    }
    return bytes[byte % 4096] & (1 << (bit % 8)) != 0;
  }

  Future<void> _systemMappings() async {
    final boot = _required(_records[7]!, 0x80);
    _plainMetadata(boot, 'boot stream');
    if (boot.resident != null ||
        boot.runs.isEmpty ||
        boot.runs.first.lcn != 0 ||
        boot.size < _sectorBytes) {
      _bad('The system boot stream does not own the boot cluster.');
    }
    final mirror = _required(_records[1]!, 0x80);
    _plainMetadata(mirror, 'MFT mirror');
    final count = _clusterBytes > 4 * _recordBytes
        ? _clusterBytes ~/ _recordBytes
        : 4;
    if (mirror.resident != null ||
        mirror.runs.isEmpty ||
        mirror.runs.first.lcn != _mirrorLcn ||
        mirror.size != count * _recordBytes) {
      _bad('The MFT mirror mapping is inconsistent with boot geometry.');
    }
    for (var number = 0; number < count; number++) {
      final first = _fixup(
        await _dataRead(_mft, number * _recordBytes, _recordBytes),
        'FILE',
        42,
      );
      final second = _fixup(
        await _dataRead(mirror, number * _recordBytes, _recordBytes),
        'FILE',
        42,
      );
      // USA counters need not agree after independent successful writes.
      for (final record in [first, second]) {
        final at = _u16(record, 4), length = _u16(record, 6) * 2;
        record.fillRange(at, at + length, 0);
      }
      if (!_sameBytes(first, second)) {
        _bad('The MFT mirror disagrees with the primary records.');
      }
    }
  }

  void _directoryCharge(int length) {
    if (length > maxDirectoryBytes - _directoryBytes) {
      _limit('Directory index bytes.');
    }
    _directoryBytes += length;
  }

  Future<List<_IndexEntry>> _index(_Record directory) async {
    final root = _required(directory, 0x90, r'$I30').resident;
    if (root == null ||
        root.length < 32 ||
        _u32(root, 0) != 0x30 ||
        _u32(root, 4) != 1 ||
        _u32(root, 8) != _indexBytes) {
      _unsupported(
        r'Only ordinary filename-collated $I30 directory indexes are admitted.',
      );
    }
    final vcnUnit = _clusterBytes <= _indexBytes ? _clusterBytes : _sectorBytes;
    if (root[12] != _indexBytes ~/ vcnUnit) {
      _bad('The directory index geometry disagrees with its boot sector.');
    }
    final allocation = directory.attribute(0xa0, r'$I30');
    final bitmap = directory.attribute(0xb0, r'$I30');
    if ((allocation == null) != (bitmap == null)) {
      _bad('Directory index allocation and bitmap are not paired.');
    }
    var blocks = 0;
    if (allocation != null) {
      _plainMetadata(allocation, 'directory index allocation');
      _plainMetadata(bitmap!, 'directory index bitmap');
      if (allocation.resident != null ||
          allocation.size % _indexBytes != 0 ||
          allocation.size > maxDirectoryBytes ||
          bitmap.size > maxDirectoryBytes) {
        _bad('Invalid directory allocation size or storage form.');
      }
      blocks = allocation.size ~/ _indexBytes;
      if (bitmap.size < (blocks + 7) ~/ 8) {
        _bad('Directory bitmap is too short.');
      }
    }
    final seen = <int>{};
    final result = <_IndexEntry>[];
    final names = <String>{};
    Future<void> node(
      Uint8List bytes,
      int header,
      int minimumEntry,
      int treeDepth,
    ) async {
      await _checkpoint();
      if (treeDepth > 64) _limit('Directory index tree depth.');
      _directoryCharge(bytes.length);
      final entriesOffset = _u32(bytes, header);
      final used = _u32(bytes, header + 4), allocated = _u32(bytes, header + 8);
      final flags = bytes[header + 12];
      if (flags > 1 ||
          entriesOffset < minimumEntry ||
          entriesOffset % 8 != 0 ||
          allocated > bytes.length - header ||
          used > allocated ||
          used % 8 != 0 ||
          entriesOffset > used - 16) {
        _bad('Malformed directory index header.');
      }
      var cursor = header + entriesOffset;
      final end = header + used;
      var terminated = false;
      while (cursor < end) {
        await _checkpoint();
        if (cursor > end - 16) _bad('Truncated directory index entry.');
        final length = _u16(bytes, cursor + 8),
            keyLength = _u16(bytes, cursor + 10);
        final entryFlags = _u16(bytes, cursor + 12);
        final child = entryFlags & 1 != 0, last = entryFlags & 2 != 0;
        if (entryFlags & ~3 != 0 ||
            child != (flags == 1) ||
            length < 16 + (child ? 8 : 0) ||
            length % 8 != 0 ||
            length > end - cursor ||
            keyLength > length - 16 - (child ? 8 : 0)) {
          _bad('Malformed directory index entry bounds or child flags.');
        }
        if (child) {
          if (allocation == null || bitmap == null) {
            _bad('A directory child has no index allocation.');
          }
          final vcn = _u64(
            bytes,
            cursor + length - 8,
            ceiling: _maxExact ~/ vcnUnit,
          );
          final offset = vcn * vcnUnit;
          if (offset % _indexBytes != 0 ||
              offset >= allocation.size ||
              _indexBytes > allocation.size - offset) {
            _bad('An index child leaves its allocation or is misaligned.');
          }
          final block = offset ~/ _indexBytes;
          if (!seen.add(block)) {
            _bad('A directory index repeats or cycles a child.');
          }
          if (!await _bit(bitmap, block)) {
            _bad('An index child is marked unallocated.');
          }
          final childBytes = _fixup(
            await _dataRead(allocation, offset, _indexBytes),
            'INDX',
            40,
          );
          if (_u64(childBytes, 16) != vcn) {
            _bad('An INDX VCN disagrees with its parent.');
          }
          await node(
            childBytes,
            24,
            _u16(childBytes, 4) + _u16(childBytes, 6) * 2 - 24,
            treeDepth + 1,
          );
        }
        if (last) {
          if (keyLength != 0 || cursor + length != end) {
            _bad('The final index entry has a key or is not final.');
          }
          terminated = true;
        } else {
          if (++_namespaceEntries > _maxEntries * 2 + 64) {
            _limit('Directory filename entries.');
          }
          final name = _filename(
            Uint8List.sublistView(bytes, cursor + 16, cursor + 16 + keyLength),
            rootDot: directory.number == 5,
          );
          if (!name.parent.matches(directory) || !names.add(name.name)) {
            _bad('A directory key has a wrong parent or duplicate filename.');
          }
          result.add(_IndexEntry(_Reference.read(bytes, cursor), name));
        }
        cursor += length;
      }
      if (!terminated) _bad('A directory index has no final entry.');
    }

    await node(root, 16, 16, 0);
    if (bitmap != null) {
      // Padding bits cannot point outside the allocation; every live block
      // must have been reached exactly once by the rooted index tree.
      if (bitmap.size > (maxDirectoryBytes ~/ _indexBytes + 7) ~/ 8 + 8) {
        _limit('Directory bitmap bytes.');
      }
      for (var bit = 0; bit < bitmap.size * 8; bit++) {
        await _checkpoint();
        if (await _bit(bitmap, bit) && (bit >= blocks || !seen.contains(bit))) {
          _bad(
            'An allocated index block is outside the rooted directory tree.',
          );
        }
      }
    }
    return result;
  }

  Future<void> _walk(
    _Record directory,
    String path,
    int depth, {
    required bool system,
  }) async {
    await _checkpoint();
    if (depth > maxDepth) _limit('Directory depth.');
    if (!_directories.add(directory.number)) {
      _bad('A directory is repeated or forms a cycle.');
    }
    final entries = await _index(directory);
    final primaryNames = <(int, String)>{};
    for (final entry in entries) {
      if (entry.name.namespace != 2) {
        primaryNames.add((entry.reference.number, entry.name.name));
      }
    }
    for (final entry in entries) {
      await _checkpoint();
      final child = await _record(entry.reference.number, entry.reference);
      if (!child.names.any(entry.name.same)) {
        _bad('A directory name is absent from its referenced FILE record.');
      }
      if ((entry.name.flags & 0x10000000 != 0) != child.directory) {
        _bad('Directory-key and FILE-record kinds disagree.');
      }
      if (entry.name.name == '.') {
        if (directory.number != 5 || child.number != 5) {
          _bad('An invalid root self-reference.');
        }
        continue;
      }
      if (entry.name.namespace == 2) {
        if (!child.names.any(
          (name) =>
              name.namespace != 2 &&
              name.parent.matches(directory) &&
              primaryNames.contains((child.number, name.name)),
        )) {
          _unsupported('A DOS-only alias lacks its primary indexed filename.');
        }
        continue;
      }
      var childSystem = system;
      if (child.number < 16) {
        if (directory.number != 5 ||
            _systemNames[child.number] != entry.name.name) {
          _bad('A system record has an unexpected public namespace link.');
        }
        childSystem = true;
      }
      final childPath = path.isEmpty
          ? entry.name.name
          : '$path/${entry.name.name}';
      if (childSystem) {
        if (_publicRecords.contains(child.number)) {
          _bad('A record is shared between public files and system metadata.');
        }
        _systemRecords.add(child.number);
      } else {
        if (_systemRecords.contains(child.number) || child.flags & ~3 != 0) {
          _unsupported(
            'System view-index records cannot be ordinary archive files.',
          );
        }
        _publicRecords.add(child.number);
        _publicLinks.update(
          child.number,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
        _addMember(child, childPath);
      }
      if (child.directory) {
        await _walk(child, childPath, depth + 1, system: childSystem);
      }
    }
  }

  void _retain(String value) {
    final bytes = utf8.encode(value).length;
    if (bytes > maxRetainedPathBytes - _pathBytes) {
      _limit('Retained paths and stream notices.');
    }
    _pathBytes += bytes;
  }

  void _addMember(_Record record, String path) {
    if (_members.length >= maxEntries) _limit('Member entries.');
    if (!_paths.add(path)) _bad('A duplicate archive path.');
    _retain(path);
    final data = record.directory ? null : _required(record, 0x80);
    if (data != null && data.size > maxMemberBytes) {
      _limit('A regular file exceeds the caller member-size allowance.');
    }
    final index = _members.length;
    _members.add(
      ViewerArchiveMember(
        name: path,
        size: data?.size ?? 0,
        isFile: !record.directory,
        isEncrypted: false,
        modified: record.modified,
        pathEscapedRoot: false,
        index: index,
      ),
    );
    _files.add(data);
    for (final attribute in record.attributes) {
      if (attribute.type != 0x80 ||
          (attribute.name.isEmpty && !record.directory)) {
        continue;
      }
      final notice =
          'Alternate DATA stream ${jsonEncode(attribute.name)} on '
          '${jsonEncode(path)} (${attribute.value.size} bytes) is metadata only; '
          'it was not read, tested, or extracted.';
      _retain(notice);
      _notices.add(notice);
    }
  }

  Future<void> _verifyClaims() async {
    _claims.sort((a, b) => a.start.compareTo(b.start));
    _Claim? previous;
    for (final claim in _claims) {
      await _checkpoint();
      if (previous != null && claim.start < previous.start + previous.count) {
        _bad(
          'Cross-linked physical allocations (${previous.owner} and ${claim.owner}).',
        );
      }
      previous = claim;
      for (
        var cluster = claim.start;
        cluster < claim.start + claim.count;
        cluster++
      ) {
        await _checkpoint();
        if (!await _bit(_volumeBitmap, cluster)) {
          _bad('A referenced physical cluster is marked unallocated.');
        }
      }
    }
  }
}
