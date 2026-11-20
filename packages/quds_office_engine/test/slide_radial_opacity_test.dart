import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _stops =
    '<a:gsLst><a:gs pos="0"><a:srgbClr val="FF0000"/></a:gs>'
    '<a:gs pos="50000"><a:srgbClr val="00FF00"/></a:gs>'
    '<a:gs pos="100000"><a:srgbClr val="0000FF"/></a:gs></a:gsLst>';
const _focus = '<a:fillToRect l="50000" t="50000" r="50000" b="50000"/>';
const _radial =
    '<a:gradFill>$_stops<a:path path="circle">$_focus</a:path></a:gradFill>';

List<PmlShape> _parseFills(List<String> fills) => parseSlideShapes(
  '<p:sld xmlns:p="${OfficeNamespaces.p}" xmlns:a="${OfficeNamespaces.a}">'
  '<p:cSld><p:spTree>'
  '${[for (var i = 0; i < fills.length; i++) '<p:sp><p:nvSpPr><p:cNvPr id="${i + 2}" name="Gradient"/></p:nvSpPr><p:spPr>${fills[i]}</p:spPr></p:sp>'].join()}'
  '</p:spTree></p:cSld></p:sld>',
);

PmlPresentation _background(String fill) {
  final package = OpcPackage.openBytes(
    SlideSerializer().writeBytes(PmlPresentation(slides: [PmlSlide(id: 256)])),
  );
  package
      .getPart('/ppt/slides/slide1.xml')!
      .writeText(
        '<p:sld xmlns:p="${OfficeNamespaces.p}" xmlns:a="${OfficeNamespaces.a}">'
        '<p:cSld><p:bg><p:bgPr>$fill</p:bgPr></p:bg><p:spTree/></p:cSld></p:sld>',
      );
  return SlideDeserializer().read(package);
}

PmlShape _shape() => PmlShape(
  id: 2,
  name: 'Radial',
  fillColor: 'FF0000',
  gradient: PmlGradientFill(
    radial: true,
    stops: [
      PmlGradientStop(position: 0, color: 'FF0000'),
      PmlGradientStop(position: 0.5, color: '00FF00'),
      PmlGradientStop(position: 1, color: '0000FF'),
    ],
  ),
  transform: const PmlTransform(x: 0, y: 0, cx: 1270000, cy: 635000),
);

OfficeVisual _picture({int pixelAlpha = 128}) => OfficeVisual(
  kind: OfficeVisualKind.picture,
  width: 80,
  height: 40,
  imageBytes: PngBytes.rgba(
    width: 1,
    height: 1,
    plot: (_, _, rgba) {
      rgba[0] = 255;
      rgba[3] = pixelAlpha;
    },
  ),
  picture: PictureAdjust(transparency: 0.5),
);

void main() {
  test(
    'centered circle gradients parse without contaminating the next fill',
    () {
      final shapes = _parseFills([
        _radial,
        '<a:gradFill>$_stops<a:lin ang="5400000"/></a:gradFill>',
        _radial
            .replaceAll('50000" ', '50%" ')
            .replaceFirst('b="50000"', 'b="50%"'),
      ]);
      expect(shapes.map((shape) => shape.gradient!.radial), [
        true,
        false,
        true,
      ]);
      expect(shapes[1].gradient!.angleDegrees, 90);
      final copy = shapes.first.copy();
      copy.gradient!.stops.removeLast();
      expect(copy.gradient!.radial, isTrue);
      expect(shapes.first.gradient!.stops, hasLength(3));
    },
  );

  for (final entry in <String, String>{
    'rectangular path': _radial.replaceFirst('path="circle"', 'path="rect"'),
    'shape path': _radial.replaceFirst('path="circle"', 'path="shape"'),
    'off-center focus': _radial.replaceFirst('l="50000"', 'l="25000"'),
    'custom tile': _radial.replaceFirst(
      '</a:gradFill>',
      '<a:tileRect l="1000"/></a:gradFill>',
    ),
  }.entries) {
    test(
      '${entry.key} retains the solid fallback in shapes and backgrounds',
      () {
        final shape = _parseFills([entry.value]).single;
        expect(shape.gradient, isNull);
        expect(shape.fillColor, 'FF0000');
        final background = _background(entry.value).slides.single;
        expect(background.backgroundGradient, isNull);
        expect(background.background, 'FF0000');
      },
    );
  }

  test(
    'omitted circle focus uses the Office default center in shapes and backgrounds',
    () {
      final fill = _radial.replaceFirst(_focus, '');
      expect(_parseFills([fill]).single.gradient!.radial, isTrue);
      expect(
        _background(fill).slides.single.backgroundGradient!.gradient!.radial,
        isTrue,
      );
    },
  );

  test(
    'native radial gradient survives repeated saves and a fresh deck copy',
    () {
      var deck = PmlPresentation(
        slides: [
          PmlSlide(id: 256, shapes: [_shape()]),
        ],
      );
      for (var i = 0; i < 3; i++) {
        final bytes = SlideSerializer().writeBytes(deck);
        final xml = OpcPackage.openBytes(
          bytes,
        ).getPart('/ppt/slides/slide1.xml')!.readText();
        expect(xml, contains('path="circle"'));
        expect(xml, contains('l="50000"'));
        expect(xml, isNot(contains('<a:lin')));
        final shape = SlideDeserializer()
            .readBytes(bytes)
            .slides
            .single
            .shapes
            .single;
        expect(shape.gradient!.radial, isTrue);
        expect(shape.gradient!.stops.map((stop) => stop.position), [0, 0.5, 1]);
        deck = PmlPresentation(
          slides: [
            PmlSlide(id: 256, shapes: [shape.copy()]),
          ],
        );
      }
    },
  );

  test('imported centered radial background remains radial through saves', () {
    var deck = _background(_radial);
    for (var i = 0; i < 3; i++) {
      expect(deck.slides.single.backgroundGradient!.gradient!.radial, isTrue);
      expect(deck.slides.single.backgroundShapes, hasLength(1));
      deck = SlideDeserializer().readBytes(SlideSerializer().writeBytes(deck));
    }
  });

  test('radial PDF paints concentric rings with every color stop', () {
    final file = PdfFile.open(
      OfficePdfExport.presentation(
        PmlPresentation(
          slides: [
            PmlSlide(id: 256, shapes: [_shape()]),
          ],
        ),
      ),
    );
    final rings = file
        .displayList(0)
        .ops
        .whereType<PdfFillPath>()
        .where(
          (op) => op.points.any((point) => point.kind == PdfPathKind.cubic),
        )
        .toList();
    expect(rings, hasLength(72));
    expect(rings.first.color, 0xFF0000FF);
    expect((rings.last.color >> 16) & 255, greaterThan(245));
    expect(rings.any((ring) => ((ring.color >> 8) & 255) > 245), isTrue);
    for (final ring in [rings.first, rings[36], rings.last]) {
      final xs =
          ring.points
              .where((point) => point.kind != PdfPathKind.close)
              .map((point) => point.x)
              .toList()
            ..sort();
      final ys =
          ring.points
              .where((point) => point.kind != PdfPathKind.close)
              .map((point) => point.y)
              .toList()
            ..sort();
      expect((xs.first + xs.last) / 2, closeTo(50, 0.01));
      expect((ys.first + ys.last) / 2, closeTo(25, 0.01));
      expect(xs.last - xs.first, closeTo(ys.last - ys.first, 0.01));
    }
  });

  for (final format in ['word', 'workbook', 'presentation']) {
    test(
      '$format PDF registers picture opacity and combines it with PNG alpha',
      () {
        final picture = _picture();
        final Uint8List bytes;
        if (format == 'word') {
          bytes = OfficePdfExport.word(
            WmlDocument(
              sections: [
                WmlSection(blocks: [WmlVisual(visual: picture)]),
              ],
            ),
          );
        } else if (format == 'workbook') {
          final book = SmlWorkbook();
          book.firstSheet.cellA1('A1').value = 'Picture';
          book.firstSheet.drawings.add(
            SmlDrawing(visual: picture, col: 0, row: 1),
          );
          bytes = OfficePdfExport.workbook(book);
        } else {
          bytes = OfficePdfExport.presentation(
            PmlPresentation(
              slides: [
                PmlSlide(id: 256, shapes: [_shape()..visual = picture]),
              ],
            ),
          );
        }
        final image = PdfFile.open(
          bytes,
        ).displayList(0).ops.whereType<PdfDrawImage>().single;
        expect(image.hasAlpha, isTrue);
        expect(image.bytes[3], closeTo(64, 1));
      },
    );
  }

  test(
    'picture opacity restores its caller and keeps the border outside its state',
    () {
      final canvas = PdfCanvas(200, 100)..setAlpha(0.25);
      final images = <PdfEmbeddedImage>[];
      final picture = _picture(pixelAlpha: 255);
      picture.picture
        ..cropLeft = 0.25
        ..borderWidth = 2
        ..borderColor = '00FF00';
      OfficePdfVisuals.paint(
        canvas,
        10,
        10,
        80,
        40,
        picture,
        images,
        drawText: (_, _, _, _, _) {},
      );
      canvas.fillRect(100, 10, 20, 20, '0000FF');
      final doc = PdfDocument()
        ..addPage(
          PdfPage(
            width: 200,
            height: 100,
            content: canvas.toStream(),
            images: images,
            extGStates: canvas.alphaStates,
          ),
        );
      final ops = PdfFile.open(doc.save()).displayList(0).ops;
      expect(ops.whereType<PdfDrawImage>().single.bytes[3], closeTo(128, 1));
      expect(ops.whereType<PdfStrokePath>().single.color >> 24, closeTo(64, 1));
      expect(ops.whereType<PdfFillPath>().last.color >> 24, closeTo(64, 1));
      expect(canvas.alphaStates, {'GS250', 'GS500'});
    },
  );

  test('PDF alpha states reject invalid names and non-finite values', () {
    final canvas = PdfCanvas(20, 20);
    for (final alpha in [
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      expect(() => canvas.setAlpha(alpha), throwsArgumentError);
    }
    for (final name in ['Other', 'GS-1', 'GS1001', 'GS0500', 'GS500/Other']) {
      final doc = PdfDocument()
        ..addPage(
          PdfPage(
            width: 20,
            height: 20,
            content: canvas.toStream(),
            extGStates: {name},
          ),
        );
      expect(doc.save, throwsArgumentError);
    }
  });
}
