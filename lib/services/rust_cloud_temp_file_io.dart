// Private temporary files for the Rust cloud engines (native platforms).
import 'dart:io';

import 'package:path/path.dart' as p;

/// A private temporary directory with one file path inside it.
class RustCloudTempFile {
  RustCloudTempFile._(this._directory, this.path);
  final Directory _directory;
  final String path;

  static Future<RustCloudTempFile> create(String name) async {
    final safe = name.isEmpty || name == '.' || name == '..'
        ? 'transfer'
        : name.replaceAll(RegExp(r'[/\\\x00]'), '_');
    final directory = await Directory.systemTemp.createTemp('crisp-rust-');
    return RustCloudTempFile._(directory, p.join(directory.path, safe));
  }

  Future<void> writeBytes(List<int> bytes) =>
      File(path).writeAsBytes(bytes, flush: true);

  /// Spool exactly [length] bytes; a short or long stream is rejected.
  Future<void> writeStream(Stream<List<int>> source, int length) async {
    final sink = File(path).openWrite();
    var written = 0;
    try {
      await for (final chunk in source) {
        written += chunk.length;
        if (written > length) {
          throw StateError('The upload source is longer than declared.');
        }
        sink.add(chunk);
      }
    } finally {
      await sink.close();
    }
    if (written != length) {
      throw StateError('The upload source ended before its declared length.');
    }
  }

  Stream<List<int>> openRead() => File(path).openRead();

  Future<int> length() => File(path).length();

  Future<void> delete() async {
    try {
      if (await _directory.exists()) await _directory.delete(recursive: true);
    } catch (_) {
      // Removing a temporary copy must not turn a completed transfer into a
      // failure; the OS temp directory is cleaned eventually.
    }
  }
}
