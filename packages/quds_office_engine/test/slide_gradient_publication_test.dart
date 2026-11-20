import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import 'support/pdf_alias_fixture.dart';

const _ns =
    'xmlns:p="${OfficeNamespaces.p}" xmlns:a="${OfficeNamespaces.a}" '
    'xmlns:r="${OfficeNamespaces.r}"';

String _gradient({int angle = 0, bool radial = false}) =>
    '<p:bg><p:bgPr><a:gradFill><a:gsLst>'
    '<a:gs pos="0"><a:srgbClr val="FF0000"/></a:gs>'
    '<a:gs pos="50000"><a:srgbClr val="00FF00"/></a:gs>'
    '<a:gs pos="100000"><a:srgbClr val="0000FF"/></a:gs>'
    '</a:gsLst>${radial ? '<a:path path="circle"><a:fillToRect '
              'l="50000" t="50000" r="50000" b="50000"/></a:path>' : '<a:lin ang="$angle" scaled="0"/>'}'
    '</a:gradFill></p:bgPr></p:bg>';

String _solid(String color) =>
    '<p:bg><p:bgPr><a:solidFill><a:srgbClr val="$color"/>'
    '</a:solidFill></p:bgPr></p:bg>';

String _part(String root, String background, {bool showMaster = true}) =>
    '<p:$root $_ns${showMaster ? '' : ' showMasterSp="0"'}><p:cSld>'
    '$background<p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/>'
    '<p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>'
    '${root == 'sldMaster' ? '<p:sp><p:nvSpPr><p:cNvPr id="2" '
              'name="Ordinary decoration"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>'
              '<p:spPr><a:xfrm><a:off x="127000" y="127000"/>'
              '<a:ext cx="127000" cy="127000"/></a:xfrm>'
              '<a:prstGeom prst="rect"/><a:solidFill>'
              '<a:srgbClr val="ABCDEF"/></a:solidFill></p:spPr></p:sp>' : ''}'
    '</p:spTree></p:cSld></p:$root>';

PmlPresentation _import({
  String master = '',
  String layout = '',
  String slide = '',
  bool showMaster = true,
}) {
  final package = OpcPackage.create(OpcPackageKind.slide);
  void put(String uri, String contentType, String xml) {
    final part = package.getPart(uri);
    if (part == null) {
      package.createPart(uri, contentType, utf8.encode(xml));
    } else {
      part.writeText(xml);
    }
  }

  const pres = '/ppt/presentation.xml';
  const masterUri = '/ppt/slideMasters/slideMaster1.xml';
  const layoutUri = '/ppt/slideLayouts/slideLayout1.xml';
  const slideUri = '/ppt/slides/slide1.xml';
  final rels = package.relationshipsFor(pres);
  for (final rel in rels.items.toList()) {
    rels.removeById(rel.id);
  }
  rels
    ..add(
      type: RelationshipTypes.slideMaster,
      target: 'slideMasters/slideMaster1.xml',
      id: 'rMaster',
    )
    ..add(
      type: RelationshipTypes.slide,
      target: 'slides/slide1.xml',
      id: 'rSlide',
    );
  put(
    pres,
    OfficeContentTypes.slideMain,
    '<p:presentation $_ns><p:sldMasterIdLst><p:sldMasterId '
    'id="2147483648" r:id="rMaster"/></p:sldMasterIdLst>'
    '<p:sldIdLst><p:sldId id="256" r:id="rSlide"/></p:sldIdLst>'
    '<p:sldSz cx="9144000" cy="5143500"/></p:presentation>',
  );
  put(masterUri, OfficeContentTypes.slideMaster, _part('sldMaster', master));
  put(layoutUri, OfficeContentTypes.slideLayout, _part('sldLayout', layout));
  put(
    slideUri,
    OfficeContentTypes.slide,
    _part('sld', slide, showMaster: showMaster),
  );
  package
      .relationshipsFor(masterUri)
      .add(
        type: RelationshipTypes.slideLayout,
        target: '../slideLayouts/slideLayout1.xml',
      );
  package
      .relationshipsFor(layoutUri)
      .add(
        type: RelationshipTypes.slideMaster,
        target: '../slideMasters/slideMaster1.xml',
      );
  package
      .relationshipsFor(slideUri)
      .add(
        type: RelationshipTypes.slideLayout,
        target: '../slideLayouts/slideLayout1.xml',
      );
  return SlideDeserializer().read(package);
}

PmlPresentation _reopen(PmlPresentation deck) =>
    SlideDeserializer().readBytes(SlideSerializer().writeBytes(deck));

PmlGradientFill _fill({double angle = 0, bool radial = false}) =>
    PmlGradientFill(
      stops: [
        PmlGradientStop(position: 0, color: 'FF0000'),
        PmlGradientStop(position: .5, color: '00FF00'),
        PmlGradientStop(position: 1, color: '0000FF'),
      ],
      angleDegrees: angle,
      radial: radial,
    );

PmlShape _shape({
  PmlShapePreset preset = PmlShapePreset.rect,
  double angle = 0,
  List<PmlPathPoint>? path,
}) => PmlShape(
  id: 2,
  name: 'Gradient',
  preset: preset,
  fillColor: 'FF0000',
  gradient: _fill(angle: angle),
  transform: const PmlTransform(
    x: 20 * 12700,
    y: 30 * 12700,
    cx: 200 * 12700,
    cy: 80 * 12700,
  ),
  path: path,
);

List<PdfPathVerb> _vertices(List<PdfPathVerb> points) =>
    points.where((p) => p.kind != PdfPathKind.close).toList();

void main() {
  final font = aliasTestFont();
  List<PdfPaintOp> export(PmlPresentation deck) => PdfFile.open(
    OfficePdfExport.presentation(deck, font: font),
  ).displayList(0).ops;
  List<PdfPaintOp> exportShape(PmlShape shape) => export(
    PmlPresentation(
      slides: [
        PmlSlide(id: 256, shapes: [shape]),
      ],
    ),
  );

  for (final (name, master, layout, slide, expected) in [
    ('master gradient', _gradient(), '', '', true),
    ('layout solid', _gradient(), _solid('112233'), '', false),
    ('slide solid', _gradient(), '', _solid('445566'), false),
    ('layout gradient', _solid('112233'), _gradient(), '', true),
    ('slide gradient', _solid('112233'), _solid('445566'), _gradient(), true),
  ]) {
    test('selected background respects $name ownership', () {
      final deck = _import(master: master, layout: layout, slide: slide);
      final page = deck.slides.single;
      expect(
        page.backgroundShapes.where((s) => s.isBackgroundGradient),
        hasLength(expected ? 1 : 0),
      );
      expect(page.shapes, isEmpty);
      expect(
        page.backgroundShapes.where((s) => s.name == 'Ordinary decoration'),
        hasLength(1),
      );
      final saved = _reopen(deck).slides.single;
      expect(
        saved.backgroundShapes.where((s) => s.isBackgroundGradient),
        hasLength(expected ? 1 : 0),
      );
      expect(saved.shapes, isEmpty);
    });
  }

  test('master-shape suppression retains the selected native gradient', () {
    final deck = _import(master: _gradient(), showMaster: false);
    expect(deck.slides.single.backgroundShapes, hasLength(1));
    expect(
      deck.slides.single.backgroundShapes.single.isBackgroundGradient,
      isTrue,
    );
    final reopened = _reopen(deck).slides.single;
    expect(reopened.showMasterShapes, isFalse);
    expect(reopened.backgroundShapes, hasLength(1));
    expect(reopened.backgroundShapes.single.isBackgroundGradient, isTrue);
  });

  for (final radial in [false, true]) {
    test(
      'native gradient keeps every stop and direction over three saves radial=$radial',
      () {
        var deck = _import(
          slide: _gradient(angle: 90 * 60000, radial: radial),
        );
        for (var cycle = 0; cycle < 3; cycle++) {
          final fill = deck.slides.single.backgroundGradient!.gradient!;
          expect(fill.stops.map((s) => (s.position, s.color)), [
            (0.0, 'FF0000'),
            (.5, '00FF00'),
            (1.0, '0000FF'),
          ]);
          expect(fill.radial, radial);
          if (!radial) expect(fill.angleDegrees, 90);
          final xml = slideToXml(deck.slides.single);
          expect(RegExp(r'<p:bg(?:\s|>)').hasMatch(xml), isTrue);
          expect(RegExp('<a:gs ').allMatches(xml), hasLength(3));
          expect(xml, isNot(contains('name="Background')));
          deck = _reopen(deck);
        }
      },
    );
  }

  test('copied inherited gradient persists in a fresh presentation', () {
    final original = _import(master: _gradient(angle: 45 * 60000));
    final copied = original.slides.single.copy(id: 300);
    final copyFill = copied.backgroundShapes
        .singleWhere((s) => s.isBackgroundGradient)
        .gradient!;
    copyFill.stops.add(PmlGradientStop(position: .75, color: '00FFFF'));
    expect(
      original.slides.single.backgroundShapes
          .singleWhere((s) => s.isBackgroundGradient)
          .gradient!
          .stops,
      hasLength(3),
    );
    copyFill.stops.removeLast();
    final fresh = _reopen(PmlPresentation(slides: [copied]));
    final gradient = fresh.slides.single.backgroundGradient!;
    expect(gradient.gradient!.stops, hasLength(3));
    expect(gradient.gradient!.angleDegrees, 45);
    expect(fresh.slides.single.shapes, isEmpty);
    expect(
      RegExp(r'<p:bg(?:\s|>)').hasMatch(slideToXml(fresh.slides.single)),
      isTrue,
    );
  });

  test(
    'same-package copy retains layout inheritance without local override',
    () {
      final deck = _import(master: _gradient());
      deck.slides.add(deck.slides.single.copy(id: 300));
      final saved = _reopen(deck);
      expect(saved.slides, hasLength(2));
      for (final slide in saved.slides) {
        expect(slide.inheritsMasterBackground, isTrue);
        expect(
          slide.backgroundShapes.where((s) => s.isBackgroundGradient),
          hasLength(1),
        );
        expect(slide.sourceBackground, isNull);
      }
    },
  );

  test(
    'master solid edit hides inherited gradient before save and retains decorations',
    () {
      final deck = _import(master: _gradient());
      expect(export(deck).whereType<PdfClipPath>(), isNotEmpty);
      deck.master.background = '112233';
      final after = export(deck);
      expect(after.whereType<PdfClipPath>(), isEmpty);
      expect(
        after.whereType<PdfFillPath>().map((s) => s.color),
        containsAll([0xFF112233, 0xFFABCDEF]),
      );
      final saved = _reopen(deck);
      expect(
        saved.slides.single.backgroundShapes.where((s) => s.isBackgroundFill),
        isEmpty,
      );
      expect(
        saved.slides.single.backgroundShapes.single.name,
        'Ordinary decoration',
      );
      expect(saved.slides.single.background, '112233');
    },
  );

  test('local gradient remains independent when the master changes', () {
    final deck = _import(
      master: _gradient(),
      slide: _gradient(angle: 90 * 60000),
    );
    deck.master.background = '112233';
    expect(export(deck).whereType<PdfClipPath>(), hasLength(1));
    final saved = _reopen(deck).slides.single;
    expect(saved.backgroundGradient!.gradient!.angleDegrees, 90);
    expect(saved.inheritsMasterBackground, isFalse);
  });

  test(
    'foreign-namespace gradient markup is not promoted to a selected fill',
    () {
      final foreign = _gradient()
          .replaceAll('a:', 'x:')
          .replaceFirst('<p:bg>', '<p:bg xmlns:x="urn:foreign">');
      final deck = _import(slide: foreign);
      expect(deck.slides.single.backgroundGradient, isNull);
      expect(
        deck.slides.single.backgroundShapes.where((s) => s.isBackgroundFill),
        isEmpty,
      );
    },
  );

  for (final location in ['line', 'text']) {
    test('a later $location gradient cannot reuse another shape fill', () {
      final fill = RegExp(
        '<a:gradFill>.*</a:gradFill>',
      ).firstMatch(_gradient())!.group(0)!;
      final shapes = parseSlideShapes(
        '<p:sld $_ns><p:cSld><p:spTree><p:sp>'
        '<p:nvSpPr><p:cNvPr id="2" name="First"/></p:nvSpPr>'
        '<p:spPr>$fill</p:spPr></p:sp><p:sp>'
        '<p:nvSpPr><p:cNvPr id="3" name="Second"/></p:nvSpPr>'
        '<p:spPr><a:solidFill><a:srgbClr val="00FF00"/></a:solidFill>'
        '${location == 'line' ? '<a:ln>$fill</a:ln>' : ''}</p:spPr>'
        '${location == 'text' ? '<p:txBody><a:bodyPr/><a:lstStyle/><a:p>'
                  '<a:r><a:rPr>$fill</a:rPr><a:t>Label</a:t></a:r>'
                  '</a:p></p:txBody>' : ''}'
        '</p:sp></p:spTree></p:cSld></p:sld>',
      );
      expect(shapes.first.gradient!.stops, hasLength(3));
      expect(shapes.last.fillColor, '00FF00');
      expect(shapes.last.gradient, isNull);
    });
  }

  test('authored radial shape gradient keeps its marker on native save', () {
    final shape = _shape()..gradient = _fill(radial: true);
    final saved = _reopen(
      PmlPresentation(
        slides: [
          PmlSlide(id: 256, shapes: [shape]),
        ],
      ),
    );
    expect(saved.slides.single.shapes.single.gradient!.radial, isTrue);
    expect(saved.slides.single.shapes.single.gradient!.stops, hasLength(3));
  });

  test('modified DrawingML colors remain owned gradient stops', () {
    final shapes = parseSlideShapes(
      '<p:sld $_ns><p:cSld><p:spTree><p:sp><p:nvSpPr>'
      '<p:cNvPr id="2" name="Modified stops"/></p:nvSpPr><p:spPr>'
      '<a:gradFill><a:gsLst><a:gs pos="0">'
      '<a:schemeClr val="accent1"><a:lumMod val="50000"/>'
      '</a:schemeClr></a:gs><a:gs pos="100000">'
      '<a:srgbClr val="0000FF"><a:tint val="50000"/></a:srgbClr>'
      '</a:gs></a:gsLst><a:lin ang="5400000"/></a:gradFill>'
      '</p:spPr></p:sp></p:spTree></p:cSld></p:sld>',
      colors: const {'accent1': 'FF0000'},
    );
    expect(shapes.single.gradient, isNotNull);
    expect(shapes.single.gradient!.stops.map((s) => (s.position, s.color)), [
      (0.0, '800000'),
      (1.0, '8080FF'),
    ]);
    expect(shapes.single.gradient!.angleDegrees, 90);
  });

  for (final angle in [0.0, 90.0]) {
    test(
      'PDF multi-stop gradient reaches the correct bounds at $angle degrees',
      () {
        final ops = exportShape(_shape(angle: angle));
        final strips = ops
            .whereType<PdfFillPath>()
            .where((p) => p.color != 0xFFFFFFFF)
            .toList();
        expect(strips, hasLength(72));
        expect((strips.first.color >> 16) & 255, greaterThan(245));
        expect(strips.last.color & 255, greaterThan(245));
        expect((strips[35].color >> 8) & 255, greaterThan(245));
        final first = _vertices(strips.first.points);
        final last = _vertices(strips.last.points);
        final start = angle == 0
            ? first.map((p) => p.x).reduce((a, b) => a < b ? a : b)
            : first.map((p) => p.y).reduce((a, b) => a < b ? a : b);
        final end = angle == 0
            ? last.map((p) => p.x).reduce((a, b) => a > b ? a : b)
            : last.map((p) => p.y).reduce((a, b) => a > b ? a : b);
        expect(start, closeTo(angle == 0 ? 20 : 30, .001));
        // The strips deliberately overlap by 0.35pt under the exact clip.
        expect(end, closeTo((angle == 0 ? 220 : 110) + .35, .001));
        final restored = _reopen(
          PmlPresentation(
            slides: [
              PmlSlide(id: 256, shapes: [_shape(angle: angle)]),
            ],
          ),
        );
        expect(
          restored.slides.single.shapes.single.gradient!.stops,
          hasLength(3),
        );
        expect(
          restored.slides.single.shapes.single.gradient!.angleDegrees,
          angle,
        );
      },
    );
  }

  for (final (preset, vertices) in [
    (PmlShapePreset.homePlate, 5),
    (PmlShapePreset.triangle, 3),
    (PmlShapePreset.rightArrow, 7),
    (PmlShapePreset.freeform, 3),
  ]) {
    test('PDF gradient uses the exact $preset clip and restores it', () {
      final shape = _shape(
        preset: preset,
        path: preset == PmlShapePreset.freeform
            ? const [
                PmlPathPoint(0, 0),
                PmlPathPoint(100 * 12700, 0),
                PmlPathPoint(0, 80 * 12700),
              ]
            : null,
      );
      final deck = PmlPresentation(
        slides: [
          PmlSlide(
            id: 256,
            shapes: [
              shape,
              PmlShape(
                id: 3,
                name: 'After gradient',
                fillColor: '123456',
                transform: const PmlTransform(
                  x: 300 * 12700,
                  y: 20 * 12700,
                  cx: 20 * 12700,
                  cy: 20 * 12700,
                ),
              ),
            ],
          ),
        ],
      );
      final ops = export(deck);
      final clip = ops.whereType<PdfClipPath>().single;
      expect(_vertices(clip.points), hasLength(vertices));
      if (preset == PmlShapePreset.homePlate) {
        expect(_vertices(clip.points).map((p) => (p.x, p.y)), [
          (20.0, 30.0),
          (180.0, 30.0),
          (220.0, 70.0),
          (180.0, 110.0),
          (20.0, 110.0),
        ]);
      }
      final following = ops.whereType<PdfFillPath>().singleWhere(
        (p) => p.color == 0xFF123456,
      );
      expect(
        _vertices(following.points).map((p) => p.x),
        containsAll([300.0, 320.0]),
      );
      final between = ops.sublist(
        ops.indexOf(clip) + 1,
        ops.indexOf(following),
      );
      expect(between.whereType<PdfRestoreGState>(), hasLength(2));
    });
  }

  test('picture shadow paints once and restores caller PDF fill color', () {
    final canvas = PdfCanvas(100, 100)..setFillColor('00FF00');
    final image = PngBytes.rgb(
      width: 1,
      height: 1,
      plot: (x, y, rgb) {
        rgb[0] = 255;
        rgb[1] = 0;
        rgb[2] = 0;
      },
    );
    final images = <PdfEmbeddedImage>[];
    OfficePdfVisuals.paint(
      canvas,
      10,
      10,
      20,
      20,
      OfficeVisual(
        kind: OfficeVisualKind.picture,
        imageBytes: image,
        picture: PictureAdjust(shadow: true),
      ),
      images,
      drawText: (text, x, y, size, color) => fail('Unexpected image fallback'),
    );
    canvas.rect(50, 50, 10, 10);
    canvas.fill();
    final stream = utf8.decode(canvas.toStream());
    var color = '';
    final stack = <String>[];
    final fills = <String>[];
    for (final line in stream.split('\n')) {
      if (line == 'q') {
        stack.add(color);
      } else if (line == 'Q') {
        color = stack.removeLast();
      } else if (line.endsWith(' rg')) {
        color = line.substring(0, line.length - 3);
      } else if (line == 'f') {
        fills.add(color);
      }
    }
    expect(fills.map((color) => color.split(' ').map(double.parse).toList()), [
      [.690, .690, .690],
      [0, 1, 0],
    ]);
    expect(stack, isEmpty);
    expect(images, hasLength(1));
  });
}
