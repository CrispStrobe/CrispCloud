import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

WordEditorController _controller(String text, {bool allCaps = true}) {
  final document = WmlDocument.empty(text: text)..proofingLanguage = 'de-DE';
  document.paragraphs.single.inlines.whereType<WmlRun>().single.properties =
      WmlRunProps(allCaps: allCaps, fontSizeHalfPoints: 24);
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

String _painted(WordEditorController controller) {
  final paragraph = controller.document.paragraphs.single;
  return controller.documentLaidOut.pages
      .expand((page) => page.lines)
      .expand(PaintRunText.paintSegments)
      .map((run) => PaintRunText.runText(paragraph.text, run))
      .join();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);

  test('editor paints all capitals at original font size', () {
    final controller = _controller('Straße ﬃ');
    expect(_painted(controller), 'STRASSE FFI');
    final line = controller.documentLaidOut.pages.single.lines.single;
    expect(line.glyphs.every((glyph) => glyph.fontSize == 12), isTrue);
    expect(controller.document.paragraphs.single.text, 'Straße ﬃ');
    expect(controller.canUndo, isFalse);
  });

  test(
    'expansions and supplementary letters expose only source caret stops',
    () {
      const source = 'ßﬃ𐐨';
      final controller = _controller(source);
      final line = controller.documentLaidOut.pages.single.lines.single;
      final segments = PaintRunText.paintSegments(line).toList();
      expect(segments.map((run) => PaintRunText.runText(source, run)), [
        'SS',
        'FFI',
        '𐐀',
      ]);
      for (final (start, end) in [(0, 1), (1, 2), (2, 4)]) {
        final group = line.glyphs
            .where((glyph) => glyph.glyph.logicalIndex == start)
            .toList();
        final left = group.first.x;
        final right = group.last.x + group.last.advance;
        expect(group.every((glyph) => glyph.logicalEnd == end), isTrue);
        expect(CaretEngine.caretX(line, start), closeTo(left, 0.001));
        expect(CaretEngine.caretX(line, end), closeTo(right, 0.001));
        expect(
          CaretEngine.hitLogicalIndex(line, left + (right - left) * 0.2),
          start,
        );
        expect(
          CaretEngine.hitLogicalIndex(line, left + (right - left) * 0.8),
          end,
        );
        _select(controller, start, end);
        final bands = controller.caret.selectionRectsOnLine(
          line,
          line.y,
          line.height,
          paragraph: 0,
          lastOfParagraph: false,
        );
        expect(bands, hasLength(1));
        expect(bands.single.left, closeTo(left, 0.001));
        expect(bands.single.right, closeTo(right, 0.001));
      }
      expect(controller.document.paragraphs.single.text, source);
    },
  );

  test('combining display preserves the whole authored cluster', () {
    const source = 'a\u0301z';
    final controller = _controller(source);
    final line = controller.documentLaidOut.pages.single.lines.single;
    final cluster = line.glyphs
        .where((glyph) => glyph.glyph.logicalIndex == 0)
        .toList();
    expect(cluster, hasLength(2));
    expect(cluster.every((glyph) => glyph.logicalEnd == 2), isTrue);
    expect(cluster.every((glyph) => glyph.fontSize == 12), isTrue);
    expect(_painted(controller), 'A\u0301Z');
    expect(controller.document.paragraphs.single.text, source);
  });

  test('formatting refresh, undo and redo retain authored letters', () {
    final controller = _controller('Straße ﬃ', allCaps: false);
    expect(_painted(controller), 'Straße ﬃ');
    _select(controller, 0, controller.document.paragraphs.single.text.length);
    controller.applyRunFormat((props) => props.allCaps = true);
    expect(_painted(controller), 'STRASSE FFI');
    expect(controller.canUndo, isTrue);
    final reopened = WordDeserializer().readBytes(controller.saveBytes());
    expect(reopened.paragraphs.single.text, 'Straße ﬃ');
    expect(
      reopened.paragraphs.single.inlines
          .whereType<WmlRun>()
          .single
          .properties
          .allCaps,
      isTrue,
    );
    controller.undo();
    expect(_painted(controller), 'Straße ﬃ');
    expect(controller.canUndo, isFalse);
    controller.redo();
    expect(_painted(controller), 'STRASSE FFI');
    expect(controller.document.paragraphs.single.text, 'Straße ﬃ');
    expect(
      controller.documentLaidOut.pages.single.lines.single.glyphs.every(
        (glyph) => glyph.fontSize == 12,
      ),
      isTrue,
    );
  });

  test(
    'copy and rich paste retain source letters and independent caps flags',
    () async {
      final clipboard = OfficeClipboard.instance;
      final previous = clipboard.useSystem;
      clipboard.useSystem = false;
      addTearDown(() {
        clipboard
          ..useSystem = previous
          ..clear();
      });
      final controller = _controller('ßﬃ');
      _select(controller, 0, 2);
      await controller.copyToClipboard();
      final payload = clipboard.local!;
      expect(payload.plain, 'ßﬃ');
      expect(payload.paragraphs.single.single.text, 'ßﬃ');
      expect(payload.paragraphs.single.single.props.allCaps, isTrue);
      controller.document.paragraphs.single.inlines
              .whereType<WmlRun>()
              .single
              .properties
              .allCaps =
          false;
      expect(payload.paragraphs.single.single.props.allCaps, isTrue);
      final pasted = _controller('', allCaps: false);
      await pasted.pasteFromClipboard();
      expect(pasted.document.paragraphs.single.text, 'ßﬃ');
      expect(_painted(pasted), 'SSFFI');
      expect(
        pasted.document.paragraphs.single.inlines
            .whereType<WmlRun>()
            .single
            .properties
            .allCaps,
        isTrue,
      );
    },
  );

  test('captured proofing controls reject direct all-capital mutations', () {
    final controller = _controller('Straße');
    final target = controller.textProofingTarget!;
    final revision = controller.contentRevision;
    controller.document.paragraphs.single.inlines
            .whereType<WmlRun>()
            .single
            .properties
            .allCaps =
        false;
    expect(controller.contentRevision, revision);
    expect(
      controller.setTextProofingLanguage('en-US', target: target),
      isFalse,
    );
    expect(controller.setTextProofingEnabled(false, target: target), isFalse);
    expect(controller.document.paragraphs.single.text, 'Straße');
    expect(controller.canUndo, isFalse);
  });

  test('captured proofing ranges bind direct capitalization formatting', () {
    final controller = _controller('Straße');
    final paragraph = controller.document.paragraphs.single;
    final capture = controller.proofing.captureTextRange(paragraph, 0, 6);
    expect(capture.status, WordTextRangeStatus.ready);
    expect(capture.target!.text, 'Straße');
    expect(controller.proofing.isTextRangeCurrent(capture.target!), isTrue);
    final revision = controller.contentRevision;
    paragraph.inlines.whereType<WmlRun>().single.properties.allCaps = false;
    expect(controller.contentRevision, revision);
    expect(controller.proofing.isTextRangeCurrent(capture.target!), isFalse);
    final replacement = controller.proofing.captureTextRange(paragraph, 0, 6);
    expect(replacement.status, WordTextRangeStatus.ready);
    expect(controller.proofing.isTextRangeCurrent(replacement.target!), isTrue);
    expect(controller.canUndo, isFalse);
  });
}
