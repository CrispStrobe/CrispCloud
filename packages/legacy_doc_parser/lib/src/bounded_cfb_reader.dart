// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'compound/cfbf_reader.dart'
    show CfbfDirectoryEntry, CfbfFile, CfbfObjectType;

export 'compound/cfbf_reader.dart' show CfbfDirectoryEntry, CfbfObjectType;

/// Resource-bounded access to the MIT office engine's compound-file reader.
///
/// Validate allocation tables before the underlying reader materializes them.
/// In particular, repeated DIFAT references must not expand a tiny file into a
/// very large FAT, and untrusted stream sizes must never drive allocations.
class BoundedCfbReader {
  BoundedCfbReader(
    Uint8List bytes, {
    int maxFileBytes = 64 * 1024 * 1024,
    this.maxStreamBytes = 32 * 1024 * 1024,
    this.maxTotalReadBytes = 64 * 1024 * 1024,
  }) {
    if (bytes.length > maxFileBytes) {
      throw const FormatException(
        'Compound file exceeds the preview size limit',
      );
    }
    _preflight(bytes);
    _file = CfbfFile.fromBytes(bytes);
    if (_file.entries.length > 65536 ||
        _file.entries
                .where((entry) => entry.type == CfbfObjectType.root)
                .length !=
            1) {
      throw const FormatException('Invalid compound-file directory');
    }
    for (final entry in _file.entries) {
      if ((entry.isStream || entry.type == CfbfObjectType.root) &&
          (entry.streamSize < 0 || entry.streamSize > bytes.length)) {
        throw const FormatException('Compound stream exceeds its container');
      }
    }
    _indexDirectory();
  }

  late final CfbfFile _file;
  final int maxStreamBytes;
  final int maxTotalReadBytes;
  int _readBytes = 0;
  Uint8List? _miniContainer;
  final Map<int, List<CfbfDirectoryEntry>> _children = {};
  final Map<int, Map<String, CfbfDirectoryEntry>> _names = {};

  CfbfDirectoryEntry get root => _file.root;

  List<CfbfDirectoryEntry> childrenOf(CfbfDirectoryEntry parent) =>
      _children[parent.index] ?? const [];

  /// Looks only in this storage, never in an unrelated embedded message.
  CfbfDirectoryEntry? child(CfbfDirectoryEntry parent, String name) {
    return _names[parent.index]?[name.toUpperCase()];
  }

  /// Compound storages own disjoint sibling trees. Validate this once before
  /// any consumer can repeatedly traverse them. Without global ownership, a
  /// small malicious MSG could make thousands of recipients share one large
  /// child tree and turn otherwise bounded property lookups into quadratic
  /// work on the UI thread.
  void _indexDirectory() {
    const noStream = 0xffffffff;
    final entries = _file.entries;
    final rootEntry = root;
    if (rootEntry.index != 0 ||
        rootEntry.leftSibling != noStream ||
        rootEntry.rightSibling != noStream) {
      throw const FormatException('Invalid compound root storage');
    }
    final owners = <int, int>{rootEntry.index: -1};
    final storages = <CfbfDirectoryEntry>[rootEntry];
    for (var cursor = 0; cursor < storages.length; cursor++) {
      final parent = storages[cursor];
      final children = <CfbfDirectoryEntry>[];
      final names = <String, CfbfDirectoryEntry>{};
      final stack = <int>[parent.child];
      while (stack.isNotEmpty) {
        final index = stack.removeLast();
        if (index == noStream) continue;
        if (index < 0 || index >= entries.length || owners.containsKey(index)) {
          throw const FormatException(
            'Compound directory has a cycle or shared child',
          );
        }
        owners[index] = parent.index;
        final entry = entries[index];
        if (entry.type == CfbfObjectType.empty ||
            entry.type == CfbfObjectType.root ||
            entry.name.isEmpty ||
            names.containsKey(entry.name.toUpperCase())) {
          throw const FormatException(
            'Invalid or duplicate compound directory entry',
          );
        }
        if (!entry.isStorage && entry.child != noStream) {
          throw const FormatException('Compound stream cannot have children');
        }
        children.add(entry);
        names[entry.name.toUpperCase()] = entry;
        if (entry.isStorage) storages.add(entry);
        stack.add(entry.leftSibling);
        stack.add(entry.rightSibling);
      }
      _children[parent.index] = List.unmodifiable(children);
      _names[parent.index] = Map.unmodifiable(names);
    }
  }

  Uint8List? readPath(String path) {
    final parts = path.split('/').where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) return null;
    var current = root;
    for (var index = 0; index < parts.length; index++) {
      final entry = child(current, parts[index]);
      if (entry == null) return null;
      if (index == parts.length - 1) {
        return entry.isStream ? readEntry(entry) : null;
      }
      if (!entry.isStorage) return null;
      current = entry;
    }
    return null;
  }

  Uint8List readEntry(CfbfDirectoryEntry entry) {
    if (!entry.isStream ||
        entry.streamSize > maxStreamBytes ||
        _readBytes + entry.streamSize > maxTotalReadBytes) {
      throw const FormatException(
        'Compound stream exceeds the preview size limit',
      );
    }
    _readBytes += entry.streamSize;
    if (entry.streamSize > 0 && entry.streamSize < 4096) {
      // The engine re-reads the entire mini-stream container for each small
      // property. Cache it once so a message with many headers is still linear
      // in the file size, instead of repeatedly allocating that container.
      final container = _miniContainer ??= _file.readEntry(root);
      final result = Uint8List(entry.streamSize);
      final seen = <int>{};
      var sector = entry.startSector;
      var written = 0;
      while (written < result.length) {
        final count = (result.length - written).clamp(0, 64);
        final offset = sector * 64;
        if (!seen.add(sector) ||
            sector >= _file.miniFat.length ||
            offset < 0 ||
            offset + count > container.length) {
          throw const FormatException('Invalid compound mini-stream chain');
        }
        result.setRange(written, written + count, container, offset);
        written += count;
        sector = _file.miniFat[sector];
      }
      return result;
    }
    return _file.readEntry(entry);
  }

  static void _preflight(Uint8List bytes) {
    const free = 0xffffffff;
    const end = 0xfffffffe;
    if (bytes.length < 512 || !CfbfFile.isCfbf(bytes)) {
      throw const FormatException('Not a compound document');
    }
    final data = ByteData.sublistView(bytes);
    int u16(int offset) => data.getUint16(offset, Endian.little);
    int u32(int offset) => data.getUint32(offset, Endian.little);
    final major = u16(26);
    final shift = u16(30);
    if (u16(28) != 0xfffe ||
        !((major == 3 && shift == 9) || (major == 4 && shift == 12)) ||
        u16(32) != 6 ||
        u32(56) != 4096) {
      throw const FormatException('Unsupported compound-file header');
    }
    final size = 1 << shift;
    final sectors = bytes.length ~/ size - 1;
    if (sectors < 1) {
      throw const FormatException('Truncated compound file');
    }
    int offsetOf(int sector) {
      if (sector < 0 || sector >= sectors) {
        throw const FormatException('Compound sector outside its container');
      }
      return (sector + 1) * size;
    }

    final fatSectors = <int>[];
    final seenFat = <int>{};
    void addFat(int sector) {
      if (sector == free) return;
      offsetOf(sector);
      if (!seenFat.add(sector)) {
        throw const FormatException('Repeated compound allocation table');
      }
      fatSectors.add(sector);
      if (fatSectors.length > (sectors + size ~/ 4 - 1) ~/ (size ~/ 4)) {
        throw const FormatException('Oversized compound allocation table');
      }
    }

    for (var index = 0; index < 109; index++) {
      addFat(u32(76 + index * 4));
    }
    var difat = u32(68);
    final seenDifat = <int>{};
    while (difat != end && difat != free) {
      if (!seenDifat.add(difat)) {
        throw const FormatException('Compound allocation-table cycle');
      }
      final start = offsetOf(difat);
      for (var index = 0; index < size ~/ 4 - 1; index++) {
        addFat(u32(start + index * 4));
      }
      difat = u32(start + size - 4);
    }
    if (fatSectors.length != u32(44) || seenDifat.length != u32(72)) {
      throw const FormatException('Inconsistent compound allocation tables');
    }
    final fat = <int>[
      for (final sector in fatSectors)
        for (var index = 0; index < size ~/ 4; index++)
          u32(offsetOf(sector) + index * 4),
    ];
    List<int> checkChain(int sector, int limit) {
      final seen = <int>{};
      while (sector != end && sector != free) {
        offsetOf(sector);
        if (sector >= fat.length || !seen.add(sector) || seen.length > limit) {
          throw const FormatException(
            'Invalid or oversized compound sector chain',
          );
        }
        sector = fat[sector];
      }
      return seen.toList(growable: false);
    }

    final directory = checkChain(u32(48), 65536 ~/ (size ~/ 128));
    for (final sector in directory) {
      final offset = offsetOf(sector);
      for (var index = 0; index < size; index += 128) {
        final type = bytes[offset + index + 66];
        if ((type == 2 || type == 5) &&
            (u32(offset + index + 124) != 0 ||
                u32(offset + index + 120) > bytes.length)) {
          // All preview inputs are smaller than 4 GiB. Check the raw high word
          // too: JavaScript integer bit operations cannot represent uint64.
          throw const FormatException('Compound stream exceeds its container');
        }
      }
    }
    if (u32(64) > 0) checkChain(u32(60), sectors);
  }
}
