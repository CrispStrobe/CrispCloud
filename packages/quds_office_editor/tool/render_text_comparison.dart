// Run explicitly with Flutter's test renderer; ordinary test runs do not find
// this tool, and it writes nothing unless an output directory is supplied:
// flutter test --no-pub tool/render_text_comparison.dart \
//   --dart-define=QUDS_TEXT_RENDERING_OUTPUT=/absolute/output/directory
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_editor/src/editor_word/word_run_metrics.dart';

const _output = String.fromEnvironment('QUDS_TEXT_RENDERING_OUTPUT');
const _source = 'AV AV';
const _size = 32.0;
const _font = 'Liberation Serif';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'render actual Flutter scalar and shaped wrapping',
    () async {
      await OfficeHostFonts.ensureRegistered();
      final props = WmlRunProps(asciiFont: _font, fontSizeHalfPoints: 64);
      final contextual = WordRunMetrics.measure(
        _source,
        _size,
        props,
        0,
      )!.fold<double>(0, (sum, cluster) => sum + cluster.advance);
      final scalar = _source.runes.fold<double>(
        0,
        (sum, cp) => sum + PaintRunText.advanceOf(cp, _size, props),
      );
      expect(scalar, greaterThan(contextual));
      final width = (contextual + scalar) / 2;
      final previous = WordEditorController(
        document: _document(width),
        layoutEngine: WordLayoutEngine(
          font: null,
          measure: PaintRunText.advanceOf,
        ),
      );
      final improved = WordEditorController(document: _document(width));
      try {
        final oldBefore = _lines(previous).map((line) => line.width).toList();
        final newBefore = _lines(improved).map((line) => line.width).toList();
        expect(oldBefore.length, greaterThan(1));
        expect(newBefore, hasLength(1));
        previous.fitPaintMetrics();
        improved.fitPaintMetrics();
        final oldLines = _lines(previous);
        final newLines = _lines(improved);
        expect(oldLines.length, greaterThan(1));
        expect(newLines, hasLength(1));
        expect(newLines.single.width, lessThan(width));

        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawColor(const Color(0xFFF5F7FA), BlendMode.src);
        _label(
          canvas,
          'Text wrapping with real font shaping',
          48,
          40,
          31,
          bold: true,
        );
        _label(
          canvas,
          'Same source, bundled font, size and available width.',
          48,
          87,
          19,
          color: const Color(0xFF516172),
        );
        _panel(
          canvas,
          left: 48,
          title: 'Previous: scalar measurement',
          subtitle: 'Character widths added separately',
          accent: const Color(0xFF9B5A19),
          lines: oldLines,
          width: width,
        );
        _panel(
          canvas,
          left: 624,
          title: 'Improved: shaped measurement',
          subtitle: 'Context measured before wrapping',
          accent: const Color(0xFF087F75),
          lines: newLines,
          width: width,
        );
        _label(
          canvas,
          'Scalar sum: ${scalar.toStringAsFixed(3)} pt    '
          'Shaped run: ${contextual.toStringAsFixed(3)} pt    '
          'Box: ${width.toStringAsFixed(3)} pt',
          48,
          602,
          18,
        );
        _label(
          canvas,
          'Actual Flutter TextPainter output from laid-out Word runs. '
          'Diagnostic fixture; not an application screenshot.',
          48,
          638,
          14,
          color: const Color(0xFF516172),
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(1200, 680);
        try {
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          expect(bytes, isNotNull);
          final output = Directory(_output)..createSync(recursive: true);
          File('${output.path}/text-rendering-comparison.png').writeAsBytesSync(
            bytes!.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
          );
          File('${output.path}/metrics.json').writeAsStringSync(
            '${const JsonEncoder.withIndent('  ').convert({
              'fixture': {'text': _source, 'font': _font, 'font_size_points': _size, 'content_width_points': width, 'scalar_width_points': scalar, 'shaped_width_points': contextual, 'raster_pixels_per_point': 2.7},
              'previous_scalar_path': {'line_count': oldLines.length, 'line_text': oldLines.map((line) => line.text).toList(), 'widths_before_paint_fit': oldBefore, 'widths_after_paint_fit': oldLines.map((line) => line.width).toList()},
              'improved_shaped_path': {'line_count': newLines.length, 'line_text': newLines.map((line) => line.text).toList(), 'widths_before_paint_fit': newBefore, 'widths_after_paint_fit': newLines.map((line) => line.width).toList()},
              'renderer': 'Flutter test engine; Canvas and PaintRunText TextPainter',
              'dart_runtime': Platform.version,
              'scope': 'Deterministic typography diagnostic, not a full application screenshot.',
              'reproduce': 'flutter test --no-pub tool/render_text_comparison.dart '
                  '--dart-define=QUDS_TEXT_RENDERING_OUTPUT=/absolute/output/directory',
            })}\n',
          );
        } finally {
          image.dispose();
          picture.dispose();
        }
      } finally {
        previous.dispose();
        improved.dispose();
      }
    },
    skip: _output.isEmpty
        ? 'Pass --dart-define=QUDS_TEXT_RENDERING_OUTPUT=/absolute/output/directory'
        : false,
  );
}

void _panel(
  Canvas canvas, {
  required double left,
  required String title,
  required String subtitle,
  required Color accent,
  required List<LaidOutLine> lines,
  required double width,
}) {
  const top = 150.0;
  final panel = Rect.fromLTWH(left, top, 528, 420);
  canvas.drawRRect(
    RRect.fromRectAndRadius(panel, const Radius.circular(15)),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(panel, const Radius.circular(15)),
    Paint()
      ..color = const Color(0xFFD9E1E8)
      ..style = PaintingStyle.stroke,
  );
  _label(canvas, title, left + 28, top + 25, 22, bold: true, color: accent);
  _label(
    canvas,
    subtitle,
    left + 28,
    top + 59,
    16,
    color: const Color(0xFF516172),
  );
  const scale = 2.7;
  final box = Rect.fromLTWH(left + 56, top + 113, width * scale, 220);
  canvas.drawRect(box, Paint()..color = const Color(0xFFFBFCFE));
  canvas.drawRect(
    box,
    Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5,
  );
  canvas.save();
  canvas.translate(box.left, box.top + 6);
  canvas.scale(scale);
  canvas.translate(-10, -lines.first.y);
  for (final line in lines) {
    for (final segment in PaintRunText.paintSegments(line)) {
      final text = PaintRunText.runText(_source, segment);
      final painter = PaintRunText.painterFor(
        text: text,
        first: segment.first,
        color: const Color(0xFF182638),
      );
      try {
        painter.layout();
        painter.paint(
          canvas,
          Offset(
            PaintRunText.runPaintOrigin(segment, painter, text, _source),
            line.y,
          ),
        );
      } finally {
        painter.dispose();
      }
    }
  }
  canvas.restore();
  _label(
    canvas,
    '${lines.length} ${lines.length == 1 ? 'line' : 'lines'}',
    left + 28,
    top + 359,
    25,
    bold: true,
    color: accent,
  );
  _label(
    canvas,
    '$_font  ·  ${_size.toInt()} pt',
    left + 160,
    top + 365,
    17,
    color: const Color(0xFF516172),
  );
}

void _label(
  Canvas canvas,
  String text,
  double x,
  double y,
  double size, {
  bool bold = false,
  Color color = const Color(0xFF182638),
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: 'Liberation Sans',
        fontSize: size,
        color: color,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      ),
    ),
    textDirection: TextDirection.ltr,
  );
  try {
    painter.layout();
    painter.paint(canvas, Offset(x, y));
  } finally {
    painter.dispose();
  }
}

WmlDocument _document(double width) => WmlDocument(
  sections: [
    WmlSection(
      pageSize: WmlPageSize(width: width + 20, height: 200),
      margins: const WmlPageMargins(left: 10, right: 10, top: 10, bottom: 10),
      blocks: [
        WmlParagraph(
          properties: WmlParagraphProps(spacingAfter: 0),
          inlines: [
            WmlRun(
              text: _source,
              properties: WmlRunProps(asciiFont: _font, fontSizeHalfPoints: 64),
            ),
          ],
        ),
      ],
    ),
  ],
);

List<LaidOutLine> _lines(WordEditorController controller) =>
    controller.documentLaidOut.pages.expand((page) => page.lines).toList();
