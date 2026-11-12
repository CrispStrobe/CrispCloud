import '../../xml/namespaces.dart';
import '../../xml/xml_node.dart';
import 'wml_document.dart';
import 'word_tree.dart';

/// A paired bookmark with the exact text selected by its native endpoints.
final class WmlBookmarkRange {
  WmlBookmarkRange({
    required this.start,
    required this.end,
    required this.startParagraph,
    required this.endParagraph,
    required this.startOffset,
    required this.endOffset,
    required this.text,
    required Iterable<WmlParagraph> paragraphs,
  }) : paragraphs = List<WmlParagraph>.unmodifiable(paragraphs);

  final WmlBookmarkBoundary start;
  final WmlBookmarkBoundary end;
  final WmlParagraph startParagraph;
  final WmlParagraph endParagraph;
  final int startOffset;
  final int endOffset;
  final String text;
  final List<WmlParagraph> paragraphs;
  String get name => start.name!;
}

/// Bookmark pairing, source preservation and generated-name/ID ownership.
abstract final class WordBookmarks {
  /// Native ranges are joined by ID, not by a nesting stack: Word permits
  /// overlapping bookmarks whose end order differs from their start order.
  static List<WmlBookmarkRange> ranges(WmlDocument document) {
    final result = <WmlBookmarkRange>[];
    for (final story in _stories(document)) {
      final open = <String, _OpenBookmark>{};
      final ids = <String>{};
      final names = <String>{};
      for (var index = 0; index < story.length; index++) {
        final paragraph = story[index];
        if (index > 0) {
          for (final bookmark in open.values) {
            bookmark.text.write('\n');
          }
        }
        var offset = 0;
        for (final inline in paragraph.inlines) {
          if (inline is WmlBookmarkBoundary) {
            validateSource(inline);
            final id = canonicalId(inline.id);
            if (inline.isStart) {
              final name = inline.name;
              if (name == null || name.isEmpty) {
                throw StateError('Bookmark $id has no name.');
              }
              if (!ids.add(id) || !names.add(name)) {
                throw StateError(
                  'Duplicate bookmark id or name ($id, $name). Copying native '
                  'ranges into the same story requires remapping their endpoints.',
                );
              }
              open[id] = _OpenBookmark(inline, paragraph, index, offset);
            } else {
              final start = open.remove(id);
              if (start == null) {
                throw StateError(
                  'Bookmark end $id has no matching start in its story.',
                );
              }
              result.add(
                WmlBookmarkRange(
                  start: start.marker,
                  end: inline,
                  startParagraph: start.paragraph,
                  endParagraph: paragraph,
                  startOffset: start.offset,
                  endOffset: offset,
                  text: start.text.toString(),
                  paragraphs: story.sublist(start.index, index + 1),
                ),
              );
            }
          } else if (inline is WmlRun) {
            for (final bookmark in open.values) {
              bookmark.text.write(inline.text);
            }
            offset += inline.text.length;
          }
        }
      }
      if (open.isNotEmpty) {
        throw StateError(
          'Bookmark start ${open.keys.join(', ')} has no matching end in its story.',
        );
      }
    }
    return result;
  }

  static WmlBookmarkRange? byName(WmlDocument document, String name) =>
      ranges(document).where((range) => range.name == name).firstOrNull;

  static Set<String> nativeNames(WmlDocument document) =>
      ranges(document).map((range) => range.name).toSet();

  static WmlParagraph? paragraphByName(WmlDocument document, String name) {
    final native = byName(document, name);
    if (native != null) return native.startParagraph;
    return _stories(document)
        .expand((story) => story)
        .where((paragraph) => generatedName(paragraph) == name)
        .firstOrNull;
  }

  static String? textByName(WmlDocument document, String name) {
    final native = byName(document, name);
    if (native != null) return native.text;
    return _stories(document)
        .expand((story) => story)
        .where((paragraph) => generatedName(paragraph) == name)
        .firstOrNull
        ?.text;
  }

  /// Paragraph-scoped bookmarks created through the existing editing API.
  static String? generatedName(WmlParagraph paragraph) {
    final name = paragraph.properties.bookmarkName;
    if (name == null ||
        name.isEmpty ||
        name == paragraph.properties.sourceBookmarkName) {
      return null;
    }
    // A compatibility alias can also be supplied by callers that construct a
    // paragraph from native inlines. The exact endpoint owns that bookmark;
    // emitting a paragraph-wide pair would duplicate and expand its range.
    if (paragraph.inlines.whereType<WmlBookmarkBoundary>().any(
      (boundary) => boundary.isStart && boundary.name == name,
    )) {
      return null;
    }
    return name;
  }

  /// Validate all ranges before package mutation and allocate deterministic
  /// free IDs for generated bookmarks. Imported IDs are never rewritten.
  static Map<String, String> generatedIds(WmlDocument document) {
    final native = ranges(document);
    final ids = native.map((range) => canonicalId(range.start.id)).toSet();
    final names = native.map((range) => range.name).toSet();
    final result = <String, String>{};
    var next = 0;
    for (final paragraph in _stories(document).expand((story) => story)) {
      final name = generatedName(paragraph);
      if (name == null) continue;
      if (!names.add(name)) {
        throw StateError('Generated bookmark name already exists: $name');
      }
      while (ids.contains('$next')) {
        next++;
      }
      final id = '${next++}';
      ids.add(id);
      result[name] = id;
    }
    return result;
  }

  /// Compare decimal IDs by value while retaining their source spelling.
  static String canonicalId(String value) {
    final id = BigInt.tryParse(value);
    if (id == null) {
      throw StateError('Bookmark id is not a native decimal number: $value');
    }
    return id.toString();
  }

  /// Imported metadata is immutable: fail before any package write if a
  /// caller constructs an endpoint whose source describes a different range.
  static void validateSource(WmlBookmarkBoundary boundary) {
    if (boundary.sourceXml == null) return;
    final element = XmlDocument.parse(boundary.sourceXml!).root;
    final kind = boundary.isStart ? 'bookmarkStart' : 'bookmarkEnd';
    if (element == null ||
        element.localName != kind ||
        element.namespaceUri != OfficeNamespaces.w ||
        element.getAttribute('id', namespaceUri: OfficeNamespaces.w) !=
            boundary.id ||
        (boundary.isStart &&
            element.getAttribute('name', namespaceUri: OfficeNamespaces.w) !=
                boundary.name)) {
      throw StateError(
        'Bookmark endpoint metadata does not match its source XML.',
      );
    }
  }

  static Iterable<List<WmlParagraph>> _stories(WmlDocument doc) sync* {
    yield* _blockStories(doc.sections.expand((section) => section.blocks));
    for (final section in doc.sections) {
      yield section.header;
      yield section.footer;
      yield section.firstHeader;
      yield section.firstFooter;
      yield section.evenHeader;
      yield section.evenFooter;
    }
    for (final note in [...doc.footnotes, ...doc.endnotes]) {
      yield* _blockStories(note.blocks);
    }
    for (final comment in doc.comments) {
      yield comment.paragraphs;
    }
  }

  static Iterable<List<WmlParagraph>> _blockStories(
    Iterable<WmlBlock> blocks,
  ) sync* {
    final paragraphs = <WmlParagraph>[];
    final frames = <WmlFrame>[];
    void visit(Iterable<WmlBlock> items) {
      for (final block in items) {
        if (block is WmlFrame) {
          // A frame block writes one native anchor paragraph in this story.
          // Its paragraph break participates in a surrounding REF range; the
          // textbox's own text and endpoints belong to a separate story.
          paragraphs.add(WmlParagraph());
          frames.add(block);
        } else if (block is WmlParagraph) {
          paragraphs.add(block);
        } else if (block is WmlToc) {
          paragraphs.add(block.titleParagraph);
          paragraphs.addAll(block.itemParagraphs);
        } else {
          for (final children in WordTree.childLists(block)) {
            visit(children);
          }
        }
      }
    }

    visit(blocks);
    yield paragraphs;
    for (final frame in frames) {
      yield* _blockStories(frame.blocks);
    }
  }
}

final class _OpenBookmark {
  _OpenBookmark(this.marker, this.paragraph, this.index, this.offset);
  final WmlBookmarkBoundary marker;
  final WmlParagraph paragraph;
  final int index;
  final int offset;
  final StringBuffer text = StringBuffer();
}
