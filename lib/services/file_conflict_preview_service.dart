import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../models/file_item.dart';
import 'file_operation_service.dart';

enum FileConflictPreviewProblem {
  unsupported,
  unsupportedStorage,
  tooLarge,
  dimensionsTooLarge,
  invalidImage,
  sourceUnavailable,
  sourceChanged,
  unavailable,
  timedOut,
  cancelled,
}

class FileConflictPreviewException implements Exception {
  const FileConflictPreviewException(this.problem);
  final FileConflictPreviewProblem problem;

  @override
  String toString() => 'File conflict preview: ${problem.name}';
}

/// Only scalar fields useful for file review are copied. Provider credentials,
/// download URLs, encryption keys and arbitrary nested maps are never exposed.
const _reviewMetadataKeys = {
  'mimeType',
  'contentType',
  'storageClass',
  'version',
  'versionId',
  'eTag',
  'etag',
  'rev',
  'cTag',
  'md5Hash',
  'sha1Hash',
  'sha256Hash',
  'contentHash',
  'createdAt',
  'createdTime',
  'creationTime',
};

Map<String, Object> _reviewMetadata(FileItem file) {
  final outer = file.metadata ?? const <String, dynamic>{};
  final inner = outer['metadata'];
  final result = <String, Object>{};
  for (final key in _reviewMetadataKeys) {
    final value = outer[key] ?? (inner is Map ? inner[key] : null);
    if (value is String || value is num || value is bool || value is DateTime) {
      result[key] = value as Object;
    }
  }
  return Map.unmodifiable(result);
}

FileItem _snapshot(FileItem file, String? path) => FileItem(
  name: file.name,
  path: path,
  uuid: file.uuid,
  storageId: file.storageId,
  isFolder: file.isFolder,
  size: file.size,
  updatedAt: file.updatedAt,
  xFile: file.xFile,
  metadata: _reviewMetadata(file),
  isSymlink: file.isSymlink,
  symlinkTarget: file.symlinkTarget,
  calculatedSize: file.calculatedSize,
);

/// One file, path and storage session captured when the conflict opens. No
/// subsequent pane lookup or path-only cache can redirect a preview.
class FileConflictPreviewTarget {
  FileConflictPreviewTarget(this.backend, FileItem file, {String? path})
    : identity = backend.identity,
      file = _snapshot(file, path ?? file.path),
      storageLabel = backend.label;

  final FileOperationBackend backend;
  final Object identity;
  final FileItem file;
  final String storageLabel;

  bool get isCurrent => backend.isCurrent && backend.identity == identity;

  void checkCurrent() {
    if (!isCurrent) {
      throw const FileConflictPreviewException(
        FileConflictPreviewProblem.sourceUnavailable,
      );
    }
  }

  Future<FileItem> verifyCurrent({
    FileItem? expected,
    FileOperationControl? control,
  }) async {
    checkCurrent();
    if (control?.isCancelled ?? false) {
      throw const FileOperationCancelled();
    }
    final path = file.path;
    if (path == null || !backend.paths.isAbsolute(path)) {
      throw const FileConflictPreviewException(
        FileConflictPreviewProblem.unavailable,
      );
    }
    final pending = backend.stat(path);
    final current = control == null
        ? await pending
        : await control.bind(Stream.fromFuture(pending)).first;
    checkCurrent();
    if (current == null ||
        current.path == null ||
        !backend.samePath(path, current.path!) ||
        !_sameVersion(file, current) ||
        (expected != null && !_sameVersion(expected, current))) {
      throw const FileConflictPreviewException(
        FileConflictPreviewProblem.sourceChanged,
      );
    }
    return _snapshot(current, path);
  }

  static bool _sameVersion(FileItem before, FileItem after) {
    if (before.isFolder != after.isFolder ||
        (before.isSymlink == true) != (after.isSymlink == true) ||
        before.symlinkTarget != after.symlinkTarget ||
        (before.uuid != null && before.uuid != after.uuid) ||
        (before.size != null && before.size != after.size) ||
        (before.updatedAt != null &&
            (after.updatedAt == null ||
                !before.updatedAt!.isAtSameMomentAs(after.updatedAt!)))) {
      return false;
    }
    final oldMetadata = _reviewMetadata(before);
    final newMetadata = _reviewMetadata(after);
    for (final key in [
      'version',
      'versionId',
      'eTag',
      'etag',
      'rev',
      'cTag',
      'md5Hash',
      'sha1Hash',
      'sha256Hash',
      'contentHash',
    ]) {
      if (oldMetadata[key] != null && oldMetadata[key] != newMetadata[key]) {
        return false;
      }
    }
    return true;
  }
}

class FileConflictImagePreview {
  const FileConflictImagePreview({
    required this.png,
    required this.width,
    required this.height,
    required this.animated,
  });

  final Uint8List png;
  final int width;
  final int height;
  final bool animated;
}

/// Ephemeral, read-only previews. No thumbnail disk cache or provider URL is
/// used. The caller owns cancellation and must discard late dialog results.
class FileConflictPreviewService {
  const FileConflictPreviewService();

  static const maxInputBytes = 4 * 1024 * 1024;
  static const maxPixels = 16000000;
  static const maxDimension = 8192;
  static const maxThumbnailDimension = 384;
  static const maxThumbnailBytes = 1024 * 1024;
  static const defaultTimeout = Duration(seconds: 15);

  static const _extensions = {
    'png',
    'jpg',
    'jpeg',
    'jpe',
    'gif',
    'webp',
    'bmp',
    'ico',
    'heic',
    'heif',
    'avif',
    'tif',
    'tiff',
  };
  static const _mediaTypes = {
    'image/png',
    'image/jpeg',
    'image/gif',
    'image/webp',
    'image/bmp',
    'image/x-icon',
    'image/vnd.microsoft.icon',
    'image/heic',
    'image/heif',
    'image/avif',
    'image/tiff',
  };

  static bool supports(FileItem file) {
    if (file.isFolder || file.isSymlink == true) return false;
    if (_extensions.contains(file.extension)) return true;
    final metadata = _reviewMetadata(file);
    final type = metadata['mimeType'] ?? metadata['contentType'];
    return type is String &&
        _mediaTypes.contains(type.split(';').first.trim().toLowerCase());
  }

  Future<FileConflictImagePreview> load(
    FileConflictPreviewTarget target, {
    FileOperationControl? control,
    Duration timeout = defaultTimeout,
  }) async {
    final request = control ?? FileOperationControl();
    var timedOut = false;
    final timer = Timer(timeout, () {
      timedOut = true;
      request.cancel();
    });
    void check() {
      if (request.isCancelled) throw const FileOperationCancelled();
      target.checkCurrent();
    }

    try {
      check();
      if (!supports(target.file)) {
        throw const FileConflictPreviewException(
          FileConflictPreviewProblem.unsupported,
        );
      }
      if ((target.file.size ?? 0) > maxInputBytes) {
        throw const FileConflictPreviewException(
          FileConflictPreviewProblem.tooLarge,
        );
      }
      // A collector cannot bound memory already buffered by an adapter before
      // it emits its first chunk. Automatic previews require that capability.
      if (!target.backend.capabilities.boundedDownload) {
        throw const FileConflictPreviewException(
          FileConflictPreviewProblem.unsupportedStorage,
        );
      }
      final before = await target.verifyCurrent(control: request);
      if (before.isSymlink == true || before.isFolder) {
        throw const FileConflictPreviewException(
          FileConflictPreviewProblem.unsupported,
        );
      }
      if ((before.size ?? 0) > maxInputBytes) {
        throw const FileConflictPreviewException(
          FileConflictPreviewProblem.tooLarge,
        );
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in request.bind(target.backend.readFile(before))) {
        check();
        if (bytes.length + chunk.length > maxInputBytes) {
          throw const FileConflictPreviewException(
            FileConflictPreviewProblem.tooLarge,
          );
        }
        if (before.size != null && bytes.length + chunk.length > before.size!) {
          throw const FileConflictPreviewException(
            FileConflictPreviewProblem.sourceChanged,
          );
        }
        // Providers may reuse a read buffer after the next event.
        bytes.add(Uint8List.fromList(chunk));
      }
      check();
      if (before.size != null && before.size != bytes.length) {
        throw const FileConflictPreviewException(
          FileConflictPreviewProblem.sourceChanged,
        );
      }
      await target.verifyCurrent(expected: before, control: request);
      final preview = await request
          .bind(Stream.fromFuture(_decode(bytes.takeBytes(), check)))
          .first;
      check();
      await target.verifyCurrent(expected: before, control: request);
      check();
      return preview;
    } on FileOperationCancelled {
      throw FileConflictPreviewException(
        timedOut
            ? FileConflictPreviewProblem.timedOut
            : FileConflictPreviewProblem.cancelled,
      );
    } on FileConflictPreviewException {
      rethrow;
    } catch (_) {
      // Provider exceptions may contain URLs or credentials. They are not UI
      // metadata, and must not be copied into a conflict preview or its logs.
      throw const FileConflictPreviewException(
        FileConflictPreviewProblem.unavailable,
      );
    } finally {
      timer.cancel();
    }
  }

  Future<FileConflictImagePreview> _decode(
    Uint8List bytes,
    void Function() check,
  ) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      check();
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      check();
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      check();
      final width = descriptor.width;
      final height = descriptor.height;
      if (width < 1 ||
          height < 1 ||
          width > maxDimension ||
          height > maxDimension ||
          width * height > maxPixels) {
        throw const FileConflictPreviewException(
          FileConflictPreviewProblem.dimensionsTooLarge,
        );
      }
      final scale = math.min(
        1.0,
        maxThumbnailDimension / math.max(width, height),
      );
      codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (width * scale).round()),
        targetHeight: math.max(1, (height * scale).round()),
      );
      check();
      image = (await codec.getNextFrame()).image;
      check();
      if (image.width > maxThumbnailDimension ||
          image.height > maxThumbnailDimension) {
        throw const FileConflictPreviewException(
          FileConflictPreviewProblem.dimensionsTooLarge,
        );
      }
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      check();
      if (data == null || data.lengthInBytes > maxThumbnailBytes) {
        throw const FileConflictPreviewException(
          FileConflictPreviewProblem.invalidImage,
        );
      }
      return FileConflictImagePreview(
        png: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        width: width,
        height: height,
        animated: codec.frameCount > 1,
      );
    } on FileOperationCancelled {
      rethrow;
    } on FileConflictPreviewException {
      rethrow;
    } catch (_) {
      throw const FileConflictPreviewException(
        FileConflictPreviewProblem.invalidImage,
      );
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }
}

/// Allowlisted display details beyond size/time/type. Keys are localization
/// identifiers, values are bounded plain text; no arbitrary metadata is dumped.
Map<String, String> fileConflictReviewDetails(FileItem file) {
  final metadata = _reviewMetadata(file);
  final result = <String, String>{};
  void add(String label, Object? value, {String prefix = ''}) {
    if (value == null) return;
    final raw = value is DateTime ? value.toUtc().toIso8601String() : '$value';
    final bounded = raw.length > 160 ? '${raw.substring(0, 160)}…' : raw;
    final clean = bounded.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ').trim();
    if (clean.isNotEmpty) {
      result[label] = '$prefix$clean';
    }
  }

  add('Content type', metadata['mimeType'] ?? metadata['contentType']);
  add('Storage class', metadata['storageClass']);
  add('Object ID', file.uuid);
  for (final key in ['version', 'versionId', 'eTag', 'etag', 'rev', 'cTag']) {
    if (metadata[key] != null) {
      add('Version', metadata[key]);
      break;
    }
  }
  for (final (key, algorithm) in [
    ('md5Hash', 'MD5'),
    ('sha1Hash', 'SHA-1'),
    ('sha256Hash', 'SHA-256'),
    ('contentHash', ''),
  ]) {
    if (metadata[key] != null) {
      add(
        'Reported checksum',
        metadata[key],
        prefix: algorithm.isEmpty ? '' : '$algorithm ',
      );
      break;
    }
  }
  add(
    'Created',
    metadata['createdAt'] ??
        metadata['createdTime'] ??
        metadata['creationTime'],
  );
  return Map.unmodifiable(result);
}
