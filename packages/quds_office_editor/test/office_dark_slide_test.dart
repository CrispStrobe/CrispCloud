import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _boundary = ValueKey('dark-slide');

Iterable<XmlElement> _descendants(XmlElement root, String name) sync* {
  for (final child in root.childElements) {
    if (child.localName == name) {
      yield child;
    }
    yield* _descendants(child, name);
  }
}

class _Raster {
  _Raster(this.width, this.height, this.bytes);
  final int width;
  final int height;
  final List<int> bytes;

  int count(ui.Rect area, int rgb) {
    var found = 0;
    for (
      var y = area.top.floor().clamp(0, height);
      y < area.bottom.ceil().clamp(0, height);
      y++
    ) {
      for (
        var x = area.left.floor().clamp(0, width);
        x < area.right.ceil().clamp(0, width);
        x++
      ) {
        final offset = (y * width + x) * 4;
        if ((bytes[offset] - ((rgb >> 16) & 255)).abs() <= 3 &&
            (bytes[offset + 1] - ((rgb >> 8) & 255)).abs() <= 3 &&
            (bytes[offset + 2] - (rgb & 255)).abs() <= 3) {
          found++;
        }
      }
    }
    return found;
  }

  double blackCoverageOnWhite(ui.Rect area) {
    var coverage = 0.0;
    for (
      var y = area.top.floor().clamp(0, height);
      y < area.bottom.ceil().clamp(0, height);
      y++
    ) {
      for (
        var x = area.left.floor().clamp(0, width);
        x < area.right.ceil().clamp(0, width);
        x++
      ) {
        final offset = (y * width + x) * 4;
        final brightest = <int>[
          bytes[offset],
          bytes[offset + 1],
          bytes[offset + 2],
        ].reduce((a, b) => a > b ? a : b);
        coverage += (255 - brightest) / 255;
      }
    }
    return coverage;
  }

  bool samePixelsIn(ui.Rect area, _Raster other) {
    if (width != other.width || height != other.height) return false;
    for (
      var y = area.top.floor().clamp(0, height);
      y < area.bottom.ceil().clamp(0, height);
      y++
    ) {
      for (
        var x = area.left.floor().clamp(0, width);
        x < area.right.ceil().clamp(0, width);
        x++
      ) {
        final offset = (y * width + x) * 4;
        for (var channel = 0; channel < 4; channel++) {
          if (bytes[offset + channel] != other.bytes[offset + channel]) {
            return false;
          }
        }
      }
    }
    return true;
  }

  Iterable<int> _offsets(ui.Rect area) sync* {
    for (
      var y = area.top.floor().clamp(0, height);
      y < area.bottom.ceil().clamp(0, height);
      y++
    ) {
      for (
        var x = area.left.floor().clamp(0, width);
        x < area.right.ceil().clamp(0, width);
        x++
      ) {
        yield (y * width + x) * 4;
      }
    }
  }

  int contrastPixels(ui.Rect area, int background) {
    final base = ui.Color(0xFF000000 | background).computeLuminance();
    var found = 0;
    for (final offset in _offsets(area)) {
      final ink = ui.Color.fromARGB(
        bytes[offset + 3],
        bytes[offset],
        bytes[offset + 1],
        bytes[offset + 2],
      ).computeLuminance();
      final contrast = ink >= base
          ? (ink + 0.05) / (base + 0.05)
          : (base + 0.05) / (ink + 0.05);
      if (contrast >= 4.5) {
        found++;
      }
    }
    return found;
  }
}

PmlShape _shape(
  int id, {
  double x = 30,
  required double y,
  double width = 300,
  double height = 40,
  String fill = '',
  String ink = '000000',
  String text = 'Readable slide text',
  double rotation = 0,
  OfficeVisual? visual,
  PmlTable? table,
}) => PmlShape(
  id: id,
  name: 'Shape $id',
  text: text,
  fillColor: fill,
  textColor: ink,
  visual: visual,
  table: table,
  transform: PmlTransform(
    x: (x * 12700).round(),
    y: (y * 12700).round(),
    cx: (width * 12700).round(),
    cy: (height * 12700).round(),
    rot: (rotation * 60000).round(),
  ),
);

Future<_Raster> _paint(
  WidgetTester tester,
  PmlSlide slide, {
  OfficeTheme theme = OfficeTheme.dark,
  PmlSlide? outgoing,
  double progress = 1,
  int? expectedImageColor,
}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: _boundary,
          child: SizedBox(
            width: 720,
            height: 405,
            child: SlideStage(
              slide: slide,
              preview: outgoing == null,
              presenting: outgoing != null,
              outgoingSlide: outgoing,
              transitionProgress: progress,
              playingTransition: outgoing == null
                  ? null
                  : const PmlSlideTransition(kind: PmlTransitionKind.morph),
              config: OfficeSurfaceConfig(
                theme: theme,
                mode: OfficeInteractionMode.viewing,
                showSlideHandles: false,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_boundary),
  );
  Future<_Raster> capture() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final pixels = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      return _Raster(image.width, image.height, pixels.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  }

  var raster = (await tester.runAsync(capture))!;
  if (expectedImageColor != null) {
    for (
      var attempt = 0;
      attempt < 20 &&
          raster.count(
                const ui.Rect.fromLTWH(40, 40, 300, 100),
                expectedImageColor,
              ) <
              500;
      attempt++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pumpAndSettle();
      raster = (await tester.runAsync(capture))!;
    }
    expect(
      raster.count(
        const ui.Rect.fromLTWH(40, 40, 300, 100),
        expectedImageColor,
      ),
      greaterThan(500),
      reason: 'The actual picture must be decoded before comparing ink.',
    );
  }
  return raster;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);

  testWidgets('native and authored slide backgrounds retain readable ink', (
    tester,
  ) async {
    final PmlSlide slide = PmlSlide(
      id: 256,
      shapes: <PmlShape>[_shape(2, y: 40, ink: '')],
    );
    final _Raster inherited = await _paint(tester, slide);
    expect(
      inherited.count(const ui.Rect.fromLTWH(0, 0, 20, 20), 0x2B2B2B),
      400,
    );
    expect(
      inherited.contrastPixels(
        const ui.Rect.fromLTWH(38, 48, 280, 28),
        0x2B2B2B,
      ),
      greaterThan(25),
    );

    slide.background = 'FFFFFF';
    for (final OfficeTheme theme in <OfficeTheme>[
      OfficeTheme.dark,
      OfficeTheme.dark.copyWith(adaptDocumentColors: false),
    ]) {
      final _Raster authored = await _paint(tester, slide, theme: theme);
      expect(
        authored.count(const ui.Rect.fromLTWH(0, 0, 20, 20), 0xFFFFFF),
        400,
      );
      expect(
        authored.contrastPixels(
          const ui.Rect.fromLTWH(38, 48, 280, 28),
          0xFFFFFF,
        ),
        greaterThan(25),
      );
    }
    expect(slide.shapes.single.textColor, isEmpty);
  });

  testWidgets('rich slide formatting edits render before saving and reopening', (
    tester,
  ) async {
    final OpcPackage package = OpcPackage.create(OpcPackageKind.slide);
    package
        .getPart('/ppt/slides/slide1.xml')!
        .writeText(
          '<p:sld xmlns:p="${OfficeNamespaces.p}" xmlns:a="${OfficeNamespaces.a}">'
          '<p:cSld><p:spTree><p:sp><p:nvSpPr><p:cNvPr id="2" name="Rich"/>'
          '<p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm>'
          '<a:off x="381000" y="508000"/><a:ext cx="6350000" cy="1270000"/>'
          '</a:xfrm><a:noFill/></p:spPr><p:txBody><a:bodyPr/><a:p>'
          '<a:r><a:rPr sz="1800" b="1"><a:solidFill><a:srgbClr val="000000"/>'
          '</a:solidFill></a:rPr><a:t>Rich </a:t></a:r>'
          '<a:r><a:rPr sz="1200" i="1"><a:solidFill><a:srgbClr val="000000"/>'
          '</a:solidFill></a:rPr><a:t>text</a:t></a:r></a:p></p:txBody>'
          '</p:sp></p:spTree></p:cSld></p:sld>',
        );
    final PmlPresentation deck = SlideDeserializer().read(package);
    final PmlSlide slide = deck.slides.single;
    final PmlShape shape = slide.shapes.single;
    final _Raster original = await _paint(
      tester,
      slide,
      theme: OfficeTheme.light,
    );
    shape
      ..fontSizePt = 30
      ..textColor = '008800'
      ..textAlign = PmlTextAlign.center;
    final _Raster edited = await _paint(
      tester,
      slide,
      theme: OfficeTheme.light,
    );
    const ui.Rect textArea = ui.Rect.fromLTWH(30, 40, 500, 100);
    expect(edited.samePixelsIn(textArea, original), isFalse);
    expect(edited.count(textArea, 0x008800), greaterThan(25));
    final PmlSlide reopened = SlideDeserializer()
        .readBytes(SlideSerializer().writeBytes(deck))
        .slides
        .single;
    final _Raster saved = await _paint(
      tester,
      reopened,
      theme: OfficeTheme.light,
    );
    expect(edited.samePixelsIn(textArea, saved), isTrue);
    expect(
      shape.richText.single.runs.map((PmlTextRun r) => r.fontSizePt),
      <double>[18, 12],
    );

    slide.background = '2B2B2B';
    shape.textColor = '000000';
    final _Raster adapted = await _paint(tester, slide);
    expect(adapted.count(textArea, 0xF2F2F2), greaterThan(25));
    final _Raster unadapted = await _paint(
      tester,
      slide,
      theme: OfficeTheme.dark.copyWith(adaptDocumentColors: false),
    );
    expect(adapted.samePixelsIn(textArea, unadapted), isFalse);
    expect(shape.textColor, '000000');
  });

  test(
    'master paper edits update inherited slides and preserve explicit fills',
    () {
      final inherited = PmlSlide(
        id: 256,
        background: 'FFFFFF',
        inheritsMasterBackground: true,
      );
      final explicit = PmlSlide(id: 257, background: 'FFFFFF');
      final fresh = PmlSlide(id: 258);
      final controller = SlideEditorController(
        presentation: PmlPresentation(
          slides: <PmlSlide>[inherited, explicit, fresh],
        ),
      );
      addTearDown(controller.dispose);
      controller.applyMasterBackground('112233');
      expect(controller.presentation.master.background, '112233');
      expect(inherited.background, '112233');
      expect(fresh.background, '112233');
      expect(explicit.background, 'FFFFFF');
      controller.applyMasterBackground('445566');
      expect(inherited.background, '445566');
      expect(fresh.background, '445566');
      expect(inherited.inheritsMasterBackground, isTrue);
      inherited.background = 'FFFFFF';
      expect(inherited.inheritsMasterBackground, isFalse);
      controller.applyMasterBackground('778899');
      expect(inherited.background, 'FFFFFF');
      expect(explicit.background, 'FFFFFF');
      expect(fresh.background, '778899');
      inherited.background = 'ABCDEF';
      expect(inherited.inheritsMasterBackground, isFalse);
      controller.applyMasterBackground('667788');
      expect(inherited.background, 'ABCDEF');
      expect(fresh.background, '667788');
      expect(explicit.background, 'FFFFFF');
      inherited.background = '';
      expect(inherited.inheritsMasterBackground, isTrue);
      controller.applyMasterBackground('99AABB');
      expect(inherited.background, '99AABB');
      controller.presentation.master.background = 'A0B0C0';
      expect(inherited.resolveBackground('A0B0C0'), 'A0B0C0');
      expect(fresh.resolveBackground('A0B0C0'), 'A0B0C0');
      expect(explicit.resolveBackground('A0B0C0'), 'FFFFFF');
    },
  );

  testWidgets(
    'inherited white paper and rich ink honor dark and high contrast',
    (tester) async {
      final shape = _shape(2, y: 20, height: 100, text: 'Readable rich text');
      shape.richText.add(
        PmlTextParagraph(
          runs: <PmlTextRun>[
            PmlTextRun(text: shape.text, fontSizePt: 18, color: '000000'),
          ],
        ),
      );
      final slide = PmlSlide(
        id: 256,
        background: 'FFFFFF',
        inheritsMasterBackground: true,
        shapes: <PmlShape>[shape],
      );
      for (final theme in <OfficeTheme>[
        OfficeTheme.dark,
        OfficeTheme.highContrast,
      ]) {
        final raster = await _paint(tester, slide, theme: theme);
        expect(
          raster.count(
            const ui.Rect.fromLTWH(400, 150, 100, 100),
            theme.slideBackground.toARGB32() & 0xFFFFFF,
          ),
          greaterThan(9000),
        );
        expect(
          raster.count(
            const ui.Rect.fromLTWH(38, 28, 280, 60),
            theme.documentText.toARGB32() & 0xFFFFFF,
          ),
          greaterThan(25),
        );
        final _Raster unadapted = await _paint(
          tester,
          slide,
          theme: theme.copyWith(adaptDocumentColors: false),
        );
        expect(
          unadapted.count(const ui.Rect.fromLTWH(400, 150, 100, 100), 0xFFFFFF),
          greaterThan(9000),
        );
        expect(
          unadapted.count(const ui.Rect.fromLTWH(38, 28, 280, 60), 0x000000),
          greaterThan(25),
        );
      }
      expect(slide.background, 'FFFFFF');
      expect(shape.richText.single.runs.single.color, '000000');
    },
  );

  testWidgets('rich text painting follows font-size edits and undo', (
    tester,
  ) async {
    final shape = _shape(2, y: 20, height: 100, text: 'MMMM');
    shape
      ..fontSizePt = 12
      ..textSource = const PmlTextSource(
        xml: '',
        text: 'MMMM',
        fontSizePt: 12,
        textColor: '000000',
        textAlign: PmlTextAlign.left,
        rightToLeft: null,
      );
    shape.richText.add(
      PmlTextParagraph(
        runs: <PmlTextRun>[
          PmlTextRun(text: shape.text, fontSizePt: 12, color: '000000'),
        ],
      ),
    );
    final slide = PmlSlide(id: 256, shapes: <PmlShape>[shape]);
    final controller = SlideEditorController(
      presentation: PmlPresentation(slides: <PmlSlide>[slide]),
    )..selected = shape;
    addTearDown(controller.dispose);
    const area = ui.Rect.fromLTWH(38, 28, 280, 100);
    final before = await _paint(tester, slide);
    controller.updateSelected(fontSizePt: 28);
    final after = await _paint(tester, slide);
    expect(
      after.count(area, 0xF2F2F2),
      greaterThan(before.count(area, 0xF2F2F2)),
    );
    controller.undo();
    final restored = await _paint(tester, slide);
    expect(restored.samePixelsIn(area, before), isTrue);
    expect(shape.richText.single.runs.single.fontSizePt, 12);
  });

  testWidgets(
    'dark Slides adapt explicit ink and preserve automatic and exported colors',
    (tester) async {
      final table = PmlTable(
        rows: <List<PmlTableCell>>[
          <PmlTableCell>[
            PmlTableCell(
              text: 'Light cell',
              fillColor: 'FFFFFF',
              textColor: '000000',
            ),
          ],
          <PmlTableCell>[
            PmlTableCell(
              text: 'Dark cell',
              fillColor: '303030',
              textColor: '000000',
            ),
          ],
        ],
      );
      final slide = PmlSlide(
        id: 256,
        shapes: <PmlShape>[
          _shape(2, y: 20),
          _shape(3, y: 80, fill: '303030'),
          _shape(4, y: 140, fill: 'FFFFFF'),
          _shape(5, y: 200, fill: '303030', ink: ''),
          _shape(6, y: 260, ink: ''),
          _shape(7, x: 380, y: 30, height: 120, table: table, text: ''),
          _shape(8, x: 380, y: 190, height: 80, fill: 'FFFFFF', text: ''),
          _shape(9, x: 400, y: 210, width: 260),
          _shape(10, x: 380, y: 300, height: 80, fill: '303030', text: ''),
          _shape(11, x: 400, y: 315, width: 260),
        ],
      );
      final originalColors = <int, String>{
        for (final shape in slide.shapes) shape.id: shape.textColor,
      };
      final dark = await _paint(tester, slide);
      for (final y in <double>[20, 80]) {
        expect(
          dark.count(ui.Rect.fromLTWH(38, y + 8, 280, 28), 0xF2F2F2),
          greaterThan(25),
        );
      }
      expect(
        dark.count(const ui.Rect.fromLTWH(38, 148, 280, 28), 0x000000),
        greaterThan(25),
      );
      for (final y in <double>[200, 260]) {
        expect(
          dark.count(ui.Rect.fromLTWH(38, y + 8, 280, 28), 0xFFFFFF),
          greaterThan(25),
          reason: 'Automatic colors retain their prior behavior.',
        );
      }
      const whiteCell = ui.Rect.fromLTWH(384, 33, 290, 25);
      // At 13 px most glyph pixels have fractional coverage. Measure that
      // coverage instead of requiring many completely opaque black pixels.
      expect(dark.blackCoverageOnWhite(whiteCell), greaterThan(15));
      const darkCell = ui.Rect.fromLTWH(384, 93, 290, 25);
      expect(dark.contrastPixels(whiteCell, 0xFFFFFF), greaterThan(25));
      expect(dark.contrastPixels(darkCell, 0x303030), greaterThan(25));
      // Contrast above measures readable glyph coverage. Opaque pixel counts
      // vary with the installed fallback font and antialiasing; separately
      // confirm that the expected adapted ink is present.
      expect(
        dark.count(const ui.Rect.fromLTWH(384, 93, 290, 25), 0xF2F2F2),
        isPositive,
      );
      expect(
        dark.count(const ui.Rect.fromLTWH(408, 218, 240, 28), 0x000000),
        greaterThan(25),
      );
      expect(
        dark.count(const ui.Rect.fromLTWH(408, 323, 240, 28), 0xF2F2F2),
        greaterThan(25),
      );

      final unadapted = await _paint(
        tester,
        slide,
        theme: OfficeTheme.dark.copyWith(adaptDocumentColors: false),
      );
      expect(
        dark.samePixelsIn(whiteCell, unadapted),
        isTrue,
        reason: 'Light cell backgrounds must preserve authored black ink.',
      );
      expect(
        unadapted.count(const ui.Rect.fromLTWH(384, 93, 290, 25), 0xF2F2F2),
        0,
        reason: 'The dark-cell assertion must distinguish adapted ink.',
      );
      expect(unadapted.contrastPixels(darkCell, 0x303030), 0);

      final wrongLightInk = slide.copy();
      wrongLightInk.shapes
              .singleWhere((shape) => shape.id == 7)
              .table!
              .rows
              .first
              .first
              .textColor =
          'F2F2F2';
      final wrongLightRaster = await _paint(tester, wrongLightInk);
      expect(
        wrongLightRaster.blackCoverageOnWhite(whiteCell),
        lessThanOrEqualTo(15),
        reason: 'Incorrect light ink on white must fail the coverage gate.',
      );
      expect(dark.samePixelsIn(whiteCell, wrongLightRaster), isFalse);
      expect(
        wrongLightRaster.contrastPixels(whiteCell, 0xFFFFFF),
        lessThanOrEqualTo(25),
      );

      final blank = slide.copy();
      blank.shapes
              .singleWhere((shape) => shape.id == 7)
              .table!
              .rows
              .first
              .first
              .text =
          '';
      final blankRaster = await _paint(tester, blank);
      expect(blankRaster.blackCoverageOnWhite(whiteCell), 0);
      expect(blankRaster.contrastPixels(whiteCell, 0xFFFFFF), 0);
      expect(dark.samePixelsIn(whiteCell, blankRaster), isFalse);

      final light = await _paint(tester, slide, theme: OfficeTheme.light);
      expect(
        light.count(const ui.Rect.fromLTWH(38, 28, 280, 28), 0x000000),
        greaterThan(25),
      );
      expect(<int, String>{
        for (final shape in slide.shapes) shape.id: shape.textColor,
      }, originalColors);
      final savedBytes = SlideSerializer().writeBytes(
        PmlPresentation(slides: <PmlSlide>[slide]),
      );
      final reopened = SlideDeserializer().readBytes(savedBytes).slides.single;
      final explicitShapes = reopened.shapes.where(
        (shape) => const <int>{2, 3, 4, 9, 11}.contains(shape.id),
      );
      expect(explicitShapes, hasLength(5));
      for (final shape in explicitShapes) {
        expect(shape.textColor, '000000');
      }
      expect(
        reopened.shapes
            .singleWhere((shape) => shape.id == 7)
            .table!
            .rows
            .expand((row) => row)
            .map((cell) => cell.textColor),
        <String>['000000', '000000'],
      );
      expect(
        table.rows.expand((row) => row).map((cell) => cell.textColor),
        <String>['000000', '000000'],
      );
      // Verify serialized colors independently of the now-corrected importer.
      final exportedSlide = XmlDocument.parse(
        OpcPackage.openBytes(
          savedBytes,
        ).getPart('/ppt/slides/slide1.xml')!.readText(),
      ).root!;
      final cells = _descendants(exportedSlide, 'tc').toList();
      expect(cells, hasLength(2));
      expect(
        <String?>[
          for (final cell in cells)
            _descendants(
              cell.firstChild('txBody')!,
              'srgbClr',
            ).single.getAttribute('val'),
        ],
        <String>['000000', '000000'],
      );
      expect(
        <String?>[
          for (final cell in cells)
            _descendants(
              cell.firstChild('tcPr')!,
              'srgbClr',
            ).single.getAttribute('val'),
        ],
        <String>['FFFFFF', '303030'],
      );
    },
  );

  for (final backing in <String>[
    'picture',
    'chart',
    'partial fill',
    'rotated fill',
  ]) {
    testWidgets('unfilled Slide text preserves authored ink over $backing', (
      tester,
    ) async {
      final pictureBytes = PngBytes.rgb(
        width: 16,
        height: 16,
        plot: (x, y, rgb) {
          rgb[0] = 0x34;
          rgb[1] = 0x85;
          rgb[2] = 0xCF;
        },
      );
      final backdrop = _shape(
        2,
        x: 40,
        y: 40,
        width: backing == 'partial fill' ? 80 : 340,
        height: 100,
        text: '',
        fill: 'FFFFFF',
        rotation: backing == 'rotated fill' ? 20 : 0,
        visual: switch (backing) {
          'picture' => OfficeVisual(
            kind: OfficeVisualKind.picture,
            imageBytes: pictureBytes,
          ),
          'chart' => OfficeVisual(
            kind: OfficeVisualKind.chartColumn,
            points: OfficeVisual.sampleSeries(),
          ),
          _ => null,
        },
      );
      final slide = PmlSlide(
        id: 256,
        shapes: <PmlShape>[backdrop, _shape(3, x: 60, y: 60, width: 300)],
      );
      final unchanged = await _paint(
        tester,
        slide,
        theme: OfficeTheme.dark.copyWith(adaptDocumentColors: false),
        expectedImageColor: backing == 'picture' ? 0x3485CF : null,
      );
      final adapted = await _paint(
        tester,
        slide,
        expectedImageColor: backing == 'picture' ? 0x3485CF : null,
      );
      expect(adapted.bytes, orderedEquals(unchanged.bytes));
      expect(slide.shapes.last.textColor, '000000');
      if (backing == 'picture') {
        expect(backdrop.visual!.imageBytes, orderedEquals(pictureBytes));
      }
    });
  }

  testWidgets(
    'dark Morph ink uses the interpolated fill instead of target fill',
    (tester) async {
      final outgoing = PmlSlide(
        id: 256,
        shapes: <PmlShape>[_shape(2, y: 40, fill: 'FFFFFF')],
      );
      final incoming = PmlSlide(
        id: 257,
        shapes: <PmlShape>[_shape(2, y: 40, fill: '303030')],
      );
      final early = await _paint(
        tester,
        incoming,
        outgoing: outgoing,
        progress: 0.1,
      );
      expect(
        early.count(const ui.Rect.fromLTWH(38, 48, 280, 28), 0x000000),
        greaterThan(25),
      );
      final late = await _paint(
        tester,
        incoming,
        outgoing: outgoing,
        progress: 0.9,
      );
      expect(
        late.count(const ui.Rect.fromLTWH(38, 48, 280, 28), 0xF2F2F2),
        greaterThan(25),
      );
      expect(outgoing.shapes.single.fillColor, 'FFFFFF');
      expect(incoming.shapes.single.fillColor, '303030');
      expect(incoming.shapes.single.textColor, '000000');
    },
  );
}
