import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import 'archive_types.dart';
import 'archive_write_model.dart';

const _sector = 2048;
const _metadataLimit = 32 * 1024 * 1024;
const _continuationLimit = 8 * 1024 * 1024;
const _chunkSize = 256 * 1024;
const _nameLimit = 1024;

/// This data-only profile stores each regular member in one ISO extent.
/// Images may be larger, but multi-extent members remain unsupported.
const kArchiveIsoSingleExtentLimit = 0xffffffff;

/// Builds a data-only ISO 9660 image with Joliet and Rock Ridge names.
///
/// File contents are streamed after the checked metadata layout. Regular files
/// and directories are supported; this writer never manufactures boot records,
/// follows links, or silently rewrites an uninspected source image. Rock Ridge
/// retains exact UTF-8 names, including names longer than Joliet's UCS-2 limit.
/// Such names have a stable, collision-free alternative in the Joliet tree.
Future<void> writeIsoArchive(
  List<ArchiveWriteEntry> entries, {
  required Future<void> Function(List<int>) sink,
  ArchiveRewriteInspection? source,
  int maxOutputBytes = 2 * 1024 * 1024 * 1024,
  bool Function()? isCancelled,
}) async {
  if (maxOutputBytes <= 0 || maxOutputBytes > 0x1fffffffffffff) {
    throw ArgumentError.value(maxOutputBytes, 'maxOutputBytes');
  }
  if (source != null &&
      (!source.supported || source.container['iso.profile'] != 1)) {
    throw ArchiveViewException(
      source.reason ?? 'This ISO has no supported rewrite inspection.',
    );
  }
  final image = _IsoImage(entries, source)..plan(maxOutputBytes);
  var written = 0;
  void check() {
    if (isCancelled?.call() ?? false) {
      throw const ArchiveViewException('ISO creation was cancelled.');
    }
  }

  Future<void> emit(List<int> bytes) async {
    for (var at = 0; at < bytes.length; at += _chunkSize) {
      check();
      final end = at + _chunkSize < bytes.length
          ? at + _chunkSize
          : bytes.length;
      if (end - at > maxOutputBytes - written) {
        throw const ArchiveViewException('The ISO exceeds its output limit.');
      }
      await sink(Uint8List.fromList(bytes.sublist(at, end)));
      written += end - at;
    }
  }

  Future<void> zero(int count) async {
    while (count > 0) {
      final take = count < _chunkSize ? count : _chunkSize;
      await emit(Uint8List(take));
      count -= take;
    }
  }

  check();
  await zero(16 * _sector);
  await emit(image.descriptor(false));
  await emit(image.descriptor(true));
  final terminator = Uint8List(_sector)..setAll(0, [255, ..._magic, 1]);
  await emit(terminator);
  for (final tree in [image.primary, image.joliet]) {
    for (final big in [false, true]) {
      final table = tree.pathTable(big);
      await emit(table);
      await zero(_round(table.length) - table.length);
    }
  }
  for (final tree in [image.primary, image.joliet]) {
    for (final directory in tree.directories) {
      await emit(directory.bytes());
      for (final record in directory.continuations) {
        await zero(record.continuationOffset - written);
        await emit(record.continuation!);
      }
      await zero(directory.endByteOffset - written);
    }
  }
  for (final node in image.files) {
    check();
    await for (final bytes in node.entry!.openRead(chunkSize: _chunkSize)) {
      await emit(bytes);
    }
    await zero(_round(node.size) - node.size);
  }
  check();
  if (written != image.byteLength) {
    throw const ArchiveViewException('The ISO output length is inconsistent.');
  }
}

/// Inspects every ISO hierarchy and all bytes outside regular file payloads.
///
/// Eligibility is deliberately narrower than readability. Boot/system areas,
/// UDF bridges, extra sessions/partitions, unknown SUSP/application metadata,
/// unsafe entries and ambiguous alternate hierarchies keep a source read-only.
/// Supported volume fields, alternate names, ownership and timestamps are
/// returned explicitly for the replacement writer.
Future<ArchiveRewriteInspection> inspectIsoRewrite(
  Uint8List bytes,
  ViewerArchive archive,
) => inspectIsoRewriteSource(
  koni.MemoryByteSource(bytes),
  archive,
  maxBytes: 2 * 1024 * 1024 * 1024,
);

/// Inspects a repeatable ISO source without collecting its image or payloads.
///
/// Reads bounded volume/directory/continuation metadata and scans every
/// unclaimed padding range so hidden boot, hybrid, UDF or application data
/// cannot be silently discarded. Regular payload extents are range-checked
/// and skipped. [source] must represent the same immutable snapshot as
/// [archive]. The caller retains ownership of both.
/// Cancellation throws rather than producing a read-only policy result.
Future<ArchiveRewriteInspection> inspectIsoRewriteSource(
  koni.ByteSource source,
  ViewerArchive archive, {
  int maxBytes = kArchiveStreamingLimit,
  bool Function()? isCancelled,
}) async {
  if (maxBytes <= 0 || maxBytes > kArchiveStreamingLimit) {
    throw ArgumentError.value(maxBytes, 'maxBytes');
  }
  try {
    return await _IsoInspection(
      source,
      archive,
      maxBytes,
      isCancelled,
    ).inspect();
  } on _IsoInspectionCancelled {
    rethrow;
  } on _IsoRefusal catch (error) {
    return ArchiveRewriteInspection(reason: error.message);
  } on ArchiveViewException catch (error) {
    return ArchiveRewriteInspection(reason: error.message);
  } on FormatException {
    return ArchiveRewriteInspection(reason: 'The ISO contains invalid text.');
  } on RangeError {
    return ArchiveRewriteInspection(reason: 'The ISO metadata is truncated.');
  }
}

const _magic = [0x43, 0x44, 0x30, 0x30, 0x31];

int _round(int bytes) => (bytes + _sector - 1) ~/ _sector * _sector;

Never _writeError(String message) => throw ArchiveViewException(message);

class _IsoNode {
  _IsoNode(this.path, this.directory, this.entry, this.attributes);

  final String path;
  final bool directory;
  ArchiveWriteEntry? entry;
  final Map<String, Object?> attributes;
  _IsoNode? parent;
  final List<_IsoNode> children = [];
  Uint8List primaryName = Uint8List(0);
  Uint8List jolietName = Uint8List(0);
  int fileSector = 0;
  int serial = 0;

  String get name => path.isEmpty ? '' : path.split('/').last;
  int get size => entry?.size ?? 0;
  DateTime? get modified => entry?.modified ?? _savedDate(attributes);
  int get mode {
    final value = entry?.mode ?? attributes['iso.mode'];
    final bits = value is int ? value : (directory ? 0x41ed : 0x81a4);
    if (bits < 0 ||
        bits > 0xffff ||
        (bits & 0xf000 != 0 &&
            bits & 0xf000 != (directory ? 0x4000 : 0x8000))) {
      _writeError('ISO writing supports regular files and directories: $path');
    }
    return (bits & 0x0fff) | (directory ? 0x4000 : 0x8000);
  }
}

class _IsoImage {
  _IsoImage(this.entries, this.source);

  final List<ArchiveWriteEntry> entries;
  final ArchiveRewriteInspection? source;
  late _IsoNode root;
  late _IsoTree primary;
  late _IsoTree joliet;
  final List<_IsoNode> files = [];
  int byteLength = 0;

  void plan(int maxBytes) {
    validateArchiveWriteEntries(entries, maxEntries: 100000);
    root = _IsoNode('', true, null, _map(source?.container['iso.root']));
    final nodes = <String, _IsoNode>{'': root};
    final ordered = List<ArchiveWriteEntry>.of(entries)
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final entry in ordered) {
      if (entry.path.contains(':')) {
        _writeError('ISO member names cannot contain a colon: ${entry.path}');
      }
      final parts = entry.path.split('/');
      if (utf8.decode(utf8.encode(entry.path)) != entry.path ||
          parts.any((part) => utf8.encode(part).length > _nameLimit)) {
        _writeError(
          'ISO names must be valid Unicode and at most $_nameLimit UTF-8 bytes.',
        );
      }
      // The ordinary primary hierarchy has no Rock Ridge relocation records.
      if (parts.length > (entry.isDirectory ? 7 : 8)) {
        _writeError('ISO writing supports at most eight directory levels.');
      }
      if (entry.size > kArchiveIsoSingleExtentLimit) {
        _writeError('Multi-extent ISO files are not supported.');
      }
      var parent = root;
      var path = '';
      for (var i = 0; i < parts.length; i++) {
        path = path.isEmpty ? parts[i] : '$path/${parts[i]}';
        final last = i == parts.length - 1;
        final existing = nodes[path];
        if (existing != null) {
          if (!existing.directory || last && !entry.isDirectory) {
            _writeError('An ISO file occupies a directory: $path');
          }
          if (last) {
            existing.entry = entry;
            existing.attributes.addAll(entry.attributes);
          }
          parent = existing;
          continue;
        }
        final attributes = <String, Object?>{
          ...?source?.attributes[path],
          if (last) ...entry.attributes,
        };
        final node = _IsoNode(
          path,
          !last || entry.isDirectory,
          last ? entry : null,
          attributes,
        )..parent = parent;
        parent.children.add(node);
        nodes[path] = node;
        parent = node;
      }
    }
    if (nodes.length > 100001) _writeError('Too many ISO directory entries.');
    final usedSerials = <int>{};
    for (final node in nodes.values) {
      final saved = _uintAttribute(node.attributes, 'iso.serial');
      if (saved != 0 && !usedSerials.add(saved)) {
        _writeError('Hard-linked ISO serial numbers cannot be rewritten.');
      }
    }
    var serial = 1;
    for (final node in nodes.values) {
      final saved = _uintAttribute(node.attributes, 'iso.serial');
      while (usedSerials.contains(serial)) {
        serial++;
      }
      node.serial = saved == 0 ? serial++ : saved;
      node.mode;
      _directoryDate(node, node.attributes);
      node.children.sort((a, b) => a.name.compareTo(b.name));
      _assignNames(node.children, false);
      _assignNames(node.children, true);
      if (!node.directory) files.add(node);
    }
    for (final node in nodes.values) {
      var units = 0;
      for (
        var current = node;
        current.parent != null;
        current = current.parent!
      ) {
        units += current.jolietName.length ~/ 2 + (units == 0 ? 0 : 1);
      }
      if (units > 120) {
        _writeError('A Joliet alternate path exceeds its 240-byte limit.');
      }
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    primary = _IsoTree(root, false);
    joliet = _IsoTree(root, true);
    var sector = 19;
    for (final tree in [primary, joliet]) {
      if (tree.directories.length > 65535) {
        _writeError('The ISO path table has too many directories.');
      }
      tree.littlePathSector = sector;
      sector += _round(tree.pathSize) ~/ _sector;
      tree.bigPathSector = sector;
      sector += _round(tree.pathSize) ~/ _sector;
    }
    var metadata = 0;
    var continuationBytes = 0;
    for (final tree in [primary, joliet]) {
      for (final directory in tree.directories) {
        directory.sector = sector;
        sector += directory.size ~/ _sector;
        metadata += directory.size;
        if (directory.size > 8 * 1024 * 1024 || metadata > _metadataLimit) {
          _writeError('The ISO directory metadata exceeds its writing limit.');
        }
        var localBytes = 0;
        final start = sector * _sector;
        for (final record in directory.continuations) {
          final count = record.continuation!.length;
          if (count > _sector) {
            _writeError('An ISO continuation exceeds one sector.');
          }
          if (localBytes % _sector + count > _sector) {
            localBytes = _round(localBytes);
          }
          record.continuationOffset = start + localBytes;
          localBytes += count;
          continuationBytes += count;
          if (continuationBytes > _continuationLimit) {
            _writeError('ISO continuation metadata exceeds its writing limit.');
          }
        }
        sector += _round(localBytes) ~/ _sector;
        directory.endByteOffset = sector * _sector;
      }
    }
    for (final node in files) {
      node.fileSector = sector;
      sector += _round(node.size) ~/ _sector;
      if (sector > 0xffffffff || sector > maxBytes ~/ _sector) {
        _writeError('The ISO exceeds its output limit.');
      }
    }
    byteLength = sector * _sector;
    if (byteLength > maxBytes) _writeError('The ISO exceeds its output limit.');
  }

  Uint8List descriptor(bool unicode) {
    final tree = unicode ? joliet : primary;
    final saved =
        source?.container[unicode ? 'iso.jolietVolume' : 'iso.volume'];
    final data = saved is String ? base64.decode(saved) : Uint8List(_sector);
    if (data.length != _sector) _writeError('Invalid ISO volume metadata.');
    final result = Uint8List.fromList(data);
    result.setAll(0, [unicode ? 2 : 1, ..._magic, 1, 0]);
    if (saved == null) {
      for (final field in const [
        (8, 32),
        (40, 32),
        (190, 128),
        (318, 128),
        (446, 128),
        (574, 128),
        (702, 37),
        (739, 37),
        (776, 37),
      ]) {
        _label(result, field.$1, field.$2, '', unicode);
      }
      _label(result, 40, 32, 'CRISPCLOUD', unicode);
      _label(result, 574, 128, 'CRISPCLOUD', unicode);
      for (final offset in [813, 830, 847, 864]) {
        result.setAll(offset, ascii.encode('0000000000000000'));
      }
    }
    result.fillRange(88, 120, 0);
    if (unicode) result.setAll(88, [0x25, 0x2f, 0x45]);
    _both32(result, 80, byteLength ~/ _sector);
    _both16(result, 120, 1);
    _both16(result, 124, 1);
    _both16(result, 128, _sector);
    _both32(result, 132, tree.pathSize);
    final view = ByteData.sublistView(result);
    view.setUint32(140, tree.littlePathSector, Endian.little);
    view.setUint32(144, 0, Endian.little);
    view.setUint32(148, tree.bigPathSector, Endian.big);
    view.setUint32(152, 0, Endian.big);
    final record = _baseRecord(
      [0],
      tree.directories.first.sector,
      tree.directories.first.size,
      true,
      saved == null
          ? _directoryDate(root, root.attributes)
          : data.sublist(174, 181),
      0,
    );
    result.setRange(156, 190, record);
    result[881] = 1;
    return result;
  }
}

class _IsoTree {
  _IsoTree(_IsoNode root, this.unicode) {
    final pending = <_IsoNode>[root];
    for (var at = 0; at < pending.length; at++) {
      final node = pending[at];
      final directory = _OutputDirectory(this, node, directories.length + 1);
      directories.add(directory);
      byNode[node] = directory;
      final children = node.children.where((child) => child.directory).toList()
        ..sort((a, b) => _compare(identifier(a), identifier(b)));
      pending.addAll(children);
    }
    for (final directory in directories) {
      directory.plan();
      final name = directory.node.parent == null
          ? [0]
          : identifier(directory.node);
      pathSize += 8 + name.length + name.length % 2;
    }
  }

  final bool unicode;
  final List<_OutputDirectory> directories = [];
  final Map<_IsoNode, _OutputDirectory> byNode = {};
  int littlePathSector = 0;
  int bigPathSector = 0;
  int pathSize = 0;
  Uint8List identifier(_IsoNode node) =>
      unicode ? node.jolietName : node.primaryName;

  Uint8List pathTable(bool big) {
    final output = Uint8List(pathSize);
    final view = ByteData.sublistView(output);
    final order = big ? Endian.big : Endian.little;
    var at = 0;
    for (final directory in directories) {
      final node = directory.node;
      final name = node.parent == null ? [0] : identifier(node);
      output[at] = name.length;
      view.setUint32(at + 2, directory.sector, order);
      view.setUint16(at + 6, byNode[node.parent ?? node]!.number, order);
      output.setAll(at + 8, name);
      at += 8 + name.length + name.length % 2;
    }
    return output;
  }
}

class _OutputDirectory {
  _OutputDirectory(this.tree, this.node, this.number);
  final _IsoTree tree;
  final _IsoNode node;
  final int number;
  final List<_OutputRecord> records = [];
  final List<_OutputRecord> continuations = [];
  int sector = 0;
  int size = 0;
  int endByteOffset = 0;

  void plan() {
    records.add(_OutputRecord(tree, node, [0], rootSelf: node.parent == null));
    records.add(_OutputRecord(tree, node.parent ?? node, [1]));
    final children = List<_IsoNode>.of(node.children)
      ..sort((a, b) => _compare(tree.identifier(a), tree.identifier(b)));
    for (final child in children) {
      records.add(
        _OutputRecord(tree, child, tree.identifier(child), named: true),
      );
    }
    var offset = 0;
    for (final record in records) {
      if (record.continuation != null) continuations.add(record);
      if (offset % _sector + record.length > _sector) offset = _round(offset);
      record.directoryOffset = offset;
      offset += record.length;
    }
    size = _round(offset);
  }

  Uint8List bytes() {
    final output = Uint8List(size);
    for (final record in records) {
      output.setAll(record.directoryOffset, record.bytes());
    }
    return output;
  }
}

class _OutputRecord {
  _OutputRecord(
    this.tree,
    this.node,
    this.identifier, {
    bool rootSelf = false,
    bool named = false,
  }) {
    if (!tree.unicode) {
      final fields = <int>[];
      List<int>? extensionRecord;
      var rootPrefixLength = 0;
      if (rootSelf) {
        fields.addAll([0x53, 0x50, 7, 1, 0xbe, 0xef, 0]);
        final er = node.attributes['iso.er'];
        extensionRecord = er is String
            ? base64.decode(er)
            : [0x45, 0x52, 18, 1, 10, 0, 0, 1, ...ascii.encode('RRIP_1991A')];
      }
      final px = Uint8List(44)..setAll(0, [0x50, 0x58, 44, 1]);
      _both32(px, 4, node.mode);
      _both32(
        px,
        12,
        node.directory
            ? 2 + node.children.where((child) => child.directory).length
            : 1,
      );
      _both32(px, 20, _uintAttribute(node.attributes, 'iso.uid'));
      _both32(px, 28, _uintAttribute(node.attributes, 'iso.gid'));
      _both32(px, 36, node.serial);
      fields.addAll(px);
      fields.addAll(_timeField(node));
      if (extensionRecord != null) {
        // Keep PX/TF inline so independent readers detect Rock Ridge before
        // choosing a hierarchy, even when the ER description is continued.
        rootPrefixLength = fields.length;
        fields.addAll(extensionRecord);
      }
      if (named) {
        final name = utf8.encode(node.name);
        for (var at = 0; at < name.length; at += 250) {
          final end = at + 250 < name.length ? at + 250 : name.length;
          fields.addAll([
            0x4e,
            0x4d,
            5 + end - at,
            1,
            end < name.length ? 1 : 0,
            ...name.sublist(at, end),
          ]);
        }
      }
      // The record/continuation length already delimits SUSP. Omitting the
      // optional ST field also interoperates with older libarchive readers
      // that stop recognizing Rock Ridge after a four-byte ST field.
      systemUse = Uint8List.fromList(fields);
      if (_baseLength(identifier.length) + fields.length > 254) {
        // SP must remain in the root self record, even when a preserved ER
        // description requires a continuation. Readers discover SUSP there.
        continuationFieldOffset = rootSelf ? rootPrefixLength : 0;
        continuation = Uint8List.fromList(
          fields.sublist(continuationFieldOffset),
        );
        systemUse = Uint8List(continuationFieldOffset + 28)
          ..setAll(0, fields.take(continuationFieldOffset))
          ..setAll(continuationFieldOffset, [0x43, 0x45, 28, 1]);
      }
    }
    final count = _baseLength(identifier.length) + systemUse.length;
    length = count + count % 2;
    if (length > 254) _writeError('An ISO directory record is too long.');
  }
  final _IsoTree tree;
  final _IsoNode node;
  final List<int> identifier;
  Uint8List systemUse = Uint8List(0);
  Uint8List? continuation;
  int continuationFieldOffset = 0;
  int continuationOffset = 0;
  int directoryOffset = 0;
  late int length;

  Uint8List bytes() {
    final dir = node.directory ? tree.byNode[node]! : null;
    final attrs = node.attributes;
    final saved = tree.unicode ? _map(attrs['iso.jolietMetadata']) : attrs;
    final flags = _uintAttribute(saved, 'iso.flags') & 1;
    final result = _baseRecord(
      identifier,
      dir?.sector ?? node.fileSector,
      dir?.size ?? node.size,
      node.directory,
      _directoryDate(node, saved),
      flags,
      extra: systemUse.length,
    );
    final use = Uint8List.fromList(systemUse);
    if (continuation != null) {
      _both32(use, continuationFieldOffset + 4, continuationOffset ~/ _sector);
      _both32(use, continuationFieldOffset + 12, continuationOffset % _sector);
      _both32(use, continuationFieldOffset + 20, continuation!.length);
    }
    result.setAll(_baseLength(identifier.length), use);
    return result;
  }
}

int _baseLength(int length) => 33 + length + (length.isEven ? 1 : 0);

Uint8List _baseRecord(
  List<int> name,
  int sector,
  int size,
  bool directory,
  List<int> date,
  int flags, {
  int extra = 0,
}) {
  final count = _baseLength(name.length) + extra;
  final output = Uint8List(count + count % 2);
  output[0] = output.length;
  _both32(output, 2, sector);
  _both32(output, 10, size);
  output.setAll(18, date);
  output[25] = flags | (directory ? 2 : 0);
  _both16(output, 28, 1);
  output[32] = name.length;
  output.setAll(33, name);
  return output;
}

void _assignNames(List<_IsoNode> children, bool unicode) {
  final used = <String>{};
  // Reserve preserved identifiers before assigning names to added siblings.
  final saved = <_IsoNode, String>{};
  for (final child in children) {
    if (child.attributes['iso.name'] != null &&
        child.attributes['iso.name'] != child.name) {
      // A rename changes every filename view while retaining other metadata.
      continue;
    }
    final name =
        child.attributes[unicode ? 'iso.jolietIdentifier' : 'iso.identifier'];
    if (name is String) {
      _validateIdentifier(name, child.directory, unicode);
      if (!used.add(name.toUpperCase())) {
        _writeError('Conflicting preserved ISO names.');
      }
      saved[child] = name;
    }
  }
  for (final child in children) {
    var name = saved[child];
    if (name == null) {
      var attempt = 0;
      do {
        name = unicode
            ? _jolietIdentifier(child.name, child.directory, attempt)
            : _primaryIdentifier(child.name, child.directory, attempt);
        attempt++;
      } while (!used.add(name.toUpperCase()));
    }
    if (unicode) {
      child.jolietName = _ucs2(name);
    } else {
      child.primaryName = Uint8List.fromList(ascii.encode(name));
    }
  }
}

String _digest(String name, int attempt) => sha256
    .convert(utf8.encode('$name\u0000$attempt'))
    .toString()
    .substring(0, 8)
    .toUpperCase();

String _primaryIdentifier(String name, bool directory, int attempt) {
  final upper = name.toUpperCase();
  if (attempt == 0 &&
      (directory
              ? RegExp(r'^[A-Z0-9_]{1,31}$')
              : RegExp(r'^[A-Z0-9_]{1,26}(\.[A-Z0-9_]{0,3})?$'))
          .hasMatch(upper)) {
    return directory ? upper : '${upper.contains('.') ? upper : '$upper.'};1';
  }
  final dot = directory ? -1 : name.lastIndexOf('.');
  final base = (dot > 0 ? name.substring(0, dot) : name)
      .toUpperCase()
      .replaceAll(RegExp('[^A-Z0-9_]'), '_');
  final extension = dot > 0
      ? name
            .substring(dot + 1)
            .toUpperCase()
            .replaceAll(RegExp('[^A-Z0-9_]'), '_')
      : '';
  final prefix = base.isEmpty
      ? 'FILE'
      : base.substring(0, base.length < 16 ? base.length : 16);
  final hash = _digest(name, attempt);
  if (directory) return '${prefix}_$hash';
  final ext = extension.substring(
    0,
    extension.length < 3 ? extension.length : 3,
  );
  return '${prefix}_$hash.$ext;1';
}

String _jolietIdentifier(String name, bool directory, int attempt) {
  final limit = directory ? 64 : 62;
  final units = <int>[];
  var changed = false;
  for (final rune in name.runes) {
    if (rune > 0xffff) {
      units.add(0x5f);
      changed = true;
    } else {
      units.add(rune);
    }
  }
  var result = String.fromCharCodes(units);
  if (attempt > 0 || changed || units.length > limit) {
    final prefix = result.substring(
      0,
      result.length < limit - 9 ? result.length : limit - 9,
    );
    result = '${prefix}_${_digest(name, attempt)}';
  }
  return directory ? result : '$result;1';
}

void _validateIdentifier(String name, bool directory, bool unicode) {
  if (name.isEmpty ||
      name.contains(RegExp(r'[/\\:\x00-\x1f\x7f]')) ||
      name.codeUnits.any((unit) => unit >= 0xd800 && unit <= 0xdfff) ||
      unicode && name.length > 64 ||
      !unicode &&
          (name.length > 31 || !RegExp(r'^[A-Z0-9_.;]+$').hasMatch(name)) ||
      !directory && !unicode && !RegExp(r';[1-9][0-9]*$').hasMatch(name)) {
    _writeError('Unsupported preserved ISO identifier: $name');
  }
}

Uint8List _ucs2(String value) => Uint8List.fromList([
  for (final unit in value.codeUnits) ...[unit >> 8, unit & 255],
]);

void _label(
  Uint8List bytes,
  int offset,
  int count,
  String value,
  bool unicode,
) {
  if (unicode) {
    for (var at = 0; at + 1 < count; at += 2) {
      bytes[offset + at] = 0;
      bytes[offset + at + 1] = 32;
    }
    final text = _ucs2(value);
    bytes.setRange(
      offset,
      offset + (text.length < count ? text.length : count),
      text,
    );
  } else {
    bytes.fillRange(offset, offset + count, 32);
    final text = ascii.encode(value);
    bytes.setRange(
      offset,
      offset + (text.length < count ? text.length : count),
      text,
    );
  }
}

Map<String, Object?> _map(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : <String, Object?>{};

int _uintAttribute(
  Map<String, Object?> attributes,
  String key, {
  int fallback = 0,
}) {
  final value = attributes[key];
  if (value == null) return fallback;
  if (value is! int || value < 0 || value > 0xffffffff) {
    _writeError('Invalid ISO metadata: $key');
  }
  return value;
}

DateTime? _savedDate(Map<String, Object?> attributes) {
  final date = attributes['iso.modified'];
  return date is int
      ? DateTime.fromMillisecondsSinceEpoch(date, isUtc: true)
      : null;
}

Uint8List _directoryDate(_IsoNode node, Map<String, Object?> attributes) {
  final date = node.modified;
  final saved = attributes['iso.date'];
  if (saved is String && date == _savedDate(node.attributes)) {
    final bytes = base64.decode(saved);
    if (bytes.length != 7) _writeError('Invalid ISO timestamp metadata.');
    _decodeDate(bytes);
    return bytes;
  }
  final utc = (date ?? DateTime.utc(1970)).toUtc();
  if (utc.year < 1900 || utc.year > 2155) {
    _writeError('ISO timestamps require a year from 1900 to 2155.');
  }
  return Uint8List.fromList([
    utc.year - 1900,
    utc.month,
    utc.day,
    utc.hour,
    utc.minute,
    utc.second,
    0,
  ]);
}

Uint8List _timeField(_IsoNode node) {
  final stored = node.attributes['iso.tf'];
  if (stored is String) {
    final bytes = base64.decode(stored);
    _checkTf(bytes);
    if (node.modified == _savedDate(node.attributes)) return bytes;
    if (bytes[4] & 2 != 0) {
      final width = bytes[4] & 0x80 != 0 ? 17 : 7;
      final offset = 5 + (bytes[4] & 1 != 0 ? width : 0);
      bytes.setAll(
        offset,
        width == 7
            ? _directoryDate(node, const {})
            : _longDate(node.modified ?? DateTime.utc(1970)),
      );
    }
    return bytes;
  }
  return Uint8List.fromList([
    0x54,
    0x46,
    12,
    1,
    2,
    ..._directoryDate(node, node.attributes),
  ]);
}

Uint8List _longDate(DateTime date) {
  final utc = date.toUtc();
  String number(int value, int width) => value.toString().padLeft(width, '0');
  return Uint8List.fromList([
    ...ascii.encode(
      '${number(utc.year, 4)}${number(utc.month, 2)}${number(utc.day, 2)}${number(utc.hour, 2)}${number(utc.minute, 2)}${number(utc.second, 2)}${number(utc.millisecond ~/ 10, 2)}',
    ),
    0,
  ]);
}

void _both16(Uint8List bytes, int offset, int value) {
  final view = ByteData.sublistView(bytes);
  view.setUint16(offset, value, Endian.little);
  view.setUint16(offset + 2, value, Endian.big);
}

void _both32(Uint8List bytes, int offset, int value) {
  final view = ByteData.sublistView(bytes);
  view.setUint32(offset, value, Endian.little);
  view.setUint32(offset + 4, value, Endian.big);
}

int _compare(List<int> a, List<int> b) {
  for (var i = 0; i < a.length && i < b.length; i++) {
    if (a[i] != b[i]) return a[i].compareTo(b[i]);
  }
  return a.length.compareTo(b.length);
}

class _IsoRefusal implements Exception {
  _IsoRefusal(this.message);
  final String message;
}

class _IsoInspectionCancelled extends ArchiveViewException {
  const _IsoInspectionCancelled() : super('ISO inspection was cancelled.');
}

Never _refuse(String message) =>
    throw _IsoRefusal('ISO remains read-only: $message');

DateTime? _decodeDate(Uint8List bytes) {
  if (bytes.every((value) => value == 0)) return null;
  final zone = bytes[6] >= 128 ? bytes[6] - 256 : bytes[6];
  if (bytes[1] < 1 ||
      bytes[1] > 12 ||
      bytes[2] < 1 ||
      bytes[2] > 31 ||
      bytes[3] > 23 ||
      bytes[4] > 59 ||
      bytes[5] > 59 ||
      zone < -48 ||
      zone > 52) {
    _refuse('an invalid directory timestamp cannot be preserved.');
  }
  final value = DateTime.utc(
    bytes[0] + 1900,
    bytes[1],
    bytes[2],
    bytes[3],
    bytes[4],
    bytes[5],
  );
  if (value.month != bytes[1] || value.day != bytes[2]) {
    _refuse('an invalid directory date cannot be preserved.');
  }
  return value.subtract(Duration(minutes: zone * 15));
}

void _checkTf(Uint8List bytes) {
  if (bytes.length < 5 ||
      bytes[0] != 0x54 ||
      bytes[1] != 0x46 ||
      bytes[2] != bytes.length ||
      bytes[3] != 1) {
    _refuse('invalid Rock Ridge timestamps.');
  }
  final width = bytes[4] & 0x80 != 0 ? 17 : 7;
  var count = 0;
  for (var bit = 0; bit < 7; bit++) {
    if (bytes[4] & (1 << bit) != 0) count++;
  }
  if (bytes.length != 5 + count * width) {
    _refuse('invalid Rock Ridge timestamp lengths.');
  }
  for (var at = 5; at < bytes.length; at += width) {
    if (width == 7) {
      _decodeDate(Uint8List.sublistView(bytes, at, at + width));
    } else {
      final text = ascii.decode(bytes.sublist(at, at + 16));
      final zone = bytes[at + 16] >= 128
          ? bytes[at + 16] - 256
          : bytes[at + 16];
      if (!RegExp(r'^[0-9]{16}$').hasMatch(text) || zone < -48 || zone > 52) {
        _refuse('invalid long Rock Ridge timestamps.');
      }
    }
  }
}

// The inspector below is intentionally independent of the browsing reader's
// selected-hierarchy shortcuts: editing must account for every stored tree.
class _IsoInspection {
  _IsoInspection(this.source, this.archive, this.maxBytes, this.isCancelled);
  final koni.ByteSource source;
  final ViewerArchive archive;
  final int maxBytes;
  final bool Function()? isCancelled;
  final List<(int, int, String)> regions = [];
  final Map<String, Map<String, Object?>> attributes = {};
  int volumeBytes = 0;
  int metadataBytes = 0;
  int continuationBytes = 0;
  int entries = 0;
  int descriptorEnd = 0;

  void _check() {
    if (isCancelled?.call() ?? false) {
      throw const _IsoInspectionCancelled();
    }
    if (archive.isClosed) _refuse('the browsing reader was closed.');
  }

  Future<ArchiveRewriteInspection> inspect() async {
    _check();
    if (archive.formatName != 'iso' ||
        source.length < 18 * _sector ||
        source.length % _sector != 0) {
      _refuse('only complete 2048-byte-sector ISO images are supported.');
    }
    if (source.length > maxBytes) {
      _refuse('the image exceeds the rewrite inspection limit.');
    }
    if ((await _slice(0, 16 * _sector)).any((value) => value != 0)) {
      _refuse('the System Area contains boot, hybrid or other data.');
    }
    Uint8List? primary;
    Uint8List? joliet;
    for (var sector = 16; sector < 144; sector++) {
      final descriptor = await _slice(sector * _sector, _sector);
      if (_compare(descriptor.sublist(1, 6), _magic) != 0 ||
          descriptor[6] != 1) {
        _refuse('a non-ISO descriptor or UDF bridge is present.');
      }
      if (descriptor[0] == 255) {
        if (descriptor.sublist(7).any((value) => value != 0)) {
          _refuse('unknown descriptor terminator metadata.');
        }
        descriptorEnd = (sector + 1) * _sector;
        break;
      }
      if (descriptor[0] == 1 && primary == null) {
        primary = descriptor;
      } else if (descriptor[0] == 2 &&
          joliet == null &&
          descriptor[7] == 0 &&
          descriptor[88] == 0x25 &&
          descriptor[89] == 0x2f &&
          const [0x40, 0x43, 0x45].contains(descriptor[90])) {
        joliet = descriptor;
      } else {
        _refuse(
          'boot, partition, duplicate or unsupported volume descriptors are present.',
        );
      }
    }
    if (primary == null || descriptorEnd == 0) {
      _refuse('the primary volume descriptor is incomplete.');
    }
    volumeBytes = _dual32(primary, 80) * _sector;
    if (volumeBytes < descriptorEnd || volumeBytes > source.length) {
      _refuse('the declared volume size is invalid.');
    }
    _claim(0, descriptorEnd, 'descriptors');
    _volume(primary, false);
    if (joliet != null) _volume(joliet, true);
    final main = await _tree(primary, false);
    final alternate = joliet == null ? null : await _tree(joliet, true);
    _checkDuplicateRecords(main);
    if (alternate != null) _checkDuplicateRecords(alternate);
    final rock = main.rock;
    final selected = rock || alternate == null ? main : alternate;
    if (alternate != null) _pair(main, alternate);
    final listed = <String, _InspectedNode>{};
    void visit(_InspectedNode node, String parent) {
      for (final child in node.children) {
        final path = parent.isEmpty ? child.name : '$parent/${child.name}';
        if (listed.containsKey(path)) _refuse('duplicate member paths.');
        listed[path] = child;
        attributes[path] = child.attributes;
        if (child.directory) visit(child, path);
      }
    }

    visit(selected, '');
    if (listed.length != archive.members.length) {
      _refuse('the browsing and stored hierarchies disagree.');
    }
    for (final member in archive.members) {
      _check();
      final node = listed[member.name];
      if (node == null ||
          member.isSpecial ||
          member.pathEscapedRoot ||
          member.isFile == node.directory ||
          member.size != (node.directory ? 0 : node.size) ||
          member.modified != node.modified) {
        _refuse('a member cannot be faithfully represented by this writer.');
      }
      if (node.directory && member.name.split('/').length > 7 ||
          !node.directory && member.name.split('/').length > 8) {
        _refuse('directory relocation would be required.');
      }
      if (member.posixMode != null &&
          member.posixMode != node.attributes['iso.mode']) {
        _refuse('POSIX metadata differs from the selected hierarchy.');
      }
    }
    await _pathTables(primary, main, false);
    if (joliet != null) await _pathTables(joliet, alternate!, true);
    regions.sort((a, b) => a.$1.compareTo(b.$1));
    var covered = 0;
    (int, int, String)? previous;
    for (final region in regions) {
      _check();
      if (region.$1 < covered) {
        if (previous != null &&
            region.$1 == previous.$1 &&
            region.$2 == previous.$2 &&
            region.$3 == previous.$3 &&
            region.$3 == 'payload') {
          continue;
        }
        _refuse('overlapping data or metadata cannot be safely rebuilt.');
      }
      await _zeroRange(covered, region.$1);
      covered = region.$2;
      previous = region;
    }
    await _zeroRange(covered, source.length);
    final inspection = ArchiveRewriteInspection(
      container: {
        'iso.profile': 1,
        'iso.volume': base64.encode(primary),
        if (joliet != null) 'iso.jolietVolume': base64.encode(joliet),
        'iso.root': selected.attributes,
      },
      attributes: attributes,
    );
    // Eligibility also includes the output profile's name, serial, hierarchy,
    // metadata and layout budgets. Planning never opens payload streams.
    final projected = [
      for (final member in archive.members)
        ArchiveWriteEntry(
          path: member.name,
          isDirectory: !member.isFile,
          size: member.size,
          modified: member.modified,
          mode: member.posixMode,
          attributes: attributes[member.name]!,
          readChunks: () => const Stream.empty(),
        ),
    ];
    _IsoImage(projected, inspection).plan(maxBytes);
    _check();
    return inspection;
  }

  void _range(int offset, int length, {bool insideVolume = true}) {
    final bound = insideVolume && volumeBytes != 0
        ? volumeBytes
        : source.length;
    if (offset < 0 || length < 0 || offset > bound || length > bound - offset) {
      _refuse('a metadata extent leaves the source image.');
    }
  }

  Future<Uint8List> _slice(int offset, int length) async {
    _range(offset, length);
    if (length > _metadataLimit) {
      _refuse('a metadata read exceeds the rewrite profile.');
    }
    _check();
    final bytes = await source.read(offset, length);
    _check();
    if (bytes.length != length) _refuse('the source image was truncated.');
    return bytes;
  }

  int _dual16(Uint8List data, int at) {
    final view = ByteData.sublistView(data);
    final value = view.getUint16(at, Endian.little);
    if (value != view.getUint16(at + 2, Endian.big)) {
      _refuse('both-endian metadata disagrees.');
    }
    return value;
  }

  int _dual32(Uint8List data, int at) {
    final view = ByteData.sublistView(data);
    final value = view.getUint32(at, Endian.little);
    if (value != view.getUint32(at + 4, Endian.big)) {
      _refuse('both-endian metadata disagrees.');
    }
    return value;
  }

  void _claim(int start, int count, String kind) {
    _range(start, count);
    if (count != 0) regions.add((start, start + count, kind));
  }

  Future<void> _zeroRange(int start, int end) async {
    _range(start, end - start, insideVolume: false);
    for (var at = start; at < end;) {
      _check();
      final remaining = end - at;
      final count = remaining < _chunkSize ? remaining : _chunkSize;
      final bytes = await source.read(at, count);
      _check();
      if (bytes.length != count) _refuse('the source image was truncated.');
      for (var index = 0; index < count; index++) {
        if (bytes[index] != 0) {
          _refuse(
            'unmodeled data, UDF, extra sessions or nonzero padding at byte '
            '0x${(at + index).toRadixString(16)} would be lost.',
          );
        }
      }
      at += count;
    }
  }

  void _volume(Uint8List descriptor, bool unicode) {
    if (_dual32(descriptor, 80) * _sector != volumeBytes ||
        _dual16(descriptor, 120) != 1 ||
        _dual16(descriptor, 124) != 1 ||
        _dual16(descriptor, 128) != _sector ||
        descriptor[881] != 1) {
      _refuse(
        'only single-volume ISO images with 2048-byte blocks are writable.',
      );
    }
    for (final range in [
      (72, 80),
      (882, 883),
      (1395, 2048),
      (unicode ? 91 : 88, 120),
    ]) {
      if (descriptor.sublist(range.$1, range.$2).any((value) => value != 0)) {
        _refuse('unknown application-use or reserved volume metadata.');
      }
    }
    final application = descriptor.sublist(883, 1395);
    if (!application.every((value) => value == 0) &&
        !application.every((value) => value == 32)) {
      _refuse('unknown application-use volume metadata.');
    }
    for (final start in [702, 739, 776]) {
      if (descriptor
          .sublist(start, start + 37)
          .any((value) => value != 0 && value != 32)) {
        _refuse(
          'volume metadata refers to a file that this profile cannot rename safely.',
        );
      }
    }
    if (descriptor[7] != 0) _refuse('unsupported volume flags.');
    for (final at in [813, 830, 847, 864]) {
      final date = descriptor.sublist(at, at + 17);
      if (date.every((v) => v == 0)) continue;
      if (!RegExp(r'^[0-9]{16}$').hasMatch(ascii.decode(date.sublist(0, 16)))) {
        _refuse('unsupported volume timestamp metadata.');
      }
    }
  }

  Future<_InspectedNode> _tree(Uint8List descriptor, bool unicode) async {
    final root = await _record(descriptor, 156, unicode, false);
    if (!root.directory ||
        root.identifier.length != 1 ||
        root.identifier[0] != 0) {
      _refuse('invalid root directory.');
    }
    final visited = <int>{};
    Future<void> read(_InspectedNode node, int depth, bool rock) async {
      _check();
      if (depth > 7 || !visited.add(node.offset)) {
        _refuse('cyclic, shared or deeply nested directories.');
      }
      metadataBytes += node.size;
      if (node.size > 8 * 1024 * 1024 ||
          metadataBytes > _metadataLimit ||
          node.size == 0 ||
          node.size % _sector != 0) {
        _refuse('directory metadata exceeds the rewrite profile.');
      }
      _claim(node.offset, node.size, 'directory');
      final data = await _slice(node.offset, node.size);
      var count = 0;
      final names = <String>{};
      for (var at = 0; at < data.length;) {
        if (data[at] == 0) {
          final end = _round(at + 1);
          if (data.sublist(at, end).any((v) => v != 0)) {
            _refuse('nonzero directory padding.');
          }
          at = end;
          continue;
        }
        final first = count == 0;
        if (first && depth == 0 && !unicode) {
          final length = data[at + 32];
          final useAt = at + _baseLength(length);
          rock =
              useAt + 7 <= at + data[at] &&
              _compare(data.sublist(useAt, useAt + 7), [
                    0x53,
                    0x50,
                    7,
                    1,
                    0xbe,
                    0xef,
                    0,
                  ]) ==
                  0;
          node.rock = rock;
        }
        final record = await _record(data, at, unicode, rock);
        at += data[at];
        count++;
        if (count <= 2) {
          if (record.identifier.length != 1 ||
              record.identifier[0] != count - 1 ||
              !record.directory) {
            _refuse('invalid self/parent directory records.');
          }
          if (count == 1) {
            if (record.offset != node.offset || record.size != node.size) {
              _refuse('inconsistent self directory extent.');
            }
            node.self = record;
            if (depth == 0) node.attributes.addAll(record.attributes);
          } else {
            node.parentRecord = record;
          }
          continue;
        }
        if (++entries > 200000) _refuse('too many stored directory records.');
        if (entries % 256 == 0) {
          await Future<void>.delayed(Duration.zero);
          _check();
        }
        if (record.identifier.length == 1 && record.identifier[0] < 2) {
          _refuse('repeated self/parent records.');
        }
        record.parent = node;
        if (!names.add(record.name)) {
          _refuse('duplicate directory names.');
        }
        node.children.add(record);
        if (!record.directory) _claim(record.offset, record.size, 'payload');
      }
      if (count < 2) _refuse('missing self/parent directory records.');
      for (final child in node.children.where((child) => child.directory)) {
        await read(child, depth + 1, rock);
      }
    }

    await read(root, 0, false);
    return root;
  }

  Future<_InspectedNode> _record(
    Uint8List data,
    int at,
    bool unicode,
    bool rock,
  ) async {
    _check();
    if (at + 34 > data.length) _refuse('truncated directory record.');
    final length = data[at];
    if (length < 34 ||
        length.isOdd ||
        at + length > data.length ||
        at % _sector + length > _sector) {
      _refuse('invalid directory record boundaries.');
    }
    final record = Uint8List.sublistView(data, at, at + length);
    final nameLength = record[32];
    final useAt = _baseLength(nameLength);
    if (nameLength == 0 ||
        useAt > record.length ||
        nameLength.isEven && record[33 + nameLength] != 0) {
      _refuse('invalid directory identifier.');
    }
    if (record[1] != 0 ||
        record[25] & ~3 != 0 ||
        record[26] != 0 ||
        record[27] != 0 ||
        _dual16(record, 28) != 1) {
      _refuse(
        'extended attributes, interleaving, multi-extents or unsupported file flags.',
      );
    }
    final nameBytes = Uint8List.sublistView(record, 33, 33 + nameLength);
    final special = nameLength == 1 && nameBytes[0] < 2;
    final directory = record[25] & 2 != 0;
    final offset = _dual32(record, 2) * _sector;
    final size = _dual32(record, 10);
    _range(offset, size);
    if (size != 0 && offset < descriptorEnd) {
      _refuse('a data extent overlaps volume descriptors.');
    }
    final date = Uint8List.sublistView(record, 18, 25);
    final modified = _decodeDate(date);
    final attributes = <String, Object?>{
      'iso.date': base64.encode(date),
      'iso.modified': modified?.millisecondsSinceEpoch,
      'iso.flags': record[25] & 1,
    };
    String? rrName;
    final use = Uint8List.sublistView(record, useAt);
    if (rock) {
      rrName = await _susp(use, attributes, special);
    } else if (use.any((value) => value != 0)) {
      _refuse('unknown directory system-use metadata.');
    }
    String identifier;
    if (special) {
      identifier = '';
    } else if (unicode) {
      if (nameLength.isOdd) _refuse('invalid Joliet identifier length.');
      final units = [
        for (var i = 0; i < nameBytes.length; i += 2)
          nameBytes[i] * 256 + nameBytes[i + 1],
      ];
      identifier = String.fromCharCodes(units);
    } else {
      identifier = ascii.decode(nameBytes);
    }
    if (!special) _validateIdentifier(identifier, directory, unicode);
    var name = identifier;
    if (!directory) {
      name = name.replaceFirst(RegExp(r';[0-9]+$'), '');
      if (name.endsWith('.')) name = name.substring(0, name.length - 1);
    }
    name = rrName ?? name;
    if (!special &&
        (name.isEmpty ||
            name == '.' ||
            name == '..' ||
            name.contains(RegExp(r'[/\\:\x00-\x1f\x7f]')) ||
            utf8.encode(name).length > _nameLimit)) {
      _refuse('unsafe or unsupported member names.');
    }
    if (!special) {
      attributes[unicode ? 'iso.jolietIdentifier' : 'iso.identifier'] =
          identifier;
      attributes['iso.name'] = name;
    }
    final mode = attributes['iso.mode'];
    if (mode is int && mode & 0xf000 != (directory ? 0x4000 : 0x8000)) {
      _refuse('links or special POSIX entries are present.');
    }
    if (!directory && (attributes['iso.links'] as int? ?? 1) > 1) {
      _refuse('hard-linked file metadata requires a different writer.');
    }
    return _InspectedNode(
      name,
      nameBytes,
      directory,
      offset,
      size,
      modified,
      attributes,
    )..rock = rock;
  }

  Future<String?> _susp(
    Uint8List initial,
    Map<String, Object?> attributes,
    bool special,
  ) async {
    final areas = <Uint8List>[initial];
    final seen = <String>{};
    final names = BytesBuilder(copy: false);
    var hasName = false;
    var continued = false;
    final tags = <String>{};
    for (var area = 0; area < areas.length; area++) {
      final data = areas[area];
      for (var at = 0; at < data.length;) {
        if (data[at] == 0) {
          if (data.sublist(at).any((value) => value != 0)) {
            _refuse('nonzero data follows SUSP padding.');
          }
          break;
        }
        if (at + 4 > data.length) _refuse('truncated SUSP metadata.');
        final length = data[at + 2];
        if (length < 4 || at + length > data.length || data[at + 3] != 1) {
          _refuse('invalid SUSP metadata.');
        }
        final field = Uint8List.sublistView(data, at, at + length);
        final tag = ascii.decode(field.sublist(0, 2));
        at += length;
        if (tag == 'ST') {
          if (length != 4 || data.sublist(at).any((v) => v != 0)) {
            _refuse('unmodeled data after SUSP terminator.');
          }
          break;
        }
        if (tag == 'CE') {
          if (length != 28 || seen.length >= 8) {
            _refuse('invalid continuation metadata.');
          }
          final block = _dual32(field, 4),
              start = _dual32(field, 12),
              size = _dual32(field, 20);
          if (start >= _sector ||
              size == 0 ||
              size > 65536 ||
              !seen.add('$block:$start:$size')) {
            _refuse('invalid continuation extent.');
          }
          continuationBytes += size;
          if (continuationBytes > _continuationLimit) {
            _refuse('too much continuation metadata.');
          }
          _claim(block * _sector + start, size, 'continuation');
          areas.add(await _slice(block * _sector + start, size));
        } else if (tag == 'NM') {
          if (length < 5 ||
              field[4] & ~1 != 0 ||
              special ||
              hasName && !continued) {
            _refuse('unsupported Rock Ridge name flags.');
          }
          names.add(field.sublist(5));
          hasName = true;
          continued = field[4] & 1 != 0;
          if (names.length > 4096) _refuse('a Rock Ridge name is too long.');
        } else if (tag == 'PX') {
          if (!tags.add(tag) || length != 36 && length != 44) {
            _refuse('invalid POSIX attributes.');
          }
          attributes['iso.mode'] = _dual32(field, 4);
          attributes['iso.links'] = _dual32(field, 12);
          attributes['iso.uid'] = _dual32(field, 20);
          attributes['iso.gid'] = _dual32(field, 28);
          if (length == 44) attributes['iso.serial'] = _dual32(field, 36);
        } else if (tag == 'TF') {
          if (!tags.add(tag)) _refuse('duplicate Rock Ridge timestamps.');
          _checkTf(field);
          attributes['iso.tf'] = base64.encode(field);
        } else if (tag == 'SP') {
          if (!special ||
              length != 7 ||
              _compare(field, [0x53, 0x50, 7, 1, 0xbe, 0xef, 0]) != 0 ||
              !tags.add(tag)) {
            _refuse('unsupported SUSP protocol.');
          }
        } else if (tag == 'ER') {
          if (!special ||
              !tags.add(tag) ||
              length < 8 ||
              8 + field[4] + field[5] + field[6] != length ||
              field[7] != 1 ||
              ascii.decode(field.sublist(8, 8 + field[4])) != 'RRIP_1991A') {
            _refuse('an unknown SUSP extension is declared.');
          }
          attributes['iso.er'] = base64.encode(field);
        } else if (tag == 'RR') {
          if (length != 5 || !tags.add(tag) || field[4] & 0x76 != 0) {
            _refuse('unsupported Rock Ridge record types.');
          }
        } else if (tag == 'PD') {
          if (field.sublist(4).any((v) => v != 0)) {
            _refuse('nonzero SUSP padding.');
          }
        } else {
          _refuse('unsupported $tag system-use metadata would be lost.');
        }
      }
    }
    if (continued) _refuse('unfinished Rock Ridge name continuation.');
    return hasName ? utf8.decode(names.takeBytes()) : null;
  }

  void _pair(_InspectedNode main, _InspectedNode alt) {
    if (main.children.length != alt.children.length) {
      _refuse('the ISO and Joliet trees contain different members.');
    }
    final buckets = <String, Set<_InspectedNode>>{};
    final byName = <String, _InspectedNode>{};
    final byIdentifier = <String, _InspectedNode>{};
    for (final child in alt.children) {
      (buckets[child.fingerprint] ??= <_InspectedNode>{}).add(child);
      byName[child.name] = child;
      byIdentifier[child.attributes['iso.jolietIdentifier'] as String] = child;
    }
    for (final child in main.children) {
      final signature = child.fingerprint;
      final candidates = buckets[signature] ?? <_InspectedNode>{};
      final expected = _jolietIdentifier(child.name, child.directory, 0);
      final named = <_InspectedNode>{
        if (byName[child.name] case final match?
            when candidates.contains(match))
          match,
        if (byIdentifier[expected] case final match?
            when candidates.contains(match))
          match,
      };
      final chosen = named.length == 1
          ? named.single
          : candidates.length == 1
          ? candidates.single
          : null;
      if (chosen == null) {
        _refuse(
          'the alternate Joliet hierarchy cannot be mapped unambiguously.',
        );
      }
      candidates.remove(chosen);
      final alternateMetadata = Map<String, Object?>.of(chosen.attributes);
      child.attributes['iso.jolietIdentifier'] =
          chosen.attributes['iso.jolietIdentifier'];
      child.attributes['iso.jolietMetadata'] = alternateMetadata;
      if (!main.rock) {
        // The public reader selects Joliet when the primary root has no SUSP.
        // Adding a Rock Ridge name must not select a different modification
        // time or lose the primary hierarchy's hidden flag/date representation.
        if (child.modified != chosen.modified) {
          _refuse(
            'the ISO and Joliet views have different modification times.',
          );
        }
        chosen.attributes.addAll(child.attributes);
        chosen.attributes['iso.name'] = chosen.name;
      }
      if (child.directory) _pair(child, chosen);
    }
    final alternateRoot = Map<String, Object?>.of(alt.attributes);
    main.attributes['iso.jolietMetadata'] = alternateRoot;
    if (!main.rock) {
      alt.attributes.addAll(main.attributes);
      alt.attributes['iso.name'] = alt.name;
    }
  }

  void _checkDuplicateRecords(_InspectedNode root) {
    void check(_InspectedNode node) {
      final self = node.self!;
      final parent = node.parent ?? node;
      final record = node.parentRecord!;
      if (record.offset != parent.offset || record.size != parent.size) {
        _refuse('a parent record points elsewhere.');
      }
      // A rewrite regenerates duplicate records from the target directory.
      // Refuse divergent dates/POSIX metadata rather than discard one version.
      for (final pair in [(self, node), (record, parent)]) {
        for (final key in [
          'iso.date',
          'iso.flags',
          'iso.mode',
          'iso.uid',
          'iso.gid',
          'iso.tf',
        ]) {
          if (pair.$1.attributes[key] != pair.$2.attributes[key]) {
            _refuse('directory metadata differs between duplicate records.');
          }
        }
      }
      for (final child in node.children.where((child) => child.directory)) {
        check(child);
      }
    }

    check(root);
  }

  Future<void> _pathTables(
    Uint8List descriptor,
    _InspectedNode root,
    bool unicode,
  ) async {
    final size = _dual32(descriptor, 132);
    if (size == 0 || size > _metadataLimit) _refuse('invalid path table size.');
    final view = ByteData.sublistView(descriptor);
    final expected = <int, _InspectedNode>{};
    void collect(_InspectedNode node) {
      expected[node.offset] = node;
      for (final child in node.children.where((n) => n.directory)) {
        collect(child);
      }
    }

    collect(root);
    for (final location in [
      (140, Endian.little, false),
      (144, Endian.little, true),
      (148, Endian.big, false),
      (152, Endian.big, true),
    ]) {
      final block = view.getUint32(location.$1, location.$2);
      if (block == 0 && location.$3) continue;
      if (block == 0) _refuse('a required path table is missing.');
      _claim(block * _sector, size, 'path');
      final table = await _slice(block * _sector, size);
      final data = ByteData.sublistView(table);
      final seen = <int>{};
      final ordered = <_InspectedNode>[];
      for (var at = 0; at < size;) {
        if (at + 8 > size) _refuse('truncated path table.');
        final length = table[at];
        final count = 8 + length + length % 2;
        if (length == 0 || at + count > size || table[at + 1] != 0) {
          _refuse('invalid path table record.');
        }
        final offset = data.getUint32(at + 2, location.$2) * _sector;
        final parent = data.getUint16(at + 6, location.$2);
        final node = expected[offset];
        if (node == null ||
            !seen.add(offset) ||
            parent == 0 ||
            parent > ordered.length + (ordered.isEmpty ? 1 : 0)) {
          _refuse('path table hierarchy mismatch.');
        }
        if (ordered.isEmpty) {
          if (node != root ||
              parent != 1 ||
              length != 1 ||
              table[at + 8] != 0) {
            _refuse('invalid root path table record.');
          }
        } else if (node.parent != ordered[parent - 1] ||
            _compare(table.sublist(at + 8, at + 8 + length), node.identifier) !=
                0) {
          _refuse('path table does not describe its directory tree.');
        }
        if (length.isOdd && table[at + count - 1] != 0) {
          _refuse('invalid path table padding.');
        }
        ordered.add(node);
        at += count;
      }
      if (seen.length != expected.length) {
        _refuse('the path table omits directories.');
      }
    }
  }
}

class _InspectedNode {
  _InspectedNode(
    this.name,
    this.identifier,
    this.directory,
    this.offset,
    this.size,
    this.modified,
    this.attributes,
  );
  final String name;
  final Uint8List identifier;
  final bool directory;
  final int offset;
  final int size;
  final DateTime? modified;
  final Map<String, Object?> attributes;
  final List<_InspectedNode> children = [];
  _InspectedNode? parent;
  _InspectedNode? self;
  _InspectedNode? parentRecord;
  bool rock = false;
  String? _fingerprint;
  String get fingerprint => _fingerprint ??= directory
      ? 'D(${(children.map((child) => child.fingerprint).toList()..sort()).join(',')})'
      : 'F$offset:$size';
}
