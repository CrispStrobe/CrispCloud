import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:legacy_doc_parser/src/compound/cfbf_reader.dart';

String _sourceSha256(String path) {
  final result = Process.runSync('sha256sum', ['--', path]);
  final digest = result.stdout.toString().split(' ').first;
  if (result.exitCode != 0 || !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
    throw StateError('Unable to hash the retained source document');
  }
  return digest;
}

void main(List<String> args) {
  final source = File(args.single).readAsBytesSync();
  final cfb = CfbfFile.fromBytes(source);
  final word = ByteData.sublistView(cfb.readStream('WordDocument')!);
  int wu16(int p) => word.getUint16(p, Endian.little);
  int wu32(int p) => word.getUint32(p, Endian.little);
  final pairs = 34 + 2 * wu16(32) + 2 + 4 * wu16(34 + 2 * wu16(32)) + 2;
  final tableName = (wu16(10) & 0x200) != 0 ? '1Table' : '0Table',
      bytes = cfb.readStream((wu16(10) & 0x200) != 0 ? '1Table' : '0Table')!,
      data = ByteData.sublistView(
        cfb.readStream((wu16(10) & 0x200) != 0 ? '1Table' : '0Table')!,
      );
  int u16(int p) => data.getUint16(p, Endian.little);
  final stsh = wu32(pairs + 8),
      headerLength = u16(stsh),
      baseLength = u16(stsh + 4),
      record = stsh + headerLength + 4;
  final size = u16(record - 2),
      kind = u16(record + 2) & 15,
      upxCount = u16(record + 4) & 15,
      nameLength = u16(record + baseLength);
  final name = String.fromCharCodes([
    for (var i = 0; i < nameLength; i++) u16(record + baseLength + 2 + i * 2),
  ]);
  var pos = record + baseLength + 4 + nameLength * 2;
  final fonts = <Map<String, Object?>>[];
  final upx = <Map<String, Object?>>[];
  for (var i = 0; i < upxCount; i++) {
    final length = u16(pos);
    pos += 2;
    final start = pos, end = pos + length;
    if (kind == 1 && i == 1) {
      var p = start;
      while (p < end) {
        final offset = p, code = u16(p);
        p += 2;
        final spra = code >> 13;
        var n = const [1, 1, 2, 4, 2, 2, -1, 3][spra];
        if (n < 0) {
          n = bytes[p];
          p++;
        }
        if (p + n > end) {
          throw FormatException('Invalid literal Normal CHPX operand');
        }
        if (const [0x4a4f, 0x4a50, 0x4a51, 0x4a5e].contains(code)) {
          fonts.add({
            'sprm': '0x${code.toRadixString(16)}',
            'tableOffset': offset,
            'fontIndex': u16(p),
            'bytes': bytes
                .sublist(offset, p + n)
                .map((v) => v.toRadixString(16).padLeft(2, '0'))
                .join(),
          });
        }
        p += n;
      }
    }
    upx.add({'index': i, 'tableOffset': start, 'bytes': length});
    pos = end;
    if ((pos - record).isOdd) pos++;
  }
  print(
    const JsonEncoder.withIndent('  ').convert({
      'source': args.single,
      'sourceSha256': _sourceSha256(args.single),
      'table': tableName,
      'styleIndex': 0,
      'styleName': name,
      'styleKind': kind,
      'styleRecordTableOffset': record,
      'styleRecordBytes': size,
      'upx': upx,
      'fontOperands': fonts,
      'reader':
          'Independent literal FIB/STSH/STD/UPX operand walk; compound storage reader only.',
    }),
  );
}
