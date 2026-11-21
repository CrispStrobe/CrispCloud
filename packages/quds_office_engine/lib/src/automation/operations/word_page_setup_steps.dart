import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/word/serial/word_section_io.dart';

const _w = OfficeNamespaces.w;
const _xmlns = 'http://www.w3.org/2000/xmlns/';
const _geometry = <String, List<String>>{
  'pgSz': ['w', 'h'],
  'pgMar': ['top', 'bottom', 'left', 'right', 'header', 'footer'],
};

/// Writes one explicit section measurement without taking ownership of its
/// other page settings. Source compilation never reads the selected section.
/// All checks and source preparation precede publication to the live model.
void setWordPageSetup(
  WmlDocument document,
  WmlSection section, {
  required String property,
  required double points,
}) {
  const properties = <String>{
    'width',
    'height',
    'top',
    'bottom',
    'left',
    'right',
    'header',
    'footer',
  };
  if (!properties.contains(property)) {
    throw ArgumentError('Unknown page setup property: $property');
  }
  final dimension = property == 'width' || property == 'height';
  final twips = points * 20;
  if (!points.isFinite ||
      points < (dimension ? 1 : 0) ||
      twips > 2147483647 ||
      twips.round() / 20 != points) {
    throw ArgumentError(
      'Page setup requires exact twentieth-points within signed Long twips; '
      'page dimensions must be at least one point and distances nonnegative.',
    );
  }
  final source = section.sourceProperties;
  final root = source == null ? null : XmlDocument.parse(source.xml).root;
  if (source != null && (root == null || !_word(root, 'sectPr'))) {
    throw UnsupportedError('Page setup requires native section properties.');
  }
  if (root != null) _validateSource(root);
  _validateOriginalSections(document);
  _validateSettings(document);

  final old = section.margins;
  final size = WmlPageSize(
    width: property == 'width' ? points : section.pageSize.width,
    height: property == 'height' ? points : section.pageSize.height,
  );
  final margins = WmlPageMargins(
    top: property == 'top' ? points : old.top,
    bottom: property == 'bottom' ? points : old.bottom,
    left: property == 'left' ? points : old.left,
    right: property == 'right' ? points : old.right,
    header: property == 'header' ? points : old.header,
    footer: property == 'footer' ? points : old.footer,
  );
  final distances = [
    margins.top,
    margins.bottom,
    margins.left,
    margins.right,
    margins.header,
    margins.footer,
    section.columnSpace,
  ];
  if (!size.width.isFinite ||
      !size.height.isFinite ||
      size.width < 1 ||
      size.height < 1 ||
      distances.any((value) => !value.isFinite || value < 0) ||
      section.columnCount < 1 ||
      section.columnCount > 45) {
    throw UnsupportedError('Page setup requires supported existing geometry.');
  }
  if (margins.left + margins.right >= size.width ||
      margins.top + margins.bottom >= size.height) {
    throw ArgumentError('Margins leave no page body');
  }
  if (section.columnSpace * (section.resolvedColumnCount - 1) >=
      size.width - margins.left - margins.right) {
    throw ArgumentError('Columns leave no text width');
  }

  WmlSectionSource? replacementSource;
  if (source != null && root != null) {
    final key = dimension ? 'pgSz' : 'pgMar';
    final attribute = switch (property) {
      'width' => 'w',
      'height' => 'h',
      _ => property,
    };
    final current = WordSectionIo.values(section);
    var element = root.firstChild(key, namespaceUri: _w);
    final names = _geometry[key]!;
    final modeled = current[key]!.split('|');
    if (element == null) {
      element = XmlElement(localName: key, prefix: 'w', namespaceUri: _w);
      _declareWordPrefix(element, 'w');
      root.addChild(element);
      // A newly created native group needs the complete modeled geometry;
      // imported groups, by contrast, retain their existing sparse shape.
      for (var index = 0; index < names.length; index++) {
        _setWordAttribute(element, names[index], modeled[index]);
      }
    }
    // A preceding general sectionFormat edit can have changed this group in
    // memory. Retain those edits as well, but leave unchanged source attributes
    // sparse and opaque extension metadata intact.
    final original = source.values[key]?.split('|');
    if (original == null || original.length != names.length) {
      throw UnsupportedError('Page setup requires a complete source snapshot.');
    }
    for (var index = 0; index < names.length; index++) {
      if (original[index] != modeled[index]) {
        _setWordAttribute(element, names[index], modeled[index]);
      }
    }
    if (dimension && source.values[key] != current[key]) {
      // Finish the existing general operation's orientation behavior before
      // this independent measurement write takes ownership of its attribute.
      if (section.pageSize.isLandscape) {
        _setWordAttribute(element, 'orient', 'landscape');
      } else {
        element.removeAttribute('orient', namespaceUri: _w);
      }
    }
    _setWordAttribute(element, attribute, '${twips.round()}');
    if (dimension) {
      // Word's PageWidth and PageHeight setters select custom paper, including
      // same-value assignments. Orientation remains an independent property.
      element.removeAttribute('code', namespaceUri: _w);
    }
    final values = Map<String, String>.from(source.values);
    values[key] = dimension
        ? '${pointsToTwips(size.width)}|${pointsToTwips(size.height)}'
        : [
            margins.top,
            margins.bottom,
            margins.left,
            margins.right,
            margins.header,
            margins.footer,
          ].map(pointsToTwips).join('|');
    replacementSource = WmlSectionSource(
      xml: XmlDocument(root: root).toXmlString(declaration: false),
      values: values,
    );
  }
  section.pageSize = size;
  section.margins = margins;
  if (replacementSource != null) section.sourceProperties = replacementSource;
}

bool _word(XmlElement element, String name) =>
    element.namespaceUri == _w && element.localName == name;

void _setWordAttribute(XmlElement element, String name, String value) {
  var prefix = element.prefix;
  if (prefix.isEmpty) {
    prefix =
        element.attributes
            .where(
              (attribute) =>
                  attribute.namespaceUri == _w && attribute.prefix.isNotEmpty,
            )
            .map((attribute) => attribute.prefix)
            .firstOrNull ??
        '';
  }
  if (prefix.isEmpty) {
    final used = <String>{};
    void collect(XmlElement node) {
      used.add(node.prefix);
      for (final attribute in node.attributes) {
        used.add(attribute.prefix);
        if (attribute.prefix == 'xmlns') used.add(attribute.localName);
      }
      for (final child in node.childElements) {
        collect(child);
      }
    }

    collect(element);
    var index = 0;
    do {
      prefix = 'qudsWord${index++}';
    } while (used.contains(prefix));
  }
  _declareWordPrefix(element, prefix);
  element.setAttribute(name, value, prefix: prefix, namespaceUri: _w);
}

void _declareWordPrefix(XmlElement element, String prefix) {
  // The XML reader retains xmlns declarations with an empty namespace URI.
  // Match their qualified name explicitly, never the native w:w attribute.
  for (final attribute in element.attributes) {
    if (attribute.prefix == 'xmlns' && attribute.localName == prefix) {
      attribute.value = _w;
      return;
    }
  }
  element.attributes.add(
    XmlAttribute(
      localName: prefix,
      prefix: 'xmlns',
      namespaceUri: _xmlns,
      value: _w,
    ),
  );
}

void _validateSource(XmlElement root) {
  for (final name in [..._geometry.keys, 'cols']) {
    final elements = root.childrenNamed(name, namespaceUri: _w).toList();
    if (elements.length > 1) {
      throw UnsupportedError('Page setup refuses duplicate native $name.');
    }
    if (elements.isEmpty) continue;
    final element = elements.single;
    final seen = <String>{};
    for (final attribute in element.attributes) {
      if (attribute.namespaceUri != _w) continue;
      if (!seen.add(attribute.localName)) {
        throw UnsupportedError(
          'Page setup refuses duplicate native attributes.',
        );
      }
    }
    for (final attribute in _geometry[name] ?? const <String>['space']) {
      final raw = element.getAttribute(attribute, namespaceUri: _w);
      if (raw == null) continue;
      final value = RegExp(r'^\+?\d+$').hasMatch(raw)
          ? int.tryParse(raw)
          : null;
      if (value == null || value > 2147483647) {
        throw UnsupportedError(
          'Page setup requires nonnegative integer native twip measurements.',
        );
      }
    }
    if (name == 'pgMar') {
      final gutter = element.getAttribute('gutter', namespaceUri: _w);
      if (gutter != null && int.tryParse(gutter) != 0) {
        throw UnsupportedError('Page setup does not model nonzero gutters.');
      }
    }
    if (name == 'cols') {
      final equal = element.getAttribute('equalWidth', namespaceUri: _w);
      final count = element.getAttribute('num', namespaceUri: _w);
      if ((equal != null && !const {'1', 'true', 'on'}.contains(equal)) ||
          element.childrenNamed('col', namespaceUri: _w).isNotEmpty ||
          (count != null &&
              (int.tryParse(count) == null ||
                  int.parse(count) < 1 ||
                  int.parse(count) > 45))) {
        throw UnsupportedError('Page setup requires uniform native columns.');
      }
    }
  }
  void alternatives(XmlElement node) {
    if (_word(node, 'sectPrChange')) return;
    if (_hasProcessContent(node)) {
      throw UnsupportedError(
        'Page setup refuses ProcessContent section markup.',
      );
    }
    if (node.namespaceUri == OfficeNamespaces.mc &&
        node.localName == 'AlternateContent') {
      throw UnsupportedError(
        'Page setup refuses alternate section properties.',
      );
    }
    // A recorded previous section is opaque history, not current geometry.
    for (final child in node.childElements) {
      alternatives(child);
    }
  }

  alternatives(root);
}

void _validateSettings(WmlDocument document) {
  final package = document.package;
  if (package == null) return;
  final office = package.packageRelationships.firstByType(
    RelationshipTypes.officeDocument,
  );
  final documentUri = office == null
      ? '/word/document.xml'
      : package.packageRelationships.resolve(office);
  final relationships = package.relationshipsFor(documentUri);
  final relation = relationships.firstByType(RelationshipTypes.settings);
  final part = package.getPart(
    relation == null ? '/word/settings.xml' : relationships.resolve(relation),
  );
  if (part == null) return;
  final root = XmlDocument.parse(part.readText()).root;
  if (root == null) return;
  const unsupported = {
    'mirrorMargins',
    'gutterAtTop',
    'bookFoldPrinting',
    'bookFoldRevPrinting',
  };
  void visit(XmlElement node) {
    if (_hasProcessContent(node)) {
      throw UnsupportedError('Page setup refuses ProcessContent settings.');
    }
    if (node.namespaceUri != _w && node.namespaceUri != OfficeNamespaces.mc) {
      return;
    }
    if (node.namespaceUri == _w && unsupported.contains(node.localName)) {
      final value = node.getAttribute('val', namespaceUri: _w);
      if (!const {'0', 'false', 'off'}.contains(value)) {
        throw UnsupportedError('Page setup does not model ${node.localName}.');
      }
    }
    // Retained Choice/Fallback branches can affect Word even when the import
    // projection discarded them. Any enabled special margin mode is refused.
    for (final child in node.childElements) {
      visit(child);
    }
  }

  visit(root);
}

void _validateOriginalSections(WmlDocument document) {
  final package = document.package;
  if (package == null) return;
  final office = package.packageRelationships.firstByType(
    RelationshipTypes.officeDocument,
  );
  final uri = office == null
      ? '/word/document.xml'
      : package.packageRelationships.resolve(office);
  final part = package.getPart(uri);
  if (part == null) return;
  final root = XmlDocument.parse(part.readText()).root;
  if (root == null) return;
  void visit(
    XmlElement node, {
    bool section = false,
    bool alternative = false,
  }) {
    if (_word(node, 'sectPrChange')) return;
    if (_hasProcessContent(node)) {
      throw UnsupportedError(
        'Page setup refuses ProcessContent section markup.',
      );
    }
    final currentSection = section || _word(node, 'sectPr');
    final currentAlternative =
        alternative ||
        (node.namespaceUri == OfficeNamespaces.mc &&
            node.localName == 'AlternateContent');
    if (currentSection && currentAlternative) {
      // The importer projects markup-compatibility branches before storing
      // section snapshots. Inspect original XML so a discarded branch cannot
      // silently establish the selector or geometry of a source macro.
      throw UnsupportedError(
        'Page setup refuses alternate section properties.',
      );
    }
    for (final child in node.childElements) {
      visit(child, section: currentSection, alternative: currentAlternative);
    }
  }

  visit(root);
}

bool _hasProcessContent(XmlElement element) =>
    element
        .getAttribute('ProcessContent', namespaceUri: OfficeNamespaces.mc)
        ?.trim()
        .isNotEmpty ??
    false;
