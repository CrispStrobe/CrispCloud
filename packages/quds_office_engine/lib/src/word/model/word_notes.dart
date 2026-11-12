import 'dart:collection';

import '../../opc/package_part.dart';
import '../../opc/relationships.dart';
import '../../xml/namespaces.dart';
import '../../xml/xml_node.dart';
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
    // Special native definitions remain in the owning package part rather than
    // the editable bucket. Their positive IDs share the same namespace as
    // normal notes, so reserve them before changing either the model or anchor.
    final reservedIds = _retainedDefinitionIds(document, endnote: endnote);
    while (reservedIds.contains(id)) {
      id++;
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

  static Set<int> _retainedDefinitionIds(
    WmlDocument document, {
    required bool endnote,
  }) {
    final package = document.package;
    if (package == null) return const <int>{};
    final office = package.packageRelationships.firstByType(
      RelationshipTypes.officeDocument,
    );
    if (office?.targetMode == RelationshipTargetMode.external) {
      throw const FormatException(
        'The Word main part must be inside its package',
      );
    }
    final mainUri = office == null
        ? '/word/document.xml'
        : package.packageRelationships.resolve(office);
    final kind = endnote ? 'endnote' : 'footnote';
    final relationships = package.relationshipsFor(mainUri);
    final relationship = relationships.firstByType(
      endnote ? RelationshipTypes.endnotes : RelationshipTypes.footnotes,
    );
    if (relationship?.targetMode == RelationshipTargetMode.external) {
      throw FormatException(
        'The Word ${kind}s part must be inside its package',
      );
    }
    // Match the serializer's legacy fallback when a native part has no owner.
    final uri = relationship == null
        ? OpcUris.resolve(mainUri, '${kind}s.xml')
        : relationships.resolve(relationship);
    final part = package.getPart(uri);
    if (part == null) return const <int>{};
    final root = XmlDocument.parse(part.readText()).root;
    final reserved = <int>{};
    if (root == null) return reserved;
    for (final definition in root.childrenNamed(
      kind,
      namespaceUri: OfficeNamespaces.w,
    )) {
      if (!const {
        'separator',
        'continuationSeparator',
        'continuationNotice',
      }.contains(
        definition.getAttribute('type', namespaceUri: OfficeNamespaces.w),
      )) {
        continue;
      }
      final id = int.tryParse(
        definition.getAttribute('id', namespaceUri: OfficeNamespaces.w) ?? '',
      );
      if (id != null) reserved.add(id);
    }
    return reserved;
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
    final List<String> lines = text.split('\n');
    List<WmlParagraph> paragraphs = editableParagraphs(note);
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
              ..sourceBookmarkName = null,
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
    var start = 0;
    while (start < old.length &&
        start < target.length &&
        old.codeUnitAt(start) == target.codeUnitAt(start)) {
      start++;
    }
    var end = 0;
    while (end < old.length - start &&
        end < target.length - start &&
        old.codeUnitAt(old.length - 1 - end) ==
            target.codeUnitAt(target.length - 1 - end)) {
      end++;
    }
    WmlRunEdit.replaceRange(
      paragraph,
      start,
      old.length - end,
      target.substring(start, target.length - end),
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
