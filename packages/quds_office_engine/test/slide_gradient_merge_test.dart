import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _gradientXml =
    '<a:gradFill><a:gsLst>'
    '<a:gs pos="0"><a:srgbClr val="FF0000"/></a:gs>'
    '<a:gs pos="50000"><a:srgbClr val="00FF00"/></a:gs>'
    '<a:gs pos="100000"><a:srgbClr val="0000FF"/></a:gs>'
    '</a:gsLst><a:lin ang="0"/></a:gradFill>';

PmlGradientFill _gradient() => PmlGradientFill(
  stops: [
    PmlGradientStop(position: 0, color: 'FF0000'),
    PmlGradientStop(position: 0.5, color: '00FF00'),
    PmlGradientStop(position: 1, color: '0000FF'),
  ],
);

PmlShape _shape() => PmlShape(
  id: 2,
  name: 'Gradient',
  fillColor: 'FF0000',
  gradient: _gradient(),
  transform: const PmlTransform(x: 0, y: 0, cx: 1270000, cy: 635000),
);

void main() {
  test('three-stop gradient is copied and round-tripped independently', () {
    final PmlShape original = _shape();
    final PmlShape copy = original.copy();
    copy.gradient!.stops.removeLast();
    expect(original.gradient!.stops, hasLength(3));
    final PmlShape saved = SlideDeserializer()
        .readBytes(
          SlideSerializer().writeBytes(
            PmlPresentation(
              slides: [
                PmlSlide(id: 256, shapes: [original]),
              ],
            ),
          ),
        )
        .slides
        .single
        .shapes
        .single;
    expect(saved.gradient!.stops.map((stop) => stop.color), [
      'FF0000',
      '00FF00',
      '0000FF',
    ]);
    expect(saved.gradient!.stops.map((stop) => stop.position), [0, 0.5, 1]);
  });

  test('a later text gradient does not borrow a preceding shape fill', () {
    final shapes = parseSlideShapes(
      '<p:sld xmlns:p="${OfficeNamespaces.p}" xmlns:a="${OfficeNamespaces.a}">'
      '<p:cSld><p:spTree>'
      '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Gradient"/></p:nvSpPr>'
      '<p:spPr>$_gradientXml</p:spPr></p:sp>'
      '<p:sp><p:nvSpPr><p:cNvPr id="3" name="Text"/></p:nvSpPr>'
      '<p:spPr><a:solidFill><a:srgbClr val="FFFFFF"/></a:solidFill></p:spPr>'
      '<p:txBody><a:p><a:r><a:rPr>$_gradientXml</a:rPr>'
      '<a:t>Text</a:t></a:r></a:p></p:txBody></p:sp>'
      '</p:spTree></p:cSld></p:sld>',
    );
    expect(shapes.first.gradient!.stops, hasLength(3));
    expect(shapes.last.gradient, isNull);
    expect(shapes.last.fillColor, 'FFFFFF');
  });

  test('centered path gradient retains radial stops and solid fallback', () {
    final String pathFill = _gradientXml.replaceFirst(
      '<a:lin ang="0"/>',
      '<a:path path="circle"><a:fillToRect '
          'l="50000" t="50000" r="50000" b="50000"/></a:path>',
    );
    final PmlShape shape = parseSlideShapes(
      '<p:sld xmlns:p="${OfficeNamespaces.p}" xmlns:a="${OfficeNamespaces.a}">'
      '<p:cSld><p:spTree><p:sp><p:spPr>$pathFill</p:spPr>'
      '</p:sp></p:spTree></p:cSld></p:sld>',
    ).single;
    expect(shape.gradient!.radial, isTrue);
    expect(shape.gradient!.stops.map((stop) => stop.color), [
      'FF0000',
      '00FF00',
      '0000FF',
    ]);
    expect(shape.gradient!.stops.map((stop) => stop.position), [0, 0.5, 1]);
    expect(shape.fillColor, 'FF0000');
  });

  test('picture shadow precedes the image in PDF export', () {
    final PmlShape shape = _shape()
      ..gradient = null
      ..visual = OfficeVisual(
        kind: OfficeVisualKind.picture,
        imageBytes: PngBytes.rgb(
          width: 1,
          height: 1,
          plot: (_, _, rgb) {
            rgb[0] = 255;
          },
        ),
        picture: PictureAdjust(shadow: true),
      );
    final PdfFile pdf = PdfFile.open(
      OfficePdfExport.presentation(
        PmlPresentation(
          slides: [
            PmlSlide(id: 256, shapes: [shape]),
          ],
        ),
      ),
    );
    final ops = pdf.displayList(0).ops;
    final int shadow = ops.indexWhere(
      (op) => op is PdfFillPath && op.color == 0xFFB0B0B0,
    );
    final int image = ops.indexWhere((op) => op is PdfDrawImage);
    expect(shadow, greaterThanOrEqualTo(0));
    expect(image, greaterThan(shadow));
    expect(
      ops.whereType<PdfFillPath>().where((op) => op.color == 0xFFB0B0B0),
      hasLength(1),
    );
  });

  test('PDF receives gradient colors across every authored stop', () {
    final PdfFile pdf = PdfFile.open(
      OfficePdfExport.presentation(
        PmlPresentation(
          slides: [
            PmlSlide(id: 256, shapes: [_shape()]),
          ],
        ),
      ),
    );
    final colors = pdf
        .displayList(0)
        .ops
        .whereType<PdfFillPath>()
        .map((fill) => fill.color)
        .toSet();
    expect(colors.length, greaterThan(16));
    expect(
      colors.any((c) => ((c >> 16) & 255) > 220 && (c & 255) < 30),
      isTrue,
    );
    expect(colors.any((c) => ((c >> 8) & 255) > 220 && (c & 255) < 30), isTrue);
    expect(
      colors.any((c) => (c & 255) > 220 && ((c >> 16) & 255) < 30),
      isTrue,
    );
  });

  test(
    'gradient on connector keeps stroke geometry instead of a filled box',
    () {
      final PmlShape connector = _shape()..preset = PmlShapePreset.connector;
      final PdfFile pdf = PdfFile.open(
        OfficePdfExport.presentation(
          PmlPresentation(
            slides: [
              PmlSlide(id: 256, shapes: [connector]),
            ],
          ),
        ),
      );
      expect(pdf.displayList(0).ops.whereType<PdfStrokePath>(), hasLength(1));
      final fills = pdf.displayList(0).ops.whereType<PdfFillPath>();
      expect(fills.where((fill) => fill.color != 0xFFFFFFFF), isEmpty);
    },
  );
}
