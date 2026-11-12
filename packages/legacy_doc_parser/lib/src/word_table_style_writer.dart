// SPDX-License-Identifier: MPL-2.0
part of 'conversion.dart';

extension _WordTableStyleWriter on _StructuredWordWriter {
  void _prepareTableStyleDefinitions() {
    if (document.tableStyles.length > 4096) _tooComplex();
    for (final style in document.tableStyles) {
      if (style.id < 0 ||
          style.id > 4095 ||
          _tableStyleDefinitions.containsKey(style.id) ||
          style.name.length > 1024 ||
          (style.rowBandSize != null &&
              (style.rowBandSize! < 1 || style.rowBandSize! > 3)) ||
          (style.columnBandSize != null &&
              (style.columnBandSize! < 1 || style.columnBandSize! > 3))) {
        throw const FormatException('Invalid Word table style definition.');
      }
      _tableStyleDefinitions[style.id] = style;
      _tableTextEvidence(style.id, style.text, null);
      for (final entry in style.textConditions.entries) {
        _tableTextEvidence(style.id, entry.value, entry.key);
      }
    }
    for (final style in document.tableStyles) {
      final seen = <int>{};
      int? id = style.id;
      while (id != null) {
        final current = _tableStyleDefinitions[id];
        if (current == null || !seen.add(id) || seen.length > 64) {
          throw const FormatException('Missing or cyclic Word table style.');
        }
        id = current.basedOn;
      }
    }
  }

  void _tableLook(int options, _BoundedWordXml xml) {
    if (options < 0 || options > 65535) {
      throw const FormatException('Invalid Word table style options.');
    }
    xml.add(
      '<w:tblLook w:val="${(options & 0x7e0).toRadixString(16).padLeft(4, '0')}"'
      ' w:firstRow="${(options & 0x20) != 0 ? 1 : 0}"'
      ' w:lastRow="${(options & 0x40) != 0 ? 1 : 0}"'
      ' w:firstColumn="${(options & 0x80) != 0 ? 1 : 0}"'
      ' w:lastColumn="${(options & 0x100) != 0 ? 1 : 0}"'
      ' w:noHBand="${(options & 0x200) != 0 ? 1 : 0}"'
      ' w:noVBand="${(options & 0x400) != 0 ? 1 : 0}"/>',
    );
  }

  void _tableBorders(
    Map<LegacyWordTableBorderSide, LegacyWordBorder> borders,
    _BoundedWordXml xml,
    String tag,
  ) {
    if (borders.isEmpty) return;
    xml.add('<w:$tag>');
    for (final side in LegacyWordTableBorderSide.values) {
      final border = borders[side];
      if (border == null) continue;
      if (!_wordBorderStyles.contains(border.style) ||
          border.widthEighthPoints < 0 ||
          border.widthEighthPoints > 255 ||
          border.spacingPoints < 0 ||
          border.spacingPoints > 31 ||
          (tag == 'tblBorders' && side.index >= 6)) {
        throw const FormatException('Invalid Word table border.');
      }
      xml.add(
        '<w:${side.name} w:val="${border.style}"'
        ' w:sz="${border.widthEighthPoints}" w:space="${border.spacingPoints}"'
        ' w:color="${border.colorHex == null ? 'auto' : _StructuredWordWriter._color(border.colorHex!)}"'
        ' w:shadow="${border.shadow ? 1 : 0}" w:frame="${border.frame ? 1 : 0}"/>',
      );
    }
    xml.add('</w:$tag>');
  }

  void _tableCellFormat(
    LegacyWordTableCellFormat format,
    _BoundedWordXml xml, {
    bool includeShading = true,
    bool includeBorders = true,
  }) {
    if (includeBorders) _tableBorders(format.borders, xml, 'tcBorders');
    if (includeShading && format.shading != null) {
      _shading(format.shading!, xml, 'tableCellStyle', null);
    }
    if (format.noWrap != null) {
      xml.add('<w:noWrap w:val="${format.noWrap! ? 'on' : 'off'}"/>');
    }
    if (format.margins.isNotEmpty) {
      xml.add('<w:tcMar>');
      for (final side in [
        LegacyWordBorderSide.top,
        LegacyWordBorderSide.left,
        LegacyWordBorderSide.bottom,
        LegacyWordBorderSide.right,
      ]) {
        if (!format.margins.containsKey(side)) continue;
        final width = format.margins[side];
        if (width != null && (width < 0 || width > 31680)) {
          throw const FormatException('Invalid Word cell margin.');
        }
        xml.add(
          '<w:${side.name} w:w="${width ?? 0}" w:type="${width == null ? 'nil' : 'dxa'}"/>',
        );
      }
      xml.add('</w:tcMar>');
    }
    if (format.textDirection != null) {
      xml.add('<w:textDirection w:val="${format.textDirection!.name}"/>');
    }
    if (format.fitText != null) {
      xml.add('<w:tcFitText w:val="${format.fitText! ? 'on' : 'off'}"/>');
    }
    if (format.verticalAlignment != null) {
      xml.add('<w:vAlign w:val="${format.verticalAlignment!.name}"/>');
    }
    if (format.hideMark != null) {
      xml.add('<w:hideMark w:val="${format.hideMark! ? 'on' : 'off'}"/>');
    }
  }

  void _tableStyleXml(_BoundedWordXml xml) {
    for (final style in document.tableStyles) {
      xml.add(
        '<w:style w:type="table" w:styleId="LegacyTable${style.id}"><w:name w:val="',
      );
      xml.text(style.name, attribute: true);
      xml.add('"/>');
      if (style.basedOn != null) {
        xml.add('<w:basedOn w:val="LegacyTable${style.basedOn}"/>');
      }
      _tableTextProperties(style.text, xml);
      xml.add('<w:tblPr>');
      if (style.rowBandSize != null) {
        xml.add('<w:tblStyleRowBandSize w:val="${style.rowBandSize}"/>');
      }
      if (style.columnBandSize != null) {
        xml.add('<w:tblStyleColBandSize w:val="${style.columnBandSize}"/>');
      }
      _tableBorders(style.cell.borders, xml, 'tblBorders');
      xml.add('</w:tblPr><w:tcPr>');
      _tableCellFormat(style.cell, xml, includeBorders: false);
      xml.add('</w:tcPr>');
      for (final condition in LegacyWordTableCondition.values) {
        final rule = style.conditions[condition];
        final text = style.textConditions[condition];
        if (rule == null && text == null) continue;
        xml.add('<w:tblStylePr w:type="${condition.name}">');
        if (text != null) _tableTextProperties(text, xml);
        if (rule != null) {
          xml.add('<w:tcPr>');
          _tableCellFormat(rule, xml);
          xml.add('</w:tcPr>');
        }
        xml.add('</w:tblStylePr>');
      }
      xml.add('</w:style>');
      _count('tableStyleDefinitions');
    }
  }
}
