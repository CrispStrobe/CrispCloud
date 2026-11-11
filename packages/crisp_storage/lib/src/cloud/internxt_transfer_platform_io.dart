import 'dart:io';

import 'package:path/path.dart' as p;

import 'transfer_spool_contract.dart';

TransferSpool sliceSpool(TransferSpool spool, int start, int end) {
  final path = spool.localPath;
  if (path == null) throw StateError('The upload has no native spool.');
  return _Slice(path, start, end);
}

class _Slice implements TransferSpool {
  _Slice(this.path, this.start, this.end);
  final String path;
  final int start, end;
  @override
  int get length => end - start;
  @override
  String? get localPath => null;
  @override
  Object? get webUploadBody => null;
  @override
  Stream<List<int>> openRead() => File(path).openRead(start, end);
  @override
  Future<void> dispose() async {}
}

Future<void> saveDownload(
  Stream<List<int>> source,
  String path, {
  required void Function() checkCurrent,
}) async {
  checkCurrent();
  final destination = File(path);
  await destination.parent.create(recursive: true);
  late final Directory workspace;
  var atomic = true;
  try {
    workspace = await destination.parent.createTemp(
      '.crisp-internxt-download-',
    );
  } on FileSystemException catch (error) {
    final code = error.osError?.errorCode;
    final denied = Platform.isWindows ? code == 5 : code == 1 || code == 13;
    if (!denied) rethrow;
    // A save dialog may authorize only the selected file, not its directory.
    workspace = await Directory.systemTemp.createTemp(
      'crisp-internxt-download-',
    );
    atomic = false;
  }
  try {
    final staged = File(p.join(workspace.path, 'payload'));
    final writer = await staged.open(mode: FileMode.write);
    try {
      await for (final chunk in source) {
        checkCurrent();
        await writer.writeFrom(chunk);
      }
      await writer.flush();
    } finally {
      await writer.close();
    }
    checkCurrent();
    if (atomic) {
      await staged.rename(destination.path);
    } else {
      await staged.copy(destination.path);
    }
  } finally {
    await workspace.delete(recursive: true);
  }
}
