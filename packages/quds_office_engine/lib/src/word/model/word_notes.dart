import '../properties/wml_properties.dart';
import 'wml_document.dart';

/// Footnote or endnote body.
class WmlNote {
  /// WmlNote API.
  WmlNote({
    required this.id,
    required this.endnote,
    List<WmlParagraph>? paragraphs,
  }) : paragraphs =
           paragraphs ??
           <WmlParagraph>[
             WmlParagraph(inlines: <WmlInline>[WmlRun(text: '')]),
           ];

  /// id API.
  int id;

  /// True for an endnote, false for a footnote.
  final bool endnote;

  /// paragraphs API.
  List<WmlParagraph> paragraphs;

  /// text API.
  String get text =>
      paragraphs.map((WmlParagraph p) => p.text).join('\n').trim();

  /// text API.
  set text(String value) {
    paragraphs
      ..clear()
      ..add(WmlParagraph(inlines: <WmlInline>[WmlRun(text: value)]));
  }
}

/// Inserts and looks up notes on a [WmlDocument].
abstract final class WordNotes {
  /// insert API.
  static WmlNote insert(
    WmlDocument document,
    WmlParagraph paragraph, {
    required bool endnote,
    String text = '',
  }) {
    final List<WmlNote> bucket = endnote
        ? document.endnotes
        : document.footnotes;
    var id = 1;
    for (final WmlNote note in bucket) {
      if (note.id >= id) {
        id = note.id + 1;
      }
    }
    final WmlNote note = WmlNote(id: id, endnote: endnote)..text = text;
    bucket.add(note);
    paragraph.properties.noteId = id;
    paragraph.properties.endnoteRef = endnote;
    paragraph.inlines.add(
      WmlRun(
        text: '$id',
        noteRefId: id,
        noteRefEndnote: endnote,
        properties: WmlRunProps(
          vertAlign: WmlVertAlign.superscript,
          fontSizeHalfPoints: 16,
        ),
      ),
    );
    return note;
  }

  /// byId API.
  static WmlNote? byId(WmlDocument document, int id, {required bool endnote}) {
    for (final WmlNote note in endnote
        ? document.endnotes
        : document.footnotes) {
      if (note.id == id) {
        return note;
      }
    }
    return null;
  }

  /// delete API.
  static bool delete(WmlDocument document, int id, {required bool endnote}) {
    final List<WmlNote> bucket = endnote
        ? document.endnotes
        : document.footnotes;
    final int index = bucket.indexWhere((WmlNote n) => n.id == id);
    if (index < 0) {
      return false;
    }
    bucket.removeAt(index);
    final String legacy = endnote ? '[E$id]' : '[$id]';
    for (final WmlParagraph paragraph in document.paragraphs) {
      if (paragraph.properties.noteId == id &&
          paragraph.properties.endnoteRef == endnote) {
        paragraph.properties.noteId = null;
        paragraph.properties.endnoteRef = false;
      }
      paragraph.inlines.removeWhere(
        (WmlInline inline) =>
            inline is WmlRun &&
            inline.noteRefId == id &&
            inline.noteRefEndnote == endnote,
      );
      for (final WmlInline inline in paragraph.inlines) {
        if (inline is WmlRun && inline.text.contains(legacy)) {
          inline.text = inline.text.replaceAll(legacy, '');
        }
      }
    }
    return true;
  }

  /// paragraphOf API.
  static WmlParagraph? paragraphOf(WmlDocument document, WmlNote note) {
    for (final WmlParagraph paragraph in document.paragraphs) {
      if (paragraph.properties.noteId == note.id &&
          paragraph.properties.endnoteRef == note.endnote) {
        return paragraph;
      }
      for (final WmlInline inline in paragraph.inlines) {
        if (inline is WmlRun &&
            inline.noteRefId == note.id &&
            inline.noteRefEndnote == note.endnote) {
          return paragraph;
        }
      }
    }
    return null;
  }
}
