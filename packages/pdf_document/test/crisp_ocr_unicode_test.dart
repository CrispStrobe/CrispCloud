import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

CosDictionary _fonts(PdfDocument document, int page) =>
    document.cos.resolve(document.page(page).resources['Font'])
        as CosDictionary;

String _unicodeMap(PdfDocument document, CosDictionary font) {
  final stream = document.cos.resolve(font['ToUnicode']) as CosStream;
  return latin1.decode(document.cos.decodeStreamData(stream));
}

void main() {
  late Uint8List fontBytes;
  setUpAll(() {
    // Shared small test-only font, with its original notices beside it.
    fontBytes = File('../pdf_operations/test/fonts/CrispPdfTestSans.ttf')
        .readAsBytesSync();
  });

  test('Unicode OCR embeds a Type0 font and every recognized character mapping',
      () {
    final font = PdfEmbeddedFont.parse(fontBytes);
    final editor = PdfEditor(PdfDocument.open(PdfBlankDocument.create()));
    const text = 'Жук Αθήνα';
    expect(
        editor.injectTextLayer(
            0,
            const [
              PdfOcrSpan(text: text, bounds: PdfRect(72, 700, 260, 730)),
            ],
            embeddedFont: font),
        1);
    final output = PdfDocument.open(editor.save());
    final fonts = _fonts(output, 0);
    final type0 = output.cos.resolve(fonts['OcrF1']) as CosDictionary;
    expect(type0['Subtype'], const CosName('Type0'));
    expect(type0['Encoding'], const CosName('Identity-H'));
    final cmap = _unicodeMap(output, type0).toLowerCase();
    for (final rune in text.runes.toSet()) {
      final gid = font.glyphForRune(rune).toRadixString(16).padLeft(4, '0');
      final unicode = rune.toRadixString(16).padLeft(4, '0');
      expect(cmap, contains('<$gid> <$unicode>'));
    }
    final content = latin1.decode(output.page(0).contentBytes());
    expect(content, contains('3 Tr'));
    expect(content, contains('<${font.encodeHex(text)}> Tj'));
    expect(content, contains('/ActualText <FEFF'));
    expect(content, isNot(contains('(??')));
    final descendants =
        output.cos.resolve(type0['DescendantFonts']) as CosArray;
    final cid = output.cos.resolve(descendants[0]) as CosDictionary;
    final descriptor =
        output.cos.resolve(cid['FontDescriptor']) as CosDictionary;
    final program = output.cos.resolve(descriptor['FontFile2']) as CosStream;
    expect(output.cos.decodeStreamData(program), fontBytes);
  });

  for (final (rotation, placement) in const [
    (0, '200 307.5 Td'),
    (90, '0 1 -1 0 222.5 300 Tm'),
    (180, '-1 0 0 -1 400 322.5 Tm'),
    (270, '0 -1 1 0 207.5 500 Tm'),
  ]) {
    test('Unicode OCR follows displayed orientation at $rotation degrees', () {
      final font = PdfEmbeddedFont.parse(fontBytes);
      final editor =
          PdfEditor(PdfDocument.open(buildMultiPagePdf(1, rotation: rotation)));
      final sideways = rotation == 90 || rotation == 270;
      editor.injectTextLayer(
          0,
          [
            PdfOcrSpan(
                text: 'Жук',
                bounds: sideways
                    ? const PdfRect(200, 300, 230, 500)
                    : const PdfRect(200, 300, 400, 330))
          ],
          embeddedFont: font);
      final content =
          latin1.decode(PdfDocument.open(editor.save()).page(0).contentBytes());
      expect(content, contains('/OcrF1 30 Tf'));
      expect(content, contains(placement));
      final scale =
          double.parse(RegExp(r'([\d.]+) Tz').firstMatch(content)![1]!);
      expect(scale, closeTo(200 / font.measure('Жук', 30) * 100, .001));
    });
  }

  test('a later layer cannot replace earlier glyph mappings', () {
    final font = PdfEmbeddedFont.parse(fontBytes);
    final editor =
        PdfEditor(PdfDocument.open(PdfBlankDocument.create(pageCount: 2)));
    editor.injectTextLayer(
        0,
        const [
          PdfOcrSpan(text: 'Жук', bounds: PdfRect(20, 20, 150, 50)),
        ],
        embeddedFont: font);
    editor.injectTextLayer(
        0,
        const [
          PdfOcrSpan(text: 'Αθήνα', bounds: PdfRect(20, 100, 180, 130)),
        ],
        embeddedFont: font);
    editor.injectTextLayer(
        1,
        const [
          PdfOcrSpan(text: 'Москва', bounds: PdfRect(20, 20, 180, 50)),
        ],
        embeddedFont: font);
    final output = PdfDocument.open(editor.save());
    final page0 = _fonts(output, 0);
    expect(page0.entries.keys, containsAll(['OcrF1', 'OcrF2']));
    final first =
        _unicodeMap(output, output.cos.resolve(page0['OcrF1']) as CosDictionary)
            .toLowerCase();
    final second =
        _unicodeMap(output, output.cos.resolve(page0['OcrF2']) as CosDictionary)
            .toLowerCase();
    expect(first, contains('<0416>')); // Ж
    expect(first, isNot(contains('<0391>'))); // Α
    expect(second, contains('<0391>'));
    expect(second, isNot(contains('<0416>')));
    expect(_fonts(output, 1).entries.keys, ['OcrF1']);
  });

  test('unsupported Unicode and missing glyphs fail before changing the PDF',
      () {
    final editor = PdfEditor(PdfDocument.open(PdfBlankDocument.create()));
    expect(
        () => editor.injectTextLayer(0, const [
              PdfOcrSpan(text: 'Жук', bounds: PdfRect(20, 20, 150, 50)),
            ]),
        throwsArgumentError);
    expect(editor.hasChanges, isFalse);
    expect(
        () => editor.injectTextLayer(
            0,
            const [
              PdfOcrSpan(text: 'good', bounds: PdfRect(20, 20, 150, 50)),
              PdfOcrSpan(text: '漢', bounds: PdfRect(20, 100, 180, 130)),
            ],
            embeddedFont: PdfEmbeddedFont.parse(fontBytes)),
        throwsArgumentError);
    expect(editor.hasChanges, isFalse);
    expect(editor.document.page(0).contentBytes(), isEmpty);
  });

  test('rejected recognition is skipped; accepted run whitespace is normalized',
      () {
    final font = PdfEmbeddedFont.parse(fontBytes);
    final editor = PdfEditor(PdfDocument.open(PdfBlankDocument.create()));
    expect(
        editor.injectTextLayer(
            0,
            const [
              PdfOcrSpan(
                  text: '漢', bounds: PdfRect(20, 20, 150, 50), confidence: .1),
              PdfOcrSpan(text: 'A\nB\tC', bounds: PdfRect(20, 100, 180, 130)),
            ],
            embeddedFont: font,
            minConfidence: .5),
        1);
    final output = PdfDocument.open(editor.save());
    expect(latin1.decode(output.page(0).contentBytes()),
        contains('<${font.encodeHex('A B C')}> Tj'));
  });

  test('existing form styling preserves Unicode text and choice appearances',
      () {
    final editor = PdfEditor(PdfDocument.open(PdfBlankDocument.create()));
    final text =
        editor.addTextField(0, 'name', const PdfRect(20, 100, 400, 130));
    editor.setTextFieldStyle(text, font: PdfEmbeddedFont.parse(fontBytes));
    editor.setTextValue(text, 'Жук Αθήνα');
    final choice = editor.addComboBoxField(
        0,
        'city',
        const PdfRect(20, 180, 400, 210),
        [('greek', 'Αθήνα'), ('cyrillic', 'Москва')]);
    editor.setChoiceFieldStyle(choice, font: PdfEmbeddedFont.parse(fontBytes));
    editor.setChoiceValue(choice, 'cyrillic');
    final output = PdfDocument.open(editor.save());
    final form = PdfAcroForm.of(output)!;
    expect(form.fieldNamed('name')!.value, 'Жук Αθήνα');
    expect(form.fieldNamed('city')!.value, 'cyrillic');
    for (final (name, expected) in [('name', '<0416>'), ('city', '<041c>')]) {
      final widget = form.fieldNamed(name)!.widgets.single;
      final ap = output.cos.resolve(widget['AP']) as CosDictionary;
      final appearance = output.cos.resolve(ap['N']) as CosStream;
      final resources = output.cos.resolve(appearance.dictionary['Resources'])
          as CosDictionary;
      final fonts = output.cos.resolve(resources['Font']) as CosDictionary;
      final type0 =
          output.cos.resolve(fonts.entries.values.single) as CosDictionary;
      expect(_unicodeMap(output, type0).toLowerCase(),
          contains(expected.toLowerCase()));
      expect(latin1.decode(output.cos.decodeStreamData(appearance)),
          contains('> Tj'));
    }
  });
}
