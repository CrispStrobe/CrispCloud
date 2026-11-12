import 'dart:typed_data';

import 'package:koni_archive/koni_archive.dart' as koni;

import 'archive_types.dart';

/// Reads an HFS+ or HFSX volume without mounting it or following links.
///
/// Catalog leaf nodes are read lazily from their inline extents; ordinary file
/// data forks are read only when requested. Extents overflow, compressed files,
/// hard links, journal replay, and resource-fork extraction are not implemented.
/// Layouts follow Apple's TN1150:
/// https://developer.apple.com/library/archive/technotes/tn/tn1150.html
///
/// The returned handle owns [source]. A failed open also closes it.
Future<ViewerArchive> openHfsArchive(
  koni.ByteSource source, {
  required int maxMemberBytes,
  int maxEntries = 100000,
  int maxCatalogBytes = 32 * 1024 * 1024,
  int maxDepth = 64,
}) async {
  try {
    if (maxMemberBytes <= 0 ||
        maxEntries <= 0 ||
        maxCatalogBytes <= 0 ||
        maxDepth <= 0) {
      throw ArgumentError('HFS reader limits must be positive.');
    }
    return await _HfsReader(
      source,
      maxMemberBytes,
      maxEntries,
      maxCatalogBytes,
      maxDepth,
    ).open();
  } catch (error) {
    await source.close();
    if (error is ArchiveViewException || error is ArgumentError) rethrow;
    throw ArchiveViewException('Could not read the HFS volume: $error');
  }
}

class _HfsReader {
  _HfsReader(
    this.source,
    this.maxMemberBytes,
    this.maxEntries,
    this.maxCatalogBytes,
    this.maxDepth,
  );

  final koni.ByteSource source;
  final int maxMemberBytes;
  final int maxEntries;
  final int maxCatalogBytes;
  final int maxDepth;
  int _blockSize = 0;
  int _totalBlocks = 0;
  int _volumeBytes = 0;
  int _catalogBytesRead = 0;
  final _records = <int, _CatalogRecord>{};

  Never _bad(String message) =>
      throw ArchiveViewException('Invalid HFS volume: $message');
  Never _unsupported(String message) =>
      throw ArchiveViewException('Unsupported HFS volume: $message');

  Future<Uint8List> _read(int offset, int length) async {
    final bound = _volumeBytes == 0 ? source.length : _volumeBytes;
    if (offset < 0 || length < 0 || offset > bound || length > bound - offset) {
      _bad('An extent leaves the volume.');
    }
    final result = await source.read(offset, length);
    if (result.length != length) _bad('The volume is truncated.');
    return result;
  }

  int _u64(ByteData bytes, int at) {
    final high = bytes.getUint32(at);
    if (high > 0x1fffff) {
      _unsupported('A fork size exceeds the exact integer range.');
    }
    return high * 0x100000000 + bytes.getUint32(at + 4);
  }

  _Fork _fork(ByteData data, int at) {
    final size = _u64(data, at);
    final totalBlocks = data.getUint32(at + 12);
    final extents = <_Extent>[];
    var allocated = 0;
    var ended = false;
    for (var i = 0; i < 8; i++) {
      final start = data.getUint32(at + 16 + 8 * i);
      final count = data.getUint32(at + 20 + 8 * i);
      if (count == 0) {
        if (start != 0) _bad('An empty extent has a nonzero start.');
        ended = true;
        continue;
      }
      if (ended) _bad('A fork has an extent after its terminator.');
      if (start >= _totalBlocks || count > _totalBlocks - start) {
        _bad('A fork extent leaves the volume.');
      }
      for (final previous in extents) {
        if (start < previous.start + previous.count &&
            previous.start < start + count) {
          _bad('A fork has overlapping extents.');
        }
      }
      extents.add(_Extent(start, count));
      allocated += count;
    }
    if (allocated > totalBlocks || totalBlocks > _totalBlocks) {
      _bad('A fork allocation count is inconsistent.');
    }
    if (size > totalBlocks * _blockSize) {
      _bad('A fork is larger than its allocation.');
    }
    return _Fork(size, extents, needsOverflow: allocated != totalBlocks);
  }

  Future<Uint8List> _readFork(_Fork fork, int offset, int length) async {
    if (fork.needsOverflow) {
      _unsupported('This fork needs the extents overflow B-tree.');
    }
    if (offset < 0 ||
        length < 0 ||
        offset > fork.size ||
        length > fork.size - offset) {
      _bad('A read leaves its fork.');
    }
    final result = Uint8List(length);
    var logical = 0;
    var copied = 0;
    for (final extent in fork.extents) {
      final extentBytes = extent.count * _blockSize;
      if (offset >= logical + extentBytes) {
        logical += extentBytes;
        continue;
      }
      var within = offset > logical ? offset - logical : 0;
      while (within < extentBytes && copied < length) {
        var amount = length - copied;
        if (amount > extentBytes - within) amount = extentBytes - within;
        if (amount > 1024 * 1024) amount = 1024 * 1024;
        final chunk = await _read(extent.start * _blockSize + within, amount);
        result.setRange(copied, copied + amount, chunk);
        copied += amount;
        within += amount;
        offset += amount;
      }
      if (copied == length) return result;
      logical += extentBytes;
    }
    if (copied != length) _bad('A fork is missing data extents.');
    return result;
  }

  Future<Uint8List> _catalogRead(_Fork fork, int offset, int length) async {
    if (length > maxCatalogBytes - _catalogBytesRead) {
      _unsupported('The catalog exceeds the metadata reading limit.');
    }
    _catalogBytesRead += length;
    return _readFork(fork, offset, length);
  }

  Future<ViewerArchive> open() async {
    final header = ByteData.sublistView(await _read(1024, 512));
    final signature = header.getUint16(0);
    final hfsx = signature == 0x4858;
    if ((!hfsx && signature != 0x482b) ||
        header.getUint16(2) != (hfsx ? 5 : 4)) {
      _unsupported('Only HFS+ and HFSX volumes are supported.');
    }
    final attributes = header.getUint32(4);
    if (attributes & 0x100 == 0 || attributes & 0x800 != 0) {
      _unsupported(
        'The volume was not cleanly unmounted; journal replay is required.',
      );
    }
    _blockSize = header.getUint32(40);
    _totalBlocks = header.getUint32(44);
    if (_blockSize < 512 ||
        _blockSize & (_blockSize - 1) != 0 ||
        _totalBlocks == 0 ||
        _blockSize > source.length ~/ _totalBlocks) {
      _bad('The allocation block size or volume length is invalid.');
    }
    // Dart web represents integer offsets with JavaScript numbers. Validate
    // before multiplying so an enormous virtual source cannot round a read.
    if (_blockSize > 0x1fffffffffffff ~/ _totalBlocks) {
      _unsupported('The volume exceeds the exact integer address range.');
    }
    _volumeBytes = _totalBlocks * _blockSize;
    if (_volumeBytes < 1536) _bad('The volume cannot contain its header.');
    final catalog = _fork(header, 272);
    await _catalog(catalog);

    final root = _records[2];
    if (root == null || !root.directory || root.parentId != 1) {
      _bad('The catalog has no valid root folder.');
    }
    final paths = <int, String>{2: ''};
    final depths = <int, int>{2: 0};
    String resolve(_CatalogRecord record) {
      final pending = <_CatalogRecord>[];
      final visiting = <int>{};
      var current = record;
      while (!paths.containsKey(current.id)) {
        if (!visiting.add(current.id)) {
          _bad('The folder hierarchy contains a cycle.');
        }
        if (pending.length >= maxDepth) {
          _unsupported('The folder hierarchy is too deep.');
        }
        pending.add(current);
        final parent = _records[current.parentId];
        if (parent == null || !parent.directory) {
          _bad('A catalog record has a missing or non-directory parent.');
        }
        current = parent;
      }
      var path = paths[current.id]!;
      var depth = depths[current.id]!;
      for (final child in pending.reversed) {
        if (++depth > maxDepth) {
          _unsupported('The folder hierarchy is too deep.');
        }
        path = path.isEmpty ? child.name : '$path/${child.name}';
        if (path.length > 4096) _unsupported('An entry path is too long.');
        paths[child.id] = path;
        depths[child.id] = depth;
      }
      return paths[record.id]!;
    }

    final members = <ViewerArchiveMember>[];
    final ordered = <_CatalogRecord>[];
    final names = <String>{};
    var nameBudget = 0;
    for (final record in _records.values) {
      if (record.id == 2) continue;
      final path = resolve(record);
      if (!names.add(path)) _bad('The catalog contains duplicate paths.');
      nameBudget += path.length * 2;
      if (nameBudget > maxCatalogBytes) {
        _unsupported('The catalog path table is too large.');
      }
      ordered.add(record);
      members.add(
        ViewerArchiveMember(
          name: path,
          size: record.fork?.size ?? 0,
          isFile: !record.directory,
          isEncrypted: false,
          isSpecial: record.special,
          modified: DateTime.fromMillisecondsSinceEpoch(
            (record.modified - 2082844800) * 1000,
            isUtc: true,
          ),
          posixMode: record.mode == 0 ? null : record.mode,
          pathEscapedRoot: false,
          index: members.length,
        ),
      );
    }
    return ViewerArchive.reader(
      formatName: hfsx ? 'hfsx' : 'hfs+',
      members: members,
      read: (member, requestedCap) async {
        final record = ordered[member.index];
        if (record.directory || record.special) {
          _unsupported(
            'Directories, symbolic links and special files cannot be read as files.',
          );
        }
        final fork = record.fork!;
        final limit = requestedCap < maxMemberBytes
            ? requestedCap
            : maxMemberBytes;
        if (fork.size > limit) {
          throw const ArchiveViewException(
            'The HFS file exceeds the member reading limit.',
          );
        }
        return _readFork(fork, 0, fork.size);
      },
      close: source.close,
    );
  }

  Future<void> _catalog(_Fork fork) async {
    final start = await _catalogRead(fork, 0, 120);
    final prefix = ByteData.sublistView(start);
    if (start[8] != 1 || start[9] != 0 || prefix.getUint16(10) != 3) {
      _bad('The catalog header node is invalid.');
    }
    final nodeSize = prefix.getUint16(32);
    final totalNodes = prefix.getUint32(36);
    final treeDepth = prefix.getUint16(14);
    final rootNode = prefix.getUint32(16);
    final leafRecords = prefix.getUint32(20);
    final firstLeaf = prefix.getUint32(24);
    final lastLeaf = prefix.getUint32(28);
    if (nodeSize < 512 ||
        nodeSize & (nodeSize - 1) != 0 ||
        totalNodes < 2 ||
        totalNodes > fork.size ~/ nodeSize ||
        treeDepth < 1 ||
        treeDepth > 32 ||
        rootNode == 0 ||
        rootNode >= totalNodes ||
        firstLeaf == 0 ||
        firstLeaf >= totalNodes ||
        lastLeaf == 0 ||
        lastLeaf >= totalNodes ||
        leafRecords == 0 ||
        prefix.getUint32(40) > totalNodes ||
        prefix.getUint32(52) & 2 == 0) {
      _bad('The catalog B-tree dimensions are invalid.');
    }
    if (leafRecords > (maxEntries + 1) * 2) {
      _unsupported('The catalog exceeds the entry count limit.');
    }
    final header = await _catalogRead(fork, 0, nodeSize);
    final headerOffsets = _offsets(header);
    if (headerOffsets[0] != 14 || headerOffsets[1] - headerOffsets[0] < 106) {
      _bad('The B-tree header record is truncated.');
    }
    if (treeDepth == 1 && (rootNode != firstLeaf || rootNode != lastLeaf)) {
      _bad('The catalog root and leaf nodes disagree.');
    }
    if (treeDepth > 1) {
      final root = await _catalogRead(fork, rootNode * nodeSize, nodeSize);
      if (root[8] != 0 || root[9] != treeDepth) {
        _bad('The catalog root is invalid.');
      }
      _offsets(root);
    }
    final visited = <int>{};
    var current = firstLeaf;
    var previous = 0;
    var count = 0;
    while (current != 0) {
      if (current >= totalNodes || !visited.add(current)) {
        _bad('The catalog leaf chain is cyclic or out of bounds.');
      }
      final node = await _catalogRead(fork, current * nodeSize, nodeSize);
      final data = ByteData.sublistView(node);
      if (node[8] != 255 || node[9] != 1 || data.getUint32(4) != previous) {
        _bad('A catalog leaf descriptor is invalid.');
      }
      final offsets = _offsets(node);
      if (offsets.length <= 1) _bad('The catalog contains an empty leaf.');
      for (var i = 0; i + 1 < offsets.length; i++) {
        if (++count > leafRecords) {
          _bad('The catalog leaf count is inconsistent.');
        }
        _record(ByteData.sublistView(node, offsets[i], offsets[i + 1]));
      }
      previous = current;
      current = data.getUint32(0);
    }
    if (previous != lastLeaf || count != leafRecords) {
      _bad('The catalog leaf chain is incomplete.');
    }
  }

  List<int> _offsets(Uint8List node) {
    final data = ByteData.sublistView(node);
    final count = data.getUint16(10);
    final tableStart = node.length - (count + 1) * 2;
    if (tableStart < 14) _bad('A B-tree record table overlaps its descriptor.');
    final offsets = <int>[];
    var previous = 0;
    for (var i = 0; i <= count; i++) {
      final offset = data.getUint16(node.length - 2 * (i + 1));
      if (offset < 14 ||
          offset > tableStart ||
          offset.isOdd ||
          (i > 0 && offset <= previous)) {
        _bad('A B-tree record offset is invalid.');
      }
      if (i == 0 && offset != 14) _bad('A B-tree first record is misplaced.');
      offsets.add(offset);
      previous = offset;
    }
    return offsets;
  }

  String _name(ByteData record, int at, int length) {
    final units = <int>[];
    for (var i = 0; i < length; i++) {
      units.add(record.getUint16(at + 2 * i));
    }
    for (var i = 0; i < units.length; i++) {
      if (units[i] >= 0xd800 && units[i] <= 0xdbff) {
        if (++i == units.length || units[i] < 0xdc00 || units[i] > 0xdfff) {
          _bad('A catalog name contains invalid UTF-16.');
        }
      } else if (units[i] >= 0xdc00 && units[i] <= 0xdfff) {
        _bad('A catalog name contains invalid UTF-16.');
      }
    }
    final name = String.fromCharCodes(units);
    if (name.isEmpty ||
        name == '.' ||
        name == '..' ||
        name.contains('/') ||
        name.contains('\\') ||
        name.contains(':') ||
        name.codeUnits.any((unit) => unit < 32 || unit == 127)) {
      _unsupported(
        'A catalog name cannot be safely represented as an archive path.',
      );
    }
    return name;
  }

  void _record(ByteData record) {
    if (record.lengthInBytes < 10) _bad('A catalog record is truncated.');
    final keyLength = record.getUint16(0);
    final parentId = record.getUint32(2);
    final nameLength = record.getUint16(6);
    if (nameLength > 255 ||
        keyLength != 6 + 2 * nameLength ||
        keyLength + 4 > record.lengthInBytes) {
      _bad('A catalog key is invalid.');
    }
    final at = keyLength + 2;
    final type = record.getUint16(at);
    if (type == 3 || type == 4) {
      if (nameLength != 0 || record.lengthInBytes - at < 10) {
        _bad('A catalog thread is invalid.');
      }
      final threadNameLength = record.getUint16(at + 8);
      if (threadNameLength > 255 ||
          at + 10 + 2 * threadNameLength > record.lengthInBytes) {
        _bad('A catalog thread is truncated.');
      }
      return;
    }
    if (type != 1 && type != 2) {
      _bad('An unknown catalog record type was found.');
    }
    if (record.lengthInBytes - at < (type == 1 ? 88 : 248)) {
      _bad('A file or folder record is truncated.');
    }
    final id = record.getUint32(at + 8);
    if (id != 2 && id < 16) _bad('A user record has a reserved catalog ID.');
    if (_records.containsKey(id)) _bad('The catalog contains duplicate IDs.');
    if (_records.length > maxEntries) {
      _unsupported('The catalog exceeds the entry count limit.');
    }
    final name = _name(record, 8, nameLength);
    final mode = record.getUint16(at + 42);
    final fileType = mode & 0xf000;
    final directory = type == 1;
    if (directory && fileType != 0 && fileType != 0x4000 ||
        !directory && fileType == 0x4000) {
      _bad('The catalog type and POSIX mode disagree.');
    }
    // UF_COMPRESSED is stored in the low BSD owner-flags byte. Its data may
    // live in an extended attribute/resource fork instead of the data fork.
    if (record.getUint8(at + 41) & 0x20 != 0) {
      _unsupported('HFS compressed files need decmpfs support.');
    }
    final linked =
        record.getUint16(at + 2) & 0x20 != 0 ||
        (record.getUint32(at + 48) == 0x686c6e6b &&
            record.getUint32(at + 52) == 0x6866732b);
    if (linked) _unsupported('HFS hard links are not supported.');
    final fork = directory ? null : _fork(record, at + 88);
    _records[id] = _CatalogRecord(
      id: id,
      parentId: parentId,
      name: name,
      directory: directory,
      special: !directory && fileType != 0 && fileType != 0x8000,
      modified: record.getUint32(at + 16),
      mode: mode,
      fork: fork,
    );
  }
}

class _Extent {
  const _Extent(this.start, this.count);
  final int start;
  final int count;
}

class _Fork {
  const _Fork(this.size, this.extents, {required this.needsOverflow});
  final int size;
  final List<_Extent> extents;
  final bool needsOverflow;
}

class _CatalogRecord {
  const _CatalogRecord({
    required this.id,
    required this.parentId,
    required this.name,
    required this.directory,
    required this.special,
    required this.modified,
    required this.mode,
    required this.fork,
  });
  final int id;
  final int parentId;
  final String name;
  final bool directory;
  final bool special;
  final int modified;
  final int mode;
  final _Fork? fork;
}
