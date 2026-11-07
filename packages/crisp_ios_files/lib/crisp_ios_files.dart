/// Native iOS document-provider access. Every lease is separately owned;
/// closing one reader cannot release another reader or terminal's grant.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Rejects relative paths before they cross the native permission boundary.
String normalizeIosFilePath(String path) {
  if (!p.posix.isAbsolute(path) || path.contains('\u0000')) {
    throw ArgumentError.value(path, 'path', 'Expected an absolute iOS path.');
  }
  return p.posix.normalize(path);
}

/// A native security-scope reference held until [release] completes.
/// A failed transport call can be retried; native release is idempotent.
class IosAccessLease {
  IosAccessLease._(this.path, this.token, this._release);

  final String path;
  final String token;
  final Future<void> Function(String token) _release;
  Future<void>? _releaseFuture;
  bool _released = false;

  Future<void> release() {
    if (_released) return Future<void>.value();
    return _releaseFuture ??= _releaseOnce();
  }

  Future<void> _releaseOnce() async {
    try {
      await _release(token);
      _released = true;
    } catch (_) {
      _releaseFuture = null;
      rethrow;
    }
  }
}

/// Metadata returned while the provider's read coordination is held.
class IosFileEntry {
  const IosFileEntry({
    required this.path,
    required this.kind,
    required this.size,
    required this.modifiedAt,
  });

  factory IosFileEntry.fromMap(Map<Object?, Object?> map) {
    final path = map['path'];
    final kind = map['kind'];
    final size = map['size'];
    final modified = map['modifiedMs'];
    if (path is! String ||
        !const {'file', 'directory', 'link'}.contains(kind) ||
        size is! num ||
        modified is! num) {
      throw const FormatException('Invalid native iOS file metadata.');
    }
    return IosFileEntry(
      path: normalizeIosFilePath(path),
      kind: kind! as String,
      size: size.toInt(),
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(modified.toInt()),
    );
  }

  final String path;
  final String kind;
  final int size;
  final DateTime modifiedAt;
}

/// The native backend persists bookmarks; Dart never serializes a raw path as
/// proof of access. File operations use NSFileCoordinator in native code.
class IosFilesClient {
  IosFilesClient({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('crisp_ios_files');

  final MethodChannel _channel;

  Future<String?> pickDirectory({String? initialDirectory}) async {
    final result = await _channel.invokeMethod<String>('pickDirectory', {
      if (initialDirectory != null)
        'initialDirectory': normalizeIosFilePath(initialDirectory),
    });
    return result == null ? null : normalizeIosFilePath(result);
  }

  Future<String?> restoreLastDirectory() async {
    final result = await _channel.invokeMethod<String>('restoreLastDirectory');
    return result == null ? null : normalizeIosFilePath(result);
  }

  Future<IosAccessLease> acquireAccess(String path) async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'acquireAccess',
      {'path': normalizeIosFilePath(path)},
    );
    final token = result?['token'];
    if (token is! String || token.isEmpty) {
      throw const FormatException(
        'The native iOS scope token was not returned.',
      );
    }
    try {
      final resolvedPath = result?['path'];
      if (resolvedPath is! String) {
        throw const FormatException(
          'The native iOS scope path was not returned.',
        );
      }
      return IosAccessLease._(
        normalizeIosFilePath(resolvedPath),
        token,
        (value) =>
            _channel.invokeMethod<void>('releaseAccess', {'token': value}),
      );
    } catch (_) {
      // A bad response must not strand an otherwise valid native lease.
      try {
        await _channel.invokeMethod<void>('releaseAccess', {'token': token});
      } catch (error) {
        debugPrint('Could not release malformed iOS scope: $error');
      }
      rethrow;
    }
  }

  /// Retains a scope for arbitrary native-path work, including a terminal's
  /// lifetime. This deliberately does not hold a provider-wide file lock.
  Future<T> withAccess<T>(
    String path,
    Future<T> Function(String accessiblePath) operation,
  ) async {
    final lease = await acquireAccess(path);
    try {
      return await operation(lease.path);
    } finally {
      // A transport failure while releasing must not report a completed write
      // as failed and encourage a duplicate upload. Native detach also drains
      // all outstanding leases.
      try {
        await lease.release();
      } catch (_) {
        // Retry a transport failure once. Native release is idempotent even
        // when the first response was lost after the native stop succeeded.
        try {
          await lease.release();
        } catch (error) {
          debugPrint('Could not release iOS file access: $error');
        }
      }
    }
  }

  Future<bool> hasAccess(String path) async =>
      await _channel.invokeMethod<bool>('hasAccess', {
        'path': normalizeIosFilePath(path),
      }) ??
      false;

  Future<List<IosFileEntry>> listDirectory(String path) =>
      _entries('listDirectory', {'path': normalizeIosFilePath(path)});

  Future<List<IosFileEntry>> walkFiles(
    String path, {
    bool includeHidden = false,
    int maxItems = 10000,
  }) {
    if (maxItems < 0) throw ArgumentError.value(maxItems, 'maxItems');
    return _entries('walkFiles', {
      'path': normalizeIosFilePath(path),
      'includeHidden': includeHidden,
      'maxItems': maxItems,
    });
  }

  Future<List<IosFileEntry>> _entries(
    String method,
    Map<String, Object> args,
  ) async {
    final result = await _channel.invokeListMethod<Object?>(method, args);
    if (result == null) {
      throw const FormatException('The native iOS listing was not returned.');
    }
    return result
        .map((entry) {
          if (entry is! Map) {
            throw const FormatException('Invalid native iOS listing entry.');
          }
          return IosFileEntry.fromMap(entry.cast<Object?, Object?>());
        })
        .toList(growable: false);
  }

  Future<Uint8List> readFile(String path) async {
    final result = await _channel.invokeMethod<Uint8List>('readFile', {
      'path': normalizeIosFilePath(path),
    });
    if (result == null) {
      throw const FormatException(
        'The native iOS file contents were not returned.',
      );
    }
    return result;
  }

  Future<void> writeFile(
    String path,
    Uint8List bytes, {
    bool overwrite = true,
  }) => _channel.invokeMethod<void>('writeFile', {
    'path': normalizeIosFilePath(path),
    'bytes': bytes,
    'overwrite': overwrite,
  });

  Future<void> createDirectory(String path) => _channel.invokeMethod<void>(
    'createDirectory',
    {'path': normalizeIosFilePath(path)},
  );

  Future<void> deleteEntry(String path, {required bool isFolder}) =>
      _channel.invokeMethod<void>('deleteEntry', {
        'path': normalizeIosFilePath(path),
        'isFolder': isFolder,
      });

  Future<int?> fileLength(String path) => _channel.invokeMethod<int>(
    'fileLength',
    {'path': normalizeIosFilePath(path)},
  );
}
