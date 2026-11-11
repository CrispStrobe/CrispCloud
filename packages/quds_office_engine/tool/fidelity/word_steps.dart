import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/word/serial/word_property_io.dart';
import 'step_input.dart';

const _storyFields = <String>['story', 'section', 'note'];
const wordOperations = <String, List<String>>{
  'replaceText': ['paragraph', 'text', 'start', 'end', ..._storyFields],
  'heading': ['paragraph', 'level', ..._storyFields],
  'applyStyle': ['paragraph', 'style', ..._storyFields],
  'characterStyle': ['paragraph', 'run', 'style', ..._storyFields],
  'tableStyle': ['table', 'style'],
  'styleDefinition': ['style', 'type', 'rPr', 'pPr', 'tblPr', 'tcPr'],
  'paragraphFormat': [
    'paragraph',
    'alignment',
    'before',
    'after',
    'lineSpacing',
    'keepTogether',
    'pageBreakBefore',
    'rtl',
    ..._storyFields,
  ],
  'runFormat': [
    'paragraph',
    'start',
    'end',
    'bold',
    'italic',
    'color',
    'highlight',
    'font',
    'size',
    'underline',
    'strike',
    ..._storyFields,
  ],
  'addNote': ['paragraph', 'text', 'endnote', 'offset'],
  'editNote': ['id', 'text', 'endnote'],
  'deleteNote': ['id', 'endnote'],
  'imageSize': ['image', 'width', 'height', ..._storyFields],
  'imageReplace': ['image', 'file', ..._storyFields],
  'imageAdd': ['section', 'index', 'file', 'width', 'height', 'title'],
  'imageRemove': ['image', ..._storyFields],
  'paragraphInsert': ['section', 'index', 'text', 'style'],
  'paragraphSplit': ['paragraph', 'offset'],
  'paragraphDelete': ['paragraph'],
  'list': ['paragraph', 'numbered', 'level'],
  'listClear': ['paragraph'],
  'listRestart': ['paragraph', 'at'],
  'hyperlink': ['paragraph', 'run', 'target', ..._storyFields],
  'tableCellText': ['table', 'row', 'column', 'text'],
  'headerFooterText': ['section', 'story', 'paragraph', 'text'],
  'sectionFormat': [
    'section',
    'width',
    'height',
    'top',
    'bottom',
    'left',
    'right',
    'header',
    'footer',
    'columns',
    'columnSpace',
    'columnSep',
    'breakKind',
    'differentFirstPage',
    'differentOddEven',
  ],
};

/// Apply one validated word-processing operation. Indices follow inspect output.
void applyStep(
  WmlDocument doc,
  Map<String, Object?> values, {
  String? assetDirectory,
}) {
  final s = StepInput(values);
  final op = s.string('op');
  final fields = wordOperations[op];
  if (fields == null) throw ArgumentError('Unknown DOCX operation: $op');
  s.fields(fields);
  WmlParagraph paragraph() => s.item('paragraph', _paragraphs(doc, s));
  WmlSection section() => s.item('section', doc.sections, fallback: 0);
  WmlTable table() => s.item('table', _tables(doc));
  WmlVisual picture() {
    final value = s.item('image', _visuals(doc, s));
    if (!value.visual.isPicture) {
      throw ArgumentError('image must select a picture');
    }
    return value;
  }

  switch (op) {
    case 'replaceText':
      final p = paragraph();
      final range = _range(p, s);
      WmlRunEdit.replaceRange(p, range.$1, range.$2, s.string('text'));
      _noteHint(p);
    case 'heading':
      WordToc.applyHeading(paragraph(), s.integer('level', max: 9));
    case 'applyStyle':
      final style = s.string('style');
      if (WordStyles.byId(style, document: doc) == null) {
        throw ArgumentError('Unknown paragraph style: $style');
      }
      WordStyles.apply(paragraph(), style, document: doc);
    case 'characterStyle':
      final id = s.string('style');
      _sourceStyle(doc, id, 'character');
      s
              .item('run', paragraph().inlines.whereType<WmlRun>())
              .properties
              .styleId =
          id;
      WordDeserializer().refreshStyles(doc);
    case 'tableStyle':
      final id = s.string('style');
      _sourceStyle(doc, id, 'table');
      table().properties.styleId = id;
      WordDeserializer().refreshStyles(doc);
    case 'styleDefinition':
      _editStyle(doc, s);
    case 'paragraphFormat':
      final p = paragraph().properties;
      // An explicit script assignment must remain direct formatting even
      // when the requested default equals the current inherited value.
      for (final entry in <String, String>{
        'alignment': 'jc',
        'before': 'spacing',
        'after': 'spacing',
        'lineSpacing': 'spacing',
        'keepTogether': 'keepLines',
        'pageBreakBefore': 'pageBreakBefore',
        'rtl': 'bidi',
      }.entries) {
        if (s.has(entry.key)) p.importedValues?.remove(entry.value);
      }
      if (s.has('alignment')) {
        p.justification = WmlJustification.values.byName(s.string('alignment'));
      }
      if (s.has('before')) p.spacingBefore = s.number('before', min: 0);
      if (s.has('after')) p.spacingAfter = s.number('after', min: 0);
      if (s.has('lineSpacing')) {
        p.lineSpacing = s.number('lineSpacing', min: 0.01);
      }
      if (s.has('keepTogether')) p.keepTogether = s.boolean('keepTogether');
      if (s.has('pageBreakBefore')) {
        p.pageBreakBefore = s.boolean('pageBreakBefore');
      }
      if (s.has('rtl')) p.rightToLeft = s.boolean('rtl');
    case 'runFormat':
      final p = paragraph();
      final range = _range(p, s);
      if (range.$1 == range.$2) {
        throw ArgumentError('runFormat requires a non-empty text range');
      }
      WmlRunEdit.applyRange(p, range.$1, range.$2, (r) {
        for (final entry in <String, String>{
          'bold': 'b',
          'italic': 'i',
          'strike': 'strike',
          'underline': 'u',
          'color': 'color',
          'highlight': 'highlight',
          'font': 'rFonts',
          'size': 'sz',
        }.entries) {
          if (s.has(entry.key)) {
            r.importedValues?.remove(entry.value);
            r.explicitProperties.add(entry.value);
          }
        }
        if (s.has('bold')) r.bold = s.boolean('bold');
        if (s.has('italic')) r.italic = s.boolean('italic');
        if (s.has('strike')) r.strike = s.boolean('strike');
        if (s.has('underline')) {
          r.underline = WmlUnderline.values.byName(s.string('underline'));
        }
        if (s.has('color')) r.color = s.color('color');
        if (s.has('highlight')) {
          r.highlight = values['highlight'] == null
              ? null
              : s.color('highlight');
        }
        if (s.has('font')) r.asciiFont = s.string('font');
        if (s.has('size')) {
          r.fontSizeHalfPoints = (s.number('size', min: 0.5, max: 1638) * 2)
              .round();
        }
      });
    case 'addNote':
      final p = paragraph();
      final at = s.integer(
        'offset',
        fallback: p.text.length,
        max: p.text.length,
      );
      _boundary(p, at);
      WordNotes.insert(
        doc,
        p,
        endnote: s.boolean('endnote', fallback: false),
        text: s.string('text'),
      );
      final mark = p.inlines.removeLast() as WmlRun;
      WmlRunEdit.insertRuns(p, at, <WmlRun>[mark]);
      _noteHint(p);
    case 'editNote':
      final note = WordNotes.byId(
        doc,
        s.integer('id'),
        endnote: s.boolean('endnote', fallback: false),
      );
      if (note == null) throw ArgumentError('Unknown note id');
      note.text = s.string('text');
    case 'deleteNote':
      if (!WordNotes.delete(
        doc,
        s.integer('id'),
        endnote: s.boolean('endnote', fallback: false),
      )) {
        throw ArgumentError('Unknown note id');
      }
    case 'imageSize':
      final image = picture().visual;
      if (!s.has('width') && !s.has('height')) {
        throw ArgumentError('imageSize needs width or height');
      }
      if (s.has('width')) image.width = s.number('width', min: 0.01);
      if (s.has('height')) image.height = s.number('height', min: 0.01);
    case 'imageReplace':
      picture().visual.imageBytes = readPicture(s, assetDirectory);
    case 'imageAdd':
      final blocks = section().blocks;
      final at = s.integer(
        'index',
        fallback: blocks.length,
        max: blocks.length,
      );
      final visual = OfficeVisual(
        kind: OfficeVisualKind.picture,
        title: s.string('title', fallback: ''),
        imageBytes: readPicture(s, assetDirectory),
        width: s.number('width', min: 0.01),
        height: s.number('height', min: 0.01),
      );
      blocks.insert(at, WmlVisual(visual: visual));
    case 'imageRemove':
      final image = picture();
      if (!_removeVisual(doc, image)) {
        throw StateError('Picture container not found');
      }
    case 'paragraphInsert':
      final blocks = section().blocks;
      final at = s.integer(
        'index',
        fallback: blocks.length,
        max: blocks.length,
      );
      final p = WmlParagraph(
        inlines: <WmlInline>[WmlRun(text: s.string('text'))],
      );
      if (s.has('style')) {
        final id = s.string('style');
        if (WordStyles.byId(id, document: doc) == null) {
          throw ArgumentError('Unknown paragraph style: $id');
        }
        WordStyles.apply(p, id, document: doc);
      }
      blocks.insert(at, p);
    case 'paragraphSplit':
      final p = paragraph();
      final at = s.integer('offset', max: p.text.length);
      _boundary(p, at);
      final container = _container(doc, p);
      WmlRunEdit.splitAt(p, at);
      var offset = 0;
      var cut = p.inlines.length;
      for (var i = 0; i < p.inlines.length; i++) {
        if (offset >= at) {
          cut = i;
          break;
        }
        final inline = p.inlines[i];
        if (inline is WmlRun) offset += inline.text.length;
      }
      final tail = WmlParagraph(
        properties: p.properties.copy()
          ..bookmarkName = null
          ..listRestart = null,
        inlines: p.inlines.sublist(cut),
      );
      p.inlines.removeRange(cut, p.inlines.length);
      _noteHint(p);
      _noteHint(tail);
      container.insert(container.indexOf(p) + 1, tail);
    case 'paragraphDelete':
      final p = paragraph();
      final container = _container(doc, p);
      container.remove(p);
      if (container.isEmpty) container.add(WmlParagraph());
    case 'list':
      WordLists.applyLevel(
        paragraph(),
        numbered: s.boolean('numbered'),
        level: s.integer('level', fallback: 0, max: 8),
        document: doc,
      );
    case 'listClear':
      WordLists.clear(paragraph());
    case 'listRestart':
      final p = paragraph();
      if (p.properties.numId == null) {
        throw ArgumentError('Paragraph is not a list');
      }
      WordLists.restart(p, at: s.integer('at', fallback: 1));
    case 'hyperlink':
      final run = s.item('run', paragraph().inlines.whereType<WmlRun>());
      run.hyperlink = WmlHyperlink.fromTarget(s.string('target'));
    case 'tableCellText':
      final row = s.item('row', table().rows);
      final cell = s.item('column', row.cells);
      cell.blocks
        ..clear()
        ..add(
          WmlParagraph(inlines: <WmlInline>[WmlRun(text: s.string('text'))]),
        );
    case 'headerFooterText':
      final story = s.string('story');
      if (!_headerStories.contains(story)) {
        throw ArgumentError('Expected a header/footer story');
      }
      final paragraphs = _headerParagraphs(section(), story);
      final at = s.integer('paragraph', fallback: 0, max: paragraphs.length);
      if (at == paragraphs.length) paragraphs.add(WmlParagraph());
      final p = paragraphs[at];
      WmlRunEdit.replaceRange(p, 0, p.text.length, s.string('text'));
    case 'sectionFormat':
      final sec = section();
      final width = s.number('width', fallback: sec.pageSize.width, min: 1);
      final height = s.number('height', fallback: sec.pageSize.height, min: 1);
      final old = sec.margins;
      final margins = WmlPageMargins(
        top: s.number('top', fallback: old.top, min: 0),
        bottom: s.number('bottom', fallback: old.bottom, min: 0),
        left: s.number('left', fallback: old.left, min: 0),
        right: s.number('right', fallback: old.right, min: 0),
        header: s.number('header', fallback: old.header, min: 0),
        footer: s.number('footer', fallback: old.footer, min: 0),
      );
      if (margins.left + margins.right >= width ||
          margins.top + margins.bottom >= height) {
        throw ArgumentError('Margins leave no page body');
      }
      final columns = s.integer(
        'columns',
        fallback: sec.columnCount,
        min: 1,
        max: 45,
      );
      final gap = s.number('columnSpace', fallback: sec.columnSpace, min: 0);
      if (gap * (columns - 1) >= width - margins.left - margins.right) {
        throw ArgumentError('Columns leave no text width');
      }
      sec.pageSize = WmlPageSize(width: width, height: height);
      sec.margins = margins;
      sec.columnCount = columns;
      sec.columnSpace = gap;
      if (s.has('columnSep')) sec.columnSep = s.boolean('columnSep');
      if (s.has('breakKind')) {
        sec.breakKind = WmlSectionBreakKind.values.byName(
          s.string('breakKind'),
        );
      }
      if (s.has('differentFirstPage')) {
        sec.differentFirstPage = s.boolean('differentFirstPage');
      }
      if (s.has('differentOddEven')) {
        sec.differentOddEven = s.boolean('differentOddEven');
      }
  }
}

const _headerStories = <String>{
  'header',
  'footer',
  'firstHeader',
  'firstFooter',
  'evenHeader',
  'evenFooter',
};
List<WmlParagraph> _headerParagraphs(WmlSection s, String story) =>
    switch (story) {
      'header' => s.header,
      'footer' => s.footer,
      'firstHeader' => s.firstHeader,
      'firstFooter' => s.firstFooter,
      'evenHeader' => s.evenHeader,
      'evenFooter' => s.evenFooter,
      _ => throw ArgumentError('Unknown story: $story'),
    };
List<WmlVisual> _headerVisuals(WmlSection s, String story) => switch (story) {
  'header' => s.headerVisuals,
  'footer' => s.footerVisuals,
  'firstHeader' => s.firstHeaderVisuals,
  'firstFooter' => s.firstFooterVisuals,
  'evenHeader' => s.evenHeaderVisuals,
  'evenFooter' => s.evenFooterVisuals,
  _ => throw ArgumentError('Unknown story: $story'),
};
WmlNote _note(WmlDocument doc, StepInput s, String story) {
  final result = WordNotes.byId(
    doc,
    s.integer('note'),
    endnote: story == 'endnote',
  );
  if (result == null) throw ArgumentError('Unknown $story id');
  return result;
}

Iterable<WmlParagraph> _paragraphs(WmlDocument doc, StepInput s) {
  final story = s.string('story', fallback: 'body');
  if (story == 'body') return doc.paragraphs;
  if (story == 'footnote' || story == 'endnote') {
    return _note(doc, s, story).allParagraphs;
  }
  return _headerParagraphs(s.item('section', doc.sections, fallback: 0), story);
}

Iterable<WmlVisual> _visuals(WmlDocument doc, StepInput s) {
  final story = s.string('story', fallback: 'body');
  if (story == 'body') return doc.visuals;
  if (story == 'footnote' || story == 'endnote') {
    return _note(doc, s, story).visuals;
  }
  return _headerVisuals(s.item('section', doc.sections, fallback: 0), story);
}

Iterable<WmlTable> _tables(WmlDocument doc) sync* {
  Iterable<WmlTable> visit(List<WmlBlock> blocks) sync* {
    for (final block in blocks) {
      if (block is WmlTable) {
        yield block;
        for (final row in block.rows) {
          for (final cell in row.cells) {
            yield* visit(cell.blocks);
          }
        }
      } else if (block is WmlFrame) {
        yield* visit(block.blocks);
      }
    }
  }

  for (final section in doc.sections) {
    yield* visit(section.blocks);
  }
}

List<WmlBlock> _container(WmlDocument doc, WmlBlock target) {
  List<WmlBlock>? visit(List<WmlBlock> blocks) {
    if (blocks.contains(target)) return blocks;
    for (final block in blocks) {
      if (block is WmlTable) {
        for (final row in block.rows) {
          for (final cell in row.cells) {
            final found = visit(cell.blocks);
            if (found != null) return found;
          }
        }
      } else if (block is WmlFrame) {
        final found = visit(block.blocks);
        if (found != null) return found;
      }
    }
    return null;
  }

  for (final section in doc.sections) {
    final found = visit(section.blocks);
    if (found != null) return found;
  }
  for (final note in <WmlNote>[...doc.footnotes, ...doc.endnotes]) {
    final found = visit(note.blocks);
    if (found != null) return found;
  }
  throw ArgumentError('Block is not in a document story');
}

bool _removeVisual(WmlDocument doc, WmlVisual target) {
  for (final section in doc.sections) {
    for (final story in _headerStories) {
      if (_headerVisuals(section, story).remove(target)) return true;
    }
  }
  return _container(doc, target).remove(target);
}

void _noteHint(WmlParagraph p) {
  final mark = p.inlines
      .whereType<WmlRun>()
      .where((r) => r.noteRefId != null)
      .firstOrNull;
  p.properties.noteId = mark?.noteRefId;
  p.properties.endnoteRef = mark?.noteRefEndnote ?? false;
}

void _boundary(WmlParagraph p, int at) {
  final text = p.text;
  if (at > 0 &&
      at < text.length &&
      text.codeUnitAt(at - 1) >= 0xD800 &&
      text.codeUnitAt(at - 1) <= 0xDBFF &&
      text.codeUnitAt(at) >= 0xDC00 &&
      text.codeUnitAt(at) <= 0xDFFF) {
    throw ArgumentError('Offset splits a UTF-16 surrogate pair');
  }
  var position = 0;
  for (final run in p.inlines.whereType<WmlRun>()) {
    if (run.noteRefId != null &&
        at > position &&
        at < position + run.text.length) {
      throw ArgumentError('Offset splits an atomic note reference');
    }
    position += run.text.length;
  }
}

(int, int) _range(WmlParagraph p, StepInput s) {
  final start = s.integer('start', fallback: 0, max: p.text.length);
  final end = s.integer(
    'end',
    fallback: p.text.length,
    min: start,
    max: p.text.length,
  );
  _boundary(p, start);
  _boundary(p, end);
  return (start, end);
}

(PackagePart, XmlDocument) _styles(WmlDocument doc) {
  final package = doc.package;
  if (package == null) {
    throw ArgumentError('Style definitions require an imported package');
  }
  final office = package.packageRelationships.firstByType(
    RelationshipTypes.officeDocument,
  );
  final uri = office == null
      ? '/word/document.xml'
      : package.packageRelationships.resolve(office);
  final rels = package.relationshipsFor(uri);
  final rel = rels.firstByType(RelationshipTypes.styles);
  final part = package.getPart(
    rel == null ? '/word/styles.xml' : rels.resolve(rel),
  );
  if (part == null) throw ArgumentError('No styles part');
  return (part, XmlDocument.parse(part.readText()));
}

XmlElement _sourceStyle(WmlDocument doc, String id, String type) {
  final style = _styles(doc).$2.root!
      .childrenNamed('style', namespaceUri: OfficeNamespaces.w)
      .where((s) => s.getAttribute('styleId') == id)
      .firstOrNull;
  if (style == null || style.getAttribute('type') != type) {
    throw ArgumentError('Unknown $type style: $id');
  }
  return style;
}

void _editStyle(WmlDocument doc, StepInput s) {
  final source = _styles(doc);
  final style = source.$2.root!
      .childrenNamed('style', namespaceUri: OfficeNamespaces.w)
      .where((e) => e.getAttribute('styleId') == s.string('style'))
      .firstOrNull;
  if (style == null) throw ArgumentError('Unknown style id');
  if (s.has('type') && style.getAttribute('type') != s.string('type')) {
    throw ArgumentError('Style type mismatch');
  }
  for (final group in <String>['pPr', 'rPr', 'tblPr', 'tcPr']) {
    if (!s.has(group)) continue;
    var props = style.firstChild(group, namespaceUri: OfficeNamespaces.w);
    if (props == null) {
      props = _wordPropertyElement(group);
      style.addChild(props);
    }
    for (final entry in s.object(group).entries) {
      if (!RegExp(r'^[A-Za-z][A-Za-z0-9]*$').hasMatch(entry.key)) {
        throw ArgumentError('Invalid property name');
      }
      props.children.removeWhere(
        (n) =>
            n is XmlElement &&
            n.localName == entry.key &&
            n.namespaceUri == OfficeNamespaces.w,
      );
      if (entry.value == null) continue;
      final attributes = entry.value;
      if (attributes is! Map<String, Object?>) {
        throw ArgumentError('${entry.key} must be an attribute object or null');
      }
      final element = _wordPropertyElement(entry.key);
      for (final attribute in attributes.entries) {
        if (!RegExp(r'^[A-Za-z][A-Za-z0-9]*$').hasMatch(attribute.key) ||
            (attribute.value is! String &&
                attribute.value is! num &&
                attribute.value is! bool)) {
          throw ArgumentError('Invalid XML attribute ${attribute.key}');
        }
        element.setAttribute(
          attribute.key,
          '${attribute.value}',
          prefix: 'w',
          namespaceUri: OfficeNamespaces.w,
        );
      }
      props.addChild(element);
    }
    if (group == 'rPr' || group == 'pPr') WordPropertyIo.order(props);
  }
  source.$1.writeText(source.$2.toXmlString());
  WordDeserializer().refreshStyles(doc);
}

// Imported parts can use another Word prefix and bind `w` to an extension.
// Bind only generated nodes so the source's namespace scopes remain intact.
XmlElement _wordPropertyElement(String name) =>
    XmlElement(localName: name, prefix: 'w', namespaceUri: OfficeNamespaces.w)
      ..setAttribute(
        'w',
        OfficeNamespaces.w,
        prefix: 'xmlns',
        namespaceUri: 'http://www.w3.org/2000/xmlns/',
      );
