import 'dart:convert';
import 'dart:typed_data';

import '../../odf/odf_text.dart';
import '../../opc/zip/zip_writer.dart';
import '../../xml/xml_writer.dart';
import '../model/pml_presentation.dart';

/// Bounded new-document ODP writer for the shared slide model.
///
/// Emits slides, positioned text shapes, pictures, tables, fills/strokes and
/// speaker notes. Transitions, animations, master inheritance and arbitrary
/// imported ODF XML are not reconstructed.
abstract final class OdpPresentationWriter {
  /// Serializes [presentation] as a new ODP package.
  static Uint8List writeBytes(PmlPresentation presentation) {
    final layout = _OdpLayout(presentation);
    final body = XmlWriter();
    body.writeStartElement('presentation', prefix: 'office');
    for (var index = 0; index < presentation.slides.length; index++) {
      _writeSlide(body, presentation.slides[index], index, layout);
    }
    body.writeEndElement();

    final content = XmlWriter();
    content.writeStartDocument();
    content.writeStartElement('document-content', prefix: 'office');
    _namespaces(content);
    content.writeAttribute('office:version', '1.3');
    content.writeStartElement('automatic-styles', prefix: 'office');
    layout.writeStyles(content);
    content.writeEndElement();
    content.writeStartElement('body', prefix: 'office');
    content.writeRaw(body.toXml());
    content.writeEndElement();
    content.writeEndElement();

    final styles = _stylesXml(presentation);
    final manifest = _manifestXml(layout.media);
    final meta = _metaXml(presentation);
    final zip = ZipWriter();
    zip.addFile(
      'mimetype',
      utf8.encode('application/vnd.oasis.opendocument.presentation'),
      store: true,
    );
    zip.addFile('META-INF/manifest.xml', utf8.encode(manifest));
    zip.addFile('content.xml', utf8.encode(content.toXml()));
    zip.addFile('styles.xml', utf8.encode(styles));
    zip.addFile('meta.xml', utf8.encode(meta));
    for (final entry in layout.mediaBytes.entries) {
      zip.addFile(entry.key, entry.value);
    }
    return zip.close();
  }

  static void _writeSlide(
    XmlWriter w,
    PmlSlide slide,
    int index,
    _OdpLayout layout,
  ) {
    final pageStyle = layout.pageStyle();
    w.writeStartElement('page', prefix: 'draw');
    w.writeAttribute('draw:name', 'page${index + 1}');
    w.writeAttribute('draw:style-name', pageStyle);
    w.writeAttribute('draw:master-page-name', 'mp1');
    for (final shape in slide.shapes) {
      _writeShape(w, shape, layout);
    }
    if (slide.notes.isNotEmpty) {
      w.writeStartElement('notes', prefix: 'presentation');
      w.writeStartElement('frame', prefix: 'draw');
      w.writeAttribute('draw:layer', 'layout');
      w.writeAttribute('svg:x', '1in');
      w.writeAttribute('svg:y', '1in');
      w.writeAttribute('svg:width', '8in');
      w.writeAttribute('svg:height', '2in');
      w.writeStartElement('text-box', prefix: 'draw');
      _writeParagraphs(w, slide.notes, layout, null);
      w.writeEndElement();
      w.writeEndElement();
      w.writeEndElement();
    }
    w.writeEndElement();
  }

  static void _writeShape(XmlWriter w, PmlShape shape, _OdpLayout layout) {
    final transform = shape.transform;
    w.writeStartElement('frame', prefix: 'draw');
    w.writeAttribute('draw:name', shape.name);
    w.writeAttribute('draw:layer', 'layout');
    w.writeAttribute('draw:style-name', layout.graphicStyle(shape));
    w.writeAttribute('svg:x', '${transform.xPoints.toStringAsFixed(2)}pt');
    w.writeAttribute('svg:y', '${transform.yPoints.toStringAsFixed(2)}pt');
    w.writeAttribute(
      'svg:width',
      '${transform.widthPoints.toStringAsFixed(2)}pt',
    );
    w.writeAttribute(
      'svg:height',
      '${transform.heightPoints.toStringAsFixed(2)}pt',
    );
    if (transform.rot != 0) {
      w.writeAttribute(
        'draw:transform',
        'rotate (${transform.rotationDegrees.toStringAsFixed(2)})',
      );
    }
    final image = shape.visual?.imageBytes;
    if (image != null && image.isNotEmpty) {
      final path = layout.addMedia(image);
      w.writeEmptyElement(
        'image',
        prefix: 'draw',
        attributes: {'xlink:href': path},
      );
    } else if (shape.table case final table?) {
      _writeTable(w, table, layout);
    } else {
      w.writeStartElement('text-box', prefix: 'draw');
      _writeParagraphs(w, shape.text, layout, shape);
      w.writeEndElement();
    }
    w.writeEndElement();
  }

  static void _writeTable(XmlWriter w, PmlTable table, _OdpLayout layout) {
    w.writeStartElement('table', prefix: 'table');
    w.writeAttribute('table:name', 'Table${layout.tableCount++}');
    for (final row in table.rows) {
      w.writeStartElement('table-row', prefix: 'table');
      for (final cell in row) {
        w.writeStartElement('table-cell', prefix: 'table');
        if (cell.fillColor.isNotEmpty) {
          w.writeAttribute(
            'table:style-name',
            layout.cellStyle(cell.fillColor),
          );
        }
        _writeParagraphs(w, cell.text, layout, null);
        w.writeEndElement();
      }
      w.writeEndElement();
    }
    w.writeEndElement();
  }

  static void _writeParagraphs(
    XmlWriter w,
    String text,
    _OdpLayout layout,
    PmlShape? shape,
  ) {
    final lines = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    if (lines.isEmpty) {
      w.writeEmptyElement('p', prefix: 'text');
      return;
    }
    final paragraphStyle = layout.paragraphStyle(shape);
    final textStyle = layout.textStyle(shape);
    for (final line in lines) {
      w.writeStartElement('p', prefix: 'text');
      w.writeAttribute('text:style-name', paragraphStyle);
      if (line.isNotEmpty) {
        w.writeStartElement('span', prefix: 'text');
        w.writeAttribute('text:style-name', textStyle);
        writeOdfText(w, line);
        w.writeEndElement();
      }
      w.writeEndElement();
    }
  }

  static String _stylesXml(PmlPresentation presentation) {
    final w = XmlWriter();
    w.writeStartDocument();
    w.writeStartElement('document-styles', prefix: 'office');
    _namespaces(w);
    w.writeAttribute('office:version', '1.3');
    w.writeStartElement('styles', prefix: 'office');
    w.writeStartElement('default-style', prefix: 'style');
    w.writeAttribute('style:family', 'drawing-page');
    w.writeEndElement();
    w.writeEndElement();
    w.writeStartElement('automatic-styles', prefix: 'office');
    w.writeStartElement('page-layout', prefix: 'style');
    w.writeAttribute('style:name', 'pm1');
    w.writeStartElement('page-layout-properties', prefix: 'style');
    w.writeAttribute(
      'fo:page-width',
      '${(presentation.slideWidth / 12700).toStringAsFixed(2)}pt',
    );
    w.writeAttribute(
      'fo:page-height',
      '${(presentation.slideHeight / 12700).toStringAsFixed(2)}pt',
    );
    w.writeAttribute(
      'style:print-orientation',
      presentation.slideWidth > presentation.slideHeight
          ? 'landscape'
          : 'portrait',
    );
    w.writeEndElement();
    w.writeEndElement();
    w.writeEndElement();
    w.writeStartElement('master-styles', prefix: 'office');
    w.writeStartElement('master-page', prefix: 'style');
    w.writeAttribute('style:name', 'mp1');
    w.writeAttribute('style:page-layout-name', 'pm1');
    w.writeEndElement();
    w.writeEndElement();
    w.writeEndElement();
    return w.toXml();
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

    entry('/', 'application/vnd.oasis.opendocument.presentation');
    entry('content.xml', 'text/xml');
    entry('styles.xml', 'text/xml');
    entry('meta.xml', 'text/xml');
    for (final path in media) {
      entry(path, _mediaType(path));
    }
    w.writeEndElement();
    return w.toXml();
  }

  static String _metaXml(PmlPresentation presentation) {
    final w = XmlWriter();
    w.writeStartDocument();
    w.writeStartElement('document-meta', prefix: 'office');
    _namespaces(w);
    w.writeAttribute('office:version', '1.3');
    w.writeStartElement('meta', prefix: 'office');
    if (presentation.properties.title.isNotEmpty) {
      w.writeStartElement('title', prefix: 'dc');
      w.writeText(presentation.properties.title);
      w.writeEndElement();
    }
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
      'draw',
      'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
    );
    w.writeNamespace(
      'presentation',
      'urn:oasis:names:tc:opendocument:xmlns:presentation:1.0',
    );
    w.writeNamespace(
      'svg',
      'urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0',
    );
    w.writeNamespace('xlink', 'http://www.w3.org/1999/xlink');
    w.writeNamespace(
      'table',
      'urn:oasis:names:tc:opendocument:xmlns:table:1.0',
    );
    w.writeNamespace(
      'fo',
      'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0',
    );
    w.writeNamespace('dc', 'http://purl.org/dc/elements/1.1/');
    w.writeNamespace('meta', 'urn:oasis:names:tc:opendocument:xmlns:meta:1.0');
  }

  static String _mediaType(String path) => path.endsWith('.png')
      ? 'image/png'
      : path.endsWith('.jpg')
      ? 'image/jpeg'
      : 'application/octet-stream';
}

class _OdpLayout {
  _OdpLayout(this.presentation);

  final PmlPresentation presentation;
  final List<String> media = <String>[];
  final Map<String, Uint8List> mediaBytes = <String, Uint8List>{};
  final Map<String, String> _graphics = <String, String>{};
  final Map<String, String> _paragraphs = <String, String>{};
  final Map<String, String> _texts = <String, String>{};
  final Map<String, String> _cells = <String, String>{};
  final List<String> _buffers = <String>[];
  int tableCount = 0;

  String addMedia(Uint8List bytes) {
    final ext = _extension(bytes);
    final path = 'Pictures/image${media.length + 1}.$ext';
    media.add(path);
    mediaBytes[path] = bytes;
    return path;
  }

  String pageStyle() {
    if (!_graphics.containsKey('__page')) {
      const name = 'dp1';
      _graphics['__page'] = name;
      _buffers.add(
        '<style:style style:name="$name" style:family="drawing-page">'
        '<style:drawing-page-properties presentation:background-visible="true"/>'
        '</style:style>',
      );
    }
    return _graphics['__page']!;
  }

  String graphicStyle(PmlShape shape) {
    final key =
        '${shape.fillColor}|${shape.strokeColor}|${shape.strokeWidth}|${shape.preset.name}';
    return _graphics.putIfAbsent(key, () {
      final name = 'gr${_graphics.length + 1}';
      final buffer = StringBuffer(
        '<style:style style:name="$name" style:family="graphic">'
        '<style:graphic-properties',
      );
      if (shape.fillColor.isNotEmpty) {
        buffer.write(
          ' draw:fill="solid" draw:fill-color="#${shape.fillColor.toLowerCase()}"',
        );
      } else {
        buffer.write(' draw:fill="none"');
      }
      if (shape.strokeColor.isNotEmpty) {
        buffer.write(' draw:stroke="solid"');
        buffer.write(' svg:stroke-color="#${shape.strokeColor.toLowerCase()}"');
        buffer.write(
          ' svg:stroke-width="${shape.strokeWidth.toStringAsFixed(2)}pt"',
        );
      } else {
        buffer.write(' draw:stroke="none"');
      }
      buffer.write('/></style:style>');
      _buffers.add(buffer.toString());
      return name;
    });
  }

  String paragraphStyle(PmlShape? shape) {
    final align = switch (shape?.textAlign ?? PmlTextAlign.left) {
      PmlTextAlign.center => 'center',
      PmlTextAlign.right => 'end',
      PmlTextAlign.justify => 'justify',
      PmlTextAlign.left => 'start',
    };
    final key = '$align|${shape?.rightToLeft ?? false}';
    return _paragraphs.putIfAbsent(key, () {
      final name = 'P${_paragraphs.length + 1}';
      _buffers.add(
        '<style:style style:name="$name" style:family="paragraph">'
        '<style:paragraph-properties fo:text-align="$align"'
        '${shape?.rightToLeft == true ? ' style:writing-mode="rl-tb"' : ''}/>'
        '</style:style>',
      );
      return name;
    });
  }

  String textStyle(PmlShape? shape) {
    final key =
        '${shape?.textColor ?? ''}|${shape?.fontSizePt ?? 0}|${shape?.rightToLeft ?? false}';
    return _texts.putIfAbsent(key, () {
      final name = 'T${_texts.length + 1}';
      final buffer = StringBuffer(
        '<style:style style:name="$name" style:family="text">'
        '<style:text-properties',
      );
      if (shape != null) {
        if (shape.textColor.isNotEmpty) {
          buffer.write(' fo:color="#${shape.textColor.toLowerCase()}"');
        }
        if (shape.fontSizePt > 0) {
          buffer.write(
            ' fo:font-size="${shape.fontSizePt.toStringAsFixed(1)}pt"',
          );
        }
      }
      buffer.write('/></style:style>');
      _buffers.add(buffer.toString());
      return name;
    });
  }

  String cellStyle(String fill) {
    return _cells.putIfAbsent(fill, () {
      final name = 'Ce${_cells.length + 1}';
      _buffers.add(
        '<style:style style:name="$name" style:family="table-cell">'
        '<style:table-cell-properties fo:background-color="#${fill.toLowerCase()}"/>'
        '</style:style>',
      );
      return name;
    });
  }

  void writeStyles(XmlWriter w) {
    for (final buffer in _buffers) {
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
}
