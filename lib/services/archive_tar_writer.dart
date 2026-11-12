import 'dart:convert';
import 'dart:typed_data';

import 'archive_compression_writer.dart';
import 'archive_types.dart';
import 'archive_viewer_service.dart' show decompressSingleFile;
import 'archive_write_model.dart';

const _block = 512;
const _maxOutput = 256 * 1024 * 1024;
const _maxMetadata = 1024 * 1024;
const _maxAllMetadata = 16 * 1024 * 1024;
const _maxExact = 0x1fffffffffffff;
const _octalOwnerMax = 0x1fffff;
const _octalTimeMax = 0x1ffffffff;
const _paxKeys = {
  'path',
  'size',
  'uid',
  'gid',
  'uname',
  'gname',
  'mtime',
  'atime',
  'ctime',
};
const _attributeKeys = {
  'package.sourcePath',
  'package.order',
  'tar.variant',
  'tar.storedPath',
  'tar.type',
  'tar.uid',
  'tar.gid',
  'tar.uname',
  'tar.gname',
  'tar.devmajor',
  'tar.devminor',
  'tar.gnuAtime',
  'tar.gnuCtime',
  'tar.hasMode',
  'tar.hasMtime',
  'tar.pax',
  'tar.extension',
};

/// A preservation inspection for raw TAR or one supported compression wrapper.
/// The member model alone omits ownership and extended metadata. Global PAX,
/// sparse files, links, opaque extensions and non-UTF-8 headers stay read-only.
Future<ArchiveRewriteInspection> inspectTarRewrite(
  Uint8List bytes,
  ViewerArchive archive,
) async {
  try {
    if (archive.isClosed || archive.formatName != 'tar') {
      _refuse('The TAR reader is unavailable or belongs to another format.');
    }
    if (bytes.length > _maxOutput) _refuse('TAR input exceeds 256 MiB.');
    final compression = archiveCompressionForBytes(bytes);
    if (compression != null) {
      validateArchiveCompressionRewrite(bytes, compression);
      final suffix = switch (compression) {
        ArchiveCompressionKind.gzip => 'gz',
        ArchiveCompressionKind.bzip2 => 'bz2',
        ArchiveCompressionKind.xz => 'xz',
        ArchiveCompressionKind.zstd => 'zst',
      };
      bytes = decompressSingleFile(bytes, 'payload.$suffix').data;
    }
    return _inspectTar(bytes, archive);
  } catch (error) {
    return ArchiveRewriteInspection(
      reason: error is _TarRefusal
          ? error.message
          : 'The TAR metadata cannot be preserved safely: $error',
      container: const {'package.kind': 'tar'},
    );
  }
}

/// Streams a regular-file TAR to an unpublished sink. Wrapping compression and
/// publication remain the caller's responsibility. Metadata unknown to this
/// profile is refused rather than discarded; failure can leave partial output.
Future<void> writeTarArchive(
  List<ArchiveWriteEntry> entries, {
  required Future<void> Function(List<int>) sink,
  ArchiveRewriteInspection? source,
  int maxOutputBytes = _maxOutput,
  bool Function()? isCancelled,
}) async {
  if (maxOutputBytes <= 0 || maxOutputBytes > _maxOutput) {
    throw ArgumentError.value(maxOutputBytes, 'maxOutputBytes');
  }
  void check() {
    if (isCancelled?.call() ?? false) {
      throw const ArchiveViewException('TAR writing was cancelled.');
    }
  }

  check();
  if (source != null &&
      (!source.supported || source.container['package.kind'] != 'tar')) {
    throw ArchiveViewException(
      source.reason ?? 'The TAR inspection is incompatible.',
    );
  }
  validateArchiveWriteEntries(entries);
  try {
    final all = List<ArchiveWriteEntry>.of(entries);
    final root = source?.container['tar.root'];
    if (root != null) {
      if (root is! Map<String, Object?> ||
          root['attributes'] is! Map<String, Object?>) {
        _refuse('Invalid preserved TAR root metadata.');
      }
      final attrs = root['attributes']! as Map<String, Object?>;
      final order = attrs['package.order'];
      final micros = root['modified'];
      if (order is! int || micros != null && micros is! int) {
        _refuse('Invalid preserved TAR root metadata.');
      }
      all.insert(
        order.clamp(0, all.length),
        ArchiveWriteEntry(
          path: '.',
          isDirectory: true,
          size: 0,
          mode: root['mode'] as int?,
          modified: micros == null
              ? null
              : DateTime.fromMicrosecondsSinceEpoch(micros as int, isUtc: true),
          attributes: attrs,
        ),
      );
    }
    final preferred = source?.container['tar.variant'] ?? 'ustar';
    if (preferred is! String ||
        !const {'ustar', 'gnu', 'v7'}.contains(preferred)) {
      _refuse('Unsupported TAR header profile.');
    }
    final padding = source?.container['tar.trailingBytes'] ?? 1024;
    if (padding is! int ||
        padding < 1024 ||
        padding > _maxOutput ||
        padding % _block != 0) {
      _refuse('Invalid TAR end padding.');
    }
    var trailing = padding;
    final plans = <_TarPlan>[];
    var total = trailing, metadata = 0;
    for (final entry in all) {
      check();
      final plan = _plan(entry, preferred, plans.length);
      metadata += plan.extension.length;
      if (metadata > _maxAllMetadata) {
        _refuse('TAR extension metadata exceeds its limit.');
      }
      total += plan.extension.length + _block + _aligned(entry.size);
      if (total > maxOutputBytes) _refuse('TAR output exceeds its size limit.');
      plans.add(plan);
    }
    if (total > maxOutputBytes) _refuse('TAR output exceeds its size limit.');
    var written = 0;
    Future<void> emit(List<int> chunk) async {
      check();
      if (chunk.length > maxOutputBytes - written) {
        _refuse('TAR output exceeds its size limit.');
      }
      if (chunk.isEmpty) return;
      await sink(chunk);
      written += chunk.length;
      check();
    }

    for (final plan in plans) {
      await emit(plan.extension);
      await emit(plan.header);
      await for (final chunk in plan.entry.openRead()) {
        await emit(chunk);
      }
      final padding = _aligned(plan.entry.size) - plan.entry.size;
      if (padding != 0) await emit(Uint8List(padding));
    }
    while (trailing > 0) {
      final amount = trailing > 65536 ? 65536 : trailing;
      await emit(Uint8List(amount));
      trailing -= amount;
    }
    check();
  } on _TarRefusal catch (error) {
    throw ArchiveViewException(error.message);
  }
}

ArchiveRewriteInspection _inspectTar(Uint8List bytes, ViewerArchive archive) {
  var offset = 0, index = 0, metadata = 0, records = 0;
  var trailing = 0;
  String? preferred, longName;
  Map<String, String>? pax;
  _TarHeader? extension;
  Map<String, Object?>? root;
  final attributes = <String, Map<String, Object?>>{};
  while (offset < bytes.length) {
    _range(bytes, offset, _block);
    final block = Uint8List.sublistView(bytes, offset, offset + _block);
    if (block.every((byte) => byte == 0)) {
      trailing = bytes.length - offset;
      if (trailing < 1024 ||
          trailing % _block != 0 ||
          bytes.sublist(offset).any((byte) => byte != 0)) {
        _refuse('TAR has incomplete, concatenated or opaque trailing records.');
      }
      break;
    }
    if (++records > 400000) _refuse('TAR has too many header records.');
    final header = _TarHeader.read(block);
    offset += _block;
    final type = header.type;
    if (type == 103) {
      _refuse('Global PAX metadata requires a scope-aware rewrite.');
    }
    if (type == 120 || type == 76) {
      if (extension != null || header.size > _maxMetadata) {
        _refuse(
          'Repeated or oversized TAR extension headers cannot be preserved.',
        );
      }
      metadata += header.size;
      if (metadata > _maxAllMetadata) {
        _refuse('TAR extension metadata exceeds its limit.');
      }
      _range(bytes, offset, _aligned(header.size));
      final data = Uint8List.sublistView(bytes, offset, offset + header.size);
      _zeroPadding(
        bytes,
        offset + header.size,
        _aligned(header.size) - header.size,
      );
      if (type == 120) {
        if (header.variant != 'ustar') {
          _refuse('PAX requires a POSIX extension header.');
        }
        pax = _parsePax(data);
      } else {
        if (header.variant != 'gnu' || data.isEmpty || data.last != 0) {
          _refuse('Unsupported GNU long-name metadata.');
        }
        var end = data.length;
        while (end > 0 && data[end - 1] == 0) {
          end--;
        }
        longName = utf8.decode(data.sublist(0, end));
      }
      extension = header;
      offset += _aligned(header.size);
      continue;
    }
    if (!const {0, 48, 53}.contains(type)) {
      _refuse(
        'TAR links, sparse files and special record types require a filesystem-aware writer.',
      );
    }
    if (pax != null && header.variant != 'ustar' ||
        longName != null && header.variant != 'gnu') {
      _refuse('Mixed TAR extension/header profiles cannot be preserved.');
    }
    preferred ??= header.variant;
    final storedPath = pax?['path'] ?? longName ?? header.path;
    final directory = type == 53 || storedPath.endsWith('/');
    final modeType = (header.mode ?? 0) & 0xf000;
    if (modeType != 0 && modeType != (directory ? 0x4000 : 0x8000)) {
      _refuse('TAR mode/type metadata is inconsistent.');
    }
    final path = _canonicalPath(storedPath, directory);
    final size = pax?['size'] == null ? header.size : _decimal(pax!['size']!);
    if (directory && (size != 0 || header.size != 0)) {
      _refuse('TAR directories carrying file data cannot be preserved.');
    }
    _range(bytes, offset, _aligned(size));
    _zeroPadding(bytes, offset + size, _aligned(size) - size);
    final modified = pax?['mtime'] == null
        ? _headerTime(header.mtime)
        : _paxTime(pax!['mtime']!);
    final uid = pax?['uid'] == null ? header.uid : _decimal(pax!['uid']!);
    final gid = pax?['gid'] == null ? header.gid : _decimal(pax!['gid']!);
    if (index >= archive.members.length) _refuse('TAR member list changed.');
    final member = archive.members[index];
    if (member.name != (path.isEmpty ? '/' : path) ||
        member.size != size ||
        member.isFile == directory ||
        member.isSpecial ||
        member.isEncrypted ||
        member.pathEscapedRoot ||
        member.modified != modified ||
        member.posixMode != header.mode) {
      _refuse(
        'The TAR metadata disagrees with its displayed member: $storedPath',
      );
    }
    final attrs = <String, Object?>{
      'package.sourcePath': path,
      'package.order': index++,
      'tar.variant': header.variant,
      'tar.storedPath': storedPath,
      'tar.type': type,
      'tar.uid': uid,
      'tar.gid': gid,
      'tar.uname': pax?['uname'] ?? header.uname,
      'tar.gname': pax?['gname'] ?? header.gname,
      'tar.devmajor': header.devmajor,
      'tar.devminor': header.devminor,
      'tar.gnuAtime': header.atime,
      'tar.gnuCtime': header.ctime,
      'tar.hasMode': header.mode != null,
      'tar.hasMtime': header.mtime != null,
      if (pax != null) 'tar.pax': Map<String, String>.unmodifiable(pax),
      if (extension != null) 'tar.extension': extension.toMap(),
    };
    if (path.isEmpty) {
      if (!directory || root != null) _refuse('Unsupported TAR root records.');
      root = Map<String, Object?>.unmodifiable({
        'attributes': Map<String, Object?>.unmodifiable(attrs),
        'mode': header.mode,
        'modified': modified?.microsecondsSinceEpoch,
      });
    } else {
      if (attributes.containsKey(path)) _refuse('Duplicate TAR member paths.');
      attributes[path] = attrs;
    }
    offset += _aligned(size);
    pax = null;
    longName = null;
    extension = null;
  }
  if (trailing == 0 || extension != null || index != archive.members.length) {
    _refuse('TAR has a missing end marker or unconsumed metadata.');
  }
  validateArchiveWriteEntries([
    for (final member in archive.members)
      if (member.name != '/')
        ArchiveWriteEntry(
          path: member.name,
          isDirectory: !member.isFile,
          size: member.size,
          readChunks: member.isFile
              ? () => const Stream<List<int>>.empty()
              : null,
        ),
  ]);
  return ArchiveRewriteInspection(
    container: {
      'package.kind': 'tar',
      'tar.variant': preferred ?? 'ustar',
      'tar.trailingBytes': trailing,
      if (root != null) 'tar.root': root,
    },
    attributes: attributes,
  );
}

class _TarPlan {
  _TarPlan(this.entry, this.header, this.extension);
  final ArchiveWriteEntry entry;
  final Uint8List header, extension;
}

_TarPlan _plan(ArchiveWriteEntry entry, String preferred, int index) {
  final attrs = entry.attributes;
  if (attrs.keys.any((key) => !_attributeKeys.contains(key))) {
    _refuse('Unknown TAR member metadata cannot be discarded.');
  }
  final variant = attrs['tar.variant'] ?? preferred;
  if (variant is! String || !const {'ustar', 'gnu', 'v7'}.contains(variant)) {
    _refuse('Unsupported TAR header profile.');
  }
  final originalPath = attrs['tar.storedPath'];
  var path = attrs['package.sourcePath'] == entry.path || entry.path == '.'
      ? originalPath is String
            ? originalPath
            : entry.path
      : entry.path;
  if (entry.isDirectory && originalPath is! String) path = '$path/';
  if (entry.isDirectory &&
      originalPath is String &&
      originalPath.endsWith('/') &&
      !path.endsWith('/')) {
    path = '$path/';
  }
  final canonical = _canonicalPath(path, entry.isDirectory);
  if (canonical != (entry.path == '.' ? '' : entry.path)) {
    _refuse('Inconsistent TAR stored path.');
  }
  final type = attrs['tar.type'] ?? (entry.isDirectory ? 53 : 48);
  if (type is! int ||
      !const {0, 48, 53}.contains(type) ||
      (type == 53 || path.endsWith('/')) != entry.isDirectory) {
    _refuse('TAR type metadata does not match the member.');
  }
  final mode =
      entry.mode ??
      (attrs['tar.hasMode'] == false
          ? null
          : entry.isDirectory
          ? 0x1ed
          : 0x1a4);
  if (mode != null &&
      (mode < 0 ||
          mode > 0xffff ||
          mode & 0xf000 != 0 &&
              mode & 0xf000 != (entry.isDirectory ? 0x4000 : 0x8000))) {
    _refuse('Unsupported TAR permission/type bits.');
  }
  int? number(String key, {int? fallback}) {
    final value = attrs.containsKey(key) ? attrs[key] : fallback;
    if (value != null && (value is! int || value < 0 || value > _maxExact)) {
      _refuse('Invalid $key metadata.');
    }
    return value as int?;
  }

  String text(String key) {
    final value = attrs[key] ?? '';
    if (value is! String) _refuse('Invalid $key metadata.');
    _nameText(value);
    return value;
  }

  final uid = number('tar.uid', fallback: 0),
      gid = number('tar.gid', fallback: 0);
  final uname = text('tar.uname'), gname = text('tar.gname');
  final pax = <String, String>{};
  final originalPax = attrs['tar.pax'];
  if (originalPax != null) {
    if (originalPax is! Map<String, String>) {
      _refuse('Invalid preserved PAX metadata.');
    }
    _validatePax(originalPax);
    pax.addAll(originalPax);
  }
  final modified = entry.modified;
  var seconds = modified == null
      ? (attrs['tar.hasMtime'] == false ? null : 0)
      : modified.microsecondsSinceEpoch ~/ Duration.microsecondsPerSecond;
  if (modified != null) _dateRange(seconds!);
  final originalTime = pax['mtime'];
  if (originalTime != null && _paxTime(originalTime) == modified) {
    // Retain all original decimal digits, including nanoseconds the member
    // model cannot represent. Changing content alone does not erase them.
  } else if (modified != null &&
      (originalTime != null ||
          modified.microsecondsSinceEpoch % 1000000 != 0)) {
    pax['mtime'] = _formatTime(modified);
  } else if (originalTime != null) {
    _refuse('Removing a PAX timestamp requires an explicit metadata edit.');
  }
  if (pax.containsKey('path')) pax['path'] = path;
  if (pax.containsKey('size')) pax['size'] = '${entry.size}';
  void paxNumber(String key, int? value) {
    if (pax.containsKey(key) ||
        variant == 'ustar' && value != null && value > _octalOwnerMax) {
      if (value == null) _refuse('Missing preserved PAX $key.');
      if (pax[key] == null || _decimal(pax[key]!) != value) pax[key] = '$value';
    }
  }

  paxNumber('uid', uid);
  paxNumber('gid', gid);
  for (final item in {'uname': uname, 'gname': gname}.entries) {
    if (pax.containsKey(item.key) || utf8.encode(item.value).length > 32) {
      pax[item.key] = item.value;
    }
  }
  if (variant == 'ustar' &&
      seconds != null &&
      (seconds < 0 || seconds > _octalTimeMax)) {
    pax['mtime'] ??= _formatTime(modified!);
  }
  if (pax.containsKey('mtime')) {
    _paxTime(pax['mtime']!);
    if (seconds != null && (seconds < 0 || seconds > _octalTimeMax)) {
      seconds = 0;
    }
  }
  final split = variant == 'ustar' ? _split(path) : ('', path);
  final long = utf8.encode(split.$2).length > 100;
  _TarHeader? originalExtension;
  final ext = attrs['tar.extension'];
  if (ext != null) {
    if (ext is! Map<String, Object?>) {
      _refuse('Invalid preserved TAR extension.');
    }
    originalExtension = _TarHeader.fromMap(ext);
    if (!const {76, 120}.contains(originalExtension.type)) {
      _refuse('Invalid TAR extension type.');
    }
  }
  if (variant == 'ustar' && long) pax['path'] = path;
  if (variant != 'ustar' && pax.isNotEmpty) {
    _refuse('This TAR header variant cannot preserve PAX metadata.');
  }
  if (variant == 'v7' &&
      (long ||
          uid != null && uid > _octalOwnerMax ||
          gid != null && gid > _octalOwnerMax ||
          seconds != null && (seconds < 0 || seconds > _octalTimeMax) ||
          uname.isNotEmpty ||
          gname.isNotEmpty)) {
    _refuse('The edited metadata no longer fits the V7 TAR profile.');
  }
  var extension = Uint8List(0);
  var headerPath = path;
  if (pax.isNotEmpty || originalExtension?.type == 120) {
    if (variant != 'ustar' ||
        originalExtension != null && originalExtension.type != 120) {
      _refuse('Incompatible PAX extension profile.');
    }
    _validatePax(pax);
    final data = _encodePax(pax);
    extension = _extensionBytes(
      originalExtension ?? _TarHeader.empty('ustar', 'PaxHeaders/$index', 120),
      data,
    );
    if (long) headerPath = 'PaxFile/$index';
  } else if (variant == 'gnu' && (long || originalExtension?.type == 76)) {
    final data = Uint8List.fromList([...utf8.encode(path), 0]);
    extension = _extensionBytes(
      originalExtension ?? _TarHeader.empty('gnu', '././@LongLink', 76),
      data,
    );
    if (long) headerPath = 'GnuFile/$index';
  }
  if (variant != 'gnu' &&
      (attrs['tar.gnuAtime'] != null || attrs['tar.gnuCtime'] != null)) {
    _refuse('GNU timestamp fields cannot be discarded from this TAR profile.');
  }
  final header = _TarHeader(
    variant: variant,
    path: headerPath,
    type: type,
    size: entry.size,
    mode: mode,
    uid: pax.containsKey('uid')
        ? (uid != null && uid <= _octalOwnerMax ? uid : 0)
        : uid,
    gid: pax.containsKey('gid')
        ? (gid != null && gid <= _octalOwnerMax ? gid : 0)
        : gid,
    mtime: seconds,
    uname: utf8.encode(uname).length <= 32 ? uname : '',
    gname: utf8.encode(gname).length <= 32 ? gname : '',
    devmajor: number('tar.devmajor'),
    devminor: number('tar.devminor'),
    atime: _signedAttribute(attrs, 'tar.gnuAtime'),
    ctime: _signedAttribute(attrs, 'tar.gnuCtime'),
  );
  return _TarPlan(entry, header.encode(), extension);
}

Uint8List _extensionBytes(_TarHeader header, Uint8List data) {
  if (data.length > _maxMetadata) {
    _refuse('TAR extension exceeds its metadata limit.');
  }
  return Uint8List.fromList([
    ...header.encode(sizeOverride: data.length),
    ...data,
    ...Uint8List(_aligned(data.length) - data.length),
  ]);
}

class _TarHeader {
  _TarHeader({
    required this.variant,
    required this.path,
    required this.type,
    required this.size,
    this.mode,
    this.uid,
    this.gid,
    this.mtime,
    this.uname = '',
    this.gname = '',
    this.devmajor,
    this.devminor,
    this.atime,
    this.ctime,
  });
  factory _TarHeader.empty(String variant, String path, int type) => _TarHeader(
    variant: variant,
    path: path,
    type: type,
    size: 0,
    mode: 0x1a4,
    uid: 0,
    gid: 0,
    mtime: 0,
  );
  final String variant, path, uname, gname;
  final int type, size;
  final int? mode, uid, gid, mtime, devmajor, devminor, atime, ctime;

  factory _TarHeader.read(Uint8List bytes) {
    final stored = _numeric(bytes, 148, 8);
    var unsigned = 0, signed = 0;
    for (var i = 0; i < _block; i++) {
      final byte = i >= 148 && i < 156 ? 32 : bytes[i];
      unsigned += byte;
      signed += byte < 128 ? byte : byte - 256;
    }
    if (stored != unsigned && stored != signed) {
      _refuse('TAR header checksum mismatch.');
    }
    final magic = ascii.decode(bytes.sublist(257, 265), allowInvalid: true);
    final String variant;
    if (magic == 'ustar\x0000') {
      variant = 'ustar';
    } else if (magic == 'ustar  \x00') {
      variant = 'gnu';
    } else if (bytes.sublist(257).every((byte) => byte == 0)) {
      variant = 'v7';
    } else {
      _refuse('Unknown TAR header extensions cannot be preserved.');
    }
    if (_string(bytes, 157, 100).isNotEmpty) {
      _refuse('TAR link metadata is unsupported.');
    }
    var path = _string(bytes, 0, 100);
    if (variant == 'ustar') {
      final prefix = _string(bytes, 345, 155);
      if (prefix.isNotEmpty) path = '$prefix/$path';
      _zeroPadding(bytes, 500, 12);
    } else if (variant == 'gnu') {
      // Old GNU reserves the rest for incremental/multivolume/sparse data.
      // Zero-valued numeric offset fields are tolerated, but no data is lost.
      final offset = _numeric(bytes, 369, 12);
      if (offset != null && offset != 0) {
        _refuse('GNU multivolume TAR requires a dedicated writer.');
      }
      _zeroPadding(bytes, 381, 131);
    }
    final size = _numeric(bytes, 124, 12) ?? 0;
    if (size < 0) _refuse('Negative TAR member size.');
    final mode = _numeric(bytes, 100, 8);
    if (mode != null && (mode < 0 || mode > 0xffff)) {
      _refuse('Unsupported TAR mode bits.');
    }
    final uid = _numeric(bytes, 108, 8), gid = _numeric(bytes, 116, 8);
    if (uid != null && uid < 0 || gid != null && gid < 0) {
      _refuse('Negative TAR ownership.');
    }
    final mtime = _numeric(bytes, 136, 12);
    if (mtime != null) _dateRange(mtime);
    final uname = variant == 'v7' ? '' : _string(bytes, 265, 32);
    final gname = variant == 'v7' ? '' : _string(bytes, 297, 32);
    _nameText(uname);
    _nameText(gname);
    final devmajor = variant == 'v7' ? null : _numeric(bytes, 329, 8);
    final devminor = variant == 'v7' ? null : _numeric(bytes, 337, 8);
    if (devmajor != null && devmajor < 0 || devminor != null && devminor < 0) {
      _refuse('Invalid TAR device metadata.');
    }
    final atime = variant == 'gnu' ? _numeric(bytes, 345, 12) : null;
    final ctime = variant == 'gnu' ? _numeric(bytes, 357, 12) : null;
    if (atime != null) _dateRange(atime);
    if (ctime != null) _dateRange(ctime);
    return _TarHeader(
      variant: variant,
      path: path,
      type: bytes[156],
      size: size,
      mode: mode,
      uid: uid,
      gid: gid,
      mtime: mtime,
      uname: uname,
      gname: gname,
      devmajor: devmajor,
      devminor: devminor,
      atime: atime,
      ctime: ctime,
    );
  }

  Map<String, Object?> toMap() => Map<String, Object?>.unmodifiable({
    'variant': variant,
    'path': path,
    'type': type,
    'mode': mode,
    'uid': uid,
    'gid': gid,
    'mtime': mtime,
    'uname': uname,
    'gname': gname,
    'devmajor': devmajor,
    'devminor': devminor,
    'atime': atime,
    'ctime': ctime,
  });

  factory _TarHeader.fromMap(Map<String, Object?> map) {
    const fields = {
      'variant',
      'path',
      'type',
      'mode',
      'uid',
      'gid',
      'mtime',
      'uname',
      'gname',
      'devmajor',
      'devminor',
      'atime',
      'ctime',
    };
    if (map.keys.any((key) => !fields.contains(key))) {
      _refuse('Unknown TAR extension metadata.');
    }
    return _TarHeader(
      variant: map['variant'] as String,
      path: map['path'] as String,
      type: map['type'] as int,
      size: 0,
      mode: map['mode'] as int?,
      uid: map['uid'] as int?,
      gid: map['gid'] as int?,
      mtime: map['mtime'] as int?,
      uname: map['uname'] as String,
      gname: map['gname'] as String,
      devmajor: map['devmajor'] as int?,
      devminor: map['devminor'] as int?,
      atime: map['atime'] as int?,
      ctime: map['ctime'] as int?,
    );
  }

  Uint8List encode({int? sizeOverride}) {
    if (!const {'ustar', 'gnu', 'v7'}.contains(variant)) {
      _refuse('Invalid TAR header variant.');
    }
    _canonicalPath(path, type == 53 || path.endsWith('/'));
    final bytes = Uint8List(_block);
    final split = variant == 'ustar' ? _split(path) : ('', path);
    _putString(bytes, 0, 100, split.$2);
    void number(int at, int width, int? value) =>
        _putNumeric(bytes, at, width, value, binary: variant == 'gnu');
    number(100, 8, mode);
    number(108, 8, uid);
    number(116, 8, gid);
    number(124, 12, sizeOverride ?? size);
    number(136, 12, mtime);
    bytes[156] = type;
    if (variant != 'v7') {
      _putString(
        bytes,
        257,
        8,
        variant == 'gnu' ? 'ustar  \x00' : 'ustar\x0000',
      );
      _putString(bytes, 265, 32, uname);
      _putString(bytes, 297, 32, gname);
      number(329, 8, devmajor);
      number(337, 8, devminor);
      if (variant == 'gnu') {
        number(345, 12, atime);
        number(357, 12, ctime);
      } else {
        _putString(bytes, 345, 155, split.$1);
      }
    } else if (uname.isNotEmpty ||
        gname.isNotEmpty ||
        devmajor != null ||
        devminor != null ||
        atime != null ||
        ctime != null) {
      _refuse('V7 TAR cannot store extended fields.');
    }
    for (var i = 148; i < 156; i++) {
      bytes[i] = 32;
    }
    final checksum = bytes.fold(0, (sum, byte) => sum + byte);
    bytes.setRange(
      148,
      154,
      ascii.encode(checksum.toRadixString(8).padLeft(6, '0')),
    );
    bytes[154] = 0;
    bytes[155] = 32;
    return bytes;
  }
}

Map<String, String> _parsePax(Uint8List bytes) {
  final result = <String, String>{};
  var at = 0;
  while (at < bytes.length) {
    var space = at;
    while (space < bytes.length && bytes[space] != 32) {
      space++;
    }
    if (space == at || space - at > 10 || space >= bytes.length) {
      _refuse('Invalid PAX record length.');
    }
    final length = _decimal(ascii.decode(bytes.sublist(at, space)));
    if (length <= space - at + 2 ||
        length > bytes.length - at ||
        bytes[at + length - 1] != 10) {
      _refuse('Truncated PAX record.');
    }
    final record = utf8.decode(bytes.sublist(space + 1, at + length - 1));
    final equals = record.indexOf('=');
    if (equals <= 0) _refuse('Invalid PAX key/value record.');
    final key = record.substring(0, equals),
        value = record.substring(equals + 1);
    if (result.containsKey(key)) {
      _refuse('Repeated PAX keys require an explicit precedence policy.');
    }
    result[key] = value;
    if (result.length > 32) _refuse('Too many PAX keys.');
    at += length;
  }
  _validatePax(result);
  return result;
}

void _validatePax(Map<String, String> values) {
  for (final item in values.entries) {
    if (!_paxKeys.contains(item.key)) {
      _refuse('Unsupported PAX metadata: ${item.key}.');
    }
    if (item.value.isEmpty ||
        item.value.contains('\x00') ||
        utf8.encode(item.value).length > 4096) {
      _refuse('Unsupported PAX value.');
    }
    if (const {'size', 'uid', 'gid'}.contains(item.key)) _decimal(item.value);
    if (const {'mtime', 'atime', 'ctime'}.contains(item.key)) {
      _paxTime(item.value);
    }
    if (item.key == 'uname' || item.key == 'gname') _nameText(item.value);
  }
}

Uint8List _encodePax(Map<String, String> values) {
  final result = BytesBuilder(copy: false);
  for (final item in values.entries) {
    final value = utf8.encode(' ${item.key}=${item.value}\n');
    var length = value.length + 1;
    while (length != value.length + '$length'.length) {
      length = value.length + '$length'.length;
    }
    result.add(ascii.encode('$length'));
    result.add(value);
  }
  return result.takeBytes();
}

(String, String) _split(String path) {
  if (utf8.encode(path).length <= 100) return ('', path);
  for (var at = path.length - 1; at > 0; at--) {
    if (path[at] != '/') continue;
    final prefix = path.substring(0, at), name = path.substring(at + 1);
    if (name.isNotEmpty &&
        utf8.encode(prefix).length <= 155 &&
        utf8.encode(name).length <= 100) {
      return (prefix, name);
    }
  }
  return ('', path);
}

String _canonicalPath(String raw, bool directory) {
  if (raw.startsWith('/') ||
      raw.contains('\\') ||
      RegExp(r'[\x00-\x1f\x7f:]').hasMatch(raw) ||
      utf8.encode(raw).length > 4096) {
    _refuse('Unsafe TAR member path.');
  }
  var path = raw;
  while (path.startsWith('./')) {
    path = path.substring(2);
  }
  if (directory && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  if (directory && (path.isEmpty || path == '.')) return '';
  final parts = path.split('/');
  if (path.isEmpty ||
      parts.length > 200 ||
      parts.any((part) => part.isEmpty || part == '.' || part == '..')) {
    _refuse('Unsafe TAR member path.');
  }
  return path;
}

void _nameText(String value) {
  if (utf8.encode(value).length > 4096 ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
    _refuse('Unsupported TAR owner/group text.');
  }
}

String _string(Uint8List bytes, int at, int length) {
  var end = at;
  while (end < at + length && bytes[end] != 0) {
    end++;
  }
  if (end < at + length) _zeroPadding(bytes, end, at + length - end);
  return utf8.decode(bytes.sublist(at, end));
}

void _putString(Uint8List bytes, int at, int length, String value) {
  final encoded = utf8.encode(value);
  if (encoded.length > length) {
    _refuse('TAR text no longer fits its header field.');
  }
  bytes.setAll(at, encoded);
}

int? _numeric(Uint8List bytes, int at, int length) {
  if (bytes[at] & 128 != 0) {
    var value = BigInt.from(bytes[at] & 127);
    for (var i = at + 1; i < at + length; i++) {
      value = value * BigInt.from(256) + BigInt.from(bytes[i]);
    }
    if (bytes[at] & 64 != 0) value -= BigInt.one << (length * 8 - 1);
    if (value.abs() > BigInt.from(_maxExact)) {
      _refuse('TAR numeric field exceeds its exact range.');
    }
    return value.toInt();
  }
  final text = ascii
      .decode(bytes.sublist(at, at + length))
      .replaceAll('\x00', ' ')
      .trim();
  if (text.isEmpty) return null;
  if (!RegExp(r'^[0-7]+$').hasMatch(text)) {
    _refuse('Invalid TAR numeric field.');
  }
  final value = int.tryParse(text, radix: 8);
  if (value == null || value > _maxExact) {
    _refuse('TAR numeric field exceeds its exact range.');
  }
  return value;
}

void _putNumeric(
  Uint8List bytes,
  int at,
  int width,
  int? value, {
  required bool binary,
}) {
  if (value == null) return;
  if (value.abs() > _maxExact) {
    _refuse('TAR numeric metadata exceeds its exact range.');
  }
  final octal = value.toRadixString(8);
  if (value >= 0 && octal.length < width) {
    bytes.setAll(at, ascii.encode(octal.padLeft(width - 1, '0')));
    return;
  }
  if (!binary) {
    _refuse('TAR numeric metadata does not fit this header variant.');
  }
  var encoded = BigInt.from(value);
  if (value < 0) encoded += BigInt.one << (width * 8 - 1);
  if (encoded < BigInt.zero || encoded >= BigInt.one << (width * 8 - 1)) {
    _refuse('TAR base-256 metadata overflows.');
  }
  for (var i = at + width - 1; i >= at; i--) {
    bytes[i] = (encoded & BigInt.from(255)).toInt();
    encoded >>= 8;
  }
  bytes[at] |= 128;
}

int _decimal(String value) {
  if (!RegExp(r'^\d+$').hasMatch(value)) _refuse('Invalid PAX integer.');
  final parsed = int.tryParse(value);
  if (parsed == null || parsed > _maxExact) {
    _refuse('PAX integer exceeds its exact range.');
  }
  return parsed;
}

DateTime _paxTime(String value) {
  final match = RegExp(r'^(-?)(\d+)(?:\.(\d{1,9}))?$').firstMatch(value);
  if (match == null) _refuse('Unsupported PAX timestamp.');
  final whole = int.tryParse(match.group(2)!);
  if (whole == null) _refuse('Invalid PAX timestamp.');
  final sign = match.group(1) == '-' ? -1 : 1;
  _dateRange(whole * sign);
  final fraction = (match.group(3) ?? '').padRight(6, '0').substring(0, 6);
  return DateTime.fromMicrosecondsSinceEpoch(
    sign * (whole * 1000000 + int.parse(fraction)),
    isUtc: true,
  );
}

String _formatTime(DateTime value) {
  final micros = value.microsecondsSinceEpoch;
  final magnitude = micros.abs(),
      seconds = magnitude ~/ 1000000,
      fraction = magnitude % 1000000;
  if (micros < 0 && seconds == 0 && fraction != 0) {
    _refuse(
      'The current TAR reader cannot faithfully represent this negative fractional timestamp.',
    );
  }
  final tail = fraction == 0
      ? ''
      : '.${'$fraction'.padLeft(6, '0').replaceFirst(RegExp(r'0+$'), '')}';
  return '${micros < 0 ? '-' : ''}$seconds$tail';
}

int? _signedAttribute(Map<String, Object?> attrs, String key) {
  final value = attrs[key];
  if (value == null) return null;
  if (value is! int) _refuse('Invalid $key metadata.');
  _dateRange(value);
  return value;
}

DateTime? _headerTime(int? seconds) => seconds == null
    ? null
    : DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
void _dateRange(int seconds) {
  if (seconds < -62135596800 || seconds > 253402300799) {
    _refuse('TAR timestamp is outside the portable date range.');
  }
}

int _aligned(int size) => (size + _block - 1) ~/ _block * _block;
void _range(Uint8List bytes, int at, int count) {
  if (at < 0 || count < 0 || at > bytes.length || count > bytes.length - at) {
    _refuse('Truncated TAR record.');
  }
}

void _zeroPadding(Uint8List bytes, int at, int count) {
  _range(bytes, at, count);
  for (var i = at; i < at + count; i++) {
    if (bytes[i] != 0) {
      _refuse('Opaque TAR padding or extension metadata cannot be discarded.');
    }
  }
}

class _TarRefusal implements Exception {
  _TarRefusal(this.message);
  final String message;
}

Never _refuse(String message) => throw _TarRefusal(message);
