import 'dart:io';

import '../models/file_item.dart';
import 'file_operation_service.dart';

class ViewerSpool {
  ViewerSpool._(this._directory, this.path);
  final Directory _directory;
  final String path;
  bool _closed = false;
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (await _directory.exists()) await _directory.delete(recursive: true);
  }
}

/// Streams a large remote file into an owned temporary directory. No full-file
/// byte array is retained, and cancellation/failure deletes incomplete data.
Future<ViewerSpool> createViewerSpool(
  FileOperationBackend source,
  FileItem file, {
  int maxBytes = 2 * 1024 * 1024 * 1024,
  bool Function()? isCancelled,
  void Function(int bytes, int? total)? onProgress,
}) async {
  if (maxBytes <= 0) throw ArgumentError.value(maxBytes, 'maxBytes');
  void check() {
    if (!source.isCurrent) {
      throw StateError('The original viewer source changed.');
    }
    if (isCancelled?.call() ?? false) {
      throw StateError('Viewer download cancelled.');
    }
  }

  check();
  final current = await source.stat(file.path!);
  if (current == null || current.isFolder || current.isSymlink == true) {
    throw StateError('The viewed file is missing or no longer a regular file.');
  }
  if (file.uuid != null && current.uuid != file.uuid) {
    throw StateError('A different file now occupies the viewed path.');
  }
  if ((current.size ?? 0) > maxBytes) {
    throw StateError(
      'Remote viewer temporary copies are limited to ${maxBytes ~/ (1024 * 1024)} MiB. Download the file to view it locally.',
    );
  }
  final directory = await Directory.systemTemp.createTemp('crisp-viewer-');
  final suffix = RegExp(r'^[A-Za-z0-9]{1,12}$').hasMatch(file.extension)
      ? '.${file.extension}'
      : '';
  final output = File('${directory.path}/content$suffix');
  final sink = output.openWrite();
  var complete = false;
  try {
    var received = 0;
    await for (final chunk in source.readFile(current)) {
      check();
      received += chunk.length;
      if (received > maxBytes) {
        throw StateError('Viewer temporary copy limit exceeded.');
      }
      sink.add(chunk);
      // Backpressure bounds queued filesystem buffers even for very fast
      // remote streams whose chunks are produced synchronously.
      await sink.flush();
      onProgress?.call(received, current.size);
    }
    await sink.flush();
    check();
    final after = await source.stat(file.path!);
    if (after == null ||
        after.isFolder ||
        after.isSymlink == true ||
        current.uuid != after.uuid ||
        current.size != after.size ||
        current.updatedAt != after.updatedAt ||
        const [
          'etag',
          'versionId',
          'revision',
        ].any((key) => current.metadata?[key] != after.metadata?[key]) ||
        (current.size != null && received != current.size)) {
      throw StateError(
        'The remote file changed while preparing the viewer. Reload it.',
      );
    }
    await sink.close();
    complete = true;
    return ViewerSpool._(directory, output.path);
  } finally {
    if (!complete) {
      try {
        await sink.close();
      } catch (_) {
        /* Preserve the read error. */
      }
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  }
}
