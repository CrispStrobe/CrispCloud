import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/word/serial/word_property_io.dart';

/// Toggle one paragraph's bullet/number kind, using the deterministic Quds
/// single-level defaults when the existing kind differs. Native definitions,
/// rather than display labels or presumed numbering IDs, determine the kind.
void applyDefaultWordList(
  WmlDocument document,
  WmlParagraph paragraph, {
  required bool numbered,
}) {
  final edit = _ListEdit(document, paragraph);
  final numbering = _NumberingSource(document);
  final current = numbering.kind(paragraph.properties);
  if (current == numbered) {
    edit.clear();
    return;
  }
  final prepared = numbering.defaultDefinition(numbered);
  final properties = edit.prepareDefault(prepared.id, numbered);
  // All source and argument checks above finish before either package or
  // paragraph mutation. The prepared XML is detached from the native package.
  prepared.publish();
  paragraph.properties = properties;
}

/// Toggle a validated numeric outline, or apply the separate nine-level Quds
/// outline default. Existing single-level defaults retain their own identity.
void applyDefaultWordOutline(WmlDocument document, WmlParagraph paragraph) {
  final edit = _ListEdit(document, paragraph);
  final numbering = _NumberingSource(document);
  if (numbering.isOutline(paragraph.properties)) {
    edit.clear();
    return;
  }
  _checkInheritedLevelGeometry(document);
  final prepared = numbering.outlineDefinition();
  final properties = edit.prepareDefault(
    prepared.id,
    true,
    preserveRightInheritance: true,
  );
  prepared.publish();
  paragraph.properties = properties;
}

/// Select one existing native list level, without replacing the list instance.
/// Absolute levels are zero-based. Relative moves must be exactly one level.
void changeWordListLevel(
  WmlDocument document,
  WmlParagraph paragraph, {
  int? level,
  int? delta,
}) {
  if ((level == null) == (delta == null) ||
      (level != null && (level < 0 || level > 8)) ||
      (delta != null && delta != -1 && delta != 1)) {
    throw ArgumentError('Specify level in 0..8 or delta -1/1, exclusively.');
  }
  final props = paragraph.properties;
  if (props.numId == null || props.numId == 0 || props.numberingSuppressed) {
    throw UnsupportedError('List-level changes require an existing list.');
  }
  if (props.listRestart != null) {
    throw UnsupportedError('Save pending list restarts before changing level.');
  }
  final edit = _ListEdit(document, paragraph);
  final target = level ?? props.ilvl + delta!;
  if (target < 0 || target > 8) {
    throw UnsupportedError('List-level change would exceed levels 1..9.');
  }
  final numbering = _NumberingSource(document).definitionFor(props);
  numbering.checkedLevel(props.ilvl);
  final selected = numbering.checkedLevel(target);
  final geometry = _levelIndent(selected);
  _checkInheritedLevelGeometry(document, firstLine: geometry.firstLine > 0);
  paragraph.properties = edit.prepareLevel(props.numId!, target, geometry);
}

/// Remove paragraph numbering, with an explicit guard for unsupported LISTNUM
/// field removal. Ordinary field content is never rewritten by a list edit.
void removeWordNumbers(
  WmlDocument document,
  WmlParagraph paragraph, {
  required String numberType,
}) {
  if (numberType != 'paragraph' && numberType != 'all') {
    throw ArgumentError('numberType must be paragraph or all');
  }
  final edit = _ListEdit(document, paragraph, allNumbers: numberType == 'all');
  if (numberType == 'all') _checkListNumFields(document, paragraph);
  edit.clear();
}

const _w = OfficeNamespaces.w;
const _numberNames = {'numPr', 'numId', 'ilvl'};

bool _word(XmlElement node, String name) =>
    node.localName == name && node.namespaceUri == _w;

Iterable<XmlElement> _children(XmlElement node, String name) =>
    node.childElements.where((child) => _word(child, name));

XmlElement? _one(XmlElement node, String name) {
  final matches = _children(node, name).toList(growable: false);
  if (matches.length > 1) {
    throw UnsupportedError('Ambiguous duplicate native $name in list source.');
  }
  return matches.firstOrNull;
}

String? _value(XmlElement node, String name) {
  final attrs = node.attributes
      .where((attr) => attr.localName == name && attr.namespaceUri == _w)
      .toList(growable: false);
  if (attrs.length > 1) {
    throw UnsupportedError('Ambiguous duplicate native $name attribute.');
  }
  for (final attr in node.attributes) {
    if (attr.localName == name &&
        attr.prefix == 'w' &&
        attr.namespaceUri != _w) {
      throw UnsupportedError('Misbound native list attribute namespace.');
    }
  }
  return attrs.firstOrNull?.value;
}

int _integer(String? value, String field, {int min = 0, int max = 2147483647}) {
  final parsed = value != null && RegExp(r'^[0-9]+$').hasMatch(value)
      ? int.tryParse(value)
      : null;
  if (parsed == null || parsed < min || parsed > max) {
    throw UnsupportedError('Native $field must be an integer in $min..$max.');
  }
  return parsed;
}

XmlElement _element(String name) =>
    XmlElement(localName: name, prefix: 'w', namespaceUri: _w)
      ..attributes.add(_wordNamespace('w'));

XmlAttribute _wordNamespace(String prefix) => XmlAttribute(
  localName: prefix,
  value: _w,
  prefix: 'xmlns',
  namespaceUri: 'http://www.w3.org/2000/xmlns/',
);

void _declareWordNamespace(XmlElement node, String prefix) {
  // Namespace declarations own their qualified name. A foreign attribute
  // named x:w or x:w1 must never be replaced by a declaration for that prefix.
  final declarations = node.attributes
      .where((attribute) => attribute.qualifiedName == 'xmlns:$prefix')
      .toList(growable: false);
  if (declarations.length > 1 ||
      declarations.any((attribute) => attribute.value != _w)) {
    throw UnsupportedError('Conflicting native list namespace declaration.');
  }
  if (declarations.isEmpty) node.attributes.add(_wordNamespace(prefix));
}

void _set(XmlElement node, String name, String value) {
  // A native attribute gets its own bound prefix; foreign same-name metadata
  // and its namespace declarations remain untouched.
  var prefix = 'w';
  var suffix = 1;
  final bindings = <String, String>{};
  for (XmlElement? parent = node; parent != null; parent = parent.parent) {
    for (final attr in parent.attributes) {
      if (attr.prefix == 'xmlns') {
        bindings.putIfAbsent(attr.localName, () => attr.value);
      }
    }
  }
  while (bindings[prefix] != null && bindings[prefix] != _w) {
    prefix = 'w${suffix++}';
  }
  _declareWordNamespace(node, prefix);
  node.attributes.removeWhere(
    (a) => a.localName == name && a.namespaceUri == _w,
  );
  node.attributes.add(
    XmlAttribute(
      localName: name,
      value: value,
      prefix: prefix,
      namespaceUri: _w,
    ),
  );
}

XmlElement _ensure(XmlElement parent, String name) {
  final found = _one(parent, name);
  if (found != null) return found;
  final child = _element(name);
  parent.addChild(child);
  return child;
}

XmlElement _properties(WmlParagraph paragraph) {
  final original = paragraph.properties.sourcePropertiesXml;
  if (original != null && original.isNotEmpty) {
    final raw = _parseProperties(original);
    _checkProperties(raw);
    _one(raw, 'ind');
  }
  final source = WordSerializer().paragraphPropertiesXml(paragraph.properties);
  return _parseProperties(source);
}

XmlElement _parseProperties(String source) {
  final wrapper = XmlDocument.parse(
    '<w:context xmlns:w="$_w">$source</w:context>',
  ).root!;
  final children = wrapper.childElements.toList(growable: false);
  if (children.length != 1 || !_word(children.single, 'pPr')) {
    throw UnsupportedError(
      'List edits require unambiguous native paragraph properties.',
    );
  }
  final properties = children.single;
  // Generated fragments inherit w from the wrapper and need that binding
  // when detached. Imported properties may legitimately bind w to an
  // extension namespace while using another prefix for native Word nodes.
  if (!properties.attributes.any(
    (attribute) => attribute.qualifiedName == 'xmlns:w',
  )) {
    _declareWordNamespace(properties, 'w');
  }
  return properties;
}

void _checkProperties(XmlElement properties) {
  void check(XmlElement node) {
    if (_numberNames.contains(node.localName) && node.namespaceUri != _w) {
      throw UnsupportedError(
        'List edits cannot resolve foreign or misbound numbering properties.',
      );
    }
    if (_word(node, 'pPr')) {
      final number = _one(node, 'numPr');
      if (number != null) {
        final id = _one(number, 'numId');
        if (id == null) {
          throw UnsupportedError(
            'Partial native numPr without numId is outside the list-edit contract.',
          );
        }
        _integer(_value(id, 'val'), 'numId');
        final level = _one(number, 'ilvl');
        if (level != null) _integer(_value(level, 'val'), 'ilvl', max: 8);
        if (_one(number, 'numberingChange') != null ||
            _one(number, 'ins') != null) {
          throw UnsupportedError(
            'Resolve tracked numbering changes before list edits.',
          );
        }
      }
    }
    for (final child in node.childElements) {
      check(child);
    }
  }

  check(properties);
}

void _checkPackageSources(WmlDocument document, {required bool allNumbers}) {
  for (final part in document.package?.parts ?? <PackagePart>[]) {
    if (!part.contentType.endsWith('+xml') ||
        (!part.contentType.contains('wordprocessingml') &&
            !part.contentType.contains('vnd.ms-word'))) {
      continue;
    }
    final text = part.readText();
    final isStyles = part.contentType == OfficeContentTypes.wordStyles;
    if (!isStyles && !text.contains('AlternateContent')) continue;
    final root = XmlDocument.parse(text).root;
    if (root == null) throw UnsupportedError('Missing native XML root.');
    if (isStyles) _checkProperties(root);
    void check(XmlElement node, bool alternative) {
      final inside =
          alternative ||
          (node.localName == 'AlternateContent' &&
              node.namespaceUri == OfficeNamespaces.mc);
      if (inside &&
          node.namespaceUri == _w &&
          (_numberNames.contains(node.localName) ||
              (allNumbers &&
                  {
                    'fldSimple',
                    'instrText',
                    'fldChar',
                  }.contains(node.localName)))) {
        throw UnsupportedError(
          'List edits do not resolve numbering or field-bearing markup-compatibility alternatives.',
        );
      }
      for (final child in node.childElements) {
        check(child, inside);
      }
    }

    check(root, false);
  }
}

class _ListEdit {
  _ListEdit(this.document, this.paragraph, {bool allNumbers = false})
    : direct = _properties(paragraph) {
    // Serialization omits unbalanced modeled field boundaries in any story.
    // Opaque field containers can hide the other half of a valid source field,
    // so never publish a list edit when saving would discard those boundaries.
    if (WordFieldSpans.unbalanced(document).isNotEmpty) {
      throw UnsupportedError(
        'List edits cannot preserve unbalanced modeled field boundaries.',
      );
    }
    _checkPackageSources(document, allNumbers: allNumbers);
    _checkProperties(direct);
    _one(direct, 'ind');
    if (paragraph.properties.numId != null) {
      _integer('${paragraph.properties.numId}', 'effective numId');
      _integer('${paragraph.properties.ilvl}', 'effective ilvl', max: 8);
    }
  }

  final WmlDocument document;
  final WmlParagraph paragraph;
  final XmlElement direct;

  void clear() {
    final props = paragraph.properties.copy()
      ..numId = null
      ..numberingSuppressed = true
      ..ilvl = 0
      ..listLabel = null
      ..listRestart = null;
    _writeNumber(0);
    _publish(props);
  }

  WmlParagraphProps prepareDefault(
    int id,
    bool numbered, {
    bool preserveRightInheritance = false,
  }) {
    final props = paragraph.properties.copy()
      ..numId = id
      ..numberingSuppressed = false
      ..ilvl = 0
      ..listLabel = numbered ? '1. ' : '• '
      ..listRestart = null;
    _writeNumber(id);
    if (preserveRightInheritance) _preserveUneditedRightInheritance();
    _writeIndent(props, const WmlIndent(left: 18, hanging: 9));
    _finish(props);
    return props;
  }

  WmlParagraphProps prepareLevel(int id, int level, WmlIndent geometry) {
    final props = paragraph.properties.copy()
      ..numId = id
      ..numberingSuppressed = false
      ..ilvl = level
      // A display label is derived from the entire story's counter sequence.
      // Invalidate it; ordinary save/reopen resolves the authored definition.
      ..listLabel = null;
    _writeNumber(id, level: level);
    _preserveUneditedRightInheritance();
    _writeIndent(props, geometry);
    _finish(props);
    return props;
  }

  void _writeIndent(WmlParagraphProps props, WmlIndent geometry) {
    final indent = _ensure(direct, 'ind');
    // A list write owns left/first-line/hanging. Preserve the paragraph's
    // right indent and all foreign attributes/children.
    for (final name in {
      'left',
      'start',
      'leftChars',
      'startChars',
      'firstLine',
      'firstLineChars',
      'hanging',
      'hangingChars',
    }) {
      indent.attributes.removeWhere(
        (a) => a.namespaceUri == _w && a.localName == name,
      );
    }
    _set(indent, 'left', '${(geometry.left * 20).round()}');
    // Presence of hanging takes precedence over firstLine in Word, even when
    // hanging is zero. Never serialize it alongside a positive firstLine.
    if (geometry.firstLine == 0) {
      _set(indent, 'hanging', '${(geometry.hanging * 20).round()}');
    }
    _set(indent, 'firstLine', '${(geometry.firstLine * 20).round()}');
    props
      ..indent = WmlIndent(
        left: geometry.left,
        right: props.indent.right,
        firstLine: geometry.firstLine,
        hanging: geometry.hanging,
      )
      ..explicitIndent = true;
  }

  void _preserveUneditedRightInheritance() {
    final props = paragraph.properties;
    final snapshot = props.importedValues?['ind']?.split('|');
    final original = props.sourcePropertiesXml;
    if (snapshot == null ||
        snapshot.length != 4 ||
        original == null ||
        snapshot[1] != '${props.indent.right}') {
      return;
    }
    // Numbering projection can change left/hanging after the import snapshot,
    // making the ordinary serializer materialize the whole effective indent.
    // Retain only right-side attributes actually present in direct source.
    // A prior explicit indent operation removes the snapshot and keeps its
    // own ownership, so this never undoes an earlier right-indent write.
    final source = original.isEmpty
        ? null
        : _one(_parseProperties(original), 'ind');
    final generated = _one(direct, 'ind');
    generated?.attributes.removeWhere(
      (attribute) =>
          attribute.namespaceUri == _w &&
          const {
            'right',
            'end',
            'rightChars',
            'endChars',
          }.contains(attribute.localName) &&
          !(source?.attributes.any(
                (old) =>
                    old.namespaceUri == _w &&
                    old.localName == attribute.localName,
              ) ??
              false),
    );
  }

  void _writeNumber(int id, {int level = 0}) {
    final num = _ensure(direct, 'numPr');
    _set(_ensure(num, 'ilvl'), 'val', '$level');
    _set(_ensure(num, 'numId'), 'val', '$id');
    // Native children stay in schema order; opaque siblings retain order.
    final levelNode = _one(num, 'ilvl')!;
    final number = _one(num, 'numId')!;
    final numberIndex = num.children.indexOf(number);
    if (num.children.indexOf(levelNode) > numberIndex) {
      num.children.remove(levelNode);
      num.children.insert(numberIndex, levelNode);
    }
  }

  void _publish(WmlParagraphProps props) {
    _finish(props);
    paragraph.properties = props;
  }

  void _finish(WmlParagraphProps props) {
    WordPropertyIo.orderChildren(direct);
    props.sourcePropertiesXml = XmlDocument(
      root: direct,
    ).toXmlString(declaration: false);
    props.importedValues = WordPropertyIo.paragraphValues(props);
  }
}

const _renderedNumberFormats = {
  'decimal',
  'decimalZero',
  'upperRoman',
  'lowerRoman',
  'upperLetter',
  'lowerLetter',
};

String _outlineLabel(int level) =>
    '${[for (var i = 0; i <= level; i++) '%${i + 1}'].join('.')}.';

String _outlineLevelXml(int level) =>
    '<w:lvl w:ilvl="$level"><w:start w:val="1"/>'
    '<w:numFmt w:val="decimal"/><w:lvlText w:val="${_outlineLabel(level)}"/>'
    '<w:lvlJc w:val="left"/><w:pPr>'
    '<w:ind w:left="${(level + 1) * 360}" w:hanging="180"/>'
    '</w:pPr></w:lvl>';

class _ResolvedList {
  _ResolvedList(this.definition, this.levels, this.overrides);
  final XmlElement definition;
  final Map<int, XmlElement> levels;
  final Map<int, XmlElement> overrides;

  XmlElement level(int index) {
    var result = levels[index];
    final override = overrides[index];
    final replacement = override == null ? null : _one(override, 'lvl');
    if (replacement != null) {
      if (_integer(
            _value(replacement, 'ilvl'),
            'override level ilvl',
            max: 8,
          ) !=
          index) {
        throw UnsupportedError('Mismatched native numbering level override.');
      }
      result = replacement;
    }
    if (result == null) {
      throw UnsupportedError('Unresolved native numbering level.');
    }
    return result;
  }

  /// Level changes select an existing definition, not an inferred fallback.
  /// Check ancestors referenced by a numeric label as well as the level itself.
  XmlElement checkedLevel(int index) {
    final node = level(index);
    final slots = _checkLevel(node, index);
    for (final ancestor in slots) {
      if (ancestor == index) continue;
      final ancestorNode = level(ancestor);
      checkedLevel(ancestor);
      if (_value(_one(ancestorNode, 'numFmt')!, 'val') == 'bullet') {
        throw UnsupportedError(
          'A numeric label cannot reference a bullet level.',
        );
      }
    }
    final override = overrides[index];
    final start = override == null ? null : _one(override, 'startOverride');
    if (start != null) _integer(_value(start, 'val'), 'startOverride', min: 1);
    return node;
  }

  Set<int> _checkLevel(XmlElement node, int index) {
    for (final name in {
      'lvlPicBulletId',
      'pStyle',
      'isLgl',
      'lvlRestart',
      'legacy',
    }) {
      if (_one(node, name) != null) {
        throw UnsupportedError('Native $name is outside list-level editing.');
      }
    }
    final formatNode = _one(node, 'numFmt');
    final textNode = _one(node, 'lvlText');
    final startNode = _one(node, 'start');
    final format = formatNode == null ? null : _value(formatNode, 'val');
    final text = textNode == null ? null : _value(textNode, 'val');
    if (format == null ||
        (format != 'bullet' && !_renderedNumberFormats.contains(format)) ||
        text == null ||
        text.isEmpty ||
        startNode == null) {
      throw UnsupportedError(
        'List-level edits require complete supported levels.',
      );
    }
    _integer(_value(startNode, 'val'), 'level start', min: 1);
    final justification = _one(node, 'lvlJc');
    if (justification != null && _value(justification, 'val') != 'left') {
      throw UnsupportedError(
        'List-level edits support left-aligned list labels.',
      );
    }
    final suffix = _one(node, 'suff');
    if (suffix != null &&
        !const {'tab', 'space', 'nothing'}.contains(_value(suffix, 'val'))) {
      throw UnsupportedError('Unsupported native list-label suffix.');
    }
    _one(node, 'pPr');
    _one(node, 'rPr');
    if (format == 'bullet') {
      if (text.contains('%')) {
        throw UnsupportedError(
          'Bullet labels cannot contain counter placeholders.',
        );
      }
      return const {};
    }
    final matches = RegExp(r'%[1-9]').allMatches(text).toList();
    final slots = <int>{
      for (final match in matches) int.parse(match[0]!.substring(1)) - 1,
    };
    if (matches.length != slots.length ||
        !slots.contains(index) ||
        slots.any((slot) => slot > index) ||
        text.replaceAll(RegExp(r'%[1-9]'), '').contains('%')) {
      throw UnsupportedError(
        'Numeric level labels need their own counter and optional unique ancestor counters.',
      );
    }
    return slots;
  }
}

WmlIndent _levelIndent(XmlElement level) {
  final properties = _one(level, 'pPr');
  final indent = properties == null ? null : _one(properties, 'ind');
  if (properties == null ||
      indent == null ||
      properties.childElements.any(
        (node) => node.namespaceUri == _w && node.localName != 'ind',
      ) ||
      indent.attributes.any(
        (attribute) =>
            attribute.namespaceUri == _w &&
            !const {
              'left',
              'hanging',
              'firstLine',
            }.contains(attribute.localName),
      ) ||
      indent.childElements.any((node) => node.namespaceUri == _w)) {
    throw UnsupportedError(
      'Target levels require explicit left/first-line/hanging twip indentation without other native paragraph formatting.',
    );
  }
  int twips(String name, {bool signed = false, bool required = false}) {
    final value = _value(indent, name);
    if (value == null && !required) return 0;
    final parsed = value != null && RegExp(r'^-?[0-9]+$').hasMatch(value)
        ? int.tryParse(value)
        : null;
    if (parsed == null ||
        parsed.abs() > 2147483647 ||
        (!signed && parsed < 0)) {
      throw UnsupportedError('Invalid native target $name indentation.');
    }
    return parsed;
  }

  final left = twips('left', signed: true, required: true);
  final first = twips('firstLine');
  final hanging = twips('hanging');
  if (first != 0 && _value(indent, 'hanging') != null) {
    throw UnsupportedError(
      'A target hanging attribute overrides first-line indentation.',
    );
  }
  return WmlIndent(
    left: left / 20,
    firstLine: first / 20,
    hanging: hanging / 20,
  );
}

void _checkInheritedLevelGeometry(
  WmlDocument document, {
  bool firstLine = false,
}) {
  // Word lets earlier character-unit indentation override later point-unit
  // values. Quds does not model that precedence or logical start indentation.
  // Conservatively reject such style/default sources before owning geometry,
  // including table conditional regions not evaluated by the live resolver.
  const unsupported = {
    'leftChars',
    'start',
    'startChars',
    'hangingChars',
    'firstLineChars',
  };
  void check(XmlElement node) {
    if (_word(node, 'ind') &&
        node.attributes.any(
          (attribute) =>
              attribute.namespaceUri == _w &&
              (unsupported.contains(attribute.localName) ||
                  (firstLine && attribute.localName == 'hanging')),
        )) {
      throw UnsupportedError(
        'List-level geometry cannot override character or logical indentation in native styles.',
      );
    }
    for (final child in node.childElements) {
      check(child);
    }
  }

  for (final part in document.package?.parts ?? <PackagePart>[]) {
    if (part.contentType == OfficeContentTypes.wordStyles) {
      final root = XmlDocument.parse(part.readText()).root;
      if (root == null) throw UnsupportedError('Missing native styles root.');
      check(root);
    }
  }
}

class _NumberingSource {
  _NumberingSource(this.document) {
    package = document.package ?? OpcPackage.create(OpcPackageKind.word);
    final mainRels = package.packageRelationships
        .byType(RelationshipTypes.officeDocument)
        .toList();
    if (mainRels.length > 1) {
      throw UnsupportedError('Ambiguous main document relationship.');
    }
    final main = mainRels.isEmpty
        ? '/word/document.xml'
        : package.packageRelationships.resolve(mainRels.single);
    relationships = package.relationshipsFor(main);
    final refs = relationships.byType(RelationshipTypes.numbering).toList();
    if (refs.length > 1 ||
        refs.any((r) => r.targetMode == RelationshipTargetMode.external)) {
      throw UnsupportedError(
        'List edits need one internal numbering relationship.',
      );
    }
    hasRelationship = refs.isNotEmpty;
    uri = refs.isEmpty
        ? '/word/numbering.xml'
        : relationships.resolve(refs.single);
    final part = package.getPart(uri);
    if (hasRelationship && part == null) {
      throw UnsupportedError('Missing native numbering part.');
    }
    root = part == null
        ? _element('numbering')
        : XmlDocument.parse(part.readText()).root!;
    if (!_word(root, 'numbering')) {
      throw UnsupportedError('Invalid native numbering root.');
    }
    void check(XmlElement node) {
      if (node.prefix == 'w' && node.namespaceUri != _w) {
        throw UnsupportedError('Misbound native numbering namespace.');
      }
      if (const {
            'abstractNum',
            'num',
            'abstractNumId',
            'lvl',
            'lvlOverride',
            'numFmt',
            'lvlText',
            'lvlPicBulletId',
            'numStyleLink',
            'styleLink',
          }.contains(node.localName) &&
          node.namespaceUri != _w) {
        throw UnsupportedError(
          'Foreign numbering lookalikes are outside the native classification contract.',
        );
      }
      if (node.namespaceUri == _w &&
          node.attributes.any(
            (attr) =>
                const {
                  'val',
                  'ilvl',
                  'numId',
                  'abstractNumId',
                }.contains(attr.localName) &&
                attr.namespaceUri != _w &&
                attr.prefix != 'xmlns',
          )) {
        throw UnsupportedError('Ambiguous foreign numbering attribute.');
      }
      if (node.namespaceUri == OfficeNamespaces.mc &&
          node.localName == 'AlternateContent') {
        throw UnsupportedError(
          'List edits do not resolve alternative numbering definitions.',
        );
      }
      for (final child in node.childElements) {
        check(child);
      }
    }

    check(root);
    for (final node in _children(root, 'abstractNum')) {
      final id = _integer(_value(node, 'abstractNumId'), 'abstractNumId');
      if (abstracts.containsKey(id)) {
        throw UnsupportedError('Duplicate abstract numbering identity.');
      }
      abstracts[id] = node;
    }
    for (final node in _children(root, 'num')) {
      final id = _integer(_value(node, 'numId'), 'numId', min: 1);
      if (instances.containsKey(id)) {
        throw UnsupportedError('Duplicate numbering identity.');
      }
      instances[id] = node;
    }
  }
  final WmlDocument document;
  late final OpcPackage package;
  late final RelationshipCollection relationships;
  late final bool hasRelationship;
  late final String uri;
  late final XmlElement root;
  final abstracts = <int, XmlElement>{};
  final instances = <int, XmlElement>{};

  _ResolvedList definitionFor(WmlParagraphProps props) {
    final instance = instances[props.numId];
    if (instance == null) {
      throw UnsupportedError('Unresolved native numbering identity.');
    }
    final abstractRef = _one(instance, 'abstractNumId');
    final abstractId = _integer(
      abstractRef == null ? null : _value(abstractRef, 'val'),
      'abstractNumId',
    );
    final definition = abstracts[abstractId];
    if (definition == null) {
      throw UnsupportedError('Unresolved abstract numbering identity.');
    }
    if (_one(definition, 'numStyleLink') != null ||
        _one(definition, 'styleLink') != null) {
      throw UnsupportedError(
        'Linked numbering definitions are outside this list-edit contract.',
      );
    }
    final levels = <int, XmlElement>{};
    for (final level in _children(definition, 'lvl')) {
      final index = _integer(_value(level, 'ilvl'), 'ilvl', max: 8);
      if (levels.containsKey(index)) {
        throw UnsupportedError('Duplicate numbering level.');
      }
      levels[index] = level;
    }
    final overrides = <int, XmlElement>{};
    for (final override in _children(instance, 'lvlOverride')) {
      final index = _integer(_value(override, 'ilvl'), 'override ilvl', max: 8);
      if (overrides.containsKey(index)) {
        throw UnsupportedError('Duplicate numbering level override.');
      }
      overrides[index] = override;
    }
    return _ResolvedList(definition, levels, overrides);
  }

  bool? kind(WmlParagraphProps props) {
    final id = props.numId;
    if (id == null || id == 0 || props.numberingSuppressed) return null;
    final level = definitionFor(props).level(props.ilvl);
    if (_one(level, 'lvlPicBulletId') != null) {
      throw UnsupportedError(
        'Picture bullets are outside this list-edit contract.',
      );
    }
    final format = _one(level, 'numFmt');
    final value = format == null ? null : _value(format, 'val');
    if (value == 'bullet') return false;
    if (!const {
      'decimal',
      'decimalZero',
      'upperRoman',
      'lowerRoman',
      'upperLetter',
      'lowerLetter',
      'ordinal',
      'cardinalText',
      'ordinalText',
      'hex',
      'chicago',
    }.contains(value)) {
      throw UnsupportedError('Unsupported or missing native numbering format.');
    }
    final text = _one(level, 'lvlText');
    final label = text == null ? '' : _value(text, 'val') ?? '';
    if (RegExp(r'%[1-9]').allMatches(label).length != 1) {
      throw UnsupportedError(
        'Outline or unmodeled numbered labels are outside this list-edit contract.',
      );
    }
    return true;
  }

  bool isOutline(WmlParagraphProps props) {
    final id = props.numId;
    if (id == null || id == 0 || props.numberingSuppressed) return false;
    final resolved = definitionFor(props);
    resolved.checkedLevel(props.ilvl);
    final typeNode = _one(resolved.definition, 'multiLevelType');
    final type = typeNode == null ? null : _value(typeNode, 'val');
    final levels = {...resolved.levels.keys, ...resolved.overrides.keys};
    // Native type metadata classifies the toggle, never limits available
    // target levels for listLevel. Absent metadata is safe only for one level.
    if (type == 'singleLevel' || (type == null && levels.length == 1)) {
      return false;
    }
    if ((type != 'multilevel' && type != 'hybridMultilevel') ||
        levels.length < 2) {
      throw UnsupportedError('Ambiguous native outline-list classification.');
    }
    for (final index in levels) {
      final node = resolved.checkedLevel(index);
      if (_value(_one(node, 'numFmt')!, 'val') == 'bullet') {
        throw UnsupportedError(
          'Mixed or bulleted multilevel templates are outside outline toggling.',
        );
      }
    }
    return true;
  }

  _PreparedNumbering outlineDefinition() {
    const name = 'Quds-VBA-decimal-outline-v1';
    final matching = <int>[];
    for (final entry in abstracts.entries) {
      final marker = _one(entry.value, 'name');
      if (marker == null || _value(marker, 'val') != name) continue;
      if (!_outlineShape(entry.value)) {
        throw UnsupportedError(
          'An imported list conflicts with the Quds outline definition.',
        );
      }
      matching.add(entry.key);
    }
    for (final abstractId in matching) {
      for (final instance in instances.entries) {
        final ref = _one(instance.value, 'abstractNumId');
        if (ref == null || _value(ref, 'val') != '$abstractId') continue;
        if (_shape(instance.value, const {'numId'}, const {'abstractNumId'}) &&
            _shape(ref, const {'val'}, const {})) {
          return _PreparedNumbering(this, instance.key, changed: false);
        }
      }
    }
    final used = <int>{
      ...abstracts.keys,
      ...instances.keys,
      for (final p in _allParagraphs(document))
        if (p.properties.numId case final int id) id,
      for (final style in document.styles)
        if (style.numId case final int id) id,
      ..._sourceNumberingReferences(package),
    };
    var id = 1;
    while (used.contains(id)) {
      id++;
    }
    if (id > 2147483647) {
      throw UnsupportedError('No native numbering identity available.');
    }
    final definition = XmlDocument.parse(
      '<w:abstractNum xmlns:w="$_w" w:abstractNumId="$id">'
      '<w:multiLevelType w:val="multilevel"/><w:name w:val="$name"/>'
      '${[for (var i = 0; i < 9; i++) _outlineLevelXml(i)].join()}'
      '</w:abstractNum>',
    ).root!;
    final instance = XmlDocument.parse(
      '<w:num xmlns:w="$_w" w:numId="$id"><w:abstractNumId w:val="$id"/></w:num>',
    ).root!;
    final beforeNum = root.children.indexWhere(
      (node) =>
          node is XmlElement &&
          (_word(node, 'num') || _word(node, 'numIdMacAtCleanup')),
    );
    if (beforeNum < 0) {
      root.addChild(definition);
    } else {
      root.children.insert(beforeNum, definition..parent = root);
    }
    final cleanup = root.children.indexWhere(
      (node) => node is XmlElement && _word(node, 'numIdMacAtCleanup'),
    );
    if (cleanup < 0) {
      root.addChild(instance);
    } else {
      root.children.insert(cleanup, instance..parent = root);
    }
    return _PreparedNumbering(this, id, changed: true);
  }

  bool _outlineShape(XmlElement definition) {
    // Match native semantics, accepting foreign metadata without confusing it
    // with native attributes. Nine lvl siblings need index-wise validation.
    if (!_shape(
      definition,
      const {'abstractNumId'},
      const {'multiLevelType', 'name', 'lvl'},
      repeated: const {'lvl'},
    )) {
      return false;
    }
    final type = _one(definition, 'multiLevelType');
    final name = _one(definition, 'name');
    final levels = _children(definition, 'lvl').toList();
    if (type == null ||
        name == null ||
        !_shape(type, const {'val'}, const {}) ||
        !_shape(name, const {'val'}, const {}) ||
        _value(type, 'val') != 'multilevel' ||
        levels.length != 9) {
      return false;
    }
    final seen = <int>{};
    for (final level in levels) {
      final index = int.tryParse(_value(level, 'ilvl') ?? '');
      if (index == null ||
          index < 0 ||
          index > 8 ||
          !seen.add(index) ||
          !_shape(
            level,
            const {'ilvl'},
            const {'start', 'numFmt', 'lvlText', 'lvlJc', 'pPr'},
          )) {
        return false;
      }
      for (final (key, value) in <(String, String)>[
        ('start', '1'),
        ('numFmt', 'decimal'),
        ('lvlText', _outlineLabel(index)),
        ('lvlJc', 'left'),
      ]) {
        final node = _one(level, key);
        if (node == null ||
            !_shape(node, const {'val'}, const {}) ||
            _value(node, 'val') != value) {
          return false;
        }
      }
      final pp = _one(level, 'pPr');
      final indent = pp == null ? null : _one(pp, 'ind');
      if (pp == null ||
          indent == null ||
          !_shape(pp, const {}, const {'ind'}) ||
          !_shape(indent, const {'left', 'hanging'}, const {}) ||
          _value(indent, 'left') != '${(index + 1) * 360}' ||
          _value(indent, 'hanging') != '180') {
        return false;
      }
    }
    return true;
  }

  _PreparedNumbering defaultDefinition(bool numbered) {
    final name = 'Quds-VBA-${numbered ? 'decimal' : 'bullet'}-single-v1';
    final used = <int>{
      ...abstracts.keys,
      ...instances.keys,
      for (final p in _allParagraphs(document))
        if (p.properties.numId case final int id) id,
      for (final style in document.styles)
        if (style.numId case final int id) id,
      ..._sourceNumberingReferences(package),
    };
    for (final entry in abstracts.entries) {
      final marker = _one(entry.value, 'name');
      if (marker == null || _value(marker, 'val') != name) continue;
      if (!_defaultShape(entry.value, numbered)) {
        throw UnsupportedError(
          'An imported list conflicts with the Quds default definition.',
        );
      }
      for (final instance in instances.entries) {
        final ref = _one(instance.value, 'abstractNumId');
        if (ref == null || _value(ref, 'val') != '${entry.key}') continue;
        if (!_shape(instance.value, const {'numId'}, const {'abstractNumId'}) ||
            !_shape(ref, const {'val'}, const {})) {
          continue;
        }
        return _PreparedNumbering(this, instance.key, changed: false);
      }
    }
    var id = 1;
    while (used.contains(id)) {
      id++;
    }
    if (id > 2147483647) {
      throw UnsupportedError('No native numbering identity available.');
    }
    final definition = XmlDocument.parse(
      '<w:abstractNum xmlns:w="$_w" w:abstractNumId="$id">'
      '<w:multiLevelType w:val="singleLevel"/><w:name w:val="$name"/>'
      '<w:lvl w:ilvl="0"><w:start w:val="1"/>'
      '<w:numFmt w:val="${numbered ? 'decimal' : 'bullet'}"/>'
      '<w:lvlText w:val="${numbered ? '%1.' : '•'}"/>'
      '<w:lvlJc w:val="left"/><w:pPr><w:ind w:left="360" w:hanging="180"/>'
      '</w:pPr></w:lvl></w:abstractNum>',
    ).root!;
    final instance = XmlDocument.parse(
      '<w:num xmlns:w="$_w" w:numId="$id"><w:abstractNumId w:val="$id"/></w:num>',
    ).root!;
    final beforeNum = root.children.indexWhere(
      (n) =>
          n is XmlElement && (_word(n, 'num') || _word(n, 'numIdMacAtCleanup')),
    );
    if (beforeNum < 0) {
      root.addChild(definition);
    } else {
      root.children.insert(beforeNum, definition..parent = root);
    }
    final cleanup = root.children.indexWhere(
      (n) => n is XmlElement && _word(n, 'numIdMacAtCleanup'),
    );
    if (cleanup < 0) {
      root.addChild(instance);
    } else {
      root.children.insert(cleanup, instance..parent = root);
    }
    return _PreparedNumbering(this, id, changed: true);
  }

  bool _defaultShape(XmlElement definition, bool numbered) {
    if (!_shape(
      definition,
      const {'abstractNumId'},
      const {'multiLevelType', 'name', 'lvl'},
    )) {
      return false;
    }
    final type = _one(definition, 'multiLevelType');
    final name = _one(definition, 'name');
    final levels = _children(definition, 'lvl').toList();
    if (type == null ||
        name == null ||
        !_shape(type, const {'val'}, const {}) ||
        !_shape(name, const {'val'}, const {}) ||
        _value(type, 'val') != 'singleLevel' ||
        levels.length != 1) {
      return false;
    }
    final level = levels.single;
    if (_value(level, 'ilvl') != '0' ||
        !_shape(
          level,
          const {'ilvl'},
          const {'start', 'numFmt', 'lvlText', 'lvlJc', 'pPr'},
        )) {
      return false;
    }
    for (final (key, expected) in <(String, String)>[
      ('start', '1'),
      ('numFmt', numbered ? 'decimal' : 'bullet'),
      ('lvlText', numbered ? '%1.' : '•'),
      ('lvlJc', 'left'),
    ]) {
      final node = _one(level, key);
      if (node == null ||
          _value(node, 'val') != expected ||
          !_shape(node, const {'val'}, const {})) {
        return false;
      }
    }
    final pp = _one(level, 'pPr');
    final indent = pp == null ? null : _one(pp, 'ind');
    return pp != null &&
        _shape(pp, const {}, const {'ind'}) &&
        indent != null &&
        _shape(indent, const {'left', 'hanging'}, const {}) &&
        _value(indent, 'left') == '360' &&
        _value(indent, 'hanging') == '180' &&
        _one(level, 'lvlPicBulletId') == null &&
        _one(definition, 'numStyleLink') == null &&
        _one(definition, 'styleLink') == null;
  }

  // A marker is an identity hint, never permission to reuse a different native
  // list. Compare the entire native semantic shape, retaining foreign metadata.
  bool _shape(
    XmlElement node,
    Set<String> attributes,
    Set<String> children, {
    Set<String> repeated = const {},
  }) {
    final nativeAttributes = node.attributes
        .where((a) => a.namespaceUri == _w)
        .toList();
    final nativeChildren = node.childElements
        .where((c) => c.namespaceUri == _w)
        .toList();
    return nativeAttributes.length == attributes.length &&
        nativeAttributes.every((a) => attributes.contains(a.localName)) &&
        nativeChildren.every((c) => children.contains(c.localName)) &&
        nativeChildren.map((c) => c.localName).toSet().length ==
            children.length &&
        children.every(
          (name) =>
              repeated.contains(name) ||
              nativeChildren.where((child) => child.localName == name).length ==
                  1,
        );
  }
}

Iterable<WmlParagraph> _allParagraphs(WmlDocument document) sync* {
  yield* document.paragraphs;
  for (final section in document.sections) {
    for (final story in [
      section.header,
      section.footer,
      section.firstHeader,
      section.firstFooter,
      section.evenHeader,
      section.evenFooter,
    ]) {
      yield* WordTree.paragraphs(story);
    }
  }
  for (final note in [...document.footnotes, ...document.endnotes]) {
    yield* note.allParagraphs;
  }
  for (final comment in document.comments) {
    yield* comment.paragraphs;
  }
}

Set<int> _sourceNumberingReferences(OpcPackage package) {
  final reserved = <int>{};
  void reserve(String? value) {
    final id = int.tryParse(value ?? '');
    if (id != null && id >= 0 && id <= 2147483647) reserved.add(id);
  }

  for (final part in package.parts) {
    final type = part.contentType;
    if (!type.endsWith('+xml') ||
        (!type.contains('wordprocessingml') && !type.contains('vnd.ms-word'))) {
      continue;
    }
    final source = part.readText();
    if (!source.contains('numId') && !source.contains('abstractNumId')) {
      continue;
    }
    final reader = XmlPullReader(source);
    while (reader.next()) {
      if (reader.eventType != XmlEventType.startElement) continue;
      // Reserve even namespace lookalikes conservatively: unmodeled source and
      // older import projections must not acquire an unrelated new definition.
      if (reader.localName == 'numId' || reader.localName == 'abstractNumId') {
        reserve(reader.getAttribute('val'));
      }
      reserve(reader.getAttribute('numId'));
      reserve(reader.getAttribute('abstractNumId'));
    }
  }
  return reserved;
}

class _PreparedNumbering {
  _PreparedNumbering(this.source, this.id, {required this.changed});
  final _NumberingSource source;
  final int id;
  final bool changed;
  void publish() {
    if (changed) {
      final xml = XmlDocument(root: source.root).toXmlString();
      final part = source.package.getPart(source.uri);
      if (part == null) {
        source.package.createPart(
          source.uri,
          OfficeContentTypes.wordNumbering,
          utf8.encode(xml),
        );
      } else {
        part.writeText(xml);
      }
    }
    if (!source.hasRelationship) {
      source.relationships.add(
        type: RelationshipTypes.numbering,
        target: source.uri,
      );
    }
    source.document.package = source.package;
  }
}

bool _listNum(String? instruction) =>
    instruction != null &&
    RegExp(r'^\s*LISTNUM\b', caseSensitive: false).hasMatch(instruction);

class _FieldScan {
  _FieldScan(this.touches);
  bool touches;
  bool separated = false;
  final instruction = StringBuffer();
}

bool _opaqueFields(String source) {
  final reader = XmlPullReader(
    '<w:opaqueContext xmlns:w="$_w">$source</w:opaqueContext>',
  );
  while (reader.next()) {
    if (reader.eventType == XmlEventType.startElement &&
        reader.namespaceUri == _w &&
        const {
          'instrText',
          'fldSimple',
          'fldChar',
        }.contains(reader.localName)) {
      return true;
    }
  }
  return false;
}

void _checkListNumFields(WmlDocument document, WmlParagraph target) {
  // An opaque container can hold a field's opening or closing boundary while
  // its result spans an ordinary selected paragraph. Inspect every body block,
  // including containers outside the selector, before scanning modeled fields.
  for (final block in WordTree.descendants(
    document.sections.expand((section) => section.blocks),
  )) {
    if (block is WmlOpaqueBlock && _opaqueFields(block.xml)) {
      throw UnsupportedError(
        'RemoveNumbers all cannot determine field spans through opaque body blocks.',
      );
    }
  }
  final open = <_FieldScan>[];
  void check(_FieldScan field) {
    if (field.touches && _listNum(field.instruction.toString())) {
      throw UnsupportedError(
        'RemoveNumbers all cannot remove LISTNUM fields; use paragraph to retain fields.',
      );
    }
  }

  for (final paragraph in document.paragraphs) {
    final selected = identical(paragraph, target);
    for (final field in open) {
      field.touches |= selected;
    }
    if (selected && _listNum(paragraph.properties.fieldInstruction)) {
      throw UnsupportedError(
        'RemoveNumbers all cannot remove a paragraph LISTNUM field.',
      );
    }
    for (final inline in paragraph.inlines) {
      if (inline is WmlFieldBoundary) {
        switch (inline.kind) {
          case WmlFieldBoundaryKind.begin:
            open.add(_FieldScan(selected));
          case WmlFieldBoundaryKind.instruction:
            if (open.isNotEmpty) {
              if (open.last.separated && selected) {
                throw UnsupportedError(
                  'Field instruction follows its separator in the selected paragraph.',
                );
              }
              open.last.instruction.write(inline.text);
            } else if (selected) {
              throw UnsupportedError(
                'Unbalanced field instruction in selected paragraph.',
              );
            }
          case WmlFieldBoundaryKind.separate:
            if (open.isNotEmpty) {
              if (open.last.separated && selected) {
                throw UnsupportedError(
                  'Repeated field separator in the selected paragraph.',
                );
              }
              open.last.separated = true;
              check(open.last);
            } else if (selected) {
              throw UnsupportedError(
                'Unbalanced field separator in the selected paragraph.',
              );
            }
          case WmlFieldBoundaryKind.end:
            if (open.isNotEmpty) {
              check(open.removeLast());
            } else if (selected) {
              throw UnsupportedError(
                'Unbalanced field end in the selected paragraph.',
              );
            }
        }
      } else if (selected &&
          inline is WmlRun &&
          _listNum(inline.fieldInstruction)) {
        throw UnsupportedError(
          'RemoveNumbers all cannot remove an inline LISTNUM field.',
        );
      } else if (inline is WmlOpaqueInline) {
        if (_opaqueFields(inline.content.xml)) {
          throw UnsupportedError(
            'RemoveNumbers all cannot determine field spans through opaque body inlines.',
          );
        }
      }
    }
  }
  for (final field in open) {
    if (field.touches) {
      throw UnsupportedError(
        'Unbalanced field overlaps the selected paragraph.',
      );
    }
  }
}
