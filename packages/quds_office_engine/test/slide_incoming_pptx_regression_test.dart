import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/automation/operations/slide_steps.dart';
import 'package:test/test.dart';

import 'support/pdf_alias_fixture.dart';

PmlShape _textShape(
  String text, {
  double width = 300,
  double height = 100,
  bool rightToLeft = false,
  List<PmlTextRun>? runs,
}) => PmlShape(
  id: 2,
  name: 'Imported text',
  text: text,
  fillColor: '',
  fontSizePt: 20,
  rightToLeft: rightToLeft,
  transform: PmlTransform(
    x: 20 * 12700,
    y: 30 * 12700,
    cx: (width * 12700).round(),
    cy: (height * 12700).round(),
  ),
  richText: [
    PmlTextParagraph(
      rightToLeft: rightToLeft,
      runs: runs ?? [PmlTextRun(text: text, fontSizePt: 20)],
    ),
  ],
);

List<List<PdfDrawText>> _paintedLines(PdfFile file) {
  final Map<double, List<PdfDrawText>> lines = {};
  for (final PdfDrawText op
      in file.displayList(0).ops.whereType<PdfDrawText>()) {
    lines.putIfAbsent(op.y, () => []).add(op);
  }
  return lines.values.toList();
}

PmlShape _connector({
  int id = 2,
  bool flipH = false,
  bool flipV = false,
  String fill = '',
  String stroke = 'FF0000',
}) => PmlShape(
  id: id,
  name: 'Connector $id',
  preset: PmlShapePreset.connector,
  fillColor: fill,
  strokeColor: stroke,
  strokeWidth: 2,
  transform: PmlTransform(
    x: 10 * 12700,
    y: 20 * 12700,
    cx: 100 * 12700,
    cy: 80 * 12700,
    flipH: flipH,
    flipV: flipV,
  ),
);

String _connectorXml(String flipH, String flipV) =>
    '<p:sld xmlns:p="${OfficeNamespaces.p}" xmlns:a="${OfficeNamespaces.a}">'
    '<p:cSld><p:spTree><p:cxnSp><p:nvCxnSpPr><p:cNvPr id="2" name="Line"/>'
    '<p:cNvCxnSpPr/><p:nvPr/></p:nvCxnSpPr><p:spPr>'
    '<a:xfrm flipH="$flipH" flipV="$flipV">'
    '<a:off x="127000" y="254000"/><a:ext cx="1270000" cy="1016000"/>'
    '</a:xfrm><a:prstGeom prst="line"><a:avLst/></a:prstGeom><a:noFill/>'
    '<a:ln w="25400"><a:solidFill><a:srgbClr val="FF0000"/></a:solidFill>'
    '</a:ln></p:spPr></p:cxnSp></p:spTree></p:cSld></p:sld>';

void main() {
  final SfntFont font = aliasTestFont();
  PdfFile export(PmlShape shape) => PdfFile.open(
    OfficePdfExport.presentation(
      PmlPresentation(
        slides: [
          PmlSlide(id: 256, shapes: [shape]),
        ],
      ),
      font: font,
    ),
  );

  for (final (bool flipH, bool flipV) in [
    (false, false),
    (true, false),
    (false, true),
    (true, true),
  ]) {
    test('connector flips H=$flipH V=$flipV survive copy and PPTX/PDF', () {
      final PmlShape shape = _connector(flipH: flipH, flipV: flipV);
      final PmlShape copied = shape.copy(id: 3);
      expect((copied.transform.flipH, copied.transform.flipV), (flipH, flipV));
      final PmlShape saved = SlideDeserializer()
          .readBytes(
            SlideSerializer().writeBytes(
              PmlPresentation(
                slides: [
                  PmlSlide(id: 256, shapes: [copied]),
                ],
              ),
            ),
          )
          .slides
          .single
          .shapes
          .single;
      expect((saved.transform.flipH, saved.transform.flipV), (flipH, flipV));
      final PdfStrokePath path = export(
        saved,
      ).displayList(0).ops.whereType<PdfStrokePath>().single;
      expect(path.points, hasLength(2));
      expect(path.points.first.kind, PdfPathKind.move);
      expect(path.points.last.kind, PdfPathKind.line);
      expect(path.points.first.x, closeTo(flipH ? 110 : 10, 0.001));
      expect(path.points.first.y, closeTo(flipV ? 100 : 20, 0.001));
      expect(path.points.last.x, closeTo(flipH ? 10 : 110, 0.001));
      expect(path.points.last.y, closeTo(flipV ? 20 : 100, 0.001));
    });
  }

  for (final (String value, bool expected) in [
    ('1', true),
    ('true', true),
    ('0', false),
    ('false', false),
  ]) {
    test('connector XML boolean $value is parsed on either axis', () {
      final PmlShape horizontal = parseSlideShapes(
        _connectorXml(value, '0'),
      ).single;
      final PmlShape vertical = parseSlideShapes(
        _connectorXml('0', value),
      ).single;
      expect(
        (horizontal.transform.flipH, horizontal.transform.flipV),
        (expected, false),
      );
      expect(
        (vertical.transform.flipH, vertical.transform.flipV),
        (false, expected),
      );
    });
  }

  test('rotated single-axis connector keeps its diagonal in PDF', () {
    final PmlShape shape = _connector(flipH: true)
      ..transform = const PmlTransform(
        x: 10 * 12700,
        y: 20 * 12700,
        cx: 100 * 12700,
        cy: 80 * 12700,
        rot: 90 * 60000,
        flipH: true,
      );
    final PdfStrokePath path = export(
      shape,
    ).displayList(0).ops.whereType<PdfStrokePath>().single;
    expect(path.points.first.x, closeTo(100, 0.001));
    expect(path.points.first.y, closeTo(110, 0.001));
    expect(path.points.last.x, closeTo(20, 0.001));
    expect(path.points.last.y, closeTo(10, 0.001));
  });

  test('slide duplication retains decorations, strokes and authored flags', () {
    final PmlSlide source = PmlSlide(
      id: 256,
      sourcePartUri: '/ppt/slides/slide1.xml',
      background: '123456',
      showMasterShapes: false,
      backgroundShapes: [_connector(id: 8, flipV: true)],
      shapes: [_connector(flipH: true)],
    );
    final PmlSlide duplicate = source.copy(id: 257);
    expect(duplicate.id, 257);
    expect(duplicate.sourcePartUri, isNull);
    expect(duplicate.showMasterShapes, isFalse);
    expect(duplicate.background, source.background);
    expect(duplicate.backgroundShapes, hasLength(1));
    expect(duplicate.backgroundShapes.single.transform.flipV, isTrue);
    expect(duplicate.shapes.single.transform.flipH, isTrue);
    expect(duplicate.shapes.single.strokeColor, 'FF0000');
    expect(duplicate.shapes.single.strokeWidth, 2);
    duplicate.shapes.single.strokeColor = '0000FF';
    duplicate.backgroundShapes.clear();
    expect(source.shapes.single.strokeColor, 'FF0000');
    expect(source.backgroundShapes, hasLength(1));
  });

  test(
    'PDF connector uses authored stroke once instead of a fill underlay',
    () {
      final PdfStrokePath path = export(
        _connector(fill: '0000FF'),
      ).displayList(0).ops.whereType<PdfStrokePath>().single;
      expect(path.color, 0xFFFF0000);
      expect(path.width, closeTo(2, 0.001));
    },
  );

  test('PDF legacy fill-only connector keeps its diagonal fallback', () {
    final PdfStrokePath path = export(
      _connector(flipH: true, fill: '0000FF', stroke: ''),
    ).displayList(0).ops.whereType<PdfStrokePath>().single;
    expect(path.color, 0xFF0000FF);
    expect(path.width, closeTo(1.6, 0.001));
    expect(path.points.first.x, closeTo(110, 0.001));
    expect(path.points.last.x, closeTo(10, 0.001));
  });

  test('alignment and distribution preserve each connector flip', () {
    List<PmlShape> shapes() => [
      _connector(flipH: true),
      _connector(id: 3, flipV: true)
        ..transform = const PmlTransform(x: 1000, y: 2000, flipV: true),
      _connector(id: 4, flipH: true, flipV: true)
        ..transform = const PmlTransform(
          x: 3000,
          y: 4000,
          flipH: true,
          flipV: true,
        ),
    ];
    void expectFlips(List<PmlShape> items) => expect(
      items.map((shape) => (shape.transform.flipH, shape.transform.flipV)),
      [(true, false), (false, true), (true, true)],
    );
    for (final PmlAlignAxis axis in PmlAlignAxis.values) {
      final List<PmlShape> items = shapes();
      PmlArrange.align(items, axis);
      expectFlips(items);
    }
    for (final bool horizontal in [false, true]) {
      final List<PmlShape> items = shapes();
      PmlArrange.distribute(items, horizontal: horizontal);
      expectFlips(items);
    }
  });

  test('native shapeGeometry retains flips through serialization', () {
    final PmlShape shape = _connector(flipH: true);
    final PmlPresentation deck = PmlPresentation(
      slides: [
        PmlSlide(id: 256, shapes: [shape]),
      ],
    );
    applySlideStep(deck, {
      'op': 'shapeGeometry',
      'shape': 0,
      'x': 22,
      'y': 33,
      'width': 44,
      'height': 55,
      'rotation': 30,
    });
    expect(shape.transform.xPoints, 22);
    expect(shape.transform.rotationDegrees, 30);
    expect((shape.transform.flipH, shape.transform.flipV), (true, false));
    final PmlTransform saved = SlideDeserializer()
        .readBytes(SlideSerializer().writeBytes(deck))
        .slides
        .single
        .shapes
        .single
        .transform;
    expect((saved.flipH, saved.flipV), (true, false));
    expect(saved.widthPoints, 44);
  });

  test(
    'morph preserves equal flips and switches differing flags with the shape',
    () {
      final PmlSlide from = PmlSlide(
        id: 256,
        shapes: [_connector(flipH: true)],
      );
      final PmlSlide equal = from.copy(id: 257);
      final PmlSlide changed = PmlSlide(
        id: 258,
        shapes: [_connector(flipV: true)],
      );
      for (final double time in [0.0, 0.25, 0.75, 1.0]) {
        final PmlTransform same = PmlMorph.frames(
          from,
          equal,
          time,
        ).single.transform;
        expect((same.flipH, same.flipV), (true, false));
        final PmlTransform next = PmlMorph.frames(
          from,
          changed,
          time,
        ).single.transform;
        expect((
          next.flipH,
          next.flipV,
        ), time < 0.5 ? (true, false) : (false, true));
      }
    },
  );

  for (final PmlShapePreset preset in [
    PmlShapePreset.downArrow,
    PmlShapePreset.upArrow,
    PmlShapePreset.leftArrow,
    PmlShapePreset.rightArrow,
  ]) {
    test('unfilled $preset retains its outline in PDF and PPTX', () {
      final PmlShape arrow = PmlShape(
        id: 2,
        name: 'Arrow',
        preset: preset,
        fillColor: '',
        strokeColor: 'FF0000',
        strokeWidth: 2,
        transform: const PmlTransform(
          x: 10 * 12700,
          y: 20 * 12700,
          cx: 100 * 12700,
          cy: 80 * 12700,
        ),
      );
      final PdfStrokePath stroke = export(
        arrow,
      ).displayList(0).ops.whereType<PdfStrokePath>().single;
      expect(stroke.color, 0xFFFF0000);
      expect(stroke.width, closeTo(2, 0.001));
      expect(
        stroke.points.where((point) => point.kind == PdfPathKind.line),
        hasLength(6),
      );
      expect(stroke.points.last.kind, PdfPathKind.close);
      final PmlPresentation saved = SlideDeserializer().readBytes(
        SlideSerializer().writeBytes(
          PmlPresentation(
            slides: [
              PmlSlide(id: 256, shapes: [arrow]),
            ],
          ),
        ),
      );
      expect(saved.slides.single.shapes.single.preset, preset);
      expect(saved.slides.single.shapes.single.strokeColor, 'FF0000');
    });
  }

  test('fitted mixed explicit and inherited font sizes scale once', () {
    const String text = 'Heading PartTwo';
    final PdfFile file = export(
      _textShape(
        text,
        width: 80,
        height: 30,
        runs: [
          PmlTextRun(text: 'Heading ', fontSizePt: 20, color: 'FF0000'),
          PmlTextRun(text: 'PartTwo', color: '0000FF'),
        ],
      ),
    );
    final List<PdfDrawText> painted = file
        .displayList(0)
        .ops
        .whereType<PdfDrawText>()
        .toList();
    final List<PdfDrawText> red = painted
        .where((op) => op.color == 0xFFFF0000)
        .toList();
    final List<PdfDrawText> blue = painted
        .where((op) => op.color == 0xFF0000FF)
        .toList();
    expect(red, isNotEmpty);
    expect(blue, isNotEmpty);
    expect(red.first.size, lessThan(20));
    for (final PdfDrawText op in blue) {
      expect(op.size, closeTo(red.first.size, 0.001));
    }
  });

  test('numeric single-line text preserves authored LTR order', () {
    const String text = '12-34/56';
    final PdfFile file = export(_textShape(text));
    expect(PdfExtract.pageText(file, 0), text);
    final List<PdfDrawText> painted = file
        .displayList(0)
        .ops
        .whereType<PdfDrawText>()
        .toList();
    expect(painted.map((op) => op.text).join(), text);
    expect(painted.map((op) => op.y).toSet(), hasLength(1));
    for (var i = 1; i < painted.length; i++) {
      expect(painted[i].x, greaterThan(painted[i - 1].x));
    }
  });

  test('numeric explicit line breaks retain separate painted baselines', () {
    final PdfFile file = export(_textShape('12\n34'));
    final List<PdfDrawText> painted = file
        .displayList(0)
        .ops
        .whereType<PdfDrawText>()
        .toList();
    expect(painted.map((op) => op.text).join(), '1234');
    expect(painted.map((op) => op.y).toSet(), hasLength(2));
    expect(painted.first.x, closeTo(painted[2].x, 0.001));
  });

  test('numeric content still wraps inside a narrow text box', () {
    final PdfFile file = export(_textShape('12 34 56 78', width: 50));
    final List<PdfDrawText> painted = file
        .displayList(0)
        .ops
        .whereType<PdfDrawText>()
        .toList();
    expect(painted.map((op) => op.y).toSet().length, greaterThan(1));
    expect(painted.map((op) => op.text).join().replaceAll(' ', ''), '12345678');
    expect(painted.every((op) => op.x < 70), isTrue);
  });

  test('numeric spaced groups keep authored order across explicit breaks', () {
    final PdfFile file = export(_textShape('12 34\n56 78'));
    expect(
      _paintedLines(file).map((line) => line.map((op) => op.text).join()),
      ['12 34', '56 78'],
    );
    expect(PdfExtract.pageText(file, 0), isNot(matches('[\u200e\u202d]')));
  });

  test(
    'numeric spaced groups keep authored order when several fit per wrap',
    () {
      final PdfFile file = export(_textShape('12 34 56 78', width: 80));
      expect(
        _paintedLines(file).map((line) => line.map((op) => op.text).join()),
        ['12 34', '56 78'],
      );
      expect(PdfExtract.pageText(file, 0).replaceAll('\n', ''), '12 34 56 78');
    },
  );

  for (final PmlTextAlign align in [
    PmlTextAlign.left,
    PmlTextAlign.center,
    PmlTextAlign.right,
  ]) {
    for (final bool wrapped in [false, true]) {
      test(
        'numeric alignment $align uses consistent ${wrapped ? 'wrapped' : 'multiline'} measurements',
        () {
          final double boxWidth = wrapped ? 80 : 300;
          final PmlShape shape = _textShape(
            wrapped ? '12 34 56 78' : '12 34\n56 78',
            width: boxWidth,
          )..textAnchor = PmlTextAnchor.center;
          shape.richText.single.align = align;
          final List<List<PdfDrawText>> lines = _paintedLines(export(shape));
          expect(lines, hasLength(2));
          final double textWidth = '12 34'.runes.fold<double>(
            0,
            (width, cp) =>
                width +
                font.advanceWidth(font.glyphIdFor(cp)) / font.unitsPerEm * 20,
          );
          final double slack = boxWidth - 14.4 - textWidth;
          final double offset = switch (align) {
            PmlTextAlign.center => slack / 2,
            PmlTextAlign.right => slack,
            _ => 0,
          };
          for (final List<PdfDrawText> line in lines) {
            expect(line.first.x, closeTo(20 + 7.2 + offset, 0.01));
          }
          // PdfDrawText reports the top of the font box (baseline minus size).
          expect(lines.first.first.y, closeTo(55, 0.01));
          expect(lines.last.first.y - lines.first.first.y, closeTo(25, 0.01));
        },
      );
    }
  }

  test('numeric multiline Standard 14 fallback keeps authored order', () {
    final PdfFile file = PdfFile.open(
      OfficePdfExport.presentation(
        PmlPresentation(
          slides: [
            PmlSlide(id: 256, shapes: [_textShape('12 34\n56 78')]),
          ],
        ),
      ),
    );
    expect(
      _paintedLines(file).map((line) => line.map((op) => op.text).join()),
      ['12 34', '56 78'],
    );
    expect(PdfExtract.pageText(file, 0), isNot(matches('[\u200e\u202d]')));
  });

  test('RTL numeric spaced groups retain their existing bidi ordering', () {
    final PdfFile file = export(_textShape('12 34\n56 78', rightToLeft: true));
    expect(
      _paintedLines(file).map((line) => line.map((op) => op.text).join()),
      ['34 12', '78 56'],
    );
    expect(PdfExtract.pageText(file, 0), isNot(matches('[\u200e\u202d]')));
  });

  test('mixed numeric styles retain source order across line breaks', () {
    final PdfFile file = export(
      _textShape(
        '12 34\n56 78',
        runs: [
          PmlTextRun(text: '12 ', fontSizePt: 20, color: 'FF0000'),
          PmlTextRun(text: '34\n56 ', fontSizePt: 20, color: '0000FF'),
          PmlTextRun(text: '78', fontSizePt: 20, color: 'FF0000'),
        ],
      ),
    );
    expect(
      _paintedLines(file).map((line) => line.map((op) => op.text).join()),
      ['1234', '5678'],
    );
    final List<PdfDrawText> painted = _paintedLines(
      file,
    ).expand((line) => line).toList();
    expect(
      painted.where((op) => op.color == 0xFFFF0000).map((op) => op.text).join(),
      '1278',
    );
    expect(
      painted.where((op) => op.color == 0xFF0000FF).map((op) => op.text).join(),
      '3456',
    );
  });

  test(
    'hidden master flag retains resolved layout decoration text and links',
    () {
      final PmlPresentation deck = PmlPresentation(
        master: PmlMaster(
          name: 'Master',
          shapes: [_textShape('Hidden master')],
        ),
        slides: [
          PmlSlide(
            id: 256,
            showMasterShapes: false,
            backgroundShapes: [
              _textShape('Layout decoration')
                ..hyperlinkUrl = 'https://example.org/layout',
            ],
          ),
        ],
      );
      for (final PdfSlideExportMode mode in PdfSlideExportMode.values) {
        for (final int perPage in [1, 2]) {
          final PdfFile file = PdfFile.open(
            OfficePdfExport.presentation(
              deck,
              mode: mode,
              slidesPerPage: perPage,
              font: font,
            ),
          );
          expect(PdfExtract.documentText(file), contains('Layout decoration'));
          expect(
            PdfExtract.documentText(file),
            isNot(contains('Hidden master')),
          );
          expect(
            file.annotsOn(0).map((link) => link.uri),
            contains('https://example.org/layout'),
          );
        }
      }
    },
  );

  test(
    'hidden master shapes stay absent in PDF with an empty decoration list',
    () {
      final PmlPresentation deck = PmlPresentation(
        master: PmlMaster(
          name: 'Master',
          shapes: [_textShape('Hidden master')],
        ),
        slides: [PmlSlide(id: 256, showMasterShapes: false)],
      );
      for (final PdfSlideExportMode mode in PdfSlideExportMode.values) {
        final PdfFile file = PdfFile.open(
          OfficePdfExport.presentation(deck, mode: mode, font: font),
        );
        expect(PdfExtract.documentText(file), isNot(contains('Hidden master')));
      }
      final PdfFile pair = PdfFile.open(
        OfficePdfExport.presentation(deck, slidesPerPage: 2, font: font),
      );
      expect(PdfExtract.documentText(pair), isNot(contains('Hidden master')));
    },
  );
}
