import 'dart:collection';

import '../properties/wml_properties.dart';
import 'wml_clone.dart';
import 'wml_document.dart';

/// Footnote or endnote body.
class WmlNote {
  /// WmlNote API.
  WmlNote({
    required this.id,
    required this.endnote,
    this.addReferenceSpace = true,
    this.referencePropertiesXml,
    List<WmlParagraph>? paragraphs,
    List<WmlBlock>? blocks,
  }) : blocks =
           blocks ??
           <WmlBlock>[
             ...paragraphs ??
                 <WmlParagraph>[
                   WmlParagraph(inlines: <WmlInline>[WmlRun(text: '')]),
                 ],
           ];

  /// id API.
  int id;

  /// True for an endnote, false for a footnote.
  final bool endnote;

  /// New note bodies get one separator after the automatic reference mark.
  /// Imported stories keep their exact source whitespace instead.
  final bool addReferenceSpace;

  /// Original automatic note-mark properties. Empty means an unformatted
  /// imported mark; null gives new notes the standard superscript style.
  String? referencePropertiesXml;

  /// Ordered note story, including paragraphs, tables, pictures and equations.
  final List<WmlBlock> blocks;

  /// Mutable top-level paragraph view retained for existing note editors.
  List<WmlParagraph> get paragraphs => _NoteParagraphs(blocks);
  set paragraphs(List<WmlParagraph> value) {
    final List<WmlParagraph> copied = List<WmlParagraph>.of(value);
    blocks
      ..clear()
      ..addAll(copied);
  }

  Iterable<WmlParagraph> get allParagraphs =>
      blocks.expand(WmlClone.paragraphsOf);

  Iterable<WmlVisual> get visuals =>
      WmlDocument(sections: <WmlSection>[WmlSection(blocks: blocks)]).visuals;

  /// text API.
  String get text => WmlClone.plainTextOf(blocks).trim();

  /// text API.
  set text(String value) {
    blocks
      ..clear()
      ..add(WmlParagraph(inlines: <WmlInline>[WmlRun(text: value)]));
  }
}

class _NoteParagraphs extends ListBase<WmlParagraph> {
  _NoteParagraphs(this.blocks);
  final List<WmlBlock> blocks;
  List<int> get _indices => <int>[
    for (var i = 0; i < blocks.length; i++)
      if (blocks[i] is WmlParagraph) i,
  ];
  @override
  int get length => _indices.length;
  @override
  set length(int value) {
    RangeError.checkNotNegative(value);
    while (length > value) {
      removeAt(length - 1);
    }
    while (length < value) {
      blocks.add(WmlParagraph());
    }
  }

  @override
  WmlParagraph operator [](int index) =>
      blocks[_indices[index]] as WmlParagraph;
  @override
  void operator []=(int index, WmlParagraph value) {
    blocks[_indices[index]] = value;
  }

  @override
  void add(WmlParagraph value) {
    blocks.add(value);
  }

  @override
  void insert(int index, WmlParagraph value) {
    RangeError.checkValidRange(index, index, length);
    blocks.insert(index == length ? blocks.length : _indices[index], value);
  }

  @override
  WmlParagraph removeAt(int index) =>
      blocks.removeAt(_indices[index]) as WmlParagraph;
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
    for (final WmlNote note
        in endnote ? document.endnotes : document.footnotes) {
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
