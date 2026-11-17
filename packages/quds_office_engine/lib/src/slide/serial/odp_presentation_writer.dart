import 'dart:convert';
import 'dart:typed_data';

import '../../odf/odf_text.dart';
import '../../opc/zip/zip_writer.dart';
import '../../xml/xml_writer.dart';
import '../anim/pml_motion.dart';
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
    if (!slide.transition.isNone) {
      w.writeAttribute(
        'presentation:transition-style',
        _transitionStyle(slide.transition),
      );
      w.writeAttribute(
        'presentation:transition-speed',
        slide.transition.durationMs <= 500
            ? 'fast'
            : slide.transition.durationMs >= 1000
            ? 'slow'
            : 'medium',
      );
      if (slide.transition.advanceAfterMs case final advance?) {
        w.writeAttribute(
          'presentation:duration',
          'PT${(advance / 1000).toStringAsFixed(2)}S',
        );
      }
    }
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

  static String _transitionStyle(PmlSlideTransition transition) {
    String direction(PmlTransitionDir dir) => switch (dir) {
      PmlTransitionDir.left => 'left',
      PmlTransitionDir.right => 'right',
      PmlTransitionDir.up => 'up',
      PmlTransitionDir.down => 'down',
      PmlTransitionDir.horizontal => 'horizontal',
      PmlTransitionDir.vertical => 'vertical',
      PmlTransitionDir.inward => 'in',
      PmlTransitionDir.outward => 'out',
    };
    return switch (transition.kind) {
      PmlTransitionKind.none => 'none',
      PmlTransitionKind.fade => 'fade-over',
      PmlTransitionKind.fadeThroughBlack => 'fade-through-black',
      PmlTransitionKind.cut => 'cut',
      PmlTransitionKind.push => 'push-${direction(transition.direction)}',
      PmlTransitionKind.wipe => 'wipe-${direction(transition.direction)}',
      PmlTransitionKind.split =>
        'split-${transition.direction == PmlTransitionDir.horizontal ? 'horizontal' : 'vertical'}',
      PmlTransitionKind.uncover => 'uncover-${direction(transition.direction)}',
      PmlTransitionKind.cover => 'cover-${direction(transition.direction)}',
      PmlTransitionKind.dissolve => 'dissolve',
      PmlTransitionKind.checkerboard => 'checkerboard',
      PmlTransitionKind.blinds => 'blinds-${direction(transition.direction)}',
      PmlTransitionKind.clock => 'clock',
      PmlTransitionKind.zoom => 'zoom-in',
      PmlTransitionKind.flash => 'flash',
      PmlTransitionKind.comb => 'comb-${direction(transition.direction)}',
      PmlTransitionKind.strips => 'strips-${direction(transition.direction)}',
      PmlTransitionKind.randomBars =>
        'random-bars-${direction(transition.direction)}',
      PmlTransitionKind.reveal => 'reveal-${direction(transition.direction)}',
      PmlTransitionKind.gallery => 'gallery',
      PmlTransitionKind.doors => 'doors-${direction(transition.direction)}',
      _ => 'fade-over',
    };
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
        attributes: {'xlink:href': path, 'xlink:type': 'simple'},
      );
    } else if (shape.table case final table?) {
      _writeTable(w, table, transform, layout);
    } else {
      w.writeStartElement('text-box', prefix: 'draw');
      _writeParagraphs(w, shape.text, layout, shape);
      w.writeEndElement();
    }
    w.writeEndElement();
  }

  static void _writeTable(
    XmlWriter w,
    PmlTable table,
    PmlTransform transform,
    _OdpLayout layout,
  ) {
    // The slide model uses an equally sized, rectangular grid. Pad missing
    // positions in the output without calling the mutating cellAt accessor.
    final columns = table.colCount < 1 ? 1 : table.colCount;
    final rows = table.rowCount < 1 ? 1 : table.rowCount;
    w.writeStartElement('table', prefix: 'table');
    w.writeAttribute('table:name', 'Table${layout.tableCount++}');
    w.writeAttribute(
      'table:style-name',
      layout.tableStyle(transform.widthPoints),
    );
    // Impress omits rows wrapped in table-header-rows. Keep presentation rows
    // direct and retain the first-row styling flag without a pagination wrapper.
    w.writeAttribute(
      'table:use-first-row-styles',
      '${table.headerRow && table.rowCount > 0}',
    );
    w.writeEmptyElement(
      'table-column',
      prefix: 'table',
      attributes: {
        'table:style-name': layout.columnStyle(transform.widthPoints / columns),
        if (columns > 1) 'table:number-columns-repeated': '$columns',
      },
    );
    final rowStyle = layout.rowStyle(transform.heightPoints / rows);
    for (var index = 0; index < rows; index++) {
      final row = index < table.rowCount
          ? table.rows[index]
          : const <PmlTableCell>[];
      w.writeStartElement('table-row', prefix: 'table');
      w.writeAttribute('table:style-name', rowStyle);
      final missing = columns - row.length;
      // Presentation readers do not consistently implement table writing-mode.
      // Serialize physical left-to-right positions while keeping each cell's
      // paragraph direction. The source model remains in logical column order.
      if (table.rightToLeft) {
        _writeEmptyTableCells(w, missing, layout, rightToLeft: true);
      }
      for (final cell in table.rightToLeft ? row.reversed : row) {
        w.writeStartElement('table-cell', prefix: 'table');
        w.writeAttribute(
          'table:style-name',
          layout.cellStyle(cell.fillColor.isEmpty ? 'FFFFFF' : cell.fillColor),
        );
        _writeParagraphs(
          w,
          cell.text,
          layout,
          null,
          textColor: cell.textColor.isEmpty ? '1A1A1A' : cell.textColor,
          rightToLeft: table.rightToLeft,
        );
        w.writeEndElement();
      }
      if (!table.rightToLeft) {
        _writeEmptyTableCells(w, missing, layout, rightToLeft: false);
      }
      w.writeEndElement();
    }
    w.writeEndElement();
  }

  static void _writeEmptyTableCells(
    XmlWriter w,
    int count,
    _OdpLayout layout, {
    required bool rightToLeft,
  }) {
    if (count <= 0) return;
    w.writeStartElement('table-cell', prefix: 'table');
    if (count > 1) w.writeAttribute('table:number-columns-repeated', '$count');
    w.writeAttribute('table:style-name', layout.cellStyle('FFFFFF'));
    _writeParagraphs(w, '', layout, null, rightToLeft: rightToLeft);
    w.writeEndElement();
  }

  static void _writeParagraphs(
    XmlWriter w,
    String text,
    _OdpLayout layout,
    PmlShape? shape, {
    String? textColor,
    bool? rightToLeft,
  }) {
    final lines = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    if (lines.isEmpty) {
      w.writeEmptyElement('p', prefix: 'text');
      return;
    }
    final paragraphStyle = layout.paragraphStyle(
      shape,
      rightToLeft: rightToLeft,
    );
    final textStyle = layout.textStyle(shape, textColor: textColor);
    for (final line in lines) {
      w.writeStartElement('p', prefix: 'text');
      w.writeAttribute('text:style-name', paragraphStyle);
      if (line.isNotEmpty) {
        final link = shape?.hyperlinkUrl ?? '';
        if (link.isNotEmpty) {
          w.writeStartElement('a', prefix: 'text');
          w.writeAttribute('xlink:href', link);
        }
        w.writeStartElement('span', prefix: 'text');
        w.writeAttribute('text:style-name', textStyle);
        writeOdfText(w, line);
        w.writeEndElement();
        if (link.isNotEmpty) w.writeEndElement();
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
  final Map<String, String> _tables = <String, String>{};
  final Map<String, String> _columns = <String, String>{};
  final Map<String, String> _rows = <String, String>{};
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

  String paragraphStyle(PmlShape? shape, {bool? rightToLeft}) {
    final align = switch (shape?.textAlign ?? PmlTextAlign.left) {
      PmlTextAlign.center => 'center',
      PmlTextAlign.right => 'end',
      PmlTextAlign.justify => 'justify',
      PmlTextAlign.left => 'start',
    };
    final rtl = rightToLeft ?? shape?.rightToLeft ?? false;
    final key = '$align|$rtl|${rightToLeft != null}';
    return _paragraphs.putIfAbsent(key, () {
      final name = 'P${_paragraphs.length + 1}';
      _buffers.add(
        '<style:style style:name="$name" style:family="paragraph">'
        '<style:paragraph-properties fo:text-align="$align"'
        '${rtl
            ? ' style:writing-mode="rl-tb"'
            : rightToLeft != null
            ? ' style:writing-mode="lr-tb"'
            : ''}'
        '${rightToLeft != null ? ' style:writing-mode-automatic="false"' : ''}/>'
        '</style:style>',
      );
      return name;
    });
  }

  String textStyle(PmlShape? shape, {String? textColor}) {
    final color = (textColor ?? shape?.textColor ?? '').toLowerCase();
    final key =
        '$color|${shape?.fontSizePt ?? 0}|${shape?.rightToLeft ?? false}';
    return _texts.putIfAbsent(key, () {
      final name = 'T${_texts.length + 1}';
      final w = XmlWriter();
      w.writeStartElement('style', prefix: 'style');
      w.writeAttribute('style:name', name);
      w.writeAttribute('style:family', 'text');
      w.writeStartElement('text-properties', prefix: 'style');
      if (color.isNotEmpty) w.writeAttribute('fo:color', '#$color');
      if (shape != null) {
        if (shape.fontSizePt > 0) {
          w.writeAttribute(
            'fo:font-size',
            '${shape.fontSizePt.toStringAsFixed(1)}pt',
          );
        }
      }
      w.writeEndElement();
      w.writeEndElement();
      _buffers.add(w.toXml());
      return name;
    });
  }

  String tableStyle(double width) {
    final length = _positiveLength(width);
    return _tables.putIfAbsent(length ?? '', () {
      final name = 'Ta${_tables.length + 1}';
      _buffers.add(
        '<style:style style:name="$name" style:family="table">'
        '<style:table-properties style:writing-mode="lr-tb"'
        '${length == null ? '' : ' style:width="$length"'}/>'
        '</style:style>',
      );
      return name;
    });
  }

  String columnStyle(double width) {
    final length = _positiveLength(width);
    return _columns.putIfAbsent(length ?? '', () {
      final name = 'Co${_columns.length + 1}';
      _buffers.add(
        '<style:style style:name="$name" style:family="table-column">'
        '<style:table-column-properties'
        '${length == null ? '' : ' style:column-width="$length" style:use-optimal-column-width="false"'}/>'
        '</style:style>',
      );
      return name;
    });
  }

  String rowStyle(double height) {
    final length = _positiveLength(height);
    return _rows.putIfAbsent(length ?? '', () {
      final name = 'Ro${_rows.length + 1}';
      _buffers.add(
        '<style:style style:name="$name" style:family="table-row">'
        '<style:table-row-properties'
        '${length == null ? '' : ' style:row-height="$length" style:use-optimal-row-height="false"'}/>'
        '</style:style>',
      );
      return name;
    });
  }

  // Match frame precision and leave unrepresentable/invalid dimensions to the
  // consumer rather than emitting a zero or nonfinite positiveLength value.
  static String? _positiveLength(double points) {
    if (!points.isFinite || points <= 0) return null;
    final value = points.toStringAsFixed(2);
    return double.parse(value) > 0 ? '${value}pt' : null;
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
