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
    'tblCellMar': '${properties.cellMargin}',
  };

  /// Projects only a complete uniform physical-edge margin into the scalar
  /// model. Partial, logical-edge, asymmetric and extension-bearing containers
  /// remain in their original XML instead of becoming a guessed uniform value.
  static double? uniformCellMargin(XmlElement element) {
    final sides = _physicalCellMargins(element);
    if (sides == null || sides.length != 4) return null;
    final first = sides.values.first;
    return sides.values.every((side) => side == first) ? first : null;
  }

  /// Resolve a direct physical margin with both horizontal edges specified.
  /// Omitted vertical edges use the native zero-padding default.
  static WmlTableCellInsets? directCellInsets(XmlElement element) {
    final sides = _physicalCellMargins(element);
    final left = sides?['left'];
    final right = sides?['right'];
    if (sides == null || left == null || right == null) return null;
    return WmlTableCellInsets(
      left: left,
      top: sides['top'] ?? 0,
      right: right,
      bottom: sides['bottom'] ?? 0,
    );
  }

  static Map<String, double>? _physicalCellMargins(XmlElement element) {
    if (element.namespaceUri != OfficeNamespaces.w ||
        element.localName != 'tblCellMar' ||
        element.attributes.any((attribute) => !_namespace(attribute)) ||
        !_whitespaceOnly(element)) {
      return null;
    }
    final sides = <String, double>{};
    for (final edge in element.childElements) {
      if (edge.namespaceUri != OfficeNamespaces.w ||
          !const {'top', 'left', 'bottom', 'right'}.contains(edge.localName) ||
          sides.containsKey(edge.localName) ||
          edge.childElements.isNotEmpty ||
          !_whitespaceOnly(edge)) {
        return null;
      }
      final attributes = <String>{};
      for (final attribute in edge.attributes) {
        if (_namespace(attribute)) continue;
        if (attribute.namespaceUri != OfficeNamespaces.w ||
            !const {'w', 'type'}.contains(attribute.localName) ||
            !attributes.add(attribute.localName)) {
          return null;
        }
      }
      final raw = edge.getAttribute('w', namespaceUri: OfficeNamespaces.w);
      if (edge.getAttribute('type', namespaceUri: OfficeNamespaces.w) !=
              'dxa' ||
          raw == null ||
          !RegExp(r'^[ \t\r\n]*\+?[0-9]+[ \t\r\n]*$').hasMatch(raw)) {
        return null;
      }
      final twips = int.tryParse(raw.trim());
      // The physical left/right margin type uses a signed 16-bit width.
      if (twips == null || twips < 0 || twips > 32767) return null;
      sides[edge.localName] = twipsToPoints(twips);
    }
    return sides;
  }

  static bool _namespace(XmlAttribute attribute) =>
      attribute.prefix == 'xmlns' || attribute.qualifiedName == 'xmlns';

  static bool _whitespaceOnly(XmlElement element) => element.children.every(
    (node) => switch (node) {
      XmlText() => RegExp(r'^[ \t\r\n]*$').hasMatch(node.text),
      XmlCdata() => RegExp(r'^[ \t\r\n]*$').hasMatch(node.text),
      _ => true,
    },
  );

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
          // bidiVisual uses ST_OnOffOnly, unlike most Word boolean flags.
          // The native enumeration accepts on/off, not numeric booleans.
          'w:val': properties.rightToLeft ? 'on' : 'off',
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
    final marginTwips = properties.cellMargin * 20;
    if (!marginTwips.isFinite || marginTwips < 0 || marginTwips > 32767) {
      throw ArgumentError.value(
        properties.cellMargin,
        'cellMargin',
        'Table cell margins must be finite, nonnegative and at most 32767 twips.',
      );
    }
    // Fresh native tables own their scalar value, including zero. Imported
    // values are emitted only when changed by the sparse merge in write().
    writer.writeStartElement('tblCellMar', prefix: 'w');
    for (final edge in const ['top', 'left', 'bottom', 'right']) {
      writer.writeEmptyElement(
        edge,
        prefix: 'w',
        attributes: {'w:w': '${marginTwips.round()}', 'w:type': 'dxa'},
      );
    }
    writer.writeEndElement();
    writer.writeEndElement();
    return XmlDocument.parse(writer.toXml()).root!;
  }
}
