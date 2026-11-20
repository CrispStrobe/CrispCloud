import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

PmlPresentation _richDeck() {
  final OpcPackage package = OpcPackage.create(OpcPackageKind.slide);
  package
      .getPart('/ppt/slides/slide1.xml')!
      .writeText(
        '<p:sld xmlns:p="${OfficeNamespaces.p}" xmlns:a="${OfficeNamespaces.a}">'
        '<p:cSld><p:spTree><p:sp><p:nvSpPr><p:cNvPr id="2" name="Text"/>'
        '<p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm>'
        '<a:off x="381000" y="508000"/><a:ext cx="3810000" cy="1270000"/>'
        '</a:xfrm><a:noFill/></p:spPr><p:txBody><a:bodyPr/><a:p>'
        '<a:pPr algn="l" rtl="0"/><a:r><a:rPr sz="1200">'
        '<a:solidFill><a:srgbClr val="FF0000"/></a:solidFill></a:rPr>'
        '<a:t>Imported text</a:t></a:r></a:p></p:txBody></p:sp>'
        '</p:spTree></p:cSld></p:sld>',
      );
  return SlideDeserializer().read(package);
}

String _pageStreams(Uint8List pdf) {
  final String bytes = String.fromCharCodes(pdf);
  final StringBuffer streams = StringBuffer();
  var from = 0;
  while (true) {
    final int marker = bytes.indexOf('stream\n', from);
    if (marker < 0) break;
    final int start = marker + 'stream\n'.length;
    final int end = bytes.indexOf('\nendstream', start);
    if (end < 0) break;
    final Uint8List compressed = Uint8List.sublistView(pdf, start, end);
    if (compressed.isNotEmpty && compressed.first == 0x78) {
      streams.write(String.fromCharCodes(PdfFlate.decompress(compressed)));
    }
    from = end + '\nendstream'.length;
  }
  return streams.toString();
}

void main() {
  for (final PdfSlideExportMode mode in PdfSlideExportMode.values) {
    test(
      'PDF $mode inherits master paper and keeps an explicit slide color',
      () {
        final PmlPresentation deck = PmlPresentation(
          master: PmlMaster(name: 'Blue master', background: '0000FF'),
          slides: <PmlSlide>[
            PmlSlide(id: 256),
            PmlSlide(id: 257, background: 'FFFF00'),
          ],
        );
        final String content = _pageStreams(
          OfficePdfExport.presentation(deck, mode: mode),
        );
        expect(content, contains('0 0 1 rg'));
        expect(content, contains('1 1 0 rg'));
      },
    );
  }

  test('PDF uses an edited font size instead of the imported run snapshot', () {
    final PmlPresentation deck = _richDeck();
    final PmlShape shape = deck.slides.single.shapes.single;
    expect(shape.richText.single.runs.single.fontSizePt, 12);
    final String before = _pageStreams(OfficePdfExport.presentation(deck));
    shape.fontSizePt = 26;
    final String after = _pageStreams(OfficePdfExport.presentation(deck));
    expect(before, contains(' 12 Tf'));
    expect(after, contains(' 26 Tf'));
    expect(after, isNot(contains(' 12 Tf')));
  });

  test('PDF uses an edited ink color instead of the imported run snapshot', () {
    final PmlPresentation deck = _richDeck();
    final PmlShape shape = deck.slides.single.shapes.single;
    expect(shape.richText.single.runs.single.color, 'FF0000');
    shape.textColor = '0000FF';
    final String content = _pageStreams(OfficePdfExport.presentation(deck));
    expect(content, contains('0 0 1 rg'));
    expect(content, isNot(contains('1 0 0 rg')));
  });

  test('scalar alignment and direction edits invalidate the imported runs', () {
    final PmlShape shape = _richDeck().slides.single.shapes.single;
    expect(shape.hasCurrentRichText, isTrue);
    shape.textAlign = PmlTextAlign.center;
    expect(shape.hasCurrentRichText, isFalse);
    shape.textAlign = PmlTextAlign.left;
    expect(shape.hasCurrentRichText, isTrue);
    shape.rightToLeft = true;
    expect(shape.hasCurrentRichText, isFalse);
    expect(shape.copy().hasCurrentRichText, isFalse);
  });
}
