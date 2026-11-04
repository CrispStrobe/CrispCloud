import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('header edits relayout into the header band, not the body', () {
    final WordEditorController controller =
        WordEditorController(document: WmlDocument.empty(text: 'BODY'));
    addTearDown(controller.dispose);
    controller.beginHeaderFooterEdit(0, footer: false);
    controller.insertText('HEADER');

    final LaidOutPage page = controller.documentLaidOut.pages.first;
    String glyphsOf(List<LaidOutLine> lines) => lines
        .expand((LaidOutLine line) => line.glyphs)
        .map((LaidOutGlyph g) => String.fromCharCode(g.glyph.codePoint))
        .join();
    String overlayOf(List<LaidOutLine> lines) =>
        lines.map((LaidOutLine line) => line.overlayText ?? '').join();

    // Header/footer stories render as overlay text, not body glyphs.
    expect(overlayOf(page.header), 'HEADER');
    expect(glyphsOf(page.lines), 'BODY');
    expect(overlayOf(page.footer), isEmpty);
  });

  test('select all marks the whole document', () {
    final WordEditorController controller =
        WordEditorController(document: WmlDocument.empty(text: 'Hello'));
    addTearDown(controller.dispose);
    controller.selectAll();
    expect(controller.caret.isCollapsed, isFalse);
    expect(controller.caret.selectionAnchorParagraph, 0);
    expect(controller.caret.selectionAnchor, 0);
    expect(controller.caret.logicalIndex, 5);
  });
}
