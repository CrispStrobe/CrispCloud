import 'dart:convert';
import 'dart:typed_data';

import '../../odf/odf_text.dart';
import '../../opc/zip/zip_writer.dart';
import '../../visual/office_visual.dart';
import '../../xml/xml_writer.dart';
import '../model/wml_document.dart';
import '../model/word_notes.dart';
import '../properties/wml_properties.dart';

/// Bounded new-document ODT writer for the shared Word model.
///
/// This is an export path. It emits the modeled text, paragraph/run formatting,
/// tables, pictures, frames, page geometry and basic headers/footers. It does
/// not claim to preserve arbitrary imported ODF XML or every Word feature.
/// Word and Zotero fields export their visible cached results; their native
/// instructions and editable field metadata are not part of this export.
abstract final class OdtDocumentWriter {
  /// Serializes [document] as a new ODT package.
  static Uint8List writeBytes(WmlDocument document) {
    final layout = _OdtLayout(document);
    final content = _contentXml(document, layout);
    final styles = _stylesXml(document, layout);
    final manifest = _manifestXml(layout.media);
    final meta = _metaXml(document);
    final zip = ZipWriter();
    zip.addFile(
      'mimetype',
      utf8.encode('application/vnd.oasis.opendocument.text'),
      store: true,
    );
    zip.addFile('META-INF/manifest.xml', utf8.encode(manifest));
    zip.addFile('content.xml', utf8.encode(content));
    zip.addFile('styles.xml', utf8.encode(styles));
    zip.addFile('meta.xml', utf8.encode(meta));
    for (final entry in layout.mediaBytes.entries) {
      zip.addFile(entry.key, entry.value);
    }
    return zip.close();
  }

  static const _mime = 'application/vnd.oasis.opendocument.text';

  static String _contentXml(WmlDocument document, _OdtLayout layout) {
    final body = XmlWriter();
    body.writeStartElement('text', prefix: 'office');
    for (var index = 0; index < document.sections.length; index++) {
      final section = document.sections[index];
      String? firstStyle;
      if (index > 0) {
        final first = section.blocks.whereType<WmlParagraph>().firstOrNull;
        if (first != null) {
          firstStyle = layout.sectionBreakStyle(
            index,
            section.breakKind,
            baseStyle: layout.paragraphStyle(
              first.properties,
              heading: first.properties.headingLevel,
            ),
          );
        }
      }
      _writeBlocks(
        body,
        section.blocks,
        layout,
        firstParagraphStyle: firstStyle,
      );
    }
    body.writeEndElement();

    final w = XmlWriter();
    w.writeStartDocument();
    w.writeStartElement('document-content', prefix: 'office');
    _namespaces(w);
    w.writeAttribute('office:version', '1.3');
    w.writeStartElement('automatic-styles', prefix: 'office');
    layout.writeContentStyles(w);
    w.writeEndElement();
    w.writeStartElement('body', prefix: 'office');
    w.writeRaw(body.toXml());
    w.writeEndElement();
    w.writeEndElement();
    return w.toXml();
  }

  static String _stylesXml(WmlDocument document, _OdtLayout layout) {
    // Master-page stories use automatic styles in styles.xml, while body
    // stories use those in content.xml. Keep the style registries separate and
    // share the package media registry so header/footer pictures cannot collide.
    final stories = _OdtLayout(document, sharedMedia: layout);
    final master = XmlWriter();
    master.writeStartElement('master-styles', prefix: 'office');
    for (var index = 0; index < document.sections.length; index++) {
      final section = document.sections[index];
      master.writeStartElement('master-page', prefix: 'style');
      master.writeAttribute('style:name', index == 0 ? 'Standard' : 'mp$index');
      master.writeAttribute('style:page-layout-name', 'pm$index');
      if (section.header.isNotEmpty) {
        master.writeStartElement('header', prefix: 'style');
        for (final paragraph in section.header) {
          _writeParagraph(master, paragraph, stories);
        }
        master.writeEndElement();
      }
      if (section.footer.isNotEmpty) {
        master.writeStartElement('footer', prefix: 'style');
        for (final paragraph in section.footer) {
          _writeParagraph(master, paragraph, stories);
        }
        master.writeEndElement();
      }
      master.writeEndElement();
    }
    master.writeEndElement();

    final w = XmlWriter();
    w.writeStartDocument();
    w.writeStartElement('document-styles', prefix: 'office');
    _namespaces(w);
    w.writeAttribute('office:version', '1.3');
    w.writeStartElement('styles', prefix: 'office');
    w.writeStartElement('default-style', prefix: 'style');
    w.writeAttribute('style:family', 'paragraph');
    w.writeStartElement('paragraph-properties', prefix: 'style');
    w.writeAttribute('fo:margin-top', '0in');
    w.writeAttribute('fo:margin-bottom', '0.08in');
    w.writeEndElement();
    w.writeStartElement('text-properties', prefix: 'style');
    w.writeAttribute('fo:font-family', 'Arial');
    w.writeAttribute('fo:font-size', '11pt');
    w.writeEndElement();
    w.writeEndElement();
    w.writeEmptyElement(
      'style',
      prefix: 'style',
      attributes: {'style:name': 'Standard', 'style:family': 'paragraph'},
    );
    for (var level = 1; level <= 9; level++) {
      w.writeStartElement('style', prefix: 'style');
      w.writeAttribute('style:name', 'Heading_20_$level');
      w.writeAttribute('style:family', 'paragraph');
      w.writeAttribute('style:parent-style-name', 'Standard');
      w.writeAttribute('style:default-outline-level', '$level');
      w.writeStartElement('text-properties', prefix: 'style');
      w.writeAttribute('fo:font-weight', 'bold');
      w.writeAttribute('fo:font-size', '${24 - level * 2}pt');
      w.writeEndElement();
      w.writeEndElement();
    }
    for (final ordered in <bool>[false, true]) {
      w.writeStartElement('list-style', prefix: 'text');
      w.writeAttribute('style:name', ordered ? 'L2' : 'L1');
      for (var level = 1; level <= 9; level++) {
        w.writeStartElement(
          ordered ? 'list-level-style-number' : 'list-level-style-bullet',
          prefix: 'text',
        );
        w.writeAttribute('text:level', '$level');
        if (ordered) {
          w.writeAttribute('loext:num-list-format', '%$level%.');
          w.writeAttribute('style:num-format', '1');
          w.writeAttribute('style:num-suffix', '.');
        } else {
          w.writeAttribute('text:bullet-char', '•');
        }
        w.writeStartElement('list-level-properties', prefix: 'style');
        w.writeAttribute(
          'text:list-level-position-and-space-mode',
          'label-alignment',
        );
        w.writeEmptyElement(
          'list-level-label-alignment',
          prefix: 'style',
          attributes: {
            'text:label-followed-by': 'listtab',
            'text:list-tab-stop-position': '${level * 0.25}in',
            'fo:margin-left': '${level * 0.25}in',
            'fo:text-indent': '-0.25in',
          },
        );
        w.writeEndElement();
        w.writeEndElement();
      }
      w.writeEndElement();
    }
    w.writeEndElement();
    w.writeStartElement('automatic-styles', prefix: 'office');
    for (var index = 0; index < document.sections.length; index++) {
      final section = document.sections[index];
      final page = section.pageSize;
      final margins = section.margins;
      w.writeStartElement('page-layout', prefix: 'style');
      w.writeAttribute('style:name', 'pm$index');
      w.writeStartElement('page-layout-properties', prefix: 'style');
      w.writeAttribute('fo:page-width', '${page.width.toStringAsFixed(2)}pt');
      w.writeAttribute('fo:page-height', '${page.height.toStringAsFixed(2)}pt');
      w.writeAttribute('fo:margin-top', '${margins.top.toStringAsFixed(2)}pt');
      w.writeAttribute(
        'fo:margin-bottom',
        '${margins.bottom.toStringAsFixed(2)}pt',
      );
      w.writeAttribute(
        'fo:margin-left',
        '${margins.left.toStringAsFixed(2)}pt',
      );
      w.writeAttribute(
        'fo:margin-right',
        '${margins.right.toStringAsFixed(2)}pt',
      );
      w.writeEndElement();
      w.writeEndElement();
    }
    stories.writeContentStyles(w);
    w.writeEndElement();
    w.writeRaw(master.toXml());
    w.writeEndElement();
    return w.toXml();
  }

  static void _namespaces(XmlWriter w) {
    w.writeNamespace(
      'office',
      'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
    );
    w.writeNamespace(
      'style',
      'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
    );
    w.writeNamespace('text', 'urn:oasis:names:tc:opendocument:xmlns:text:1.0');
    w.writeNamespace(
      'table',
      'urn:oasis:names:tc:opendocument:xmlns:table:1.0',
    );
    w.writeNamespace(
      'draw',
      'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
    );
    w.writeNamespace(
      'fo',
      'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0',
    );
    w.writeNamespace(
      'svg',
      'urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0',
    );
    w.writeNamespace('xlink', 'http://www.w3.org/1999/xlink');
    w.writeNamespace('dc', 'http://purl.org/dc/elements/1.1/');
    w.writeNamespace('meta', 'urn:oasis:names:tc:opendocument:xmlns:meta:1.0');
    w.writeNamespace(
      'loext',
      'urn:org:documentfoundation:names:experimental:office:xmlns:loext:1.0',
    );
  }

  static void _writeBlocks(
    XmlWriter w,
    List<WmlBlock> blocks,
    _OdtLayout layout, {
    String? firstParagraphStyle,
  }) {
    var first = true;
    for (var index = 0; index < blocks.length; index++) {
      final block = blocks[index];
      final override = first && block is WmlParagraph
          ? firstParagraphStyle
          : null;
      first = false;
      if (block is WmlParagraph &&
          block.properties.numId != null &&
          !block.properties.numberingSuppressed) {
        final list = <WmlParagraph>[block];
        while (index + 1 < blocks.length) {
          final next = blocks[index + 1];
          if (next is! WmlParagraph ||
              next.properties.numId != block.properties.numId ||
              next.properties.numberingSuppressed) {
            break;
          }
          list.add(next);
          index++;
        }
        _writeList(w, list, layout);
      } else {
        _writeBlock(w, block, layout, paragraphStyle: override);
      }
    }
  }

  static void _writeList(
    XmlWriter w,
    List<WmlParagraph> paragraphs,
    _OdtLayout layout,
  ) {
    final roots = <_OdtListItem>[];
    final stack = <_OdtListItem>[];
    for (final paragraph in paragraphs) {
      var level = paragraph.properties.ilvl.clamp(0, 8);
      if (level > stack.length) level = stack.length;
      while (stack.length > level) {
        stack.removeLast();
      }
      final item = _OdtListItem(paragraph);
      if (stack.isEmpty) {
        roots.add(item);
      } else {
        stack.last.children.add(item);
      }
      stack.add(item);
    }
    final ordered = paragraphs.any((paragraph) {
      final label = paragraph.properties.listLabel?.trim() ?? '';
      return label.isNotEmpty &&
          !const <String>{'•', '◦', '▪', 'o'}.contains(label);
    });
    void writeItems(List<_OdtListItem> items) {
      w.writeStartElement('list', prefix: 'text');
      w.writeAttribute('text:style-name', layout.listStyle(ordered: ordered));
      for (final item in items) {
        w.writeStartElement('list-item', prefix: 'text');
        _writeParagraph(w, item.paragraph, layout);
        if (item.children.isNotEmpty) writeItems(item.children);
        w.writeEndElement();
      }
      w.writeEndElement();
    }

    writeItems(roots);
  }

  static void _writeBlock(
    XmlWriter w,
    WmlBlock block,
    _OdtLayout layout, {
    String? paragraphStyle,
  }) {
    switch (block) {
      case WmlParagraph():
        _writeParagraph(w, block, layout, styleOverride: paragraphStyle);
      case WmlTable():
        _writeTable(w, block, layout);
      case WmlVisual():
        _writeVisual(w, block.visual, layout);
      case WmlFrame():
        _writeFrame(w, block, layout);
      case WmlEquation():
        break;
      case WmlContentControlBlock():
        _writeBlocks(w, block.blocks, layout);
      case WmlOpaqueBlock() || WmlToc():
        break;
    }
  }

  static void _writeParagraph(
    XmlWriter w,
    WmlParagraph paragraph,
    _OdtLayout layout, {
    String? styleOverride,
  }) {
    final heading = paragraph.properties.headingLevel;
    final tag = heading == null ? 'p' : 'h';
    w.writeStartElement(tag, prefix: 'text');
    if (heading != null) {
      w.writeAttribute('text:outline-level', '${heading.clamp(1, 9)}');
    }
    w.writeAttribute(
      'text:style-name',
      styleOverride ??
          layout.paragraphStyle(paragraph.properties, heading: heading),
    );
    for (final inline in paragraph.inlines) {
      _writeInline(w, inline, layout);
    }
    w.writeEndElement();
  }

  static void _writeInline(XmlWriter w, WmlInline inline, _OdtLayout layout) {
    switch (inline) {
      case WmlRun():
        final style = layout.runStyle(inline.properties);
        final href = switch (inline.hyperlink) {
          final link? =>
            link.url ??
                link.file ??
                (link.anchor == null || link.anchor!.isEmpty
                    ? null
                    : '#${link.anchor}'),
          null => null,
        };
        if (href != null && href.isNotEmpty) {
          w.writeStartElement('a', prefix: 'text');
          w.writeAttribute('xlink:href', href);
        }
        if (inline.noteRefId case final noteId?) {
          final note = layout.note(noteId, endnote: inline.noteRefEndnote);
          if (note != null) {
            final noteNumber = layout.noteNumber(
              noteId,
              endnote: inline.noteRefEndnote,
            );
            w.writeStartElement('note', prefix: 'text');
            w.writeAttribute(
              'text:note-class',
              inline.noteRefEndnote ? 'endnote' : 'footnote',
            );
            w.writeAttribute(
              'text:id',
              '${inline.noteRefEndnote ? 'end' : 'ftn'}$noteNumber',
            );
            w.writeStartElement('note-citation', prefix: 'text');
            w.writeText('$noteNumber');
            w.writeEndElement();
            w.writeStartElement('note-body', prefix: 'text');
            _writeBlocks(w, note.blocks, layout);
            w.writeEndElement();
            w.writeEndElement();
          }
        } else if (inline.text.isNotEmpty) {
          w.writeStartElement('span', prefix: 'text');
          w.writeAttribute('text:style-name', style);
          writeOdfText(w, inline.text);
          w.writeEndElement();
        }
        for (final commentId in inline.commentIds) {
          final comment = layout.comment(commentId);
          if (comment == null || !layout.markCommentWritten(commentId)) {
            continue;
          }
          w.writeStartElement('annotation', prefix: 'office');
          w.writeAttribute('office:display', 'true');
          if (comment.author.isNotEmpty) {
            w.writeStartElement('creator', prefix: 'dc');
            w.writeText(comment.author);
            w.writeEndElement();
          }
          if (comment.dateIso.isNotEmpty) {
            w.writeStartElement('date', prefix: 'dc');
            w.writeText(comment.dateIso);
            w.writeEndElement();
          }
          _writeBlocks(w, comment.paragraphs, layout);
          w.writeEndElement();
        }
        if (inline.inlineVisual case final visual?) {
          _writeVisual(w, visual.visual, layout, inline: true);
        }
        if (href != null && href.isNotEmpty) w.writeEndElement();
      case WmlBreak():
        w.writeEmptyElement(
          inline.type == WmlBreakType.textWrapping
              ? 'line-break'
              : 'soft-page-break',
          prefix: 'text',
        );
      case WmlFieldBoundary():
        // Instructions are hidden field metadata, not document text. The
        // surrounding result runs remain in the inline sequence, including
        // citations and bibliographies that span several paragraphs.
        break;
      case WmlBookmarkBoundary():
        final name = inline.name;
        if (name != null && name.isNotEmpty) {
          w.writeEmptyElement(
            inline.isStart ? 'bookmark-start' : 'bookmark-end',
            prefix: 'text',
            attributes: {'text:name': name},
          );
        }
      case WmlContentControlBoundary() || WmlNoteMarker():
        break;
      case WmlObject():
      case WmlOpaqueInline():
        break;
    }
  }

  static void _writeTable(XmlWriter w, WmlTable table, _OdtLayout layout) {
    final cells = _OdtTableCells(table);
    w.writeStartElement('table', prefix: 'table');
    w.writeAttribute('table:name', 'Table${layout.tableCount++}');
    w.writeAttribute('table:style-name', layout.tableStyle());
    for (final width in table.grid) {
      w.writeStartElement('table-column', prefix: 'table');
      w.writeAttribute('table:style-name', layout.columnStyle(width));
      w.writeEndElement();
    }
    final inferredColumns = cells.columnCount - BigInt.from(table.grid.length);
    if (inferredColumns > BigInt.zero) {
      w.writeEmptyElement(
        'table-column',
        prefix: 'table',
        attributes: inferredColumns == BigInt.one
            ? null
            : {'table:number-columns-repeated': '$inferredColumns'},
      );
    }
    if (table.rows.isEmpty) {
      w.writeStartElement('table-row', prefix: 'table');
      _writeOmittedCells(w, cells.columnCount);
      w.writeEndElement();
    }
    for (var rowIndex = 0; rowIndex < table.rows.length; rowIndex++) {
      final row = table.rows[rowIndex];
      w.writeStartElement('table-row', prefix: 'table');
      _writeOmittedCells(
        w,
        BigInt.from(row.gridBefore > 0 ? row.gridBefore : 0),
      );
      for (var index = 0; index < row.cells.length; index++) {
        final cell = row.cells[index];
        final placement = cells.rows[rowIndex][index];
        w.writeStartElement(
          placement.covered ? 'covered-table-cell' : 'table-cell',
          prefix: 'table',
        );
        if (!placement.covered) {
          if (placement.columns > 1) {
            w.writeAttribute(
              'table:number-columns-spanned',
              '${placement.columns}',
            );
          }
          if (placement.rows > 1) {
            w.writeAttribute('table:number-rows-spanned', '${placement.rows}');
          }
        }
        if (cell.fillColor case final fill?) {
          w.writeAttribute('table:style-name', layout.cellStyle(fill));
        }
        if (cell.blocks.isEmpty) {
          _writePlainParagraph(w, '');
        } else {
          _writeBlocks(w, cell.blocks, layout);
        }
        w.writeEndElement();
        _writeCoveredCells(w, placement.columns - 1);
      }
      _writeOmittedCells(
        w,
        BigInt.from(row.gridAfter > 0 ? row.gridAfter : 0) +
            cells.columnCount -
            cells.rowWidths[rowIndex],
      );
      w.writeEndElement();
    }
    w.writeEndElement();
  }

  static void _writeCoveredCells(XmlWriter w, int count) {
    if (count <= 0) return;
    w.writeEmptyElement(
      'covered-table-cell',
      prefix: 'table',
      attributes: count == 1
          ? null
          : {'table:number-columns-repeated': '$count'},
    );
  }

  static void _writeOmittedCells(XmlWriter w, BigInt count) {
    if (count <= BigInt.zero) return;
    w.writeStartElement('table-cell', prefix: 'table');
    if (count > BigInt.one) {
      w.writeAttribute('table:number-columns-repeated', '$count');
    }
    _writePlainParagraph(w, '');
    w.writeEndElement();
  }

  static void _writeFrame(XmlWriter w, WmlFrame frame, _OdtLayout layout) {
    w.writeStartElement('frame', prefix: 'draw');
    w.writeAttribute('text:anchor-type', 'page');
    w.writeAttribute('svg:x', '${frame.x.toStringAsFixed(2)}pt');
    w.writeAttribute('svg:y', '${frame.y.toStringAsFixed(2)}pt');
    w.writeAttribute('svg:width', '${frame.width.toStringAsFixed(2)}pt');
    w.writeAttribute('svg:height', '${frame.height.toStringAsFixed(2)}pt');
    if (frame.fillColor case final fill?) {
      w.writeAttribute('draw:fill-color', '#${fill.toLowerCase()}');
    }
    w.writeStartElement('text-box', prefix: 'draw');
    for (final block in frame.blocks) {
      _writeBlock(w, block, layout);
    }
    w.writeEndElement();
    w.writeEndElement();
  }

  static void _writeVisual(
    XmlWriter w,
    OfficeVisual visual,
    _OdtLayout layout, {
    bool inline = false,
  }) {
    final bytes = visual.imageBytes;
    if (bytes != null && bytes.isNotEmpty) {
      final path = layout.addMedia(bytes);
      w.writeStartElement('frame', prefix: 'draw');
      w.writeAttribute('text:anchor-type', 'as-char');
      w.writeAttribute('draw:name', visual.title);
      w.writeAttribute('svg:width', '${visual.width.toStringAsFixed(2)}pt');
      w.writeAttribute('svg:height', '${visual.height.toStringAsFixed(2)}pt');
      w.writeEmptyElement(
        'image',
        prefix: 'draw',
        attributes: {'xlink:href': path, 'xlink:type': 'simple'},
      );
      w.writeEndElement();
    } else if (inline) {
      writeOdfText(w, visual.title);
    } else {
      _writePlainParagraph(w, visual.title);
    }
  }

  static void _writePlainParagraph(XmlWriter w, String text) {
    w.writeStartElement('p', prefix: 'text');
    if (text.isNotEmpty) writeOdfText(w, text);
    w.writeEndElement();
  }

  static String _manifestXml(List<String> media) {
    final w = XmlWriter();
    w.writeStartDocument();
    w.writeStartElement(
      'manifest',
      prefix: 'manifest',
      namespaceUri: 'urn:oasis:names:tc:opendocument:xmlns:manifest:1.0',
    );
    w.writeAttribute('manifest:version', '1.3');
    void entry(String path, String type) {
      w.writeEmptyElement(
        'file-entry',
        prefix: 'manifest',
        attributes: {'manifest:full-path': path, 'manifest:media-type': type},
      );
    }

    entry('/', _mime);
    entry('content.xml', 'text/xml');
    entry('styles.xml', 'text/xml');
    entry('meta.xml', 'text/xml');
    for (final path in media) {
      entry(path, _mediaType(path));
    }
    w.writeEndElement();
    return w.toXml();
  }

  static String _metaXml(WmlDocument document) {
    final w = XmlWriter();
    w.writeStartDocument();
    w.writeStartElement('document-meta', prefix: 'office');
    _namespaces(w);
    w.writeAttribute('office:version', '1.3');
    w.writeStartElement('meta', prefix: 'office');
    void value(String tag, String prefix, String text) {
      if (text.isEmpty) return;
      w.writeStartElement(tag, prefix: prefix);
      w.writeText(text);
      w.writeEndElement();
    }

    value('title', 'dc', document.properties.title);
    value('subject', 'dc', document.properties.subject);
    value('creator', 'dc', document.properties.creator);
    value('description', 'dc', document.properties.description);
    value('keyword', 'meta', document.properties.keywords);
    value('initial-creator', 'meta', document.properties.creator);
    value('creation-date', 'meta', document.properties.createdIso);
    value('date', 'dc', document.properties.modifiedIso);
    value('generator', 'meta', 'Quds Office');
    w.writeEndElement();
    w.writeEndElement();
    return w.toXml();
  }

  static String _mediaType(String path) => path.endsWith('.png')
      ? 'image/png'
      : path.endsWith('.jpg')
      ? 'image/jpeg'
      : 'application/octet-stream';
}

/// Infers vertical ownership only for exactly aligned, consecutive cells.
///
/// Like WordTable's logical addressing, a continuation must have the same
/// logical start and column span as its predecessor. An orphan or mismatched
/// continuation stays visible as an ordinary cell, rather than hiding its
/// content under an unrelated anchor. Invalid row metadata breaks all chains
/// through that row. Known row omissions retain their logical positions.
///
/// Storage and iteration are proportional to physical cells, not authored
/// column spans. BigInt offsets prevent cumulative span overflow on VM and web.
class _OdtTableCells {
  _OdtTableCells(WmlTable table)
    : columnCount = BigInt.from(table.grid.isEmpty ? 1 : table.grid.length) {
    var previous = <(BigInt, int), _OdtTableCell>{};
    for (final row in table.rows) {
      final placements = <_OdtTableCell>[];
      rows.add(placements);
      final valid =
          row.gridBefore >= 0 &&
          row.gridAfter >= 0 &&
          row.cells.every((cell) => cell.gridSpan > 0);
      final current = <(BigInt, int), _OdtTableCell>{};
      var column = BigInt.from(row.gridBefore > 0 ? row.gridBefore : 0);
      for (final cell in row.cells) {
        final span = cell.gridSpan > 0 ? cell.gridSpan : 1;
        final placement = _OdtTableCell(span);
        placements.add(placement);
        final key = (column, span);
        if (valid) {
          if (cell.vMerge == WmlVMerge.restart) {
            current[key] = placement;
          } else if (cell.vMerge == WmlVMerge.cont) {
            final anchor = previous[key];
            if (anchor != null) {
              placement.covered = true;
              anchor.rows++;
              current[key] = anchor;
            }
          }
        }
        column += BigInt.from(span);
      }
      column += BigInt.from(row.gridAfter > 0 ? row.gridAfter : 0);
      rowWidths.add(column);
      if (column > columnCount) columnCount = column;
      previous = current;
    }
  }

  final rows = <List<_OdtTableCell>>[];
  final rowWidths = <BigInt>[];
  BigInt columnCount;
}

class _OdtTableCell {
  _OdtTableCell(this.columns);

  final int columns;
  int rows = 1;
  bool covered = false;
}

class _OdtLayout {
  _OdtLayout(this.document, {_OdtLayout? sharedMedia})
    : media = sharedMedia?.media ?? <String>[],
      _mediaBytes = sharedMedia?._mediaBytes ?? <String, Uint8List>{};

  final WmlDocument document;
  final List<String> media;
  final Map<String, String> _runStyles = <String, String>{};
  final Map<String, String> _paragraphStyles = <String, String>{};
  final Map<String, String> _columnStyles = <String, String>{};
  final Map<String, String> _cellStyles = <String, String>{};
  final List<String> _styleBuffers = <String>[];
  int tableCount = 0;

  String addMedia(Uint8List bytes) {
    final ext = _extension(bytes);
    final path = 'Pictures/image${media.length + 1}.$ext';
    media.add(path);
    _mediaBytes[path] = bytes;
    return path;
  }

  final Map<String, Uint8List> _mediaBytes;

  Map<String, Uint8List> get mediaBytes => _mediaBytes;

  String runStyle(WmlRunProps props) {
    final key =
        '${props.bold}|${props.italic}|${props.underline.index}|${props.strike}|${props.color}|${props.fontSizeHalfPoints}|${props.asciiFont}|${props.highlight}|${props.vertAlign.index}';
    return _runStyles.putIfAbsent(key, () {
      final name = 'T${_runStyles.length + 1}';
      final buffer = StringBuffer(
        '<style:style style:name="$name" style:family="text">'
        '<style:text-properties',
      );
      if (props.bold) buffer.write(' fo:font-weight="bold"');
      if (props.italic) buffer.write(' fo:font-style="italic"');
      if (props.underline != WmlUnderline.none) {
        buffer.write(' style:text-underline-style="solid"');
        buffer.write(' style:text-underline-type="single"');
      }
      if (props.strike) buffer.write(' style:text-line-through-style="solid"');
      if (props.color.isNotEmpty) {
        buffer.write(' fo:color="#${props.color.toLowerCase()}"');
      }
      buffer.write(
        ' fo:font-size="${props.fontSizePoints.toStringAsFixed(1)}pt"',
      );
      if (props.asciiFont.isNotEmpty) {
        buffer.write(' fo:font-family="${_escape(props.asciiFont)}"');
      }
      if (props.highlight case final highlight?) {
        buffer.write(' fo:background-color="#${highlight.toLowerCase()}"');
      }
      if (props.vertAlign == WmlVertAlign.superscript) {
        buffer.write(' style:text-position="super 58%"');
      } else if (props.vertAlign == WmlVertAlign.subscript) {
        buffer.write(' style:text-position="sub 58%"');
      }
      buffer.write('/></style:style>');
      _styleBuffers.add(buffer.toString());
      return name;
    });
  }

  String paragraphStyle(WmlParagraphProps props, {int? heading}) {
    final key =
        '${heading == null ? 'body' : heading.clamp(1, 9)}|${props.justification.index}|${props.rightToLeft}|${props.lineSpacingRule.index}|${props.lineSpacing}|${props.spacingBefore}|${props.spacingAfter}|${props.indent.left}|${props.indent.right}|${props.indent.firstLine}|${props.indent.hanging}|${props.pageBreakBefore}';
    return _paragraphStyles.putIfAbsent(key, () {
      final name = 'P${_paragraphStyles.length + 1}';
      final buffer = StringBuffer(
        '<style:style style:name="$name" style:family="paragraph" '
        'style:parent-style-name="${heading == null ? 'Standard' : 'Heading_20_${heading.clamp(1, 9)}'}">'
        '<style:paragraph-properties',
      );
      // The model's left/right alignment is physical, independently of the
      // paragraph's BiDi base direction. ODF start/end would reverse it in RTL.
      final align = switch (props.justification) {
        WmlJustification.center => 'center',
        WmlJustification.right => 'right',
        WmlJustification.justify || WmlJustification.distributed => 'justify',
        WmlJustification.left => 'left',
      };
      buffer.write(' fo:text-align="$align"');
      if (props.rightToLeft case final direction?) {
        buffer.write(' style:writing-mode="${direction ? 'rl-tb' : 'lr-tb'}"');
        buffer.write(' style:writing-mode-automatic="false"');
      }
      // Write zero margins too: omission inherits the generated default style,
      // whose bottom margin is nonzero. Headings retain their resolved values.
      if (_paragraphDecimal(props.spacingBefore) case final before?) {
        buffer.write(' fo:margin-top="${before}pt"');
      }
      if (_paragraphDecimal(props.spacingAfter) case final after?) {
        buffer.write(' fo:margin-bottom="${after}pt"');
      }
      if (props.lineSpacing > 0) {
        switch (props.lineSpacingRule) {
          case WmlLineSpacingRule.auto:
            if (_paragraphDecimal(props.lineSpacing * 100)
                case final percent?) {
              buffer.write(' fo:line-height="$percent%"');
            }
          case WmlLineSpacingRule.exact:
            if (_paragraphDecimal(props.lineSpacing) case final points?) {
              buffer.write(' fo:line-height="${points}pt"');
            }
          case WmlLineSpacingRule.atLeast:
            if (_paragraphDecimal(props.lineSpacing) case final points?) {
              buffer.write(' style:line-height-at-least="${points}pt"');
            }
        }
      }
      if (props.pageBreakBefore) buffer.write(' fo:break-before="page"');
      if (props.indent.left != 0) {
        if (_paragraphDecimal(props.indent.left) case final left?) {
          buffer.write(' fo:margin-left="${left}pt"');
        }
      }
      if (props.indent.right != 0) {
        if (_paragraphDecimal(props.indent.right) case final right?) {
          buffer.write(' fo:margin-right="${right}pt"');
        }
      }
      final firstLine = props.indent.hanging != 0
          ? -props.indent.hanging
          : props.indent.firstLine;
      if (firstLine != 0) {
        if (_paragraphDecimal(firstLine) case final points?) {
          buffer.write(' fo:text-indent="${points}pt"');
        }
      }
      buffer.write('/></style:style>');
      _styleBuffers.add(buffer.toString());
      return name;
    });
  }

  static String? _paragraphDecimal(double value) {
    if (!value.isFinite) return null;
    final decimal = value.toStringAsFixed(2);
    // ODF lengths and percentages do not accept exponent notation, which
    // toStringAsFixed uses for magnitudes of at least 10^21.
    return decimal.contains('e') ? null : decimal;
  }

  String tableStyle() {
    final name = 'Tab${tableCount + 1}';
    _styleBuffers.add(
      '<style:style style:name="$name" style:family="table">'
      '<style:table-properties style:rel-width="100%" table:align="margins"/></style:style>',
    );
    return name;
  }

  String columnStyle(double width) {
    final key = width.toStringAsFixed(2);
    return _columnStyles.putIfAbsent(key, () {
      final name = 'Co${_columnStyles.length + 1}';
      _styleBuffers.add(
        '<style:style style:name="$name" style:family="table-column">'
        '<style:table-column-properties style:column-width="${width.toStringAsFixed(2)}pt"/>'
        '</style:style>',
      );
      return name;
    });
  }

  final Set<int> _writtenComments = <int>{};

  WmlComment? comment(int id) {
    for (final comment in document.comments) {
      if (comment.id == id) return comment;
    }
    return null;
  }

  bool markCommentWritten(int id) => _writtenComments.add(id);

  final Map<String, int> _noteNumbers = <String, int>{};

  WmlNote? note(int id, {required bool endnote}) {
    final notes = endnote ? document.endnotes : document.footnotes;
    for (final note in notes) {
      if (note.id == id) return note;
    }
    return null;
  }

  int noteNumber(int id, {required bool endnote}) {
    final key = '${endnote ? 'e' : 'f'}:$id';
    return _noteNumbers.putIfAbsent(key, () => _noteNumbers.length + 1);
  }

  String sectionBreakStyle(
    int index,
    WmlSectionBreakKind kind, {
    required String baseStyle,
  }) {
    final name = 'SB$index';
    if (_sectionBreakStyles.add(name)) {
      final buffer = StringBuffer(
        '<style:style style:name="$name" style:family="paragraph" '
        'style:parent-style-name="$baseStyle" '
        'style:master-page-name="mp$index">'
        '<style:paragraph-properties',
      );
      if (kind != WmlSectionBreakKind.continuous) {
        buffer.write(' fo:break-before="page"');
      }
      buffer.write(' style:page-number="auto"/></style:style>');
      _styleBuffers.add(buffer.toString());
    }
    return name;
  }

  final Set<String> _sectionBreakStyles = <String>{};

  String listStyle({required bool ordered}) => ordered ? 'L2' : 'L1';

  String cellStyle(String fill) {
    return _cellStyles.putIfAbsent(fill, () {
      final name = 'Ce${_cellStyles.length + 1}';
      _styleBuffers.add(
        '<style:style style:name="$name" style:family="table-cell">'
        '<style:table-cell-properties fo:background-color="#${fill.toLowerCase()}"/>'
        '</style:style>',
      );
      return name;
    });
  }

  void writeContentStyles(XmlWriter w) {
    for (final buffer in _styleBuffers) {
      w.writeRaw(buffer);
    }
  }

  static String _extension(Uint8List bytes) {
    if (bytes.length >= 4 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'png';
    }
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
      return 'jpg';
    }
    return 'bin';
  }

  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

class _OdtListItem {
  _OdtListItem(this.paragraph);

  final WmlParagraph paragraph;
  final List<_OdtListItem> children = <_OdtListItem>[];
}
