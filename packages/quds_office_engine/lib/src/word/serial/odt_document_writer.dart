import 'dart:convert';
import 'dart:typed_data';

import '../../opc/zip/zip_writer.dart';
import '../../visual/office_visual.dart';
import '../../xml/xml_writer.dart';
import '../model/wml_document.dart';
import '../properties/wml_properties.dart';

/// Bounded new-document ODT writer for the shared Word model.
///
/// This is an export path. It emits the modeled text, paragraph/run formatting,
/// tables, pictures, frames, page geometry and basic headers/footers. It does
/// not claim to preserve arbitrary imported ODF XML or every Word feature.
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
    for (final section in document.sections) {
      _writeBlocks(body, section.blocks, layout);
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
    w.writeEndElement();
    w.writeStartElement('automatic-styles', prefix: 'office');
    final section = document.sections.firstOrNull;
    final page = section?.pageSize ?? const WmlPageSize();
    final margins = section?.margins ?? const WmlPageMargins();
    w.writeStartElement('page-layout', prefix: 'style');
    w.writeAttribute('style:name', 'pm1');
    w.writeStartElement('page-layout-properties', prefix: 'style');
    w.writeAttribute('fo:page-width', '${page.width.toStringAsFixed(2)}pt');
    w.writeAttribute('fo:page-height', '${page.height.toStringAsFixed(2)}pt');
    w.writeAttribute('fo:margin-top', '${margins.top.toStringAsFixed(2)}pt');
    w.writeAttribute(
      'fo:margin-bottom',
      '${margins.bottom.toStringAsFixed(2)}pt',
    );
    w.writeAttribute('fo:margin-left', '${margins.left.toStringAsFixed(2)}pt');
    w.writeAttribute(
      'fo:margin-right',
      '${margins.right.toStringAsFixed(2)}pt',
    );
    w.writeEndElement();
    w.writeEndElement();
    w.writeEndElement();
    w.writeStartElement('master-styles', prefix: 'office');
    w.writeStartElement('master-page', prefix: 'style');
    w.writeAttribute('style:name', 'Standard');
    w.writeAttribute('style:page-layout-name', 'pm1');
    final header = section?.header ?? const <WmlParagraph>[];
    final footer = section?.footer ?? const <WmlParagraph>[];
    if (header.isNotEmpty) {
      w.writeStartElement('header', prefix: 'style');
      for (final paragraph in header) {
        _writePlainParagraph(w, paragraph.text);
      }
      w.writeEndElement();
    }
    if (footer.isNotEmpty) {
      w.writeStartElement('footer', prefix: 'style');
      for (final paragraph in footer) {
        _writePlainParagraph(w, paragraph.text);
      }
      w.writeEndElement();
    }
    w.writeEndElement();
    w.writeEndElement();
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
  }

  static void _writeBlocks(
    XmlWriter w,
    List<WmlBlock> blocks,
    _OdtLayout layout,
  ) {
    for (final block in blocks) {
      _writeBlock(w, block, layout);
    }
  }

  static void _writeBlock(XmlWriter w, WmlBlock block, _OdtLayout layout) {
    switch (block) {
      case WmlParagraph():
        _writeParagraph(w, block, layout);
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
    _OdtLayout layout,
  ) {
    final heading = paragraph.properties.headingLevel;
    final tag = heading == null ? 'p' : 'h';
    w.writeStartElement(tag, prefix: 'text');
    if (heading != null) {
      w.writeAttribute('text:outline-level', '${heading.clamp(1, 9)}');
    }
    w.writeAttribute(
      'text:style-name',
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
        final href = inline.hyperlink?.url;
        if (href != null && href.isNotEmpty) {
          w.writeStartElement('a', prefix: 'text');
          w.writeAttribute('xlink:href', href);
        }
        if (inline.text.isNotEmpty) {
          w.writeStartElement('span', prefix: 'text');
          w.writeAttribute('text:style-name', style);
          w.writeText(inline.text);
          w.writeEndElement();
        }
        if (inline.inlineVisual case final visual?) {
          _writeVisual(w, visual.visual, layout);
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
        if (inline.text.isNotEmpty) w.writeText(inline.text);
      case WmlContentControlBoundary() ||
          WmlNoteMarker() ||
          WmlBookmarkBoundary():
        break;
      case WmlObject():
      case WmlOpaqueInline():
        break;
    }
  }

  static void _writeTable(XmlWriter w, WmlTable table, _OdtLayout layout) {
    w.writeStartElement('table', prefix: 'table');
    w.writeAttribute('table:name', 'Table${layout.tableCount++}');
    w.writeAttribute('table:style-name', layout.tableStyle());
    for (final width in table.grid) {
      w.writeStartElement('table-column', prefix: 'table');
      w.writeAttribute('table:style-name', layout.columnStyle(width));
      w.writeEndElement();
    }
    for (final row in table.rows) {
      w.writeStartElement('table-row', prefix: 'table');
      for (final cell in row.cells) {
        w.writeStartElement('table-cell', prefix: 'table');
        if (cell.gridSpan > 1) {
          w.writeAttribute('table:number-columns-spanned', '${cell.gridSpan}');
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
        for (var span = 1; span < cell.gridSpan; span++) {
          w.writeEmptyElement('covered-table-cell', prefix: 'table');
        }
      }
      w.writeEndElement();
    }
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
    _OdtLayout layout,
  ) {
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
        attributes: {'xlink:href': path},
      );
      w.writeEndElement();
    } else {
      _writePlainParagraph(w, visual.title);
    }
  }

  static void _writePlainParagraph(XmlWriter w, String text) {
    w.writeStartElement('p', prefix: 'text');
    if (text.isNotEmpty) w.writeText(text);
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
    if (document.properties.title.isNotEmpty) {
      w.writeStartElement('title', prefix: 'dc');
      w.writeText(document.properties.title);
      w.writeEndElement();
    }
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

class _OdtLayout {
  _OdtLayout(this.document);

  final WmlDocument document;
  final List<String> media = <String>[];
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

  final Map<String, Uint8List> _mediaBytes = <String, Uint8List>{};

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
        '${heading ?? 0}|${props.justification.index}|${props.lineSpacing}|${props.spacingBefore}|${props.spacingAfter}|${props.indent.left}|${props.indent.right}|${props.indent.firstLine}|${props.indent.hanging}|${props.pageBreakBefore}';
    return _paragraphStyles.putIfAbsent(key, () {
      final name = 'P${_paragraphStyles.length + 1}';
      final buffer = StringBuffer(
        '<style:style style:name="$name" style:family="paragraph" '
        'style:parent-style-name="${heading == null ? 'Standard' : 'Heading_20_${heading.clamp(1, 9)}'}">'
        '<style:paragraph-properties',
      );
      if (heading == null) {
        final align = switch (props.justification) {
          WmlJustification.center => 'center',
          WmlJustification.right => 'end',
          WmlJustification.justify || WmlJustification.distributed => 'justify',
          WmlJustification.left => 'start',
        };
        buffer.write(' fo:text-align="$align"');
        if (props.spacingBefore != 0) {
          buffer.write(
            ' fo:margin-top="${props.spacingBefore.toStringAsFixed(2)}pt"',
          );
        }
        if (props.spacingAfter != 0) {
          buffer.write(
            ' fo:margin-bottom="${props.spacingAfter.toStringAsFixed(2)}pt"',
          );
        }
        if (props.lineSpacing > 0) {
          buffer.write(
            ' fo:line-height="${(props.lineSpacing * 100).round()}%"',
          );
        }
      }
      if (props.pageBreakBefore) buffer.write(' fo:break-before="page"');
      if (props.indent.left != 0) {
        buffer.write(
          ' fo:margin-left="${props.indent.left.toStringAsFixed(2)}pt"',
        );
      }
      if (props.indent.right != 0) {
        buffer.write(
          ' fo:margin-right="${props.indent.right.toStringAsFixed(2)}pt"',
        );
      }
      if (props.indent.firstLine != 0) {
        buffer.write(
          ' fo:text-indent="${props.indent.firstLine.toStringAsFixed(2)}pt"',
        );
      }
      if (props.indent.hanging != 0) {
        buffer.write(
          ' fo:text-indent="-${props.indent.hanging.toStringAsFixed(2)}pt"',
        );
      }
      buffer.write('/></style:style>');
      _styleBuffers.add(buffer.toString());
      return name;
    });
  }

  String tableStyle() {
    final name = 'Tab${tableCount + 1}';
    _styleBuffers.add(
      '<style:style style:name="$name" style:family="table">'
      '<style:table-properties style:width="100%" table:align="margins"/></style:style>',
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
