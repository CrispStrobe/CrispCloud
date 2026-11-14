import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:crisp_cloud/models/file_item.dart';

import 'archive_queue_fixture.dart';

/// A ZIP with just locally verifiable records and no central directory.
Uint8List recoveryWorkflowZip([Map<String, List<int>>? files]) {
  final output = BytesBuilder(copy: false);
  for (final file
      in (files ??
              {
                'one.txt': utf8.encode('first payload'),
                'two.txt': utf8.encode('second payload'),
              })
          .entries) {
    final name = utf8.encode(file.key);
    final header = ByteData(30)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 0x800, Endian.little)
      ..setUint32(14, getCrc32(file.value), Endian.little)
      ..setUint32(18, file.value.length, Endian.little)
      ..setUint32(22, file.value.length, Endian.little)
      ..setUint16(26, name.length, Endian.little);
    output.add(header.buffer.asUint8List());
    output.add(name);
    output.add(file.value);
  }
  return output.takeBytes();
}

/// Exposes the same sequence as native exclusive staging, including changes
/// between initial verification and the final committing checkpoint.
class RecoveryWorkflowBackend extends QueueArchiveBackend {
  RecoveryWorkflowBackend(super.account);
  Future<void> Function()? beforeCommit;
  bool corruptStage = false;
  @override
  Future<void> writePreparedFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
    Future<void> Function(FileItem)? verifyStaged,
    Future<void> Function(Map<String, dynamic>)? checkpoint,
  }) async {
    if (replace || await stat(path) != null) {
      throw StateError('Destination exists');
    }
    const stage = '/output/.recovery-stage';
    await checkpoint?.call({'phase': 'staging', 'stagedPath': stage});
    final output = BytesBuilder(copy: false);
    await for (final chunk in data) {
      output.add(chunk);
    }
    put(stage, output.takeBytes());
    try {
      if (corruptStage) contents[stage]![0] ^= 0xff;
      beforeStageVerification?.call();
      await verifyStaged?.call((await stat(stage))!);
      await beforeCommit?.call();
      await checkpoint?.call({'phase': 'committing', 'stagedPath': stage});
      if (await stat(path) != null) throw StateError('Destination exists');
      contents[path] = contents[stage]!;
      writes.add(path);
      afterInstall?.call();
      await checkpoint?.call({'phase': 'committed'});
    } finally {
      contents.remove(stage);
    }
  }
}
