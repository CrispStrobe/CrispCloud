import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('CrispCloud: imported footnote marks are superscript', () {
    final Uint8List bytes = File(
      'test/fixtures/footnote.docx',
    ).readAsBytesSync();
    final WordEditorController controller = WordEditorController.fromBytes(
      bytes,
    );
    addTearDown(controller.dispose);

    final WmlParagraph title = controller.document.paragraphs.firstWhere(
      (WmlParagraph p) => p.text.contains('Madness'),
    );
    WmlRun? ref;
    for (final WmlInline inline in title.inlines) {
      if (inline is WmlRun && inline.noteRefId != null) {
        ref = inline;
        break;
      }
    }
    expect(ref, isNotNull);
    expect(ref!.properties.vertAlign, WmlVertAlign.superscript);
  });

  test('CrispCloud: header edits relayout into the header band', () {
    final WordEditorController controller = WordEditorController(
      document: WmlDocument.empty(text: 'BODY'),
    );
    addTearDown(controller.dispose);
    controller.beginHeaderFooterEdit(0, footer: false);
    controller.insertText('HEADER');

    final LaidOutPage page = controller.documentLaidOut.pages.first;
    final String header = page.header
        .map((LaidOutLine line) => line.overlayText ?? '')
        .join();
    final String body = page.lines
        .expand((LaidOutLine line) => line.glyphs)
        .map((LaidOutGlyph g) => String.fromCharCode(g.glyph.codePoint))
        .join();
    expect(header, 'HEADER');
    expect(body, 'BODY');
  });

  test('CrispCloud: select all marks the whole document', () {
    final WordEditorController controller = WordEditorController(
      document: WmlDocument.empty(text: 'Hello'),
    );
    addTearDown(controller.dispose);
    controller.selectAll();
    expect(controller.caret.isCollapsed, isFalse);
    expect(controller.caret.selectionAnchorParagraph, 0);
    expect(controller.caret.selectionAnchor, 0);
    expect(controller.caret.logicalIndex, 5);
  });
}
