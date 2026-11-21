import 'package:quds_office_engine/quds_office_engine.dart';

import 'word_page_setup_steps.dart';

// Keep this order aligned with WordSerializer._syncHeadersFooters: the native
// writer allocates one numbered part for each nonempty story in this order.
const _stories = <String>[
  'header',
  'footer',
  'firstHeader',
  'firstFooter',
  'evenHeader',
  'evenFooter',
];

/// Resolves an existing independent paragraph story for a bounded operation.
///
/// Import can project missing primary references into copied model content;
/// save also allocates fresh story references. Neither is an implementation of
/// Word's linked-header semantics. Require direct, unique ownership instead of
/// silently editing a copy, breaking a link, or affecting an inherited story.
/// All checks precede the caller's paragraph mutation.
List<WmlParagraph> editableWordHeaderFooterParagraphs(
  WmlDocument document,
  WmlSection section,
  String story,
) {
  final paragraphs = _paragraphs(section, story);
  final index = document.sections.indexOf(section);
  if (index < 0 ||
      document.sections.where((value) => identical(value, section)).length !=
          1) {
    _refuse('requires one unambiguous section');
  }
  if (section.preservedStories.containsKey(story)) {
    _refuse('cannot edit an opaque preserved story');
  }
  if (paragraphs.isEmpty) _refuse('requires an existing paragraph story');
  _validateModelOwnership(document, paragraphs);

  final source = section.sourceProperties;
  final root = source == null ? null : XmlDocument.parse(source.xml).root;
  validateWordSectionIdentity(document, root);
  final package = document.package;
  if (package == null) {
    for (final candidate in document.sections) {
      final source = candidate.sourceProperties;
      final root = source == null ? null : XmlDocument.parse(source.xml).root;
      if (root != null && _references(root).isNotEmpty) {
        _refuse('requires the package for imported story references');
      }
    }
    _validateIndependentStories([
      for (final (i, candidate) in document.sections.indexed)
        {
          for (final name in _stories)
            if (_hasStory(candidate, name)) name: 'authored:$i:$name',
        },
    ]);
    return paragraphs;
  }

  final offices = package.packageRelationships
      .byType(RelationshipTypes.officeDocument)
      .toList();
  if (offices.length != 1 ||
      offices.single.targetMode != RelationshipTargetMode.internal ||
      package.packageRelationships.items
              .where((value) => value.id == offices.single.id)
              .length !=
          1) {
    _refuse('requires one internal document relationship');
  }
  _validateTarget(offices.single.target);
  final documentUri = package.packageRelationships.resolve(offices.single);
  final documentPart = package.getPart(documentUri);
  if (documentPart == null) _refuse('requires its native document part');
  final original = XmlDocument.parse(documentPart.readText()).root;
  if (original == null || !_word(original, 'document')) {
    _refuse('requires a native Word document');
  }
  final nativeSections = _sections(original);
  if (nativeSections.length != document.sections.length) {
    _refuse('requires matching source and modeled sections');
  }
  final relationships = package.relationshipsFor(documentUri);
  final ids = <String>{};
  for (final relationship in relationships.items) {
    if (!ids.add(relationship.id)) {
      _refuse('refuses duplicate relationship IDs');
    }
  }

  final references = <Map<String, String>>[];
  final sourceParts = <String>{};
  final referencedIds = <String>{};
  for (var i = 0; i < nativeSections.length; i++) {
    final current = document.sections[i];
    final snapshot = current.sourceProperties;
    if (snapshot == null) _refuse('requires native section source identity');
    final snapshotRoot = XmlDocument.parse(snapshot.xml).root;
    if (snapshotRoot == null || !_word(snapshotRoot, 'sectPr')) {
      _refuse('requires native section source identity');
    }
    final raw = _references(nativeSections[i]);
    final modeled = _references(snapshotRoot);
    if (raw.length != modeled.length ||
        raw.entries.any((entry) => modeled[entry.key] != entry.value)) {
      _refuse('refuses mismatched source and modeled story references');
    }
    final resolved = <String, String>{};
    for (final candidate in _stories) {
      final rid = raw[candidate];
      if (rid == null) {
        if (_hasStory(current, candidate)) {
          final type = _header(candidate)
              ? RelationshipTypes.header
              : RelationshipTypes.footer;
          if (relationships.byType(type).isNotEmpty) {
            _refuse('refuses missing or inherited source references');
          }
          // Native callers may have authored a new story in memory before
          // formatting it. With no source relationship of this family there
          // is no imported fallback or source inheritance to confuse it with.
          resolved[candidate] = 'authored:$i:$candidate';
        }
        continue;
      }
      final header = _header(candidate);
      final relationship = relationships.byId(rid);
      if (relationship == null ||
          relationship.targetMode != RelationshipTargetMode.internal ||
          relationship.type !=
              (header ? RelationshipTypes.header : RelationshipTypes.footer)) {
        _refuse('requires an internal relationship of the matching story type');
      }
      _validateTarget(relationship.target);
      final uri = relationships.resolve(relationship);
      final part = package.getPart(uri);
      if (part == null ||
          part.contentType !=
              (header
                  ? OfficeContentTypes.wordHeader
                  : OfficeContentTypes.wordFooter)) {
        _refuse('requires an existing part of the matching story type');
      }
      final storyRoot = XmlDocument.parse(part.readText()).root;
      if (storyRoot == null || !_word(storyRoot, header ? 'hdr' : 'ftr')) {
        _refuse('requires a native header/footer root');
      }
      if (!_hasStory(current, candidate)) {
        _refuse('cannot preserve an explicit empty source story');
      }
      if (!current.preservedStories.containsKey(candidate)) {
        _validateParagraphProjection(storyRoot, current, candidate);
      }
      resolved[candidate] = uri;
      sourceParts.add(uri);
      referencedIds.add(rid);
    }
    references.add(resolved);
  }
  final selectedUri = references[index][story];
  if (selectedUri == null) _refuse('requires a direct source story reference');
  _validateIndependentStories(references);
  _validateDestinations(
    document,
    package,
    documentUri,
    sourceParts,
    referencedIds,
  );
  return paragraphs;
}

Never _refuse(String reason) =>
    throw UnsupportedError('Header/footer paragraph editing $reason.');

bool _word(XmlElement element, String name) =>
    element.namespaceUri == OfficeNamespaces.w && element.localName == name;

bool _header(String story) => story.toLowerCase().endsWith('header');

List<WmlParagraph> _paragraphs(WmlSection section, String story) =>
    switch (story) {
      'header' => section.header,
      'footer' => section.footer,
      'firstHeader' => section.firstHeader,
      'firstFooter' => section.firstFooter,
      'evenHeader' => section.evenHeader,
      'evenFooter' => section.evenFooter,
      _ => throw ArgumentError('Unknown story: $story'),
    };

List<WmlVisual> _visuals(WmlSection section, String story) => switch (story) {
  'header' => section.headerVisuals,
  'footer' => section.footerVisuals,
  'firstHeader' => section.firstHeaderVisuals,
  'firstFooter' => section.firstFooterVisuals,
  'evenHeader' => section.evenHeaderVisuals,
  'evenFooter' => section.evenFooterVisuals,
  _ => throw ArgumentError('Unknown story: $story'),
};

bool _hasStory(WmlSection section, String story) =>
    _paragraphs(section, story).isNotEmpty ||
    _visuals(section, story).isNotEmpty ||
    section.preservedStories.containsKey(story);

void _validateModelOwnership(
  WmlDocument document,
  List<WmlParagraph> selected,
) {
  Iterable<Object> mutableObjects(WmlParagraph paragraph) sync* {
    yield paragraph;
    yield paragraph.inlines;
    yield paragraph.properties;
    if (paragraph.properties.importedParagraphMark case final mark?) {
      yield mark;
    }
    for (final inline in paragraph.inlines) {
      if (inline is WmlRun) {
        yield inline;
        yield inline.properties;
      } else if (inline is WmlNoteMarker) {
        yield inline.properties;
      }
    }
  }

  final targets = Set<Object>.identity()
    ..addAll(selected.expand(mutableObjects));
  final seen = Set<Object>.identity();
  final all = <WmlParagraph>[
    ...document.paragraphs,
    for (final section in document.sections)
      for (final story in _stories) ..._paragraphs(section, story),
    for (final note in [...document.footnotes, ...document.endnotes])
      ...note.allParagraphs,
    for (final comment in document.comments) ...comment.paragraphs,
  ];
  for (final paragraph in all) {
    for (final object in mutableObjects(paragraph)) {
      if (targets.contains(object) && !seen.add(object)) {
        _refuse('refuses shared mutable paragraph, inline, or property models');
      }
    }
  }
}

void _validateIndependentStories(List<Map<String, String>> sections) {
  final parts = <String>{};
  final previous = <String>{};
  for (final section in sections) {
    for (final story in _stories) {
      final uri = section[story];
      if (uri == null) {
        if (previous.contains(story)) {
          _refuse('cannot preserve inherited story linkage in another section');
        }
      } else {
        if (!parts.add(uri)) {
          _refuse('cannot preserve a part shared by multiple story references');
        }
        previous.add(story);
      }
    }
  }
}

List<XmlElement> _sections(XmlElement document) {
  final bodies = document.childrenNamed(
    'body',
    namespaceUri: OfficeNamespaces.w,
  );
  if (bodies.length != 1) _refuse('requires one native document body');
  final body = bodies.single;
  final result = <XmlElement>[];
  void visit(XmlElement node) {
    if (_word(node, 'sectPrChange') || _word(node, 'pPrChange')) return;
    if (_word(node, 'sectPr')) {
      final parent = node.parent;
      final paragraph = parent?.parent;
      if (!identical(parent, body) &&
          !(parent != null &&
              _word(parent, 'pPr') &&
              paragraph != null &&
              _word(paragraph, 'p') &&
              identical(paragraph.parent, body))) {
        _refuse('refuses ambiguous current section positions');
      }
      result.add(node);
      return;
    }
    for (final child in node.childElements) {
      visit(child);
    }
  }

  visit(document);
  return result;
}

Map<String, String> _references(XmlElement section) {
  if (!_word(section, 'sectPr')) _refuse('requires native section properties');
  final result = <String, String>{};
  for (final reference in section.childElements) {
    final header = _word(reference, 'headerReference');
    if (!header && !_word(reference, 'footerReference')) continue;
    _attributes(
      reference,
      allowed: {
        OfficeNamespaces.w: {'type'},
        OfficeNamespaces.r: {'id'},
      },
    );
    _empty(reference);
    final types = reference.attributes.where(
      (value) =>
          value.namespaceUri == OfficeNamespaces.w && value.localName == 'type',
    );
    final ids = reference.attributes.where(
      (value) =>
          value.namespaceUri == OfficeNamespaces.r && value.localName == 'id',
    );
    if (types.length != 1 || ids.length != 1 || ids.single.value.isEmpty) {
      _refuse('requires unambiguous native type and relationship attributes');
    }
    final family = header ? 'Header' : 'Footer';
    final story = switch (types.single.value) {
      'default' => header ? 'header' : 'footer',
      'first' => 'first$family',
      'even' => 'even$family',
      _ => _refuse('refuses an unsupported header/footer reference type'),
    };
    if (result.containsKey(story)) {
      _refuse('refuses duplicate story references');
    }
    result[story] = ids.single.value;
  }
  return result;
}

void _validateTarget(String target) {
  // Percent escapes, fragments and URI schemes have no faithful alias model in
  // OpcUris. Ordinary relative/absolute part paths (including dot segments) do.
  if (target.isEmpty || RegExp(r'[%?#:\s\\]').hasMatch(target)) {
    _refuse('refuses ambiguous relationship target syntax');
  }
}

void _validateParagraphProjection(
  XmlElement root,
  WmlSection section,
  String story,
) {
  void compatibility(XmlElement node) {
    if (node.namespaceUri == OfficeNamespaces.mc &&
            node.localName == 'AlternateContent' ||
        (node
                .getAttribute(
                  'ProcessContent',
                  namespaceUri: OfficeNamespaces.mc,
                )
                ?.trim()
                .isNotEmpty ??
            false)) {
      _refuse('refuses alternate or ProcessContent story markup');
    }
    for (final child in node.childElements) {
      compatibility(child);
    }
  }

  compatibility(root);
  final children = root.childElements.toList();
  if (children.any((child) => !_word(child, 'p')) ||
      children.length != _paragraphs(section, story).length ||
      _visuals(section, story).isNotEmpty) {
    _refuse('requires a faithful direct paragraph-only story projection');
  }
  _attributes(root);
  _containerText(root);
  for (final paragraph in children) {
    _attributes(paragraph);
    _containerText(paragraph);
    var properties = false;
    for (final child in paragraph.childElements) {
      if (_word(child, 'pPr') && !properties) {
        properties = true;
        // Property fragments are retained verbatim by sparse property I/O.
        // They do not authorize additional paragraph/run structure, though.
        continue;
      }
      if (!_word(child, 'r')) {
        _refuse('requires native paragraph/run text without unmodeled content');
      }
      _attributes(child);
      _containerText(child);
      var runProperties = false;
      for (final item in child.childElements) {
        if (_word(item, 'rPr') && !runProperties) {
          runProperties = true;
          continue;
        }
        if (_word(item, 't')) {
          _attributes(
            item,
            allowed: {
              OfficeNamespaces.xml: {'space'},
            },
          );
          final space = item.getAttribute(
            'space',
            namespaceUri: OfficeNamespaces.xml,
          );
          if (space != null && space != 'preserve' && space != 'default') {
            _refuse('refuses an unsupported text whitespace mode');
          }
          if (item.childElements.isNotEmpty) {
            _refuse('requires text elements without nested content');
          }
        } else if (_word(item, 'tab') ||
            _word(item, 'cr') ||
            _word(item, 'softHyphen') ||
            _word(item, 'noBreakHyphen')) {
          _attributes(item);
          _empty(item);
        } else if (_word(item, 'br')) {
          _attributes(
            item,
            allowed: {
              OfficeNamespaces.w: {'type'},
            },
          );
          final type = item.getAttribute(
            'type',
            namespaceUri: OfficeNamespaces.w,
          );
          if (type != null &&
              !const {'textWrapping', 'page', 'column'}.contains(type)) {
            _refuse('refuses an unsupported native break type');
          }
          _empty(item);
        } else {
          _refuse('requires native run text, tabs, and supported breaks');
        }
      }
    }
  }
}

void _attributes(
  XmlElement element, {
  Map<String, Set<String>> allowed = const {},
}) {
  final names = <(String, String)>{};
  for (final attribute in element.attributes) {
    if (attribute.prefix == 'xmlns' ||
        attribute.prefix.isEmpty && attribute.localName == 'xmlns') {
      continue;
    }
    if (!(allowed[attribute.namespaceUri]?.contains(attribute.localName) ??
            false) ||
        !names.add((attribute.namespaceUri, attribute.localName))) {
      _refuse('refuses unpreserved or ambiguous story content attributes');
    }
  }
}

void _containerText(XmlElement element) {
  for (final child in element.children) {
    final text = switch (child) {
      XmlText(:final text) => text,
      XmlCdata(:final text) => text,
      _ => '',
    };
    if (text.trim().isNotEmpty) _refuse('refuses unmodeled container text');
  }
}

void _empty(XmlElement element) {
  _containerText(element);
  if (element.childElements.isNotEmpty) {
    _refuse('requires empty native markers');
  }
}

void _validateDestinations(
  WmlDocument document,
  OpcPackage package,
  String documentUri,
  Set<String> sourceParts,
  Set<String> referencedIds,
) {
  final destinations = <String>{};
  var next = 1;
  for (final (index, section) in document.sections.indexed) {
    for (final story in _stories) {
      if (!_hasStory(section, story) &&
          !(index == 0 && story == 'header' && document.watermark.isNotEmpty)) {
        continue;
      }
      final header = _header(story);
      final uri = OpcUris.resolve(
        documentUri,
        '${header ? 'header' : 'footer'}${next++}.xml',
      );
      destinations.add(uri);
      final existing = package.getPart(uri);
      if (existing != null &&
          (!sourceParts.contains(uri) ||
              existing.contentType !=
                  (header
                      ? OfficeContentTypes.wordHeader
                      : OfficeContentTypes.wordFooter))) {
        _refuse('cannot overwrite an unrelated package part during story save');
      }
    }
  }
  for (final owner in ['/', ...package.partNames]) {
    final relationships = owner == '/'
        ? package.packageRelationships
        : package.relationshipsFor(owner);
    for (final relationship in relationships.items) {
      if (relationship.targetMode != RelationshipTargetMode.internal ||
          !destinations.contains(relationships.resolve(relationship))) {
        continue;
      }
      if (owner != documentUri || !referencedIds.contains(relationship.id)) {
        _refuse(
          'cannot rewrite story parts referenced by unrelated package content',
        );
      }
    }
  }
}
