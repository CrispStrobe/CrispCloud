part of 'word_deserializer.dart';

const _paragraphBuiltins = <int, String>{
  -1: 'normal',
  -2: 'heading 1',
  -3: 'heading 2',
  -4: 'heading 3',
  -5: 'heading 4',
  -6: 'heading 5',
  -7: 'heading 6',
  -8: 'heading 7',
  -9: 'heading 8',
  -10: 'heading 9',
  -35: 'caption',
  -63: 'title',
  -75: 'subtitle',
};

// This resolver deliberately uses the operative native styles part. The UI's
// global style catalog is not evidence that a definition exists in this file.
extension _ParagraphStyleAssignment on _StyleCascade {
  void assignParagraphStyle(WmlParagraph target, {String? name, int? builtin}) {
    if ((name == null) == (builtin == null)) {
      throw ArgumentError('Use exactly one paragraph style name or builtin.');
    }
    if (name != null && !_styleText(name)) {
      throw ArgumentError(
        'Style names must be nonempty XML-safe single-line text.',
      );
    }
    if (builtin != null && !_paragraphBuiltins.containsKey(builtin)) {
      throw ArgumentError(
        'Unsupported Word paragraph style constant: $builtin',
      );
    }
    // Resolve against the same native definitions that serialization will
    // retain. A pending host-side model replacement/removal would otherwise
    // produce one cascade now and a different one after reopening the file.
    final modeledIds = <String>{};
    if (document.styles.any(
          (style) =>
              !modeledIds.add(style.id) ||
              !identical(style, document.importedStyles[style.id]),
        ) ||
        document.importedStyles.keys.any((id) => !modeledIds.contains(id))) {
      throw UnsupportedError(
        'Style assignment requires synchronized native and modeled styles.',
      );
    }
    final root = _assignmentStyles();
    final definitions = <String, XmlElement>{};
    final names = <String, String>{};
    var paragraphDefaults = 0;
    for (final definition in root.childElements.where(
      (element) => _StyleCascade._word(element, 'style'),
    )) {
      final id = _styleAttribute(definition, 'styleId');
      if (id == null || !_styleText(id) || definitions.containsKey(id)) {
        throw UnsupportedError(
          'Paragraph styles require unique native style IDs.',
        );
      }
      definitions[id] = definition;
      final type = _styleAttribute(definition, 'type') ?? 'paragraph';
      if (!const {
        'paragraph',
        'character',
        'table',
        'numbering',
      }.contains(type)) {
        throw UnsupportedError('Unsupported native style type: $type');
      }
      for (final marker in ['default', 'customStyle']) {
        final value = _styleAttribute(definition, marker);
        if (value != null && !_styleOnOff.contains(value)) {
          throw UnsupportedError('Invalid native style $marker marker.');
        }
      }
      if (type == 'paragraph' &&
          _styleEnabled(_styleAttribute(definition, 'default'))) {
        paragraphDefaults++;
      }
      final primary = _styleSingleChild(definition, 'name');
      if (primary != null) {
        final label = _styleAttribute(primary, 'val');
        if (label == null ||
            !_styleText(label) ||
            names.containsKey(label.toLowerCase())) {
          throw UnsupportedError(
            'Paragraph styles require unique primary names.',
          );
        }
        names[label.toLowerCase()] = id;
      }
      _styleSingleChild(definition, 'basedOn');
      _styleCheckProperties(_styleSingleChild(definition, 'pPr'), style: true);
      _styleCheckProperties(_styleSingleChild(definition, 'rPr'), style: true);
      for (final region in definition.childElements.where(
        (node) => _StyleCascade._word(node, 'tblStylePr'),
      )) {
        _styleCheckProperties(_styleSingleChild(region, 'pPr'), style: true);
        _styleCheckProperties(_styleSingleChild(region, 'rPr'), style: true);
      }
    }
    if (paragraphDefaults > 1) {
      throw UnsupportedError('Ambiguous default paragraph style.');
    }
    for (final entry in definitions.entries) {
      final seen = <String>{};
      var current = entry.key;
      final type = _styleAttribute(entry.value, 'type') ?? 'paragraph';
      while (true) {
        if (!seen.add(current)) {
          throw UnsupportedError('Cyclic native style inheritance.');
        }
        final definition = definitions[current];
        if (definition == null ||
            (_styleAttribute(definition, 'type') ?? 'paragraph') != type) {
          throw UnsupportedError('Missing or incompatible basedOn style.');
        }
        final base = _styleSingleChild(definition, 'basedOn');
        if (base == null) break;
        final next = _styleAttribute(base, 'val');
        if (next == null || next.isEmpty) {
          throw UnsupportedError('Missing basedOn style identity.');
        }
        current = next;
      }
    }
    final requested = (name ?? _paragraphBuiltins[builtin]!).toLowerCase();
    final id = names[requested];
    final selected = definitions[id];
    if (selected == null ||
        (_styleAttribute(selected, 'type') ?? 'paragraph') != 'paragraph') {
      throw ArgumentError('No unique native paragraph style named $requested.');
    }
    if (builtin != null &&
        _styleEnabled(_styleAttribute(selected, 'customStyle'))) {
      throw UnsupportedError(
        'A custom style cannot satisfy a Word built-in selector.',
      );
    }
    _load();
    final context = _assignmentContext(target);
    if (WordFieldSpans.unbalanced(document).isNotEmpty) {
      throw UnsupportedError(
        'Style assignment requires balanced field boundaries.',
      );
    }
    final original = target.properties;
    final sourceProperties = original.sourcePropertiesXml;
    final nativeSource = sourceProperties == null || sourceProperties.isEmpty
        ? null
        : _styleFragment(sourceProperties, 'pPr');
    _styleCheckProperties(nativeSource);
    final nativeReference = _styleSingleChild(nativeSource, 'pStyle');
    // outlineLvl may synthesize a HeadingN layout identity on import without
    // a native pStyle. Only an authored/pending style value or a source
    // reference must resolve against the real catalog.
    final imported = original.importedValues;
    final pendingStyle =
        imported == null || imported['pStyle'] != '${original.styleId}';
    final previousStyle = pendingStyle
        ? original.styleId
        : nativeReference == null
        ? null
        : _styleAttribute(nativeReference, 'val');
    if (previousStyle case final String previous) {
      if ((definitions[previous] == null) ||
          (_styleAttribute(definitions[previous]!, 'type') ?? 'paragraph') !=
              'paragraph') {
        throw UnsupportedError(
          'The current paragraph style must resolve natively.',
        );
      }
    }
    final preview = WmlClone.paragraph(target);
    // Preserve the existing pStyle packet before serialization. This operation
    // owns its native value explicitly; a generic changed-value serializer
    // would replace the packet, discarding its extension attributes/children.
    preview.properties.importedValues?['pStyle'] =
        '${preview.properties.styleId}';
    final direct = _styleFragment(
      WordSerializer().paragraphPropertiesXml(preview.properties),
      'pPr',
    );
    _styleCheckProperties(direct);
    final reference = _styleSingleChild(direct, 'pStyle');
    final styleNode =
        reference ??
        XmlElement(
          localName: 'pStyle',
          prefix: 'w',
          namespaceUri: OfficeNamespaces.w,
        );
    final oldValue = styleNode.attributes
        .where(
          (attribute) =>
              attribute.localName == 'val' &&
              attribute.namespaceUri == OfficeNamespaces.w,
        )
        .firstOrNull;
    if (oldValue == null) {
      styleNode.setAttribute('w', OfficeNamespaces.w, prefix: 'xmlns');
      styleNode.setAttribute(
        'val',
        id!,
        prefix: 'w',
        namespaceUri: OfficeNamespaces.w,
      );
    } else {
      oldValue.value = id!;
    }
    if (reference == null) direct.children.insert(0, styleNode);
    WordPropertyIo.orderChildren(direct);
    preview.properties
      ..styleId = id
      ..sourcePropertiesXml = XmlDocument(
        root: direct,
      ).toXmlString(declaration: false);
    preview.properties.importedValues = WordPropertyIo.paragraphValues(
      preview.properties,
    );
    for (final run in preview.inlines.whereType<WmlRun>()) {
      final properties = run.properties;
      final sourceProperties = properties.sourcePropertiesXml;
      if (sourceProperties != null && sourceProperties.isNotEmpty) {
        _styleCheckProperties(_styleFragment(sourceProperties, 'rPr'));
      }
      final runDirect = _styleFragment(
        WordSerializer().runPropertiesXml(properties),
        'rPr',
      );
      _styleCheckProperties(runDirect);
      if (properties.styleId case final String character) {
        final definition = definitions[character];
        if (definition == null ||
            _styleAttribute(definition, 'type') != 'character') {
          throw UnsupportedError(
            'The current character style must resolve natively.',
          );
        }
      }
      properties.sourcePropertiesXml = XmlDocument(
        root: runDirect,
      ).toXmlString(declaration: false);
      properties.importedValues = WordPropertyIo.runValues(properties);
    }
    for (final layer in context) {
      _styleCheckProperties(
        _StyleCascade._wordChild(layer, 'pPr'),
        style: true,
      );
      _styleCheckProperties(
        _StyleCascade._wordChild(layer, 'rPr'),
        style: true,
      );
    }
    paragraph(preview, context, preserveTableSpacing: false);
    final next = preview.properties;
    if (next.numId != original.numId ||
        next.ilvl != original.ilvl ||
        next.numberingSuppressed != original.numberingSuppressed ||
        (next.numId == null &&
            (next.listLabel != null || next.listRestart != null))) {
      throw UnsupportedError(
        'Paragraph Style cannot change effective numbering; use explicit list operations.',
      );
    }
    _assignmentNumberingLinks(
      original,
      next,
      previousStyle ?? defaultParagraph,
    );
    // Publishing properties preserves the live paragraph and inline identities
    // used by bookmarks, revisions and callers. The clone has the same runs.
    final preparedRuns = preview.inlines.whereType<WmlRun>().toList(
      growable: false,
    );
    final targetRuns = target.inlines.whereType<WmlRun>().toList(
      growable: false,
    );
    for (var index = 0; index < targetRuns.length; index++) {
      targetRuns[index].properties = preparedRuns[index].properties;
    }
    target.properties = next;
  }

  XmlElement _assignmentStyles() {
    final package = document.package;
    if (package == null) {
      throw UnsupportedError(
        'Paragraph Style requires an existing native styles part.',
      );
    }
    PackageRelationship single(
      RelationshipCollection relationships,
      String type,
    ) {
      final matches = relationships.byType(type).toList(growable: false);
      if (matches.length != 1 ||
          matches.single.targetMode != RelationshipTargetMode.internal ||
          relationships.items
                  .where((item) => item.id == matches.single.id)
                  .length !=
              1 ||
          matches.single.target.isEmpty ||
          RegExp(r'[%?#:\s\\]').hasMatch(matches.single.target)) {
        throw UnsupportedError(
          'Paragraph Style requires unambiguous internal document/styles relationships.',
        );
      }
      return matches.single;
    }

    final office = single(
      package.packageRelationships,
      RelationshipTypes.officeDocument,
    );
    final documentUri = package.packageRelationships.resolve(office);
    final documentPart = package.getPart(documentUri);
    if (documentPart == null) {
      throw UnsupportedError('Missing native Word document.');
    }
    final documentRoot = XmlDocument.parse(documentPart.readText()).root;
    if (documentRoot == null ||
        !_StyleCascade._word(documentRoot, 'document')) {
      throw UnsupportedError(
        'Paragraph Style requires a native Word document.',
      );
    }
    final relationships = package.relationshipsFor(documentUri);
    final styleRelationship = single(relationships, RelationshipTypes.styles);
    final part = package.getPart(relationships.resolve(styleRelationship));
    if (part == null || part.contentType != OfficeContentTypes.wordStyles) {
      throw UnsupportedError('Paragraph Style requires a native styles part.');
    }
    final root = XmlDocument.parse(part.readText()).root;
    if (root == null || !_StyleCascade._word(root, 'styles')) {
      throw UnsupportedError('Paragraph Style requires native styles XML.');
    }
    _styleCheckAlternatives(root, all: true);
    for (final stored in package.parts) {
      if (!stored.contentType.endsWith('+xml') ||
          (!stored.contentType.contains('wordprocessingml') &&
              !stored.contentType.contains('vnd.ms-word'))) {
        continue;
      }
      final xml = package.getPart(stored.uri)!.readText();
      final source = XmlDocument.parse(xml).root;
      if (source != null) {
        _styleCheckAlternatives(source);
        _styleCheckSourceTree(source);
      }
    }
    final defaults = _styleSingleChild(root, 'docDefaults');
    _styleCheckProperties(
      _styleSingleChild(_styleSingleChild(defaults, 'pPrDefault'), 'pPr'),
      style: true,
    );
    _styleCheckProperties(
      _styleSingleChild(_styleSingleChild(defaults, 'rPrDefault'), 'rPr'),
      style: true,
    );
    return root;
  }

  List<XmlElement> _assignmentContext(WmlParagraph target) {
    List<XmlElement>? context;
    var occurrences = 0;
    final containers = <WmlBlock>{};
    final runs = <WmlRun>{};
    void visit(
      Iterable<WmlBlock> blocks, [
      List<XmlElement> layers = const [],
    ]) {
      for (final block in blocks) {
        if (!containers.add(block)) {
          throw StateError(
            'Style assignment requires uniquely owned, acyclic document blocks.',
          );
        }
        if (identical(block, target)) {
          occurrences++;
          context = layers;
        }
        if (block is WmlParagraph) {
          for (final run in block.inlines.whereType<WmlRun>()) {
            if (!runs.add(run)) {
              throw StateError(
                'Style assignment requires uniquely owned run objects.',
              );
            }
          }
        }
        if (block is WmlTable) {
          final tableStyle = block.properties.styleId;
          if (tableStyle != null &&
              (styles[tableStyle] == null ||
                  _styleAttribute(styles[tableStyle]!, 'type') != 'table')) {
            throw UnsupportedError(
              'Table context requires a resolved native table style.',
            );
          }
          for (var row = 0; row < block.rows.length; row++) {
            for (final cell in block.rows[row].cells) {
              visit(cell.blocks, _tableCellLayers(block, row));
            }
          }
        } else if (block is WmlToc) {
          final paragraphs = [
            block.titleParagraph,
            ...block.itemParagraphs,
            for (final source
                in block.sourcePresentation?.paragraphs ??
                    <WmlTocSourceParagraph>[])
              source.paragraph,
          ];
          if (paragraphs.any((paragraph) => identical(paragraph, target))) {
            throw UnsupportedError(
              'Paragraph Style does not edit generated table-of-contents paragraphs.',
            );
          }
          // These runs, including the retained native cache, are live owners.
          // A body target must not alias a TOC result that would change when
          // its run is published.
          visit(paragraphs, layers);
        } else {
          for (final children in WordTree.childLists(block)) {
            visit(children, layers);
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
    if (occurrences != 1) {
      throw StateError('The paragraph must have one current document owner.');
    }
    return context!;
  }

  void _assignmentNumberingLinks(
    WmlParagraphProps before,
    WmlParagraphProps after,
    String? previousStyle,
  ) {
    if (previousStyle == after.styleId) return;
    final package = document.package!;
    final office = package.packageRelationships.firstByType(
      RelationshipTypes.officeDocument,
    )!;
    final relationships = package.relationshipsFor(
      package.packageRelationships.resolve(office),
    );
    final references = relationships
        .byType(RelationshipTypes.numbering)
        .toList();
    if (references.length > 1 ||
        references.any(
          (reference) =>
              reference.targetMode != RelationshipTargetMode.internal ||
              reference.target.isEmpty ||
              RegExp(r'[%?#:\s\\]').hasMatch(reference.target),
        )) {
      throw UnsupportedError(
        'Style assignment requires unambiguous numbering relationships.',
      );
    }
    final part = package.getPart(
      references.isEmpty
          ? '/word/numbering.xml'
          : relationships.resolve(references.single),
    );
    if (part == null) return;
    final root = XmlDocument.parse(part.readText()).root;
    if (root == null || !_StyleCascade._word(root, 'numbering')) {
      throw UnsupportedError('Style assignment requires native numbering XML.');
    }
    final active = <String>{
      if (before.numId != null) '${before.numId}',
      if (after.numId != null) '${after.numId}',
    };
    final abstractIds = <String>{};
    final instances = <String>{};
    bool hasLink(XmlElement node, {required bool activeDefinition}) {
      if (!_StyleCascade._word(node, node.localName)) return false;
      if (const {
        'pStyle',
        'styleLink',
        'numStyleLink',
      }.contains(node.localName)) {
        final style = _styleAttribute(node, 'val');
        if (activeDefinition ||
            style == previousStyle ||
            style == after.styleId) {
          return true;
        }
      }
      return node.childElements.any(
        (child) => hasLink(child, activeDefinition: activeDefinition),
      );
    }

    for (final instance in root.childElements.where(
      (node) => _StyleCascade._word(node, 'num'),
    )) {
      final id = _styleAttribute(instance, 'numId');
      if (id == null || !active.contains(id)) continue;
      if (!instances.add(id)) {
        throw UnsupportedError('Ambiguous active numbering identity.');
      }
      final reference = _styleSingleChild(instance, 'abstractNumId');
      final abstract = reference == null
          ? null
          : _styleAttribute(reference, 'val');
      if (abstract != null) abstractIds.add(abstract);
      if (hasLink(instance, activeDefinition: true)) {
        throw UnsupportedError(
          'Paragraph Style cannot change style-linked numbering.',
        );
      }
    }
    final seen = <String>{};
    for (final definition in root.childElements.where(
      (node) => _StyleCascade._word(node, 'abstractNum'),
    )) {
      final id = _styleAttribute(definition, 'abstractNumId');
      final isActive = abstractIds.contains(id);
      if (isActive && id != null && !seen.add(id)) {
        throw UnsupportedError('Ambiguous active abstract numbering identity.');
      }
      if (hasLink(definition, activeDefinition: isActive)) {
        throw UnsupportedError(
          'Paragraph Style cannot change style-linked numbering.',
        );
      }
    }
  }
}

const _styleOnOff = {'0', '1', 'true', 'false', 'on', 'off'};
bool _styleEnabled(String? value) => const {'1', 'true', 'on'}.contains(value);

bool _styleText(String value) {
  if (value.isEmpty) return false;
  for (var i = 0; i < value.length; i++) {
    final unit = value.codeUnitAt(i);
    if (unit < 32 || unit == 0xfffe || unit == 0xffff) return false;
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++i >= value.length) return false;
      final low = value.codeUnitAt(i);
      if (low < 0xdc00 || low > 0xdfff) return false;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      return false;
    }
  }
  return true;
}

String? _styleAttribute(XmlElement element, String name) {
  final matches = element.attributes
      .where(
        (attribute) =>
            attribute.localName == name &&
            attribute.namespaceUri == OfficeNamespaces.w,
      )
      .toList(growable: false);
  if (matches.length > 1) {
    throw UnsupportedError('Duplicate native style $name attribute.');
  }
  return matches.firstOrNull?.value;
}

XmlElement? _styleSingleChild(XmlElement? parent, String name) {
  final matches =
      parent?.childElements
          .where((node) => _StyleCascade._word(node, name))
          .toList(growable: false) ??
      <XmlElement>[];
  if (matches.length > 1) {
    throw UnsupportedError('Ambiguous native $name properties.');
  }
  return matches.firstOrNull;
}

XmlElement _styleFragment(String xml, String name) {
  final wrapper = XmlDocument.parse(
    '<w:context xmlns:w="${OfficeNamespaces.w}">$xml</w:context>',
  ).root!;
  final roots = wrapper.childElements.toList(growable: false);
  if (roots.length != 1 || !_StyleCascade._word(roots.single, name)) {
    throw UnsupportedError(
      'Style assignment requires native $name properties.',
    );
  }
  final root = roots.single;
  // Preserve a foreign binding on an aliased native root. Rebinding it would
  // reinterpret opaque descendant elements/attributes when the XML reopens.
  // Only materialize the wrapper's inherited native binding when absent.
  if (!root.attributes.any(
    (attribute) => attribute.prefix == 'xmlns' && attribute.localName == 'w',
  )) {
    root.setAttribute('w', OfficeNamespaces.w, prefix: 'xmlns');
  }
  return root;
}

void _styleCheckAlternatives(XmlElement node, {bool all = false}) {
  bool relevant(XmlElement candidate) =>
      (candidate.namespaceUri == OfficeNamespaces.w &&
          const {
            'p',
            'pPr',
            'rPr',
            'pStyle',
            'rStyle',
            'style',
            'styles',
          }.contains(candidate.localName)) ||
      candidate.childElements.any(relevant);
  if ((node.namespaceUri == OfficeNamespaces.mc &&
          node.localName == 'AlternateContent' &&
          (all || relevant(node))) ||
      node
              .getAttribute('ProcessContent', namespaceUri: OfficeNamespaces.mc)
              ?.trim()
              .isNotEmpty ==
          true) {
    throw UnsupportedError(
      'Style assignment cannot resolve markup-compatibility alternatives.',
    );
  }
  for (final child in node.childElements) {
    _styleCheckAlternatives(child, all: all);
  }
}

void _styleCheckSourceTree(XmlElement node) {
  if (_StyleCascade._word(node, 'p')) _styleSingleChild(node, 'pPr');
  if (_StyleCascade._word(node, 'r')) _styleSingleChild(node, 'rPr');
  for (final child in node.childElements) {
    _styleCheckSourceTree(child);
  }
}

void _styleCheckProperties(XmlElement? node, {bool style = false}) {
  if (node == null) return;
  _styleCheckAlternatives(node, all: true);
  final names = <String>{};
  for (final child in node.childElements) {
    if (child.namespaceUri != OfficeNamespaces.w) continue;
    if (!names.add(child.localName)) {
      throw UnsupportedError('Duplicate native ${child.localName} property.');
    }
    if (style && child.localName == 'pStyle') {
      throw UnsupportedError(
        'A style definition cannot replace the selected pStyle.',
      );
    }
    final val = _styleAttribute(child, 'val');
    if (const {'pStyle', 'rStyle'}.contains(child.localName) &&
        (val == null || !_styleText(val))) {
      throw UnsupportedError('Missing native style reference.');
    }
    if (const {
          'b',
          'i',
          'bCs',
          'iCs',
          'caps',
          'smallCaps',
          'strike',
          'noProof',
          'rtl',
          'cs',
          'bidi',
          'keepLines',
          'keepNext',
          'pageBreakBefore',
          'suppressAutoHyphens',
        }.contains(child.localName) &&
        val != null &&
        !_styleOnOff.contains(val)) {
      throw UnsupportedError('Invalid native ${child.localName} boolean.');
    }
    if (const {'sz', 'szCs', 'kern', 'outlineLvl'}.contains(child.localName)) {
      final number = val == null ? null : int.tryParse(val);
      if (number == null ||
          number < 0 ||
          number > 2147483647 ||
          (child.localName == 'outlineLvl' && number > 9)) {
        throw UnsupportedError('Invalid native ${child.localName} value.');
      }
    }
    if (child.localName == 'position') {
      final number =
          val == null || !RegExp(r'^[+-]?[0-9]+$').hasMatch(val.trim())
          ? null
          : int.tryParse(val.trim());
      if (number == null || number < -2147483648 || number > 2147483647) {
        throw UnsupportedError('Invalid native position value.');
      }
    }
    if (child.localName == 'spacing' || child.localName == 'ind') {
      for (final attribute in child.attributes.where(
        (value) => value.namespaceUri == OfficeNamespaces.w,
      )) {
        _styleAttribute(child, attribute.localName);
        if (attribute.localName == 'lineRule') {
          if (!const {'auto', 'exact', 'atLeast'}.contains(attribute.value)) {
            throw UnsupportedError('Invalid native line spacing rule.');
          }
        } else if (attribute.localName.endsWith('Autospacing')) {
          if (!_styleOnOff.contains(attribute.value)) {
            throw UnsupportedError('Invalid native automatic spacing.');
          }
        } else {
          final number = int.tryParse(attribute.value);
          if (number == null || number < -2147483648 || number > 2147483647) {
            throw UnsupportedError('Invalid native paragraph measurement.');
          }
        }
      }
    }
    if (child.localName == 'numPr') {
      for (final name in ['numId', 'ilvl']) {
        final value = _styleSingleChild(child, name);
        if (value == null) continue;
        final raw = _styleAttribute(value, 'val');
        final number = raw == null ? null : int.tryParse(raw);
        if (number == null ||
            number < 0 ||
            number > (name == 'ilvl' ? 8 : 2147483647)) {
          throw UnsupportedError('Invalid native numbering $name.');
        }
      }
    }
    if (child.localName == 'rPr') _styleCheckProperties(child, style: style);
  }
}
