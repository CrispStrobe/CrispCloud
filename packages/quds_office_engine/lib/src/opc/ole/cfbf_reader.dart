import 'dart:typed_data';

import '../../io/byte_source.dart';

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
    required this.startSector,
    required this.streamSize,
  });

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
class CfbfFile {
  CfbfFile._({
    required this.source,
    required this.header,
    required this.fat,
    required this.miniFat,
    required this.entries,
  });

  /// source API.
  final ByteSource source;

  /// header API.
  final CfbfHeader header;

  /// fat API.
  final List<int> fat;

  /// miniFat API.
  final List<int> miniFat;

  /// entries API.
  final List<CfbfDirectoryEntry> entries;

  /// root API.
  CfbfDirectoryEntry get root => entries.firstWhere(
    (CfbfDirectoryEntry e) => e.type == CfbfObjectType.root,
  );

  /// open API.
  factory CfbfFile.open(ByteSource source) {
    final CfbfHeader header = CfbfHeader.parse(source);
    final List<int> fat = _readFat(source, header);
    final List<CfbfDirectoryEntry> entries = _readDirectory(
      source,
      header,
      fat,
    );
    final List<int> miniFat = _readMiniFat(source, header, fat);
    return CfbfFile._(
      source: source,
      header: header,
      fat: fat,
      miniFat: miniFat,
      entries: entries,
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

  /// readEntry API.
  Uint8List readEntry(CfbfDirectoryEntry entry) {
    if (entry.streamSize == 0) {
      return Uint8List(0);
    }
    final bool mini =
        entry.type != CfbfObjectType.root &&
        entry.streamSize < header.miniStreamCutoff;
    if (mini) {
      return _readMiniStream(entry);
    }
    return _readFatStream(entry.startSector, entry.streamSize);
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
    final Uint8List out = Uint8List(size);
    int remaining = size;
    int written = 0;
    int sector = startSector;
    final int sectorSize = header.sectorSize;
    final Set<int> guard = <int>{};
    while (remaining > 0 && sector != cfbfEndOfChain) {
      if (!guard.add(sector)) {
        throw const CfbfException('FAT cycle detected');
      }
      final int offset = header.sectorOffset(sector);
      final int take = remaining < sectorSize ? remaining : sectorSize;
      out.setRange(written, written + take, source.view(offset, take));
      written += take;
      remaining -= take;
      if (sector >= fat.length) {
        throw CfbfException('FAT index $sector out of range (${fat.length})');
      }
      sector = fat[sector];
    }
    if (remaining != 0) {
      throw CfbfException('Truncated FAT stream: $remaining bytes missing');
    }
    return out;
  }

  Uint8List _readMiniStream(CfbfDirectoryEntry entry) {
    final Uint8List miniContainer = _readFatStream(
      root.startSector,
      root.streamSize,
    );
    final Uint8List out = Uint8List(entry.streamSize);
    int remaining = entry.streamSize;
    int written = 0;
    int sector = entry.startSector;
    final int miniSize = header.miniSectorSize;
    final Set<int> guard = <int>{};
    while (remaining > 0 && sector != cfbfEndOfChain) {
      if (!guard.add(sector)) {
        throw const CfbfException('MiniFAT cycle detected');
      }
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
      if (sector >= miniFat.length) {
        throw CfbfException('MiniFAT index $sector out of range');
      }
      sector = miniFat[sector];
    }
    if (remaining != 0) {
      throw CfbfException('Truncated MiniFAT stream: $remaining bytes missing');
    }
    return out;
  }

  static List<int> _readFat(ByteSource source, CfbfHeader header) {
    final List<int> difat = List<int>.from(header.headerDifat);
    int difatSector = header.firstDifatSector;
    final Set<int> guard = <int>{};
    while (difatSector != cfbfEndOfChain && difatSector != cfbfFreeSect) {
      if (!guard.add(difatSector)) {
        throw const CfbfException('DIFAT cycle detected');
      }
      final int offset = header.sectorOffset(difatSector);
      final ByteCursor cursor = ByteCursor.view(
        source,
        offset,
        header.sectorSize,
      );
      final int entriesPerSector = header.sectorSize ~/ 4;
      for (int i = 0; i < entriesPerSector - 1; i++) {
        difat.add(cursor.u32le());
      }
      difatSector = cursor.u32le();
    }

    final List<int> fat = <int>[];
    int fatSectorsSeen = 0;
    for (final int fatSector in difat) {
      if (fatSector == cfbfFreeSect || fatSector == cfbfEndOfChain) {
        continue;
      }
      fatSectorsSeen++;
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
    if (header.fatSectorCount != 0 && fatSectorsSeen != header.fatSectorCount) {
      // Some writers leave unused DIFAT slots; tolerate extra FREESECT.
    }
    return fat;
  }

  static List<CfbfDirectoryEntry> _readDirectory(
    ByteSource source,
    CfbfHeader header,
    List<int> fat,
  ) {
    final List<int> chain = _followChain(fat, header.firstDirectorySector);
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
      entries.add(_parseDirectoryEntry(raw, offset, index));
    }
    return entries;
  }

  static List<int> _readMiniFat(
    ByteSource source,
    CfbfHeader header,
    List<int> fat,
  ) {
    if (header.miniFatSectorCount == 0 ||
        header.firstMiniFatSector == cfbfEndOfChain) {
      return <int>[];
    }
    final List<int> chain = _followChain(fat, header.firstMiniFatSector);
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

  static List<int> _followChain(List<int> fat, int start) {
    final List<int> chain = <int>[];
    final Set<int> seen = <int>{};
    int sector = start;
    while (sector != cfbfEndOfChain && sector != cfbfFreeSect) {
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
    final int createdRaw = cursor.u64le();
    final int modifiedRaw = cursor.u64le();
    final int start = cursor.u32le();
    final int size = cursor.u64le();

    final int charCount = nameLen ~/ 2;
    final StringBuffer name = StringBuffer();
    for (int i = 0; i < charCount && i < 32; i++) {
      final int unit = nameBytes[i * 2] | (nameBytes[i * 2 + 1] << 8);
      if (unit == 0) {
        break;
      }
      name.writeCharCode(unit);
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
  return a.toUpperCase() == b.toUpperCase();
}

DateTime? _filetimeToDate(int filetime) {
  if (filetime == 0) {
    return null;
  }

  /// epochDiff API.
  const int epochDiff = 116444736000000000;

  /// micros API.
  final int micros = (filetime - epochDiff) ~/ 10;
  return DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true);
}
