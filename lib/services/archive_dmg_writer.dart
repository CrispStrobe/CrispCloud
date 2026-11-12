import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' as ar;

import 'archive_hfs_writer.dart';
import 'archive_types.dart';
import 'archive_write_model.dart';

const _imageLimit = 2 * 1024 * 1024 * 1024;
const _chunkBytes = 1024 * 1024;

Future<ArchiveRewriteInspection> inspectDmgRewrite(
  Uint8List bytes,
  ViewerArchive archive,
) async => ArchiveRewriteInspection(
  reason:
      'Existing DMG images remain read-only. Their file and partition views '
      'are not independent writable members. Create a new HFSX data image '
      'from regular files and folders instead.',
);

/// Creates an unsigned, unencrypted, single-volume UDIF image containing a
/// fresh case-sensitive HFSX filesystem. Regular data forks only; existing
/// filesystem attributes and image partitions cannot be rewritten by this API.
///
/// One MiB raw blocks are encoded independently as zlib or raw data, whichever
/// is smaller. Zero blocks use UDIF zero runs. The trailer and checksummed block
/// table are appended after streaming the image; no whole-volume buffer exists.
Future<void> writeDmgArchive(
  List<ArchiveWriteEntry> entries, {
  required Future<void> Function(List<int>) sink,
  ArchiveRewriteInspection? source,
  int maxOutputBytes = _imageLimit,
  bool Function()? isCancelled,
  String volumeName = 'CrispCloud',
  bool compress = true,
}) async {
  if (source != null) {
    throw const ArchiveViewException(
      'DMG image rewriting is unavailable; create a new data image instead.',
    );
  }
  final writer = _UdifWriter(sink, maxOutputBytes, isCancelled, compress);
  await writeHfsArchive(
    entries,
    sink: writer.add,
    maxOutputBytes: _imageLimit,
    isCancelled: isCancelled,
    volumeName: volumeName,
  );
  await writer.finish();
}

class _UdifWriter {
  _UdifWriter(this.sink, this.limit, this.isCancelled, this.compress) {
    if (limit <= 0 || limit > _imageLimit) {
      throw ArgumentError.value(limit, 'maxOutputBytes');
    }
    _check();
  }
  final Future<void> Function(List<int>) sink;
  final int limit;
  final bool Function()? isCancelled;
  final bool compress;
  final _pending = Uint8List(_chunkBytes);
  final _runs = <(int, int, int, int, int)>[];
  int _pendingBytes = 0, _rawBytes = 0, _outputBytes = 0;
  int _rawCrc = 0, _packedCrc = 0;

  void _check() {
    if (isCancelled?.call() ?? false) {
      throw const ArchiveViewException('Disk image creation cancelled.');
    }
  }

  Future<void> _emit(List<int> bytes) async {
    _check();
    if (bytes.length > limit - _outputBytes) {
      throw const ArchiveViewException('The DMG exceeds its output limit.');
    }
    await sink(bytes);
    _outputBytes += bytes.length;
    _check();
  }

  Future<void> add(List<int> bytes) async {
    _check();
    if (bytes.length > _imageLimit - _rawBytes - _pendingBytes) {
      throw const ArchiveViewException('The DMG volume exceeds two GiB.');
    }
    var at = 0;
    while (at < bytes.length) {
      final room = _chunkBytes - _pendingBytes;
      final count = room < bytes.length - at ? room : bytes.length - at;
      _pending.setRange(_pendingBytes, _pendingBytes + count, bytes, at);
      _pendingBytes += count;
      at += count;
      if (_pendingBytes == _chunkBytes) await _flush();
    }
  }

  Future<void> _flush() async {
    if (_pendingBytes == 0) return;
    _check();
    if (_pendingBytes % 512 != 0 || _runs.length >= 2048) {
      throw const ArchiveViewException(
        'Invalid or excessive UDIF block layout.',
      );
    }
    final raw = Uint8List.sublistView(_pending, 0, _pendingBytes);
    _rawCrc = ar.getCrc32(raw, _rawCrc);
    final start = _rawBytes ~/ 512;
    final count = raw.length ~/ 512;
    if (raw.every((byte) => byte == 0)) {
      _runs.add((0, start, count, _outputBytes, 0));
    } else {
      final packed = compress ? const ar.ZLibEncoder().encodeBytes(raw) : raw;
      final compressed = packed.length < raw.length;
      final output = compressed ? packed : raw;
      _runs.add((
        compressed ? 0x80000005 : 1,
        start,
        count,
        _outputBytes,
        output.length,
      ));
      _packedCrc = ar.getCrc32(output, _packedCrc);
      // A raw run may alias _pending; copy because the sink may retain chunks.
      await _emit(Uint8List.fromList(output));
    }
    _rawBytes += _pendingBytes;
    _pendingBytes = 0;
  }

  Future<void> finish() async {
    await _flush();
    _check();
    final table = Uint8List(204 + 40 * (_runs.length + 1));
    final t = ByteData.sublistView(table);
    table.setRange(0, 4, ascii.encode('mish'));
    t.setUint32(4, 1);
    _u64(t, 16, _rawBytes ~/ 512);
    t.setUint32(32, _chunkBytes ~/ 512);
    t.setUint32(36, 0xfffffffe); // entire partition
    _checksum(t, 64, _rawCrc);
    t.setUint32(200, _runs.length + 1);
    for (var i = 0; i < _runs.length; i++) {
      final run = _runs[i];
      final at = 204 + i * 40;
      t.setUint32(at, run.$1);
      _u64(t, at + 8, run.$2);
      _u64(t, at + 16, run.$3);
      _u64(t, at + 24, run.$4);
      _u64(t, at + 32, run.$5);
    }
    final end = 204 + _runs.length * 40;
    t.setUint32(end, 0xffffffff);
    _u64(t, end + 8, _rawBytes ~/ 512);
    _u64(t, end + 24, _outputBytes);
    final xml = utf8.encode(
      '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
      '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
      '<plist version="1.0"><dict><key>resource-fork</key><dict>'
      '<key>blkx</key><array><dict>'
      '<key>Attributes</key><string>0x0050</string>'
      '<key>ID</key><string>0</string>'
      '<key>Name</key><string>Apple_HFSX (CrispCloud data volume)</string>'
      '<key>Data</key><data>${base64.encode(table)}</data>'
      '</dict></array></dict></dict></plist>\n',
    );
    final forkLength = _outputBytes;
    if (xml.length + 512 > limit - _outputBytes) {
      throw const ArchiveViewException(
        'The DMG metadata exceeds its output limit.',
      );
    }
    await _emit(xml);
    final trailer = Uint8List(512);
    final k = ByteData.sublistView(trailer);
    trailer.setRange(0, 4, ascii.encode('koly'));
    k.setUint32(4, 4);
    k.setUint32(8, 512);
    k.setUint32(12, 1);
    _u64(k, 32, forkLength);
    k.setUint32(56, 1);
    k.setUint32(60, 1);
    // A deterministic per-image identifier; this is not a signature or UUID.
    k.setUint32(64, 0x43724331);
    k.setUint32(68, _rawCrc);
    k.setUint32(72, _packedCrc);
    k.setUint32(76, _rawBytes);
    _checksum(k, 80, _packedCrc);
    _u64(k, 216, forkLength);
    _u64(k, 224, xml.length);
    final checksum = Uint8List(4);
    ByteData.sublistView(checksum).setUint32(0, _rawCrc);
    _checksum(k, 352, ar.getCrc32(checksum));
    k.setUint32(488, 2); // partition image, no partition-map reconstruction
    _u64(k, 492, _rawBytes ~/ 512);
    await _emit(trailer);
  }
}

void _u64(ByteData data, int at, int value) {
  data.setUint32(at, value ~/ 0x100000000);
  data.setUint32(at + 4, value & 0xffffffff);
}

void _checksum(ByteData data, int at, int value) {
  data.setUint32(at, 2);
  data.setUint32(at + 4, 32);
  data.setUint32(at + 8, value);
}
