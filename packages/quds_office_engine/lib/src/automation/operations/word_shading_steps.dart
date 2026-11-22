import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/word/serial/word_property_io.dart';

const _w = OfficeNamespaces.w;

bool _word(XmlElement node, String name) =>
    node.localName == name && node.namespaceUri == _w;

Never _refuse(String reason) =>
    throw UnsupportedError('Paragraph shading $reason');

/// Check ownership before the general paragraph selector walks the document.
/// Generated TOC paragraphs have no independently editable native pPr owner.
Set<WmlParagraph> wordShadingTargets(WmlDocument document) {
  final seen = Set<WmlBlock>.identity();
  final targets = Set<WmlParagraph>.identity();
  void visit(Iterable<WmlBlock> blocks, {bool generated = false}) {
    for (final block in blocks) {
      if (!seen.add(block)) {
        throw StateError(
          'Paragraph shading requires uniquely owned acyclic document blocks.',
        );
      }
      if (block is WmlParagraph && !generated) targets.add(block);
      if (block is WmlToc) {
        visit([
          block.titleParagraph,
          ...block.itemParagraphs,
          for (final source
              in block.sourcePresentation?.paragraphs ??
                  <WmlTocSourceParagraph>[])
            source.paragraph,
        ], generated: true);
      } else {
        for (final children in WordTree.childLists(block)) {
          visit(children, generated: generated);
        }
      }
    }
  }

  for (final section in document.sections) {
    visit(section.blocks);
    for (final story in [
      section.header,
      section.footer,
      section.firstHeader,
      section.firstFooter,
      section.evenHeader,
      section.evenFooter,
    ]) {
      visit(story);
    }
  }
  for (final note in [...document.footnotes, ...document.endnotes]) {
    visit(note.blocks);
  }
  for (final comment in document.comments) {
    visit(comment.paragraphs);
  }
  return targets;
}

/// Set one solid paragraph background, preserving all unowned native metadata.
///
/// `auto` is an explicit native background override, represented as no fill in
/// the renderer. It is deliberately not implemented by removing w:shd, which
/// would reveal an inherited color. This operation does not change the texture.
void setWordParagraphShading(
  WmlDocument document,
  WmlParagraph paragraph, {
  required String color,
  required Set<WmlParagraph> targets,
}) {
  if (color != 'auto' && !RegExp(r'^[0-9A-F]{6}$').hasMatch(color)) {
    throw ArgumentError('color must be six uppercase RGB hex digits or auto');
  }
  if (!targets.contains(paragraph)) {
    _refuse('requires an independently owned ordinary paragraph.');
  }
  if (WordFieldSpans.unbalanced(document).isNotEmpty) {
    _refuse('requires balanced modeled field boundaries.');
  }
  // First serialize earlier pending edits on a detached copy. Recording the
  // resulting direct packet and its current values avoids pinning unrelated
  // inherited properties or discarding earlier native operations in this plan.
  final properties = paragraph.properties.copy();
  final direct = _fragment(WordSerializer().paragraphPropertiesXml(properties));
  _validateSource(document, paragraph, direct);
  _checkTree(direct, validateShading: true);
  WordPropertyIo.mergeParagraphShading(direct, color);
  properties
    ..shadingFill = color == 'auto' ? null : color
    ..sourcePropertiesXml = XmlDocument(
      root: direct,
    ).toXmlString(declaration: false);
  properties.importedValues = WordPropertyIo.paragraphValues(properties);
  // No package, live paragraph, run, or original property object has changed
  // before this single publication point.
  paragraph.properties = properties;
}

XmlElement _fragment(String source) {
  final wrapper = XmlDocument.parse(
    '<w:context xmlns:w="$_w">$source</w:context>',
  ).root!;
  final roots = wrapper.childElements.toList(growable: false);
  if (roots.length != 1 || !_word(roots.single, 'pPr')) {
    _refuse('requires an unambiguous native paragraph property packet.');
  }
  final root = roots.single;
  // Serializer fragments can inherit w from their surrounding document. Keep
  // that binding on the standalone snapshot without rebinding a foreign w.
  if (!root.attributes.any(
    (attribute) => attribute.prefix == 'xmlns' && attribute.localName == 'w',
  )) {
    root.setAttribute('w', _w, prefix: 'xmlns');
  }
  return root;
}

void _validateSource(
  WmlDocument document,
  WmlParagraph paragraph,
  XmlElement direct,
) {
  final source = paragraph.properties.sourcePropertiesXml;
  if (source != null && source.isNotEmpty) {
    _checkTree(_fragment(source), validateShading: true);
  }
  final package = document.package;
  if (package == null) return;

  final modeled = <String>{};
  if (document.styles.any(
        (style) =>
            !modeled.add(style.id) ||
            !identical(style, document.importedStyles[style.id]),
      ) ||
      document.importedStyles.keys.any((id) => !modeled.contains(id))) {
    _refuse('requires synchronized native and modeled styles.');
  }

  final styles = _activeStyles(document);
  final types = styles == null ? <String, String>{} : _styleTypes(styles);
  final roots = <XmlElement>[];
  for (final stored in package.parts) {
    if (!stored.contentType.endsWith('+xml') ||
        (!stored.contentType.contains('wordprocessingml') &&
            !stored.contentType.contains('vnd.ms-word'))) {
      continue;
    }
    final root = XmlDocument.parse(
      package.getPart(stored.uri)!.readText(),
    ).root;
    if (root == null) _refuse('requires native Word XML roots.');
    _checkTree(root);
    roots.add(root);
  }
  for (final root in roots) {
    _checkStyleReferences(root, types);
  }
  // A pending style assignment is already serialized into sourcePropertiesXml;
  // inspect that source too, rather than guessing from synthetic HeadingN IDs.
  if (source != null && source.isNotEmpty) {
    _checkStyleReferences(_fragment(source), types);
  }
  _checkStyleReferences(direct, types);
  if (styles != null) {
    _validateInheritedShading(document, paragraph, direct, styles);
  }
}

void _validateInheritedShading(
  WmlDocument document,
  WmlParagraph target,
  XmlElement direct,
  XmlElement styles,
) {
  final definitions = <String, XmlElement>{
    for (final style in styles.childElements.where(
      (node) => _word(node, 'style'),
    ))
      _attribute(style, 'styleId')!: style,
  };
  void properties(XmlElement? owner) {
    if (owner == null) return;
    final pPr = _child(owner, 'pPr');
    if (pPr != null) _checkTree(pPr, validateShading: true);
  }

  final defaults = _child(styles, 'docDefaults');
  properties(defaults == null ? null : _child(defaults, 'pPrDefault'));
  void chain(String? id, {bool table = false}) {
    while (id != null) {
      final style = definitions[id];
      if (style == null) _refuse('cannot resolve the selected native style.');
      properties(style);
      if (table) {
        // Validate every paragraph packet of this table style rather than
        // guessing which unsupported conditional region Word may select.
        for (final region in style.childElements.where(
          (node) => _word(node, 'tblStylePr'),
        )) {
          _checkTree(region, validateShading: true);
        }
      }
      final parent = _child(style, 'basedOn');
      id = parent == null ? null : _attribute(parent, 'val');
    }
  }

  final selected = _child(direct, 'pStyle');
  final defaultStyle = definitions.values
      .where(
        (style) =>
            (_attribute(style, 'type') ?? 'paragraph') == 'paragraph' &&
            const {'1', 'true', 'on'}.contains(_attribute(style, 'default')),
      )
      .firstOrNull;
  chain(
    selected == null
        ? defaultStyle == null
              ? null
              : _attribute(defaultStyle, 'styleId')
        : _attribute(selected, 'val'),
  );

  void visit(Iterable<WmlBlock> blocks, List<WmlTable> tables) {
    for (final block in blocks) {
      if (identical(block, target)) {
        for (final table in tables) {
          chain(table.properties.styleId, table: true);
        }
      }
      for (final children in WordTree.childLists(block)) {
        visit(children, block is WmlTable ? [...tables, block] : tables);
      }
    }
  }

  // Headers/footers/comments are paragraph-only model stories. Body and note
  // paragraphs can inherit a table context, including nested tables/controls.
  for (final section in document.sections) {
    visit(section.blocks, []);
  }
  for (final note in [...document.footnotes, ...document.endnotes]) {
    visit(note.blocks, []);
  }
}

XmlElement? _activeStyles(WmlDocument document) {
  final package = document.package!;
  PackageRelationship? single(RelationshipCollection list, String type) {
    final matches = list.byType(type).toList(growable: false);
    if (matches.isEmpty) return null;
    if (matches.length != 1 ||
        matches.single.targetMode != RelationshipTargetMode.internal ||
        list.items.where((item) => item.id == matches.single.id).length != 1 ||
        matches.single.target.isEmpty ||
        RegExp(r'[%?#:\s\\]').hasMatch(matches.single.target)) {
      _refuse('requires unambiguous internal document/style relationships.');
    }
    return matches.single;
  }

  final office = single(
    package.packageRelationships,
    RelationshipTypes.officeDocument,
  );
  final uri = office == null
      ? '/word/document.xml'
      : package.packageRelationships.resolve(office);
  final part = package.getPart(uri);
  if (part == null) _refuse('requires its native document part.');
  final root = XmlDocument.parse(part.readText()).root;
  if (root == null || !_word(root, 'document')) {
    _refuse('requires a native Word document root.');
  }
  final relationships = package.relationshipsFor(uri);
  final reference = single(relationships, RelationshipTypes.styles);
  final styles = package.getPart(
    reference == null ? '/word/styles.xml' : relationships.resolve(reference),
  );
  if (styles == null) {
    if (reference != null) _refuse('cannot resolve its native styles part.');
    return null;
  }
  final styleRoot = XmlDocument.parse(styles.readText()).root;
  if (styles.contentType != OfficeContentTypes.wordStyles ||
      styleRoot == null ||
      !_word(styleRoot, 'styles')) {
    _refuse('requires a native styles part.');
  }
  return styleRoot;
}

String? _attribute(XmlElement element, String name) {
  final values = element.attributes.where(
    (attribute) => attribute.localName == name && attribute.namespaceUri == _w,
  );
  if (values.length > 1) _refuse('refuses duplicate native $name attributes.');
  return values.firstOrNull?.value;
}

XmlElement? _child(XmlElement element, String name) {
  final values = element.childElements.where((node) => _word(node, name));
  if (values.length > 1) _refuse('refuses duplicate native $name properties.');
  return values.firstOrNull;
}

Map<String, String> _styleTypes(XmlElement root) {
  final types = <String, String>{};
  final parents = <String, String?>{};
  var defaults = 0;
  _child(root, 'docDefaults');
  for (final style in root.childElements.where(
    (node) => _word(node, 'style'),
  )) {
    final id = _attribute(style, 'styleId');
    final type = _attribute(style, 'type') ?? 'paragraph';
    if (id == null ||
        id.isEmpty ||
        types.containsKey(id) ||
        !const {
          'paragraph',
          'character',
          'table',
          'numbering',
        }.contains(type)) {
      _refuse('requires unique native style identities of supported types.');
    }
    final flag = _attribute(style, 'default');
    if (flag != null &&
        !const {'0', '1', 'true', 'false', 'on', 'off'}.contains(flag)) {
      _refuse('refuses malformed native default-style flags.');
    }
    if (type == 'paragraph' && const {'1', 'true', 'on'}.contains(flag)) {
      defaults++;
    }
    final base = _child(style, 'basedOn');
    final baseId = base == null ? null : _attribute(base, 'val');
    if (base != null && (baseId == null || baseId.isEmpty)) {
      _refuse('requires explicit native inheritance identities.');
    }
    types[id] = type;
    parents[id] = baseId;
  }
  if (defaults > 1) _refuse('refuses ambiguous default paragraph styles.');
  for (final entry in parents.entries) {
    if (entry.value != null && types[entry.value] != types[entry.key]) {
      _refuse('requires complete same-type native inheritance.');
    }
  }
  final resolved = <String>{};
  for (final id in types.keys) {
    final chain = <String>{};
    String? current = id;
    while (current != null && !resolved.contains(current)) {
      if (!chain.add(current) || types[current] != types[id]) {
        _refuse('requires complete acyclic same-type style inheritance.');
      }
      current = parents[current];
    }
    resolved.addAll(chain);
  }
  return types;
}

void _checkStyleReferences(XmlElement node, Map<String, String> types) {
  for (final (name, expected) in [
    ('pStyle', 'paragraph'),
    ('tblStyle', 'table'),
  ]) {
    if (!_word(node, name)) continue;
    final id = _attribute(node, 'val');
    if (id == null || id.isEmpty || types[id] != expected) {
      _refuse('requires resolved native paragraph/table style references.');
    }
  }
  for (final child in node.childElements) {
    _checkStyleReferences(child, types);
  }
}

void _checkTree(
  XmlElement node, {
  bool unmodeled = false,
  bool validateShading = false,
}) {
  bool relevant(XmlElement candidate) =>
      (_word(candidate, 'pPr') || _word(candidate, 'shd')) ||
      candidate.childElements.any(relevant);
  if (((node.namespaceUri == OfficeNamespaces.mc &&
              node.localName == 'AlternateContent') ||
          node.getAttribute(
                'ProcessContent',
                namespaceUri: OfficeNamespaces.mc,
              ) !=
              null) &&
      relevant(node)) {
    _refuse('does not resolve shading in markup-compatibility alternatives.');
  }
  final unsupportedRegion =
      unmodeled ||
      _word(node, 'lvl') ||
      (_word(node, 'tblStylePr') &&
          !const {
            'wholeTable',
            'band1Horz',
            'band2Horz',
            'firstRow',
          }.contains(_attribute(node, 'type')));
  if (_word(node, 'docDefaults')) _child(node, 'pPrDefault');
  if (_word(node, 'p') || _word(node, 'style') || _word(node, 'pPrDefault')) {
    _child(node, 'pPr');
  }
  if (_word(node, 'pPr')) {
    _child(node, 'pStyle');
    final shading = _child(node, 'shd');
    if (shading != null) {
      if (unsupportedRegion) {
        _refuse(
          'does not resolve numbering or unsupported table-region shading.',
        );
      }
      if (validateShading) _checkShading(shading);
    }
  }
  if (_word(node, 'tblPr')) _child(node, 'tblStyle');
  for (final child in node.childElements) {
    _checkTree(
      child,
      unmodeled: unsupportedRegion,
      validateShading: validateShading,
    );
  }
}

void _checkShading(XmlElement shading) {
  final names = <String>{};
  for (final attribute in shading.attributes.where(
    (value) => value.namespaceUri == _w,
  )) {
    if (!names.add(attribute.localName)) {
      _refuse('refuses duplicate native shading attributes.');
    }
    if (!const {'val', 'color', 'fill'}.contains(attribute.localName)) {
      _refuse('does not resolve themed or unsupported shading attributes.');
    }
    if (attribute.localName == 'val') {
      if (attribute.value != 'clear') {
        _refuse('supports only existing clear (solid background) shading.');
      }
    } else if (attribute.value != 'auto' &&
        !RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(attribute.value)) {
      _refuse('requires valid native RGB or automatic shading colors.');
    }
  }
  if (shading.childElements.any((node) => node.namespaceUri == _w)) {
    _refuse('refuses malformed native children in shading.');
  }
}
