import 'dart:convert';
import 'dart:typed_data';

import 'archive_types.dart';

/// A captured member supplied to an archive/image writer. Each invocation must
/// open a fresh stream over the same captured content; callers retain ownership
/// of the underlying source and revalidate it before publication.
class ArchiveWriteEntry {
  ArchiveWriteEntry({
    required this.path,
    required this.isDirectory,
    required this.size,
    this.modified,
    this.mode,
    Map<String, Object?> attributes = const {},
    Stream<List<int>> Function()? readChunks,
  }) : attributes = Map.unmodifiable(attributes),
       _readChunks = readChunks {
    if (size < 0 || size > 0x1fffffffffffff || isDirectory && size != 0) {
      throw ArgumentError.value(size, 'size');
    }
    if (!isDirectory && readChunks == null) {
      throw ArgumentError('Regular archive members require a captured stream.');
    }
  }

  final String path;
  final bool isDirectory;
  final int size;
  final DateTime? modified;
  final int? mode;
  final Map<String, Object?> attributes;
  final Stream<List<int>> Function()? _readChunks;

  /// Copies bounded chunks and rejects a short or growing source. A writer
  /// never receives a provider-owned mutable buffer to retain after yielding.
  Stream<List<int>> openRead({int chunkSize = 256 * 1024}) async* {
    if (chunkSize <= 0 || chunkSize > 16 * 1024 * 1024) {
      throw ArgumentError.value(chunkSize, 'chunkSize');
    }
    if (isDirectory) return;
    var received = 0;
    await for (final chunk in _readChunks!()) {
      if (chunk.length > size - received) {
        throw ArchiveViewException('The captured member grew: $path');
      }
      if (chunk is! Uint8List && chunk.any((byte) => byte < 0 || byte > 255)) {
        throw ArchiveViewException(
          'The member stream contains invalid bytes: $path',
        );
      }
      for (var offset = 0; offset < chunk.length; offset += chunkSize) {
        final end = offset + chunkSize < chunk.length
            ? offset + chunkSize
            : chunk.length;
        final copy = Uint8List.fromList(chunk.sublist(offset, end));
        received += copy.length;
        yield copy;
      }
    }
    if (received != size) {
      throw ArchiveViewException('The captured member was truncated: $path');
    }
  }

  Future<Uint8List> read({int maxBytes = kArchiveReadLimit}) async {
    if (maxBytes < 0 || size > maxBytes) {
      throw ArchiveViewException(
        'The member exceeds the writer input limit: $path',
      );
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in openRead()) {
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }
}

/// Metadata explicitly understood by a format-specific rewrite inspector.
/// A non-null reason keeps the original container read-only; readers alone do
/// not establish that omitted structures can safely be regenerated.
class ArchiveRewriteInspection {
  ArchiveRewriteInspection({
    this.reason,
    Map<String, Object?> container = const {},
    Map<String, Map<String, Object?>> attributes = const {},
  }) : container = Map.unmodifiable(container),
       attributes = Map.unmodifiable({
         for (final entry in attributes.entries)
           entry.key: Map<String, Object?>.unmodifiable(entry.value),
       });

  final String? reason;
  final Map<String, Object?> container;
  final Map<String, Map<String, Object?>> attributes;
  bool get supported => reason == null;
}

/// Shared namespace checks for direct writer callers, independent of the UI.
void validateArchiveWriteEntries(
  List<ArchiveWriteEntry> entries, {
  int maxEntries = 200000,
  int maxNameBytes = 8 * 1024 * 1024,
  bool allowDirectories = true,
}) {
  if (entries.length > maxEntries) {
    throw const ArchiveViewException('Too many archive members to write.');
  }
  final paths = <String, bool>{};
  var nameBytes = 0;
  for (final entry in entries) {
    final path = entry.path;
    final components = path.split('/');
    nameBytes += utf8.encode(path).length;
    if (path.isEmpty ||
        path.contains('\\') ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(path) ||
        RegExp(r'^[A-Za-z]:').hasMatch(path) ||
        components.length > 200 ||
        components.any((part) => part.isEmpty || part == '.' || part == '..') ||
        utf8.encode(path).length > 4096 ||
        nameBytes > maxNameBytes) {
      throw ArchiveViewException('Unsupported archive member path: $path');
    }
    if (!allowDirectories && (entry.isDirectory || components.length != 1)) {
      throw ArchiveViewException(
        'This format requires flat regular members: $path',
      );
    }
    if (paths.containsKey(path)) {
      throw ArchiveViewException('Duplicate archive member path: $path');
    }
    paths[path] = entry.isDirectory;
  }
  for (final entry in entries) {
    final parts = entry.path.split('/');
    for (var end = 1; end < parts.length; end++) {
      if (paths[parts.take(end).join('/')] == false) {
        throw ArchiveViewException(
          'A file occupies an archive directory: ${entry.path}',
        );
      }
    }
  }
}

/// Collects a bounded writer result for the existing reviewed workspace path.
/// Large image creation uses a file spool instead of this collector.
Future<Uint8List> collectArchiveWrite(
  Future<void> Function(Future<void> Function(List<int>) sink) write, {
  int maxBytes = 256 * 1024 * 1024,
}) async {
  if (maxBytes <= 0) throw ArgumentError.value(maxBytes, 'maxBytes');
  final output = BytesBuilder(copy: false);
  await write((chunk) async {
    if (chunk.length > maxBytes - output.length) {
      throw const ArchiveViewException(
        'The packed archive exceeds its output limit.',
      );
    }
    output.add(Uint8List.fromList(chunk));
  });
  return output.takeBytes();
}
