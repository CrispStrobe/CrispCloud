// test/office_footnote_test.dart
//
// Imported footnote marks must remain superscript, with both note bodies
// visibly laid out in the reserved note band on the reference's page.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

String _visibleText(LaidOutLine line) {
  if (line.glyphs.isEmpty) return line.overlayText ?? '';
  final glyphs = List<LaidOutGlyph>.of(line.glyphs)
    ..sort((a, b) => a.glyph.logicalIndex.compareTo(b.glyph.logicalIndex));
  return String.fromCharCodes(glyphs.map((glyph) => glyph.glyph.codePoint));
}

void main() {
  test('DOCX footnote references are superscript and notes are laid out', () {
    final Uint8List bytes = File('test/fixtures/footnote.docx')
        .readAsBytesSync();
    final WordEditorController controller = WordEditorController.fromBytes(
      bytes,
    );
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
    // Rich notes use shaped glyphs; plain overlays remain a supported fallback.
    // Assert the actual visible text rather than an implementation-only field.
    expect(page.notes.map(_visibleText), <String>[
      '1. First footnote text.',
      '2. Second footnote text.',
    ]);
    final separator = page.frames
        .where((box) => box.kind == LaidOutBoxKind.footnote)
        .single;
    final section = controller.document.sections[page.sectionIndex];
    for (final line in page.lines) {
      expect(line.y + line.height, lessThanOrEqualTo(separator.y + 0.01));
    }
    for (final line in page.notes) {
      expect(line.pageIndex, page.index);
      expect(line.y, greaterThanOrEqualTo(separator.y));
      expect(
        line.y + line.height,
        lessThanOrEqualTo(
          section.pageSize.height - section.margins.bottom + 0.01,
        ),
      );
    }
  });
}
