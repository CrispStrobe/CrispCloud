import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/quds_office_engine_optional.dart';
import 'package:test/test.dart';

void main() {
  test('OfficeFontResolver picks covering primary and fallbacks', () {
    final SfntFont? latin = _tryLatin();
    final SfntFont? arabic = _tryArabic();
    if (latin == null) {
      markTestSkipped('No Latin TTF available');
      return;
    }
    if (arabic == null) {
      final OfficeFontSet single = OfficeFontResolver.covering(
        <String>['Hello'],
        <SfntFont>[latin],
      );
      expect(single.primary, same(latin));
      expect(single.fallbacks, isEmpty);
      return;
    }
    final OfficeFontSet set = OfficeFontResolver.covering(
      <String>['Hello', 'مرحبا'],
      <SfntFont>[latin, arabic],
    );
    expect(set.primary, isNotNull);
    expect(set.embeddable.length, greaterThanOrEqualTo(1));
    expect(set.faceFor('H'.runes.first), isNotNull);
    expect(set.faceFor('م'.runes.first), isNotNull);
  });

  test('multi-face PDF embeds distinct font resources', () {
    final SfntFont? latin = _tryLatin();
    final SfntFont? arabic = _tryArabic();
    if (latin == null || arabic == null) {
      markTestSkipped('Need Latin + Arabic TTF for multi-face embed');
      return;
    }
    if (latin.glyphIdFor('م'.runes.first) != 0) {
      markTestSkipped('Latin face already covers Arabic; cannot force F3');
      return;
    }
    final WmlDocument doc = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          blocks: <WmlBlock>[
            WmlParagraph(
              inlines: <WmlInline>[
                WmlRun(text: 'Hello '),
                WmlRun(text: 'مرحبا'),
              ],
            ),
          ],
        ),
      ],
    );
    final Uint8List pdf = OfficePdfExport.word(
      doc,
      fonts: OfficeFontSet(primary: latin, fallbacks: <SfntFont>[arabic]),
      title: 'MultiFace',
    );
    final String ascii = utf8.decode(pdf, allowMalformed: true);
    expect(ascii, contains('/F1'));
    expect(ascii, contains('/F3'));
    expect('/FontFile2'.allMatches(ascii).length, greaterThanOrEqualTo(2));
  });

  test('PdfSaveOptions emits PDF/A and tagged catalog markers', () {
    final PdfDocument pdf = PdfDocument(title: 'Tagged', author: 'Wave4');
    final PdfCanvas canvas = PdfCanvas(200, 200);
    canvas.fillRect(0, 0, 200, 200, 'FFFFFF');
    canvas.showLatin(
      x: 20,
      y: 40,
      fontSize: 12,
      text: 'Hi',
      color: '000000',
    );
    canvas.endText();
    pdf.addPage(
      PdfPage(width: 200, height: 200, content: canvas.toStream()),
    );
    pdf.addOutline(const PdfOutlineItem(title: 'Intro', pageIndex: 0));
    final Uint8List bytes = pdf.save(
      options: const PdfSaveOptions(pdfA: true, tagged: true),
    );
    final String ascii = utf8.decode(bytes, allowMalformed: true);
    expect(ascii, contains('/Metadata'));
    expect(ascii, contains('/OutputIntent'));
    expect(ascii, contains('/MarkInfo'));
    expect(ascii, contains('/StructTreeRoot'));
    expect(ascii, contains('pdfaid:part'));
    expect(ascii, contains('Intro'));
  });

  test('optional PptxMediaIo syncs media parts', () {
    final PmlPresentation deck = PmlPresentation(
      slides: <PmlSlide>[
        PmlSlide(
          id: 256,
          shapes: <PmlShape>[
            PmlShape(
              id: 2,
              name: 'Clip',
              mediaName: 'clip.mp4',
              mediaBytes: <int>[1, 2, 3, 4],
              transform: const PmlTransform(
                x: 0,
                y: 0,
                cx: 1000000,
                cy: 1000000,
              ),
            ),
          ],
        ),
      ],
    );
    final OpcPackage package = SlideSerializer().write(deck);
    final Map<PmlShape, String> ids = PptxMediaIo.sync(deck, package);
    expect(ids, isNotEmpty);
    final PackagePart? part = package.getPart('/ppt/media/clip.mp4');
    expect(part, isNotNull);
    expect(part!.readBytes(), <int>[1, 2, 3, 4]);

    deck.slides.first.shapes.first.mediaBytes.clear();
    PptxMediaIo.hydrate(deck, package);
    expect(deck.slides.first.shapes.first.mediaBytes, <int>[1, 2, 3, 4]);
  });
}

SfntFont? _tryLatin() {
  SfntFont? any;
  for (final String path in <String>[
    r'C:\Windows\Fonts\consola.ttf',
    r'C:\Windows\Fonts\cour.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf',
    r'C:\Windows\Fonts\arial.ttf',
    r'C:\Windows\Fonts\calibri.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  ]) {
    final SfntFont? font = _tryPath(path);
    if (font == null) {
      continue;
    }
    any ??= font;
    // Prefer a face that does not cover Arabic so a fallback is required.
    if (font.glyphIdFor('م'.runes.first) == 0) {
      return font;
    }
  }
  return any;
}

SfntFont? _tryArabic() {
  for (final String path in <String>[
    '/usr/share/fonts/truetype/noto/NotoNaskhArabic-Regular.ttf',
    r'C:\Windows\Fonts\NotoNaskhArabic-Regular.ttf',
    r'C:\Windows\Fonts\arial.ttf',
    r'C:\Windows\Fonts\tahoma.ttf',
  ]) {
    final SfntFont? font = _tryPath(path);
    if (font != null && font.glyphIdFor('م'.runes.first) != 0) {
      return font;
    }
  }
  return null;
}

SfntFont? _tryPath(String path) {
  if (!File(path).existsSync()) {
    return null;
  }
  return SfntFont.parse(File(path).readAsBytesSync());
}
