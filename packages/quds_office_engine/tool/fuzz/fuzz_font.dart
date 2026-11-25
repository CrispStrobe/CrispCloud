import 'dart:io';
import 'dart:typed_data';

import 'package:covfuzz/covfuzz.dart';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/fonts/gsub_ligature.dart';
import 'package:quds_office_engine/src/pdf/file/text/pdf_cff_host.dart';

List<Uint8List> _seeds() {
  final out = <Uint8List>[];
  for (final root in <String>[
    '../quds_office_editor/fonts',
    'packages/quds_office_editor/fonts',
  ]) {
    final dir = Directory(root);
    if (!dir.existsSync()) continue;
    for (final file in dir.listSync().whereType<File>()) {
      final name = file.path.toLowerCase();
      if (!(name.endsWith('.ttf') || name.endsWith('.otf'))) continue;
      if (file.lengthSync() > 512 * 1024) continue;
      try {
        final font = SfntFont.parse(file.readAsBytesSync());
        final subset = FontSubsetter(
          font,
        ).subset(const <int>[0x20, 0x41, 0x627, 0x20AC]);
        out.add(subset.bytes);
      } on SfntException {
        continue;
      }
      if (out.length >= 6) return out;
    }
  }
  return out;
}

void _parse(Uint8List bytes) {
  if (PdfCffHost.isSfnt(bytes) || PdfCffHost.isRawCff(bytes)) {
    PdfCffHost.forFlutter(bytes);
  }
  final font = SfntFont.parse(bytes);
  for (final codePoint in const <int>[0x41, 0x627, 0x20AC, 0x1F600]) {
    final glyph = font.glyphIdFor(codePoint);
    font.advanceWidth(glyph);
    GlyphOutlineDecoder(font).decode(glyph);
  }
  GsubLigatures.parse(font);
  GposMarkToBase.parse(font);
}

void main(List<String> args) {
  final seeds = _seeds();
  for (final seed in seeds) {
    try {
      _parse(seed);
    } on SfntException {
      // A bundled face must remain parseable, but keep the warmup harness from
      // failing before the campaign if a platform font is unavailable.
    }
  }
  final report = fuzz<Uint8List>(
    seeds: seeds,
    entry: _parse,
    mutate: mutateBytes,
    isClean: (error) => error is SfntException || error is FormatException,
    iterations: 100000,
    budgetMs: int.tryParse(args.firstOrNull ?? '') ?? 30000,
    stressors: <Uint8List>[
      Uint8List(0),
      Uint8List.fromList(<int>[0x00, 0x01, 0x00, 0x00]),
      Uint8List.fromList(<int>[0x4F, 0x54, 0x54, 0x4F]),
    ],
  );
  exit(report.report());
}
