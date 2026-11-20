import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

OfficeVisual _picture() {
  final picture = OfficeVisual(
    kind: OfficeVisualKind.picture,
    width: 80,
    height: 40,
    imageBytes: PngBytes.rgba(
      width: 2,
      height: 1,
      plot: (x, y, rgba) {
        rgba[0] = 200;
        rgba[1] = 100;
        rgba[2] = 50;
        rgba[3] = x == 0 ? 128 : 255;
      },
    ),
  );
  picture.picture
    ..transparency = 0.5
    ..borderColor = 'CC3300'
    ..borderWidth = 2;
  return picture;
}

void main() {
  for (final word in [false, true]) {
    test(
      'exported ${word ? 'Word' : 'slide'} opacity composes with PNG alpha',
      () {
        final picture = _picture();
        final Uint8List bytes;
        if (word) {
          bytes = OfficePdfExport.word(
            WmlDocument(
              sections: [
                WmlSection(blocks: [WmlVisual(visual: picture)]),
              ],
            ),
          );
        } else {
          bytes = OfficePdfExport.presentation(
            PmlPresentation(
              slides: [
                PmlSlide(
                  id: 256,
                  shapes: [
                    PmlShape(
                      id: 2,
                      name: 'Transparent picture',
                      transform: const PmlTransform(
                        cx: 80 * 12700,
                        cy: 40 * 12700,
                      ),
                      visual: picture,
                    ),
                  ],
                ),
              ],
            ),
          );
        }
        final ops = PdfFile.open(bytes).displayList(0).ops;
        final image = ops.whereType<PdfDrawImage>().single;
        expect(image.hasAlpha, isTrue);
        expect(image.bytes[3], 64);
        expect(image.bytes[7], 128);
        final border = ops.whereType<PdfStrokePath>().singleWhere(
          (op) => op.color & 0x00ffffff == 0x00cc3300,
        );
        expect(border.color >>> 24, 255);
      },
    );
  }

  test('picture opacity restores the caller graphics state', () {
    final canvas = PdfCanvas(100, 100)..setAlpha(0.3);
    final images = <PdfEmbeddedImage>[];
    OfficePdfVisuals.paint(
      canvas,
      0,
      0,
      80,
      40,
      _picture(),
      images,
      drawText: (text, x, y, size, color) {},
    );
    canvas.fillRect(0, 60, 20, 20, 'FF0000');
    final document = PdfDocument()
      ..addPage(
        PdfPage(
          width: 100,
          height: 100,
          content: canvas.toStream(),
          images: images,
          extGStates: canvas.alphaStates,
        ),
      );
    final fill = PdfFile.open(
      document.save(),
    ).displayList(0).ops.whereType<PdfFillPath>().single;
    expect(fill.color >>> 24, 77);
  });
}
