// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Mohammed Asaad Asaad
// See third_party/quds_office_engine-MIT.txt.

import 'dart:typed_data';

import 'byte_source.dart';
import 'cfbf_names.dart';

/// Compound File Binary signature: `D0 CF 11 E0 A1 B1 1A E1`.
const List<int> cfbfSignature = <int>[
  0xD0,
  0xCF,
  0x11,
  0xE0,
  0xA1,
  0xB1,
  0x1A,
  0xE1,
];

const int cfbfFreeSect = 0xFFFFFFFF;
const int cfbfEndOfChain = 0xFFFFFFFE;
const int cfbfFatSect = 0xFFFFFFFD;
const int cfbfDifatSect = 0xFFFFFFFC;
const int cfbfNoStream = 0xFFFFFFFF;

/// Directory object type (MS-CFB §2.6.1).
enum CfbfObjectType { empty, storage, stream, root }

/// One 128-byte directory entry.
class CfbfDirectoryEntry {
  /// CfbfDirectoryEntry API.
  CfbfDirectoryEntry({
    required this.index,
    required this.name,
    required this.type,
    required this.colorBlack,
    required this.leftSibling,
    required this.rightSibling,
    required this.child,
    required this.clsid,
    required this.stateBits,
    required this.created,
    required this.modified,
    Uint8List? createdFiletime,
    Uint8List? modifiedFiletime,
    required this.startSector,
    required this.streamSize,
  }) : createdFiletime = (createdFiletime ?? Uint8List(8)).asUnmodifiableView(),
       modifiedFiletime = (modifiedFiletime ?? Uint8List(8))
           .asUnmodifiableView();

  /// index API.
  final int index;

  /// name API.
  final String name;

  /// type API.
  final CfbfObjectType type;

  /// colorBlack API.
  final bool colorBlack;

  /// leftSibling API.
  final int leftSibling;

  /// rightSibling API.
  final int rightSibling;

  /// child API.
  final int child;

  /// clsid API.
  final Uint8List clsid;

  /// stateBits API.
  final int stateBits;

  /// created API.
  final DateTime? created;

  /// modified API.
  final DateTime? modified;

  /// Exact little-endian FILETIME bytes, including sub-microsecond precision.
  final Uint8List createdFiletime;
  final Uint8List modifiedFiletime;

  /// startSector API.
  final int startSector;

  /// streamSize API.
  final int streamSize;

  /// isStream API.
  bool get isStream => type == CfbfObjectType.stream;

  /// isStorage API.
  bool get isStorage =>
      type == CfbfObjectType.storage || type == CfbfObjectType.root;
}

/// Parsed Compound File Binary (OLE 2.0 structured storage).
///
/// Allocation and directory metadata are immutable snapshots. Successful and
/// failed chain validation is cached, as is the mini-stream container once it
/// is read. Do not modify the underlying [source] while this reader is in use.
class CfbfFile {
  CfbfFile._({
    required this.source,
    required this.header,
    required List<int> fat,
    required List<int> miniFat,
    required List<CfbfDirectoryEntry> entries,
    required Set<int> metadataSectors,
  }) : fat = List.unmodifiable(fat),
       miniFat = List.unmodifiable(miniFat),
       entries = List.unmodifiable(entries),
       _metadataSectors = Set.unmodifiable(metadataSectors);

  /// source API.
  final ByteSource source;

  /// header API.
  final CfbfHeader header;

  /// Immutable FAT snapshot. Chain validation is cached against these bytes.
  final List<int> fat;

  /// Immutable mini-FAT snapshot.
  final List<int> miniFat;

  /// Immutable directory snapshot, including the mini-stream's root metadata.
  final List<CfbfDirectoryEntry> entries;

  final Map<int, int> _fatChainLengths = {};
  final Map<int, int> _miniChainLengths = {};
  final Set<int> _metadataSectors;
  Set<int>? _sharedStreamEntries;
  Uint8List? _miniContainer;

  /// root API.
  CfbfDirectoryEntry get root => entries.firstWhere(
    (CfbfDirectoryEntry e) => e.type == CfbfObjectType.root,
  );

  /// open API.
  factory CfbfFile.open(ByteSource source) {
    final CfbfHeader header = CfbfHeader.parse(source);
    final metadataSectors = <int>{};
    final List<int> fat = _readFat(source, header, metadataSectors);
    final List<CfbfDirectoryEntry> entries = _readDirectory(
      source,
      header,
      fat,
      metadataSectors,
    );
    final List<int> miniFat = _readMiniFat(
      source,
      header,
      fat,
      metadataSectors,
    );
    return CfbfFile._(
      source: source,
      header: header,
      fat: fat,
      miniFat: miniFat,
      entries: entries,
      metadataSectors: metadataSectors,
    );
  }

  /// fromBytes API.
  factory CfbfFile.fromBytes(Uint8List bytes) =>
      CfbfFile.open(MemoryByteSource(bytes));

  /// isCfbf API.
  static bool isCfbf(List<int> bytes) {
    if (bytes.length < 8) {
      return false;
    }
    for (int i = 0; i < 8; i++) {
      if (bytes[i] != cfbfSignature[i]) {
        return false;
      }
    }
    return true;
  }

  /// entryByName API.
  CfbfDirectoryEntry? entryByName(String name) {
    for (final CfbfDirectoryEntry entry in entries) {
      if (entry.type == CfbfObjectType.empty) {
        continue;
      }
      if (_cfbfNamesEqual(entry.name, name)) {
        return entry;
      }
    }
    return null;
  }

  /// Walks the red-black sibling tree under [parent] (child index).
  Iterable<CfbfDirectoryEntry> childrenOf(CfbfDirectoryEntry parent) sync* {
    if (parent.child == cfbfNoStream) {
      return;
    }
    final List<int> stack = <int>[parent.child];
    final Set<int> seen = <int>{};
    while (stack.isNotEmpty) {
      final int index = stack.removeLast();
      if (index == cfbfNoStream ||
          !seen.add(index) ||
          index >= entries.length) {
        continue;
      }
      final CfbfDirectoryEntry entry = entries[index];
      if (entry.type == CfbfObjectType.empty) {
        continue;
      }
      yield entry;
      stack.add(entry.leftSibling);
      stack.add(entry.rightSibling);
    }
  }

  /// Reads a stream by directory [name] (case-insensitive CFBF compare).
  Uint8List? readStream(String name) {
    final CfbfDirectoryEntry? entry = entryByName(name);
    if (entry == null || !entry.isStream) {
      return null;
    }
    return readEntry(entry);
  }

  /// Reads a stream or mini-container described by this file's directory.
  Uint8List readEntry(CfbfDirectoryEntry entry) {
    // Ownership is cached against the parsed directory, so a caller-supplied
    // entry must not substitute a different allocation under the same index.
    if (entry.index < 0 ||
        entry.index >= entries.length ||
        (!entry.isStream && entry.type != CfbfObjectType.root) ||
        entries[entry.index].type != entry.type ||
        entries[entry.index].startSector != entry.startSector ||
        entries[entry.index].streamSize != entry.streamSize) {
      throw const CfbfException('Stream entry does not match this directory');
    }
    if (entry.streamSize < 0 || entry.streamSize > source.length) {
      throw const CfbfException('Stream size exceeds its compound container');
    }
    if (entry.streamSize == 0) {
      return Uint8List(0);
    }
    final bool mini =
        entry.type != CfbfObjectType.root &&
        entry.streamSize < header.miniStreamCutoff;
    final shared = _sharedStreamEntries ??= _findSharedStreamEntries();
    if (shared.contains(entry.index) || (mini && shared.contains(root.index))) {
      throw const CfbfException('Stream allocation has multiple owners');
    }
    if (mini) {
      return _readMiniStream(entry);
    }
    return _readFatStream(entry.startSector, entry.streamSize);
  }

  /// Detect ambiguous ownership before returning any stream's bytes. Merely
  /// claiming sectors as streams are read would expose whichever alias was
  /// requested first. Each sector is visited at most once in each namespace;
  /// stopping at an existing owner also bounds adversarial shared long tails.
  ///
  /// This is not an eager topology check: unrelated invalid links and cycles
  /// are still rejected only when their streams are requested. Extra allocated
  /// capacity belongs to its stream even when it lies past the logical bytes.
  Set<int> _findSharedStreamEntries() {
    final conflicts = <int>{};
    final regularOwners = <int, int>{
      for (final sector in _metadataSectors) sector: -1,
    };
    final miniOwners = <int, int>{};
    void claim(
      CfbfDirectoryEntry entry,
      List<int> table,
      Map<int, int> owners,
      int physicalSectors,
    ) {
      var sector = entry.startSector;
      while (sector != cfbfEndOfChain &&
          sector >= 0 &&
          sector < physicalSectors &&
          sector < table.length) {
        final previous = owners[sector];
        if (previous != null) {
          if (previous != entry.index) {
            conflicts.add(entry.index);
            if (previous >= 0) conflicts.add(previous);
          }
          return;
        }
        owners[sector] = entry.index;
        sector = table[sector];
      }
    }

    final physicalSectors = source.length ~/ header.sectorSize - 1;
    final miniSize = header.miniSectorSize;
    // The mini-container cannot exceed the source; its exact logical bound
    // (including compatibility with a partial last mini sector) is checked on
    // read. This cap also bounds the scan of an oversized mini-FAT.
    final miniSectors = miniSize > 0
        ? (source.length + miniSize - 1) ~/ miniSize
        : 0;
    for (final entry in entries) {
      if (entry.streamSize <= 0) continue;
      if (entry.type == CfbfObjectType.root ||
          (entry.isStream && entry.streamSize >= header.miniStreamCutoff)) {
        claim(entry, fat, regularOwners, physicalSectors);
      } else if (entry.isStream) {
        claim(entry, miniFat, miniOwners, miniSectors);
      }
    }
    return conflicts;
  }

  /// Resolves a storage path such as `ObjectPool/obj1/Package`.
  Uint8List? readPath(String path) {
    final List<String> parts = path
        .split('/')
        .where((String s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return null;
    }
    CfbfDirectoryEntry current = root;
    for (int i = 0; i < parts.length; i++) {
      final String segment = parts[i];
      CfbfDirectoryEntry? next;
      for (final CfbfDirectoryEntry child in childrenOf(current)) {
        if (_cfbfNamesEqual(child.name, segment)) {
          next = child;
          break;
        }
      }
      if (next == null) {
        return null;
      }
      if (i == parts.length - 1) {
        if (next.isStream) {
          return readEntry(next);
        }
        return null;
      }
      if (!next.isStorage) {
        return null;
      }
      current = next;
    }
    return null;
  }

  Uint8List _readFatStream(int startSector, int size) {
    // Mini-stream reads call this directly for the root container, bypassing
    // readEntry. Check its physical bound before allocating, too.
    if (size < 0 || size > source.length) {
      throw const CfbfException('Stream size exceeds its compound container');
    }
    final int sectorSize = header.sectorSize;
    final sectors = _validatedChainLength(
      fat,
      startSector,
      _fatChainLengths,
      source.length ~/ sectorSize - 1,
    );
    if (sectors * sectorSize < size) {
      throw const CfbfException('Truncated FAT stream');
    }
    final Uint8List out = Uint8List(size);
    int remaining = size;
    int written = 0;
    int sector = startSector;
    while (remaining > 0) {
      final int offset = header.sectorOffset(sector);
      final int take = remaining < sectorSize ? remaining : sectorSize;
      out.setRange(written, written + take, source.view(offset, take));
      written += take;
      remaining -= take;
      sector = fat[sector];
    }
    return out;
  }

  Uint8List _readMiniStream(CfbfDirectoryEntry entry) {
    final Uint8List miniContainer = _miniContainer ??= _readFatStream(
      root.startSector,
      root.streamSize,
    );
    final int miniSize = header.miniSectorSize;
    final sectors = _validatedChainLength(
      miniFat,
      entry.startSector,
      _miniChainLengths,
      (miniContainer.length + miniSize - 1) ~/ miniSize,
    );
    if (sectors * miniSize < entry.streamSize) {
      throw const CfbfException('Truncated mini stream');
    }
    final Uint8List out = Uint8List(entry.streamSize);
    int remaining = entry.streamSize;
    int written = 0;
    int sector = entry.startSector;
    while (remaining > 0) {
      final int offset = sector * miniSize;
      final int take = remaining < miniSize ? remaining : miniSize;
      if (offset + take > miniContainer.length) {
        throw const CfbfException('Mini stream exceeds container');
      }
      out.setRange(
        written,
        written + take,
        Uint8List.sublistView(miniContainer, offset, offset + take),
      );
      written += take;
      remaining -= take;
      sector = miniFat[sector];
    }
    return out;
  }

  /// Validate each allocation-table suffix once, including spare capacity.
  /// Logical reads still copy only their requested bytes. Without suffix
  /// caching, repeated reads of a valid overallocated stream could repeatedly
  /// traverse the whole file. Ownership validation separately rejects aliases.
  static int _validatedChainLength(
    List<int> table,
    int start,
    Map<int, int> cached,
    int physicalSectorCount,
  ) {
    final path = <int>[];
    final seen = <int>{};
    var sector = start;
    var length = 0;
    try {
      while (sector != cfbfEndOfChain) {
        final previous = cached[sector];
        if (previous != null) {
          if (previous < 0) {
            throw const CfbfException('Invalid compound allocation chain');
          }
          length = previous;
          break;
        }
        if (sector < 0 ||
            sector >= physicalSectorCount ||
            sector >= table.length ||
            !seen.add(sector)) {
          throw const CfbfException('Invalid or cyclic allocation chain');
        }
        path.add(sector);
        sector = table[sector];
      }
      for (var index = path.length - 1; index >= 0; index--) {
        cached[path[index]] = ++length;
      }
      return length;
    } on CfbfException {
      // A repeated request for an invalid suffix must not repeat its work.
      for (final index in path) {
        cached[index] = -1;
      }
      rethrow;
    }
  }

  static List<int> _readFat(
    ByteSource source,
    CfbfHeader header,
    Set<int> metadataSectors,
  ) {
    final List<int> difat = <int>[];
    final seenFat = <int>{};
    final physicalSectors = source.length ~/ header.sectorSize - 1;
    final entriesPerSector = header.sectorSize ~/ 4;
    void addFat(int sector) {
      if (sector == cfbfFreeSect) return;
      if (sector < 0 || sector >= physicalSectors || !seenFat.add(sector)) {
        throw const CfbfException('Invalid or repeated FAT sector');
      }
      difat.add(sector);
    }

    for (final sector in header.headerDifat) {
      addFat(sector);
    }
    int difatSector = header.firstDifatSector;
    final Set<int> guard = <int>{};
    while (difatSector != cfbfEndOfChain && difatSector != cfbfFreeSect) {
      if (difatSector < 0 ||
          difatSector >= physicalSectors ||
          !guard.add(difatSector)) {
        throw const CfbfException('Invalid or cyclic DIFAT sector');
      }
      final int offset = header.sectorOffset(difatSector);
      final ByteCursor cursor = ByteCursor.view(
        source,
        offset,
        header.sectorSize,
      );
      for (int i = 0; i < entriesPerSector - 1; i++) {
        addFat(cursor.u32le());
      }
      difatSector = cursor.u32le();
    }

    if (difat.length != header.fatSectorCount ||
        guard.length != header.difatSectorCount) {
      throw const CfbfException('Inconsistent FAT or DIFAT sector count');
    }
    _reserveMetadata(difat, metadataSectors);
    _reserveMetadata(guard, metadataSectors);

    final List<int> fat = <int>[];
    for (final int fatSector in difat) {
      final ByteCursor cursor = ByteCursor.view(
        source,
        header.sectorOffset(fatSector),
        header.sectorSize,
      );
      final int count = header.sectorSize ~/ 4;
      for (int i = 0; i < count; i++) {
        fat.add(cursor.u32le());
      }
    }
    return fat;
  }

  static List<CfbfDirectoryEntry> _readDirectory(
    ByteSource source,
    CfbfHeader header,
    List<int> fat,
    Set<int> metadataSectors,
  ) {
    final List<int> chain = _followChain(fat, header.firstDirectorySector);
    if (header.majorVersion == 4 &&
        chain.length != header.directorySectorCount) {
      throw const CfbfException('Inconsistent directory sector count');
    }
    _reserveMetadata(chain, metadataSectors);
    final BytesBuilder builder = BytesBuilder(copy: false);
    for (final int sector in chain) {
      builder.add(source.view(header.sectorOffset(sector), header.sectorSize));
    }
    final Uint8List raw = builder.takeBytes();
    final List<CfbfDirectoryEntry> entries = <CfbfDirectoryEntry>[];
    for (
      int offset = 0, index = 0;
      offset + 128 <= raw.length;
      offset += 128, index++
    ) {
      entries.add(
        _parseDirectoryEntry(raw, offset, index, header.majorVersion),
      );
    }
    return entries;
  }

  static List<int> _readMiniFat(
    ByteSource source,
    CfbfHeader header,
    List<int> fat,
    Set<int> metadataSectors,
  ) {
    if (header.miniFatSectorCount == 0) {
      return <int>[];
    }
    final List<int> chain = _followChain(fat, header.firstMiniFatSector);
    if (chain.length != header.miniFatSectorCount) {
      throw const CfbfException('Inconsistent mini FAT sector count');
    }
    _reserveMetadata(chain, metadataSectors);
    final List<int> mini = <int>[];
    for (final int sector in chain) {
      final ByteCursor cursor = ByteCursor.view(
        source,
        header.sectorOffset(sector),
        header.sectorSize,
      );
      final int count = header.sectorSize ~/ 4;
      for (int i = 0; i < count; i++) {
        mini.add(cursor.u32le());
      }
    }
    return mini;
  }

  static void _reserveMetadata(Iterable<int> chain, Set<int> reserved) {
    for (final sector in chain) {
      if (!reserved.add(sector)) {
        throw const CfbfException('Compound metadata sectors overlap');
      }
    }
  }

  static List<int> _followChain(List<int> fat, int start) {
    final List<int> chain = <int>[];
    final Set<int> seen = <int>{};
    int sector = start;
    while (sector != cfbfEndOfChain) {
      if (!seen.add(sector)) {
        throw const CfbfException('Sector chain cycle detected');
      }
      chain.add(sector);
      if (sector >= fat.length) {
        throw CfbfException('Sector $sector missing from FAT');
      }
      sector = fat[sector];
    }
    return chain;
  }

  static CfbfDirectoryEntry _parseDirectoryEntry(
    Uint8List raw,
    int offset,
    int index,
    int majorVersion,
  ) {
    final ByteCursor cursor = ByteCursor(
      Uint8List.sublistView(raw, offset, offset + 128),
    );
    final Uint8List nameBytes = cursor.bytes(64);
    final int nameLen = cursor.u16le();
    final int typeByte = cursor.u8();
    final int color = cursor.u8();
    final int left = cursor.u32le();
    final int right = cursor.u32le();
    final int child = cursor.u32le();
    final Uint8List clsid = cursor.copyBytes(16);
    final int state = cursor.u32le();
    final createdRaw = cursor.copyBytes(8);
    final modifiedRaw = cursor.copyBytes(8);
    final int start = cursor.u32le();
    final int sizeLow = cursor.u32le();
    final int sizeHigh = cursor.u32le();
    // MS-CFB §2.6.3: historical version-3 writers left the high DWORD
    // uninitialized. Only version 4 gives those bits stream-size meaning.
    // These fields are unused for storage/unallocated directory entries.
    var size = sizeLow;
    if (majorVersion != 3 && (typeByte == 2 || typeByte == 5)) {
      if (sizeHigh > 0x1fffff) {
        throw const CfbfException(
          'Stream size exceeds the portable integer range',
        );
      }
      // JavaScript bitwise shifts discard the high word. Arithmetic retains
      // exact unsigned metadata through 2^53-1; larger values fail explicitly.
      size = sizeHigh * 0x100000000 + sizeLow;
    }

    final StringBuffer name = StringBuffer();
    if (typeByte == 1 || typeByte == 2 || typeByte == 5) {
      // MS-CFB §2.6.1 counts the terminating UTF-16 NUL in the byte length.
      // Silently truncating this field aliases malformed names to unrelated
      // valid lookup keys. Padding and deleted directory slots remain ignored.
      if (nameLen < 2 || nameLen > 64 || nameLen.isOdd) {
        throw CfbfException('Invalid directory name length at entry $index');
      }
      final int charCount = nameLen ~/ 2;
      for (int i = 0; i < charCount; i++) {
        final int unit = nameBytes[i * 2] | (nameBytes[i * 2 + 1] << 8);
        if (i == charCount - 1) {
          if (unit != 0) {
            throw CfbfException('Unterminated directory name at entry $index');
          }
        } else {
          if (unit == 0 ||
              unit == 0x2f ||
              unit == 0x5c ||
              unit == 0x3a ||
              unit == 0x21) {
            throw CfbfException('Invalid directory name at entry $index');
          }
          name.writeCharCode(unit);
        }
      }
    }

    return CfbfDirectoryEntry(
      index: index,
      name: name.toString(),
      type: switch (typeByte) {
        1 => CfbfObjectType.storage,
        2 => CfbfObjectType.stream,
        5 => CfbfObjectType.root,
        _ => CfbfObjectType.empty,
      },
      colorBlack: color == 1,
      leftSibling: left,
      rightSibling: right,
      child: child,
      clsid: clsid,
      stateBits: state,
      created: _filetimeToDate(createdRaw),
      modified: _filetimeToDate(modifiedRaw),
      createdFiletime: createdRaw,
      modifiedFiletime: modifiedRaw,
      startSector: start,
      streamSize: size,
    );
  }
}

/// CFBF header (first 512 bytes).
class CfbfHeader {
  /// CfbfHeader API.
  CfbfHeader({
    required this.majorVersion,
    required this.sectorShift,
    required this.miniSectorShift,
    required this.directorySectorCount,
    required this.fatSectorCount,
    required this.firstDirectorySector,
    required this.miniStreamCutoff,
    required this.firstMiniFatSector,
    required this.miniFatSectorCount,
    required this.firstDifatSector,
    required this.difatSectorCount,
    required this.headerDifat,
  });

  /// majorVersion API.
  final int majorVersion;

  /// sectorShift API.
  final int sectorShift;

  /// miniSectorShift API.
  final int miniSectorShift;

  /// directorySectorCount API.
  final int directorySectorCount;

  /// fatSectorCount API.
  final int fatSectorCount;

  /// firstDirectorySector API.
  final int firstDirectorySector;

  /// miniStreamCutoff API.
  final int miniStreamCutoff;

  /// firstMiniFatSector API.
  final int firstMiniFatSector;

  /// miniFatSectorCount API.
  final int miniFatSectorCount;

  /// firstDifatSector API.
  final int firstDifatSector;

  /// difatSectorCount API.
  final int difatSectorCount;

  /// headerDifat API.
  final List<int> headerDifat;

  /// sectorSize API.
  int get sectorSize => 1 << sectorShift;

  /// miniSectorSize API.
  int get miniSectorSize => 1 << miniSectorShift;

  /// sectorOffset API.
  int sectorOffset(int sector) => (sector + 1) * sectorSize;

  /// parse API.
  factory CfbfHeader.parse(ByteSource source) {
    if (source.length < 512) {
      throw const CfbfException('CFBF header is shorter than 512 bytes');
    }
    final ByteCursor cursor = ByteCursor.view(source, 0, 512);
    final Uint8List sig = cursor.bytes(8);
    for (int i = 0; i < 8; i++) {
      if (sig[i] != cfbfSignature[i]) {
        throw const CfbfException('Invalid CFBF signature');
      }
    }
    cursor.skip(16); // CLSID
    cursor.u16le(); // minor
    final int major = cursor.u16le();
    final int order = cursor.u16le();
    if (order != 0xFFFE) {
      throw CfbfException(
        'Unsupported CFBF byte order 0x${order.toRadixString(16)}',
      );
    }
    final int sectorShift = cursor.u16le();
    final int miniShift = cursor.u16le();
    cursor.skip(6);
    final int dirCount = cursor.u32le();
    final int fatCount = cursor.u32le();
    final int firstDir = cursor.u32le();
    cursor.u32le(); // transaction
    final int cutoff = cursor.u32le();
    final int firstMini = cursor.u32le();
    final int miniCount = cursor.u32le();
    final int firstDifat = cursor.u32le();
    final int difatCount = cursor.u32le();
    final List<int> headerDifat = <int>[];
    for (int i = 0; i < 109; i++) {
      headerDifat.add(cursor.u32le());
    }
    if (sectorShift != 9 && sectorShift != 12) {
      throw CfbfException('Unsupported sector shift $sectorShift');
    }
    return CfbfHeader(
      majorVersion: major,
      sectorShift: sectorShift,
      miniSectorShift: miniShift,
      directorySectorCount: dirCount,
      fatSectorCount: fatCount,
      firstDirectorySector: firstDir,
      miniStreamCutoff: cutoff == 0 ? 4096 : cutoff,
      firstMiniFatSector: firstMini,
      miniFatSectorCount: miniCount,
      firstDifatSector: firstDifat,
      difatSectorCount: difatCount,
      headerDifat: headerDifat,
    );
  }
}

/// Thrown when a CFBF file is corrupt or unsupported.
class CfbfException implements Exception {
  /// CfbfException API.
  const CfbfException(this.message);

  /// message API.
  final String message;

  @override
  /// toString API.
  String toString() => 'CfbfException: $message';
}

bool _cfbfNamesEqual(String a, String b) {
  if (a.length != b.length) {
    return false;
  }
  return cfbfNameKey(a) == cfbfNameKey(b);
}

DateTime? _filetimeToDate(Uint8List bytes) {
  var filetime = BigInt.zero;
  for (var index = 7; index >= 0; index--) {
    filetime = (filetime << 8) | BigInt.from(bytes[index]);
  }
  if (filetime == BigInt.zero) {
    return null;
  }
  final micros =
      (filetime - BigInt.parse('116444736000000000')) ~/ BigInt.from(10);
  return DateTime.fromMicrosecondsSinceEpoch(micros.toInt(), isUtc: true);
}
