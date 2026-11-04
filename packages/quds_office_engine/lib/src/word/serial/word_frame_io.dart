import '../../xml/namespaces.dart';
import '../../xml/xml_reader.dart';
import '../../xml/xml_writer.dart';
import '../model/wml_document.dart';
import '../properties/wml_properties.dart';
import 'word_drawing_io.dart';

/// WordprocessingShape + VML fallback for [WmlFrame].
///
/// LibreOffice and Word both honor `wp:anchor` rectangles. The custom
/// `qudsFrame` SDT tag is kept only as a reader for older files.
abstract final class WordFrameIo {
  /// write API.
  static void write(
    XmlWriter w,
    WmlFrame frame, {
    required void Function(XmlWriter w, WmlBlock block) writeBlock,
    required int docPrId,
  }) {
    final int cx = WordDrawingIo.sizeToEmu(frame.width);
    final int cy = WordDrawingIo.sizeToEmu(frame.height);
    final int ox = WordDrawingIo.offsetToEmu(frame.x);
    final int oy = WordDrawingIo.offsetToEmu(frame.y);
    final String relative = frame.anchor == WmlFrameAnchor.margin
        ? 'margin'
        : 'page';
    final bool behind = frame.blocks.every(_isBlankBlock);
    final String fill = _hex(frame.fillColor);
    final String stroke = _hex(frame.strokeColor);
    w.writeStartElement('p', prefix: 'w');
    w.writeStartElement('pPr', prefix: 'w');
    w.writeEmptyElement(
      'spacing',
      prefix: 'w',
      attributes: <String, String>{
        'w:before': '0',
        'w:after': '0',
        'w:line': '20',
        'w:lineRule': 'exact',
      },
    );
    w.writeEndElement();
    w.writeStartElement('r', prefix: 'w');
    w.writeStartElement('AlternateContent', prefix: 'mc');
    w.writeStartElement('Choice', prefix: 'mc');
    w.writeAttribute('Requires', 'wps');
    _writeDrawing(
      w,
      frame: frame,
      cx: cx,
      cy: cy,
      ox: ox,
      oy: oy,
      relative: relative,
      behind: behind,
      fill: fill,
      stroke: stroke,
      docPrId: docPrId,
      writeBlock: writeBlock,
    );
    w.writeEndElement();
    w.writeStartElement('Fallback', prefix: 'mc');
    _writeVml(
      w,
      frame: frame,
      fill: fill,
      stroke: stroke,
      behind: behind,
      writeBlock: writeBlock,
    );
    w.writeEndElement();
    w.writeEndElement();
    w.writeEndElement();
    w.writeEndElement();
  }

  /// read API.
  static WmlFrame? read(
    XmlPullReader reader, {
    required WmlParagraph Function(XmlPullReader reader) readParagraph,
  }) {
    if (reader.localName != 'drawing') {
      return null;
    }
    var x = 0.0;
    var y = 0.0;
    var width = 200.0;
    var height = 120.0;
    var verticalPos = false;
    var sawShape = false;
    var inSolidFill = false;
    var inLine = false;
    String? fill;
    String? stroke;
    var anchor = WmlFrameAnchor.page;
    var wrap = WmlFrameWrap.none;
    final List<WmlBlock> blocks = <WmlBlock>[];
    if (!reader.isEmptyElement) {
      final int depth = reader.depth;
      while (reader.next() && reader.depth >= depth) {
        if (reader.eventType != XmlEventType.startElement) {
          continue;
        }
        if (reader.localName == 'wsp' ||
            reader.localName == 'txbx' ||
            reader.localName == 'txbxContent') {
          sawShape = true;
        }
        if (reader.localName == 'pic' || reader.localName == 'chart') {
          return null;
        }
        if (reader.localName == 'positionH') {
          verticalPos = false;
          final String? from = reader.getAttribute('relativeFrom');
          if (from == 'margin') {
            anchor = WmlFrameAnchor.margin;
          }
        } else if (reader.localName == 'positionV') {
          verticalPos = true;
        } else if (reader.localName == 'posOffset') {
          final int? emu = int.tryParse(_elementText(reader));
          if (emu != null) {
            final double points = WordDrawingIo.emuToPoints(emu);
            if (verticalPos) {
              y = points;
            } else {
              x = points;
            }
          }
        } else if (reader.localName == 'extent' || reader.localName == 'ext') {
          final int? cx = int.tryParse(reader.getAttribute('cx') ?? '');
          final int? cy = int.tryParse(reader.getAttribute('cy') ?? '');
          if (cx != null && cx > 0) {
            width = WordDrawingIo.emuToPoints(cx);
          }
          if (cy != null && cy > 0) {
            height = WordDrawingIo.emuToPoints(cy);
          }
        } else if (reader.localName == 'wrapSquare' ||
            reader.localName == 'wrapTight' ||
            reader.localName == 'wrapTopAndBottom') {
          wrap = WmlFrameWrap.square;
        } else if (reader.localName == 'solidFill') {
          inSolidFill = true;
        } else if (reader.localName == 'ln') {
          inLine = true;
        } else if (reader.localName == 'srgbClr') {
          final String? val = reader.getAttribute('val');
          if (val != null && val.isNotEmpty) {
            if (inLine) {
              stroke = val.toUpperCase();
            } else if (inSolidFill) {
              fill = val.toUpperCase();
            }
          }
        } else if (reader.localName == 'p' &&
            reader.namespaceUri == OfficeNamespaces.w) {
          blocks.add(readParagraph(reader));
        }
        if (reader.eventType == XmlEventType.endElement) {
          if (reader.localName == 'solidFill') {
            inSolidFill = false;
          } else if (reader.localName == 'ln') {
            inLine = false;
          }
        }
      }
    }
    if (!sawShape) {
      return null;
    }
    return WmlFrame(
      x: x,
      y: y,
      width: width,
      height: height,
      anchor: anchor,
      wrap: wrap,
      fillColor: fill,
      strokeColor: stroke,
      blocks: blocks,
    );
  }

  static void _writeDrawing(
    XmlWriter w, {
    required WmlFrame frame,
    required int cx,
    required int cy,
    required int ox,
    required int oy,
    required String relative,
    required bool behind,
    required String fill,
    required String stroke,
    required int docPrId,
    required void Function(XmlWriter w, WmlBlock block) writeBlock,
  }) {
    w.writeStartElement('drawing', prefix: 'w');
    w.writeStartElement('anchor', prefix: 'wp');
    w.writeAttribute('distT', '0');
    w.writeAttribute('distB', '0');
    w.writeAttribute('distL', '0');
    w.writeAttribute('distR', '0');
    w.writeAttribute('simplePos', '0');
    w.writeAttribute('relativeHeight', behind ? '0' : '251659264');
    w.writeAttribute('behindDoc', behind ? '1' : '0');
    w.writeAttribute('locked', '0');
    w.writeAttribute('layoutInCell', '1');
    w.writeAttribute('allowOverlap', '1');
    w.writeEmptyElement(
      'simplePos',
      prefix: 'wp',
      attributes: <String, String>{'x': '0', 'y': '0'},
    );
    w.writeStartElement('positionH', prefix: 'wp');
    w.writeAttribute('relativeFrom', relative);
    w.writeStartElement('posOffset', prefix: 'wp');
    w.writeText('$ox');
    w.writeEndElement();
    w.writeEndElement();
    w.writeStartElement('positionV', prefix: 'wp');
    w.writeAttribute('relativeFrom', relative);
    w.writeStartElement('posOffset', prefix: 'wp');
    w.writeText('$oy');
    w.writeEndElement();
    w.writeEndElement();
    w.writeEmptyElement(
      'extent',
      prefix: 'wp',
      attributes: <String, String>{'cx': '$cx', 'cy': '$cy'},
    );
    w.writeEmptyElement(
      'effectExtent',
      prefix: 'wp',
      attributes: <String, String>{'l': '0', 't': '0', 'r': '0', 'b': '0'},
    );
    if (frame.wrap == WmlFrameWrap.square) {
      w.writeEmptyElement(
        'wrapSquare',
        prefix: 'wp',
        attributes: <String, String>{'wrapText': 'bothSides'},
      );
    } else {
      w.writeEmptyElement('wrapNone', prefix: 'wp');
    }
    w.writeStartElement('docPr', prefix: 'wp');
    w.writeAttribute('id', '$docPrId');
    w.writeAttribute('name', 'Frame $docPrId');
    w.writeEndElement();
    w.writeStartElement('cNvGraphicFramePr', prefix: 'wp');
    w.writeEmptyElement('graphicFrameLocks', prefix: 'a');
    w.writeEndElement();
    w.writeStartElement('graphic', prefix: 'a');
    w.writeStartElement('graphicData', prefix: 'a');
    w.writeAttribute('uri', OfficeNamespaces.wps);
    w.writeStartElement('wsp', prefix: 'wps');
    w.writeEmptyElement(
      'cNvSpPr',
      prefix: 'wps',
      attributes: <String, String>{'txBox': '1'},
    );
    w.writeStartElement('spPr', prefix: 'wps');
    w.writeStartElement('xfrm', prefix: 'a');
    w.writeEmptyElement(
      'off',
      prefix: 'a',
      attributes: <String, String>{'x': '0', 'y': '0'},
    );
    w.writeEmptyElement(
      'ext',
      prefix: 'a',
      attributes: <String, String>{'cx': '$cx', 'cy': '$cy'},
    );
    w.writeEndElement();
    w.writeStartElement('prstGeom', prefix: 'a');
    w.writeAttribute('prst', 'rect');
    w.writeEmptyElement('avLst', prefix: 'a');
    w.writeEndElement();
    if (fill.isNotEmpty) {
      w.writeStartElement('solidFill', prefix: 'a');
      w.writeEmptyElement(
        'srgbClr',
        prefix: 'a',
        attributes: <String, String>{'val': fill},
      );
      w.writeEndElement();
    } else {
      w.writeEmptyElement('noFill', prefix: 'a');
    }
    w.writeStartElement('ln', prefix: 'a');
    if (stroke.isEmpty) {
      w.writeEmptyElement('noFill', prefix: 'a');
    } else {
      w.writeAttribute('w', '12700');
      w.writeStartElement('solidFill', prefix: 'a');
      w.writeEmptyElement(
        'srgbClr',
        prefix: 'a',
        attributes: <String, String>{'val': stroke},
      );
      w.writeEndElement();
    }
    w.writeEndElement();
    w.writeEndElement();
    w.writeStartElement('txbx', prefix: 'wps');
    w.writeStartElement('txbxContent', prefix: 'w');
    _writeContent(w, frame, writeBlock);
    w.writeEndElement();
    w.writeEndElement();
    w.writeEmptyElement(
      'bodyPr',
      prefix: 'wps',
      attributes: <String, String>{
        'wrap': 'square',
        'lIns': '0',
        'tIns': '0',
        'rIns': '0',
        'bIns': '0',
        'anchor': 't',
      },
    );
    w.writeEndElement();
    w.writeEndElement();
    w.writeEndElement();
    w.writeEndElement();
    w.writeEndElement();
  }

  static void _writeVml(
    XmlWriter w, {
    required WmlFrame frame,
    required String fill,
    required String stroke,
    required bool behind,
    required void Function(XmlWriter w, WmlBlock block) writeBlock,
  }) {
    final String left = _fmt(frame.x);
    final String top = _fmt(frame.y);
    final String width = _fmt(frame.width);
    final String height = _fmt(frame.height);
    final String relative = frame.anchor == WmlFrameAnchor.margin
        ? 'margin'
        : 'page';
    w.writeStartElement('pict', prefix: 'w');
    w.writeStartElement('rect', prefix: 'v');
    w.writeAttribute(
      'style',
      'position:absolute;left:${left}pt;top:${top}pt;'
      'width:${width}pt;height:${height}pt;z-index:${behind ? -1 : 251659264};'
      'mso-position-horizontal-relative:$relative;'
      'mso-position-vertical-relative:$relative;'
      'mso-wrap-style:${frame.wrap == WmlFrameWrap.square ? 'square' : 'none'}',
    );
    if (fill.isEmpty) {
      w.writeAttribute('filled', 'f');
    } else {
      w.writeAttribute('fillcolor', '#$fill');
    }
    if (stroke.isEmpty) {
      w.writeAttribute('stroked', 'f');
    } else {
      w.writeAttribute('strokecolor', '#$stroke');
    }
    w.writeStartElement('textbox', prefix: 'v');
    w.writeAttribute('inset', '0,0,0,0');
    w.writeStartElement('txbxContent', prefix: 'w');
    _writeContent(w, frame, writeBlock);
    w.writeEndElement();
    w.writeEndElement();
    w.writeEndElement();
    w.writeEndElement();
  }

  static void _writeContent(
    XmlWriter w,
    WmlFrame frame,
    void Function(XmlWriter w, WmlBlock block) writeBlock,
  ) {
    var wrote = false;
    for (final WmlBlock child in frame.blocks) {
      if (_isBlankBlock(child)) {
        continue;
      }
      writeBlock(w, child);
      wrote = true;
    }
    if (!wrote) {
      w.writeStartElement('p', prefix: 'w');
      w.writeEndElement();
    }
  }

  static bool _isBlankBlock(WmlBlock block) {
    return block is WmlParagraph && block.text.trim().isEmpty;
  }

  static String _hex(String? color) {
    if (color == null || color.isEmpty) {
      return '';
    }
    return color.startsWith('#') ? color.substring(1).toUpperCase() : color.toUpperCase();
  }

  static String _fmt(double value) {
    if (value == value.roundToDouble()) {
      return '${value.round()}';
    }
    return value.toStringAsFixed(2);
  }

  static String _elementText(XmlPullReader reader) {
    if (reader.isEmptyElement) {
      return '';
    }
    final StringBuffer buffer = StringBuffer();
    final int depth = reader.depth;
    while (reader.next() && reader.depth >= depth) {
      if (reader.eventType == XmlEventType.characters ||
          reader.eventType == XmlEventType.cdata) {
        buffer.write(reader.text);
      }
    }
    return buffer.toString();
  }
}
