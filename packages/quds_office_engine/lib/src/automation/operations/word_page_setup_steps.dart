import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/word/serial/word_section_io.dart';

const _w = OfficeNamespaces.w;
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
  if (source != null && root == null) {
    throw UnsupportedError('Page setup requires native section properties.');
  }
  validateWordSectionIdentity(document, root);
  if (root != null) _validateSource(root);
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
  _validateGeometry(section, size, margins);

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
    final created = element == null;
    final names = _geometry[key]!;
    final modeled = current[key]!.split('|');
    if (element == null) {
      element = XmlElement(localName: key, prefix: 'w', namespaceUri: _w);
      WordSectionIo.setNamespaceDeclaration(element, 'w', _w);
      root.addChild(element);
      // A newly created native group needs the complete modeled geometry;
      // imported groups, by contrast, retain their existing sparse shape.
      for (var index = 0; index < names.length; index++) {
        setWordSectionAttribute(element, names[index], modeled[index]);
      }
      if (dimension &&
          source.values[key] == null &&
          section.pageSize.isLandscape) {
        // A sparse snapshot created by an independent section edit does not
        // own this absent group; keep ordinary model serialization semantics.
        setWordSectionAttribute(element, 'orient', 'landscape');
      }
    }
    // A preceding general sectionFormat edit can have changed this group in
    // memory. Retain those edits as well, but leave unchanged source attributes
    // sparse and opaque extension metadata intact.
    final original = source.values[key]?.split('|');
    if ((original == null && !created) ||
        (original != null && original.length != names.length)) {
      throw UnsupportedError('Page setup requires a complete source snapshot.');
    }
    for (var index = 0; index < names.length; index++) {
      if (original != null && original[index] != modeled[index]) {
        setWordSectionAttribute(element, names[index], modeled[index]);
      }
    }
    if (dimension && original != null && source.values[key] != current[key]) {
      // Finish the existing general operation's orientation behavior before
      // this independent measurement write takes ownership of its attribute.
      if (section.pageSize.isLandscape) {
        setWordSectionAttribute(element, 'orient', 'landscape');
      } else {
        element.removeAttribute('orient', namespaceUri: _w);
      }
    }
    setWordSectionAttribute(element, attribute, '${twips.round()}');
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

/// Sets or toggles one section's explicit page orientation.
///
/// The bounded operation resolves dimensions at the serializer's integer-twip
/// precision, swaps them when the orientation changes, and retains margins,
/// header/footer distances, and printer paper metadata. Native orientation is
/// independent of dimensions for square pages, so it is retained in a sparse
/// source snapshot even for a newly authored section.
void setWordPageOrientation(
  WmlDocument document,
  WmlSection section, {
  required String orientation,
}) {
  if (!const {'portrait', 'landscape', 'toggle'}.contains(orientation)) {
    throw ArgumentError('Expected portrait, landscape, or toggle orientation.');
  }
  final source = section.sourceProperties;
  var root = source == null ? null : XmlDocument.parse(source.xml).root;
  if (source != null && root == null) {
    throw UnsupportedError('Page setup requires native section properties.');
  }
  validateWordSectionIdentity(document, root);
  if (root != null) _validateSource(root);
  _validateSettings(document);

  final old = section.pageSize;
  if ([
    old.width,
    old.height,
  ].any((value) => !value.isFinite || value < 1 || value * 20 > 2147483647)) {
    throw UnsupportedError(
      'Orientation requires supported existing page size.',
    );
  }
  final widthTwips = pointsToTwips(old.width);
  final heightTwips = pointsToTwips(old.height);
  final normalized =
      widthTwips / 20 != old.width || heightTwips / 20 != old.height;
  final effective = normalized
      ? WmlPageSize(width: widthTwips / 20, height: heightTwips / 20)
      : old;
  var element = root?.firstChild('pgSz', namespaceUri: _w);
  final raw = element?.getAttribute('orient', namespaceUri: _w);
  if (raw != null && !const {'portrait', 'landscape'}.contains(raw)) {
    throw UnsupportedError('Orientation requires a supported native value.');
  }
  final snapshot = source?.values['pgSz'];
  if (element != null && snapshot == null) {
    throw UnsupportedError(
      'Orientation requires a complete page-size snapshot.',
    );
  }
  final current = '$widthTwips|$heightTwips';
  final pendingSize = snapshot != null && snapshot != current;
  if (pendingSize && (effective.width > effective.height) != old.isLandscape) {
    throw UnsupportedError(
      'Orientation refuses pending near-square geometry whose general '
      'section-format orientation is ambiguous.',
    );
  }
  var previous = effective.width > effective.height ? 'landscape' : 'portrait';
  if (snapshot != null) {
    final values = snapshot.split('|').map(int.tryParse).toList();
    if (values.length != 2 ||
        values.any(
          (value) => value == null || value < 20 || value > 2147483647,
        )) {
      throw UnsupportedError(
        'Orientation requires a supported page-size snapshot.',
      );
    }
    final width = values[0]!;
    final height = values[1]!;
    final imported = raw ?? 'portrait';
    if (width != height && (width > height) != (imported == 'landscape')) {
      throw UnsupportedError(
        'Orientation refuses dimensions inconsistent with native orientation.',
      );
    }
    // A preceding general sectionFormat edit owns page geometry and derives its
    // orientation. Resolve that pending edit first; otherwise native orientation
    // (including the missing-attribute portrait default) remains authoritative.
    if (!pendingSize) previous = imported;
  }
  final next = orientation == 'toggle'
      ? (previous == 'portrait' ? 'landscape' : 'portrait')
      : orientation;
  final changed = previous != next;
  final size = changed
      ? WmlPageSize(width: effective.height, height: effective.width)
      : effective;
  _validateGeometry(section, size, section.margins);
  final margins = section.margins;
  if ([
    margins.top,
    margins.bottom,
    margins.left,
    margins.right,
    margins.header,
    margins.footer,
    section.columnSpace,
  ].any((value) => value * 20 > 2147483647)) {
    throw UnsupportedError(
      'Orientation requires supported existing distances.',
    );
  }
  // The model retains all distances unchanged. Check their serialized values
  // as well so rounding cannot eliminate a body or a column's text width.
  _validateGeometry(
    section,
    size,
    WmlPageMargins(
      top: pointsToTwips(margins.top) / 20,
      bottom: pointsToTwips(margins.bottom) / 20,
      left: pointsToTwips(margins.left) / 20,
      right: pointsToTwips(margins.right) / 20,
      header: margins.header,
      footer: margins.footer,
    ),
    columnSpace: pointsToTwips(section.columnSpace) / 20,
  );

  if (root == null) {
    root = XmlElement(localName: 'sectPr', prefix: 'w', namespaceUri: _w);
    WordSectionIo.setNamespaceDeclaration(root, 'w', _w);
  }
  final created = element == null;
  if (element == null) {
    element = XmlElement(localName: 'pgSz', prefix: 'w', namespaceUri: _w);
    WordSectionIo.setNamespaceDeclaration(element, 'w', _w);
    root.addChild(element);
  }
  if (created || changed || pendingSize || normalized) {
    setWordSectionAttribute(element, 'w', '${pointsToTwips(size.width)}');
    setWordSectionAttribute(element, 'h', '${pointsToTwips(size.height)}');
  }
  setWordSectionAttribute(element, 'orient', next);
  final values = <String, String>{
    ...?source?.values,
    'pgSz': '${pointsToTwips(size.width)}|${pointsToTwips(size.height)}',
  };
  final replacementSource = WmlSectionSource(
    xml: XmlDocument(root: root).toXmlString(declaration: false),
    values: values,
  );
  // Construct and validate the complete replacement before changing the model.
  section.pageSize = size;
  section.sourceProperties = replacementSource;
}

void _validateGeometry(
  WmlSection section,
  WmlPageSize size,
  WmlPageMargins margins, {
  double? columnSpace,
}) {
  final gap = columnSpace ?? section.columnSpace;
  final distances = [
    margins.top,
    margins.bottom,
    margins.left,
    margins.right,
    margins.header,
    margins.footer,
    gap,
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
  if (gap * (section.resolvedColumnCount - 1) >=
      size.width - margins.left - margins.right) {
    throw ArgumentError('Columns leave no text width');
  }
}

bool _word(XmlElement element, String name) =>
    element.namespaceUri == _w && element.localName == name;

/// Writes a native Word attribute without changing extension namespace identity.
void setWordSectionAttribute(XmlElement element, String name, String value) {
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
  WordSectionIo.setNamespaceDeclaration(element, prefix, _w);
  element.setAttribute(name, value, prefix: prefix, namespaceUri: _w);
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
}

/// Checks that a selected section has an unambiguous native identity.
///
/// This deliberately does not inspect geometry or printer settings: independent
/// section properties can be edited while retaining unmodeled layout metadata.
/// Recorded previous sections remain opaque revision history.
void validateWordSectionIdentity(WmlDocument document, XmlElement? root) {
  if (root != null && !_word(root, 'sectPr')) {
    throw UnsupportedError('Page setup requires native section properties.');
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

  if (root != null) alternatives(root);
  _validateOriginalSections(document);
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
