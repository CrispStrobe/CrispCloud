import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  test(
    'imported footnote references are superscript and notes are laid out',
    () {
      final WmlDocument document = WordDeserializer().readBytes(
        File('test/fixtures/footnote.docx').readAsBytesSync(),
      );

      final WmlParagraph title = document.paragraphs.firstWhere(
        (WmlParagraph p) => p.text.contains('Madness'),
      );
      WmlRun? reference;
      for (final WmlInline inline in title.inlines) {
        if (inline is WmlRun && inline.noteRefId != null) {
          reference = inline;
          break;
        }
      }
      expect(reference, isNotNull);
      expect(reference!.properties.vertAlign, WmlVertAlign.superscript);

      final LaidOutDocument laid = WordLayoutEngine(
        font: null,
      ).layout(document);
      final List<String> notes = laid.pages
          .expand((LaidOutPage page) => page.notes)
          .map((LaidOutLine line) => line.overlayText ?? '')
          .toList();
      expect(notes, contains('1. First footnote text.'));
      expect(notes, contains('2. Second footnote text.'));
    },
  );
}
