import 'dart:collection';

import '../properties/wml_properties.dart';
import 'wml_clone.dart';
import 'wml_document.dart';
import 'wml_run_edit.dart';

/// An automatic reference mark at its actual position inside a note story.
/// It occupies no text offset; its native run properties remain immutable.
class WmlNoteBodyMarker extends WmlZeroWidthInline {
  WmlNoteBodyMarker({required this.endnote, this.propertiesXml = ''});

  final bool endnote;
  final String propertiesXml;

  @override
  bool get isStart => true;

  @override
  WmlNoteBodyMarker copy() =>
      WmlNoteBodyMarker(endnote: endnote, propertiesXml: propertiesXml);
}

/// Footnote or endnote body.
class WmlNote {
  /// WmlNote API.
  WmlNote({
    required this.id,
    required this.endnote,
    this.addReferenceSpace = true,
    this.referencePropertiesXml,
    this.preserveBodyMarkers = false,
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

  /// Generated-mark properties and a compatibility view of the first imported
  /// mark. Empty means unformatted; null gives new notes superscript styling.
  /// Explicit imported marks retain their own [WmlNoteBodyMarker.propertiesXml].
  String? referencePropertiesXml;

  /// Imported stories retain explicit [WmlNoteBodyMarker] positions, including
  /// a deliberate absence of marks. New notes use the conventional prefix.
  final bool preserveBodyMarkers;

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

  /// Replaces the complete body. An existing native marker becomes the leading
  /// mark of the replacement; an unmarked imported note remains unmarked.
  /// This intentionally removes the old rich blocks, formatting and ranges.
  /// Direct paragraph/range edits instead retain their actual marker positions.
  set text(String value) {
    WmlNoteBodyMarker? retainedMarker;
    if (preserveBodyMarkers) {
      findMarker:
      for (final WmlParagraph paragraph in allParagraphs) {
        for (final WmlInline inline in paragraph.inlines) {
          if (inline is WmlNoteBodyMarker) {
            retainedMarker = inline.copy();
            break findMarker;
          }
        }
      }
    }
    blocks
      ..clear()
      ..add(
        WmlParagraph(
          inlines: <WmlInline>[
            ?retainedMarker,
            WmlRun(text: value),
          ],
        ),
      );
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

  /// The editable text of [note]: one line per top-level paragraph.
  ///
  /// The space Word places after the automatic note number is not part of
  /// the editable text. Tables, pictures and equations inside the note are
  /// not included, and [editText] never changes them.
  static String editableText(WmlNote note) {
    final List<WmlParagraph> paragraphs = note.paragraphs;
    final bool hideSeparator = _leadingSeparator(note);
    return <String>[
      for (var i = 0; i < paragraphs.length; i++)
        i == 0 && hideSeparator && paragraphs[i].text.startsWith(' ')
            ? paragraphs[i].text.substring(1)
            : paragraphs[i].text,
    ].join('\n');
  }

  /// Applies edited [text] (as returned by [editableText], then changed) to
  /// [note] with the smallest change per paragraph.
  ///
  /// Untouched characters keep their runs, so formatting, links and comment
  /// anchors survive; inserted characters take the formatting of the text
  /// they join. Paragraph properties (such as the FootnoteText style) are
  /// kept, extra lines become paragraphs styled like the last one, and
  /// removed lines delete trailing paragraphs. Non-paragraph blocks are kept.
  static void editText(WmlNote note, String text) {
    final String oldEditable = editableText(note);
    if (oldEditable == text) return;
    final List<String> lines = text.split('\n');
    List<WmlParagraph> paragraphs = note.paragraphs.toList();
    if (lines.length != paragraphs.length && paragraphs.isNotEmpty) {
      if (_editParagraphBoundary(note, oldEditable, text)) return;
      if (paragraphs.any(
        (paragraph) => paragraph.inlines.any(
          (inline) =>
              inline is WmlZeroWidthInline && inline is! WmlNoteBodyMarker,
        ),
      )) {
        throw UnsupportedError(
          'Complex paragraph replacement inside native note ranges requires explicit paragraph editing',
        );
      }
    }
    final bool hideSeparator = _leadingSeparator(note);
    if (paragraphs.isEmpty) {
      note.blocks.insert(0, WmlParagraph(inlines: <WmlInline>[WmlRun()]));
      paragraphs = note.paragraphs.toList();
    }
    final int shared = lines.length < paragraphs.length
        ? lines.length
        : paragraphs.length;
    for (var i = 0; i < shared; i++) {
      _applyLine(paragraphs[i], lines[i], first: i == 0 && hideSeparator);
    }
    if (lines.length > paragraphs.length) {
      final WmlParagraph template = paragraphs.last;
      final WmlRunProps runProps = WmlRunEdit.propsAt(
        template,
        template.text.length - 1,
      ).copy();
      var at = note.blocks.indexOf(template) + 1;
      for (var i = paragraphs.length; i < lines.length; i++) {
        note.blocks.insert(
          at++,
          WmlParagraph(
            properties: template.properties.copy()
              ..bookmarkName = null
              ..listRestart = null,
            inlines: <WmlInline>[
              WmlRun(text: lines[i], properties: runProps.copy()),
            ],
          ),
        );
      }
    } else {
      for (var i = paragraphs.length - 1; i >= lines.length; i--) {
        note.blocks.remove(paragraphs[i]);
      }
    }
  }

  static bool _leadingSeparator(WmlNote note) {
    if (!note.preserveBodyMarkers) return true;
    if (note.paragraphs.isEmpty) return false;
    for (final WmlInline inline in note.paragraphs.first.inlines) {
      if (inline is WmlNoteBodyMarker) return true;
      if (inline is WmlRun && inline.text.isNotEmpty) return false;
    }
    return false;
  }

  /// Enter and backspace move actual inline tokens between adjacent paragraphs
  /// instead of deleting the tail and recreating it as unformatted text.
  static bool _editParagraphBoundary(WmlNote note, String old, String target) {
    final change = _changedRange(old, target);
    final bool inserting =
        change.end == change.start && change.inserted.contains('\n');
    final bool joining =
        old.substring(change.start, change.end) == '\n' &&
        change.inserted.isEmpty;
    final List<WmlParagraph> paragraphs = note.paragraphs.toList();
    final List<String> display = <String>[
      for (var i = 0; i < paragraphs.length; i++)
        i == 0 && _leadingSeparator(note) && paragraphs[i].text.startsWith(' ')
            ? paragraphs[i].text.substring(1)
            : paragraphs[i].text,
    ];
    var paragraphIndex = 0;
    var offset = change.start;
    while (paragraphIndex < display.length - 1 &&
        offset > display[paragraphIndex].length) {
      offset -= display[paragraphIndex].length + 1;
      paragraphIndex++;
    }
    if (paragraphIndex >= paragraphs.length) return false;
    final WmlParagraph paragraph = paragraphs[paragraphIndex];
    final int removed = change.end - change.start;
    final bool withinParagraph =
        offset + removed <= display[paragraphIndex].length;
    if (paragraphIndex == 0 &&
        _leadingSeparator(note) &&
        paragraph.text.startsWith(' ')) {
      offset++;
    }
    if (!inserting &&
        withinParagraph &&
        paragraph.text.contains('\n') &&
        !change.inserted.contains('\n')) {
      WmlRunEdit.replaceRange(
        paragraph,
        offset,
        offset + removed,
        change.inserted,
      );
      return true;
    }
    if (!inserting && !joining) return false;
    if (joining) {
      if (paragraphIndex + 1 >= paragraphs.length ||
          offset != paragraph.text.length) {
        return false;
      }
      final WmlParagraph next = paragraphs[paragraphIndex + 1];
      if (note.blocks.indexOf(next) != note.blocks.indexOf(paragraph) + 1) {
        throw UnsupportedError(
          'Cannot join note paragraphs across preserved blocks',
        );
      }
      paragraph.inlines.addAll(WmlClone.inlines(next.inlines));
      WmlRunEdit.coalesce(paragraph);
      note.blocks.remove(next);
      return true;
    }
    final WmlParagraph head = WmlClone.paragraph(paragraph);
    final WmlRunProps properties = WmlRunEdit.propsAt(paragraph, offset).copy();
    final List<WmlInline> tail = WmlRunEdit.splitParagraphInlines(head, offset);
    final List<String> inserted = change.inserted.split('\n');
    WmlRunEdit.replaceRange(head, offset, offset, inserted.first);
    final List<WmlParagraph> additions = <WmlParagraph>[];
    for (var i = 1; i < inserted.length; i++) {
      final WmlParagraph added = WmlParagraph(
        properties: paragraph.properties.copy()
          ..bookmarkName = null
          ..listRestart = null,
        inlines: i == inserted.length - 1 && tail.isNotEmpty
            ? tail
            : <WmlInline>[WmlRun(properties: properties.copy())],
      );
      WmlRunEdit.replaceRange(added, 0, 0, inserted[i]);
      additions.add(added);
    }
    paragraph.inlines
      ..clear()
      ..addAll(head.inlines);
    note.blocks.insertAll(note.blocks.indexOf(paragraph) + 1, additions);
    return true;
  }

  static ({int start, int end, String inserted}) _changedRange(
    String old,
    String target,
  ) {
    var start = 0;
    while (start < old.length &&
        start < target.length &&
        old.codeUnitAt(start) == target.codeUnitAt(start)) {
      start++;
    }
    if (start > 0 &&
        start < old.length &&
        old.codeUnitAt(start) >= 0xDC00 &&
        old.codeUnitAt(start) <= 0xDFFF) {
      start--;
    }
    var suffix = 0;
    while (suffix < old.length - start &&
        suffix < target.length - start &&
        old.codeUnitAt(old.length - 1 - suffix) ==
            target.codeUnitAt(target.length - 1 - suffix)) {
      suffix++;
    }
    final int boundary = old.length - suffix;
    if (suffix > 0 &&
        boundary < old.length &&
        old.codeUnitAt(boundary) >= 0xDC00 &&
        old.codeUnitAt(boundary) <= 0xDFFF) {
      suffix--;
    }
    return (
      start: start,
      end: old.length - suffix,
      inserted: target.substring(start, target.length - suffix),
    );
  }

  static void _applyLine(
    WmlParagraph paragraph,
    String line, {
    required bool first,
  }) {
    final String old = paragraph.text;
    final String target = first && old.startsWith(' ') && !line.startsWith(' ')
        ? ' $line'
        : line;
    if (old == target) {
      return;
    }
    final change = _changedRange(old, target);
    WmlRunEdit.replaceRange(
      paragraph,
      change.start,
      change.end,
      change.inserted,
    );
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
