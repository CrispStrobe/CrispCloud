import 'dart:io';

import 'package:path/path.dart' as p;

import 'transfer_spool_contract.dart';

Future<TransferSpool> createTransferSpool(
  Stream<List<int>> source, {
  int? expectedLength,
  int? maxBytes,
  Future<void> Function()? checkpoint,
}) async {
  final directory = await Directory.systemTemp.createTemp(
    'crisp-transfer-spool-',
  );
  final file = File(p.join(directory.path, 'payload'));
  var length = 0;
  try {
    final writer = await file.open(mode: FileMode.write);
    try {
      await for (final chunk in source) {
        await checkpoint?.call();
        length += chunk.length;
        if ((maxBytes != null && length > maxBytes) ||
            (expectedLength != null && length > expectedLength)) {
          throw StateError('Temporary transfer data exceeds its size limit.');
        }
        await writer.writeFrom(chunk);
      }
      if (expectedLength != null && length != expectedLength) {
        throw StateError('The source length changed while spooling.');
      }
      await writer.flush();
    } finally {
      await writer.close();
    }
    return _NativeTransferSpool(directory, file, length);
  } catch (_) {
    await _remove(directory);
    rethrow;
  }
}

Future<void> _remove(Directory directory) async {
  try {
    await directory.delete(recursive: true);
  } on FileSystemException {
    // Cleanup must not turn an acknowledged upload into an apparent failure.
    // The host owns optional cleanup diagnostics.
  }
}

class _NativeTransferSpool implements TransferSpool {
  _NativeTransferSpool(this.directory, this.file, this.length);
  final Directory directory;
  final File file;
  @override
  final int length;
  bool _closed = false;
  @override
  String get localPath => file.path;
  @override
  Object? get webUploadBody => null;
  @override
  Stream<List<int>> openRead() {
    if (_closed) throw StateError('This transfer spool was closed.');
    return file.openRead();
  }

  @override
  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    await _remove(directory);
  }
}
