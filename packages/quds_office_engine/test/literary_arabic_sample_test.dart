import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/pdf_widgets_samples.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  final SfntFont? tajawal = _font(
    '../quds_office_editor/example/fonts/Tajawal-Regular.ttf',
  );
  final SfntFont? tajawalBold = _font(
    '../quds_office_editor/example/fonts/Tajawal-Bold.ttf',
  );

  test('ayat wa ashar diwan embeds Tajawal tashkeel and poetry', () {
    if (tajawal == null || tajawalBold == null) {
      markTestSkipped('Tajawal is not next to the engine package');
      return;
    }
    final Uint8List bytes = buildAyatWaAsharPdf(
      font: tajawal,
      fontBold: tajawalBold,
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(String.fromCharCodes(bytes), contains('/Tajawal'));

    final PdfFile file = PdfFile.open(bytes);
    expect(file.pageCount, greaterThan(3));

    final String folded = ArabicShaper.foldPresentation(
      PdfExtract.documentText(file),
    );
    final String letters = String.fromCharCodes(
      folded.runes.where((int cp) => cp < 0x064B || cp > 0x0652),
    );
    expect(folded.contains('\u064F'), isTrue, reason: 'damma');
    expect(_mentions(letters, 'الحمد'), isTrue, reason: letters);
    expect(_mentions(letters, 'قفا'), isTrue, reason: letters);
    expect(_mentions(letters, 'المتنبي'), isTrue, reason: letters);

    PdfDrawText? damma;
    PdfDrawText? qaf;
    for (int i = 0; i < file.pageCount; i++) {
      for (final PdfPaintOp op in file.displayList(i).ops) {
        if (op is! PdfDrawText || op.text.isEmpty) {
          continue;
        }
        final int cp = op.text.runes.first;
        if (cp == 0x064F && damma == null) {
          damma = op;
        }
        if ((cp == 0x0642 || cp == 0xFED7 || cp == 0xFED8) && qaf == null) {
          qaf = op;
        }
      }
    }
    expect(damma, isNotNull, reason: 'combining damma must paint');
    expect(qaf, isNotNull);
  });
}

bool _mentions(String hay, String logical) {
  final String rev = String.fromCharCodes(logical.runes.toList().reversed);
  return hay.contains(logical) || hay.contains(rev);
}

SfntFont? _font(String path) {
  final File file = File(path);
  if (!file.existsSync()) {
    return null;
  }
  return SfntFont.parse(file.readAsBytesSync());
}
