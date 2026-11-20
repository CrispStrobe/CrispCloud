import 'dart:convert';

import '../../xml/xml_reader.dart';
import '../../zotero/zotero_formatted_text.dart';
import '../properties/wml_properties.dart';
import 'wml_document.dart';
import 'word_zotero_note_image.dart';

/// A bounded, inert note fragment with citation placeholders kept separate.
/// Unsupported structure and formatting are refused before document edits.
final class WordZoteroNoteText {
  WordZoteroNoteText._(this.paragraphs, this.placeholders, this.listItems);

  final List<WmlParagraph> paragraphs;
  final Map<String, WordZoteroNotePlaceholder> placeholders;

  /// Native list metadata keyed by each item or continuation paragraph index.
  final Map<int, WordZoteroNoteListItem> listItems;
  String get plainText => paragraphs.map((p) => p.text).join('\n');

  factory WordZoteroNoteText.fromHtml(
    String html, {
    WmlRunProps? baseProperties,
  }) {
    if (html.length > 8 * 1024 * 1024 ||
        utf8.encode(html).length > 8 * 1024 * 1024) {
      throw const FormatException('The Zotero note is too large.');
    }
    if (html.contains('<![CDATA[')) {
      throw UnsupportedError('CDATA in Zotero note content is not supported.');
    }
    final reader = XmlPullReader('<quds-note>${_normalize(html)}</quds-note>');
    final canonical = StringBuffer();
    final stack = <_NoteElement>[];
    final links = <_NoteLink>[];
    final images = <WmlVisual>[];
    final imageReader = WordZoteroNoteImageReader();
    final items = <WordZoteroNoteListItem>[];
    var listCount = 0;
    var activeLink = false;
    var elements = 0;
    const escape = HtmlEscape(HtmlEscapeMode.element);
    const attributeEscape = HtmlEscape(HtmlEscapeMode.attribute);

    void writeListParagraph(_NoteItem item) {
      final index = items.length;
      items.add(
        WordZoteroNoteListItem(
          listId: item.list.id,
          numbered: item.list.numbered,
          start: item.list.start,
          index: item.index,
          level: item.list.level,
          continuation: item.paragraphs++ != 0,
        ),
      );
      canonical.write('\uE002\uE000l$index\uE001');
    }

    void openItemParagraph(_NoteItem item) {
      if (item.implicitParagraphOpen) return;
      canonical.write('<p>');
      writeListParagraph(item);
      item.implicitParagraphOpen = true;
    }

    void closeItemParagraph(_NoteItem item) {
      if (!item.implicitParagraphOpen) return;
      canonical.write('\uE002</p>');
      item.implicitParagraphOpen = false;
    }

    try {
      while (reader.next()) {
        switch (reader.eventType) {
          case XmlEventType.startElement:
            if (++elements > 50000 || stack.length > 64) {
              throw const FormatException('The Zotero note is too complex.');
            }
            final tag = reader.qualifiedName.toLowerCase();
            if (!_tags.contains(tag)) {
              throw UnsupportedError(
                'This Zotero note contains unsupported $tag content. The document was kept unchanged.',
              );
            }
            final attributes = <String, String>{};
            if (reader.attributeCount > 64) throw _malformed();
            for (var i = 0; i < reader.attributeCount; i++) {
              final name = reader.attributeQualifiedName(i).toLowerCase();
              if (attributes.containsKey(name)) throw _malformed();
              final value = reader.attributeValue(i);
              _checkMarkers(value);
              if (name != 'style' &&
                  name != 'class' &&
                  !(name == 'href' && tag == 'a') &&
                  !(name == 'start' && tag == 'ol') &&
                  !(tag == 'img' &&
                      const <String>{
                        'src',
                        'width',
                        'height',
                        'alt',
                        'title',
                      }.contains(name)) &&
                  !(const <String>{
                        'data-schema-version',
                        'data-citation-items',
                      }.contains(name) &&
                      tag == 'div') &&
                  !(name == 'data-annotation' &&
                      (tag == 'span' || tag == 'img'))) {
                throw UnsupportedError(
                  'This Zotero note contains unsupported $name attributes. The document was kept unchanged.',
                );
              }
              if (name == 'class' &&
                  value
                      .split(RegExp(r'\s+'))
                      .any((name) => name.startsWith('csl-'))) {
                throw UnsupportedError(
                  'This Zotero note uses unsupported class-based formatting.',
                );
              }
              attributes[name] = value;
            }
            final parent = stack.lastOrNull;
            if (tag == 'img' &&
                activeLink &&
                links.last.placeholderId != null) {
              throw UnsupportedError(
                'A Zotero citation placeholder cannot contain an image. The document was kept unchanged.',
              );
            }
            final activeItem = stack
                .where((element) => element.item != null)
                .lastOrNull
                ?.item;
            final isList = tag == 'ul' || tag == 'ol';
            if (isList &&
                (activeLink ||
                    (activeItem != null
                        ? !identical(parent?.item, activeItem)
                        : !const <String>{
                            'quds-note',
                            'html',
                            'body',
                            'div',
                          }.contains(parent?.tag)))) {
              throw _unsupportedList();
            }
            if (parent?.list != null && tag != 'li') {
              throw _unsupportedList();
            }
            if (activeItem != null &&
                (tag == 'p' || tag == 'div' || _headings.contains(tag))) {
              if (tag != 'p' ||
                  !identical(parent?.item, activeItem) ||
                  activeLink) {
                throw _unsupportedList();
              }
            }
            _NoteList? list;
            if (isList) {
              final level = activeItem == null ? 0 : activeItem.list.level + 1;
              if (level > 8) throw _unsupportedList();
              final start = attributes['start'];
              if (start != null &&
                  (!RegExp(r'^[1-9][0-9]{0,5}$').hasMatch(start))) {
                throw _unsupportedList();
              }
              list = _NoteList(
                id: listCount++,
                numbered: tag == 'ol',
                start: start == null ? 1 : int.parse(start),
                level: level,
              );
            }
            _NoteItem? item;
            if (tag == 'li') {
              final owner = parent?.list;
              if (owner == null) throw _unsupportedList();
              item = _NoteItem(owner, owner.items++);
            }
            if (activeItem != null && identical(parent?.item, activeItem)) {
              if (isList) {
                // A list-only item still owns one visible marker before its
                // children. Later content resumes at the parent's indentation.
                if (activeItem.paragraphs == 0) openItemParagraph(activeItem);
                closeItemParagraph(activeItem);
              } else if (tag == 'p') {
                closeItemParagraph(activeItem);
              } else {
                openItemParagraph(activeItem);
              }
            }
            final outputTag = tag == 'a' || tag == 'img'
                ? 'span'
                : isList || tag == 'li'
                ? 'div'
                : tag;
            canonical.write('<$outputTag');
            final authoredStyle = attributes['style'];
            final style = _headings.contains(tag)
                ? 'font-weight: bold;${authoredStyle ?? ''}'
                : authoredStyle;
            if (style != null) {
              canonical.write(' style="${attributeEscape.convert(style)}"');
            }
            canonical.write(tag == 'br' ? '/>' : '>');
            int? linkIndex;
            if (tag == 'a') {
              if (activeLink) throw _malformed();
              final href = attributes['href'];
              if (href == null) throw _malformed();
              final link = _NoteLink(href);
              linkIndex = links.length;
              links.add(link);
              if (links.length > 10000) {
                throw const FormatException(
                  'The Zotero note has too many links.',
                );
              }
              activeLink = true;
              canonical.write('\uE000${linkIndex * 2}\uE001');
            }
            // Preserve authored empty paragraphs through the shared renderer.
            if (tag == 'p') {
              if (activeItem == null) {
                canonical.write('\uE002');
              } else {
                writeListParagraph(activeItem);
              }
            }
            if (tag == 'img') {
              final index = images.length;
              images.add(WmlVisual(visual: imageReader.read(attributes)));
              canonical.write('\uE000i$index\uE001');
            }
            if (_headings.contains(tag)) {
              canonical.write('\uE000$tag\uE001');
            }
            stack.add(_NoteElement(outputTag, tag, linkIndex, list, item));
          case XmlEventType.endElement:
            if (stack.isEmpty) throw _malformed();
            final element = stack.removeLast();
            if (element.list?.items == 0) throw _unsupportedList();
            final item = element.item;
            if (item != null) {
              if (item.paragraphs == 0) openItemParagraph(item);
              closeItemParagraph(item);
            }
            if (element.linkIndex != null) {
              canonical.write('\uE000${element.linkIndex! * 2 + 1}\uE001');
              activeLink = false;
            }
            if (element.tag == 'p' ||
                (element.tag == 'div' && !element.hasText)) {
              canonical.write('\uE002');
            }
            if (_headings.contains(element.tag)) {
              canonical.write('\uE000/h\uE001');
            }
            if (element.tag != 'br') {
              canonical.write('</${element.outputTag}>');
            }
            if (stack.isNotEmpty &&
                (element.hasText ||
                    element.tag == 'p' ||
                    element.tag == 'div' ||
                    element.tag == 'li' ||
                    element.tag == 'img')) {
              stack.last.hasText = true;
            }
          case XmlEventType.characters:
            _checkMarkers(reader.text);
            final parent = stack.lastOrNull;
            if (parent?.list != null) {
              if (reader.text.trim().isNotEmpty) throw _unsupportedList();
              break;
            }
            final item = parent?.item;
            if (item != null) {
              if (!item.implicitParagraphOpen && reader.text.trim().isEmpty) {
                break;
              }
              openItemParagraph(item);
            }
            canonical.write(escape.convert(reader.text));
            if (stack.isNotEmpty && reader.text.trim().isNotEmpty) {
              stack.last.hasText = true;
            }
          case XmlEventType.comment:
          case XmlEventType.none:
          case XmlEventType.endDocument:
            break;
          case XmlEventType.cdata:
          case XmlEventType.xmlDeclaration:
          case XmlEventType.processingInstruction:
          case XmlEventType.dtd:
            throw _malformed();
        }
      }
    } on XmlParseException {
      throw _malformed();
    }
    if (stack.isNotEmpty || activeLink) throw _malformed();
    final formatted = ZoteroFormattedText.fromHtml(canonical.toString());
    if (formatted.unsupportedFormatting.isNotEmpty) {
      throw UnsupportedError(
        'This Zotero note contains unsupported formatting or embedded content. The document was kept unchanged.',
      );
    }
    final paragraphs = <WmlParagraph>[];
    final placeholders = <String, WordZoteroNotePlaceholder>{};
    final listItems = <int, WordZoteroNoteListItem>{};
    _NoteLink? current;
    var currentStart = 0;
    var currentParagraph = 0;
    final marker = RegExp(
      '\uE000([0-9]+|h[1-6]|/h|l[0-9]+|i[0-9]+)\uE001|\uE002',
    );
    for (final sourceRuns in formatted.toParagraphRuns(
      baseProperties: baseProperties,
    )) {
      final paragraph = WmlParagraph();
      var offset = 0;
      for (final run in sourceRuns) {
        void append(String value) {
          if (value.isEmpty) return;
          paragraph.inlines.add(
            WmlRun(
              text: value,
              properties: run.properties.copy(),
              hyperlink: current?.placeholderId == null && current != null
                  ? WmlHyperlink(url: current.href)
                  : null,
            ),
          );
          offset += value.length;
        }

        var start = 0;
        for (final match in marker.allMatches(run.text)) {
          append(run.text.substring(start, match.start));
          final number = match[1];
          if (number != null && number.startsWith('i')) {
            paragraph.inlines.add(
              WmlRun(
                text: '\uFFFC',
                properties: run.properties.copy(),
                inlineVisual: images[int.parse(number.substring(1))],
                hyperlink: current == null
                    ? null
                    : WmlHyperlink(url: current.href),
              ),
            );
            offset++;
          } else if (number != null && number.startsWith('l')) {
            if (offset != 0 || listItems.containsKey(paragraphs.length)) {
              throw _malformed();
            }
            listItems[paragraphs.length] =
                items[int.parse(number.substring(1))];
          } else if (number != null && number.startsWith('h')) {
            if (offset != 0 || paragraph.properties.headingLevel != null) {
              throw _malformed();
            }
            final level = int.parse(number.substring(1));
            paragraph.properties
              ..headingLevel = level
              ..styleId = 'Heading$level';
          } else if (number == '/h') {
            if (paragraph.properties.headingLevel == null) throw _malformed();
          } else if (number != null) {
            final index = int.parse(number);
            final link = links[index ~/ 2];
            if (index.isEven) {
              if (current != null) throw _malformed();
              current = link;
              currentStart = offset;
              currentParagraph = paragraphs.length;
            } else {
              if (!identical(current, link) ||
                  currentParagraph != paragraphs.length ||
                  currentStart == offset) {
                throw const FormatException(
                  'A Zotero note link is empty or crosses a paragraph boundary.',
                );
              }
              final id = link.placeholderId;
              if (id != null) {
                if (placeholders.containsKey(id)) {
                  throw const FormatException(
                    'The Zotero note repeats a citation placeholder.',
                  );
                }
                placeholders[id] = WordZoteroNotePlaceholder(
                  id,
                  paragraphs.length,
                  currentStart,
                  offset,
                );
              }
              current = null;
            }
          }
          start = match.end;
        }
        append(run.text.substring(start));
      }
      if (current != null) {
        throw const FormatException('A Zotero note link crosses paragraphs.');
      }
      paragraphs.add(paragraph);
      if (paragraphs.length > 10000) {
        throw const FormatException('The Zotero note has too many paragraphs.');
      }
    }
    if (paragraphs.every((p) => p.text.trim().isEmpty)) {
      throw const FormatException('The selected Zotero note contains no text.');
    }
    if (listItems.length != items.length) throw _malformed();
    return WordZoteroNoteText._(paragraphs, placeholders, listItems);
  }

  static void _checkMarkers(String value) {
    if (value.contains(RegExp('[\uE000-\uE002]'))) throw _malformed();
  }

  static String _normalize(String html) {
    final normalized = html.replaceAllMapped(
      RegExp(r'&([A-Za-z][A-Za-z0-9]*);'),
      (match) {
        final value = _entities[match[1]];
        if (value == null) throw _malformed();
        return '&#$value;';
      },
    );
    // Zotero's DOM serializer emits HTML void elements. Recognize their real
    // tag boundaries without mistaking a quoted '>' or comment for markup.
    final out = StringBuffer();
    var position = 0;
    while (position < normalized.length) {
      final start = normalized.indexOf('<', position);
      if (start < 0) {
        out.write(normalized.substring(position));
        break;
      }
      out.write(normalized.substring(position, start));
      if (normalized.startsWith('<!--', start)) {
        final end = normalized.indexOf('-->', start + 4);
        if (end < 0) throw _malformed();
        out.write(normalized.substring(start, end + 3));
        position = end + 3;
        continue;
      }
      var end = start + 1;
      int? quote;
      for (; end < normalized.length; end++) {
        final code = normalized.codeUnitAt(end);
        if (quote != null) {
          if (code == quote) quote = null;
        } else if (code == 34 || code == 39) {
          quote = code;
        } else if (code == 62) {
          break;
        }
      }
      if (end == normalized.length) throw _malformed();
      final tag = normalized.substring(start, end);
      out.write(tag);
      if (RegExp(
            r'^<(?:img|br)(?:\s|/|$)',
            caseSensitive: false,
          ).hasMatch(tag) &&
          !tag.trimRight().endsWith('/')) {
        out.write('/');
      }
      out.write('>');
      position = end + 1;
    }
    return out.toString();
  }

  static FormatException _malformed() => const FormatException(
    'Zotero returned a malformed or unsupported note. The document was kept unchanged.',
  );
  static UnsupportedError _unsupportedList() => UnsupportedError(
    'This Zotero note needs bulleted or decimal-numbered lists with at most nine levels, paragraphs, and inline content. Custom numbering and other list structures are not supported. The document was kept unchanged.',
  );
  static const _headings = <String>{'h1', 'h2', 'h3', 'h4', 'h5', 'h6'};
  static const _tags = <String>{
    ..._headings,
    'quds-note',
    'html',
    'body',
    'div',
    'p',
    'span',
    'a',
    'br',
    'img',
    'b',
    'strong',
    'i',
    'em',
    'u',
    's',
    'strike',
    'del',
    'sub',
    'sup',
    'ul',
    'ol',
    'li',
  };
  static const _entities = <String, int>{
    'amp': 38,
    'lt': 60,
    'gt': 62,
    'quot': 34,
    'apos': 39,
    'nbsp': 160,
    'ensp': 8194,
    'emsp': 8195,
    'thinsp': 8201,
    'ndash': 8211,
    'mdash': 8212,
    'lsquo': 8216,
    'rsquo': 8217,
    'sbquo': 8218,
    'ldquo': 8220,
    'rdquo': 8221,
    'bdquo': 8222,
    'bull': 8226,
    'hellip': 8230,
    'laquo': 171,
    'raquo': 187,
    'copy': 169,
    'reg': 174,
    'trade': 8482,
    'deg': 176,
    'plusmn': 177,
    'times': 215,
    'divide': 247,
    'minus': 8722,
    'micro': 181,
    'middot': 183,
  };
}

/// A paragraph in one independent research-note list.
///
/// [level] is the native Word level, from zero through eight. A [continuation]
/// belongs to the same item and indentation without adding another marker.
final class WordZoteroNoteListItem {
  const WordZoteroNoteListItem({
    required this.listId,
    required this.numbered,
    required this.start,
    required this.index,
    this.level = 0,
    this.continuation = false,
  });
  final int listId;
  final bool numbered;
  final int start;
  final int index;
  final int level;
  final bool continuation;
}

final class WordZoteroNotePlaceholder {
  const WordZoteroNotePlaceholder(
    this.id,
    this.paragraphIndex,
    this.start,
    this.end,
  );
  final String id;
  final int paragraphIndex;
  final int start;
  final int end;
}

final class _NoteElement {
  _NoteElement(this.outputTag, this.tag, this.linkIndex, this.list, this.item);
  final String outputTag;
  final String tag;
  final int? linkIndex;
  final _NoteList? list;
  final _NoteItem? item;
  bool hasText = false;
}

final class _NoteList {
  _NoteList({
    required this.id,
    required this.numbered,
    required this.start,
    required this.level,
  });
  final int id;
  final bool numbered;
  final int start;
  final int level;
  int items = 0;
}

final class _NoteItem {
  _NoteItem(this.list, this.index);
  final _NoteList list;
  final int index;
  int paragraphs = 0;
  bool implicitParagraphOpen = false;
}

final class _NoteLink {
  _NoteLink(this.href) {
    const prefix = 'https://www.zotero.org/?';
    if (href.startsWith(prefix)) {
      final id = href.substring(prefix.length);
      if (!RegExp(r'^[A-Za-z0-9]{1,128}$').hasMatch(id)) {
        throw const FormatException('Invalid Zotero citation placeholder.');
      }
      placeholderId = id;
      return;
    }
    final uri = Uri.tryParse(href);
    if (href.length > 8192 ||
        href.trim() != href ||
        RegExp(r'[\x00-\x20\x7f]').hasMatch(href) ||
        uri == null ||
        !const <String>{
          'http',
          'https',
          'mailto',
          'zotero',
        }.contains(uri.scheme) ||
        (uri.scheme != 'mailto' && uri.host.isEmpty) ||
        uri.userInfo.isNotEmpty) {
      throw UnsupportedError(
        'This Zotero note has an unsupported link target.',
      );
    }
  }
  final String href;
  String? placeholderId;
}
