import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  for (final bool cropped in <bool>[false, true]) {
    test(
      'PPT picture opacity is resource-backed and scoped, crop=$cropped',
      () {
        final OfficeVisual translucent = _picture(alpha: 128);
        translucent.picture
          ..transparency = 0.5
          ..cropLeft = cropped ? 0.25 : 0
          ..borderColor = 'CC3300'
          ..borderWidth = 2;
        final PmlPresentation deck = PmlPresentation(
          slides: <PmlSlide>[
            PmlSlide(
              id: 256,
              shapes: <PmlShape>[
                _shape(2, translucent),
                _shape(3, _picture(alpha: 128)),
              ],
            ),
          ],
        );
        final PdfDisplayList page = PdfFile.open(
          OfficePdfExport.presentation(deck),
        ).displayList(0);
        final List<PdfDrawImage> images = page.ops
            .whereType<PdfDrawImage>()
            .toList();
        expect(images, hasLength(2));
        expect(images.first.hasAlpha, isTrue);
        expect(images.first.bytes[3], closeTo(64, 1));
        expect(images.last.bytes[3], 128);
        final PdfStrokePath border = page.ops
            .whereType<PdfStrokePath>()
            .singleWhere(
              (PdfStrokePath op) => (op.color & 0xFFFFFF) == 0xCC3300,
            );
        expect(border.color >> 24, 255);
      },
    );
  }

  test(
    'picture restores the caller opacity before its border and later paint',
    () {
      final PdfCanvas canvas = PdfCanvas(200, 200)..setAlpha(0.25);
      final List<PdfEmbeddedImage> images = <PdfEmbeddedImage>[];
      final OfficeVisual picture = _picture(alpha: 255);
      picture.picture
        ..transparency = 0.5
        ..borderColor = 'CC3300'
        ..borderWidth = 2;
      OfficePdfVisuals.paint(
        canvas,
        10,
        20,
        50,
        40,
        picture,
        images,
        drawText:
            (String text, double x, double y, double size, String color) {},
      );
      canvas.fillRect(80, 20, 50, 40, '224466');
      final PdfDocument document = PdfDocument()
        ..addPage(
          PdfPage(
            width: 200,
            height: 200,
            content: canvas.toStream(),
            images: images,
            extGStates: canvas.alphaStates,
          ),
        );
      final PdfDisplayList page = PdfFile.open(document.save()).displayList(0);
      expect(
        page.ops.whereType<PdfDrawImage>().single.bytes[3],
        closeTo(128, 1),
      );
      expect(
        page.ops.whereType<PdfStrokePath>().single.color >> 24,
        closeTo(64, 1),
      );
      expect(
        page.ops.whereType<PdfFillPath>().last.color >> 24,
        closeTo(64, 1),
      );
      expect(canvas.alphaStates, <String>{'GS250', 'GS500'});
    },
  );
}

OfficeVisual _picture({required int alpha}) => OfficeVisual(
  kind: OfficeVisualKind.picture,
  imageBytes: PngBytes.rgba(
    width: 2,
    height: 2,
    plot: (int x, int y, List<int> rgba) {
      rgba
        ..[0] = 100
        ..[1] = 150
        ..[2] = 200
        ..[3] = alpha;
    },
  ),
);

PmlShape _shape(int id, OfficeVisual visual) => PmlShape(
  id: id,
  name: 'Picture $id',
  transform: PmlTransform(
    x: (id - 2) * 100 * 12700,
    cx: 50 * 12700,
    cy: 40 * 12700,
  ),
  visual: visual,
);
