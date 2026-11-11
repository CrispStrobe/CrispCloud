import 'dart:io';
import 'dart:typed_data';
import 'remote_client.dart';

abstract interface class SmbTransport {
  String urlForPath(String path);
  Future<List<RemoteEntry>> browse(String path);
  Future<RemoteEntry?> stat(String path);
  Stream<List<int>> stream(String path, {void Function(int, int)? onProgress});
  Future<void> download(
    String path,
    File output, {
    void Function(int)? onBytes,
    required int limit,
  });
  Future<void> write(String path, Uint8List bytes);
  Future<void> upload(String path, Stream<List<int>> data);
  Future<void> mkdir(String path);
  Future<void> rename(String from, String to);
  Future<void> delete(String path, {required bool directory});
  void close();
}
