import '../../xml/namespaces.dart';
import '../../xml/xml_node.dart';
import '../../xml/xml_reader.dart';
import '../../xml/xml_writer.dart';
import '../model/wml_document.dart';
import '../model/word_bookmarks.dart';
import '../model/word_notes.dart';
import '../properties/wml_properties.dart';

/// Exact native endpoints and a validated allocation for generated bookmarks.
abstract final class WordBookmarkIo {
  static bool isMarker(XmlPullReader reader) =>
      reader.namespaceUri == OfficeNamespaces.w &&
      (reader.localName == 'bookmarkStart' ||
          reader.localName == 'bookmarkEnd');

  static WmlBookmarkMarker read(XmlPullReader reader) {
    final XmlElement element = XmlDocument.readElement(reader);
    final String id =
        element.getAttribute('id', namespaceUri: OfficeNamespaces.w) ?? '';
    final String source = XmlDocument(
      root: element,
    ).toXmlString(declaration: false);
    final WmlBookmarkMarker marker = element.localName == 'bookmarkStart'
        ? WmlBookmarkStart(
            id: id,
            name:
                element.getAttribute(
                  'name',
                  namespaceUri: OfficeNamespaces.w,
                ) ??
                '',
            sourceXml: source,
          )
        : WmlBookmarkEnd(id: id, sourceXml: source);
    _source(marker);
    return marker;
  }

  static String _id(WmlBookmarkMarker marker) {
    if (!RegExp(r'^[+-]?[0-9]+$').hasMatch(marker.id)) {
      throw FormatException('Invalid bookmark ID: ${marker.id}');
    }
    return BigInt.parse(marker.id).toString();
  }

  static XmlElement? _source(WmlBookmarkMarker marker) {
    _id(marker);
    if (marker is WmlBookmarkStart && marker.name.isEmpty) {
      throw const FormatException('A bookmark start requires a name');
    }
    if (marker.sourceXml == null) return null;
    final XmlElement? element = XmlDocument.parse(marker.sourceXml!).root;
    if (element == null ||
        element.namespaceUri != OfficeNamespaces.w ||
        element.localName !=
            (marker.isStart ? 'bookmarkStart' : 'bookmarkEnd') ||
        element.getAttribute('id', namespaceUri: OfficeNamespaces.w) !=
            marker.id ||
        (marker is WmlBookmarkStart &&
            element.getAttribute('name', namespaceUri: OfficeNamespaces.w) !=
                marker.name) ||
        element.childElements.isNotEmpty ||
        element.text.trim().isNotEmpty) {
      throw const FormatException(
        'Bookmark source markup disagrees with its endpoint',
      );
    }
    return element;
  }

  static void write(XmlWriter writer, WmlBookmarkMarker marker) {
    final XmlElement? source = _source(marker);
    if (source != null) {
      source.writeTo(writer);
    } else {
      writer.writeEmptyElement(
        marker.isStart ? 'bookmarkStart' : 'bookmarkEnd',
        prefix: 'w',
        attributes: <String, String>{
          'w:id': marker.id,
          if (marker is WmlBookmarkStart) 'w:name': marker.name,
        },
      );
    }
  }

  /// Runs before package mutation. Every story must contain paired, ordered,
  /// uniquely identified endpoints. Crossing bookmark ranges are legal; an
  /// endpoint cannot pair with a marker in another header, note or text box.
  static Map<WmlParagraphProps, WmlBookmarkStart> prepare(
    WmlDocument document,
  ) {
    final Map<WmlParagraphProps, WmlBookmarkStart> generated =
        Map<WmlParagraphProps, WmlBookmarkStart>.identity();
    final List<List<WmlParagraph>> bodyStories = <List<WmlParagraph>>[
      <WmlParagraph>[],
    ];
    for (final WmlSection section in document.sections) {
      _paragraphs(section.blocks, bodyStories.first, bodyStories);
    }
    _part(bodyStories, generated, 'document');
    for (final WmlSection section in document.sections) {
      for (final List<WmlParagraph> story in <List<WmlParagraph>>[
        section.header,
        section.footer,
        section.firstHeader,
        section.firstFooter,
        section.evenHeader,
        section.evenFooter,
      ]) {
        _part(<List<WmlParagraph>>[story], generated, 'header/footer');
      }
    }
    for (final List<WmlNote> notes in <List<WmlNote>>[
      document.footnotes,
      document.endnotes,
    ]) {
      final List<List<WmlParagraph>> stories = <List<WmlParagraph>>[];
      for (final WmlNote note in notes) {
        final List<WmlParagraph> story = <WmlParagraph>[];
        stories.add(story);
        _paragraphs(note.blocks, story, stories);
      }
      _part(stories, generated, 'notes');
    }
    _part(
      <List<WmlParagraph>>[
        for (final WmlComment comment in document.comments) comment.paragraphs,
      ],
      generated,
      'comments',
    );
    return generated;
  }

  static void _paragraphs(
    List<WmlBlock> blocks,
    List<WmlParagraph> story,
    List<List<WmlParagraph>> stories,
  ) {
    for (final WmlBlock block in blocks) {
      if (block is WmlParagraph) {
        story.add(block);
      } else if (block is WmlTable) {
        for (final WmlTableRow row in block.rows) {
          for (final WmlTableCell cell in row.cells) {
            _paragraphs(cell.blocks, story, stories);
          }
        }
      } else if (block is WmlFrame) {
        final List<WmlParagraph> frameStory = <WmlParagraph>[];
        stories.add(frameStory);
        _paragraphs(block.blocks, frameStory, stories);
      } else if (block is WmlToc) {
        story.add(block.titleParagraph);
        story.addAll(block.itemParagraphs);
      } else if (block is WmlOpaqueBlock) {
        final List<WmlInline> markers = <WmlInline>[];
        void collect(XmlElement element) {
          if (element.namespaceUri == OfficeNamespaces.w) {
            final String id =
                element.getAttribute('id', namespaceUri: OfficeNamespaces.w) ??
                '';
            if (element.localName == 'bookmarkStart') {
              markers.add(
                WmlBookmarkStart(
                  id: id,
                  name:
                      element.getAttribute(
                        'name',
                        namespaceUri: OfficeNamespaces.w,
                      ) ??
                      '',
                ),
              );
            } else if (element.localName == 'bookmarkEnd') {
              markers.add(WmlBookmarkEnd(id: id));
            }
          }
          for (final XmlElement child in element.childElements) {
            collect(child);
          }
        }

        final XmlElement? source = XmlDocument.parse(block.xml).root;
        if (source != null) collect(source);
        if (markers.isNotEmpty) {
          // Validation-only view: reserve opaque source identities without
          // changing its XML, exposing fake editable text or moving endpoints.
          story.add(WmlParagraph(inlines: markers));
        }
      }
    }
  }

  static void _part(
    List<List<WmlParagraph>> stories,
    Map<WmlParagraphProps, WmlBookmarkStart> generated,
    String context,
  ) {
    final Set<String> ids = <String>{};
    final Set<String> names = <String>{};
    final List<Set<String>> nativeNames = <Set<String>>[];
    for (final List<WmlParagraph> story in stories) {
      final Set<String> open = <String>{};
      final Set<String> storyNames = <String>{};
      nativeNames.add(storyNames);
      for (final WmlParagraph paragraph in story) {
        for (final WmlBookmarkMarker marker
            in paragraph.inlines.whereType<WmlBookmarkMarker>()) {
          _source(marker);
          final String id = _id(marker);
          if (marker is WmlBookmarkStart) {
            if (!ids.add(id) || !names.add(marker.name)) {
              throw StateError(
                'Cannot save duplicate bookmark ID/name ${marker.id}/${marker.name} ($context)',
              );
            }
            open.add(id);
            storyNames.add(marker.name);
          } else if (!open.remove(id)) {
            throw StateError(
              'Cannot save an unmatched bookmark end ${marker.id} ($context)',
            );
          }
        }
      }
      if (open.isNotEmpty) {
        throw StateError(
          'Cannot save unclosed bookmarks ${open.join(', ')} ($context)',
        );
      }
    }
    var nextId = 1;
    for (int i = 0; i < stories.length; i++) {
      for (final WmlParagraph paragraph in stories[i]) {
        final String? name = paragraph.properties.bookmarkName;
        if (name == null || name.isEmpty || nativeNames[i].contains(name)) {
          continue;
        }
        if (!names.add(name)) {
          throw StateError(
            'Cannot save duplicate generated bookmark name $name ($context)',
          );
        }
        while (ids.contains('$nextId')) {
          nextId++;
        }
        final String id = '${nextId++}';
        ids.add(id);
        generated[paragraph.properties] = WmlBookmarkStart(id: id, name: name);
      }
    }
  }
}
