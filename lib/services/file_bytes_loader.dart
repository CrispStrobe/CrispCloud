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
import './log_service.dart';

/// Something went wrong loading bytes for preview.
class FileBytesLoadException implements Exception {
  final String message;
  const FileBytesLoadException(this.message);

  @override
  String toString() => message;
}

/// Thrown when the file exceeds an explicit caller-provided size cap.
class FileBytesTooLargeException extends FileBytesLoadException {
  FileBytesTooLargeException(int size, int cap)
      : super(
            'File is ${_fmt(size)} — larger than the ${_fmt(cap)} view limit.');

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
}) async {
  // Local panel: read through the platform service so macOS security-scoped
  // bookmarks are honoured.
  if (side == PanelSide.local && file.path != null) {
    final localSvc = ref.read(localFileServiceProvider);
    final path = file.path!;

    // Prefer the listing size to avoid loading an oversized file just to
    // reject it.
    if (capBytes != null && file.size != null) {
      _assertCap(file.size!, capBytes);
    }

    try {
      final bytes = await localSvc.readFile(path, fileItem: file);
      _assertCap(bytes.length, capBytes);
      return bytes;
    } on PathNotFoundException {
      throw FileBytesLoadException('File not found: $path');
    } on FileSystemException catch (e) {
      if (kIsWeb || !_isPermissionDenied(e)) {
        throw FileBytesLoadException('Could not read "$path": ${e.message}');
      }
      // Sandbox denial: ask the user to grant the containing folder, save the
      // bookmark, then retry once.
      final granted = await localSvc.ensureAccess(path);
      if (!granted) {
        throw FileBytesLoadException(
          'Access to "$path" was not granted. Grant access to its folder '
          'and try again.',
        );
      }
      final bytes = await localSvc.readFile(path, fileItem: file);
      _assertCap(bytes.length, capBytes);
      return bytes;
    }
  }

  // Remote panel: cache first, then download.
  final auth = ref.read(authProvider);
  final client = auth.client;
  final remotePath = file.path ?? '/${file.name}';
  final providerName = auth.providerName;
  final cache = ref.read(fileCacheProvider);

  // Refuse oversized files before downloading when the listing has a size.
  if (capBytes != null && file.size != null && file.size! > capBytes) {
    throw FileBytesTooLargeException(file.size!, capBytes);
  }

  final cached = await cache.get(remotePath, providerName);
  if (cached != null) {
    _assertCap(cached.length, capBytes);
    return Uint8List.fromList(cached);
  }

  final bytes = await client.downloadFileBytes(remotePath);
  _assertCap(bytes.length, capBytes);

  // Cache for offline access (fire-and-forget: never delay the preview).
  unawaited(() async {
    try {
      await cache.put(remotePath, providerName, bytes);
    } catch (e, st) {
      _log.warn('cache put failed (non-fatal)', e, st);
    }
  }());
  return bytes;
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
  })  : _file = File(path),
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
    size = await f.length();
    _raf = await f.open();
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
          _window!, start - _windowStart, end - _windowStart);
    }

    final raf = _raf;
    if (raf == null) return Uint8List(0);

    // Load a window around the requested slice.
    final wStart = start;
    var wLen = _windowSize;
    if (wStart + wLen > size) wLen = size - wStart;
    if (wLen <= 0) return Uint8List(0);
    raf.setPositionSync(wStart);
    final window = raf.readSync(wLen);
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
