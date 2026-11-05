// lib/services/archive_viewer_service.dart
//
// Archive reading for the F3 viewer, built on two MIT/BSD-licensed pure-Dart
// libraries:
//
//  * package:koni_archive — ZIP, TAR, GZIP (incl. .tar.gz), 7z and RAR.
//    Metadata-only open, streaming reads with a per-entry size cap
//    (decompression-bomb protection), sanitized entry paths, checksum
//    verification, and password support (ZIP/7z/RAR4/RAR5).
//  * package:archive — bounded decompression for bzip2 / xz / zstd
//    containers (`.tar.bz2`, `.tbz2`, `.tar.xz`, `.tar.zst`, …) and
//    single-file `.gz`/`.bz2`/`.xz`/`.zst` expansion. Every decode passes
//    `maxOutputSize`, so a compression bomb fails with an error instead of
//    exhausting memory.
//
// Neither library is GPL; both are permissive (koni_archive: MIT,
// archive: MIT). No native code, no FFI, works on Flutter web too.

import 'dart:typed_data';

import 'package:archive/archive.dart' as ar;
import 'package:koni_archive/koni_archive.dart' as koni;

/// Maximum bytes read from a single archive member / decompressed container.
const int kArchiveReadLimit = 64 * 1024 * 1024;

/// Machine-readable identifiers for app-authored archive messages.
enum ArchiveMessageCode {
  closed, archiveLimit, corrupt, entryLimit, entryLimitDetail, readEntry,
  singleFormat, decompressFile, decompressArchive, unsupported,
  archiveEncrypted, entryEncrypted, wrongOrCorrupt,
}

/// A user-presentable archive error (unsupported, corrupt, oversized).
class ArchiveViewException implements Exception {
  final String message;
  final ArchiveMessageCode? code;
  final Map<String, Object> arguments;
  const ArchiveViewException(this.message, {this.code, this.arguments = const {}});

  @override
  String toString() => message;
}

/// The archive (or a member) is encrypted and needs a password.
class ArchivePasswordRequiredException implements Exception {
  final String message;

  /// True when a password was supplied but rejected.
  final bool wrongPassword;
  final ArchiveMessageCode? code;
  final Map<String, Object> arguments;

  const ArchivePasswordRequiredException(
    this.message, {
    this.wrongPassword = false,
    this.code,
    this.arguments = const {},
  });

  @override
  String toString() => message;
}

/// One listing row.
class ViewerArchiveMember {
  final String name;
  final int size;
  final bool isFile;
  final bool isEncrypted;

  /// True when the stored path tried to escape the archive root (`..`) and
  /// was sanitized by the parser.
  final bool pathEscapedRoot;

  /// Index into the underlying parser's entry list.
  final int index;

  const ViewerArchiveMember({
    required this.name,
    required this.size,
    required this.isFile,
    required this.isEncrypted,
    required this.pathEscapedRoot,
    required this.index,
  });
}

/// An opened archive: metadata plus lazy, size-capped member reads.
class ViewerArchive {
  final String formatName;
  final List<ViewerArchiveMember> members;

  final Future<Uint8List> Function(ViewerArchiveMember member, int maxBytes)
      _read;
  final Future<void> Function() _close;
  bool _closed = false;

  ViewerArchive._({
    required this.formatName,
    required this.members,
    required Future<Uint8List> Function(
      ViewerArchiveMember member,
      int maxBytes,
    ) read,
    required Future<void> Function() close,
  })  : _read = read,
        _close = close;

  /// A one-member archive over already-decompressed bytes.
  factory ViewerArchive.direct({
    required String formatName,
    required String name,
    required Uint8List data,
  }) {
    final member = ViewerArchiveMember(
      name: name,
      size: data.length,
      isFile: true,
      isEncrypted: false,
      pathEscapedRoot: false,
      index: 0,
    );
    return ViewerArchive._(
      formatName: formatName,
      members: List<ViewerArchiveMember>.unmodifiable([member]),
      read: (_, __) async => data,
      close: () async {},
    );
  }

  bool get isClosed => _closed;

  Future<Uint8List> readMember(
    ViewerArchiveMember member, {
    int maxBytes = kArchiveReadLimit,
  }) async {
    if (_closed) {
      throw const ArchiveViewException('This archive has been closed.', code: ArchiveMessageCode.closed);
    }
    return _read(member, maxBytes);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _close();
    } catch (_) {
      // Closing is best-effort; the data is in memory already.
    }
  }
}

/// Open [bytes] as an archive.
///
/// Throws [ArchivePasswordRequiredException] for encrypted archives and
/// [ArchiveViewException] for unsupported/corrupt/oversized input.
Future<ViewerArchive> openViewerArchive(
  Uint8List bytes, {
  required String name,
  String? password,
  int maxMemberBytes = kArchiveReadLimit,
}) async {
  final lower = name.toLowerCase();

  // bzip2/xz/zstd containers are decoded here (bounded), then listed as TAR
  // when they contain one, or exposed as a single decompressed entry.
  if (_isPackageCompressed(lower)) {
    final decompressed = _decompressContainer(
      bytes,
      lower,
      maxMemberBytes,
    );
    if (_isTarContainerName(lower) || looksLikeTar(decompressed)) {
      return _openWithKoni(
        decompressed,
        password: password,
        maxMemberBytes: maxMemberBytes,
      );
    }
    return ViewerArchive.direct(
      formatName: _compressionLabel(lower),
      name: stripCompressionSuffix(name),
      data: decompressed,
    );
  }

  return _openWithKoni(
    bytes,
    password: password,
    maxMemberBytes: maxMemberBytes,
  );
}

Future<ViewerArchive> _openWithKoni(
  Uint8List bytes, {
  String? password,
  required int maxMemberBytes,
}) async {
  final source = koni.MemoryByteSource(bytes);
  koni.ArchiveReader reader;
  try {
    // Use the reader directly (not the Archive facade): a reader may throw
    // synchronously from openRead() for encrypted/unsupported entries, and
    // the facade's stream wrapper turns that into an unclosed stream (hang).
    reader = await koni.builtInFormats.openReader(
      source,
      options: koni.ArchiveReadOptions(
        password: password,
        maxEntrySize: maxMemberBytes,
        maxEntryCount: 200000,
        maxContainerDecodeSize: maxMemberBytes,
      ),
    );
  } on koni.EncryptedArchiveException catch (e) {
    await source.close();
    throw ArchivePasswordRequiredException(
      'This archive is encrypted.',
      code: ArchiveMessageCode.archiveEncrypted,
      wrongPassword: password != null || e is koni.InvalidPasswordException,
    );
  } on koni.SizeLimitExceededException catch (e) {
    await source.close();
    throw ArchiveViewException(
      'The archive expands beyond the ${_mb(maxMemberBytes)} safety limit '
      '(${e.message}).',
      code: ArchiveMessageCode.archiveLimit,
      arguments: {'limit': _mb(maxMemberBytes), 'detail': e.message},
    );
  } on koni.ArchiveException catch (e) {
    await source.close();
    throw ArchiveViewException('Unsupported or corrupt archive: ${e.message}', code: ArchiveMessageCode.corrupt, arguments: {'detail': e.message});
  } catch (e) {
    await source.close();
    throw ArchiveViewException('Unsupported or corrupt archive: $e', code: ArchiveMessageCode.corrupt, arguments: {'detail': e});
  }

  final entries = reader.entries;
  final members = <ViewerArchiveMember>[];
  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i];
    members.add(
      ViewerArchiveMember(
        name: entry.path.isEmpty ? '/' : entry.path,
        size: entry.uncompressedSize,
        isFile: entry.isFile,
        isEncrypted: entry.isEncrypted,
        pathEscapedRoot: entry.pathEscapedRoot,
        index: i,
      ),
    );
  }

  return ViewerArchive._(
    formatName: reader.format.name,
    members: List<ViewerArchiveMember>.unmodifiable(members),
    read: (member, requestedCap) async {
      final limit =
          requestedCap < maxMemberBytes ? requestedCap : maxMemberBytes;
      final entry = entries[member.index];
      if (entry.isEncrypted && password == null) {
        throw const ArchivePasswordRequiredException(
            'This entry is encrypted.', code: ArchiveMessageCode.entryEncrypted);
      }
      final builder = BytesBuilder(copy: false);
      try {
        final stream = reader.openRead(entry); // may throw synchronously
        await for (final chunk in stream) {
          if (builder.length + chunk.length > limit) {
            throw ArchiveViewException(
              'The entry is larger than the ${_mb(limit)} safety limit.',
              code: ArchiveMessageCode.entryLimit, arguments: {'limit': _mb(limit)},
            );
          }
          builder.add(chunk);
        }
      } on ArchiveViewException {
        rethrow;
      } on koni.EncryptedArchiveException catch (e) {
        throw ArchivePasswordRequiredException(
          'This entry is encrypted.',
          code: ArchiveMessageCode.entryEncrypted,
          wrongPassword: password != null || e is koni.InvalidPasswordException,
        );
      } on koni.SizeLimitExceededException catch (e) {
        throw ArchiveViewException(
          'The entry is larger than the ${_mb(limit)} safety limit '
          '(${e.message}).',
          code: ArchiveMessageCode.entryLimitDetail, arguments: {'limit': _mb(limit), 'detail': e.message},
        );
      } on koni.ArchiveException catch (e) {
        if (entry.isEncrypted) {
          // 7z has no password check: a wrong password shows up as corrupt
          // data or a checksum mismatch.
          throw const ArchivePasswordRequiredException(
            'The password is wrong or the entry is corrupt.',
            code: ArchiveMessageCode.wrongOrCorrupt,
            wrongPassword: true,
          );
        }
        throw ArchiveViewException('Could not read entry: ${e.message}', code: ArchiveMessageCode.readEntry, arguments: {'detail': e.message});
      } catch (e) {
        throw ArchiveViewException('Could not read entry: $e', code: ArchiveMessageCode.readEntry, arguments: {'detail': e});
      }
      return builder.takeBytes();
    },
    close: () async {
      try {
        await reader.close();
      } finally {
        await source.close();
      }
    },
  );
}

// ---------------------------------------------------------------------------
// Single-file compression
// ---------------------------------------------------------------------------

/// Whether [name] is a single-file compression (not a tar container):
/// `.gz`, `.bz2`, `.xz`, `.zst` — used to auto-expand on open.
bool isSingleCompressedFile(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.tar.gz') || lower.endsWith('.tgz')) return false;
  if (_isTarContainerName(lower)) return false;
  return lower.endsWith('.gz') ||
      lower.endsWith('.bz2') ||
      lower.endsWith('.xz') ||
      lower.endsWith('.zst');
}

/// Remove a single compression suffix (`.gz`, `.bz2`, `.xz`, `.zst`).
String stripCompressionSuffix(String name) {
  final lower = name.toLowerCase();
  for (final suffix in const ['.gz', '.bz2', '.xz', '.zst']) {
    if (lower.endsWith(suffix)) {
      return name.substring(0, name.length - suffix.length);
    }
  }
  return name;
}

/// Decompress a single-file `.gz`/`.bz2`/`.xz`/`.zst` payload, bounded by
/// [maxBytes] so compression bombs cannot exhaust memory.
({Uint8List data, String innerName}) decompressSingleFile(
  Uint8List bytes,
  String name, {
  int maxBytes = kArchiveReadLimit,
}) {
  final lower = name.toLowerCase();
  final Uint8List data;
  try {
    if (lower.endsWith('.gz')) {
      data = const ar.GZipDecoder().decodeBytes(bytes, maxOutputSize: maxBytes);
    } else if (lower.endsWith('.bz2') ||
        lower.endsWith('.tbz2') ||
        lower.endsWith('.tbz')) {
      data = ar.BZip2Decoder().decodeBytes(bytes, maxOutputSize: maxBytes);
    } else if (lower.endsWith('.xz') || lower.endsWith('.txz')) {
      data = ar.XZDecoder().decodeBytes(bytes, maxOutputSize: maxBytes);
    } else if (lower.endsWith('.zst') || lower.endsWith('.tzst')) {
      data = ar.ZstdDecoder().decodeBytes(bytes, maxOutputSize: maxBytes);
    } else {
      throw ArchiveViewException('Not a single-file compressed format: $name', code: ArchiveMessageCode.singleFormat, arguments: {'name': name});
    }
  } on ArchiveViewException {
    rethrow;
  } catch (e) {
    throw ArchiveViewException(
      'Could not decompress $name (it may be corrupt or larger than the '
      '${_mb(maxBytes)} safety limit): $e',
      code: ArchiveMessageCode.decompressFile, arguments: {'name': name, 'limit': _mb(maxBytes), 'detail': e},
    );
  }
  return (data: data, innerName: stripCompressionSuffix(name));
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const List<String> _tarCompressedSuffixes = <String>[
  '.tar.bz2',
  '.tbz2',
  '.tbz',
  '.tar.xz',
  '.txz',
  '.tar.zst',
  '.tzst',
];

bool _isTarContainerName(String lower) =>
    _tarCompressedSuffixes.any(lower.endsWith);

bool _isPackageCompressed(String lower) =>
    lower.endsWith('.bz2') ||
    lower.endsWith('.tbz2') ||
    lower.endsWith('.tbz') ||
    lower.endsWith('.xz') ||
    lower.endsWith('.txz') ||
    lower.endsWith('.zst') ||
    lower.endsWith('.tzst');

/// True when the buffer starts with the POSIX tar magic at offset 257.
bool looksLikeTar(Uint8List data) {
  if (data.length < 262) return false;
  return data[257] == 0x75 && // u
      data[258] == 0x73 && // s
      data[259] == 0x74 && // t
      data[260] == 0x61 && // a
      data[261] == 0x72; // r
}

Uint8List _decompressContainer(Uint8List bytes, String lower, int cap) {
  try {
    if (lower.endsWith('.bz2') ||
        lower.endsWith('.tbz2') ||
        lower.endsWith('.tbz')) {
      return ar.BZip2Decoder().decodeBytes(bytes, maxOutputSize: cap);
    }
    if (lower.endsWith('.xz') || lower.endsWith('.txz')) {
      return ar.XZDecoder().decodeBytes(bytes, maxOutputSize: cap);
    }
    if (lower.endsWith('.zst') || lower.endsWith('.tzst')) {
      return ar.ZstdDecoder().decodeBytes(bytes, maxOutputSize: cap);
    }
  } catch (e) {
    throw ArchiveViewException(
      'Could not decompress the archive (corrupt or larger than the '
      '${_mb(cap)} safety limit): $e',
      code: ArchiveMessageCode.decompressArchive, arguments: {'limit': _mb(cap), 'detail': e},
    );
  }
  throw ArchiveViewException('Not a supported compressed archive: $lower', code: ArchiveMessageCode.unsupported, arguments: {'name': lower});
}

String _compressionLabel(String lower) {
  if (lower.endsWith('.bz2') ||
      lower.endsWith('.tbz2') ||
      lower.endsWith('.tbz')) {
    return 'bzip2';
  }
  if (lower.endsWith('.xz') || lower.endsWith('.txz')) return 'xz';
  return 'zstd';
}

String _mb(int bytes) => '${(bytes / (1024 * 1024)).round()} MB';
