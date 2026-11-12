// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Mohammed Asaad Asaad
// See third_party/quds_office_engine-MIT.txt.

import 'dart:typed_data';

import 'byte_source.dart';
import 'cfbf_reader.dart';

/// Builds a version-3 (512-byte sector) Compound File Binary.
class CfbfWriter {
  /// CfbfWriter API.
  CfbfWriter({
    Uint8List? clsid,
    this.stateBits = 0,
    DateTime? created,
    DateTime? modified,
    Uint8List? createdFiletime,
    Uint8List? modifiedFiletime,
  }) : clsid = _classId(clsid),
       createdFiletime = _filetime(created, createdFiletime),
       modifiedFiletime = _filetime(modified, modifiedFiletime) {
    _validateState(stateBits);
  }

  /// Root-storage CLSID (16 bytes). Defaults to all zeros.
  final Uint8List clsid;
  final int stateBits;
  final Uint8List createdFiletime;
  final Uint8List modifiedFiletime;

  /// Creates storages along [path] (e.g. `ObjectPool/obj1`).
  void addStorage(
    String path, {
    Uint8List? clsid,
    int stateBits = 0,
    DateTime? created,
    DateTime? modified,
    Uint8List? createdFiletime,
    Uint8List? modifiedFiletime,
  }) {
    final node = _ensureStorage(path);
    _metadata(
      node,
      clsid,
      stateBits,
      created,
      modified,
      createdFiletime,
      modifiedFiletime,
    );
  }

  /// Writes [data] at [path] (e.g. `Package` or `ObjectPool/obj1/CONTENTS`).
  void addStream(
    String path,
    List<int> data, {
    Uint8List? clsid,
    int stateBits = 0,
    DateTime? created,
    DateTime? modified,
    Uint8List? createdFiletime,
    Uint8List? modifiedFiletime,
  }) {
    final List<String> parts = _split(path);
    if (parts.isEmpty) {
      throw ArgumentError('Stream path must not be empty');
    }
    final String name = parts.removeLast();
    _Node parent = _virtualRoot;
    if (parts.isNotEmpty) {
      parent = _ensureStorage(parts.join('/'));
    }
    if (parent.children.keys.any(
      (other) => _cfbfNameCompare(other, name) == 0,
    )) {
      throw ArgumentError('Duplicate compound-file entry: $path');
    }
    final node = _Node.stream(name, Uint8List.fromList(data));
    _metadata(
      node,
      clsid,
      stateBits,
      created,
      modified,
      createdFiletime,
      modifiedFiletime,
    );
    parent.children[name] = node;
  }

  /// build API.
  Uint8List build() {
    final List<_DirDraft> drafts = <_DirDraft>[
      _DirDraft(
        name: 'Root Entry',
        type: CfbfObjectType.root,
        clsid: clsid,
        stateBits: stateBits,
        createdFiletime: createdFiletime,
        modifiedFiletime: modifiedFiletime,
      ),
    ];
    _flatten(_virtualRoot, drafts, 0);

    final int cutoff = 4096;
    final int sectorSize = 512;
    final int miniSize = 64;

    final List<Uint8List> regularChunks = <Uint8List>[];
    final BytesBuilder miniBuilder = BytesBuilder(copy: false);
    final List<int> miniFat = <int>[];

    void appendRegular(Uint8List data, _DirDraft draft) {
      if (data.isEmpty) {
        draft.startSector = cfbfEndOfChain;
        draft.streamSize = 0;
        draft.regularSectorCount = 0;
        return;
      }
      draft.startSector = regularChunks.length;
      draft.streamSize = data.length;
      int offset = 0;
      int count = 0;
      while (offset < data.length) {
        final int take = (data.length - offset) < sectorSize
            ? data.length - offset
            : sectorSize;
        final Uint8List sector = Uint8List(sectorSize);
        sector.setRange(0, take, data, offset);
        regularChunks.add(sector);
        offset += take;
        count++;
      }
      draft.regularSectorCount = count;
    }

    void appendMini(Uint8List data, _DirDraft draft) {
      if (data.isEmpty) {
        draft.startSector = cfbfEndOfChain;
        draft.streamSize = 0;
        return;
      }
      draft.startSector = miniFat.length;
      draft.streamSize = data.length;
      int offset = 0;
      while (offset < data.length) {
        final int take = (data.length - offset) < miniSize
            ? data.length - offset
            : miniSize;
        final int index = miniFat.length;
        miniBuilder.add(Uint8List.sublistView(data, offset, offset + take));
        if (take < miniSize) {
          miniBuilder.add(Uint8List(miniSize - take));
        }
        final bool last = offset + take >= data.length;
        miniFat.add(last ? cfbfEndOfChain : index + 1);
        offset += take;
      }
    }

    for (final _DirDraft draft in drafts) {
      if (draft.type != CfbfObjectType.stream) {
        continue;
      }
      final Uint8List data = draft.data ?? Uint8List(0);
      if (data.length < cutoff) {
        appendMini(data, draft);
      } else {
        appendRegular(data, draft);
      }
    }

    final Uint8List miniStreamBytes = miniBuilder.takeBytes();
    final _DirDraft root = drafts[0];
    appendRegular(miniStreamBytes, root);

    final Uint8List miniFatBytes = _encodeFat(miniFat, sectorSize);
    final Uint8List directoryBytes = _encodeDirectory(drafts, sectorSize);

    final int dataSectors = regularChunks.length;
    final int miniFatSectors = miniFatBytes.isEmpty
        ? 0
        : (miniFatBytes.length + sectorSize - 1) ~/ sectorSize;
    final int dirSectors =
        (directoryBytes.length + sectorSize - 1) ~/ sectorSize;

    int fatSectors = 0;
    int difatSectors = 0;
    for (int i = 0; i < 8; i++) {
      final int total =
          dataSectors + miniFatSectors + dirSectors + fatSectors + difatSectors;
      final int newFat = (total + 127) ~/ 128;
      final int extra = newFat > 109 ? newFat - 109 : 0;
      final int newDifat = extra == 0 ? 0 : (extra + 126) ~/ 127;
      if (newFat == fatSectors && newDifat == difatSectors) {
        break;
      }
      fatSectors = newFat;
      difatSectors = newDifat;
    }

    final int miniFatStart = miniFatSectors == 0 ? cfbfEndOfChain : dataSectors;
    final int dirStart = dataSectors + miniFatSectors;
    final int fatStart = dirStart + dirSectors;
    final int difatStart = difatSectors == 0
        ? cfbfEndOfChain
        : fatStart + fatSectors;

    root.streamSize = miniStreamBytes.length;
    if (miniStreamBytes.isEmpty) {
      root.startSector = cfbfEndOfChain;
      root.regularSectorCount = 0;
    }

    final List<int> fat = List<int>.filled(fatSectors * 128, cfbfFreeSect);
    void chainSectors(int start, int count) {
      if (count <= 0 || start == cfbfEndOfChain) {
        return;
      }
      for (int i = 0; i < count; i++) {
        fat[start + i] = i == count - 1 ? cfbfEndOfChain : start + i + 1;
      }
    }

    for (final _DirDraft draft in drafts) {
      if (draft.regularSectorCount > 0) {
        chainSectors(draft.startSector, draft.regularSectorCount);
      }
    }
    chainSectors(miniFatStart, miniFatSectors);
    chainSectors(dirStart, dirSectors);
    for (int i = 0; i < fatSectors; i++) {
      fat[fatStart + i] = cfbfFatSect;
    }
    if (difatSectors > 0) {
      for (int i = 0; i < difatSectors; i++) {
        fat[difatStart + i] = cfbfDifatSect;
      }
    }

    final List<int> fatSectorIds = <int>[
      for (int i = 0; i < fatSectors; i++) fatStart + i,
    ];

    final ByteSink sink = ByteSink(capacity: 512 + fat.length * 4);
    _writeHeader(
      sink,
      fatSectorCount: fatSectors,
      firstDirectorySector: dirStart,
      firstMiniFatSector: miniFatStart,
      miniFatSectorCount: miniFatSectors,
      firstDifatSector: difatStart,
      difatSectorCount: difatSectors,
      fatSectorIds: fatSectorIds,
    );

    for (final Uint8List chunk in regularChunks) {
      sink.add(chunk);
    }
    if (miniFatSectors > 0) {
      sink.add(_padTo(miniFatBytes, miniFatSectors * sectorSize));
    }
    sink.add(_padTo(directoryBytes, dirSectors * sectorSize));
    sink.add(_encodeFat(fat, sectorSize));
    if (difatSectors > 0) {
      sink.add(
        _encodeDifatChain(
          fatSectorIds.skip(109).toList(),
          difatStart,
          sectorSize,
        ),
      );
    }

    return sink.takeBytes();
  }

  /// storage API.
  final _Node _virtualRoot = _Node.storage('Root Entry');

  _Node _ensureStorage(String path) {
    _Node current = _virtualRoot;
    for (final String part in _split(path)) {
      final keys = current.children.keys.where(
        (name) => _cfbfNameCompare(name, part) == 0,
      );
      final key = keys.isEmpty ? part : keys.first;
      current = current.children.putIfAbsent(key, () => _Node.storage(part));
      if (current.kind != CfbfObjectType.storage) {
        throw StateError('Path component $part is not a storage');
      }
    }
    return current;
  }

  static List<String> _split(String path) {
    final parts = path.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.length > 128 ||
        parts.any(
          (part) => part.length > 31 || part.contains(RegExp(r'[\\:!\x00]')),
        )) {
      throw ArgumentError('Invalid compound-file path');
    }
    return parts;
  }

  static void _flatten(_Node parent, List<_DirDraft> drafts, int parentIndex) {
    if (parent.children.isEmpty) {
      drafts[parentIndex].child = cfbfNoStream;
      return;
    }
    final List<int> childIndexes = <int>[];
    final List<String> names = parent.children.keys.toList()
      ..sort(_cfbfNameCompare);
    for (final String name in names) {
      final _Node node = parent.children[name]!;
      final int index = drafts.length;
      drafts.add(
        _DirDraft(
          name: node.name,
          type: node.kind,
          data: node.data,
          clsid: node.clsid,
          stateBits: node.stateBits,
          createdFiletime: node.createdFiletime,
          modifiedFiletime: node.modifiedFiletime,
        ),
      );
      childIndexes.add(index);
      if (node.kind == CfbfObjectType.storage) {
        _flatten(node, drafts, index);
      }
    }
    drafts[parentIndex].child = _buildBalancedTree(drafts, childIndexes);
  }

  static int _buildBalancedTree(List<_DirDraft> drafts, List<int> indexes) {
    if (indexes.isEmpty) {
      return cfbfNoStream;
    }
    int build(int lo, int hi) {
      if (lo > hi) {
        return cfbfNoStream;
      }
      final int mid = (lo + hi) >> 1;
      final int index = indexes[mid];
      drafts[index].left = build(lo, mid - 1);
      drafts[index].right = build(mid + 1, hi);
      drafts[index].black = true;
      return index;
    }

    return build(0, indexes.length - 1);
  }

  static Uint8List _encodeDirectory(List<_DirDraft> drafts, int sectorSize) {
    final ByteSink sink = ByteSink(capacity: drafts.length * 128);
    for (final _DirDraft draft in drafts) {
      _writeDirectoryEntry(sink, draft);
    }
    return _padTo(sink.takeBytes(), _align(drafts.length * 128, sectorSize));
  }

  static void _writeDirectoryEntry(ByteSink sink, _DirDraft draft) {
    final Uint8List name = Uint8List(64);
    final String text = draft.name;
    int units = 0;
    for (int i = 0; i < text.length && i < 31; i++) {
      final int unit = text.codeUnitAt(i);
      name[i * 2] = unit & 0xFF;
      name[i * 2 + 1] = (unit >> 8) & 0xFF;
      units = i + 1;
    }
    final int nameLen = (units + 1) * 2;
    sink.add(name);
    sink.u16le(nameLen);
    sink.u8(switch (draft.type) {
      CfbfObjectType.empty => 0,
      CfbfObjectType.storage => 1,
      CfbfObjectType.stream => 2,
      CfbfObjectType.root => 5,
    });
    sink.u8(draft.black ? 1 : 0);
    sink.u32le(draft.left);
    sink.u32le(draft.right);
    sink.u32le(draft.child);
    sink.add(draft.clsid);
    sink.u32le(draft.stateBits);
    sink.add(draft.createdFiletime);
    sink.add(draft.modifiedFiletime);
    sink.u32le(draft.startSector);
    sink.u64le(draft.streamSize);
  }

  static Uint8List _encodeFat(List<int> fat, int sectorSize) {
    if (fat.isEmpty) {
      return Uint8List(0);
    }
    final int entriesPerSector = sectorSize ~/ 4;
    final int padded = _align(fat.length, entriesPerSector);
    final ByteSink sink = ByteSink(capacity: padded * 4);
    for (int i = 0; i < padded; i++) {
      sink.u32le(i < fat.length ? fat[i] : cfbfFreeSect);
    }
    return sink.takeBytes();
  }

  static Uint8List _encodeDifatChain(
    List<int> extraFatSectors,
    int firstDifatSector,
    int sectorSize,
  ) {
    final int perSector = (sectorSize ~/ 4) - 1;
    final int sectorCount = extraFatSectors.isEmpty
        ? 0
        : (extraFatSectors.length + perSector - 1) ~/ perSector;
    final ByteSink sink = ByteSink(capacity: sectorCount * sectorSize);
    int cursor = 0;
    for (int s = 0; s < sectorCount; s++) {
      for (int i = 0; i < perSector; i++) {
        if (cursor < extraFatSectors.length) {
          sink.u32le(extraFatSectors[cursor++]);
        } else {
          sink.u32le(cfbfFreeSect);
        }
      }
      final int next = s == sectorCount - 1
          ? cfbfEndOfChain
          : firstDifatSector + s + 1;
      sink.u32le(next);
    }
    return sink.takeBytes();
  }

  static void _writeHeader(
    ByteSink sink, {
    required int fatSectorCount,
    required int firstDirectorySector,
    required int firstMiniFatSector,
    required int miniFatSectorCount,
    required int firstDifatSector,
    required int difatSectorCount,
    required List<int> fatSectorIds,
  }) {
    sink.add(cfbfSignature);
    sink.add(Uint8List(16));
    sink.u16le(0x003E);
    sink.u16le(3);
    sink.u16le(0xFFFE);
    sink.u16le(9);
    sink.u16le(6);
    sink.add(Uint8List(6));
    sink.u32le(0);
    sink.u32le(fatSectorCount);
    sink.u32le(firstDirectorySector);
    sink.u32le(0);
    sink.u32le(4096);
    sink.u32le(firstMiniFatSector);
    sink.u32le(miniFatSectorCount);
    sink.u32le(firstDifatSector);
    sink.u32le(difatSectorCount);
    for (int i = 0; i < 109; i++) {
      sink.u32le(i < fatSectorIds.length ? fatSectorIds[i] : cfbfFreeSect);
    }
  }

  static Uint8List _padTo(Uint8List data, int length) {
    if (data.length == length) {
      return data;
    }
    if (data.length > length) {
      return Uint8List.sublistView(data, 0, length);
    }
    final Uint8List out = Uint8List(length);
    out.setRange(0, data.length, data);
    return out;
  }

  static int _align(int value, int alignment) {
    final int rem = value % alignment;
    return rem == 0 ? value : value + (alignment - rem);
  }

  static void _metadata(
    _Node node,
    Uint8List? clsid,
    int stateBits,
    DateTime? created,
    DateTime? modified,
    Uint8List? createdRaw,
    Uint8List? modifiedRaw,
  ) {
    _validateState(stateBits);
    node.clsid = _classId(clsid);
    node.stateBits = stateBits;
    node.createdFiletime = _filetime(created, createdRaw);
    node.modifiedFiletime = _filetime(modified, modifiedRaw);
  }

  static void _validateState(int value) {
    if (value < 0 || value > 0xffffffff) {
      throw ArgumentError.value(value, 'stateBits');
    }
  }

  static Uint8List _classId(Uint8List? value) {
    if (value != null && value.length != 16) {
      throw ArgumentError('A compound CLSID must have 16 bytes');
    }
    return Uint8List.fromList(value ?? Uint8List(16)).asUnmodifiableView();
  }

  static Uint8List _filetime(DateTime? value, Uint8List? raw) {
    if (raw != null) {
      if (raw.length != 8) throw ArgumentError('A FILETIME must have 8 bytes');
      return Uint8List.fromList(raw).asUnmodifiableView();
    }
    if (value == null) return Uint8List(8).asUnmodifiableView();
    var ticks =
        BigInt.from(value.toUtc().microsecondsSinceEpoch) * BigInt.from(10) +
        BigInt.parse('116444736000000000');
    if (ticks < BigInt.zero || ticks.bitLength > 64) {
      throw ArgumentError.value(value, 'FILETIME');
    }
    final bytes = Uint8List(8);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = (ticks & BigInt.from(255)).toInt();
      ticks >>= 8;
    }
    return bytes.asUnmodifiableView();
  }
}

class _Node {
  /// storage API.
  _Node.storage(this.name)
    : kind = CfbfObjectType.storage,
      data = null,
      children = <String, _Node>{};

  /// stream API.
  _Node.stream(this.name, this.data)
    : kind = CfbfObjectType.stream,
      children = <String, _Node>{};

  /// name API.
  final String name;

  /// kind API.
  final CfbfObjectType kind;

  /// data API.
  final Uint8List? data;

  /// children API.
  final Map<String, _Node> children;
  Uint8List clsid = Uint8List(16);
  int stateBits = 0;
  Uint8List createdFiletime = Uint8List(8);
  Uint8List modifiedFiletime = Uint8List(8);
}

class _DirDraft {
  _DirDraft({
    required this.name,
    required this.type,
    this.data,
    required this.clsid,
    required this.stateBits,
    required this.createdFiletime,
    required this.modifiedFiletime,
  });

  /// name API.
  final String name;

  /// type API.
  final CfbfObjectType type;

  /// data API.
  final Uint8List? data;

  /// clsid API.
  final Uint8List clsid;
  final int stateBits;
  final Uint8List createdFiletime;
  final Uint8List modifiedFiletime;

  /// left API.
  int left = cfbfNoStream;

  /// right API.
  int right = cfbfNoStream;

  /// child API.
  int child = cfbfNoStream;

  /// black API.
  bool black = true;

  /// startSector API.
  int startSector = cfbfEndOfChain;

  /// streamSize API.
  int streamSize = 0;

  /// regularSectorCount API.
  int regularSectorCount = 0;
}

int _cfbfNameCompare(String a, String b) {
  final lengthDifference = a.length - b.length;
  if (lengthDifference != 0) return lengthDifference;

  /// au API.
  final String au = a.toUpperCase();

  /// bu API.
  final String bu = b.toUpperCase();

  /// minLen API.
  final int minLen = au.length < bu.length ? au.length : bu.length;
  for (int i = 0; i < minLen; i++) {
    final int d = au.codeUnitAt(i) - bu.codeUnitAt(i);
    if (d != 0) {
      return d;
    }
  }
  return au.length - bu.length;
}
