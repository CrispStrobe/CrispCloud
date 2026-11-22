import '../../opc/opc_archive.dart';
import '../../opc/package_part.dart';
import '../../opc/relationships.dart';
import '../../xml/namespaces.dart';
import '../../xml/xml_node.dart';
import '../../xml/xml_writer.dart';
import '../model/wml_clone.dart';
import '../model/wml_document.dart';
import '../model/word_notes.dart';

/// The explicit native DOCX envelope for modeled footnote rules.
///
/// A single empty paragraph uses an exact line height for the upper gap, a
/// bottom border for the rule and after-spacing for the lower gap. Physical
/// indents bound the rule; both special notes have the same geometry. Native
/// hidden rules add their nominal thickness to the exact paragraph line height
/// because an invisible border contributes no painted rule box. Native
/// reopening accepts this complete shape only. Arbitrary imported separator
/// paragraphs remain opaque in their original package.
///
/// DOCX uses twentieth-point spacing/indents and eighth-point border widths.
/// This mapping is source-qualified separately from installed Word rendering.
/// LibreOffice currently normalizes custom DOCX separator paragraphs, so this
/// class does not establish the DOCX-to-LibreOffice converter route.
abstract final class WordFootnoteSeparatorIo {
  static const _specialTypes = {
    'separator',
    'continuationSeparator',
    'continuationNotice',
  };

  static WmlFootnoteSeparator? read(WmlDocument document) {
    final package = document.package;
    if (package == null) return null;
    try {
      final source = _source(document, package);
      if (source?.localName != 'footnotes' ||
          source?.namespaceUri != OfficeNamespaces.w ||
          !_uniqueAttributes(source!)) {
        return null;
      }
      final definitions = _definitions(source);
      if (definitions.length != 2) return null;
      final normal = definitions.where(
        (node) => _attr(node, 'type') == 'separator',
      );
      final continued = definitions.where(
        (node) => _attr(node, 'type') == 'continuationSeparator',
      );
      if (normal.length != 1 || continued.length != 1) return null;
      final firstId = int.tryParse(_attr(normal.single, 'id') ?? '');
      final secondId = int.tryParse(_attr(continued.single, 'id') ?? '');
      if (firstId == null ||
          secondId == null ||
          firstId == secondId ||
          firstId < -2147483648 ||
          firstId > 2147483647 ||
          secondId < -2147483648 ||
          secondId > 2147483647) {
        return null;
      }
      final allIds = source
          .childrenNamed('footnote', namespaceUri: OfficeNamespaces.w)
          .map((node) => int.tryParse(_attr(node, 'id') ?? ''))
          .toList();
      if (allIds.where((id) => id == firstId).length != 1 ||
          allIds.where((id) => id == secondId).length != 1) {
        return null;
      }
      final refs = _specialReferenceIds(package);
      if (refs.length != 2 ||
          !refs.contains(firstId) ||
          !refs.contains(secondId)) {
        return null;
      }
      final width = _bodyWidthTwips(document);
      final first = _parseDefinition(normal.single, width);
      final second = _parseDefinition(continued.single, width);
      return first != null && first == second ? first : null;
    } on FormatException {
      return null;
    } on UnsupportedError {
      return null;
    }
  }

  /// Validate before the serializer changes any package part.
  static WordFootnoteSeparatorPlan? prepare(WmlDocument document) {
    final geometry = document.footnoteSeparator;
    if (geometry == null) return null;
    geometry.validate();
    final width = _bodyWidthTwips(document);
    final before = _twips(geometry.beforeSpacing);
    final after = _twips(geometry.afterSpacing);
    if ((geometry.thickness != 0 &&
            (geometry.thickness < 0.25 || geometry.thickness > 12)) ||
        (geometry.lineStyle == WmlFootnoteSeparatorLineStyle.solid &&
            geometry.thickness == 0)) {
      throw UnsupportedError(
        'DOCX footnote rules require a solid width from 0.25 to 12 points; '
        'a hidden rule may have zero width.',
      );
    }
    final eighths = (geometry.thickness * 8).round();
    final ruleWidth = (width * geometry.relativeWidth).round();
    if (geometry.visible && ruleWidth == 0) {
      throw UnsupportedError(
        'The footnote rule is narrower than DOCX indent precision.',
      );
    }
    final remainder = width - ruleWidth;
    final left = switch (geometry.alignment) {
      WmlFootnoteSeparatorAlignment.left => 0,
      WmlFootnoteSeparatorAlignment.center => remainder ~/ 2,
      WmlFootnoteSeparatorAlignment.right => remainder,
    };
    final right = remainder - left;
    final lineHeight =
        before + (geometry.visible ? 0 : (eighths * 2.5).round());
    if (lineHeight > 2147483647) {
      throw UnsupportedError(
        'Hidden footnote separator spacing exceeds the DOCX range.',
      );
    }
    final footnoteIds = document.footnotes.map((note) => note.id).toSet();
    final normalizedReserve = before / 20 + eighths / 8 + after / 20;
    for (final section in document.sections) {
      final active = section.blocks
          .expand(WmlClone.paragraphsOf)
          .expand((paragraph) => paragraph.inlines.whereType<WmlRun>())
          .any(
            (run) => !run.noteRefEndnote && footnoteIds.contains(run.noteRefId),
          );
      if (!active) continue;
      final verticalDimensions = [
        section.pageSize.height,
        section.margins.top,
        section.margins.bottom,
      ];
      if (verticalDimensions.any(
        (value) => !value.isFinite || value < 0 || value > 107374182.35,
      )) {
        throw UnsupportedError('Invalid footnote separator body height.');
      }
      final storedHeight =
          ((section.pageSize.height * 20).round() -
              (section.margins.top * 20).round() -
              (section.margins.bottom * 20).round()) /
          20;
      if (geometry.reservedHeight >= section.contentHeight ||
          normalizedReserve >= storedHeight) {
        throw UnsupportedError(
          'The modeled footnote separator exhausts the body height.',
        );
      }
    }
    final package = document.package;
    final source = package == null ? null : _source(document, package);
    if (source != null &&
        (source.localName != 'footnotes' ||
            source.namespaceUri != OfficeNamespaces.w ||
            !_uniqueAttributes(source))) {
      throw const FormatException('Invalid native footnote part.');
    }
    final definitions = _definitions(source);
    if (definitions.isEmpty &&
        package != null &&
        _specialReferenceIds(package).isNotEmpty) {
      throw UnsupportedError(
        'Footnote settings reference missing separator definitions.',
      );
    }
    int normalId;
    int continuationId;
    if (definitions.isNotEmpty) {
      if (read(document) == null) {
        throw UnsupportedError(
          'An unsupported imported footnote separator cannot be replaced implicitly.',
        );
      }
      normalId = int.parse(
        _attr(
          definitions.singleWhere((node) => _attr(node, 'type') == 'separator'),
          'id',
        )!,
      );
      continuationId = int.parse(
        _attr(
          definitions.singleWhere(
            (node) => _attr(node, 'type') == 'continuationSeparator',
          ),
          'id',
        )!,
      );
    } else {
      final used = <int>{
        for (final note in document.footnotes) note.id,
        for (final node
            in source?.childrenNamed(
                  'footnote',
                  namespaceUri: OfficeNamespaces.w,
                ) ??
                <XmlElement>[])
          if (int.tryParse(_attr(node, 'id') ?? '') case final int id) id,
      };
      int allocate(int preferred) {
        var id = preferred;
        while (used.contains(id)) {
          id--;
        }
        used.add(id);
        return id;
      }

      normalId = allocate(-1);
      continuationId = allocate(0);
    }
    if (document.footnotes.any(
      (note) => note.id == normalId || note.id == continuationId,
    )) {
      throw const FormatException(
        'Footnote separator IDs collide with an editable note.',
      );
    }
    return WordFootnoteSeparatorPlan(
      normalId: normalId,
      continuationId: continuationId,
      lineHeight: lineHeight,
      after: after,
      eighths: eighths,
      left: left,
      right: right,
      alignment: geometry.alignment,
      color: geometry.color,
      lineStyle: geometry.lineStyle,
    );
  }

  static int _twips(double value) {
    if (value > 107374182.35) {
      throw UnsupportedError(
        'Footnote separator spacing exceeds the DOCX range.',
      );
    }
    return (value * 20).round();
  }

  static int _bodyWidthTwips(WmlDocument document) {
    if (document.sections.isEmpty) {
      throw UnsupportedError(
        'A modeled footnote separator requires a body section.',
      );
    }
    int? width;
    for (final section in document.sections) {
      final dimensions = [
        section.pageSize.width,
        section.margins.left,
        section.margins.right,
      ];
      if (dimensions.any(
            (value) => !value.isFinite || value < 0 || value > 107374182.35,
          ) ||
          !section.contentWidth.isFinite ||
          section.contentWidth <= 0 ||
          section.contentWidth > 107374182.35) {
        throw UnsupportedError('Invalid footnote separator body width.');
      }
      // The native writer rounds each stored page/margin independently.
      // Rounding their difference instead can produce a one-twip disagreement
      // and make a zero-width rule wider than its reopened body owner.
      final candidate =
          (section.pageSize.width * 20).round() -
          (section.margins.left * 20).round() -
          (section.margins.right * 20).round();
      if (candidate <= 0 || (width != null && width != candidate)) {
        throw UnsupportedError(
          'DOCX modeled footnote separators require a uniform body width across sections.',
        );
      }
      width = candidate;
    }
    return width!;
  }

  static String _mainUri(OpcPackage package) {
    final relation = package.packageRelationships.firstByType(
      RelationshipTypes.officeDocument,
    );
    if (relation?.targetMode == RelationshipTargetMode.external) {
      throw const FormatException(
        'The Word main part must be inside its package.',
      );
    }
    return relation == null
        ? '/word/document.xml'
        : package.packageRelationships.resolve(relation);
  }

  static PackagePart? _part(
    OpcPackage package,
    String mainUri,
    String type,
    String fallback,
  ) {
    final relations = package.relationshipsFor(mainUri);
    final relation = relations.firstByType(type);
    if (relation?.targetMode == RelationshipTargetMode.external) {
      throw const FormatException(
        'The Word note/settings part must be inside its package.',
      );
    }
    return package.getPart(
      relation == null
          ? OpcUris.resolve(mainUri, fallback)
          : relations.resolve(relation),
    );
  }

  static XmlElement? _source(WmlDocument document, OpcPackage package) {
    final part = _part(
      package,
      _mainUri(package),
      RelationshipTypes.footnotes,
      'footnotes.xml',
    );
    return part == null ? null : XmlDocument.parse(part.readText()).root;
  }

  static List<int> _specialReferenceIds(OpcPackage package) {
    final settings = _part(
      package,
      _mainUri(package),
      RelationshipTypes.settings,
      'settings.xml',
    );
    if (settings == null) return [];
    final root = XmlDocument.parse(settings.readText()).root;
    if (root?.localName != 'settings' ||
        root?.namespaceUri != OfficeNamespaces.w ||
        !_uniqueAttributes(root!)) {
      throw const FormatException('Invalid native Word settings.');
    }
    final groups = root.childrenNamed(
      'footnotePr',
      namespaceUri: OfficeNamespaces.w,
    );
    if (groups.length > 1) {
      throw const FormatException('Ambiguous native footnote settings.');
    }
    if (groups.isEmpty) return [];
    final properties = groups.single;
    if (!_uniqueAttributes(properties) ||
        properties.attributes.any(
          (attr) => attr.prefix != 'xmlns' && attr.qualifiedName != 'xmlns',
        )) {
      throw const FormatException(
        'Unsupported native footnote settings attributes.',
      );
    }
    final ids = <int>[];
    for (final node in properties.childrenNamed(
      'footnote',
      namespaceUri: OfficeNamespaces.w,
    )) {
      final id = int.tryParse(_attr(node, 'id') ?? '');
      if (!_shape(node, {'id'}, []) ||
          id == null ||
          id < -2147483648 ||
          id > 2147483647 ||
          ids.contains(id)) {
        throw const FormatException(
          'Invalid native special footnote reference.',
        );
      }
      ids.add(id);
    }
    return ids;
  }

  static List<XmlElement> _definitions(XmlElement? root) => [
    for (final node
        in root?.childrenNamed('footnote', namespaceUri: OfficeNamespaces.w) ??
            <XmlElement>[])
      if (_specialTypes.contains(_attr(node, 'type'))) node,
  ];

  static String? _attr(XmlElement node, String name) =>
      node.getAttribute(name, namespaceUri: OfficeNamespaces.w);

  // The shared preservation parser retains malformed duplicate attributes.
  // Such XML may be kept opaque, but must never become a single modeled value
  // merely because getAttribute returns its first occurrence. Prefix aliases
  // still name the same expanded attribute; declarations use their QName.
  static bool _uniqueAttributes(XmlElement node) {
    final expanded = <(String, String)>{};
    final declarations = <String>{};
    for (final attribute in node.attributes) {
      if (attribute.prefix == 'xmlns' || attribute.qualifiedName == 'xmlns') {
        if (!declarations.add(attribute.qualifiedName)) return false;
      } else if (!expanded.add((attribute.namespaceUri, attribute.localName))) {
        return false;
      }
    }
    return true;
  }

  static bool _shape(
    XmlElement node,
    Set<String> attrs,
    List<String> children,
  ) {
    if (node.namespaceUri != OfficeNamespaces.w ||
        node.text.trim().isNotEmpty ||
        !_uniqueAttributes(node)) {
      return false;
    }
    if (node.attributes.any(
      (attr) =>
          attr.prefix != 'xmlns' &&
          attr.qualifiedName != 'xmlns' &&
          (attr.namespaceUri != OfficeNamespaces.w ||
              !attrs.contains(attr.localName)),
    )) {
      return false;
    }
    final actual = node.childElements.toList();
    return actual.length == children.length &&
        List.generate(actual.length, (index) => index).every(
          (index) =>
              actual[index].namespaceUri == OfficeNamespaces.w &&
              actual[index].localName == children[index],
        );
  }

  static WmlFootnoteSeparator? _parseDefinition(XmlElement node, int width) {
    if (!_shape(node, {'id', 'type'}, ['p'])) return null;
    final paragraph = node.childElements.single;
    if (!_shape(paragraph, {}, ['pPr'])) return null;
    final properties = paragraph.childElements.single;
    if (!_shape(properties, {}, ['pBdr', 'spacing', 'ind', 'jc', 'rPr'])) {
      return null;
    }
    final children = properties.childElements.toList();
    if (!_shape(children[0], {}, ['bottom'])) return null;
    final border = children[0].childElements.single;
    if (!_shape(border, {'val', 'sz', 'space', 'color'}, []) ||
        _attr(border, 'space') != '0') {
      return null;
    }
    final style = switch (_attr(border, 'val')) {
      'single' => WmlFootnoteSeparatorLineStyle.solid,
      'nil' => WmlFootnoteSeparatorLineStyle.none,
      _ => null,
    };
    final rawSize = _attr(border, 'sz');
    final eighths = rawSize == null ? 0 : int.tryParse(rawSize);
    final colorString = _attr(border, 'color') ?? '';
    if (style == null ||
        eighths == null ||
        (eighths != 0 && (eighths < 2 || eighths > 96)) ||
        (style == WmlFootnoteSeparatorLineStyle.solid && eighths == 0) ||
        !RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(colorString)) {
      return null;
    }
    final spacing = children[1];
    if (!_shape(spacing, {'before', 'after', 'line', 'lineRule'}, []) ||
        _attr(spacing, 'before') != '0' ||
        _attr(spacing, 'lineRule') != 'exact') {
      return null;
    }
    int? unsigned(XmlElement value, String name) {
      final raw = _attr(value, name) ?? '';
      if (!RegExp(r'^\d+$').hasMatch(raw)) return null;
      final result = int.tryParse(raw);
      return result == null || result > 2147483647 ? null : result;
    }

    final before = unsigned(spacing, 'line');
    final after = unsigned(spacing, 'after');
    final indent = children[2];
    if (!_shape(indent, {'left', 'right', 'firstLine'}, []) ||
        _attr(indent, 'firstLine') != '0') {
      return null;
    }
    final left = unsigned(indent, 'left');
    final right = unsigned(indent, 'right');
    if (before == null ||
        after == null ||
        left == null ||
        right == null ||
        left + right > width) {
      return null;
    }
    final hiddenThickness =
        style == WmlFootnoteSeparatorLineStyle.none || left + right == width
        ? (eighths * 2.5).round()
        : 0;
    if (before < hiddenThickness) return null;
    final justification = children[3];
    if (!_shape(justification, {'val'}, [])) return null;
    final alignment = switch (_attr(justification, 'val')) {
      'left' => WmlFootnoteSeparatorAlignment.left,
      'center' => WmlFootnoteSeparatorAlignment.center,
      'right' => WmlFootnoteSeparatorAlignment.right,
      _ => null,
    };
    if (alignment == null ||
        (alignment == WmlFootnoteSeparatorAlignment.left && left != 0) ||
        (alignment == WmlFootnoteSeparatorAlignment.right && right != 0) ||
        (alignment == WmlFootnoteSeparatorAlignment.center &&
            (right - left < 0 || right - left > 1))) {
      return null;
    }
    final mark = children[4];
    if (!_shape(mark, {}, ['sz', 'szCs']) ||
        mark.childElements.any(
          (element) =>
              !_shape(element, {'val'}, []) || _attr(element, 'val') != '2',
        )) {
      return null;
    }
    return WmlFootnoteSeparator(
      beforeSpacing: (before - hiddenThickness) / 20,
      afterSpacing: after / 20,
      thickness: eighths / 8,
      relativeWidth: (width - left - right) / width,
      alignment: alignment,
      color: int.parse(colorString, radix: 16),
      lineStyle: style,
    );
  }
}

final class WordFootnoteSeparatorPlan {
  const WordFootnoteSeparatorPlan({
    required this.normalId,
    required this.continuationId,
    required this.lineHeight,
    required this.after,
    required this.eighths,
    required this.left,
    required this.right,
    required this.alignment,
    required this.color,
    required this.lineStyle,
  });
  final int normalId;
  final int continuationId;
  final int lineHeight;
  final int after;
  final int eighths;
  final int left;
  final int right;
  final WmlFootnoteSeparatorAlignment alignment;
  final int color;
  final WmlFootnoteSeparatorLineStyle lineStyle;

  List<int> get ids => [normalId, continuationId];

  void write(XmlWriter writer) {
    for (final (type, id) in [
      ('separator', normalId),
      ('continuationSeparator', continuationId),
    ]) {
      writer.writeStartElement('footnote', prefix: 'w');
      writer.writeAttribute('w:type', type);
      writer.writeAttribute('w:id', '$id');
      writer.writeStartElement('p', prefix: 'w');
      writer.writeStartElement('pPr', prefix: 'w');
      writer.writeStartElement('pBdr', prefix: 'w');
      writer.writeStartElement('bottom', prefix: 'w');
      writer.writeAttribute(
        'w:val',
        lineStyle == WmlFootnoteSeparatorLineStyle.solid ? 'single' : 'nil',
      );
      if (eighths != 0) writer.writeAttribute('w:sz', '$eighths');
      writer.writeAttribute('w:space', '0');
      writer.writeAttribute(
        'w:color',
        color.toRadixString(16).padLeft(6, '0').toUpperCase(),
      );
      writer.writeEndElement();
      writer.writeEndElement();
      writer.writeStartElement('spacing', prefix: 'w');
      writer.writeAttribute('w:before', '0');
      writer.writeAttribute('w:after', '$after');
      writer.writeAttribute('w:line', '$lineHeight');
      writer.writeAttribute('w:lineRule', 'exact');
      writer.writeEndElement();
      writer.writeStartElement('ind', prefix: 'w');
      writer.writeAttribute('w:left', '$left');
      writer.writeAttribute('w:right', '$right');
      writer.writeAttribute('w:firstLine', '0');
      writer.writeEndElement();
      writer.writeStartElement('jc', prefix: 'w');
      writer.writeAttribute('w:val', alignment.name);
      writer.writeEndElement();
      writer.writeStartElement('rPr', prefix: 'w');
      for (final name in ['sz', 'szCs']) {
        writer.writeStartElement(name, prefix: 'w');
        writer.writeAttribute('w:val', '2');
        writer.writeEndElement();
      }
      writer.writeEndElement();
      writer.writeEndElement();
      writer.writeEndElement();
      writer.writeEndElement();
    }
  }
}
