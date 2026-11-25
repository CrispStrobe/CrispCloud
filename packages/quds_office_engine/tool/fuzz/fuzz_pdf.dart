import 'dart:io';
import 'dart:typed_data';

import 'package:covfuzz/covfuzz.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

List<Uint8List> _seeds() {
  final doc = PdfDocument(title: 'Parser fixture');
  final canvas = PdfCanvas(200, 200)
    ..showLatin(x: 20, y: 30, fontSize: 12, text: 'PDF', color: '000000')
    ..showLatin(
      x: 20,
      y: 50,
      fontSize: 12,
      text: 'Second line',
      color: '000000',
    );
  doc.addPage(PdfPage(width: 200, height: 200, content: canvas.toStream()));
  final second = PdfCanvas(
    200,
    200,
  )..showLatin(x: 10, y: 10, fontSize: 8, text: 'Second page', color: '000000');
  doc.addPage(PdfPage(width: 200, height: 200, content: second.toStream()));
  // Keep the seed deterministic and fast. Validation-corpus PDFs include
  // complex but valid pages that take most of a second; using them here would
  // classify ordinary rendering cost as a slow-parse finding. The regression
  // suite, not the blind campaign, owns complex-layout coverage.
  return <Uint8List>[doc.save()];
}

void _parse(Uint8List bytes) {
  final file = PdfFile.open(bytes);
  final pages = file.pageCount < 8 ? file.pageCount : 8;
  for (var i = 0; i < pages; i++) {
    final list = file.displayList(i);
    if (list.failed) continue;
    PdfExtract.pageText(file, i);
  }
}

void main(List<String> args) {
  final seeds = _seeds();
  // Warm the parser and JIT before measuring per-input time. Without this, the
  // first mutation can carry compilation cost and look like a slow-parse bomb.
  _parse(seeds.first);
  final report = fuzz<Uint8List>(
    seeds: seeds,
    entry: _parse,
    mutate: mutateBytes,
    isClean: (error) =>
        error is PdfOpenException ||
        error is PdfFilterUnsupported ||
        error is ZipDeflateException ||
        error is FormatException,
    iterations: 20000,
    budgetMs: int.tryParse(args.firstOrNull ?? '') ?? 30000,
  );
  exit(report.report());
}
