import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_editor/src/editor_word/word_run_metrics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);

  test('controller breaks lines using kerning before paint fitting', () {
    const text = 'AV AV';
    const size = 32.0;
    final props = _props(size);
    final shaped = WordRunMetrics.measure(
      text,
      size,
      props,
      0,
    )!.fold<double>(0, (sum, cluster) => sum + cluster.advance);
    final isolated = text.runes.fold<double>(
      0,
      (sum, cp) => sum + PaintRunText.advanceOf(cp, size, props),
    );
    expect(isolated - shaped, greaterThan(0.1));
    final width = (shaped + isolated) / 2;
    final controller = _controller(_document(text, size: size, width: width));

    final before = _lines(controller);
    expect(before, hasLength(1));
    expect(before.single.width, closeTo(shaped, 0.001));
    expect(before.single.width, lessThan(width));
    controller.fitPaintMetrics();
    final after = _lines(controller);
    expect(after, hasLength(1));
    expect(after.single.width, closeTo(shaped, 0.001));
    expect(after.single.text, text);

    // Negative control: the old scalar-only callback cannot make the same
    // correct line-break decision even though paint fitting fixes run widths.
    final scalar = _controller(
      _document(text, size: size, width: width),
      layoutEngine: WordLayoutEngine(
        font: null,
        measure: PaintRunText.advanceOf,
      ),
    );
    expect(_lines(scalar).length, greaterThan(1));
    scalar.fitPaintMetrics();
    expect(_lines(scalar).length, greaterThan(1));
  });

  for (final sample in <({String name, String text, bool rtl})>[
    (name: 'Latin kerning', text: 'AVATAR office', rtl: false),
    (
      name: 'Arabic joining and marks',
      text: 'السَّلَامُ عَلَيْكُمْ',
      rtl: true,
    ),
    (name: 'combining sequence', text: 'Cafe\u0301 a\u0327', rtl: false),
    (name: 'supplementary characters', text: 'A😀𐐨B', rtl: false),
  ]) {
    test('${sample.name} agree before and after paint fitting', () {
      final controller = _controller(
        _document(sample.text, size: 24, width: 450, rtl: sample.rtl),
      );
      final initial = _lines(controller);
      expect(initial, hasLength(1));
      final before = initial.single.width;
      final inkWidth = _paintWidth(initial.single, sample.text);
      expect(before, closeTo(inkWidth, 0.001));

      controller.fitPaintMetrics();
      final fitted = _lines(controller);
      expect(fitted, hasLength(1));
      expect(fitted.single.width, closeTo(before, 0.001));
      expect(fitted.single.text, sample.text);
      expect(controller.document.paragraphs.single.text, sample.text);
      for (final glyph in fitted.single.glyphs) {
        expect(glyph.x.isFinite && glyph.advance.isFinite, isTrue);
        expect(glyph.advance, greaterThanOrEqualTo(0));
      }
    });
  }

  // The narrow case needs a 73.2 pt line box, where 'AV To AV' (73.45 pt
  // shaped) no longer fits. Derive the cell width from the layout's actual
  // default cell margin, also used by the table model, instead of a width
  // coupled to the renderer's former fixed padding.
  const narrowBox = 73.2;
  final narrowCell = narrowBox + 2 * LaidOutLine.tableCellPad;
  for (final cellWidth in [88.0, narrowCell]) {
    test('narrow $cellWidth point cells contain reshaped line fragments', () {
      final paragraphs = [
        _paragraph('AV To AV To AV To', 18),
        _paragraph('السلام عليكم السلام عليكم', 18, rtl: true),
        _paragraph('Cafe\u0301 😀 Cafe\u0301 😀', 18),
      ];
      final document = WmlDocument(
        sections: [
          WmlSection(
              blocks: [
                WmlTable(
                  grid: [cellWidth],
                  properties: WmlTableProps(cellMargin: 4),
                  rows: [
                    WmlTableRow(cells: [WmlTableCell(blocks: paragraphs)]),
                  ],
                ),
              ],
            )
            ..pageSize = const WmlPageSize(width: 300, height: 600)
            ..margins = const WmlPageMargins(
              left: 10,
              right: 10,
              top: 10,
              bottom: 10,
            ),
        ],
      );
      final controller = _controller(document);
      final before = _lines(controller);
      expect(before.length, greaterThan(paragraphs.length));
      if (cellWidth == narrowCell) {
        expect(before.first.boxWidth, closeTo(narrowBox, 0.001));
        expect(
          before.first.text,
          isNot('AV To AV'),
          reason:
              'This fragment grows from 73.125 to 73.4502 after trimming; '
              'the actual line must be reshaped and rebroken before painting.',
        );
      }
      final widths = before.map((line) => line.width).toList();
      for (final line in before) {
        expect(line.width, lessThanOrEqualTo(line.boxWidth + 0.01));
      }
      controller.fitPaintMetrics();
      final after = _lines(controller);
      expect(after, hasLength(before.length));
      for (var i = 0; i < after.length; i++) {
        final line = after[i];
        expect(
          line.width,
          closeTo(widths[i], 0.01),
          reason: 'Line $i: ${line.text}, paragraph ${line.paragraphIndex}',
        );
        expect(line.x, greaterThanOrEqualTo(line.boxX - 0.01));
        expect(
          line.x + line.width,
          lessThanOrEqualTo(line.boxX + line.boxWidth + 0.01),
        );
      }
      expect(document.paragraphs.map((paragraph) => paragraph.text), [
        'AV To AV To AV To',
        'السلام عليكم السلام عليكم',
        'Cafe\u0301 😀 Cafe\u0301 😀',
      ]);
    });
  }

  test('adaptive frame wrapping remeasures a narrow accepted fragment', () {
    const source = 'AV To AV To AV To AV To AV To AV To AV To AV To';
    final document = WmlDocument(
      sections: [
        WmlSection(
          pageSize: const WmlPageSize(width: 193.2, height: 400),
          margins: const WmlPageMargins(
            left: 10,
            right: 10,
            top: 10,
            bottom: 10,
          ),
          blocks: [
            WmlFrame(
              x: 0,
              y: 0,
              width: 100,
              height: 64,
              anchor: WmlFrameAnchor.margin,
              wrap: WmlFrameWrap.square,
              hasTextBox: false,
            ),
            _paragraph(source, 18),
          ],
        ),
      ],
    );
    final controller = _controller(document);
    final before = _lines(controller);
    expect(before.first.boxWidth, closeTo(73.2, 0.001));
    expect(before.first.text, isNot('AV To AV'));
    expect(before.any((line) => line.boxWidth > 73.3), isTrue);
    final widths = before.map((line) => line.width).toList();
    for (final line in before) {
      expect(line.width, lessThanOrEqualTo(line.boxWidth + 0.01));
    }
    controller.fitPaintMetrics();
    final after = _lines(controller);
    expect(after, hasLength(before.length));
    for (var i = 0; i < after.length; i++) {
      expect(after[i].width, closeTo(widths[i], 0.01));
      expect(
        after[i].x + after[i].width,
        lessThanOrEqualTo(after[i].boxX + after[i].boxWidth + 0.01),
      );
    }
    expect(after.map((line) => line.text).join(' '), source);
  });
}

WmlRunProps _props(double size) => WmlRunProps(
  asciiFont: 'Liberation Serif',
  csFont: 'Noto Naskh Arabic',
  fontSizeHalfPoints: (size * 2).round(),
);

WmlParagraph _paragraph(String text, double size, {bool rtl = false}) =>
    WmlParagraph(
        inlines: [WmlRun(text: text, properties: _props(size))],
      )
      ..properties.rightToLeft = rtl
      ..properties.spacingAfter = 0;

WmlDocument _document(
  String text, {
  required double size,
  required double width,
  bool rtl = false,
}) => WmlDocument(
  sections: [
    WmlSection(blocks: [_paragraph(text, size, rtl: rtl)])
      ..pageSize = WmlPageSize(width: width + 20, height: 400)
      ..margins = const WmlPageMargins(
        left: 10,
        right: 10,
        top: 10,
        bottom: 10,
      ),
  ],
);

WordEditorController _controller(
  WmlDocument document, {
  WordLayoutEngine? layoutEngine,
}) {
  final controller = WordEditorController(
    document: document,
    layoutEngine: layoutEngine,
  );
  addTearDown(controller.dispose);
  return controller;
}

List<LaidOutLine> _lines(WordEditorController controller) =>
    controller.documentLaidOut.pages.expand((page) => page.lines).toList();

double _paintWidth(LaidOutLine line, String source) {
  var width = 0.0;
  for (final segment in PaintRunText.paintSegments(line)) {
    final painter = PaintRunText.painterFor(
      text: PaintRunText.runText(source, segment),
      first: segment.first,
    );
    try {
      painter.layout();
      width += painter.width;
    } finally {
      painter.dispose();
    }
  }
  return width;
}
