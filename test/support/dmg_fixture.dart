import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Independent small UDIF writer for tests. The fixture describes one complete
/// partition and does not invoke any production disk-image reading code.
class DmgFixture {
  DmgFixture(
    Uint8List payload, {
    this.method = 1,
    this.label = 'Test volume',
    this.checksum = true,
    this.chunkBytes = 4096,
  }) {
    logical = Uint8List(((payload.length + 511) ~/ 512) * 512)
      ..setAll(0, payload);
    final packed = BytesBuilder(copy: false);
    final chunks = <List<int>>[];
    for (var at = 0; at < logical.length; at += chunkBytes) {
      final end = (at + chunkBytes).clamp(0, logical.length);
      final raw = logical.sublist(at, end);
      final compressed = switch (method) {
        0 || 2 => Uint8List(0),
        0x80000004 => _adcLiterals(raw),
        0x80000005 => Uint8List.fromList(const ZLibEncoder().encode(raw)),
        0x80000006 => Uint8List.fromList(BZip2Encoder().encode(raw)),
        0x80000008 => Uint8List.fromList(XZEncoder().encode(raw)),
        _ => raw,
      };
      chunks.add([
        method,
        at ~/ 512,
        raw.length ~/ 512,
        packed.length,
        compressed.length,
      ]);
      packed.add(compressed);
    }
    chunks.add([0xffffffff, logical.length ~/ 512, 0, 0, 0]);
    table = Uint8List(204 + chunks.length * 40);
    final header = ByteData.sublistView(table);
    table.setAll(0, ascii.encode('mish'));
    header.setUint32(4, 1);
    header.setUint64(16, logical.length ~/ 512);
    header.setUint32(32, chunkBytes ~/ 512);
    if (checksum) {
      header.setUint32(64, 2);
      header.setUint32(68, 32);
      header.setUint32(72, method == 2 ? 0 : getCrc32(logical));
    }
    header.setUint32(200, chunks.length);
    for (var i = 0; i < chunks.length; i++) {
      final chunk = chunks[i];
      final at = 204 + i * 40;
      header.setUint32(at, chunk[0]);
      header.setUint64(at + 8, chunk[1]);
      header.setUint64(at + 16, chunk[2]);
      header.setUint64(at + 24, chunk[3]);
      header.setUint64(at + 32, chunk[4]);
    }
    packedBytes = packed.takeBytes();
    rebuild();
  }

  final int method, chunkBytes;
  final String label;
  final bool checksum;
  late Uint8List logical, packedBytes, table, bytes;
  late int xmlOffset, xmlLength;

  void rebuild({String? xml}) {
    final escaped = label.replaceAll('&', '&amp;').replaceAll('<', '&lt;');
    final text =
        xml ??
        '<?xml version="1.0" encoding="UTF-8"?>'
            '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
            '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
            '<plist version="1.0"><dict><key>resource-fork</key><dict>'
            '<key>blkx</key><array><dict><key>Name</key><string>$escaped</string>'
            '<key>Data</key><data>${base64.encode(table)}</data></dict></array>'
            '</dict></dict></plist>';
    final metadata = utf8.encode(text);
    xmlOffset = packedBytes.length;
    xmlLength = metadata.length;
    bytes = Uint8List(packedBytes.length + metadata.length + 512)
      ..setAll(0, packedBytes)
      ..setAll(xmlOffset, metadata);
    final trailer = ByteData.sublistView(bytes, bytes.length - 512);
    bytes.setAll(bytes.length - 512, ascii.encode('koly'));
    trailer.setUint32(4, 4);
    trailer.setUint32(8, 512);
    trailer.setUint32(12, 1);
    trailer.setUint64(32, packedBytes.length);
    trailer.setUint32(56, 1);
    trailer.setUint32(60, 1);
    trailer.setUint64(216, xmlOffset);
    trailer.setUint64(224, xmlLength);
    trailer.setUint32(488, 1);
    trailer.setUint64(492, logical.length ~/ 512);
  }

  ByteData get trailer => ByteData.sublistView(bytes, bytes.length - 512);
  ByteData get tableData => ByteData.sublistView(table);
}

// Only literal runs are needed to wrap arbitrary filesystem test data. Real
// match tokens are exercised by the independently sourced Apple ADC fixture.
Uint8List _adcLiterals(Uint8List input) {
  final output = BytesBuilder(copy: false);
  for (var at = 0; at < input.length; at += 128) {
    final end = (at + 128).clamp(0, input.length);
    output.addByte(0x80 | (end - at - 1));
    output.add(Uint8List.sublistView(input, at, end));
  }
  return output.takeBytes();
}
