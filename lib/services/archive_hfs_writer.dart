import 'dart:convert';
import 'dart:typed_data';

import 'package:koni_archive/koni_archive.dart' as koni;

import 'archive_hfs_reader.dart';
import 'archive_streaming_unsupported.dart';
import 'archive_types.dart';
import 'archive_write_model.dart';

const _blockSize = 4096;
const _maxCatalogBytes = 32 * 1024 * 1024;
const _maxEntries = 100000;
const _hfsEpoch = 2082844800;
const _dateAttributes = {
  'hfs.created',
  'hfs.attributesModified',
  'hfs.accessed',
  'hfs.backedUp',
};

/// Existing images can contain forks, attributes and links outside the file
/// view. Creation does not establish that those structures can be rewritten.
Future<ArchiveRewriteInspection> inspectHfsRewrite(
  Uint8List bytes,
  ViewerArchive archive,
) async => ArchiveRewriteInspection(
  reason:
      'Existing HFS images remain read-only. Create a new HFSX data image from '
      'regular files and folders; resource forks, attributes and links are not '
      'preserved by this creator.',
);

/// Verifies the exact HFSX data-volume layout produced by this writer, while
/// retaining supported dates, modes and the volume label. Every byte outside
/// regular data forks must match the regenerated plan, including both volume
/// headers, all tree nodes, allocation bits, file slack and unused blocks.
/// The CrC1 identifier is only a profile hint, never the preservation proof.
/// [source] and [opened] remain caller-owned, including on failure.
Future<ArchiveRewriteInspection> inspectHfsRewriteSource(
  koni.ByteSource source,
  HfsArchiveOpen opened, {
  int maxBytes = kArchiveStreamingLimit,
  bool Function()? isCancelled,
}) async {
  void check() {
    if (isCancelled?.call() ?? false) {
      throw const ArchiveViewException('HFS inspection was cancelled.');
    }
  }

  check();
  if (maxBytes <= 0 || maxBytes > kArchiveStreamingLimit) {
    throw ArgumentError.value(maxBytes, 'maxBytes');
  }
  if (source.length > maxBytes || opened.archive.formatName != 'hfsx') {
    throw const ArchiveStreamingUnsupported(
      'Only a bounded canonical HFSX data volume can be rewritten.',
    );
  }
  final archive = opened.archive;
  final profile = _VerifiedHfsProfile(opened.metadata, {
    for (final member in archive.members) member.name: _date(member.modified!),
  });
  final entries = <ArchiveWriteEntry>[];
  for (final member in archive.members) {
    check();
    if (member.isSpecial || member.isEncrypted || member.pathEscapedRoot) {
      throw const ArchiveStreamingUnsupported(
        'Special filesystem entries cannot be rewritten as data files.',
      );
    }
    entries.add(
      ArchiveWriteEntry(
        path: member.name,
        isDirectory: !member.isFile,
        size: member.size,
        modified: member.modified,
        mode: member.posixMode,
        attributes: opened.metadata.attributes[member.name] ?? const {},
        readChunks: member.isFile
            ? () => archive.openMember(member, maxBytes: maxBytes)
            : null,
      ),
    );
  }
  final _HfsPlan plan;
  try {
    plan = _HfsPlan(
      entries,
      opened.metadata.volumeName,
      maxBytes,
      preserved: profile,
    );
  } on ArchiveViewException catch (error) {
    throw ArchiveStreamingUnsupported(
      'The HFSX metadata cannot be regenerated safely: ${error.message}',
    );
  }
  if (source.length != plan.totalBlocks * _blockSize) {
    throw const ArchiveStreamingUnsupported(
      'The HFSX volume has a noncanonical allocation layout or extra data.',
    );
  }
  var offset = 0;
  Future<void> compare(List<int> expected) async {
    for (var at = 0; at < expected.length; at += 256 * 1024) {
      check();
      final count = expected.length - at < 256 * 1024
          ? expected.length - at
          : 256 * 1024;
      final actual = await source.read(offset, count);
      check();
      if (actual.length != count) {
        throw const ArchiveViewException('The HFSX volume is truncated.');
      }
      for (var i = 0; i < count; i++) {
        if (actual[i] != expected[at + i]) {
          throw const ArchiveStreamingUnsupported(
            'The HFSX volume contains metadata, padding or unused data that '
            'this writer cannot preserve.',
          );
        }
      }
      offset += count;
    }
  }

  await _emitHfsPlan(
    plan,
    emit: compare,
    writeFile: (item) async {
      check();
      // The already-compared catalog fixes this file's start and exact size.
      // Only its logical data bytes are excluded from metadata comparison.
      offset += item.size;
    },
  );
  check();
  if (offset != source.length) {
    throw StateError('HFS preservation inspection did not cover the volume.');
  }
  return ArchiveRewriteInspection(
    container: {'package.kind': 'hfsx', 'hfs.profile': profile},
    attributes: opened.metadata.attributes,
  );
}

// A direct caller cannot authorize rewriting with a marker or an empty
// ArchiveRewriteInspection. This token is returned only after full comparison.
class _VerifiedHfsProfile {
  _VerifiedHfsProfile(this.metadata, Map<String, int> modified)
    : modified = Map.unmodifiable(modified);
  final HfsArchiveMetadata metadata;
  final Map<String, int> modified;
}

/// Checks the auxiliary metadata after a candidate has passed the complete
/// canonical inspection again. Namespace, content hashes, modification times
/// and modes are also checked by the workspace's normal verification path.
void verifyHfsRewritePreservation(
  List<ArchiveWriteEntry> entries,
  ArchiveRewriteInspection actual, {
  ArchiveRewriteInspection? source,
}) {
  Never mismatch() => throw const ArchiveViewException(
    'Rewritten HFSX volume metadata does not match the planned preservation.',
  );
  final actualProfile = actual.container['hfs.profile'];
  final sourceProfile = source?.container['hfs.profile'];
  if (!actual.supported ||
      actualProfile is! _VerifiedHfsProfile ||
      source != null &&
          (!source.supported || sourceProfile is! _VerifiedHfsProfile)) {
    mismatch();
  }
  final metadata = actualProfile.metadata;
  if (sourceProfile is _VerifiedHfsProfile) {
    final previous = sourceProfile.metadata;
    if (metadata.volumeName != previous.volumeName ||
        metadata.volumeCreated != previous.volumeCreated ||
        metadata.volumeModified != previous.volumeModified ||
        metadata.volumeBackup != previous.volumeBackup ||
        metadata.volumeChecked != previous.volumeChecked ||
        metadata.rootModified != previous.rootModified ||
        metadata.rootMode != previous.rootMode ||
        !_sameAttributes(metadata.rootAttributes, previous.rootAttributes)) {
      mismatch();
    }
  }
  for (final entry in entries) {
    final path = normalizeHfsArchivePath(entry.path);
    final attrs = metadata.attributes[path];
    final modified = entry.modified == null
        ? actualProfile.modified[path]
        : _date(entry.modified!);
    if (attrs == null || modified == null || attrs.length != 4) mismatch();
    if (entry.attributes.keys.any((key) => !_dateAttributes.contains(key))) {
      mismatch();
    }
    for (final key in _dateAttributes) {
      if (attrs[key] !=
          _dateAttribute(
            entry.attributes,
            key,
            key == 'hfs.backedUp' ? 0 : modified,
          )) {
        mismatch();
      }
    }
  }
}

bool _sameAttributes(Map<String, Object?> first, Map<String, Object?> second) =>
    first.length == second.length &&
    first.entries.every((item) => second[item.key] == item.value);

/// HFSX compares decomposed UTF-16 names, preserving case. This normalization
/// is frozen to Unicode 3.2 with the HFS exclusions in Apple's TN1150; current
/// platform NFD routines are not equivalent. Supplementary pairs stay intact.
String normalizeHfsArchivePath(String path) =>
    path.split('/').map(_normalizeName).join('/');

/// Creates a fresh, unjournaled, case-sensitive HFSX data volume. The complete
/// layout is planned from captured lengths before writing; file contents and
/// free space are streamed without retaining a whole file or image in memory.
///
/// Supports regular data forks, directories, POSIX modes and modification
/// times. Unsupported attributes/types are rejected rather than discarded.
/// The sink is caller-owned; a failed/cancelled output must not be published.
/// Format reference: https://developer.apple.com/library/archive/technotes/tn/tn1150.html
Future<void> writeHfsArchive(
  List<ArchiveWriteEntry> entries, {
  required Future<void> Function(List<int>) sink,
  ArchiveRewriteInspection? source,
  int maxOutputBytes = kArchiveStreamingLimit,
  bool Function()? isCancelled,
  String volumeName = 'CrispCloud',
}) async {
  final preserved = source?.container['hfs.profile'];
  if (source != null &&
      (!source.supported || preserved is! _VerifiedHfsProfile)) {
    throw const ArchiveViewException(
      'HFS rewriting requires a verified canonical data-volume inspection.',
    );
  }
  if (maxOutputBytes <= 0 || maxOutputBytes > kArchiveStreamingLimit) {
    throw ArgumentError.value(maxOutputBytes, 'maxOutputBytes');
  }
  void check() {
    if (isCancelled?.call() ?? false) {
      throw const ArchiveViewException('Disk image creation cancelled.');
    }
  }

  check();
  final plan = _HfsPlan(
    entries,
    preserved is _VerifiedHfsProfile
        ? preserved.metadata.volumeName
        : volumeName,
    maxOutputBytes,
    preserved: preserved as _VerifiedHfsProfile?,
  );
  var written = 0;
  Future<void> emit(List<int> bytes) async {
    check();
    if (bytes.length > maxOutputBytes - written) {
      throw const ArchiveViewException(
        'The HFS image exceeds its output limit.',
      );
    }
    await sink(bytes);
    written += bytes.length;
    check();
  }

  await _emitHfsPlan(
    plan,
    emit: emit,
    writeFile: (item) async {
      check();
      await for (final chunk in item.entry!.openRead()) {
        await emit(chunk);
      }
    },
  );
  if (written != plan.totalBlocks * _blockSize) {
    throw StateError('HFS layout length did not match the emitted volume.');
  }
}

Future<void> _emitHfsPlan(
  _HfsPlan plan, {
  required Future<void> Function(List<int>) emit,
  required Future<void> Function(_Item) writeFile,
}) async {
  Future<void> zeros(int count) async {
    final buffer = Uint8List(256 * 1024);
    while (count > 0) {
      final size = count > buffer.length ? buffer.length : count;
      await emit(Uint8List.sublistView(buffer, 0, size));
      count -= size;
    }
  }

  final first = Uint8List(_blockSize)..setRange(1024, 1536, plan.header);
  await emit(first);
  await emit(plan.bitmap);
  await emit(
    _treeHeader(
      totalNodes: 2,
      usedNodes: 1,
      root: 0,
      depth: 0,
      records: 0,
      firstLeaf: 0,
      lastLeaf: 0,
      catalog: false,
    ),
  );
  await zeros(_blockSize);
  await emit(
    _treeHeader(
      totalNodes: plan.nodes.length + 2,
      usedNodes: plan.nodes.length + 1,
      root: plan.nodes.last.id,
      depth: plan.nodes.last.height,
      records: (plan.items.length + 1) * 2,
      firstLeaf: 1,
      lastLeaf: plan.lastLeaf,
      catalog: true,
    ),
  );
  for (final node in plan.nodes) {
    await emit(node.encode());
  }
  await zeros(_blockSize);
  for (final item in plan.items) {
    if (item.directory) continue;
    await writeFile(item);
    await zeros(item.blocks * _blockSize - item.size);
  }
  await zeros((plan.totalBlocks - 1 - plan.dataEndBlock) * _blockSize);
  final last = Uint8List(_blockSize)
    ..setRange(_blockSize - 1024, _blockSize - 512, plan.header);
  await emit(last);
}

class _HfsPlan {
  _HfsPlan(
    List<ArchiveWriteEntry> entries,
    String label,
    int limit, {
    _VerifiedHfsProfile? preserved,
  }) {
    validateArchiveWriteEntries(entries, maxEntries: _maxEntries);
    final normalizedLabel = _normalizeName(label);
    _checkName(normalizedLabel);
    final now = _date(DateTime.now().toUtc());
    final metadata = preserved?.metadata;
    final root = _Item(
      '',
      normalizedLabel,
      true,
      metadata == null
          ? null
          : ArchiveWriteEntry(
              path: normalizedLabel,
              isDirectory: true,
              size: 0,
              mode: metadata.rootMode,
              attributes: metadata.rootAttributes,
            ),
      2,
      1,
      metadata?.rootModified ?? now,
    );
    final paths = <String, _Item>{'': root};
    final explicit = <String>{};
    var nameBytes = normalizedLabel.length * 2;
    for (final entry in entries) {
      if (entry.attributes.isNotEmpty &&
          (preserved == null ||
              entry.attributes.keys.any(
                (key) => !_dateAttributes.contains(key),
              ))) {
        throw ArchiveViewException(
          'HFS creation cannot preserve extra member attributes: ${entry.path}',
        );
      }
      for (final key in entry.attributes.keys) {
        _dateAttribute(entry.attributes, key, now);
      }
      final kind = (entry.mode ?? 0) & 0xf000;
      if ((entry.mode ?? 0) < 0 ||
          (entry.mode ?? 0) > 0xffff ||
          kind != 0 && kind != (entry.isDirectory ? 0x4000 : 0x8000)) {
        throw ArchiveViewException(
          'HFS creation accepts only regular files and directories: ${entry.path}',
        );
      }
      if (entry.size > limit) {
        throw const ArchiveViewException('A file exceeds the HFS image limit.');
      }
      final parts = normalizeHfsArchivePath(entry.path).split('/');
      if (parts.length > 64) {
        throw const ArchiveViewException(
          'The HFS folder hierarchy is too deep.',
        );
      }
      final fullPath = parts.join('/');
      if (!explicit.add(fullPath)) {
        throw ArchiveViewException(
          'HFS names collide after Unicode decomposition: ${entry.path}',
        );
      }
      var parent = '';
      for (var i = 0; i < parts.length; i++) {
        _checkName(parts[i]);
        final path = parent.isEmpty ? parts[i] : '$parent/${parts[i]}';
        final last = i == parts.length - 1;
        final directory = !last || entry.isDirectory;
        final previous = paths[path];
        if (previous != null && (!previous.directory || !directory)) {
          throw ArchiveViewException('Conflicting HFS paths: ${entry.path}');
        }
        if (previous == null) {
          nameBytes += parts[i].length * 2;
          if (paths.length > _maxEntries || nameBytes > 8 * 1024 * 1024) {
            throw const ArchiveViewException(
              'HFS directory metadata is too large.',
            );
          }
          paths[path] = _Item(
            path,
            parts[i],
            directory,
            last ? entry : null,
            0,
            0,
            last && entry.modified != null ? _date(entry.modified!) : now,
          );
        } else if (last) {
          previous.entry = entry;
          previous.date = entry.modified == null ? now : _date(entry.modified!);
        }
        parent = path;
      }
    }
    items = paths.values.where((item) => item.id != 2).toList()
      ..sort((a, b) => _compareUnits(a.path, b.path));
    var nextId = 16;
    var dataBlocks = 0;
    for (final item in items) {
      item.id = nextId++;
      dataBlocks += item.blocks;
      if (dataBlocks > limit ~/ _blockSize) {
        throw const ArchiveViewException(
          'File data exceeds the HFS image limit.',
        );
      }
    }
    for (final item in items) {
      final slash = item.path.lastIndexOf('/');
      final parent = paths[slash < 0 ? '' : item.path.substring(0, slash)]!;
      item.parent = parent.id;
      parent.children++;
      if (item.directory) parent.folders++;
    }
    final records = <_Record>[];
    var recordBytes = 0;
    for (final item in [root, ...items]) {
      final entry = _Record.item(item);
      final thread = _Record.thread(item);
      recordBytes += entry.length + thread.length;
      if (recordBytes > _maxCatalogBytes) {
        throw const ArchiveViewException('The HFS catalog exceeds 32 MiB.');
      }
      records.addAll([entry, thread]);
    }
    records.sort((a, b) {
      final parent = a.parent.compareTo(b.parent);
      return parent != 0 ? parent : _compareUnits(a.name, b.name);
    });
    var level = _pack(records, 1);
    lastLeaf = level.length;
    while (level.length > 1) {
      level = _pack(
        level.map((node) => _Record.index(node)).toList(),
        level.first.height + 1,
      );
    }
    final catalogBlocks = nodes.length + 2; // header and one free node
    // Keep one MiB free and use at least eight MiB for ordinary OS tooling.
    var bitmapBlocks = 1;
    while (true) {
      final used = 1 + bitmapBlocks + 2 + catalogBlocks + dataBlocks + 1;
      totalBlocks = used + 256;
      if (totalBlocks < 2048) totalBlocks = 2048;
      final required = (totalBlocks + 8 * _blockSize - 1) ~/ (8 * _blockSize);
      if (required == bitmapBlocks) break;
      bitmapBlocks = required;
    }
    if (totalBlocks > limit ~/ _blockSize) {
      throw const ArchiveViewException(
        'The HFS image exceeds its output limit.',
      );
    }
    final extentsStart = 1 + bitmapBlocks;
    final catalogStart = extentsStart + 2;
    var nextBlock = catalogStart + catalogBlocks;
    for (final item in items) {
      if (item.blocks > 0) {
        item.start = nextBlock;
        nextBlock += item.blocks;
      }
    }
    dataEndBlock = nextBlock;
    bitmap = Uint8List(bitmapBlocks * _blockSize);
    for (var i = 0; i < nextBlock; i++) {
      bitmap[i >> 3] |= 0x80 >> (i & 7);
    }
    bitmap[(totalBlocks - 1) >> 3] |= 0x80 >> ((totalBlocks - 1) & 7);
    final h = ByteData.sublistView(header);
    h.setUint16(0, 0x4858);
    h.setUint16(2, 5);
    h.setUint32(4, 0x100); // cleanly unmounted, unjournaled
    h.setUint32(8, 0x43724331); // CrC1: this creator's on-disk profile
    h.setUint32(16, metadata?.volumeCreated ?? now);
    h.setUint32(20, metadata?.volumeModified ?? now);
    h.setUint32(24, metadata?.volumeBackup ?? 0);
    h.setUint32(28, metadata?.volumeChecked ?? now);
    h.setUint32(32, items.where((item) => !item.directory).length);
    h.setUint32(36, items.where((item) => item.directory).length);
    h.setUint32(40, _blockSize);
    h.setUint32(44, totalBlocks);
    h.setUint32(48, totalBlocks - nextBlock - 1);
    h.setUint32(52, nextBlock);
    h.setUint32(56, _blockSize);
    h.setUint32(60, _blockSize);
    h.setUint32(64, nextId);
    h.setUint32(68, 1);
    h.setUint32(76, 1); // MacRoman hint; Unicode names remain authoritative
    _fork(h, 112, bitmap.length, 1, bitmapBlocks);
    _fork(h, 192, 2 * _blockSize, extentsStart, 2);
    _fork(h, 272, catalogBlocks * _blockSize, catalogStart, catalogBlocks);
  }

  late final List<_Item> items;
  final nodes = <_Node>[];
  late final int lastLeaf;
  late int totalBlocks;
  late final int dataEndBlock;
  late final Uint8List bitmap;
  final header = Uint8List(512);

  List<_Node> _pack(List<_Record> records, int height) {
    final result = <_Node>[];
    var current = <_Record>[];
    var used = 16;
    void finish() {
      if (current.isEmpty) return;
      final node = _Node(nodes.length + 1, height, current);
      if (result.isNotEmpty) {
        result.last.next = node.id;
        node.previous = result.last.id;
      }
      nodes.add(node);
      result.add(node);
      current = [];
      used = 16;
      if ((nodes.length + 2) * _blockSize > _maxCatalogBytes) {
        throw const ArchiveViewException('The HFS catalog exceeds 32 MiB.');
      }
    }

    for (final record in records) {
      if (used + record.length + 2 > _blockSize) finish();
      current.add(record);
      used += record.length + 2;
    }
    finish();
    return result;
  }
}

class _Item {
  _Item(
    this.path,
    this.name,
    this.directory,
    this.entry,
    this.id,
    this.parent,
    this.date,
  );
  final String path, name;
  final bool directory;
  ArchiveWriteEntry? entry;
  int id, parent, date;
  int children = 0, folders = 0, start = 0;
  int get size => entry?.size ?? 0;
  int get blocks => (size + _blockSize - 1) ~/ _blockSize;
  int get mode =>
      (directory ? 0x4000 : 0x8000) |
      ((entry?.mode ?? (directory ? 0x1ed : 0x1a4)) & 0xfff);
  int dateAttribute(String key, int fallback) =>
      _dateAttribute(entry?.attributes ?? const {}, key, fallback);
}

class _Record {
  _Record.item(_Item item) : this._(item.parent, item.name, item, false, null);
  _Record.thread(_Item item) : this._(item.id, '', item, true, null);
  _Record.index(_Node node)
    : this._(
        node.records.first.parent,
        node.records.first.name,
        null,
        false,
        node.id,
      );
  _Record._(this.parent, this.name, this.item, this.thread, this.child);
  final int parent;
  final String name;
  final _Item? item;
  final bool thread;
  final int? child;
  int get keyBytes => 8 + name.length * 2;
  int get length =>
      keyBytes +
      (child != null
          ? 4
          : thread
          ? 10 + item!.name.length * 2
          : item!.directory
          ? 88
          : 248);

  Uint8List encode() {
    final bytes = Uint8List(length);
    final d = ByteData.sublistView(bytes);
    d.setUint16(0, keyBytes - 2);
    d.setUint32(2, parent);
    _name(d, 6, name);
    final at = keyBytes;
    if (child != null) {
      d.setUint32(at, child!);
      return bytes;
    }
    final node = item!;
    if (thread) {
      d.setUint16(at, node.directory ? 3 : 4);
      d.setUint32(at + 4, node.parent);
      _name(d, at + 8, node.name);
      return bytes;
    }
    d.setUint16(at, node.directory ? 1 : 2);
    d.setUint16(at + 2, node.directory ? 0x10 : 2);
    if (node.directory) d.setUint32(at + 4, node.children);
    d.setUint32(at + 8, node.id);
    d.setUint32(at + 12, node.dateAttribute('hfs.created', node.date));
    d.setUint32(at + 16, node.date);
    d.setUint32(
      at + 20,
      node.dateAttribute('hfs.attributesModified', node.date),
    );
    d.setUint32(at + 24, node.dateAttribute('hfs.accessed', node.date));
    d.setUint32(at + 28, node.dateAttribute('hfs.backedUp', 0));
    d.setUint16(at + 42, node.mode);
    if (node.directory) {
      d.setUint32(at + 84, node.folders);
    } else {
      _fork(d, at + 88, node.size, node.start, node.blocks);
    }
    return bytes;
  }
}

class _Node {
  _Node(this.id, this.height, this.records);
  final int id, height;
  final List<_Record> records;
  int next = 0, previous = 0;
  Uint8List encode() {
    final bytes = Uint8List(_blockSize);
    final d = ByteData.sublistView(bytes);
    d.setUint32(0, next);
    d.setUint32(4, previous);
    bytes[8] = height == 1 ? 255 : 0;
    bytes[9] = height;
    d.setUint16(10, records.length);
    var at = 14;
    for (var i = 0; i < records.length; i++) {
      d.setUint16(_blockSize - 2 * (i + 1), at);
      final record = records[i].encode();
      bytes.setRange(at, at + record.length, record);
      at += record.length;
    }
    d.setUint16(_blockSize - 2 * (records.length + 1), at);
    return bytes;
  }
}

Uint8List _treeHeader({
  required int totalNodes,
  required int usedNodes,
  required int root,
  required int depth,
  required int records,
  required int firstLeaf,
  required int lastLeaf,
  required bool catalog,
}) {
  final bytes = Uint8List(_blockSize);
  final d = ByteData.sublistView(bytes);
  bytes[8] = 1;
  d.setUint16(10, 3);
  d.setUint16(14, depth);
  d.setUint32(16, root);
  d.setUint32(20, records);
  d.setUint32(24, firstLeaf);
  d.setUint32(28, lastLeaf);
  d.setUint16(32, _blockSize);
  d.setUint16(34, catalog ? 516 : 10);
  d.setUint32(36, totalNodes);
  d.setUint32(40, totalNodes - usedNodes);
  d.setUint32(46, _blockSize);
  bytes[51] = catalog ? 0xbc : 0;
  d.setUint32(52, catalog ? 6 : 2);
  for (var i = 0; i < usedNodes; i++) {
    bytes[248 + (i >> 3)] |= 0x80 >> (i & 7);
  }
  for (final (index, offset) in [14, 120, 248, _blockSize - 8].indexed) {
    d.setUint16(_blockSize - 2 * (index + 1), offset);
  }
  return bytes;
}

void _fork(ByteData d, int at, int size, int start, int blocks) {
  d.setUint32(at, size ~/ 0x100000000);
  d.setUint32(at + 4, size & 0xffffffff);
  d.setUint32(at + 8, _blockSize);
  d.setUint32(at + 12, blocks);
  if (blocks != 0) {
    d.setUint32(at + 16, start);
    d.setUint32(at + 20, blocks);
  }
}

void _name(ByteData d, int at, String name) {
  d.setUint16(at, name.length);
  for (var i = 0; i < name.length; i++) {
    d.setUint16(at + 2 + i * 2, name.codeUnitAt(i));
  }
}

int _date(DateTime date) {
  final milliseconds = date.toUtc().millisecondsSinceEpoch + _hfsEpoch * 1000;
  if (milliseconds < 0 || milliseconds >= 0x100000000 * 1000) {
    throw const ArchiveViewException('HFS timestamps must fit 1904–2040.');
  }
  return milliseconds ~/ 1000;
}

int _dateAttribute(Map<String, Object?> attributes, String key, int fallback) {
  if (!attributes.containsKey(key)) return fallback;
  final value = attributes[key];
  if (value is! int || value < 0 || value > 0xffffffff) {
    throw ArchiveViewException('Invalid preserved HFS timestamp: $key');
  }
  return value;
}

void _checkName(String name) {
  if (name.isEmpty ||
      name.length > 255 ||
      name == '.' ||
      name == '..' ||
      RegExp(r'[\x00-\x1f\x7f/:\\]').hasMatch(name)) {
    throw ArchiveViewException('Unsupported HFS name: $name');
  }
}

int _compareUnits(String a, String b) {
  final length = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < length; i++) {
    final difference = a.codeUnitAt(i) - b.codeUnitAt(i);
    if (difference != 0) return difference;
  }
  return a.length - b.length;
}

String _normalizeName(String name) {
  if (name.length > 255) {
    throw const ArchiveViewException('An HFS name exceeds 255 UTF-16 units.');
  }
  final units = <int>[];
  for (var i = 0; i < name.length; i++) {
    final value = name.codeUnitAt(i);
    if (value >= 0xd800 && value <= 0xdfff) {
      if (value > 0xdbff ||
          i + 1 >= name.length ||
          name.codeUnitAt(i + 1) < 0xdc00 ||
          name.codeUnitAt(i + 1) > 0xdfff) {
        throw const ArchiveViewException('HFS names require valid Unicode.');
      }
      units.add(value);
      units.add(name.codeUnitAt(++i));
    } else if (value >= 0xac00 && value <= 0xd7a3) {
      final syllable = value - 0xac00;
      units.add(0x1100 + syllable ~/ 588);
      units.add(0x1161 + (syllable % 588) ~/ 28);
      if (syllable % 28 != 0) units.add(0x11a7 + syllable % 28);
    } else {
      units.addAll(_unicodeDecomposition[value] ?? [value]);
    }
  }
  // Stable canonical ordering, bounded by HFS's 255-code-unit name limit.
  if (units.length > 255) {
    throw const ArchiveViewException('An HFS name exceeds 255 UTF-16 units.');
  }
  for (var i = 1; i < units.length; i++) {
    final combining = _unicodeCombining[units[i]] ?? 0;
    if (combining == 0) continue;
    var at = i;
    while (at > 0 && (_unicodeCombining[units[at - 1]] ?? 0) > combining) {
      final before = units[at - 1];
      units[at - 1] = units[at];
      units[at] = before;
      at--;
    }
  }
  return String.fromCharCodes(units);
}

// Generated from Python unicodedata.ucd_3_2_0, restricted to BMP scalar values.
// Decomposition excludes HFS's U+2000–2FFF and U+F900–FAFF ranges; combining
// classes retain those ranges. Hangul decomposition is algorithmic.
// Each decomposition record is uint16 codepoint, uint8 count, uint16[count].
// Each combining record is uint16 codepoint, uint8 canonical-combining-class.
final _unicodeDecomposition = _decodeDecomposition();
final _unicodeCombining = _decodeCombining();
Map<int, List<int>> _decodeDecomposition() {
  final bytes = base64.decode(_decompositionData);
  final d = ByteData.sublistView(bytes);
  final result = <int, List<int>>{};
  for (var at = 0; at < bytes.length;) {
    final key = d.getUint16(at);
    final count = bytes[at + 2];
    at += 3;
    result[key] = [for (var i = 0; i < count; i++) d.getUint16(at + 2 * i)];
    at += count * 2;
  }
  return result;
}

Map<int, int> _decodeCombining() {
  final bytes = base64.decode(_combiningData);
  final d = ByteData.sublistView(bytes);
  return {
    for (var at = 0; at < bytes.length; at += 3) d.getUint16(at): bytes[at + 2],
  };
}

const _decompositionData =
    'AMACAEEDAADBAgBBAwEAwgIAQQMCAMMCAEEDAwDEAgBBAwgAxQIAQQMKAMcCAEMDJwDIAgBFAwAAyQIARQMBAMoCAEUDAgDLAgBF'
    'AwgAzAIASQMAAM0CAEkDAQDOAgBJAwIAzwIASQMIANECAE4DAwDSAgBPAwAA0wIATwMBANQCAE8DAgDVAgBPAwMA1gIATwMIANkC'
    'AFUDAADaAgBVAwEA2wIAVQMCANwCAFUDCADdAgBZAwEA4AIAYQMAAOECAGEDAQDiAgBhAwIA4wIAYQMDAOQCAGEDCADlAgBhAwoA'
    '5wIAYwMnAOgCAGUDAADpAgBlAwEA6gIAZQMCAOsCAGUDCADsAgBpAwAA7QIAaQMBAO4CAGkDAgDvAgBpAwgA8QIAbgMDAPICAG8D'
    'AADzAgBvAwEA9AIAbwMCAPUCAG8DAwD2AgBvAwgA+QIAdQMAAPoCAHUDAQD7AgB1AwIA/AIAdQMIAP0CAHkDAQD/AgB5AwgBAAIA'
    'QQMEAQECAGEDBAECAgBBAwYBAwIAYQMGAQQCAEEDKAEFAgBhAygBBgIAQwMBAQcCAGMDAQEIAgBDAwIBCQIAYwMCAQoCAEMDBwEL'
    'AgBjAwcBDAIAQwMMAQ0CAGMDDAEOAgBEAwwBDwIAZAMMARICAEUDBAETAgBlAwQBFAIARQMGARUCAGUDBgEWAgBFAwcBFwIAZQMH'
    'ARgCAEUDKAEZAgBlAygBGgIARQMMARsCAGUDDAEcAgBHAwIBHQIAZwMCAR4CAEcDBgEfAgBnAwYBIAIARwMHASECAGcDBwEiAgBH'
    'AycBIwIAZwMnASQCAEgDAgElAgBoAwIBKAIASQMDASkCAGkDAwEqAgBJAwQBKwIAaQMEASwCAEkDBgEtAgBpAwYBLgIASQMoAS8C'
    'AGkDKAEwAgBJAwcBNAIASgMCATUCAGoDAgE2AgBLAycBNwIAawMnATkCAEwDAQE6AgBsAwEBOwIATAMnATwCAGwDJwE9AgBMAwwB'
    'PgIAbAMMAUMCAE4DAQFEAgBuAwEBRQIATgMnAUYCAG4DJwFHAgBOAwwBSAIAbgMMAUwCAE8DBAFNAgBvAwQBTgIATwMGAU8CAG8D'
    'BgFQAgBPAwsBUQIAbwMLAVQCAFIDAQFVAgByAwEBVgIAUgMnAVcCAHIDJwFYAgBSAwwBWQIAcgMMAVoCAFMDAQFbAgBzAwEBXAIA'
    'UwMCAV0CAHMDAgFeAgBTAycBXwIAcwMnAWACAFMDDAFhAgBzAwwBYgIAVAMnAWMCAHQDJwFkAgBUAwwBZQIAdAMMAWgCAFUDAwFp'
    'AgB1AwMBagIAVQMEAWsCAHUDBAFsAgBVAwYBbQIAdQMGAW4CAFUDCgFvAgB1AwoBcAIAVQMLAXECAHUDCwFyAgBVAygBcwIAdQMo'
    'AXQCAFcDAgF1AgB3AwIBdgIAWQMCAXcCAHkDAgF4AgBZAwgBeQIAWgMBAXoCAHoDAQF7AgBaAwcBfAIAegMHAX0CAFoDDAF+AgB6'
    'AwwBoAIATwMbAaECAG8DGwGvAgBVAxsBsAIAdQMbAc0CAEEDDAHOAgBhAwwBzwIASQMMAdACAGkDDAHRAgBPAwwB0gIAbwMMAdMC'
    'AFUDDAHUAgB1AwwB1QMAVQMIAwQB1gMAdQMIAwQB1wMAVQMIAwEB2AMAdQMIAwEB2QMAVQMIAwwB2gMAdQMIAwwB2wMAVQMIAwAB'
    '3AMAdQMIAwAB3gMAQQMIAwQB3wMAYQMIAwQB4AMAQQMHAwQB4QMAYQMHAwQB4gIAxgMEAeMCAOYDBAHmAgBHAwwB5wIAZwMMAegC'
    'AEsDDAHpAgBrAwwB6gIATwMoAesCAG8DKAHsAwBPAygDBAHtAwBvAygDBAHuAgG3AwwB7wICkgMMAfACAGoDDAH0AgBHAwEB9QIA'
    'ZwMBAfgCAE4DAAH5AgBuAwAB+gMAQQMKAwEB+wMAYQMKAwEB/AIAxgMBAf0CAOYDAQH+AgDYAwEB/wIA+AMBAgACAEEDDwIBAgBh'
    'Aw8CAgIAQQMRAgMCAGEDEQIEAgBFAw8CBQIAZQMPAgYCAEUDEQIHAgBlAxECCAIASQMPAgkCAGkDDwIKAgBJAxECCwIAaQMRAgwC'
    'AE8DDwINAgBvAw8CDgIATwMRAg8CAG8DEQIQAgBSAw8CEQIAcgMPAhICAFIDEQITAgByAxECFAIAVQMPAhUCAHUDDwIWAgBVAxEC'
    'FwIAdQMRAhgCAFMDJgIZAgBzAyYCGgIAVAMmAhsCAHQDJgIeAgBIAwwCHwIAaAMMAiYCAEEDBwInAgBhAwcCKAIARQMnAikCAGUD'
    'JwIqAwBPAwgDBAIrAwBvAwgDBAIsAwBPAwMDBAItAwBvAwMDBAIuAgBPAwcCLwIAbwMHAjADAE8DBwMEAjEDAG8DBwMEAjICAFkD'
    'BAIzAgB5AwQDQAEDAANBAQMBA0MBAxMDRAIDCAMBA3QBArkDfgEAOwOFAgCoAwEDhgIDkQMBA4cBALcDiAIDlQMBA4kCA5cDAQOK'
    'AgOZAwEDjAIDnwMBA44CA6UDAQOPAgOpAwEDkAMDuQMIAwEDqgIDmQMIA6sCA6UDCAOsAgOxAwEDrQIDtQMBA64CA7cDAQOvAgO5'
    'AwEDsAMDxQMIAwEDygIDuQMIA8sCA8UDCAPMAgO/AwEDzQIDxQMBA84CA8kDAQPTAgPSAwED1AID0gMIBAACBBUDAAQBAgQVAwgE'
    'AwIEEwMBBAcCBAYDCAQMAgQaAwEEDQIEGAMABA4CBCMDBgQZAgQYAwYEOQIEOAMGBFACBDUDAARRAgQ1AwgEUwIEMwMBBFcCBFYD'
    'CARcAgQ6AwEEXQIEOAMABF4CBEMDBgR2AgR0Aw8EdwIEdQMPBMECBBYDBgTCAgQ2AwYE0AIEEAMGBNECBDADBgTSAgQQAwgE0wIE'
    'MAMIBNYCBBUDBgTXAgQ1AwYE2gIE2AMIBNsCBNkDCATcAgQWAwgE3QIENgMIBN4CBBcDCATfAgQ3AwgE4gIEGAMEBOMCBDgDBATk'
    'AgQYAwgE5QIEOAMIBOYCBB4DCATnAgQ+AwgE6gIE6AMIBOsCBOkDCATsAgQtAwgE7QIETQMIBO4CBCMDBATvAgRDAwQE8AIEIwMI'
    'BPECBEMDCATyAgQjAwsE8wIEQwMLBPQCBCcDCAT1AgRHAwgE+AIEKwMIBPkCBEsDCAYiAgYnBlMGIwIGJwZUBiQCBkgGVAYlAgYn'
    'BlUGJgIGSgZUBsACBtUGVAbCAgbBBlQG0wIG0gZUCSkCCSgJPAkxAgkwCTwJNAIJMwk8CVgCCRUJPAlZAgkWCTwJWgIJFwk8CVsC'
    'CRwJPAlcAgkhCTwJXQIJIgk8CV4CCSsJPAlfAgkvCTwJywIJxwm+CcwCCccJ1wncAgmhCbwJ3QIJogm8Cd8CCa8JvAozAgoyCjwK'
    'NgIKOAo8ClkCChYKPApaAgoXCjwKWwIKHAo8Cl4CCisKPAtIAgtHC1YLSwILRws+C0wCC0cLVwtcAgshCzwLXQILIgs8C5QCC5IL'
    '1wvKAgvGC74LywILxwu+C8wCC8YL1wxIAgxGDFYMwAIMvwzVDMcCDMYM1QzIAgzGDNYMygIMxgzCDMsDDMYMwgzVDUoCDUYNPg1L'
    'Ag1HDT4NTAINRg1XDdoCDdkNyg3cAg3ZDc8N3QMN2Q3PDcoN3gIN2Q3fD0MCD0IPtw9NAg9MD7cPUgIPUQ+3D1cCD1YPtw9cAg9b'
    'D7cPaQIPQA+1D3MCD3EPcg91Ag9xD3QPdgIPsg+AD3gCD7MPgA+BAg9xD4APkwIPkg+3D50CD5wPtw+iAg+hD7cPpwIPpg+3D6wC'
    'D6sPtw+5Ag+QD7UQJgIQJRAuHgACAEEDJR4BAgBhAyUeAgIAQgMHHgMCAGIDBx4EAgBCAyMeBQIAYgMjHgYCAEIDMR4HAgBiAzEe'
    'CAMAQwMnAwEeCQMAYwMnAwEeCgIARAMHHgsCAGQDBx4MAgBEAyMeDQIAZAMjHg4CAEQDMR4PAgBkAzEeEAIARAMnHhECAGQDJx4S'
    'AgBEAy0eEwIAZAMtHhQDAEUDBAMAHhUDAGUDBAMAHhYDAEUDBAMBHhcDAGUDBAMBHhgCAEUDLR4ZAgBlAy0eGgIARQMwHhsCAGUD'
    'MB4cAwBFAycDBh4dAwBlAycDBh4eAgBGAwceHwIAZgMHHiACAEcDBB4hAgBnAwQeIgIASAMHHiMCAGgDBx4kAgBIAyMeJQIAaAMj'
    'HiYCAEgDCB4nAgBoAwgeKAIASAMnHikCAGgDJx4qAgBIAy4eKwIAaAMuHiwCAEkDMB4tAgBpAzAeLgMASQMIAwEeLwMAaQMIAwEe'
    'MAIASwMBHjECAGsDAR4yAgBLAyMeMwIAawMjHjQCAEsDMR41AgBrAzEeNgIATAMjHjcCAGwDIx44AwBMAyMDBB45AwBsAyMDBB46'
    'AgBMAzEeOwIAbAMxHjwCAEwDLR49AgBsAy0ePgIATQMBHj8CAG0DAR5AAgBNAwceQQIAbQMHHkICAE0DIx5DAgBtAyMeRAIATgMH'
    'HkUCAG4DBx5GAgBOAyMeRwIAbgMjHkgCAE4DMR5JAgBuAzEeSgIATgMtHksCAG4DLR5MAwBPAwMDAR5NAwBvAwMDAR5OAwBPAwMD'
    'CB5PAwBvAwMDCB5QAwBPAwQDAB5RAwBvAwQDAB5SAwBPAwQDAR5TAwBvAwQDAR5UAgBQAwEeVQIAcAMBHlYCAFADBx5XAgBwAwce'
    'WAIAUgMHHlkCAHIDBx5aAgBSAyMeWwIAcgMjHlwDAFIDIwMEHl0DAHIDIwMEHl4CAFIDMR5fAgByAzEeYAIAUwMHHmECAHMDBx5i'
    'AgBTAyMeYwIAcwMjHmQDAFMDAQMHHmUDAHMDAQMHHmYDAFMDDAMHHmcDAHMDDAMHHmgDAFMDIwMHHmkDAHMDIwMHHmoCAFQDBx5r'
    'AgB0AwcebAIAVAMjHm0CAHQDIx5uAgBUAzEebwIAdAMxHnACAFQDLR5xAgB0Ay0ecgIAVQMkHnMCAHUDJB50AgBVAzAedQIAdQMw'
    'HnYCAFUDLR53AgB1Ay0eeAMAVQMDAwEeeQMAdQMDAwEeegMAVQMEAwgeewMAdQMEAwgefAIAVgMDHn0CAHYDAx5+AgBWAyMefwIA'
    'dgMjHoACAFcDAB6BAgB3AwAeggIAVwMBHoMCAHcDAR6EAgBXAwgehQIAdwMIHoYCAFcDBx6HAgB3AwceiAIAVwMjHokCAHcDIx6K'
    'AgBYAwceiwIAeAMHHowCAFgDCB6NAgB4AwgejgIAWQMHHo8CAHkDBx6QAgBaAwIekQIAegMCHpICAFoDIx6TAgB6AyMelAIAWgMx'
    'HpUCAHoDMR6WAgBoAzEelwIAdAMIHpgCAHcDCh6ZAgB5AwoemwIBfwMHHqACAEEDIx6hAgBhAyMeogIAQQMJHqMCAGEDCR6kAwBB'
    'AwIDAR6lAwBhAwIDAR6mAwBBAwIDAB6nAwBhAwIDAB6oAwBBAwIDCR6pAwBhAwIDCR6qAwBBAwIDAx6rAwBhAwIDAx6sAwBBAyMD'
    'Ah6tAwBhAyMDAh6uAwBBAwYDAR6vAwBhAwYDAR6wAwBBAwYDAB6xAwBhAwYDAB6yAwBBAwYDCR6zAwBhAwYDCR60AwBBAwYDAx61'
    'AwBhAwYDAx62AwBBAyMDBh63AwBhAyMDBh64AgBFAyMeuQIAZQMjHroCAEUDCR67AgBlAwkevAIARQMDHr0CAGUDAx6+AwBFAwID'
    'AR6/AwBlAwIDAR7AAwBFAwIDAB7BAwBlAwIDAB7CAwBFAwIDCR7DAwBlAwIDCR7EAwBFAwIDAx7FAwBlAwIDAx7GAwBFAyMDAh7H'
    'AwBlAyMDAh7IAgBJAwkeyQIAaQMJHsoCAEkDIx7LAgBpAyMezAIATwMjHs0CAG8DIx7OAgBPAwkezwIAbwMJHtADAE8DAgMBHtED'
    'AG8DAgMBHtIDAE8DAgMAHtMDAG8DAgMAHtQDAE8DAgMJHtUDAG8DAgMJHtYDAE8DAgMDHtcDAG8DAgMDHtgDAE8DIwMCHtkDAG8D'
    'IwMCHtoDAE8DGwMBHtsDAG8DGwMBHtwDAE8DGwMAHt0DAG8DGwMAHt4DAE8DGwMJHt8DAG8DGwMJHuADAE8DGwMDHuEDAG8DGwMD'
    'HuIDAE8DGwMjHuMDAG8DGwMjHuQCAFUDIx7lAgB1AyMe5gIAVQMJHucCAHUDCR7oAwBVAxsDAR7pAwB1AxsDAR7qAwBVAxsDAB7r'
    'AwB1AxsDAB7sAwBVAxsDCR7tAwB1AxsDCR7uAwBVAxsDAx7vAwB1AxsDAx7wAwBVAxsDIx7xAwB1AxsDIx7yAgBZAwAe8wIAeQMA'
    'HvQCAFkDIx71AgB5AyMe9gIAWQMJHvcCAHkDCR74AgBZAwMe+QIAeQMDHwACA7EDEx8BAgOxAxQfAgMDsQMTAwAfAwMDsQMUAwAf'
    'BAMDsQMTAwEfBQMDsQMUAwEfBgMDsQMTA0IfBwMDsQMUA0IfCAIDkQMTHwkCA5EDFB8KAwORAxMDAB8LAwORAxQDAB8MAwORAxMD'
    'AR8NAwORAxQDAR8OAwORAxMDQh8PAwORAxQDQh8QAgO1AxMfEQIDtQMUHxIDA7UDEwMAHxMDA7UDFAMAHxQDA7UDEwMBHxUDA7UD'
    'FAMBHxgCA5UDEx8ZAgOVAxQfGgMDlQMTAwAfGwMDlQMUAwAfHAMDlQMTAwEfHQMDlQMUAwEfIAIDtwMTHyECA7cDFB8iAwO3AxMD'
    'AB8jAwO3AxQDAB8kAwO3AxMDAR8lAwO3AxQDAR8mAwO3AxMDQh8nAwO3AxQDQh8oAgOXAxMfKQIDlwMUHyoDA5cDEwMAHysDA5cD'
    'FAMAHywDA5cDEwMBHy0DA5cDFAMBHy4DA5cDEwNCHy8DA5cDFANCHzACA7kDEx8xAgO5AxQfMgMDuQMTAwAfMwMDuQMUAwAfNAMD'
    'uQMTAwEfNQMDuQMUAwEfNgMDuQMTA0IfNwMDuQMUA0IfOAIDmQMTHzkCA5kDFB86AwOZAxMDAB87AwOZAxQDAB88AwOZAxMDAR89'
    'AwOZAxQDAR8+AwOZAxMDQh8/AwOZAxQDQh9AAgO/AxMfQQIDvwMUH0IDA78DEwMAH0MDA78DFAMAH0QDA78DEwMBH0UDA78DFAMB'
    'H0gCA58DEx9JAgOfAxQfSgMDnwMTAwAfSwMDnwMUAwAfTAMDnwMTAwEfTQMDnwMUAwEfUAIDxQMTH1ECA8UDFB9SAwPFAxMDAB9T'
    'AwPFAxQDAB9UAwPFAxMDAR9VAwPFAxQDAR9WAwPFAxMDQh9XAwPFAxQDQh9ZAgOlAxQfWwMDpQMUAwAfXQMDpQMUAwEfXwMDpQMU'
    'A0IfYAIDyQMTH2ECA8kDFB9iAwPJAxMDAB9jAwPJAxQDAB9kAwPJAxMDAR9lAwPJAxQDAR9mAwPJAxMDQh9nAwPJAxQDQh9oAgOp'
    'AxMfaQIDqQMUH2oDA6kDEwMAH2sDA6kDFAMAH2wDA6kDEwMBH20DA6kDFAMBH24DA6kDEwNCH28DA6kDFANCH3ACA7EDAB9xAgOx'
    'AwEfcgIDtQMAH3MCA7UDAR90AgO3AwAfdQIDtwMBH3YCA7kDAB93AgO5AwEfeAIDvwMAH3kCA78DAR96AgPFAwAfewIDxQMBH3wC'
    'A8kDAB99AgPJAwEfgAMDsQMTA0UfgQMDsQMUA0UfggQDsQMTAwADRR+DBAOxAxQDAANFH4QEA7EDEwMBA0UfhQQDsQMUAwEDRR+G'
    'BAOxAxMDQgNFH4cEA7EDFANCA0UfiAMDkQMTA0UfiQMDkQMUA0UfigQDkQMTAwADRR+LBAORAxQDAANFH4wEA5EDEwMBA0UfjQQD'
    'kQMUAwEDRR+OBAORAxMDQgNFH48EA5EDFANCA0UfkAMDtwMTA0UfkQMDtwMUA0UfkgQDtwMTAwADRR+TBAO3AxQDAANFH5QEA7cD'
    'EwMBA0UflQQDtwMUAwEDRR+WBAO3AxMDQgNFH5cEA7cDFANCA0UfmAMDlwMTA0UfmQMDlwMUA0UfmgQDlwMTAwADRR+bBAOXAxQD'
    'AANFH5wEA5cDEwMBA0UfnQQDlwMUAwEDRR+eBAOXAxMDQgNFH58EA5cDFANCA0UfoAMDyQMTA0UfoQMDyQMUA0UfogQDyQMTAwAD'
    'RR+jBAPJAxQDAANFH6QEA8kDEwMBA0UfpQQDyQMUAwEDRR+mBAPJAxMDQgNFH6cEA8kDFANCA0UfqAMDqQMTA0UfqQMDqQMUA0Uf'
    'qgQDqQMTAwADRR+rBAOpAxQDAANFH6wEA6kDEwMBA0UfrQQDqQMUAwEDRR+uBAOpAxMDQgNFH68EA6kDFANCA0UfsAIDsQMGH7EC'
    'A7EDBB+yAwOxAwADRR+zAgOxA0UftAMDsQMBA0UftgIDsQNCH7cDA7EDQgNFH7gCA5EDBh+5AgORAwQfugIDkQMAH7sCA5EDAR+8'
    'AgORA0UfvgEDuR/BAgCoA0IfwgMDtwMAA0UfwwIDtwNFH8QDA7cDAQNFH8YCA7cDQh/HAwO3A0IDRR/IAgOVAwAfyQIDlQMBH8oC'
    'A5cDAB/LAgOXAwEfzAIDlwNFH80CH78DAB/OAh+/AwEfzwIfvwNCH9ACA7kDBh/RAgO5AwQf0gMDuQMIAwAf0wMDuQMIAwEf1gID'
    'uQNCH9cDA7kDCANCH9gCA5kDBh/ZAgOZAwQf2gIDmQMAH9sCA5kDAR/dAh/+AwAf3gIf/gMBH98CH/4DQh/gAgPFAwYf4QIDxQME'
    'H+IDA8UDCAMAH+MDA8UDCAMBH+QCA8EDEx/lAgPBAxQf5gIDxQNCH+cDA8UDCANCH+gCA6UDBh/pAgOlAwQf6gIDpQMAH+sCA6UD'
    'AR/sAgOhAxQf7QIAqAMAH+4CAKgDAR/vAQBgH/IDA8kDAANFH/MCA8kDRR/0AwPJAwEDRR/2AgPJA0If9wMDyQNCA0Uf+AIDnwMA'
    'H/kCA58DAR/6AgOpAwAf+wIDqQMBH/wCA6kDRR/9AQC0MEwCMEswmTBOAjBNMJkwUAIwTzCZMFICMFEwmTBUAjBTMJkwVgIwVTCZ'
    'MFgCMFcwmTBaAjBZMJkwXAIwWzCZMF4CMF0wmTBgAjBfMJkwYgIwYTCZMGUCMGQwmTBnAjBmMJkwaQIwaDCZMHACMG8wmTBxAjBv'
    'MJowcwIwcjCZMHQCMHIwmjB2AjB1MJkwdwIwdTCaMHkCMHgwmTB6AjB4MJowfAIwezCZMH0CMHswmjCUAjBGMJkwngIwnTCZMKwC'
    'MKswmTCuAjCtMJkwsAIwrzCZMLICMLEwmTC0AjCzMJkwtgIwtTCZMLgCMLcwmTC6AjC5MJkwvAIwuzCZML4CML0wmTDAAjC/MJkw'
    'wgIwwTCZMMUCMMQwmTDHAjDGMJkwyQIwyDCZMNACMM8wmTDRAjDPMJow0wIw0jCZMNQCMNIwmjDWAjDVMJkw1wIw1TCaMNkCMNgw'
    'mTDaAjDYMJow3AIw2zCZMN0CMNswmjD0AjCmMJkw9wIw7zCZMPgCMPAwmTD5AjDxMJkw+gIw8jCZMP4CMP0wmfsdAgXZBbT7HwIF'
    '8gW3+yoCBekFwfsrAgXpBcL7LAMF6QW8BcH7LQMF6QW8BcL7LgIF0AW3+y8CBdAFuPswAgXQBbz7MQIF0QW8+zICBdIFvPszAgXT'
    'Bbz7NAIF1AW8+zUCBdUFvPs2AgXWBbz7OAIF2AW8+zkCBdkFvPs6AgXaBbz7OwIF2wW8+zwCBdwFvPs+AgXeBbz7QAIF4AW8+0EC'
    'BeEFvPtDAgXjBbz7RAIF5AW8+0YCBeYFvPtHAgXnBbz7SAIF6AW8+0kCBekFvPtKAgXqBbz7SwIF1QW5+0wCBdEFv/tNAgXbBb/7'
    'TgIF5AW/';
const _combiningData =
    'AwDmAwHmAwLmAwPmAwTmAwXmAwbmAwfmAwjmAwnmAwrmAwvmAwzmAw3mAw7mAw/mAxDmAxHmAxLmAxPmAxTmAxXoAxbcAxfcAxjc'
    'AxncAxroAxvYAxzcAx3cAx7cAx/cAyDcAyHKAyLKAyPcAyTcAyXcAybcAyfKAyjKAyncAyrcAyvcAyzcAy3cAy7cAy/cAzDcAzHc'
    'AzLcAzPcAzQBAzUBAzYBAzcBAzgBAzncAzrcAzvcAzzcAz3mAz7mAz/mA0DmA0HmA0LmA0PmA0TmA0XwA0bmA0fcA0jcA0ncA0rm'
    'A0vmA0zmA03cA07cA2DqA2HqA2LpA2PmA2TmA2XmA2bmA2fmA2jmA2nmA2rmA2vmA2zmA23mA27mA2/mBIPmBITmBIXmBIbmBZHc'
    'BZLmBZPmBZTmBZXmBZbcBZfmBZjmBZnmBZreBZvcBZzmBZ3mBZ7mBZ/mBaDmBaHmBaPcBaTcBaXcBabcBafcBajmBanmBarcBavm'
    'BazmBa3eBa7kBa/mBbAKBbELBbIMBbMNBbQOBbUPBbYQBbcRBbgSBbkTBbsUBbwVBb0WBb8XBcEYBcIZBcTmBksbBkwcBk0dBk4e'
    'Bk8fBlAgBlEhBlIiBlPmBlTmBlXcBnAjBtbmBtfmBtjmBtnmBtrmBtvmBtzmBt/mBuDmBuHmBuLmBuPcBuTmBufmBujmBurcBuvm'
    'BuzmBu3cBxEkBzDmBzHcBzLmBzPmBzTcBzXmBzbmBzfcBzjcBzncBzrmBzvcBzzcBz3mBz7cBz/mB0DmB0HmB0LcB0PmB0TcB0Xm'
    'B0bcB0fmB0jcB0nmB0rmCTwHCU0JCVHmCVLcCVPmCVTmCbwHCc0JCjwHCk0JCrwHCs0JCzwHC00JC80JDE0JDFVUDFZbDM0JDU0J'
    'DcoJDjhnDjlnDjoJDkhrDklrDkprDktrDrh2Drl2Dsh6Dsl6Dsp6Dst6DxjcDxncDzXcDzfcDznYD3GBD3KCD3SED3qCD3uCD3yC'
    'D32CD4CCD4LmD4PmD4QJD4bmD4fmD8bcEDcHEDkJFxQJFzQJF9IJGKnkINDmINHmINIBINMBINTmINXmINbmINfmINgBINkBINoB'
    'INvmINzmIOHmIOUBIOYBIOfmIOjcIOnmIOoBMCraMCvkMCzoMC3eMC7gMC/gMJkIMJoI+x4a/iDm/iHm/iLm/iPm';
