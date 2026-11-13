import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:koni_archive/koni_archive.dart' as koni;

import 'archive_types.dart';

const int kArchiveVolumeCountLimit = 1024;
const int kArchiveVolumeMetadataLimit = 16 * 1024 * 1024;
const int kArchiveVolumeReadLimit = kArchiveReadLimit + 64 * 1024;

/// One captured, regular file in a numbered volume set.
///
/// [open] must return a fresh, independently closable source on every call. It
/// must retain any access grant needed until that source closes. [validate]
/// checks the captured identity, length and revision without acquiring a new
/// user grant. The joined source calls it before and after each part read.
/// Immutable private snapshots do not need an additional identity callback.
class ArchiveVolumePart {
  const ArchiveVolumePart({
    required this.name,
    required this.length,
    required this.open,
    this.validate,
  });

  final String name;
  final int length;
  final Future<koni.ByteSource> Function() open;
  final Future<void> Function()? validate;
}

/// Recognizes any numeric 7z suffix, including aliases that an opener must
/// reject (for example `.1`, `.01`, or a second padding width).
///
/// This is a routing hint, not validation. A caller discovering sibling parts
/// must include every numeric suffix for the same base, including case aliases,
/// rather than quietly discard an ambiguous or noncanonical sibling.
String? sevenZipVolumeBaseName(String name) {
  final match = RegExp(
    r'^(.+\.7z)\.([0-9]+)$',
    caseSensitive: false,
  ).firstMatch(name);
  return match?.group(1);
}

/// Checks a captured manifest before copying or opening any of its sources.
({String name, int length}) validateSevenZipVolumeManifest(
  List<ArchiveVolumePart> parts, {
  int maxVolumes = kArchiveVolumeCountLimit,
  int maxTotalBytes = kArchiveStreamingLimit,
}) {
  if (maxVolumes <= 0 ||
      maxVolumes > kArchiveVolumeCountLimit ||
      maxTotalBytes <= 0 ||
      maxTotalBytes > kArchiveStreamingLimit) {
    throw ArgumentError('Invalid split-archive manifest limits.');
  }
  final manifest = _validateManifest(parts, maxVolumes, maxTotalBytes);
  return (name: manifest.name, length: manifest.length);
}

/// Joins a complete captured `.7z.001`, `.7z.002`, ... manifest for reading.
///
/// Names must have one exact base and a fixed numeric width of 3–6 digits,
/// start at one, and already be in ascending order. Every part must be nonempty.
/// The caller owns discovery: include all matching siblings from the same
/// storage/account/parent and reject links or provider aliases before calling.
/// This function never opens a path inferred from untrusted archive contents.
///
/// The 7z signature, start-header CRC, next-header CRC and exact declared end
/// are checked before returning. This detects missing final parts, including
/// parts beginning on a file boundary, and refuses trailing data. The ordinary
/// archive reader still validates the full index and member checksums. A part
/// substituted with same-sized data may only be detected when its members are
/// read; this inspection is not a full archive test or authentication.
///
/// Ownership transfers for every opened part and [onClose], including failure.
/// Cached sources are closed before [onClose] releases shared grants/snapshots.
/// Use a distinct read-only archive format such as `volumes/7z`: writing only
/// the selected first part would destroy a volume set.
///
/// 7-Zip's own Split handler exposes numbered parts as one positional stream:
/// https://github.com/ip7z/7zip/blob/main/CPP/7zip/Archive/SplitHandler.cpp
Future<ArchiveVolumeSource> openSevenZipVolumes(
  List<ArchiveVolumePart> parts, {
  bool Function()? isCurrent,
  Future<void> Function()? onClose,
  int maxVolumes = kArchiveVolumeCountLimit,
  int maxTotalBytes = kArchiveStreamingLimit,
  int maxReadBytes = kArchiveVolumeReadLimit,
  int maxMetadataBytes = kArchiveVolumeMetadataLimit,
}) async {
  ArchiveVolumeSource? joined;
  try {
    if (maxVolumes <= 0 ||
        maxVolumes > kArchiveVolumeCountLimit ||
        maxTotalBytes <= 0 ||
        maxTotalBytes > kArchiveStreamingLimit ||
        maxReadBytes <= 0 ||
        maxReadBytes > kArchiveVolumeReadLimit ||
        maxMetadataBytes < 32 ||
        maxMetadataBytes > kArchiveVolumeMetadataLimit) {
      throw ArgumentError('Invalid split-archive resource limits.');
    }
    final manifest = _validateManifest(parts, maxVolumes, maxTotalBytes);
    joined = ArchiveVolumeSource._(
      List<ArchiveVolumePart>.unmodifiable(parts),
      manifest.offsets,
      manifest.length,
      manifest.name,
      isCurrent,
      onClose,
      maxReadBytes,
    );
    for (final part in joined._parts) {
      joined._checkCurrent();
      await part.validate?.call();
      joined._checkCurrent();
    }
    await joined._inspectSevenZip(maxMetadataBytes);
    joined._checkCurrent();
    return joined;
  } catch (error, stack) {
    try {
      if (joined != null) {
        await joined.close();
      } else {
        await onClose?.call();
      }
    } catch (_) {
      // Preserve the inspection failure if releasing a source also fails.
    }
    Error.throwWithStackTrace(error, stack);
  }
}

/// Owning, bounded random access over an inspected 7z volume set.
///
/// Requests are serialized to bound both handle use and temporary memory.
/// Concurrent callers still receive independent positional reads. At most two
/// part sources are open, and underlying reads never exceed 256 KiB. Closing
/// invalidates the source immediately, then waits for in-flight opens/reads to
/// settle before releasing sources and shared ownership.
class ArchiveVolumeSource implements koni.ByteSource {
  ArchiveVolumeSource._(
    this._parts,
    this._offsets,
    this.length,
    this.name,
    this._isCurrent,
    this._onClose,
    this._maxReadBytes,
  );

  final List<ArchiveVolumePart> _parts;
  final List<int> _offsets;
  final bool Function()? _isCurrent;
  final Future<void> Function()? _onClose;
  final int _maxReadBytes;
  final Map<int, koni.ByteSource> _cache = {};
  static const _chunkBytes = 256 * 1024;
  static const _cachedParts = 2;
  bool _closed = false;
  Future<void> _queue = Future<void>.value();
  Future<void>? _closing;

  @override
  final int length;
  @override
  final String name;
  bool get isClosed => _closed;
  int get partCount => _parts.length;

  static const notices = <String>[
    'Read-only numbered 7z volume set. All parts were captured together; '
        'editing or replacing an individual part is unavailable.',
    'Opening validates the part sequence and 7z header checksums. Member '
        'checksums are verified when read; use Test archive to check contents.',
  ];

  @override
  Future<Uint8List> read(int offset, int count) async {
    _checkCurrent();
    if (offset < 0) throw ArgumentError.value(offset, 'offset');
    if (count < 0) throw ArgumentError.value(count, 'length');
    if (offset > length || count > length - offset) {
      throw koni.UnexpectedEofException(
        'Read leaves the captured 7z volume set.',
        offset: offset,
      );
    }
    if (count > _maxReadBytes) {
      throw _limit('A split-archive read exceeds its bounded input window.');
    }
    final next = _queue.then((_) => _read(offset, count));
    _queue = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<Uint8List> _read(int offset, int count) async {
    _checkCurrent();
    final output = Uint8List(count);
    if (count == 0) return output;
    var index = _partAt(offset);
    var written = 0;
    while (written < count) {
      _checkCurrent();
      final part = _parts[index];
      await part.validate?.call();
      _checkCurrent();
      final source = await _openPart(index);
      var within = offset + written - _offsets[index];
      final remaining = count - written;
      final available = part.length - within;
      final take = available < remaining ? available : remaining;
      var received = 0;
      while (received < take) {
        _checkCurrent();
        _checkLength(source, part);
        final left = take - received;
        final chunk = left < _chunkBytes ? left : _chunkBytes;
        final bytes = await source.read(within, chunk);
        _checkCurrent();
        _checkLength(source, part);
        if (bytes.length != chunk) {
          throw _corrupt('A 7z volume returned a truncated byte range.');
        }
        output.setRange(written, written + chunk, bytes);
        written += chunk;
        received += chunk;
        within += chunk;
      }
      await part.validate?.call();
      _checkCurrent();
      _checkLength(source, part);
      index++;
    }
    return output;
  }

  Future<koni.ByteSource> _openPart(int index) async {
    final cached = _cache[index];
    if (cached != null) {
      _checkLength(cached, _parts[index]);
      _cache.remove(index);
      _cache[index] = cached;
      return cached;
    }
    if (_cache.length >= _cachedParts) {
      final oldest = _cache.remove(_cache.keys.first)!;
      await oldest.close();
      _checkCurrent();
    }
    final source = await _parts[index].open();
    // A factory must not return another part's already-owned source.
    if (_cache.values.any((cached) => identical(cached, source))) {
      throw _corrupt('Two 7z volumes share the same mutable source handle.');
    }
    try {
      _checkCurrent();
      _checkLength(source, _parts[index]);
      _cache[index] = source;
      return source;
    } catch (error, stack) {
      try {
        await source.close();
      } catch (_) {
        // The open/identity failure is more useful than a cleanup failure.
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  int _partAt(int offset) {
    var low = 0, high = _offsets.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (_offsets[middle] <= offset) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low - 1;
  }

  void _checkLength(koni.ByteSource source, ArchiveVolumePart part) {
    if (source.length != part.length) {
      throw _corrupt('A 7z volume changed its captured length.');
    }
  }

  void _checkCurrent() {
    if (_closed) {
      throw koni.ArchiveClosedException('The 7z volume set is closed.');
    }
    if (_isCurrent != null && !_isCurrent()) {
      throw _corrupt('The captured 7z volume set is no longer current.');
    }
  }

  Future<void> _inspectSevenZip(int maxMetadataBytes) async {
    if (length < 32) throw _corrupt('The 7z volume set is truncated.');
    // A deliberately small public read window must also work for inspection.
    Future<Uint8List> metadata(int offset, int count) async {
      final bytes = Uint8List(count);
      var copied = 0;
      while (copied < count) {
        final remaining = count - copied;
        final take = remaining < _maxReadBytes ? remaining : _maxReadBytes;
        bytes.setRange(
          copied,
          copied + take,
          await read(offset + copied, take),
        );
        copied += take;
      }
      return bytes;
    }

    final header = await metadata(0, 32);
    const signature = [0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c];
    for (var i = 0; i < signature.length; i++) {
      if (header[i] != signature[i]) {
        throw _corrupt('The numbered files do not contain a 7z archive.');
      }
    }
    if (header[6] != 0) {
      throw const ArchiveViewException(
        'This split 7z archive uses an unsupported major version.',
      );
    }
    final view = ByteData.sublistView(header);
    if (getCrc32(Uint8List.sublistView(header, 12, 32)) !=
        view.getUint32(8, Endian.little)) {
      throw _corrupt('The split 7z start-header checksum is invalid.');
    }
    final nextOffset = _safeUint64(view, 12);
    final nextSize = _safeUint64(view, 20);
    if (nextOffset > length - 32 || nextSize != length - 32 - nextOffset) {
      throw _corrupt(
        'The 7z volume set is incomplete or has unexpected trailing data.',
      );
    }
    if (nextSize > maxMetadataBytes - 32) {
      throw _limit('The split 7z next header exceeds its metadata limit.');
    }
    final next = await metadata(32 + nextOffset, nextSize);
    if (getCrc32(next) != view.getUint32(28, Endian.little)) {
      throw _corrupt('The split 7z next-header checksum is invalid.');
    }
  }

  @override
  Future<void> close() {
    _closed = true;
    return _closing ??= _queue.then((_) async {
      Object? firstError;
      StackTrace? firstStack;
      Future<void> release(Future<void> Function() action) async {
        try {
          await action();
        } catch (error, stack) {
          firstError ??= error;
          firstStack ??= stack;
        }
      }

      final sources = _cache.values.toList(growable: false);
      _cache.clear();
      for (final source in sources) {
        await release(source.close);
      }
      if (_onClose != null) await release(_onClose);
      if (firstError != null) {
        Error.throwWithStackTrace(firstError!, firstStack!);
      }
    });
  }
}

({String name, int length, List<int> offsets}) _validateManifest(
  List<ArchiveVolumePart> parts,
  int maxVolumes,
  int maxTotalBytes,
) {
  if (parts.isEmpty) throw _corrupt('No 7z archive volumes were supplied.');
  if (parts.length > maxVolumes) {
    throw _limit('The 7z volume set contains too many parts.');
  }
  final first = RegExp(
    r'^(.+\.7z)\.([0-9]{3,6})$',
    caseSensitive: false,
  ).firstMatch(parts.first.name);
  if (first == null || int.parse(first.group(2)!) != 1) {
    throw const ArchiveViewException(
      'Open the first 7z volume, using a suffix such as .7z.001.',
    );
  }
  final base = first.group(1)!;
  final width = first.group(2)!.length;
  final offsets = <int>[];
  var total = 0;
  for (var index = 0; index < parts.length; index++) {
    final part = parts[index];
    final expected = '$base.${(index + 1).toString().padLeft(width, '0')}';
    if (part.name.length > 1024 ||
        part.name.contains(RegExp(r'[/\\\x00]')) ||
        part.name != expected ||
        (index + 1).toString().length > width) {
      throw _corrupt(
        '7z volumes must have one exact base, a contiguous sequence, and '
        'one fixed numbering width without aliases.',
      );
    }
    if (part.length <= 0) {
      throw _corrupt('A 7z volume has no captured nonempty length.');
    }
    if (part.length > maxTotalBytes - total) {
      throw _limit('The combined 7z volumes exceed the input limit.');
    }
    offsets.add(total);
    total += part.length;
  }
  return (name: base, length: total, offsets: List<int>.unmodifiable(offsets));
}

int _safeUint64(ByteData view, int offset) {
  final high = view.getUint32(offset + 4, Endian.little);
  if (high > 0x1fffff) {
    throw _corrupt('A 7z header position cannot be represented safely.');
  }
  return high * 4294967296 + view.getUint32(offset, Endian.little);
}

ArchiveViewException _corrupt(String detail) => ArchiveViewException(
  detail,
  code: ArchiveMessageCode.corrupt,
  arguments: {'detail': detail},
);

ArchiveViewException _limit(String detail) => ArchiveViewException(
  detail,
  code: ArchiveMessageCode.archiveLimit,
  arguments: {'detail': detail, 'limit': 'split-archive resource limit'},
);
