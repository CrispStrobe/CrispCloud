import 'dart:typed_data';

import 'package:koni_archive/koni_archive.dart' as koni;

import 'archive_types.dart';

/// A bounded random-access view. Offsets in a nested container never reach
/// outside its captured slice, including when several reads run concurrently.
class ArchiveSliceSource implements koni.ByteSource {
  ArchiveSliceSource(
    this.parent, {
    required this.offset,
    required this.length,
    this.name,
    this.ownsParent = true,
  }) {
    if (offset < 0 ||
        length < 0 ||
        offset > parent.length ||
        length > parent.length - offset) {
      throw const ArchiveViewException('Container extent leaves its source.');
    }
  }

  final koni.ByteSource parent;
  final int offset;
  @override
  final int length;
  @override
  final String? name;
  final bool ownsParent;
  bool _closed = false;

  @override
  Future<Uint8List> read(int offset, int length) async {
    if (_closed) throw const ArchiveViewException('This source is closed.');
    if (offset < 0 ||
        length < 0 ||
        offset > this.length ||
        length > this.length - offset) {
      throw const ArchiveViewException('Read leaves the container extent.');
    }
    final bytes = await parent.read(this.offset + offset, length);
    if (bytes.length != length) {
      throw const ArchiveViewException('The container source is truncated.');
    }
    return bytes;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (ownsParent) await parent.close();
  }
}
