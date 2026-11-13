import 'dart:convert';
import 'dart:io';

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
  const normalHex =
      '422a004f4a0400514a0400434a16006d480904734809044b480000'
      '504a05006e480904744809045e4a0600614a16005f480104';
  final bytes = File(args.single).readAsBytesSync();
  final cfb = CfbfFile.fromBytes(bytes);
  final table = cfb.readStream('1Table')!;
  final word = cfb.readStream('WordDocument')!;
  final needle = [
    for (var i = 0; i < normalHex.length; i += 2)
      int.parse(normalHex.substring(i, i + 2), radix: 16),
  ];
  final matches = <int>[];
  for (var i = 0; i + needle.length <= table.length; i++) {
    if (List.generate(
      needle.length,
      (j) => table[i + j] == needle[j],
    ).every((match) => match)) {
      matches.add(i);
    }
  }
  if (matches.length != 2 ||
      matches[0] != 84 ||
      matches[1] != 3916 ||
      word[2156] != 0x3d ||
      word[2157] != 0xd8 ||
      word[2158] != 0x00 ||
      word[2159] != 0xde) {
    throw StateError(
      'Retained source byte anchors differ: matches=$matches, '
      'emojiBytes=${word.sublist(2156, 2160)}',
    );
  }
  print(
    const JsonEncoder.withIndent('  ').convert({
      'sourceSha256': _sourceSha256(args.single),
      'tableStream': '1Table',
      'normalStyleGrpprlHex': normalHex,
      'exactMatchOffsets': matches,
      'rawEmojiWordDocumentOffset': 2156,
      'rawEmojiWordDocumentBytes': '3dd800de',
      'fontOperandIndices': {
        'sprmCRgFtc0': 4,
        'sprmCRgFtc1': 5,
        'sprmCRgFtc2': 4,
        'sprmCFtcBi': 6,
      },
      'sourceOfNormalStyleAnchor':
          'doc/evidence/script-font-slots-20261112/summary.json',
    }),
  );
}
