import 'dart:io';
import 'dart:typed_data';

import 'package:covfuzz/covfuzz.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

List<Uint8List> _seeds() {
  final doc = PdfDocument(title: 'Parser fixture');
  final canvas = PdfCanvas(200, 200)
    ..showLatin(x: 20, y: 30, fontSize: 12, text: 'PDF', color: '000000');
  doc.addPage(PdfPage(width: 200, height: 200, content: canvas.toStream()));
  final out = <Uint8List>[doc.save()];
  for (final root in <String>['../../docs', '../docs', 'docs']) {
    final dir = Directory(root);
    if (!dir.existsSync()) continue;
    for (final file in dir.listSync(recursive: true).whereType<File>()) {
      if (!file.path.toLowerCase().endsWith('.pdf')) continue;
      if (file.lengthSync() > 64 * 1024) continue;
      out.add(file.readAsBytesSync());
      if (out.length >= 32) return out;
    }
  }
  return out;
}

void main(List<String> args) {
  final seeds = _seeds();
  final report = fuzz<Uint8List>(
    seeds: seeds,
    entry: (bytes) {
      final file = PdfFile.open(bytes);
      final pages = file.pageCount < 8 ? file.pageCount : 8;
      for (var i = 0; i < pages; i++) {
        final list = file.displayList(i);
        if (list.failed) continue;
        PdfExtract.pageText(file, i);
      }
    },
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
