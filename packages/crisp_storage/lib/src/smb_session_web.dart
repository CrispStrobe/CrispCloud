import 'dart:io';
import 'dart:typed_data';
import 'remote_client.dart';

/// Browsers cannot connect to SMB TCP sockets.
class SmbSession {
  SmbSession(RemoteConnection connection);
  Never _unsupported() =>
      throw UnsupportedError('SMB requires the installed app.');
  String urlForPath(String path) => _unsupported();
  Future<List<RemoteEntry>> browse(String path) => _unsupported();
  Future<RemoteEntry?> stat(String path) => _unsupported();
  Stream<List<int>> stream(
    String path, {
    void Function(int, int)? onProgress,
  }) => _unsupported();
  Future<void> download(
    String path,
    File output, {
    void Function(int)? onBytes,
    required int limit,
  }) => _unsupported();
  Future<void> write(String path, Uint8List bytes) => _unsupported();
  Future<void> upload(String path, Stream<List<int>> data) => _unsupported();
  Future<void> mkdir(String path) => _unsupported();
  Future<void> rename(String from, String to) => _unsupported();
  Future<void> delete(String path, {required bool directory}) => _unsupported();
  void close() {}
}
