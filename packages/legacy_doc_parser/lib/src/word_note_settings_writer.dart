// SPDX-License-Identifier: MPL-2.0

part of 'conversion.dart';

extension _WordNoteSettingsWriter on _StructuredWordWriter {
  void _writeSectionNoteSettings(LegacyWordSection section) {
    if (section.footnotes case final settings?) {
      _writeFootnoteSettings(_xml, settings);
    }
    if (section.endnotes case final settings?) {
      _writeEndnoteSettings(_xml, settings);
    }
  }

  void _writeDocumentNoteSettings(_BoundedWordXml xml) {
    _writeFootnoteSettings(xml, document.footnotes, documentWide: true);
    _writeEndnoteSettings(xml, document.endnotes, documentWide: true);
  }

  void _writeFootnoteSettings(
    _BoundedWordXml xml,
    LegacyWordFootnoteSettings settings, {
    bool documentWide = false,
  }) {
    xml.add(
      '<w:footnotePr><w:pos w:val="${switch (settings.position) {
        LegacyWordFootnotePosition.pageBottom => 'pageBottom',
        LegacyWordFootnotePosition.beneathText => 'beneathText',
        LegacyWordFootnotePosition.sectionEnd => 'sectEnd',
      }}"/>',
    );
    _writeNoteNumbering(xml, settings.numbering);
    if (documentWide) _writeSpecialNoteReferences(xml, endnote: false);
    xml.add('</w:footnotePr>');
  }

  void _writeEndnoteSettings(
    _BoundedWordXml xml,
    LegacyWordEndnoteSettings settings, {
    bool documentWide = false,
  }) {
    xml.add(
      '<w:endnotePr><w:pos w:val="${switch (settings.position) {
        LegacyWordEndnotePosition.documentEnd => 'docEnd',
        LegacyWordEndnotePosition.sectionEnd => 'sectEnd',
      }}"/>',
    );
    _writeNoteNumbering(xml, settings.numbering);
    if (documentWide) _writeSpecialNoteReferences(xml, endnote: true);
    xml.add('</w:endnotePr>');
  }

  void _writeNoteNumbering(
    _BoundedWordXml xml,
    LegacyWordNoteNumbering numbering,
  ) {
    if (numbering.startAt < 0 || numbering.startAt > 16383) {
      throw const FormatException('Invalid Word note numbering start.');
    }
    xml.add(
      '<w:numFmt w:val="${numbering.format.name}"/>'
      '<w:numStart w:val="${numbering.startAt}"/>'
      '<w:numRestart w:val="${switch (numbering.restart) {
        LegacyWordNoteRestart.continuous => 'continuous',
        LegacyWordNoteRestart.eachSection => 'eachSect',
        LegacyWordNoteRestart.eachPage => 'eachPage',
      }}"/>',
    );
  }

  void _writeSpecialNoteReferences(
    _BoundedWordXml xml, {
    required bool endnote,
  }) {
    // Match only the special notes that _writeAuxiliaryStories actually
    // emitted. Hidden/private note content is never activated by settings.
    if (!document.noteReferences.any(
      (reference) =>
          reference.endnote == endnote &&
          !_inertStories.containsKey(reference.storyId),
    )) {
      return;
    }
    final name = endnote ? 'endnote' : 'footnote';
    xml.add('<w:$name w:id="-1"/><w:$name w:id="0"/>');
    final noticeKind = endnote
        ? LegacyWordStoryKind.endnoteContinuationNotice
        : LegacyWordStoryKind.footnoteContinuationNotice;
    if (document.stories.any((story) => story.kind == noticeKind)) {
      xml.add('<w:$name w:id="-2"/>');
    }
  }
}
