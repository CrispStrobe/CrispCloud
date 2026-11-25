import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:covfuzz/covfuzz.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

List<Uint8List> _seeds() {
  final archive = ZipWriter()
    ..addFile(
      '[Content_Types].xml',
      '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>'
          .codeUnits,
    )
    ..addFile(
      'word/document.xml',
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p/></w:body></w:document>'
          .codeUnits,
    );
  // Keep the seed deterministic and fast. Large fixture packages can consume
  // hundreds of milliseconds as valid parses; the regression suite owns that
  // coverage, while this campaign exercises ZIP/XML/repair work on mutated
  // minimal OOXML.
  return <Uint8List>[archive.close()];
}

void _parse(Uint8List bytes) {
  final package = OfficeRepair.open(bytes);
  var read = 0;
  for (final part in package.parts) {
    if (read++ >= 32) break;
    part.readBytes();
  }
}

// Manual campaign. The strict OOXML path is fast, but malformed packages can
// fall back to OfficeRepair/ZIP reconstruction at a few milliseconds each.
// That is above covfuzz's blind slow-parse budget for a 5-second CI smoke, so
// the bounded repair regressions run in CI and this full campaign stays local.
void main(List<String> args) {
  final seeds = _seeds();
  // Warm both the strict open path and the repair/recovery fallback before
  // timing. A cold repair path otherwise carries JIT cost into the first
  // mutated package and looks like a slow-parse bomb.
  for (final warm in <Uint8List>[
    seeds.first,
    Uint8List.sublistView(seeds.first, 0, seeds.first.length - 12),
    Uint8List.fromList(seeds.first)
      ..fillRange(seeds.first.length - 22, seeds.first.length, 0),
  ]) {
    try {
      _parse(warm);
    } on Object {
      // Typed rejection is expected for the warmup damage.
    }
  }
  // A deterministic pre-campaign mutation pass warms the many typed repair
  // branches. Otherwise the first hit in a cold branch can carry JIT/GC cost
  // and be reported as a slow-parse bomb.
  final rng = Random(7);
  for (var i = 0; i < 64; i++) {
    try {
      _parse(mutateBytes(seeds.first, rng));
    } on Object {
      // Typed rejection is expected.
    }
  }
  final report = fuzz<Uint8List>(
    seeds: seeds,
    entry: _parse,
    mutate: mutateBytes,
    isClean: (error) =>
        error is OfficeRepairException ||
        error is ZipException ||
        error is ZipDeflateException ||
        error is XmlParseException ||
        error is FormatException,
    iterations: 20000,
    budgetMs: int.tryParse(args.firstOrNull ?? '') ?? 30000,
  );
  exit(report.report());
}
