import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import 'support/pdf_alias_fixture.dart';

final _output = Platform.environment['QUDS_ALIAS_RENDER_OUTPUT'] ?? '';

void main() {
  final source = aliasTestFont();
  final aliases = withSharedGlyphAliases(source);
  const text = 'A\u{1f600}\u{20000}AZ';

  test('Word PDF preserves distinct Unicode aliases of one real glyph', () {
    final bytes = OfficePdfExport.word(
      WmlDocument.empty(text: text),
      font: aliases,
    );
    final file = PdfFile.open(bytes);
    expect(PdfExtract.pageText(file, 0), text);
    final ops = file.displayList(0).ops.whereType<PdfDrawText>().toList();
    expect(ops.map((op) => op.text).join(), text);
    for (final query in ['A', '\u{1f600}', '\u{20000}']) {
      expect(
        OfficeFind.inPdf(file, OfficeFindOptions(query: query)),
        hasLength(query == 'A' ? 2 : 1),
      );
    }
    for (final op in ops) {
      final subset = SfntFont.parse(op.fontBytes!);
      final oldId = source.glyphIdFor(op.text == 'Z' ? 0x5a : 0x41);
      final newId = subset.glyphIdFor(op.text.runes.single);
      expect(subset.advanceWidth(newId), source.advanceWidth(oldId));
    }
    if (_output.isNotEmpty) {
      Directory(_output).createSync(recursive: true);
      File('$_output/word-unicode-aliases.pdf').writeAsBytesSync(bytes);
    }
  });

  test('Word PDF preserves the bundled italic font fi aliases', () {
    final italic = aliasTestFont('LiberationSerif-Italic');
    expect(italic.glyphIdFor(0xf001), isNonZero);
    expect(italic.glyphIdFor(0xf001), italic.glyphIdFor(0xfb01));
    const authored = '\uf001\ufb01\uf001';
    final file = PdfFile.open(
      OfficePdfExport.word(WmlDocument.empty(text: authored), font: italic),
    );
    expect(PdfExtract.pageText(file, 0), authored);
    expect(
      OfficeFind.inPdf(file, const OfficeFindOptions(query: '\uf001')),
      hasLength(2),
    );
    expect(
      OfficeFind.inPdf(file, const OfficeFindOptions(query: '\ufb01')),
      hasLength(1),
    );
  });

  test('worksheet PDF preserves shared-glyph Unicode text', () {
    final book = SmlWorkbook();
    book.firstSheet.cellA1('A1').value = text;
    final file = PdfFile.open(OfficePdfExport.workbook(book, font: aliases));
    expect(PdfExtract.pageText(file, 0), contains(text));
  });

  test('presentation PDF preserves shared-glyph Unicode text', () {
    final deck = PmlPresentation(
      slides: [
        PmlSlide(
          id: 256,
          shapes: [
            PmlShape(
              id: 2,
              name: 'Aliases',
              text: text,
              transform: const PmlTransform(
                x: 200000,
                y: 200000,
                cx: 4000000,
                cy: 800000,
              ),
            ),
          ],
        ),
      ],
    );
    final file = PdfFile.open(
      OfficePdfExport.presentation(deck, font: aliases),
    );
    expect(PdfExtract.pageText(file, 0), contains(text));
  });

  test('large repertoires split and reuse bounded PDF font resources', () {
    // Supplementary private-use aliases avoid script/control semantics. Zero
    // advances keep this synthetic capacity fixture on one layout line.
    final points = [
      for (var i = 0; i < 0xfffe; i++) 0xf0000 + i,
      0x100000,
      0x100001,
    ];
    final font = fontWithCmap(source, {
      for (final cp in points) cp: source.glyphIdFor(0x41),
    }, zeroAdvance: true);
    final file = PdfFile.open(
      OfficePdfExport.word(
        WmlDocument.empty(
          text: String.fromCharCodes([...points, points.first, points.last]),
        ),
        font: font,
      ),
    );
    final resources = file.store.asDict(file.pageRec(0).dict['Resources'])!;
    final fonts = file.store.asDict(resources['Font'])!;
    final counts = <int>[];
    for (final value in fonts.values.values) {
      final type0 = file.store.asDict(value)!;
      if (pdfCosName(type0['Subtype']) != 'Type0') continue;
      final descendants =
          file.store.deref(type0['DescendantFonts']) as PdfCosArray;
      final cid = file.store.asDict(descendants.items.single)!;
      final mapping = file.store.streamBytes(cid['CIDToGIDMap'])!;
      counts.add(mapping.length ~/ 2 - 1);
    }
    counts.sort();
    expect(counts, [
      1,
      0xffff,
    ], reason: 'Previously emitted CIDs stay reusable');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
