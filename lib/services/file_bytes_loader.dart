// lib/services/file_bytes_loader.dart
//
// Shared byte-loading used by the PreviewPane and the F3 internal viewer.
// Local non-web files are streamed from disk, web-local files go through the
// LocalFileService (FileSystem Access API), and remote files are downloaded
// with the file cache as a first stop.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import 'file_operation_backend.dart';
import 'file_operation_service.dart';
import 'panel_source_service.dart';
import './log_service.dart';

/// App-authored byte-loading failures that can be localized at the UI boundary.
enum FileBytesErrorCode { tooLarge, notFound, couldNotRead, accessDenied }

/// Something went wrong loading bytes for preview.
class FileBytesLoadException implements Exception {
  final String message;
  final FileBytesErrorCode? code;
  final Map<String, Object> arguments;
  const FileBytesLoadException(this.message, {this.code, this.arguments = const {}});

  @override
  String toString() => message;
}

/// Thrown when the file exceeds an explicit caller-provided size cap.
class FileBytesTooLargeException extends FileBytesLoadException {
  FileBytesTooLargeException(int size, int cap)
    : super('File is ${_fmt(size)} — larger than the ${_fmt(cap)} view limit.');

  static String _fmt(int b) => b >= 1024 * 1024 * 1024
      ? '${(b / 1024 / 1024 / 1024).toStringAsFixed(1)} GB'
      : b >= 1024 * 1024
      ? '${(b / 1024 / 1024).toStringAsFixed(1)} MB'
      : '${(b / 1024).toStringAsFixed(0)} KB';
}

const _log = Log('FileBytesLoader');

/// Load the complete bytes of [file] for previewing.
///
/// Throws [FileBytesTooLargeException] when [capBytes] is set and exceeded,
/// and [FileBytesLoadException] for IO/download errors.
Future<Uint8List> loadFileBytes(
  WidgetRef ref,
  FileItem file,
  PanelSide side, {
  int? capBytes,
  PanelFileOrigin? origin,
}) async {
  final captured =
      origin ?? ref.read(panelProvider(side)).originForOperation(file);
  if (captured == null || !captured.isCurrent) {
    throw const FileBytesLoadException(
      'The original file source is unavailable. Refresh or reopen the file.',
    );
  }
  final source = captured.source;
  final local = ref.read(localFileServiceProvider);
  final backend = fileOperationBackend(
    source: source,
    local: local,
    isCurrent: () => captured.isCurrent,
  );
  final path = file.path ?? backend.paths.join(source.currentPath, file.name);
  final limit = capBytes ?? 64 * 1024 * 1024;
  if (limit <= 0) throw ArgumentError.value(limit, 'capBytes');
  if (file.size != null) _assertCap(file.size!, limit);

  Future<Uint8List> read() async {
    final current = await backend.stat(path);
    if (current == null || current.isFolder) {
      throw FileBytesLoadException('File not found: $path');
    }
    if (file.uuid != null && current.uuid != file.uuid) {
      throw const FileBytesLoadException(
        'A different item now occupies this path. Refresh or reopen it.',
      );
    }
    if (current.size != null) _assertCap(current.size!, limit);
    // Only provider versions can safely identify reusable preview bytes.
    // Unversioned files are read afresh, including same-size external edits.
    final version =
        current.metadata?['etag'] ??
        current.metadata?['versionId'] ??
        current.metadata?['revision'];
    final cacheScope =
        '${captured.storageId}:view:${current.uuid ?? path}:$version';
    final cache = ref.read(fileCacheProvider);
    if (source is RemotePanelSource && version != null) {
      final cached = await cache.get(path, cacheScope);
      if (!captured.isCurrent) {
        throw const FileBytesLoadException(
          'The account disconnected while reading.',
        );
      }
      if (cached != null) {
        _assertCap(cached.length, limit);
        return Uint8List.fromList(cached);
      }
    }
    final bytes = await readFileBytesBounded(backend, current, maxBytes: limit);
    if (source is RemotePanelSource && version != null) {
      unawaited(() async {
        try {
          await cache.put(path, cacheScope, bytes);
        } catch (error, stack) {
          _log.warn('cache put failed (non-fatal)', error, stack);
        }
      }());
    }
    return bytes;
  }

  try {
    return await read();
  } on FileSystemException catch (error) {
    if (source is! LocalPanelSource || kIsWeb || !_isPermissionDenied(error)) {
      throw FileBytesLoadException('Could not read "$path": ${error.message}');
    }
    if (!await local.ensureAccess(path)) {
      throw FileBytesLoadException('Access to "$path" was not granted.');
    }
    return read();
  }
}

/// Bounded reads shared by previews; the iterator is cancelled on overflow.
Future<Uint8List> readFileBytesBounded(
  FileOperationBackend backend,
  FileItem file, {
  required int maxBytes,
  bool Function()? isCancelled,
}) async {
  if (maxBytes <= 0) throw ArgumentError.value(maxBytes, 'maxBytes');
  if (file.size != null) _assertCap(file.size!, maxBytes);
  final bytes = BytesBuilder(copy: false);
  void check() {
    if (!backend.isCurrent) {
      throw const FileBytesLoadException(
        'The account disconnected while reading.',
      );
    }
    if (isCancelled?.call() ?? false) {
      throw const FileBytesLoadException('File read cancelled.');
    }
  }

  check();
  await for (final chunk in backend.readFile(file)) {
    check();
    _assertCap(bytes.length + chunk.length, maxBytes);
    bytes.add(chunk);
  }
  check();
  return bytes.takeBytes();
}

bool _isPermissionDenied(FileSystemException error) {
  if (error is PathAccessException) return true;
  final code = error.osError?.errorCode;
  return code == 1 || code == 13;
}

void _assertCap(int size, int? capBytes) {
  if (capBytes != null && size > capBytes) {
    throw FileBytesTooLargeException(size, capBytes);
  }
}

/// Sync-capable byte source over a local file or in-memory data.
///
/// The hex/ASCII/binary viewer modes use this so that arbitrarily large local
/// files can be viewed without loading them fully into memory (web has no
/// RandomAccessFile, so streams are only supported for native platforms –
/// callers pass in-memory data for web/remote files).
class ViewBytesSource {
  final File? _file;
  RandomAccessFile? _raf;
  final Uint8List? _memory;
  bool _disposed = false;
  bool _opened = false;
  FileStat? _snapshot;

  final Future<void> Function()? _acquireAccess;
  final Future<void> Function()? _releaseAccess;

  ViewBytesSource.memory(Uint8List data)
    : _memory = data,
      _file = null,
      _acquireAccess = null,
      _releaseAccess = null;

  ViewBytesSource.file(
    String path, {
    Future<void> Function()? acquireAccess,
    Future<void> Function()? releaseAccess,
  }) : _file = File(path),
       _memory = null,
       _acquireAccess = acquireAccess,
       _releaseAccess = releaseAccess;

  static const _windowSize = 256 * 1024;
  Uint8List? _window;
  int _windowStart = 0;

  /// Total byte size of the underlying data.
  int size = 0;

  /// True when lazily streamed from disk.
  bool get isStreamed => _file != null;

  String get path => _file?.path ?? '';

  /// Open latent resources and stat the data. Safe to call more than once.
  Future<void> open() async {
    if (_disposed) throw StateError('ViewBytesSource already disposed');
    if (_opened) return;
    _opened = true;
    final mem = _memory;
    if (mem != null) {
      size = mem.length;
      return;
    }
    // Acquire the security scope (macOS) before opening the RandomAccessFile.
    final acquire = _acquireAccess;
    if (acquire != null) await acquire();
    final f = _file!;
    _snapshot = await f.stat();
    size = _snapshot!.size;
    _raf = await f.open();
    await validateUnchanged();
  }

  /// Searches must not present an early hit as a verified result if the file
  /// was replaced, truncated or edited before the scan reached its end.
  Future<void> validateUnchanged() async {
    if (_disposed) throw StateError('ViewBytesSource already disposed');
    final before = _snapshot;
    if (before == null) return;
    final after = await _file!.stat();
    if (before.type != after.type ||
        before.size != after.size ||
        before.modified != after.modified ||
        before.changed != after.changed) {
      throw FileSystemException(
        'The viewed file changed; reload it before searching.',
        path,
      );
    }
  }

  /// Read [length] bytes at [offset] (clamped to the available range).
  Uint8List readSync(int offset, int length) {
    if (_disposed) throw StateError('ViewBytesSource already disposed');
    final end = (offset + length).clamp(0, size);
    final start = offset < 0 ? 0 : offset;
    if (end <= start) return Uint8List(0);

    if (_memory != null) {
      return Uint8List.sublistView(_memory, start, end);
    }

    // Streaming window cache for random access files.
    if (_window != null &&
        start >= _windowStart &&
        end <= _windowStart + _window!.length) {
      return Uint8List.sublistView(
        _window!,
        start - _windowStart,
        end - _windowStart,
      );
    }

    final raf = _raf;
    if (raf == null) return Uint8List(0);

    // Load a window around the requested slice.
    final wStart = start;
    // Callers also index/search in chunks larger than the scroll cache. The
    // window must cover the entire requested slice, not just its first 256 KiB.
    var wLen = end - start > _windowSize ? end - start : _windowSize;
    if (wStart + wLen > size) wLen = size - wStart;
    if (wLen <= 0) return Uint8List(0);
    raf.setPositionSync(wStart);
    final window = raf.readSync(wLen);
    if (window.length < end - start) {
      throw FileSystemException(
        'The viewed file became shorter while reading.',
        path,
      );
    }
    _window = window;
    _windowStart = wStart;
    return Uint8List.sublistView(window, start - wStart, end - wStart);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    try {
      _raf?.closeSync();
    } catch (_) {
      // Best effort.
    }
    _raf = null;
    final release = _releaseAccess;
    if (release != null) unawaited(release());
  }
}
