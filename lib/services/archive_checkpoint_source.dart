import 'dart:typed_data';

import 'package:koni_archive/koni_archive.dart' as koni;

/// Adds an awaited operation boundary to lazy container metadata/payload reads.
/// Ownership remains identical to the wrapped source: closing this view closes
/// its source, while failed reads leave cleanup to the reader's existing owner.
class ArchiveCheckpointSource implements koni.ByteSource {
  ArchiveCheckpointSource(this.source, this.checkpoint, this.check);

  final koni.ByteSource source;
  final Future<void> Function() checkpoint;
  final void Function() check;

  @override
  int get length => source.length;
  @override
  String? get name => source.name;

  @override
  Future<Uint8List> read(int offset, int count) async {
    await checkpoint();
    final bytes = await source.read(offset, count);
    check();
    return bytes;
  }

  @override
  Future<void> close() => source.close();
}
