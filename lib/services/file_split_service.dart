import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import 'file_integrity_service.dart';
import 'file_operation_backend.dart';
import 'file_operation_service.dart';
import 'local_file_service.dart';

const kSplitManifestMaxBytes = 8 * 1024 * 1024;
const kSplitMaxParts = 10000;

enum SplitManifestStatus { incomplete, complete, cancelled, failed }

class SplitPart {
  const SplitPart({
    required this.index,
    required this.path,
    required this.size,
    required this.sha256,
  });
  final int index;
  final String path;
  final int size;
  final String sha256;
  Map<String, Object> toJson() => {
    'index': index,
    'path': path,
    'size': size,
    'sha256': sha256,
  };
}

class SplitManifest {
  const SplitManifest({
    required this.originalName,
    required this.totalBytes,
    required this.chunkSize,
    required this.status,
    required this.parts,
    this.sha256,
  });
  final String originalName;
  final int totalBytes;
  final int chunkSize;
  final SplitManifestStatus status;
  final List<SplitPart> parts;
  final String? sha256;
  int get expectedParts => math.max(
    1,
    totalBytes ~/ chunkSize + (totalBytes % chunkSize == 0 ? 0 : 1),
  );
  int sizeOfPart(int index) =>
      math.min(chunkSize, math.max(0, totalBytes - (index - 1) * chunkSize));
  Map<String, Object?> toJson() => {
    'format': 'CrispCloud split',
    'version': 1,
    'originalName': originalName,
    'totalBytes': totalBytes,
    'chunkSize': chunkSize,
    'expectedParts': expectedParts,
    'status': status.name,
    'sha256': sha256,
    'parts': parts.map((part) => part.toJson()).toList(),
  };
  List<int> encode() {
    final bytes = utf8.encode('${jsonEncode(toJson())}\n');
    if (bytes.length > kSplitManifestMaxBytes) {
      throw const FormatException('Split manifest exceeds 8 MiB.');
    }
    return bytes;
  }

  SplitManifest copyWith({
    SplitManifestStatus? status,
    List<SplitPart>? parts,
    String? sha256,
  }) => SplitManifest(
    originalName: originalName,
    totalBytes: totalBytes,
    chunkSize: chunkSize,
    status: status ?? this.status,
    parts: parts ?? this.parts,
    sha256: sha256 ?? this.sha256,
  );

  static SplitManifest decode(List<int> bytes) {
    if (bytes.length > kSplitManifestMaxBytes) {
      throw const FormatException('Split manifest exceeds 8 MiB.');
    }
    final json = jsonDecode(utf8.decode(bytes));
    if (json is! Map<String, dynamic> ||
        json['format'] != 'CrispCloud split' ||
        json['version'] != 1 ||
        json['originalName'] is! String ||
        (json['originalName'] as String).isEmpty ||
        (json['originalName'] as String).length > 8192 ||
        json['totalBytes'] is! int ||
        (json['totalBytes'] as int) < 0 ||
        json['chunkSize'] is! int ||
        (json['chunkSize'] as int) <= 0 ||
        json['parts'] is! List ||
        (json['parts'] as List).length > kSplitMaxParts) {
      throw const FormatException('Invalid or unsupported split manifest.');
    }
    final status = SplitManifestStatus.values
        .where((value) => value.name == json['status'])
        .firstOrNull;
    if (status == null) throw const FormatException('Invalid split status.');
    final parts = <SplitPart>[];
    for (final part in json['parts'] as List) {
      if (part is! Map<String, dynamic> ||
          part['index'] is! int ||
          part['index'] != parts.length + 1 ||
          part['path'] is! String ||
          (part['path'] as String).isEmpty ||
          (part['path'] as String).length > 8192 ||
          part['size'] is! int ||
          (part['size'] as int) < 0 ||
          part['sha256'] is! String ||
          !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(part['sha256'] as String)) {
        throw const FormatException(
          'Invalid, duplicate or unordered split part.',
        );
      }
      parts.add(
        SplitPart(
          index: part['index'] as int,
          path: part['path'] as String,
          size: part['size'] as int,
          sha256: (part['sha256'] as String).toLowerCase(),
        ),
      );
    }
    final digest = json['sha256'];
    if (digest != null &&
        (digest is! String || !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(digest))) {
      throw const FormatException('Invalid whole-file checksum.');
    }
    final manifest = SplitManifest(
      originalName: json['originalName'] as String,
      totalBytes: json['totalBytes'] as int,
      chunkSize: json['chunkSize'] as int,
      status: status,
      parts: List.unmodifiable(parts),
      sha256: (digest as String?)?.toLowerCase(),
    );
    if (manifest.expectedParts > kSplitMaxParts ||
        json['expectedParts'] != manifest.expectedParts ||
        parts.length > manifest.expectedParts ||
        parts.any((part) => part.size != manifest.sizeOfPart(part.index)) ||
        status == SplitManifestStatus.complete &&
            (parts.length != manifest.expectedParts ||
                manifest.sha256 == null)) {
      throw const FormatException(
        'The manifest has missing parts or inconsistent sizes.',
      );
    }
    return manifest;
  }
}

class SplitResult {
  const SplitResult(this.manifestPath, this.manifest, this.partPaths);
  final String manifestPath;
  final SplitManifest manifest;
  final List<String> partPaths;
}

/// Holds only an upstream chunk and returns bounded slices; part size never
/// determines a memory allocation.
class _PartReader {
  _PartReader(Stream<List<int>> input) : _input = StreamIterator(input);
  final StreamIterator<List<int>> _input;
  List<int> _chunk = const [];
  int _offset = 0;
  bool _started = false;
  bool _ended = false;
  Future<bool> _next() async {
    if (_ended) return false;
    while (_offset == _chunk.length) {
      _started = true;
      if (!await _input.moveNext()) {
        _ended = true;
        return false;
      }
      _chunk = _input.current;
      _offset = 0;
    }
    return true;
  }

  Stream<List<int>> take(int length, void Function(List<int>) onChunk) async* {
    var left = length;
    while (left > 0) {
      if (!await _next()) {
        throw StateError('The source ended before the expected part size.');
      }
      final count = math.min(
        left,
        math.min(_chunk.length - _offset, 256 * 1024),
      );
      final bytes = _chunk.sublist(_offset, _offset + count);
      _offset += count;
      left -= count;
      onChunk(bytes);
      yield bytes;
    }
  }

  Future<bool> get hasMore => _next();
  Future<void> close() async {
    // A naturally drained stream has already released its subscription. Avoid
    // cancelling it twice, and never start an input just to cancel it.
    if (_started && !_ended) await _input.cancel();
    _ended = true;
    _chunk = const [];
  }
}

class FileSplitService {
  static FileOperationBackend _local() =>
      LocalOperationBackend(LocalFileService(), isCurrent: () => true);
  static FileItem _file(String path) =>
      FileItem(name: p.basename(path), path: path, isFolder: false);
  static String partName(String baseName, int index) =>
      '$baseName.part${index.toString().padLeft(3, '0')}';

  static Future<SplitResult> splitToBackend({
    required FileOperationBackend source,
    required FileItem file,
    required FileOperationBackend destination,
    required String targetDirectory,
    required int chunkSizeBytes,
    bool Function()? isCancelled,
    void Function(String phase, int bytes, int total)? onProgress,
  }) async {
    if (chunkSizeBytes <= 0) {
      throw ArgumentError.value(chunkSizeBytes, 'chunkSizeBytes');
    }
    final original = await requireIntegrityFile(
      source,
      file,
      isCancelled: isCancelled,
    );
    final total = original.size;
    if (total == null) {
      throw UnsupportedError(
        'The source must report its size before splitting.',
      );
    }
    if (!destination.supportsStagedVerification) {
      throw UnsupportedError(
        'This destination cannot verify a staged file before committing it.',
      );
    }
    if (!destination.capabilities.boundedUpload &&
        math.min(chunkSizeBytes, total) > 64 * 1024 * 1024) {
      throw UnsupportedError(
        'This destination needs part sizes of 64 MiB or smaller.',
      );
    }
    final directory = await destination.stat(targetDirectory);
    if (directory == null ||
        !directory.isFolder ||
        directory.isSymlink == true) {
      throw StateError('Choose an existing destination directory.');
    }
    var manifest = SplitManifest(
      originalName: original.name,
      totalBytes: total,
      chunkSize: chunkSizeBytes,
      status: SplitManifestStatus.incomplete,
      parts: const [],
    );
    if (manifest.expectedParts > kSplitMaxParts) {
      throw ArgumentError(
        'Choose a larger part size; at most $kSplitMaxParts parts are supported.',
      );
    }
    final manifestPath = resolveIntegrityPath(
      destination,
      targetDirectory,
      '${original.name}.split.json',
    );
    final partPaths = <String>[];
    for (var index = 1; index <= manifest.expectedParts; index++) {
      final path = resolveIntegrityPath(
        destination,
        targetDirectory,
        partName(original.name, index),
      );
      if (await destination.stat(path) != null) {
        throw StateError('A part already exists: $path');
      }
      partPaths.add(path);
    }
    if (await destination.stat(manifestPath) != null) {
      throw StateError('A split manifest already exists: $manifestPath');
    }
    // Refuse overlarge manifests before any file is created.
    manifest
        .copyWith(
          parts: [
            for (var index = 1; index <= manifest.expectedParts; index++)
              SplitPart(
                index: index,
                path: partName(original.name, index),
                size: manifest.sizeOfPart(index),
                sha256: '0' * 64,
              ),
          ],
        )
        .encode();
    final whole = ChecksumAccumulator(ChecksumAlgorithm.sha256);
    final completed = <SplitPart>[];
    final reader = _PartReader(source.readFile(original));
    String? writtenManifestHash;
    var written = 0;
    void check() {
      checkIntegrityCurrent(source, isCancelled);
      checkIntegrityCurrent(destination, isCancelled);
    }

    Future<void> saveManifest({bool finishingFailure = false}) async {
      final bytes = manifest.encode();
      final expectedPrevious = writtenManifestHash;
      Future<void> checkPrevious() async {
        final existing = await destination.stat(manifestPath);
        if (expectedPrevious == null) {
          if (existing != null) {
            throw StateError(
              'A different manifest appeared at the destination.',
            );
          }
        } else if (existing == null ||
            await hashIntegrityFile(
                  destination,
                  existing,
                  ChecksumAlgorithm.sha256,
                ) !=
                expectedPrevious) {
          throw StateError('The split manifest was changed externally.');
        }
      }

      await checkPrevious();
      await writeIntegrityBytes(
        destination,
        manifestPath,
        bytes,
        replace: expectedPrevious != null,
        isCancelled: finishingFailure ? null : isCancelled,
        beforeCommit: checkPrevious,
      );
      final digest = ChecksumAccumulator(ChecksumAlgorithm.sha256)..add(bytes);
      writtenManifestHash = digest.finish();
    }

    try {
      check();
      await saveManifest();
      for (var index = 1; index <= manifest.expectedParts; index++) {
        check();
        final size = manifest.sizeOfPart(index);
        final hash = ChecksumAccumulator(ChecksumAlgorithm.sha256);
        var consumed = 0;
        final stream = reader.take(size, (bytes) {
          check();
          hash.add(bytes);
          whole.add(bytes);
          consumed += bytes.length;
          written += bytes.length;
          onProgress?.call(
            'Splitting part $index of ${manifest.expectedParts}',
            written,
            total,
          );
        });
        await destination.writePreparedFile(
          partPaths[index - 1],
          stream,
          size,
          replace: false,
          verifyStaged: (staged) async {
            check();
            if (consumed != size) {
              throw StateError(
                'The destination did not consume the complete part.',
              );
            }
            final actual = await hashIntegrityFile(
              destination,
              staged,
              ChecksumAlgorithm.sha256,
              isCancelled: isCancelled,
            );
            if (actual != hash.finish()) {
              throw StateError('Part $index failed verification.');
            }
          },
        );
        check();
        completed.add(
          SplitPart(
            index: index,
            path: partName(original.name, index),
            size: size,
            sha256: hash.finish(),
          ),
        );
        manifest = manifest.copyWith(parts: List.unmodifiable(completed));
        await saveManifest();
      }
      if (await reader.hasMore) {
        throw StateError('The source grew while splitting.');
      }
      final after = await source.stat(original.path!);
      check();
      if (after == null ||
          !sameIntegrityVersion(original, after) ||
          written != total) {
        throw StateError('The source changed while splitting.');
      }
      manifest = manifest.copyWith(
        status: SplitManifestStatus.complete,
        sha256: whole.finish(),
      );
      await saveManifest();
      onProgress?.call('Split and manifest verified', written, total);
      return SplitResult(manifestPath, manifest, List.unmodifiable(partPaths));
    } catch (error) {
      if (writtenManifestHash != null && destination.isCurrent) {
        manifest = manifest.copyWith(
          status: error is FileIntegrityCancelled
              ? SplitManifestStatus.cancelled
              : SplitManifestStatus.failed,
        );
        try {
          await saveManifest(finishingFailure: true);
        } catch (_) {
          /* Keep original failure. */
        }
      }
      rethrow;
    } finally {
      await reader.close();
    }
  }

  static Future<SplitManifest> readManifest(
    FileOperationBackend source,
    FileItem file, {
    bool Function()? isCancelled,
  }) async => SplitManifest.decode(
    await readIntegrityBytes(
      source,
      file,
      maxBytes: kSplitManifestMaxBytes,
      isCancelled: isCancelled,
    ),
  );

  static Future<String> combineFromManifest({
    required FileOperationBackend source,
    required FileItem manifestFile,
    required FileOperationBackend destination,
    required String outputPath,
    bool Function()? isCancelled,
    void Function(String phase, int bytes, int total)? onProgress,
  }) async {
    final manifest = await readManifest(
      source,
      manifestFile,
      isCancelled: isCancelled,
    );
    if (manifest.status != SplitManifestStatus.complete) {
      throw StateError(
        'This split is ${manifest.status.name}; ${manifest.parts.length} of ${manifest.expectedParts} parts were recorded.',
      );
    }
    final base = source.paths.dirname(manifestFile.path!);
    final seen = <String>{};
    final files = <FileItem>[];
    for (final part in manifest.parts) {
      final path = resolveIntegrityPath(source, base, part.path);
      if (!seen.add(source.pathKey(path))) {
        throw const FormatException('Duplicate split part path.');
      }
      await rejectIntegritySymlinkParents(
        source,
        base,
        path,
        isCancelled: isCancelled,
      );
      final file = await requireIntegrityFile(
        source,
        _file(path),
        isCancelled: isCancelled,
      );
      if (file.size != part.size) {
        throw StateError(
          'Missing or truncated part ${part.index}: ${part.path}',
        );
      }
      files.add(file);
    }
    return _combine(
      source: source,
      files: files,
      parts: manifest.parts,
      expectedWhole: manifest.sha256,
      destination: destination,
      outputPath: outputPath,
      isCancelled: isCancelled,
      onProgress: onProgress,
    );
  }

  static Future<String> combineLegacy({
    required FileOperationBackend source,
    required List<FileItem> files,
    required FileOperationBackend destination,
    required String outputPath,
    required bool allowUnverifiedLegacy,
    bool Function()? isCancelled,
    void Function(String phase, int bytes, int total)? onProgress,
  }) async {
    if (!allowUnverifiedLegacy) {
      throw StateError(
        'No integrity manifest. Confirm legacy combination; a missing final part cannot be detected.',
      );
    }
    final ordered = orderedLegacyParts(source, files);
    final parts = <SplitPart>[];
    for (var index = 0; index < ordered.length; index++) {
      final current = await requireIntegrityFile(
        source,
        ordered[index],
        isCancelled: isCancelled,
      );
      if (current.size == null) {
        throw StateError('Part size is unavailable: ${current.path}');
      }
      parts.add(
        SplitPart(
          index: index + 1,
          path: current.path!,
          size: current.size!,
          sha256: await hashIntegrityFile(
            source,
            current,
            ChecksumAlgorithm.sha256,
            isCancelled: isCancelled,
          ),
        ),
      );
    }
    return _combine(
      source: source,
      files: ordered,
      parts: parts,
      destination: destination,
      outputPath: outputPath,
      isCancelled: isCancelled,
      onProgress: onProgress,
    );
  }

  static List<FileItem> orderedLegacyParts(
    FileOperationBackend source,
    List<FileItem> files,
  ) {
    if (files.isEmpty || files.length > kSplitMaxParts) {
      throw ArgumentError('Choose one or more numbered parts.');
    }
    final numbered = <(int, FileItem)>[];
    String? prefix;
    for (final file in files) {
      final match = RegExp(
        r'^(.*?)(\.part|\.)(\d{3,})$',
        caseSensitive: false,
      ).firstMatch(file.path ?? '');
      if (match == null || file.isFolder) {
        throw FormatException('Not a numbered part: ${file.name}');
      }
      final currentPrefix = source.pathKey('${match[1]}${match[2]}');
      if (prefix != null && currentPrefix != prefix) {
        throw const FormatException('Parts belong to different split files.');
      }
      prefix = currentPrefix;
      numbered.add((int.parse(match[3]!), file));
    }
    numbered.sort((a, b) => a.$1.compareTo(b.$1));
    for (var index = 0; index < numbered.length; index++) {
      if (numbered[index].$1 != index + 1) {
        throw StateError('Missing or duplicate part ${index + 1}.');
      }
    }
    return numbered.map((entry) => entry.$2).toList();
  }

  static Future<String> _combine({
    required FileOperationBackend source,
    required List<FileItem> files,
    required List<SplitPart> parts,
    String? expectedWhole,
    required FileOperationBackend destination,
    required String outputPath,
    bool Function()? isCancelled,
    void Function(String phase, int bytes, int total)? onProgress,
  }) async {
    if (!destination.supportsStagedVerification) {
      throw UnsupportedError(
        'This destination cannot verify combined data before committing it.',
      );
    }
    if (await destination.stat(outputPath) != null) {
      throw StateError('The output already exists: $outputPath');
    }
    final outputDirectory = await destination.stat(
      destination.paths.dirname(outputPath),
    );
    if (outputDirectory == null ||
        !outputDirectory.isFolder ||
        outputDirectory.isSymlink == true) {
      throw StateError('Choose an existing destination directory.');
    }
    final total = parts.fold<int>(0, (sum, part) => sum + part.size);
    if (!destination.capabilities.boundedUpload && total > 64 * 1024 * 1024) {
      throw UnsupportedError(
        'This storage cannot stream a combined file of this size. Choose a local destination.',
      );
    }
    if (source.identity == destination.identity &&
        files.any((file) => source.samePath(file.path!, outputPath))) {
      throw StateError('The output cannot replace an input part.');
    }
    final before = <FileItem>[];
    for (var index = 0; index < files.length; index++) {
      final current = await requireIntegrityFile(
        source,
        files[index],
        isCancelled: isCancelled,
      );
      if (current.size != parts[index].size ||
          await hashIntegrityFile(
                source,
                current,
                ChecksumAlgorithm.sha256,
                isCancelled: isCancelled,
                onProgress: (bytes, _) => onProgress?.call(
                  'Verifying part ${index + 1} of ${files.length}',
                  bytes,
                  parts[index].size,
                ),
              ) !=
              parts[index].sha256) {
        throw StateError('Part ${index + 1} is missing, truncated or corrupt.');
      }
      before.add(current);
    }
    final whole = ChecksumAccumulator(ChecksumAlgorithm.sha256);
    var written = 0;
    String? combinedHash;
    void check() {
      checkIntegrityCurrent(source, isCancelled);
      checkIntegrityCurrent(destination, isCancelled);
    }

    Stream<List<int>> joined() async* {
      for (var index = 0; index < before.length; index++) {
        check();
        final hash = ChecksumAccumulator(ChecksumAlgorithm.sha256);
        var count = 0;
        await for (final chunk in source.readFile(before[index])) {
          check();
          count += chunk.length;
          written += chunk.length;
          if (count > parts[index].size) {
            throw StateError('Part ${index + 1} grew during combination.');
          }
          hash.add(chunk);
          whole.add(chunk);
          onProgress?.call(
            'Combining part ${index + 1} of ${files.length}',
            written,
            total,
          );
          yield chunk;
        }
        final after = await source.stat(before[index].path!);
        if (after == null ||
            !sameIntegrityVersion(before[index], after) ||
            count != parts[index].size ||
            hash.finish() != parts[index].sha256) {
          throw StateError('Part ${index + 1} changed during combination.');
        }
      }
      check();
      combinedHash = whole.finish();
      if (expectedWhole != null && combinedHash != expectedWhole) {
        throw StateError(
          'The combined file does not match the original checksum.',
        );
      }
    }

    await destination.writePreparedFile(
      outputPath,
      joined(),
      total,
      replace: false,
      verifyStaged: (staged) async {
        check();
        if (written != total ||
            combinedHash == null ||
            await hashIntegrityFile(
                  destination,
                  staged,
                  ChecksumAlgorithm.sha256,
                  isCancelled: isCancelled,
                ) !=
                combinedHash) {
          throw StateError('The combined output failed verification.');
        }
        check();
      },
    );
    check();
    onProgress?.call('Combined file verified', total, total);
    return outputPath;
  }

  static Future<List<String>> splitFile(
    String sourcePath,
    String targetDir, {
    required int chunkSizeBytes,
    bool Function()? isCancelled,
    void Function(int bytesWritten, int totalBytes)? onProgress,
  }) async {
    final backend = _local();
    return (await splitToBackend(
      source: backend,
      file: _file(sourcePath),
      destination: backend,
      targetDirectory: targetDir,
      chunkSizeBytes: chunkSizeBytes,
      isCancelled: isCancelled,
      onProgress: (_, bytes, total) => onProgress?.call(bytes, total),
    )).partPaths;
  }

  static Future<String> combineFiles(
    List<String> partPaths,
    String outputPath, {
    bool allowUnverifiedLegacy = false,
    bool Function()? isCancelled,
    void Function(int partsDone, int totalParts)? onProgress,
  }) async {
    final backend = _local();
    final files = orderedLegacyParts(backend, partPaths.map(_file).toList());
    final first = files.first.path!;
    final prefix = first.replaceFirst(
      RegExp(r'\.(?:part)?\d{3,}$', caseSensitive: false),
      '',
    );
    final manifest = await backend.stat('$prefix.split.json');
    if (manifest != null) {
      final content = await readManifest(
        backend,
        manifest,
        isCancelled: isCancelled,
      );
      final expected = content.parts
          .map(
            (part) => resolveIntegrityPath(
              backend,
              backend.paths.dirname(manifest.path!),
              part.path,
            ),
          )
          .toSet();
      if (expected.length != files.length ||
          files.any((file) => !expected.contains(file.path))) {
        throw StateError(
          'The supplied parts do not match the complete manifest.',
        );
      }
      final result = await combineFromManifest(
        source: backend,
        manifestFile: manifest,
        destination: backend,
        outputPath: outputPath,
        isCancelled: isCancelled,
      );
      onProgress?.call(files.length, files.length);
      return result;
    }
    final result = await combineLegacy(
      source: backend,
      files: files,
      destination: backend,
      outputPath: outputPath,
      allowUnverifiedLegacy: allowUnverifiedLegacy,
      isCancelled: isCancelled,
    );
    onProgress?.call(files.length, files.length);
    return result;
  }

  static List<String> detectParts(String dirPath, String baseName) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return [];
    final pattern = RegExp(
      '^${RegExp.escape(baseName)}\\.(?:part)?(\\d{3,})\$',
      caseSensitive: false,
    );
    final parts = <MapEntry<int, String>>[];
    for (final entity in dir.listSync(followLinks: false)) {
      if (entity is! File) continue;
      final match = pattern.firstMatch(p.basename(entity.path));
      if (match != null) parts.add(MapEntry(int.parse(match[1]!), entity.path));
    }
    parts.sort((a, b) => a.key.compareTo(b.key));
    return parts.map((entry) => entry.value).toList();
  }
}
