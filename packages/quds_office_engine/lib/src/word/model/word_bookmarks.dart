import '../../xml/namespaces.dart';
import '../../xml/xml_node.dart';
import 'wml_clone.dart';
import 'wml_document.dart';
import 'word_toc.dart';
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
  /// Deep-copies complete editable ranges for insertion into [destination].
  ///
  /// Colliding IDs and names are remapped only in the returned copy. Names
  /// allocated here use at most 40 ASCII letters, digits or underscores and
  /// start with a letter or underscore. Noncolliding native identities keep
  /// their source spelling. The whole destination reserves identities,
  /// including independent stories and preserved opaque XML.
  ///
  /// Range order, native attributes and paragraph aliases are retained. REF
  /// instructions and hyperlink targets continue to refer to their original
  /// names; this operation does not retarget references. Partial ranges and
  /// bookmarks inside opaque XML or preserved TOC caches require a separate
  /// editing operation and are rejected before either input is changed.
  ///
  /// Use [WmlClone] directly for history snapshots or identity-preserving
  /// replacement. This method is specifically for duplicate-producing copies.
  static List<WmlBlock> copyForInsertion(
    WmlDocument destination,
    Iterable<WmlBlock> blocks,
  ) {
    final source = blocks.toList();
    if (_opaqueMarkersIn(source).isNotEmpty) {
      throw UnsupportedError(
        'Copying bookmarks inside opaque XML requires an explicit native edit.',
      );
    }
    for (final toc in WordTree.descendants(source).whereType<WmlToc>()) {
      final native = WordToc.nativeParagraphs(toc);
      if (native?.any(
            (paragraph) => paragraph.inlines.any(
              (inline) => inline is WmlBookmarkBoundary,
            ),
          ) ??
          false) {
        throw UnsupportedError(
          'Copying bookmarks inside a preserved TOC cache is not supported.',
        );
      }
    }
    final copies = source.map(WmlClone.block).toList();
    final fragment = WmlDocument(sections: [WmlSection(blocks: copies)]);
    // Pair and validate the entire fragment before allocating any identities.
    // This also rejects duplicate IDs across textbox stories in the same part.
    final native = ranges(fragment);
    final generated = generatedIds(fragment);
    if (native.isEmpty && generated.isEmpty) return copies;

    final destinationGenerated = generatedIds(destination);
    final destinationNative = ranges(destination);
    final destinationOpaque = _opaqueMarkers(destination).toList();
    final usedIds = <String>{
      ...destinationNative.map((range) => canonicalId(range.start.id)),
      ...destinationOpaque.map((marker) => canonicalId(marker.id)),
      ...destinationGenerated.values,
    };
    final usedNames = <String>{
      ...destinationNative.map((range) => range.name.toLowerCase()),
      for (final marker in destinationOpaque)
        if (marker.isStart) marker.name!.toLowerCase(),
      ...destinationGenerated.keys.map((name) => name.toLowerCase()),
    };
    // Reserve later incoming identities before changing earlier collisions.
    // A copied Alpha must not steal a distinct incoming Alpha_copy bookmark.
    final reservedIds = <String>{
      ...usedIds,
      ...native.map((range) => canonicalId(range.start.id)),
    };
    final reservedNames = <String>{
      ...usedNames,
      ...native.map((range) => range.name.toLowerCase()),
      ...generated.keys.map((name) => name.toLowerCase()),
    };
    var nextId = 1;
    String allocateId(String original) {
      if (usedIds.add(canonicalId(original))) return original;
      while (reservedIds.contains('$nextId')) {
        nextId++;
      }
      final result = '${nextId++}';
      reservedIds.add(result);
      usedIds.add(result);
      return result;
    }

    String allocateName(String original) {
      if (usedNames.add(original.toLowerCase())) return original;
      var base = original.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
      if (base.isEmpty) base = 'Bookmark';
      if (!RegExp(r'^[A-Za-z_]').hasMatch(base)) base = 'Bookmark_$base';
      for (var number = 1; ; number++) {
        final suffix = number == 1 ? '_copy' : '_copy$number';
        final length = base.length.clamp(0, 40 - suffix.length);
        final name = '${base.substring(0, length)}$suffix';
        if (reservedNames.add(name.toLowerCase())) {
          usedNames.add(name.toLowerCase());
          return name;
        }
      }
    }

    final byStart = Map<WmlBookmarkBoundary, WmlBookmarkRange>.identity();
    for (final range in native) {
      byStart[range.start] = range;
    }
    final replacements =
        Map<WmlBookmarkBoundary, WmlBookmarkBoundary>.identity();
    final names = <String, String>{};
    final paragraphs = _stories(fragment).expand((story) => story).toList();
    // Starts determine allocation order, even when ranges overlap and their
    // ends occur in a different order.
    for (final paragraph in paragraphs) {
      for (final start in paragraph.inlines.whereType<WmlBookmarkBoundary>()) {
        if (!start.isStart) continue;
        final range = byStart[start]!;
        final id = allocateId(start.id);
        final name = allocateName(range.name);
        names[range.name] = name;
        replacements[start] = _copiedBoundary(start, id: id, name: name);
        replacements[range.end] = _copiedBoundary(
          range.end,
          // If no collision exists, retain each endpoint's native spelling.
          id: id == start.id ? range.end.id : id,
        );
      }
    }
    for (final paragraph in paragraphs) {
      final generatedName = WordBookmarks.generatedName(paragraph);
      for (var index = 0; index < paragraph.inlines.length; index++) {
        final replacement = replacements[paragraph.inlines[index]];
        if (replacement != null) paragraph.inlines[index] = replacement;
      }
      final properties = paragraph.properties;
      if (generatedName != null) {
        properties.bookmarkName = allocateName(generatedName);
      } else if (names.containsKey(properties.bookmarkName)) {
        properties.bookmarkName = names[properties.bookmarkName];
      }
      if (names.containsKey(properties.sourceBookmarkName)) {
        properties.sourceBookmarkName = names[properties.sourceBookmarkName];
      }
    }
    generatedIds(fragment);
    return copies;
  }

  static WmlBookmarkBoundary _copiedBoundary(
    WmlBookmarkBoundary marker, {
    required String id,
    String? name,
  }) {
    var source = marker.sourceXml;
    if (source != null && (id != marker.id || name != marker.name)) {
      final element = XmlDocument.parse(source).root!;
      element.setAttribute('id', id, namespaceUri: OfficeNamespaces.w);
      if (marker.isStart) {
        element.setAttribute('name', name!, namespaceUri: OfficeNamespaces.w);
      }
      source = XmlDocument(root: element).toXmlString(declaration: false);
    }
    final result = WmlBookmarkBoundary(
      id: id,
      isStart: marker.isStart,
      name: name,
      sourceXml: source,
    );
    validateSource(result);
    return result;
  }

  /// Native ranges are joined by ID, not by a nesting stack: Word permits
  /// overlapping bookmarks whose end order differs from their start order.
  static List<WmlBookmarkRange> ranges(WmlDocument document) {
    final result = <WmlBookmarkRange>[];
    final owners = Map<WmlParagraph, WmlParagraph>.identity();
    for (final story in _stories(document, owners: owners)) {
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
              open[id] = _OpenBookmark(
                inline,
                owners[paragraph] ?? paragraph,
                index,
                offset,
              );
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
                  endParagraph: owners[paragraph] ?? paragraph,
                  startOffset: start.offset,
                  endOffset: offset,
                  text: start.text.toString(),
                  paragraphs: story
                      .sublist(start.index, index + 1)
                      .map((item) => owners[item] ?? item),
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

  static Set<String> nativeNames(WmlDocument document) => {
    ...ranges(document).map((range) => range.name),
    for (final marker in _opaqueMarkers(document))
      if (marker.isStart) marker.name!,
  };

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
    _validatePartIdentities(document);
    final ids = native.map((range) => canonicalId(range.start.id)).toSet();
    final names = native.map((range) => range.name).toSet();
    // Opaque source XML is not editable range text, but still owns its native
    // identities. Reserving them prevents generated headings from silently
    // colliding with preserved custom XML and other unmodeled containers.
    for (final marker in _opaqueMarkers(document)) {
      ids.add(canonicalId(marker.id));
      if (marker.isStart) names.add(marker.name!);
    }
    final result = <String, String>{};
    var next = 1;
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

  static Iterable<WmlBookmarkBoundary> _opaqueMarkers(
    WmlDocument document,
  ) sync* {
    for (final blocks in [
      for (final section in document.sections) section.blocks,
      for (final note in [...document.footnotes, ...document.endnotes])
        note.blocks,
    ]) {
      yield* _opaqueMarkersIn(blocks);
    }
  }

  static Iterable<WmlBookmarkBoundary> _opaqueMarkersIn(
    Iterable<WmlBlock> blocks,
  ) sync* {
    Iterable<WmlBookmarkBoundary> visit(XmlElement element) sync* {
      if (element.namespaceUri == OfficeNamespaces.w &&
          (element.localName == 'bookmarkStart' ||
              element.localName == 'bookmarkEnd')) {
        final marker = WmlBookmarkBoundary(
          id:
              element.getAttribute('id', namespaceUri: OfficeNamespaces.w) ??
              '',
          isStart: element.localName == 'bookmarkStart',
          name: element.getAttribute('name', namespaceUri: OfficeNamespaces.w),
        );
        validateSource(marker);
        yield marker;
      }
      for (final child in element.childElements) {
        yield* visit(child);
      }
    }

    for (final block in WordTree.descendants(
      blocks,
    ).whereType<WmlOpaqueBlock>()) {
      final source = XmlDocument.parse(block.xml).root;
      if (source != null) yield* visit(source);
    }
  }

  /// Notes and textboxes own separate text stories, but their IDs still share
  /// one physical XML part. Independent header/footer parts have their own IDs.
  static void _validatePartIdentities(WmlDocument document) {
    void part(
      Iterable<Iterable<WmlParagraph>> stories,
      Iterable<WmlBookmarkBoundary> opaque,
      String context,
    ) {
      final ids = <String>{};
      final names = <String>{};
      for (final marker in [
        for (final story in stories)
          for (final paragraph in story)
            ...paragraph.inlines.whereType<WmlBookmarkBoundary>(),
        ...opaque,
      ]) {
        validateSource(marker);
        if (marker.isStart &&
            (!ids.add(canonicalId(marker.id)) || !names.add(marker.name!))) {
          throw StateError(
            'Duplicate bookmark id or name (${marker.id}, ${marker.name}) in $context.',
          );
        }
      }
    }

    final body = document.sections.expand((section) => section.blocks).toList();
    part(_blockStories(body), _opaqueMarkersIn(body), 'document part');
    for (final notes in [document.footnotes, document.endnotes]) {
      part(
        notes.expand((note) => _blockStories(note.blocks)),
        notes.expand((note) => _opaqueMarkersIn(note.blocks)),
        'note part',
      );
    }
    part(
      document.comments.map((comment) => comment.paragraphs),
      const <WmlBookmarkBoundary>[],
      'comments part',
    );
    for (final section in document.sections) {
      for (final story in [
        section.header,
        section.footer,
        section.firstHeader,
        section.firstFooter,
        section.evenHeader,
        section.evenFooter,
      ]) {
        part([story], const <WmlBookmarkBoundary>[], 'header/footer part');
      }
    }
  }

  /// Compare decimal IDs by value while retaining their source spelling.
  static String canonicalId(String value) {
    final id = RegExp(r'^[+-]?[0-9]+$').hasMatch(value)
        ? BigInt.tryParse(value)
        : null;
    if (id == null) {
      throw StateError('Bookmark id is not a native decimal number: $value');
    }
    return id.toString();
  }

  /// Imported metadata is immutable: fail before any package write if a
  /// caller constructs an endpoint whose source describes a different range.
  static void validateSource(WmlBookmarkBoundary boundary) {
    canonicalId(boundary.id);
    if (boundary.isStart && (boundary.name == null || boundary.name!.isEmpty)) {
      throw StateError('A bookmark start requires a name.');
    }
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
                boundary.name) ||
        element.childElements.isNotEmpty ||
        element.text.trim().isNotEmpty) {
      throw StateError(
        'Bookmark endpoint metadata does not match its source XML.',
      );
    }
  }

  static Iterable<List<WmlParagraph>> _stories(
    WmlDocument doc, {
    Map<WmlParagraph, WmlParagraph>? owners,
  }) sync* {
    yield* _blockStories(
      doc.sections.expand((section) => section.blocks),
      owners: owners,
    );
    for (final section in doc.sections) {
      yield section.header;
      yield section.footer;
      yield section.firstHeader;
      yield section.firstFooter;
      yield section.evenHeader;
      yield section.evenFooter;
    }
    for (final note in [...doc.footnotes, ...doc.endnotes]) {
      yield* _blockStories(note.blocks, owners: owners);
    }
    for (final comment in doc.comments) {
      yield comment.paragraphs;
    }
  }

  static Iterable<List<WmlParagraph>> _blockStories(
    Iterable<WmlBlock> blocks, {
    Map<WmlParagraph, WmlParagraph>? owners,
  }) sync* {
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
          final native = WordToc.nativeParagraphs(block);
          if (native == null) {
            paragraphs.add(block.titleParagraph);
            paragraphs.addAll(block.itemParagraphs);
          } else {
            for (var index = 0; index < native.length; index++) {
              final source = block.sourcePresentation!.paragraphs[index];
              owners?[native[index]] = source.title
                  ? block.titleParagraph
                  : source.entryIndex == null
                  ? source.paragraph
                  : block.itemParagraphs[source.entryIndex!];
            }
            paragraphs.addAll(native);
          }
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
      yield* _blockStories(frame.blocks, owners: owners);
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
