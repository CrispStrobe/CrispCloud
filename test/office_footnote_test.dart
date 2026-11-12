// test/office_footnote_test.dart
//
// Imported footnote marks must remain superscript, with both note bodies
// visibly laid out in the reserved note band on the reference's page.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:xml/xml.dart' as xml;

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
    // The authored note bodies contain no automatic note marks. Assert that
    // independently of the importer before comparing their visible layout.
    const wordNamespace =
        'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
    final archive = ZipDecoder().decodeBytes(bytes);
    final sourceNotes =
        xml.XmlDocument.parse(
              utf8.decode(archive.findFile('word/footnotes.xml')!.content),
            )
            .findAllElements('footnote', namespace: wordNamespace)
            .where(
              (note) =>
                  note.getAttribute('type', namespace: wordNamespace) == null,
            )
            .toList();
    expect(
      sourceNotes.map(
        (note) => note.getAttribute('id', namespace: wordNamespace),
      ),
      ['1', '2'],
    );
    expect(
      sourceNotes.expand(
        (note) => note.findAllElements('footnoteRef', namespace: wordNamespace),
      ),
      isEmpty,
    );
    final authoredBodies = sourceNotes
        .map(
          (note) => note
              .findAllElements('t', namespace: wordNamespace)
              .map((text) => text.innerText)
              .join(),
        )
        .toList();
    expect(authoredBodies, ['First footnote text.', 'Second footnote text.']);
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
    expect(page.notes.map(_visibleText), authoredBodies);
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
