import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'remote_client.dart';
import 'libsmb2_session.dart';
import 'rust_smb_session.dart';
import 'smb_backend.dart';
import 'smb_paths.dart';
import 'smb_transport.dart';
export 'smb_backend.dart' show SmbBackend, parseSmbBackend;

/// Compatibility facade: apps retain the same API and libsmb2 default.
class SmbSession implements SmbTransport {
  final RemoteConnection connection;
  final SmbBackend backend;
  SmbBackend? effectiveBackend;
  Future<SmbTransport>? _opening;
  bool _closed = false;
  late final _paths = SmbPaths(connection);
  SmbSession(this.connection, {SmbBackend? backend})
    : backend = backend ?? connection.smbBackend ?? configuredSmbBackend() {
    if (connection.kind != 'smb') {
      throw ArgumentError('Expected SMB connection');
    }
  }
  Future<SmbTransport> _open() {
    if (_closed) {
      return Future.error(
        const RemoteException(
          'SMB connection closed.',
          code: RemoteErrorCode.closed,
          arguments: {'protocol': 'SMB'},
        ),
      );
    }
    return _opening ??=
        (() async {
          final selected = await selectSmbBackend(
            backend,
            RustSmbSession.initialize,
          );
          if (_closed) {
            throw const RemoteException(
              'SMB connection closed.',
              code: RemoteErrorCode.closed,
            );
          }
          effectiveBackend = selected;
          // This happens outside fallback handling: all config/auth/network/security
          // failures stay with the selected backend, without another login attempt.
          return selected == SmbBackend.rust
              ? RustSmbSession(connection)
              : Libsmb2Session(connection);
        })().catchError((Object e, StackTrace s) {
          _opening = null;
          Error.throwWithStackTrace(e, s);
        });
  }

  @override
  String urlForPath(String path) => _paths.urlForPath(path);
  @override
  Future<List<RemoteEntry>> browse(String path) async =>
      (await _open()).browse(path);
  @override
  Future<RemoteEntry?> stat(String path) async => (await _open()).stat(path);
  @override
  Stream<List<int>> stream(
    String path, {
    void Function(int, int)? onProgress,
  }) async* {
    yield* (await _open()).stream(path, onProgress: onProgress);
  }

  @override
  Future<void> download(
    String path,
    File output, {
    void Function(int)? onBytes,
    required int limit,
  }) async =>
      (await _open()).download(path, output, onBytes: onBytes, limit: limit);
  @override
  Future<void> write(String path, Uint8List bytes) async =>
      (await _open()).write(path, bytes);
  @override
  Future<void> upload(String path, Stream<List<int>> data) async =>
      (await _open()).upload(path, data);
  @override
  Future<void> mkdir(String path) async => (await _open()).mkdir(path);
  @override
  Future<void> rename(String from, String to) async =>
      (await _open()).rename(from, to);
  @override
  Future<void> delete(String path, {required bool directory}) async =>
      (await _open()).delete(path, directory: directory);
  @override
  void close() {
    if (_closed) return;
    _closed = true;
    final opening = _opening;
    if (opening != null) {
      unawaited(opening.then((s) => s.close()).catchError((Object _) {}));
    }
  }
}
