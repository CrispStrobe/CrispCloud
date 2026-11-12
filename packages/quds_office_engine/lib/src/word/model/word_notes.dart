import 'dart:collection';

import '../properties/wml_properties.dart';
import 'wml_clone.dart';
import 'wml_document.dart';
import 'wml_run_edit.dart';
import 'word_bookmarks.dart';
import 'word_content_controls.dart';
import 'word_tree.dart';

/// Footnote or endnote body.
class WmlNote {
  /// WmlNote API.
  WmlNote({
    required this.id,
    required this.endnote,
    this.addReference = true,
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

  /// Newly authored notes get a conventional leading marker when their story
  /// has no [WmlNoteMarker]. Imported notes preserve marker absence and order.
  final bool addReference;

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

  bool get hasReferenceMarkers => allParagraphs.any(
    (paragraph) => paragraph.inlines.any((inline) => inline is WmlNoteMarker),
  );

  Iterable<WmlVisual> get visuals =>
      WmlDocument(sections: <WmlSection>[WmlSection(blocks: blocks)]).visuals;

  /// text API.
  String get text => WmlClone.plainTextOf(blocks).trim();

  /// text API.
  set text(String value) {
    // This legacy setter deliberately replaces the rich story, but its
    // automatic note number is not ordinary body text. Retain one existing
    // marker (and its own formatting); imported absence remains absence.
    final marker = allParagraphs
        .expand((paragraph) => paragraph.inlines.whereType<WmlNoteMarker>())
        .firstOrNull;
    blocks
      ..clear()
      ..add(
        WmlParagraph(
          inlines: <WmlInline>[
            if (marker != null)
              WmlNoteMarker(
                endnote: marker.endnote,
                properties: marker.properties.copy(),
              ),
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

  /// Editable note-pane paragraphs in their original live containers.
  ///
  /// Native block content controls are transparent. Table and frame content
  /// remains outside this simple text pane, as it was before controls were
  /// represented in the model.
  static List<WmlParagraph> editableParagraphs(WmlNote note) =>
      WordTree.visibleBlocks(note.blocks).whereType<WmlParagraph>().toList();

  /// The editable text of [note]: one line per paragraph in its main flow.
  ///
  /// The space Word places after the automatic note number is not part of
  /// the editable text. Tables, pictures and equations inside the note are
  /// not included, and [editText] never changes them.
  static String editableText(WmlNote note) {
    final List<WmlParagraph> paragraphs = editableParagraphs(note);
    return <String>[
      for (var i = 0; i < paragraphs.length; i++)
        i == 0 &&
                _hasLeadingReference(note, paragraphs[i]) &&
                paragraphs[i].text.startsWith(' ')
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
  /// removed lines delete trailing paragraphs. New paragraphs do not inherit
  /// bookmark identity. Non-paragraph blocks are kept; removal that would
  /// orphan one bookmark endpoint is rejected before any live edit.
  static void editText(WmlNote note, String text) {
    final oldEditable = editableText(note);
    if (oldEditable == text) return;
    final List<String> lines = text.split('\n');
    List<WmlParagraph> paragraphs = editableParagraphs(note);
    if (lines.length != paragraphs.length && paragraphs.isNotEmpty) {
      if (_editParagraphBoundary(note, oldEditable, text)) return;
      if (paragraphs.length == 1 &&
          paragraphs.single.inlines.any(
            (inline) => inline is WmlBookmarkBoundary,
          )) {
        throw UnsupportedError(
          'Complex paragraph replacement inside native note ranges requires explicit paragraph editing',
        );
      }
    }
    if (lines.length != paragraphs.length &&
        paragraphs.any(WordContentControls.hasInlineControls)) {
      throw UnsupportedError(
        'Changing note line count with inline content controls is not supported. '
        'Edit each existing control paragraph separately.',
      );
    }
    if (lines.length < paragraphs.length) {
      final removed = Set<WmlParagraph>.identity()
        ..addAll(paragraphs.skip(lines.length));
      final story = WmlDocument(
        sections: <WmlSection>[],
        footnotes: note.endnote ? null : <WmlNote>[note],
        endnotes: note.endnote ? <WmlNote>[note] : null,
      );
      for (final range in WordBookmarks.ranges(story)) {
        if (removed.contains(range.startParagraph) !=
            removed.contains(range.endParagraph)) {
          throw UnsupportedError(
            'Removing note paragraphs would orphan bookmark "${range.name}". '
            'Keep both endpoint paragraphs or remove the complete range.',
          );
        }
      }
    }
    final int shared = lines.length < paragraphs.length
        ? lines.length
        : paragraphs.length;
    // A later guarded range must not leave earlier paragraphs partially
    // updated. Preflight the exact edit on copies before touching live owners.
    for (var i = 0; i < shared; i++) {
      _applyLine(
        WmlClone.paragraph(paragraphs[i]),
        lines[i],
        preserveReferenceSpace:
            i == 0 && _hasLeadingReference(note, paragraphs[i]),
      );
    }
    if (paragraphs.isEmpty) {
      final parent = _emptyEditableHost(note.blocks);
      final paragraph = WmlParagraph(inlines: <WmlInline>[WmlRun()]);
      parent.insert(0, paragraph);
      paragraphs = <WmlParagraph>[paragraph];
      _applyLine(paragraph, lines.first, preserveReferenceSpace: false);
    }
    for (var i = 0; i < shared; i++) {
      _applyLine(
        paragraphs[i],
        lines[i],
        preserveReferenceSpace:
            i == 0 && _hasLeadingReference(note, paragraphs[i]),
      );
    }
    if (lines.length > paragraphs.length) {
      final WmlParagraph template = paragraphs.last;
      final WmlRunProps runProps = WmlRunEdit.propsAt(
        template,
        template.text.length - 1,
      ).copy();
      final location = WordTree.locateIn(note.blocks, template)!;
      var at = location.index + 1;
      for (var i = paragraphs.length; i < lines.length; i++) {
        location.parent.insert(
          at++,
          WmlParagraph(
            properties: template.properties.copy()
              ..bookmarkName = null
              ..sourceBookmarkName = null
              ..listRestart = null,
            inlines: <WmlInline>[
              WmlRun(text: lines[i], properties: runProps.copy()),
            ],
          ),
        );
      }
    } else {
      for (var i = paragraphs.length - 1; i >= lines.length; i--) {
        final location = WordTree.locateIn(note.blocks, paragraphs[i])!;
        location.parent.removeAt(location.index);
      }
    }
  }

  static List<WmlBlock> _emptyEditableHost(List<WmlBlock> blocks) {
    for (final block in blocks) {
      if (block is WmlContentControlBlock) {
        return _emptyEditableHost(block.blocks);
      }
    }
    return blocks;
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
    final List<WmlParagraph> paragraphs = editableParagraphs(note);
    final List<String> display = <String>[
      for (var i = 0; i < paragraphs.length; i++)
        i == 0 &&
                _hasLeadingReference(note, paragraphs.first) &&
                paragraphs[i].text.startsWith(' ')
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
        _hasLeadingReference(note, paragraphs.first) &&
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
      final location = WordTree.locateIn(note.blocks, paragraph)!;
      final nextLocation = WordTree.locateIn(note.blocks, next)!;
      if (!identical(location.parent, nextLocation.parent) ||
          nextLocation.index != location.index + 1 ||
          WordContentControls.hasStructuralControls(paragraph) ||
          WordContentControls.hasStructuralControls(next)) {
        throw UnsupportedError(
          'Cannot join note paragraphs across preserved blocks',
        );
      }
      paragraph.inlines.addAll(WmlClone.inlines(next.inlines));
      WmlRunEdit.coalesce(paragraph);
      location.parent.removeAt(nextLocation.index);
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
          ..sourceBookmarkName = null
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
    final location = WordTree.locateIn(note.blocks, paragraph)!;
    location.parent.insertAll(location.index + 1, additions);
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
    required bool preserveReferenceSpace,
  }) {
    final String old = paragraph.text;
    final String target = preserveReferenceSpace && old.startsWith(' ')
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

  static bool _hasLeadingReference(WmlNote note, WmlParagraph paragraph) {
    if (note.addReference &&
        !note.hasReferenceMarkers &&
        note.blocks.isNotEmpty &&
        identical(note.blocks.first, paragraph)) {
      return true;
    }
    for (final inline in paragraph.inlines) {
      if (inline is WmlNoteMarker) return true;
      if (inline is WmlContentControlBoundary ||
          inline is WmlBookmarkBoundary) {
        continue;
      }
      if (inline is WmlRun && inline.text.isEmpty) continue;
      return false;
    }
    return false;
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
