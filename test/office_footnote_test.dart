// test/office_footnote_test.dart
//
// Regression coverage for imported DOCX footnote marks. Word stores the
// superscript in the FootnoteReference character style, which the importer
// does not resolve, so the reader must apply it directly.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

void main() {
  test('DOCX footnote references are superscript and notes are laid out', () {
    final Uint8List bytes =
        File('test/fixtures/footnote.docx').readAsBytesSync();
    final WordEditorController controller =
        WordEditorController.fromBytes(bytes);
    addTearDown(controller.dispose);

    expect(controller.document.footnotes.length, 2);

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
    expect(ref.text, '1');

    final LaidOutPage page = controller.documentLaidOut.pages.first;
    expect(
      page.notes.any(
        (LaidOutLine line) =>
            (line.overlayText ?? '').contains('First footnote text.'),
      ),
      isTrue,
    );
  });
}
