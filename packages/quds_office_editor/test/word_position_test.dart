import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

WordEditorController _controller(
  List<(String, int)> runs, {
  WmlVertAlign alignment = WmlVertAlign.baseline,
}) {
  final document = WmlDocument.empty()..proofingLanguage = 'en-GB';
  document.paragraphs.single.inlines
    ..clear()
    ..addAll([
      for (final (text, position) in runs)
        WmlRun(
          text: text,
          properties: WmlRunProps(
            asciiFont: 'Liberation Serif',
            fontSizeHalfPoints: 24,
            vertAlign: alignment,
            positionHalfPoints: position,
          ),
        ),
    ]);
  final controller = WordEditorController(document: document);
  addTearDown(controller.dispose);
  return controller;
}

void _select(WordEditorController controller, int start, int end) {
  controller.caret
    ..paragraphIndex = 0
    ..logicalIndex = end
    ..selectionAnchorParagraph = 0
    ..selectionAnchor = start;
}

List<int> _positions(WmlDocument document) => [
  for (var index = 0; index < document.paragraphs.single.text.length; index++)
    WmlRunEdit.propsAt(document.paragraphs.single, index).positionHalfPoints,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);

  test('raised and lowered text keep separate paint runs and font sizes', () {
    final controller = _controller([
      ('AB', 0),
      ('CD', 6),
      ('EF', -4),
      ('GH', 0),
    ]);
    final paragraph = controller.document.paragraphs.single;
    final line = controller.documentLaidOut.pages.single.lines.single;
    final segments = PaintRunText.paintSegments(line).toList();
    expect(segments.map((run) => PaintRunText.runText(paragraph.text, run)), [
      'AB',
      'CD',
      'EF',
      'GH',
    ]);
    expect(segments.map((run) => run.first.positionHalfPoints), [0, 6, -4, 0]);
    expect(line.glyphs.every((glyph) => glyph.fontSize == 12), isTrue);
    final baseline = segments.first.first.y;
    expect(segments[1].first.y, closeTo(baseline - 3, 0.001));
    expect(segments[2].first.y, closeTo(baseline + 2, 0.001));
    expect(segments[3].first.y, closeTo(baseline, 0.001));
    controller.fitPaintMetrics();
    expect(paragraph.text, 'ABCDEFGH');
    final fittedLine = controller.documentLaidOut.pages.single.lines.single;
    for (final segment in PaintRunText.paintSegments(fittedLine)) {
      final start = segment.first.glyph.logicalIndex;
      final end = segment.last.logicalEnd;
      expect(
        PaintRunText.caretXOnLine(fittedLine, start, paragraph: paragraph.text),
        closeTo(segment.first.x, 0.001),
      );
      expect(
        PaintRunText.caretXOnLine(fittedLine, end, paragraph: paragraph.text),
        closeTo(segment.last.x + segment.last.advance, 0.001),
      );
    }
    expect(controller.canUndo, isFalse);
  });

  test('position remains independent of superscript painting', () {
    final controller = _controller([
      ('A', 0),
      ('B', 6),
    ], alignment: WmlVertAlign.superscript);
    final line = controller.documentLaidOut.pages.single.lines.single;
    final segments = PaintRunText.paintSegments(line).toList();
    expect(segments, hasLength(2));
    final ordinary = segments.first.single;
    final raised = segments.last.single;
    expect(ordinary.vertAlign, WmlVertAlign.superscript);
    expect(raised.vertAlign, WmlVertAlign.superscript);
    expect(raised.fontSize, ordinary.fontSize);
    expect(raised.y, closeTo(ordinary.y - 3, 0.001));
    expect(controller.document.paragraphs.single.text, 'AB');
  });

  test('selected position formatting supports undo, redo and DOCX reopen', () {
    final controller = _controller([('ABCD', 0)]);
    _select(controller, 1, 3);
    controller.applyRunFormat((props) => props.positionHalfPoints = -5);
    expect(_positions(controller.document), [0, -5, -5, 0]);
    expect(controller.document.paragraphs.single.text, 'ABCD');
    expect(controller.canUndo, isTrue);
    final reopened = WordDeserializer().readBytes(controller.saveBytes());
    expect(reopened.paragraphs.single.text, 'ABCD');
    expect(_positions(reopened), [0, -5, -5, 0]);
    expect(
      reopened.paragraphs.single.inlines.whereType<WmlRun>().every(
        (run) => run.properties.fontSizeHalfPoints == 24,
      ),
      isTrue,
    );
    controller.undo();
    expect(_positions(controller.document), [0, 0, 0, 0]);
    expect(controller.canUndo, isFalse);
    controller.redo();
    expect(_positions(controller.document), [0, -5, -5, 0]);
    expect(
      controller.documentLaidOut.pages.single.lines.single.glyphs.map(
        (glyph) => glyph.positionHalfPoints,
      ),
      [0, -5, -5, 0],
    );
  });

  test('rich clipboard copies position independently of the source', () async {
    final clipboard = OfficeClipboard.instance;
    final previous = clipboard.useSystem;
    clipboard.useSystem = false;
    addTearDown(() {
      clipboard
        ..useSystem = previous
        ..clear();
    });
    final source = _controller([('Raised', 7)]);
    _select(source, 0, 6);
    await source.copyToClipboard();
    final payload = clipboard.local!;
    expect(payload.plain, 'Raised');
    expect(payload.paragraphs.single.single.props.positionHalfPoints, 7);
    source.document.paragraphs.single.inlines
            .whereType<WmlRun>()
            .single
            .properties
            .positionHalfPoints =
        0;
    expect(payload.paragraphs.single.single.props.positionHalfPoints, 7);
    final pasted = _controller([('', 0)]);
    await pasted.pasteFromClipboard();
    expect(pasted.document.paragraphs.single.text, 'Raised');
    expect(_positions(pasted.document), List<int>.filled(6, 7));
    expect(
      pasted.documentLaidOut.pages.single.lines.single.glyphs.every(
        (glyph) => glyph.positionHalfPoints == 7 && glyph.fontSize == 12,
      ),
      isTrue,
    );
  });

  test('captured proofing controls reject direct position mutations', () {
    final controller = _controller([('Position', 6)]);
    final target = controller.textProofingTarget!;
    final revision = controller.contentRevision;
    controller.document.paragraphs.single.inlines
            .whereType<WmlRun>()
            .single
            .properties
            .positionHalfPoints =
        -4;
    expect(controller.contentRevision, revision);
    expect(
      controller.setTextProofingLanguage('de-DE', target: target),
      isFalse,
    );
    expect(controller.setTextProofingEnabled(false, target: target), isFalse);
    expect(controller.document.paragraphs.single.text, 'Position');
    expect(controller.canUndo, isFalse);
  });

  test('captured proofing ranges bind position even without a revision', () {
    final controller = _controller([('Position', 6)]);
    final paragraph = controller.document.paragraphs.single;
    final capture = controller.proofing.captureTextRange(paragraph, 0, 8);
    expect(capture.status, WordTextRangeStatus.ready);
    expect(controller.proofing.isTextRangeCurrent(capture.target!), isTrue);
    final revision = controller.contentRevision;
    paragraph.inlines.whereType<WmlRun>().single.properties.positionHalfPoints =
        0;
    expect(controller.contentRevision, revision);
    expect(controller.proofing.isTextRangeCurrent(capture.target!), isFalse);
    final replacement = controller.proofing.captureTextRange(paragraph, 0, 8);
    expect(replacement.status, WordTextRangeStatus.ready);
    expect(controller.proofing.isTextRangeCurrent(replacement.target!), isTrue);
    expect(controller.canUndo, isFalse);
  });
}
