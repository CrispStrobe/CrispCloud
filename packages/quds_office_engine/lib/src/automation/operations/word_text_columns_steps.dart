import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/word/serial/word_section_io.dart';

import 'word_page_setup_steps.dart';

const _w = OfficeNamespaces.w;
const _longMax = 2147483647;

/// Edits one property of one existing section's uniform text columns.
///
/// Source projection, serialized geometry and the complete sparse replacement
/// are checked before any live model or package state changes. Custom columns
/// remain opaque until their individual widths and ordering are modeled.
void setWordTextColumns(
  WmlDocument document,
  WmlSection section, {
  int? count,
  double? spacing,
  bool? lineBetween,
}) {
  if ([count, spacing, lineBetween].where((value) => value != null).length !=
      1) {
    throw ArgumentError(
      'Text columns require exactly one of count, spacing, or lineBetween.',
    );
  }
  if (count != null && (count < 1 || count > 45)) {
    throw ArgumentError('Text column count must be in 1..45.');
  }
  if (spacing != null && !_exactDistance(spacing)) {
    throw ArgumentError(
      'Column spacing requires nonnegative exact twentieth-points within '
      'signed Long twips.',
    );
  }
  if (document.sections.where((value) => identical(value, section)).length !=
      1) {
    throw UnsupportedError('Text columns require one independent section.');
  }

  final source = section.sourceProperties;
  var root = source == null ? null : XmlDocument.parse(source.xml).root;
  if (source != null && root == null) {
    throw UnsupportedError('Text columns require native section properties.');
  }
  validateWordSectionIdentity(document, root);
  final columns = root == null ? null : _validateSource(root);
  _validateSettings(document);

  final nextCount = count ?? section.columnCount;
  final nextSpacing = spacing ?? section.columnSpace;
  final nextSeparator = lineBetween ?? section.columnSep;
  if (section.columnCount < 1 ||
      section.columnCount > 45 ||
      !_exactDistance(section.columnSpace)) {
    throw UnsupportedError('Text columns require supported existing columns.');
  }
  _validateGeometry(section, nextCount, nextSpacing);

  final current = <String>[
    '${section.columnCount}',
    '${pointsToTwips(section.columnSpace)}',
    '${section.columnSep}',
  ];
  final snapshot = source?.values['cols'];
  final original = snapshot?.split('|');
  if (original != null &&
      (original.length != 3 ||
          _integer(original[0], min: 1, max: 45) == null ||
          _integer(original[1]) == null ||
          !const {'true', 'false'}.contains(original[2]))) {
    throw UnsupportedError('Text columns require a complete source snapshot.');
  }
  if (columns != null && original == null) {
    throw UnsupportedError('Text columns require a complete source snapshot.');
  }
  if (original != null) {
    final projected = <String>[
      '${_integer(columns?.getAttribute('num', namespaceUri: _w) ?? '1', min: 1, max: 45)}',
      '${_integer(columns?.getAttribute('space', namespaceUri: _w) ?? '720')}',
      '${_onOff(columns?.getAttribute('sep', namespaceUri: _w)) ?? false}',
    ];
    if (original.join('|') != projected.join('|')) {
      throw UnsupportedError('Text columns refuse inconsistent source values.');
    }
  }

  root ??= XmlElement(localName: 'sectPr', prefix: 'w', namespaceUri: _w);
  if (source == null) WordSectionIo.setNamespaceDeclaration(root, 'w', _w);
  final element =
      columns ?? XmlElement(localName: 'cols', prefix: 'w', namespaceUri: _w);
  if (columns == null) root.addChild(element);
  const names = ['num', 'space', 'sep'];
  String nativeValue(int index, String value) =>
      index == 2 ? (value == 'true' ? '1' : '0') : value;
  for (var index = 0; index < names.length; index++) {
    // Preserve pending changes made by a preceding general native operation.
    // Unchanged imported attributes retain their original sparse shape.
    if (columns == null || original![index] != current[index]) {
      setWordSectionAttribute(
        element,
        names[index],
        nativeValue(index, current[index]),
      );
    }
  }
  if (count != null) setWordSectionAttribute(element, 'num', '$count');
  if (spacing != null) {
    setWordSectionAttribute(element, 'space', '${pointsToTwips(spacing)}');
  }
  if (lineBetween != null) {
    setWordSectionAttribute(element, 'sep', lineBetween ? '1' : '0');
  }
  final replacement = WmlSectionSource(
    xml: XmlDocument(root: root).toXmlString(declaration: false),
    values: {
      ...?source?.values,
      'cols': '$nextCount|${pointsToTwips(nextSpacing)}|$nextSeparator',
    },
  );
  section.columnCount = nextCount;
  section.columnSpace = nextSpacing;
  section.columnSep = nextSeparator;
  section.sourceProperties = replacement;
}

bool _exactDistance(double value) =>
    value.isFinite &&
    value >= 0 &&
    value * 20 <= _longMax &&
    (value * 20).round() / 20 == value;

int? _integer(String raw, {int min = 0, int max = _longMax}) {
  if (!RegExp(r'^\+?\d+$').hasMatch(raw)) return null;
  final value = int.tryParse(raw);
  return value != null && value >= min && value <= max ? value : null;
}

bool? _onOff(String? raw) => switch (raw) {
  '1' || 'true' || 'on' => true,
  '0' || 'false' || 'off' => false,
  _ => null,
};

void _validateGeometry(WmlSection section, int count, double spacing) {
  final size = section.pageSize;
  final margins = section.margins;
  final distances = [
    size.width,
    size.height,
    margins.top,
    margins.bottom,
    margins.left,
    margins.right,
    margins.header,
    margins.footer,
  ];
  if (distances.any(
        (value) => !value.isFinite || value < 0 || value * 20 > _longMax,
      ) ||
      size.width < 1 ||
      size.height < 1 ||
      count < 1 ||
      count > 45 ||
      !_exactDistance(spacing)) {
    throw UnsupportedError('Text columns require supported page geometry.');
  }
  // Check both live and serialized dimensions. The layout model clamps a
  // column to 12pt; accepting less would produce overlapping live columns.
  for (final serialized in [false, true]) {
    double distance(double value) =>
        serialized ? pointsToTwips(value) / 20 : value;
    final width =
        distance(size.width) - distance(margins.left) - distance(margins.right);
    final height =
        distance(size.height) -
        distance(margins.top) -
        distance(margins.bottom);
    if (height <= 0 || width - spacing * (count - 1) < 12 * count) {
      throw ArgumentError(
        'Columns require a positive page body and at least 12 points of '
        'text width per column.',
      );
    }
  }
}

void _uniqueAttributes(XmlElement element) {
  final seen = <String>{};
  for (final attribute in element.attributes) {
    if (attribute.namespaceUri == _w && !seen.add(attribute.localName)) {
      throw UnsupportedError(
        'Text columns refuse duplicate native attributes.',
      );
    }
  }
}

XmlElement? _validateSource(XmlElement root) {
  XmlElement? columns;
  for (final name in ['pgSz', 'pgMar', 'cols', 'textDirection', 'bidi']) {
    final elements = root.childrenNamed(name, namespaceUri: _w).toList();
    if (elements.length > 1) {
      throw UnsupportedError('Text columns refuse duplicate native $name.');
    }
    if (elements.isEmpty) continue;
    final element = elements.single;
    _uniqueAttributes(element);
    if (name == 'textDirection') {
      final direction = element.getAttribute('val', namespaceUri: _w);
      if (direction != 'lrTb') {
        throw UnsupportedError(
          'Text columns require horizontal text direction.',
        );
      }
      continue;
    }
    if (name == 'bidi') {
      if (_onOff(element.getAttribute('val', namespaceUri: _w)) != false) {
        throw UnsupportedError(
          'Text columns do not model right-to-left sections.',
        );
      }
      continue;
    }
    final measurements = switch (name) {
      'pgSz' => ['w', 'h'],
      'pgMar' => [
        'top',
        'bottom',
        'left',
        'right',
        'header',
        'footer',
        'gutter',
      ],
      _ => ['space'],
    };
    for (final attribute in measurements) {
      final raw = element.getAttribute(attribute, namespaceUri: _w);
      if (raw != null && _integer(raw) == null) {
        throw UnsupportedError(
          'Text columns require nonnegative integer native twip measurements.',
        );
      }
    }
    if (name == 'pgMar') {
      final gutter = element.getAttribute('gutter', namespaceUri: _w);
      if (gutter != null && _integer(gutter) != 0) {
        throw UnsupportedError('Text columns do not model nonzero gutters.');
      }
    }
    if (name == 'cols') {
      columns = element;
      final equal = element.getAttribute('equalWidth', namespaceUri: _w);
      final count = element.getAttribute('num', namespaceUri: _w);
      final separator = element.getAttribute('sep', namespaceUri: _w);
      if ((equal != null && _onOff(equal) != true) ||
          (count != null && _integer(count, min: 1, max: 45) == null) ||
          (separator != null && _onOff(separator) == null) ||
          element.childElements.any((child) => child.namespaceUri == _w) ||
          element.attributes.any(
            (attribute) =>
                attribute.namespaceUri == _w &&
                !const {
                  'num',
                  'space',
                  'sep',
                  'equalWidth',
                }.contains(attribute.localName),
          )) {
        throw UnsupportedError('Text columns require uniform native columns.');
      }
    }
  }
  return columns;
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
  if (root == null || root.namespaceUri != _w || root.localName != 'settings') {
    throw UnsupportedError('Text columns require native document settings.');
  }
  const unsupported = {
    'mirrorMargins',
    'gutterAtTop',
    'bookFoldPrinting',
    'bookFoldRevPrinting',
  };
  void visit(XmlElement node) {
    if (node
            .getAttribute('ProcessContent', namespaceUri: OfficeNamespaces.mc)
            ?.trim()
            .isNotEmpty ??
        false) {
      throw UnsupportedError('Text columns refuse ProcessContent settings.');
    }
    if (node.namespaceUri != _w && node.namespaceUri != OfficeNamespaces.mc) {
      return;
    }
    if (node.namespaceUri == _w && unsupported.contains(node.localName)) {
      _uniqueAttributes(node);
      if (_onOff(node.getAttribute('val', namespaceUri: _w)) != false) {
        throw UnsupportedError('Text columns do not model ${node.localName}.');
      }
    }
    for (final child in node.childElements) {
      visit(child);
    }
  }

  visit(root);
}
