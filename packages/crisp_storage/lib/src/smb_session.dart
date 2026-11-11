import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:dart_smb2/dart_smb2.dart';
import 'download_state.dart';
import 'remote_client.dart';

/// SMB2/3 operations run in a worker isolate, never on the UI thread.
class SmbSession {
  final RemoteConnection connection;
  final _cancel = Smb2CancelToken();
  Future<Smb2Pool>? _opening;
  bool _closed = false;
  SmbSession(this.connection) {
    if (connection.kind != 'smb') {
      throw ArgumentError('Expected SMB connection');
    }
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    if (_closed)
      throw const RemoteException(
        'SMB connection closed.',
        code: RemoteErrorCode.closed,
        arguments: {'protocol': 'SMB'},
      );
    try {
      return await action();
    } on Smb2Exception catch (e) {
      throw RemoteException(
        e.isCancelled
            ? 'SMB transfer paused.'
            : e.isAuthError
            ? 'SMB sign-in failed. Check your username, domain and password.'
            : e.isNotFound
            ? 'SMB share or file was not found.'
            : 'SMB request failed (${e.type.name}). Check the share permissions, network and encryption setting.',
        retryable: e.isTransient,
        cause: e,
        code: e.isCancelled
            ? RemoteErrorCode.smbPaused
            : e.isAuthError
            ? RemoteErrorCode.smbAuth
            : e.isNotFound
            ? RemoteErrorCode.smbNotFound
            : RemoteErrorCode.smbRequest,
        arguments: {'type': e.type.name},
      );
    }
  }

  Future<Smb2Pool> _open() => _opening ??=
      _guard(() async {
        final user = connection.username;
        final split = user.indexOf(r'\');
        final pool = await Smb2Pool.connect(
          host: connection.url.hasPort
              ? connection.url.authority
              : connection.url.host,
          share: connection.url.pathSegments.first,
          user: split < 0 ? user : user.substring(split + 1),
          domain: split < 0 ? null : user.substring(0, split),
          password: connection.secret,
          workers: 1,
          timeout: const Duration(seconds: 15),
          signing: true,
          seal: connection.requireEncryption,
          version: connection.requireEncryption
              ? Smb2Version.any3
              : Smb2Version.any,
        );
        if (_closed) {
          await pool.disconnect();
          throw const RemoteException(
            'SMB connection closed.',
            code: RemoteErrorCode.closed,
            arguments: {'protocol': 'SMB'},
          );
        }
        return pool;
      }).catchError((Object error, StackTrace stack) {
        // Share an in-flight handshake, but do not cache a failed connection.
        // A later explicit operation may retry after the network recovers.
        _opening = null;
        Error.throwWithStackTrace(error, stack);
      });

  /// Convert a share-root-relative app path into a confined server URL.
  String urlForPath(String path) {
    final parts = path.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.any(
      (s) => s == '.' || s == '..' || s.contains(r'\') || s.contains('\u0000'),
    )) {
      throw const RemoteFormatException(
        'Invalid SMB path.',
        RemoteErrorCode.invalidPath,
        arguments: {'protocol': 'SMB'},
      );
    }
    return connection.url
        .replace(
          path: '${Uri.decodeComponent(connection.url.path)}${parts.join('/')}',
        )
        .toString();
  }

  String _path(String path) {
    final base = connection.url;
    final raw = Uri.parse(path);
    if (raw.pathSegments.any(
      (s) =>
          s == '.' ||
          s == '..' ||
          s.contains('/') ||
          s.contains(r'\') ||
          s.contains('\u0000'),
    )) {
      throw const RemoteException(
        'Invalid SMB path.',
        code: RemoteErrorCode.invalidPath,
        arguments: {'protocol': 'SMB'},
      );
    }
    final target = base.resolve(path.isEmpty ? base.toString() : path);
    final parts = target.pathSegments;
    if (target.scheme != base.scheme ||
        target.host != base.host ||
        target.port != base.port ||
        target.userInfo.isNotEmpty ||
        target.hasQuery ||
        target.hasFragment ||
        !target.path.startsWith(base.path) ||
        parts.any(
          (s) =>
              s == '.' ||
              s == '..' ||
              s.contains('/') ||
              s.contains(r'\') ||
              s.contains('\u0000'),
        )) {
      throw const RemoteException(
        'The SMB path is outside this connection’s root.',
        code: RemoteErrorCode.outsideRoot,
        arguments: {'protocol': 'SMB'},
      );
    }
    return parts.skip(1).where((s) => s.isNotEmpty).join('/');
  }

  Future<List<RemoteEntry>> browse(String path) => _guard(() async {
    final target = _path(path);
    final pool = await _open();
    final entries = await pool.listDirectory(target, cancelToken: _cancel);
    if (entries.length > 10000) {
      throw const RemoteException(
        'SMB folder is too large.',
        code: RemoteErrorCode.folderTooLarge,
        arguments: {'protocol': 'SMB'},
      );
    }
    final parent = connection.url.resolve(
      path.isEmpty ? connection.url.toString() : path,
    );
    final result = <RemoteEntry>[];
    for (final e in entries) {
      if ((!e.isFile && !e.isDirectory) ||
          e.name.isEmpty ||
          e.name == '.' ||
          e.name == '..' ||
          e.name.contains('/') ||
          e.name.contains(r'\') ||
          e.name.contains('\u0000')) {
        continue;
      }
      final uri = parent.replace(
        path:
            '${Uri.decodeComponent(parent.path).replaceFirst(RegExp(r'/*$'), '')}/${e.name}${e.isDirectory ? '/' : ''}',
      );
      _path(uri.toString());
      result.add(
        RemoteEntry(
          uri.toString(),
          e.name,
          e.isDirectory ? 'folder' : 'file',
          size: e.size,
        ),
      );
    }
    result.sort(
      (a, b) => a.type == b.type
          ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
          : a.type == 'folder'
          ? -1
          : 1,
    );
    return result;
  });

  Future<RemoteEntry?> stat(String path) => _guard(() async {
    final target = _path(path);
    final pool = await _open();
    try {
      final s = await pool.stat(target, cancelToken: _cancel);
      if (!s.isDirectory && !s.isFile) {
        throw const RemoteException(
          'SMB links are unsupported.',
          code: RemoteErrorCode.linksUnsupported,
          arguments: {'protocol': 'SMB'},
        );
      }
      return RemoteEntry(
        path,
        target.split('/').last,
        s.isDirectory ? 'folder' : 'file',
        size: s.size,
      );
    } on Smb2Exception catch (e) {
      if (e.isNotFound) return null;
      rethrow;
    }
  });

  Stream<List<int>> stream(
    String path, {
    void Function(int, int)? onProgress,
  }) async* {
    final target = _path(path);
    final pool = await _open();
    try {
      final before = await pool.stat(target, cancelToken: _cancel);
      if (!before.isFile)
        throw const RemoteException(
          'Choose an SMB file.',
          code: RemoteErrorCode.chooseFile,
          arguments: {'protocol': 'SMB'},
        );
      final handle = await pool.openFile(target, cancelToken: _cancel);
      try {
        var received = 0;
        while (received < before.size) {
          final bytes = await pool.readFromHandle(
            handle,
            offset: received,
            length: (before.size - received).clamp(0, 256 * 1024),
            cancelToken: _cancel,
          );
          if (bytes.isEmpty) {
            throw const RemoteException(
              'SMB download was incomplete.',
              code: RemoteErrorCode.incomplete,
              arguments: {'protocol': 'SMB'},
              retryable: true,
            );
          }
          received += bytes.length;
          onProgress?.call(received, before.size);
          yield bytes;
        }
        final after = await pool.stat(target, cancelToken: _cancel);
        if (before.size != after.size ||
            before.modified != after.modified ||
            before.changed != after.changed) {
          throw const RemoteException(
            'SMB file changed during download. Retry it.',
            code: RemoteErrorCode.fileChanged,
            arguments: {'protocol': 'SMB'},
          );
        }
      } finally {
        await pool.closeHandle(handle);
      }
    } on Smb2Exception catch (e) {
      throw RemoteException(
        'SMB download interrupted.',
        code: RemoteErrorCode.interrupted,
        arguments: {'protocol': 'SMB'},
        retryable: e.isTransient,
      );
    }
  }

  Future<void> download(
    String path,
    File output, {
    void Function(int)? onBytes,
    required int limit,
  }) => _guard(() async {
    final target = _path(path);
    final pool = await _open();
    final before = await pool.stat(target, cancelToken: _cancel);
    if (!before.isFile || before.size <= 0 || before.size > limit) {
      throw const RemoteException(
        'SMB file is empty, unsupported or exceeds the download limit.',
        code: RemoteErrorCode.invalidFile,
        arguments: {'protocol': 'SMB'},
      );
    }
    final validator =
        '${before.modified.microsecondsSinceEpoch}:${before.changed.microsecondsSinceEpoch}:${before.size}';
    final source = connection.url.resolve(path).toString();
    final saved = await DownloadState.read(output);
    var offset = await output.exists() ? await output.length() : 0;
    if (saved?.source != source ||
        saved?.validator != validator ||
        offset > before.size) {
      offset = 0;
    }
    final sink = await output.open(
      mode: offset > 0 ? FileMode.append : FileMode.write,
    );
    try {
      await DownloadState(source, validator, before.size).save(output);
      onBytes?.call(offset);
      await pool.withFile(
        target,
        (file) async {
          while (offset < before.size) {
            final length = (before.size - offset).clamp(0, 256 * 1024);
            if (_closed)
              throw const RemoteException(
                'SMB transfer paused.',
                code: RemoteErrorCode.paused,
                arguments: {'protocol': 'SMB'},
              );
            final bytes = await file.read(offset: offset, length: length);
            if (bytes.isEmpty) {
              throw const RemoteException(
                'SMB download was incomplete.',
                code: RemoteErrorCode.incomplete,
                arguments: {'protocol': 'SMB'},
                retryable: true,
              );
            }
            // Await the write itself for backpressure. An IOSink flush after
            // every chunk adds another asynchronous round trip; it is not an
            // fsync durability guarantee. Keep at most one SMB chunk in flight.
            await sink.writeFrom(bytes);
            offset += bytes.length;
            onBytes?.call(offset);
          }
        },
        knownSize: before.size,
        cancelToken: _cancel,
      );
      final after = await pool.stat(target, cancelToken: _cancel);
      if (after.size != before.size ||
          after.modified != before.modified ||
          after.changed != before.changed) {
        throw const RemoteException(
          'SMB file changed during download. Retry it.',
          code: RemoteErrorCode.fileChanged,
          arguments: {'protocol': 'SMB'},
        );
      }
    } finally {
      await sink.close();
    }
  });

  Future<void> write(String path, Uint8List bytes) => _guard(() async {
    final target = _path(path);
    await (await _open()).writeFile(target, bytes, cancelToken: _cancel);
  });
  Future<void> upload(String path, Stream<List<int>> data) => _guard(() async {
    final target = _path(path);
    await (await _open()).streamWrite(
      target,
      data.map(Uint8List.fromList),
      cancelToken: _cancel,
    );
  });
  Future<void> mkdir(String path) => _guard(() async {
    final target = _path(path);
    await (await _open()).mkdir(target, cancelToken: _cancel);
  });
  Future<void> rename(String from, String to) => _guard(() async {
    final source = _path(from), target = _path(to);
    await (await _open()).rename(source, target, cancelToken: _cancel);
  });
  Future<void> delete(String path, {required bool directory}) =>
      _guard(() async {
        final target = _path(path);
        if (target.isEmpty || target == _path('')) {
          throw const RemoteException(
            'Cannot delete the connection root.',
            code: RemoteErrorCode.deleteRoot,
          );
        }
        final pool = await _open();
        if (directory) {
          await pool.rmdir(target, cancelToken: _cancel);
        } else {
          await pool.deleteFile(target, cancelToken: _cancel);
        }
      });
  void close() {
    if (_closed) return;
    _closed = true;
    _cancel.cancel();
    final opening = _opening;
    if (opening != null) {
      unawaited(opening.then((p) => p.disconnect()).catchError((Object _) {}));
    }
  }
}
