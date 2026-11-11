import '../../xml/namespaces.dart';
import '../../xml/xml_node.dart';
import '../../xml/xml_writer.dart';
import '../properties/wml_properties.dart';
import 'word_property_io.dart';

/// Preserve direct table properties separately from resolved style values.
abstract final class WordTablePropertyIo {
  static Map<String, String> values(
    WmlTableProps properties,
  ) => <String, String>{
    'tblStyle': '${properties.styleId}',
    'bidiVisual': '${properties.rightToLeft}',
    'jc': '${properties.alignment}',
    'tblBorders':
        '${properties.borders}|${properties.borderColor}|${properties.borderWidth}',
  };

  static void write(XmlWriter writer, WmlTableProps properties) {
    final XmlElement generated = _generated(properties);
    final String? source = properties.sourcePropertiesXml;
    final Map<String, String>? imported = properties.importedValues;
    if (source == null || imported == null) {
      generated.writeTo(writer);
      return;
    }
    final XmlElement result = WordPropertyIo.parse(source, 'tblPr');
    final Map<String, String> current = values(properties);
    for (final String key in current.keys) {
      if (current[key] == imported[key]) continue;
      result.children.removeWhere(
        (XmlNode node) =>
            node is XmlElement &&
            node.namespaceUri == OfficeNamespaces.w &&
            node.localName == key,
      );
      for (final XmlElement child in generated.childrenNamed(key)) {
        result.addChild(
          child.copy()..setAttribute('w', OfficeNamespaces.w, prefix: 'xmlns'),
        );
      }
    }
    const order = <String>[
      'tblStyle',
      'tblpPr',
      'tblOverlap',
      'bidiVisual',
      'tblW',
      'jc',
      'tblCellSpacing',
      'tblInd',
      'tblBorders',
      'shd',
      'tblLayout',
      'tblCellMar',
      'tblLook',
      'tblCaption',
      'tblDescription',
      'tblPrChange',
    ];
    int rank(XmlNode node) {
      final int index = node is XmlElement ? order.indexOf(node.localName) : -1;
      return index < 0 ? order.length : index;
    }

    result.children.sort((XmlNode a, XmlNode b) => rank(a).compareTo(rank(b)));
    result.writeTo(writer);
  }

  static XmlElement _generated(WmlTableProps properties) {
    final XmlWriter writer = XmlWriter();
    writer.writeStartElement('tblPr', prefix: 'w');
    writer.writeNamespace('w', OfficeNamespaces.w);
    if (properties.styleId != null) {
      writer.writeEmptyElement(
        'tblStyle',
        prefix: 'w',
        attributes: <String, String>{'w:val': properties.styleId!},
      );
    }
    if (properties.rightToLeft || properties.importedValues != null) {
      writer.writeEmptyElement(
        'bidiVisual',
        prefix: 'w',
        attributes: <String, String>{
          'w:val': properties.rightToLeft ? '1' : '0',
        },
      );
    }
    writer.writeEmptyElement(
      'jc',
      prefix: 'w',
      attributes: <String, String>{
        'w:val': switch (properties.alignment) {
          WmlJustification.center => 'center',
          WmlJustification.right => 'right',
          WmlJustification.justify => 'both',
          WmlJustification.distributed => 'distribute',
          WmlJustification.left => 'left',
        },
      },
    );
    // An explicit off edit must override inherited table-style borders. Merely
    // deleting tblBorders would allow those inherited borders to reappear.
    if (properties.borders ||
        properties.importedValues != null ||
        properties.styleId != null) {
      writer.writeStartElement('tblBorders', prefix: 'w');
      for (final String edge in <String>[
        'top',
        'left',
        'bottom',
        'right',
        'insideH',
        'insideV',
      ]) {
        writer.writeEmptyElement(
          edge,
          prefix: 'w',
          attributes: <String, String>{
            'w:val': properties.borders ? 'single' : 'nil',
            if (properties.borders) ...<String, String>{
              'w:sz': '${(properties.borderWidth * 8).round()}',
              'w:space': '0',
              'w:color': properties.borderColor ?? '000000',
            },
          },
        );
      }
      writer.writeEndElement();
    }
    writer.writeEndElement();
    return XmlDocument.parse(writer.toXml()).root!;
  }
}
