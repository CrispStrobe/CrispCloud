import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'remote_client.dart';
import 'rust_library.dart';
import 'rust/api.dart' as native;
import 'rust/frb_generated.dart';
import 'smb_backend.dart';
import 'smb_paths.dart';
import 'smb_transport.dart';

/// Experimental adapter. Native downloads bypass Dart byte copies entirely.
class RustSmbSession implements SmbTransport {
  static Future<void>? _initializing;
  static Future<void> initialize() => _initializing ??= (() async {
    try {
      const defined = String.fromEnvironment('CRISP_SMB_LIBRARY');
      final explicit = defined.isNotEmpty
          ? defined
          : Platform.environment['CRISP_SMB_LIBRARY'];
      if (explicit != null && explicit.isNotEmpty) {
        await RustLib.init(externalLibrary: ExternalLibrary.open(explicit));
        loadedFrom = explicit;
        return;
      }
      // App builds with `hooks.user_defines.crisp_storage.rust_smb: true`
      // bundle the bridge next to the executable (see hook/build.dart).
      for (final candidate in bundledRustLibraryCandidates(
        os: Platform.operatingSystem,
        executable: Platform.resolvedExecutable,
        workingDirectory: Directory.current.path,
      )) {
        final ExternalLibrary library;
        try {
          library = ExternalLibrary.open(candidate);
        } catch (_) {
          continue;
        }
        await RustLib.init(externalLibrary: library);
        loadedFrom = candidate;
        return;
      }
      // Developer checkout: FRB's default (rust/target/release/...).
      await RustLib.init();
      loadedFrom = 'default';
    } catch (_) {
      // No session, credentials or network operations exist at this boundary.
      throw const RustSmbUnavailable();
    }
  })();

  /// Diagnostic only: which library location initialized the bridge.
  static String? loadedFrom;

  final RemoteConnection connection;
  late final SmbPaths _paths = SmbPaths(connection);
  late final int _id;
  bool _closed = false, _downloading = false;

  /// The native session holds at most [maxOpenHandles] read/write handles
  /// (MAX_HANDLES in crisp_smb). Extra streams/uploads wait for a slot
  /// instead of failing with TooManyHandles, matching libsmb2's queueing.
  static const maxOpenHandles = 8;
  int _openHandles = 0;
  final _slotWaiters = <Completer<void>>[];

  Future<void> _acquireHandle() async {
    if (_closed) {
      throw const RemoteException(
        'SMB connection closed.',
        code: RemoteErrorCode.closed,
      );
    }
    if (_openHandles < maxOpenHandles) {
      _openHandles++;
      return;
    }
    final waiter = Completer<void>();
    _slotWaiters.add(waiter);
    await waiter.future; // the releasing holder hands its slot over
  }

  void _releaseHandle() {
    if (_slotWaiters.isNotEmpty) {
      _slotWaiters.removeAt(0).complete();
    } else {
      _openHandles--;
    }
  }

  RustSmbSession(this.connection) {
    final user = connection.username;
    final split = user.indexOf(r'\');
    final host = connection.url.host.contains(':')
        ? '[${connection.url.host}]'
        : connection.url.host;
    try {
      _id = native.createSession(
        configJson: jsonEncode({
          'address':
              '$host:${connection.url.hasPort ? connection.url.port : 445}',
          'share': connection.url.pathSegments.first,
          'root': _paths.root,
          'username': split < 0 ? user : user.substring(split + 1),
          'domain': split < 0 ? '' : user.substring(0, split),
          'password': connection.secret,
          'require_encryption': connection.requireEncryption,
        }),
      );
    } on FrbException catch (e) {
      throw _failure(e);
    }
  }
  static RemoteException _failure(FrbException e) {
    Map<String, dynamic> data = const {};
    if (e is AnyhowException) {
      try {
        data = jsonDecode(e.message) as Map<String, dynamic>;
      } catch (_) {}
    }
    final kind = data['code'] as String? ?? 'NativeFailure';
    final code = switch (kind) {
      'AuthRequired' => RemoteErrorCode.smbAuth,
      'NotFound' => RemoteErrorCode.smbNotFound,
      'Cancelled' => RemoteErrorCode.smbPaused,
      'Closed' => RemoteErrorCode.closed,
      'InvalidPath' => RemoteErrorCode.invalidPath,
      'FolderTooLarge' => RemoteErrorCode.folderTooLarge,
      'FileChanged' => RemoteErrorCode.fileChanged,
      'Incomplete' => RemoteErrorCode.incomplete,
      'LinksUnsupported' => RemoteErrorCode.linksUnsupported,
      'InvalidFile' => RemoteErrorCode.invalidFile,
      'RootMutation' => RemoteErrorCode.deleteRoot,
      _ => RemoteErrorCode.smbRequest,
    };
    return RemoteException(
      'SMB request failed ($kind).',
      code: code,
      retryable: data['retryable'] == true,
      arguments: {'protocol': 'SMB', 'type': kind},
    );
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    if (_closed) {
      throw const RemoteException(
        'SMB connection closed.',
        code: RemoteErrorCode.closed,
      );
    }
    try {
      return await action();
    } on FrbException catch (e) {
      throw _failure(e);
    }
  }

  Future<dynamic> _request(
    String op, {
    String path = '',
    String target = '',
    int handle = 0,
  }) => _guard(
    () async => jsonDecode(
      await native.request(
        id: _id,
        operation: op,
        path: _paths.relative(path),
        target: _paths.relative(target),
        handle: handle,
      ),
    ),
  );
  @override
  String urlForPath(String path) => _paths.urlForPath(path);
  @override
  Future<List<RemoteEntry>> browse(String path) async {
    final rows = await _request('list', path: path) as List;
    final parent = connection.url.resolve(
      path.isEmpty ? connection.url.toString() : path,
    );
    final result = <RemoteEntry>[];
    for (final row in rows) {
      final name = row['name'] as String;
      if (name.isEmpty ||
          name == '.' ||
          name == '..' ||
          name.contains('/') ||
          name.contains(r'\') ||
          name.contains('\u0000')) {
        continue;
      }
      final directory = row['directory'] == true;
      final uri = parent.replace(
        path:
            '${Uri.decodeComponent(parent.path).replaceFirst(RegExp(r'/*$'), '')}/$name${directory ? '/' : ''}',
      );
      _paths.relative(uri.toString());
      result.add(
        RemoteEntry(
          uri.toString(),
          name,
          directory ? 'folder' : 'file',
          size: row['size'] as int,
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
  }

  @override
  Future<RemoteEntry?> stat(String path) async {
    final row = await _request('stat', path: path);
    return row == null
        ? null
        : RemoteEntry(
            path,
            _paths.relative(path).split('/').last,
            row['directory'] == true ? 'folder' : 'file',
            size: row['size'] as int,
          );
  }

  @override
  Stream<List<int>> stream(
    String path, {
    void Function(int, int)? onProgress,
  }) async* {
    await _acquireHandle();
    final Map<String, dynamic> opened;
    try {
      opened = await _request('openRead', path: path) as Map<String, dynamic>;
    } catch (_) {
      _releaseHandle();
      rethrow;
    }
    final handle = opened['handle'] as int, size = opened['size'] as int;
    try {
      var offset = 0;
      while (offset < size) {
        final bytes = await _guard(
          () => native.readChunk(
            id: _id,
            handle: handle,
            offset: offset,
            length: (size - offset).clamp(0, 256 * 1024),
          ),
        );
        if (bytes.isEmpty) {
          throw const RemoteException(
            'SMB download was incomplete.',
            code: RemoteErrorCode.incomplete,
          );
        }
        offset += bytes.length;
        onProgress?.call(offset, size);
        yield bytes;
      }
      final after = await _request('stat', path: path);
      if (after == null ||
          jsonEncode(after['version']) != jsonEncode(opened['version'])) {
        throw const RemoteException(
          'SMB file changed during download.',
          code: RemoteErrorCode.fileChanged,
        );
      }
    } finally {
      try {
        if (!_closed) await _request('closeRead', handle: handle);
      } finally {
        _releaseHandle();
      }
    }
  }

  @override
  Future<void> download(
    String path,
    File output, {
    void Function(int)? onBytes,
    required int limit,
  }) => _guard(() async {
    if (limit <= 0) throw ArgumentError.value(limit, 'limit');
    if (_downloading) {
      throw StateError('Only one download per SMB session is supported.');
    }
    final relative = _paths.relative(path);
    _downloading = true;
    Object? callbackError;
    StackTrace? callbackStack;
    Timer? timer;
    try {
      if (onBytes != null) {
        timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
          if (_closed || callbackError != null) return;
          try {
            onBytes(native.progress(id: _id));
          } catch (e, s) {
            callbackError = e;
            callbackStack = s;
            native.cancelSession(id: _id);
          }
        });
      }
      final total = await native.download(
        id: _id,
        path: relative,
        output: output.path,
        source: connection.url.resolve(path).toString(),
        limit: limit,
      );
      if (callbackError != null) {
        Error.throwWithStackTrace(callbackError!, callbackStack!);
      }
      onBytes?.call(total);
    } catch (e, s) {
      if (callbackError != null) {
        Error.throwWithStackTrace(callbackError!, callbackStack!);
      }
      Error.throwWithStackTrace(e, s);
    } finally {
      timer?.cancel();
      _downloading = false;
    }
  });
  @override
  Future<void> write(String path, Uint8List bytes) =>
      upload(path, Stream.value(bytes));
  @override
  Future<void> upload(String path, Stream<List<int>> data) async {
    await _acquireHandle();
    final int handle;
    try {
      handle = await _request('openWrite', path: path) as int;
    } catch (_) {
      _releaseHandle();
      rethrow;
    }
    var finished = false;
    try {
      await for (final bytes in data) {
        for (var start = 0; start < bytes.length; start += 256 * 1024) {
          final end = (start + 256 * 1024).clamp(0, bytes.length);
          await _guard(
            () => native.writeChunk(
              id: _id,
              handle: handle,
              bytes: bytes is Uint8List
                  ? Uint8List.sublistView(bytes, start, end)
                  : bytes.sublist(start, end),
            ),
          );
        }
      }
      await _request('finishWrite', handle: handle);
      finished = true;
    } finally {
      try {
        if (!finished && !_closed) {
          await _request('abortWrite', handle: handle);
        }
      } finally {
        _releaseHandle();
      }
    }
  }

  @override
  Future<void> mkdir(String path) async {
    await _request('mkdir', path: path);
  }

  @override
  Future<void> rename(String from, String to) async {
    await _request('rename', path: from, target: to);
  }

  @override
  Future<void> delete(String path, {required bool directory}) async {
    await _request(directory ? 'rmdir' : 'delete', path: path);
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    for (final waiter in _slotWaiters) {
      waiter.completeError(
        const RemoteException(
          'SMB connection closed.',
          code: RemoteErrorCode.closed,
        ),
      );
    }
    _slotWaiters.clear();
    native.cancelSession(id: _id);
    unawaited(native.closeSession(id: _id).catchError((Object _) {}));
  }
}
