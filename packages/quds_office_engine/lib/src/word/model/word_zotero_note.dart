import 'dart:convert';

import '../../xml/xml_reader.dart';
import '../../zotero/zotero_formatted_text.dart';
import '../properties/wml_properties.dart';
import 'wml_document.dart';
import 'word_tree.dart';
import 'word_zotero_note_image.dart';

/// A bounded, inert note fragment with citation placeholders kept separate.
/// Unsupported structure and formatting are refused before document edits.
final class WordZoteroNoteText {
  WordZoteroNoteText._(
    this.blocks,
    this.paragraphs,
    this.placeholders,
    this.listItems,
    this.quoteDepths,
    this.paragraphFormats,
  );

  /// Native blocks in document order, retaining each table's cell ownership.
  final List<WmlBlock> blocks;

  /// The same paragraph objects as [blocks], flattened in row-major order.
  /// Citation and list indexes address this view, never disconnected copies.
  /// It includes vertical continuations and trailing cell paragraphs.
  final List<WmlParagraph> paragraphs;
  final Map<String, WordZoteroNotePlaceholder> placeholders;

  /// Native list metadata keyed by each item or continuation paragraph index.
  final Map<int, WordZoteroNoteListItem> listItems;

  /// Quote depth for each quoted native paragraph. Structural quote scopes
  /// never become document text; citation and list indexes keep the same view.
  /// Native insertion adds 18 points of left indentation per level, at most
  /// eight levels. Zotero's editor-only CSS borders/spacing are not exported.
  final Map<int, int> quoteDepths;

  /// Explicit layout exported on Zotero paragraphs and headings. Applied after
  /// native heading/list/quote formatting, without modifying surrounding prose.
  /// Indexes refer to the final native tree, including merged-cell continuations.
  final Map<int, WordZoteroNoteParagraphFormat> paragraphFormats;
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
    final formats = <WordZoteroNoteParagraphFormat>[];
    final tables = <WmlTable>[];
    final cells = <({WmlTable table, WmlTableCell cell})>[];
    final columnWidths = <WmlTableCell, List<double?>>{};
    final rowSpans = <WmlTableCell, int>{};
    final rowGroups = <WmlTableRow, Object>{};
    final directRowGroups = <WmlTable, Object>{};
    var nativeCells = 0;
    var listCount = 0;
    var quoteCount = 0;
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

    void openCellParagraph(_NoteElement element) {
      if (element.implicitCellParagraphOpen) return;
      canonical.write('<p>\uE002');
      element
        ..implicitCellParagraphOpen = true
        ..hasText = true;
    }

    void closeCellParagraph(_NoteElement element) {
      if (!element.implicitCellParagraphOpen) return;
      canonical.write('\uE002</p>');
      element.implicitCellParagraphOpen = false;
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
                  !((name == 'dir' || name == 'data-indent') &&
                      (tag == 'p' || _headings.contains(tag))) &&
                  !(name == 'href' && tag == 'a') &&
                  !(name == 'start' && tag == 'ol') &&
                  !(_cellTags.contains(tag) &&
                      const <String>{
                        'colspan',
                        'rowspan',
                        'data-colwidth',
                      }.contains(name)) &&
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
            final quoteDepth = stack
                .where((element) => element.tag == 'blockquote')
                .length;
            if (tag == 'blockquote') {
              if (activeLink ||
                  !_quoteParents.contains(parent?.tag) ||
                  stack.any(
                    (element) => !_quoteAncestors.contains(element.tag),
                  )) {
                throw _unsupportedQuote();
              }
              if (quoteDepth >= 8) {
                throw const FormatException(
                  'The Zotero note exceeds eight levels of blockquotes.',
                );
              }
            }
            if ((parent?.tag == 'blockquote' && !_quoteBlocks.contains(tag)) ||
                (quoteDepth != 0 && tag == 'table')) {
              throw _unsupportedQuote();
            }
            if ((_tableContainers.contains(parent?.tag) &&
                    !(switch (parent?.tag) {
                      'table' => tag == 'tbody' || tag == 'tr',
                      'tbody' => tag == 'tr',
                      'tr' => _cellTags.contains(tag),
                      _ => false,
                    })) ||
                (_tableTags.contains(tag) &&
                    (attributes['class']?.trim().isNotEmpty == true ||
                        (!_cellTags.contains(tag) &&
                            attributes['style']?.trim().isNotEmpty == true)))) {
              throw _unsupportedTable();
            }
            WmlTable? table;
            WmlTableRow? row;
            WmlTableCell? cell;
            int? tableIndex;
            int? cellIndex;
            final activeTable = stack
                .where((element) => element.table != null)
                .lastOrNull
                ?.table;
            if (tag == 'table') {
              if (activeLink ||
                  stack.any(
                    (element) => !const <String>{
                      'quds-note',
                      'html',
                      'body',
                      'div',
                      'table',
                      'tbody',
                      'tr',
                      'td',
                      'th',
                    }.contains(element.tag),
                  ) ||
                  (activeTable != null && parent?.cellFlow != true)) {
                throw _unsupportedTable();
              }
              if (stack.where((element) => element.table != null).length >=
                  _maximumTableDepth) {
                throw const FormatException(
                  'The Zotero note exceeds eight levels of nested tables.',
                );
              }
              if (tables.length >= 64) {
                throw const FormatException(
                  'The Zotero note has too many tables.',
                );
              }
              tableIndex = tables.length;
              table = WmlTable();
              tables.add(table);
            } else if (tag == 'tbody') {
              if (parent?.table == null) throw _unsupportedTable();
              // Each run of direct rows is a separate implicit group. Even
              // an empty tbody ends that run and must block a rowspan from
              // reaching a later direct row across the explicit group.
              directRowGroups.remove(parent!.table);
            } else if (tag == 'tr') {
              if (activeTable == null ||
                  !const <String>{'table', 'tbody'}.contains(parent?.tag)) {
                throw _unsupportedTable();
              }
              if (activeTable.rows.length >= 256) {
                throw const FormatException(
                  'A Zotero note table has too many rows.',
                );
              }
              row = WmlTableRow();
              activeTable.rows.add(row);
              rowGroups[row] = parent!.tag == 'tbody'
                  ? parent
                  : directRowGroups.putIfAbsent(activeTable, Object.new);
            } else if (_cellTags.contains(tag)) {
              final owner = parent?.row;
              if (owner == null || activeTable == null) {
                throw _unsupportedTable();
              }
              if (owner.cells.length >= 32 || cells.length >= 4096) {
                throw const FormatException(
                  'The Zotero note exceeds the table cell bounds.',
                );
              }
              final parsedCell = _tableCell(attributes);
              cell = parsedCell.cell;
              final columns = owner.cells.fold<int>(
                cell.gridSpan,
                (sum, previous) => sum + previous.gridSpan,
              );
              if (columns > 32) {
                throw const FormatException(
                  'A Zotero note table has too many columns.',
                );
              }
              owner.cells.add(cell);
              columnWidths[cell] = parsedCell.widths;
              rowSpans[cell] = parsedCell.rows;
              cellIndex = cells.length;
              cells.add((table: activeTable, cell: cell));
            }
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
                            'blockquote',
                            'td',
                            'th',
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
            if (parent != null && parent.cellFlow) {
              if (_cellBlockTags.contains(tag)) {
                closeCellParagraph(parent);
              } else {
                openCellParagraph(parent);
              }
            }
            final outputTag = tag == 'a' || tag == 'img'
                ? 'span'
                : isList || tag == 'li' || _tableTags.contains(tag)
                ? 'div'
                : tag;
            canonical.write('<$outputTag');
            var authoredStyle = _tableTags.contains(tag)
                ? null
                : attributes['style'];
            WordZoteroNoteParagraphFormat? paragraphFormat;
            if (tag == 'p' || _headings.contains(tag)) {
              final parsed = _paragraphFormat(attributes);
              paragraphFormat = parsed.format;
              authoredStyle = parsed.inlineStyle;
              // A native list paragraph has one direction for its text and
              // marker. A child RTL paragraph can change only the text's
              // direction in HTML; retain the guard until those are distinct.
              if (activeItem != null && paragraphFormat?.rightToLeft == true) {
                throw UnsupportedError(
                  'Right-to-left paragraphs inside Zotero lists are not yet supported. The document was kept unchanged.',
                );
              }
            }
            final style = tag == 'th'
                ? 'font-weight: bold;'
                : _headings.contains(tag)
                ? 'font-weight: bold;${authoredStyle ?? ''}'
                : authoredStyle;
            if (style != null) {
              canonical.write(' style="${attributeEscape.convert(style)}"');
            }
            canonical.write(tag == 'br' ? '/>' : '>');
            // Structural markers own separate canonical paragraphs. They are
            // removed before indexing actual paragraphs and never become text.
            if (tableIndex != null) {
              canonical.write('<p>\uE000t$tableIndex\uE001</p>');
            }
            if (cellIndex != null) {
              canonical.write('<p>\uE000c$cellIndex\uE001</p>');
            }
            if (tag == 'blockquote') {
              canonical.write('<p>\uE000q${quoteCount++}\uE001</p>');
            }
            if (paragraphFormat != null) {
              canonical.write('\uE000p${formats.length}\uE001');
              formats.add(paragraphFormat);
            }
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
            stack.add(
              _NoteElement(
                outputTag,
                tag,
                linkIndex,
                list,
                item,
                table: table,
                row: row,
                cell: cell,
                cellFlow:
                    cell != null ||
                    (tag == 'div' &&
                        stack.any((element) => element.cell != null)),
              ),
            );
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
            if (element.cellFlow) closeCellParagraph(element);
            if (element.cell != null) {
              if (!element.hasText) canonical.write('<p>\uE002</p>');
              canonical.write('<p>\uE000/c\uE001</p>');
            }
            if (element.table != null) {
              nativeCells += _finishTable(
                element.table!,
                columnWidths,
                rowSpans,
                rowGroups,
                remainingCells: 4096 - nativeCells,
              );
              canonical.write('<p>\uE000/t\uE001</p>');
            }
            if (element.tag == 'blockquote') {
              // Keep an authored empty quote without leaking the scope markers
              // into text or manufacturing an extra outer/cell paragraph.
              if (!element.hasText) canonical.write('<p>\uE002</p>');
              canonical.write('<p>\uE000/q\uE001</p>');
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
                    element.tag == 'blockquote' ||
                    _headings.contains(element.tag) ||
                    element.tag == 'img' ||
                    _tableTags.contains(element.tag))) {
              stack.last.hasText = true;
            }
          case XmlEventType.characters:
            _checkMarkers(reader.text);
            final parent = stack.lastOrNull;
            if (parent?.tag == 'blockquote') {
              if (reader.text.trim().isNotEmpty) throw _unsupportedQuote();
              break;
            }
            if (parent?.list != null) {
              if (reader.text.trim().isNotEmpty) throw _unsupportedList();
              break;
            }
            if (_tableContainers.contains(parent?.tag)) {
              if (reader.text.trim().isNotEmpty) throw _unsupportedTable();
              break;
            }
            if (parent != null && parent.cellFlow) {
              if (!parent.implicitCellParagraphOpen &&
                  reader.text.trim().isEmpty) {
                break;
              }
              openCellParagraph(parent);
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
    final formatted = ZoteroFormattedText.fromHtml(
      canonical.toString(),
      allowNoteColors: true,
    );
    if (formatted.unsupportedFormatting.isNotEmpty) {
      throw UnsupportedError(
        'This Zotero note contains unsupported formatting or embedded content. The document was kept unchanged.',
      );
    }
    final blocks = <WmlBlock>[];
    final paragraphs = <WmlParagraph>[];
    final placeholders = <String, WordZoteroNotePlaceholder>{};
    final listItems = <int, WordZoteroNoteListItem>{};
    final quoteDepths = <int, int>{};
    final paragraphFormats = <int, WordZoteroNoteParagraphFormat>{};
    _NoteLink? current;
    var currentStart = 0;
    var currentParagraph = 0;
    final tableOwners = <_NoteTableOwner>[];
    var tableMarks = 0;
    var cellMarks = 0;
    var quoteMarks = 0;
    final quoteOwners = <WmlTableCell?>[];
    final structure = RegExp(
      r'^\uE000(t[0-9]+|c[0-9]+|q[0-9]+|/c|/t|/q)\uE001$',
    );
    final marker = RegExp(
      '\uE000([0-9]+|h[1-6]|/h|l[0-9]+|i[0-9]+|p[0-9]+)\uE001|\uE002',
    );
    void appendParagraph(WmlParagraph paragraph, List<WmlBlock> destination) {
      if (paragraphs.length >= 10000) {
        throw const FormatException('The Zotero note has too many paragraphs.');
      }
      destination.add(paragraph);
      if (quoteOwners.isNotEmpty) {
        quoteDepths[paragraphs.length] = quoteOwners.length;
      }
      paragraphs.add(paragraph);
    }

    for (final sourceRuns in formatted.toParagraphRuns(
      baseProperties: baseProperties,
    )) {
      final structural = structure.firstMatch(
        sourceRuns.map((run) => run.text).join(),
      );
      if (structural != null) {
        if (current != null) throw _malformed();
        final value = structural[1]!;
        if (value.startsWith('q')) {
          if (quoteOwners.length >= 8 ||
              int.parse(value.substring(1)) != quoteMarks++ ||
              (tableOwners.isNotEmpty && tableOwners.last.cell == null)) {
            throw _malformed();
          }
          quoteOwners.add(tableOwners.lastOrNull?.cell);
        } else if (value == '/q') {
          if (quoteOwners.isEmpty ||
              !identical(quoteOwners.last, tableOwners.lastOrNull?.cell)) {
            throw _malformed();
          }
          quoteOwners.removeLast();
        } else if (quoteOwners.isNotEmpty) {
          // Quotes may be inside a cell but cannot cross table ownership.
          throw _malformed();
        } else if (value.startsWith('t')) {
          final index = int.parse(value.substring(1));
          final parent = tableOwners.lastOrNull;
          if ((parent != null && parent.cell == null) ||
              tableOwners.length >= _maximumTableDepth ||
              index != tableMarks++) {
            throw _malformed();
          }
          final table = tables[index];
          (parent?.cell?.blocks ?? blocks).add(table);
          tableOwners.add(_NoteTableOwner(table));
        } else if (value.startsWith('c')) {
          final index = int.parse(value.substring(1));
          final owner = tableOwners.lastOrNull;
          if (owner == null ||
              owner.cell != null ||
              index != cellMarks++ ||
              !identical(cells[index].table, owner.table)) {
            throw _malformed();
          }
          owner.cell = cells[index].cell;
        } else if (value == '/c') {
          final owner = tableOwners.lastOrNull;
          final cell = owner?.cell;
          if (cell == null || cell.blocks.isEmpty) {
            throw _malformed();
          }
          // DOCX cells end in a paragraph. Keep it in the native tree before
          // citation/list indexing, rather than adding it only during saving.
          if (cell.blocks.last is! WmlParagraph) {
            appendParagraph(WmlParagraph(), cell.blocks);
          }
          owner!.cell = null;
        } else {
          if (tableOwners.isEmpty || tableOwners.last.cell != null) {
            throw _malformed();
          }
          tableOwners.removeLast();
        }
        continue;
      }
      if (tableOwners.isNotEmpty && tableOwners.last.cell == null) {
        throw _malformed();
      }
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
          } else if (number != null && number.startsWith('p')) {
            if (offset != 0 ||
                paragraphFormats.containsKey(paragraphs.length)) {
              throw _malformed();
            }
            paragraphFormats[paragraphs.length] =
                formats[int.parse(number.substring(1))];
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
      appendParagraph(
        paragraph,
        tableOwners.lastOrNull?.cell?.blocks ?? blocks,
      );
    }
    if (tableOwners.isNotEmpty ||
        quoteOwners.isNotEmpty ||
        quoteMarks != quoteCount ||
        tableMarks != tables.length ||
        cellMarks != cells.length) {
      throw _malformed();
    }
    if (tables.isEmpty && paragraphs.every((p) => p.text.trim().isEmpty)) {
      throw const FormatException('The selected Zotero note contains no text.');
    }
    if (listItems.length != items.length ||
        paragraphFormats.length != formats.length) {
      throw _malformed();
    }
    // HTML omits cells covered by a rowspan, while native Word retains an
    // empty paragraph in each continuation cell. Address the final native
    // tree, so cloning it in the citing session cannot shift later citations
    // or list metadata onto one of those synthetic paragraphs.
    final nativeParagraphs = WordTree.paragraphs(blocks).toList();
    if (nativeParagraphs.length > 10000) {
      throw const FormatException('The Zotero note has too many paragraphs.');
    }
    final indexes = Map<WmlParagraph, int>.identity();
    for (var index = 0; index < nativeParagraphs.length; index++) {
      indexes[nativeParagraphs[index]] = index;
    }
    return WordZoteroNoteText._(
      blocks,
      nativeParagraphs,
      {
        for (final entry in placeholders.entries)
          entry.key: WordZoteroNotePlaceholder(
            entry.value.id,
            indexes[paragraphs[entry.value.paragraphIndex]]!,
            entry.value.start,
            entry.value.end,
          ),
      },
      {
        for (final entry in listItems.entries)
          indexes[paragraphs[entry.key]]!: entry.value,
      },
      {
        for (final entry in quoteDepths.entries)
          indexes[paragraphs[entry.key]]!: entry.value,
      },
      {
        for (final entry in paragraphFormats.entries)
          indexes[paragraphs[entry.key]]!: entry.value,
      },
    );
  }

  static ({WordZoteroNoteParagraphFormat? format, String? inlineStyle})
  _paragraphFormat(Map<String, String> attributes) {
    final rawDirection = attributes['dir']?.trim().toLowerCase();
    if (rawDirection != null &&
        rawDirection != 'ltr' &&
        rawDirection != 'rtl') {
      throw _unsupportedParagraphFormat();
    }
    final direction = rawDirection == null ? null : rawDirection == 'rtl';
    final rawIndent = attributes['data-indent']?.trim();
    if (rawIndent != null && !RegExp(r'^[1-7]$').hasMatch(rawIndent)) {
      throw _unsupportedParagraphFormat();
    }
    final level = rawIndent == null ? 0 : int.parse(rawIndent);
    WmlJustification? alignment;
    bool? paddingRight;
    final names = <String>{};
    final inlineStyles = <String>[];
    for (final declaration in (attributes['style'] ?? '').split(';')) {
      if (declaration.trim().isEmpty) continue;
      final colon = declaration.indexOf(':');
      if (colon < 1) throw _unsupportedParagraphFormat();
      final name = declaration.substring(0, colon).trim().toLowerCase();
      final value = declaration.substring(colon + 1).trim().toLowerCase();
      if (name == 'text-align') {
        if (!names.add(name)) throw _unsupportedParagraphFormat();
        alignment = switch (value) {
          'left' => WmlJustification.left,
          'right' => WmlJustification.right,
          'center' => WmlJustification.center,
          'justify' => WmlJustification.justify,
          _ => throw _unsupportedParagraphFormat(),
        };
      } else if (name == 'padding-left' || name == 'padding-right') {
        // Zotero emits 40 CSS px per data-indent level for word-processor
        // export. Its editor-only 30 px rule is not part of that payload.
        // Accept the redundant compatibility style exactly once, and never
        // infer arbitrary CSS layout or double-count it with data-indent.
        if (paddingRight != null || level == 0 || value != '${level * 40}px') {
          throw _unsupportedParagraphFormat();
        }
        paddingRight = name == 'padding-right';
        if (direction != null && direction != paddingRight) {
          throw _unsupportedParagraphFormat();
        }
      } else {
        // The shared inert formatter must still validate every other style.
        inlineStyles.add(declaration);
      }
    }
    final format = direction == null && level == 0 && alignment == null
        ? null
        : WordZoteroNoteParagraphFormat(
            rightToLeft: direction,
            justification:
                alignment ??
                (direction == null
                    ? null
                    : direction
                    ? WmlJustification.right
                    : WmlJustification.left),
            indentPoints: level * 30.0,
            // An RTL Zotero editor can export right padding without a dir
            // attribute. Preserve the physical side without inventing bidi.
            indentOnRight: paddingRight ?? direction ?? false,
          );
    return (
      format: format,
      inlineStyle: inlineStyles.isEmpty ? null : inlineStyles.join(';'),
    );
  }

  static UnsupportedError _unsupportedParagraphFormat() => UnsupportedError(
    'This Zotero paragraph uses unsupported direction, indentation or alignment. The document was kept unchanged.',
  );

  static ({WmlTableCell cell, int rows, List<double?> widths}) _tableCell(
    Map<String, String> attributes,
  ) {
    final rawRows = attributes['rowspan']?.trim();
    if (rawRows != null && !RegExp(r'^[1-9][0-9]{0,2}$').hasMatch(rawRows)) {
      throw _unsupportedTable();
    }
    final rows = rawRows == null ? 1 : int.parse(rawRows);
    if (rows > 256) throw _unsupportedTable();
    final rawSpan = attributes['colspan']?.trim();
    if (rawSpan != null && !RegExp(r'^[1-9][0-9]?$').hasMatch(rawSpan)) {
      throw _unsupportedTable();
    }
    final span = rawSpan == null ? 1 : int.parse(rawSpan);
    if (span > 32) throw _unsupportedTable();
    final widths = List<double?>.filled(span, null);
    final rawWidth = attributes['data-colwidth']?.trim();
    if (rawWidth != null) {
      // ProseMirror records one width per logical column, using zero for a
      // column that has not been resized. Bound the vector before splitting.
      if (rawWidth.length > 159) throw _unsupportedTable();
      final values = rawWidth.split(',');
      if (values.length != span) throw _unsupportedTable();
      for (var column = 0; column < span; column++) {
        final value = values[column];
        if (!RegExp(r'^(0|[1-9][0-9]{0,3})$').hasMatch(value)) {
          throw _unsupportedTable();
        }
        final pixels = int.parse(value);
        if (pixels > 4000) throw _unsupportedTable();
        if (pixels != 0) widths[column] = pixels * 0.75;
      }
    }
    return (
      cell: WmlTableCell(
        gridSpan: span,
        fillColor: _cellFill(attributes['style']),
      ),
      rows: rows,
      widths: widths,
    );
  }

  static String? _cellFill(String? style) {
    if (style == null || style.trim().isEmpty) return null;
    String? fill;
    var seen = false;
    for (final declaration in style.split(';')) {
      if (declaration.trim().isEmpty) continue;
      final colon = declaration.indexOf(':');
      if (colon < 0 ||
          seen ||
          declaration.substring(0, colon).trim().toLowerCase() !=
              'background-color') {
        throw _unsupportedTable();
      }
      seen = true;
      final value = declaration.substring(colon + 1).trim().toLowerCase();
      if (value == 'transparent') continue;
      if (RegExp(r'^#[0-9a-f]{6}$').hasMatch(value)) {
        fill = value.substring(1).toUpperCase();
      } else if (RegExp(r'^#[0-9a-f]{3}$').hasMatch(value)) {
        fill = value
            .substring(1)
            .split('')
            .map((part) => '$part$part')
            .join()
            .toUpperCase();
      } else {
        final rgb = RegExp(
          r'^rgb\(\s*([0-9]{1,3})\s*,\s*([0-9]{1,3})\s*,\s*([0-9]{1,3})\s*\)$',
        ).firstMatch(value);
        if (rgb == null) throw _unsupportedTable();
        final components = [for (var i = 1; i <= 3; i++) int.parse(rgb[i]!)];
        if (components.any((component) => component > 255)) {
          throw _unsupportedTable();
        }
        fill = components
            .map((component) => component.toRadixString(16).padLeft(2, '0'))
            .join()
            .toUpperCase();
      }
    }
    return fill;
  }

  static int _finishTable(
    WmlTable table,
    Map<WmlTableCell, List<double?>> columnWidths,
    Map<WmlTableCell, int> rowSpans,
    Map<WmlTableRow, Object> rowGroups, {
    required int remainingCells,
  }) {
    if (table.rows.isEmpty || table.rows.first.cells.isEmpty) {
      throw _unsupportedTable();
    }
    final columns = table.rows.first.cells.fold<int>(
      0,
      (sum, cell) => sum + cell.gridSpan,
    );
    // Bound the expanded native representation before allocating continuation
    // cells. A small HTML payload can otherwise amplify through row spans.
    var nativeCells = 0;
    for (final row in table.rows) {
      for (final cell in row.cells) {
        nativeCells += rowSpans[cell]!;
        if (nativeCells > remainingCells) {
          throw const FormatException(
            'The Zotero note exceeds the native table cell bounds.',
          );
        }
      }
    }
    final coverage = [
      for (final _ in table.rows) List<WmlTableCell?>.filled(columns, null),
    ];
    final origins = <WmlTableCell, int>{};
    final widths = List<double?>.filled(columns, null);
    for (var rowIndex = 0; rowIndex < table.rows.length; rowIndex++) {
      final row = table.rows[rowIndex];
      var column = 0;
      for (final cell in row.cells) {
        while (column < columns && coverage[rowIndex][column] != null) {
          column++;
        }
        final rows = rowSpans[cell]!;
        if (column + cell.gridSpan > columns ||
            rowIndex + rows > table.rows.length) {
          throw _unsupportedTable();
        }
        for (
          var coveredRow = rowIndex;
          coveredRow < rowIndex + rows;
          coveredRow++
        ) {
          // HTML row spans belong to a single row group. Do not silently
          // extend a cell from one tbody (or direct-row group) into another.
          if (!identical(rowGroups[row], rowGroups[table.rows[coveredRow]])) {
            throw _unsupportedTable();
          }
          for (
            var coveredColumn = column;
            coveredColumn < column + cell.gridSpan;
            coveredColumn++
          ) {
            if (coverage[coveredRow][coveredColumn] != null) {
              throw _unsupportedTable();
            }
            coverage[coveredRow][coveredColumn] = cell;
          }
        }
        origins[cell] = rowIndex;
        cell.vMerge = rows > 1 ? WmlVMerge.restart : WmlVMerge.none;
        for (var offset = 0; offset < cell.gridSpan; offset++) {
          final width = columnWidths[cell]![offset];
          final logicalColumn = column + offset;
          if (width != null) {
            if (widths[logicalColumn] != null &&
                widths[logicalColumn] != width) {
              throw _unsupportedTable();
            }
            widths[logicalColumn] = width;
          }
        }
        column += cell.gridSpan;
      }
      if (coverage[rowIndex].any((cell) => cell == null)) {
        throw _unsupportedTable();
      }
    }
    final grid = [for (final width in widths) width ?? 120.0];
    if (grid.fold<double>(0, (sum, width) => sum + width) > 4000) {
      throw _unsupportedTable();
    }
    table.grid.addAll(grid);
    for (var rowIndex = 0; rowIndex < table.rows.length; rowIndex++) {
      final normalized = <WmlTableCell>[];
      var column = 0;
      while (column < columns) {
        final origin = coverage[rowIndex][column]!;
        final cell = origins[origin] == rowIndex
            ? origin
            : WmlTableCell(
                blocks: [WmlParagraph()],
                gridSpan: origin.gridSpan,
                vMerge: WmlVMerge.cont,
                fillColor: origin.fillColor,
              );
        var width = 0.0;
        for (var offset = 0; offset < cell.gridSpan; offset++) {
          width += grid[column++];
        }
        cell.width = width;
        normalized.add(cell);
      }
      table.rows[rowIndex].cells
        ..clear()
        ..addAll(normalized);
    }
    return nativeCells;
  }

  static UnsupportedError _unsupportedTable() => UnsupportedError(
    'This Zotero note needs rectangular tables with supported row and column spans, widths and background colors. Spans must stay within their row group. Tables may nest within cells up to eight levels; other table formatting is not supported. The document was kept unchanged.',
  );

  static const _maximumTableDepth = 8;
  static const _tableContainers = <String>{'table', 'tbody', 'tr'};
  static const _cellTags = <String>{'td', 'th'};
  static const _tableTags = <String>{..._tableContainers, ..._cellTags};
  static const _cellBlockTags = <String>{
    ..._headings,
    'p',
    'div',
    'ul',
    'ol',
    'table',
    'blockquote',
  };

  static const _quoteParents = <String>{
    'quds-note',
    'html',
    'body',
    'div',
    'td',
    'th',
    'blockquote',
  };
  static const _quoteAncestors = <String>{
    ..._quoteParents,
    ..._tableContainers,
  };
  static const _quoteBlocks = <String>{
    ..._headings,
    'p',
    'div',
    'ul',
    'ol',
    'blockquote',
  };

  static UnsupportedError _unsupportedQuote() => UnsupportedError(
    'This Zotero blockquote needs paragraphs, headings, lists or nested blockquotes. Quotes inside list items, tables inside quotes and inline-only quote content are not supported. The document was kept unchanged.',
  );

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
    ..._tableTags,
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
    'blockquote',
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

/// Canonical paragraph layout from Zotero's exported note HTML.
///
/// Indentation uses the exported 40 CSS pixels (30 points) per level, not the
/// editor-only stylesheet's 30 pixels. It composes with native lists/quotes.
final class WordZoteroNoteParagraphFormat {
  const WordZoteroNoteParagraphFormat({
    this.rightToLeft,
    this.justification,
    this.indentPoints = 0,
    this.indentOnRight = false,
  });

  final bool? rightToLeft;
  final WmlJustification? justification;
  final double indentPoints;
  final bool indentOnRight;

  void applyTo(WmlParagraphProps properties) {
    if (rightToLeft != null) properties.rightToLeft = rightToLeft;
    if (justification != null) {
      properties
        ..justification = justification!
        ..explicitJustification = true;
    }
    if (indentPoints != 0) {
      properties
        ..indent = properties.indent.copyWith(
          left: properties.indent.left + (indentOnRight ? 0 : indentPoints),
          right: properties.indent.right + (indentOnRight ? indentPoints : 0),
        )
        ..explicitIndent = true;
    }
  }
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

final class _NoteTableOwner {
  _NoteTableOwner(this.table);
  final WmlTable table;
  WmlTableCell? cell;
}

final class _NoteElement {
  _NoteElement(
    this.outputTag,
    this.tag,
    this.linkIndex,
    this.list,
    this.item, {
    this.table,
    this.row,
    this.cell,
    this.cellFlow = false,
  });
  final String outputTag;
  final String tag;
  final int? linkIndex;
  final _NoteList? list;
  final _NoteItem? item;
  final WmlTable? table;
  final WmlTableRow? row;
  final WmlTableCell? cell;
  final bool cellFlow;
  bool implicitCellParagraphOpen = false;
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
