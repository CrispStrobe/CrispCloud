import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import 'support/pdf_alias_fixture.dart';

PmlShape _import(String preset, {int width = 100, int height = 100}) =>
    parseSlideShapes(
      '<p:sld xmlns:p="${OfficeNamespaces.p}" '
      'xmlns:a="${OfficeNamespaces.a}"><p:cSld><p:spTree><p:sp>'
      '<p:nvSpPr><p:cNvPr id="2" name="Geometry"/>'
      '<p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr>'
      '<a:xfrm><a:off x="127000" y="254000"/>'
      '<a:ext cx="${width * 12700}" cy="${height * 12700}"/></a:xfrm>'
      '<a:prstGeom prst="$preset"><a:avLst/></a:prstGeom>'
      '<a:solidFill><a:srgbClr val="0000FF"/></a:solidFill>'
      '<a:ln w="25400"><a:solidFill><a:srgbClr val="FF0000"/>'
      '</a:solidFill></a:ln></p:spPr></p:sp></p:spTree></p:cSld></p:sld>',
    ).single;

List<PdfPathVerb> _vertices(List<PdfPathVerb> path) => path
    .where((point) => point.kind != PdfPathKind.close)
    .toList(growable: false);

List<double> _turns(List<PdfPathVerb> vertices) => [
  for (var i = 0; i < vertices.length; i++)
    (vertices[(i + 1) % vertices.length].x - vertices[i].x) *
            (vertices[(i + 2) % vertices.length].y -
                vertices[(i + 1) % vertices.length].y) -
        (vertices[(i + 1) % vertices.length].y - vertices[i].y) *
            (vertices[(i + 2) % vertices.length].x -
                vertices[(i + 1) % vertices.length].x),
];

void main() {
  final SfntFont font = aliasTestFont();
  List<PdfPaintOp> export(PmlShape shape) => PdfFile.open(
    OfficePdfExport.presentation(
      PmlPresentation(
        slides: [
          PmlSlide(id: 256, shapes: [shape]),
        ],
      ),
      font: font,
    ),
  ).displayList(0).ops;

  for (final String preset in [
    'diamond',
    'hexagon',
    'pentagon',
    'homePlate',
    'chevron',
    'parallelogram',
    'trapezoid',
  ]) {
    test('$preset identity survives import, copy and PPTX round trip', () {
      final PmlShape shape = _import(preset);
      expect(shape.preset.name, preset);
      final PmlShape copied = shape.copy(id: 3);
      expect(copied.preset, shape.preset);
      final PmlSlide slide = PmlSlide(id: 256, shapes: [copied]);
      expect(slideToXml(slide), contains('prst="$preset"'));
      final PmlShape reopened = SlideDeserializer()
          .readBytes(
            SlideSerializer().writeBytes(PmlPresentation(slides: [slide])),
          )
          .slides
          .single
          .shapes
          .single;
      expect(reopened.preset.name, preset);
    });
  }

  test('pentagon PDF fill and outline have five convex vertices', () {
    final List<PdfPaintOp> ops = export(_import('pentagon'));
    final PdfFillPath fill = ops.whereType<PdfFillPath>().singleWhere(
      (op) => op.color == 0xFF0000FF,
    );
    final PdfStrokePath stroke = ops.whereType<PdfStrokePath>().single;
    final List<PdfPathVerb> points = _vertices(fill.points);
    expect(points, hasLength(5));
    expect(_turns(points), everyElement(greaterThan(0)));
    expect(
      points.where((point) => (point.y - 20).abs() < 0.001).single.x,
      closeTo(60, 0.001),
    );
    expect(
      points.where((point) => (point.y - 120).abs() < 0.001),
      hasLength(2),
    );
    expect(
      stroke.points.map((point) => (point.kind, point.x, point.y)),
      fill.points.map((point) => (point.kind, point.x, point.y)),
    );
    expect(stroke.color, 0xFFFF0000);
    expect(stroke.width, closeTo(2, 0.001));
  });

  for (final (int width, int height) in [(100, 100), (200, 80)]) {
    test('homePlate PDF keeps a flat back at $width by $height', () {
      final PdfStrokePath stroke = export(
        _import('homePlate', width: width, height: height),
      ).whereType<PdfStrokePath>().single;
      final List<PdfPathVerb> points = _vertices(stroke.points);
      expect(points, hasLength(5));
      expect(_turns(points), everyElement(greaterThan(0)));
      expect(points.map((point) => (point.x, point.y)), [
        (10.0, 20.0),
        (10 + width - height / 2, 20.0),
        (10.0 + width, 20 + height / 2),
        (10 + width - height / 2, 20.0 + height),
        (10.0, 20.0 + height),
      ]);
    });
  }

  test('chevron retains six vertices and its inward notch', () {
    final PdfStrokePath stroke = export(
      _import('chevron'),
    ).whereType<PdfStrokePath>().single;
    final List<PdfPathVerb> points = _vertices(stroke.points);
    expect(points, hasLength(6));
    expect(_turns(points).where((turn) => turn < 0), hasLength(1));
  });
}
