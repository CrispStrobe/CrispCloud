import 'package:quds_office_engine/quds_office_engine.dart';

import 'step_input.dart';

const _w = OfficeNamespaces.w;

Never _refuse(String reason) =>
    throw UnsupportedError('Word table cell range $reason');

/// Checks graph ownership before admission performs ordinary recursive walks.
/// The public catalog calls this for cell text and formatting operations.
void checkWordTableCellRangeOwnership(WmlDocument document) {
  _tables(document);
}

/// Replaces the text of one ordinary cell without replacing its paragraph.
///
/// This is deliberately distinct from the legacy whole-story tableCellText
/// operation. Its zero-based table selector addresses direct main-story tables
/// across sections, not the native inspector's recursive table enumeration.
/// Merged cells, nested/opaque table owners, structural markers and unsupported
/// native row/cell packets are refused before any live model is changed.
void setWordTableCellRangeText(WmlDocument document, StepInput step) {
  final text = step.string('text');
  _text(text);
  final paragraph = editableWordTableCellRangeParagraph(document, step);

  // Work on detached runs first. Neither properties nor structural ownership
  // are replaced, and rejection cannot leave a partly edited live paragraph.
  final replacement = WmlClone.paragraph(paragraph);
  if (replacement.inlines.isEmpty) {
    if (paragraph.properties.importedParagraphMark case final mark?) {
      replacement.inlines.add(WmlRun(properties: mark.copy()));
    }
  }
  WmlRunEdit.replaceRange(replacement, 0, replacement.text.length, text);
  paragraph.inlines = replacement.inlines;
}

/// Prefixes the current text of one ordinary cell without changing its range.
///
/// This operation deliberately has no offsets or alternate story selector.
/// It uses the same table/cell admission as [setWordTableCellRangeText], keeps
/// the existing text and run formatting, and leaves paragraph/cell delimiters
/// structural. Inserted text inherits the formatting at the start of the
/// current text, the first retained empty run, or the retained paragraph mark
/// when the cell has no runs.
void insertBeforeWordTableCellRange(WmlDocument document, StepInput step) {
  final text = step.string('text');
  _text(text);
  final paragraph = editableWordTableCellRangeParagraph(document, step);
  // Even an empty prefix validates the selector and its native ownership.
  // Once admitted, it must not coalesce runs or create an empty insertion run.
  if (text.isEmpty) return;

  final replacement = WmlClone.paragraph(paragraph);
  final hasText = replacement.inlines.whereType<WmlRun>().any(
    (run) => run.text.isNotEmpty,
  );
  final properties = replacement.inlines.isEmpty
      ? paragraph.properties.importedParagraphMark?.copy() ?? WmlRunProps()
      : WmlRunEdit.propsAt(replacement, hasText ? 0 : -1).copy();
  // Admission guarantees ordinary runs and insertion is always at offset
  // zero. Keep every original run, including zero-width native metadata, and
  // avoid global coalescing that could erase distinct formatting ownership.
  // A separate inserted run also preserves the original text's script routing.
  replacement.inlines.insert(0, WmlRun(text: text, properties: properties));
  paragraph.inlines = replacement.inlines;
}

/// Resolves the one ordinary paragraph of an explicitly selected table cell.
///
/// Cell text and formatting share the same ownership, source-fidelity and
/// document-protection checks. This selector never falls back to the recursive
/// body paragraph/table collections or creates a missing cell or paragraph.
WmlParagraph editableWordTableCellRangeParagraph(
  WmlDocument document,
  StepInput step,
) {
  final tableIndex = step.integer('table');
  final rowIndex = step.integer('row');
  final columnIndex = step.integer('column');
  if (document.restrictEditing ||
      document.protectionFormattingRestricted ||
      document.trackRevisions) {
    _refuse('cannot edit restricted or change-tracked documents.');
  }

  final tables = _tables(document);
  if (tableIndex >= tables.length) {
    throw ArgumentError('table is outside the direct main-story collection');
  }
  final table = tables[tableIndex];
  _rectangular(table);
  if (rowIndex >= table.rows.length || columnIndex >= table.grid.length) {
    throw ArgumentError('row or column is outside the selected table');
  }
  final cell = table.rows[rowIndex].cells[columnIndex];
  if (cell.blocks.length != 1 || cell.blocks.single is! WmlParagraph) {
    _refuse('requires one existing ordinary paragraph in the selected cell.');
  }
  final paragraph = cell.blocks.single as WmlParagraph;
  _plainParagraph(paragraph);
  _anchors(document, paragraph);
  _source(document, tables);
  return paragraph;
}

void _text(String text) {
  for (var index = 0; index < text.length; index++) {
    final unit = text.codeUnitAt(index);
    if ((unit < 0x20 && unit != 9) || unit == 0xfffe || unit == 0xffff) {
      throw ArgumentError(
        'text must be XML-safe single-paragraph text; tabs are supported, '
        'paragraph, line and cell markers are not',
      );
    }
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++index >= text.length ||
          text.codeUnitAt(index) < 0xdc00 ||
          text.codeUnitAt(index) > 0xdfff) {
        throw ArgumentError('text must contain well-formed UTF-16');
      }
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      throw ArgumentError('text must contain well-formed UTF-16');
    }
  }
}

List<WmlTable> _tables(WmlDocument document) {
  final tables = <WmlTable>[];
  final seen = Set<Object>.identity();
  void own(Object value) {
    if (!seen.add(value)) {
      _refuse('requires uniquely owned, acyclic document blocks and runs.');
    }
  }

  void visit(
    Iterable<WmlBlock> blocks, {
    bool body = false,
    bool direct = false,
  }) {
    own(blocks);
    for (final block in blocks) {
      own(block);
      if (body && block is WmlOpaqueBlock) {
        _refuse('cannot number tables through opaque main-story blocks.');
      }
      if (block is WmlParagraph) {
        own(block.inlines);
        for (final inline in block.inlines) {
          own(inline);
        }
      } else if (block is WmlTable) {
        own(block.rows);
        if (body) {
          if (!direct) {
            _refuse('cannot number nested, framed or control-wrapped tables.');
          }
          tables.add(block);
        }
        for (final row in block.rows) {
          own(row);
          own(row.cells);
          for (final cell in row.cells) {
            own(cell);
            visit(cell.blocks, body: body);
          }
        }
      } else if (block is WmlToc) {
        visit([block.titleParagraph, ...block.itemParagraphs], body: body);
      } else {
        for (final children in WordTree.childLists(block)) {
          visit(children, body: body);
        }
      }
    }
  }

  for (final section in document.sections) {
    own(section);
    visit(section.blocks, body: true, direct: true);
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
  return tables;
}

void _rectangular(WmlTable table) {
  if (table.rows.isEmpty ||
      table.grid.isEmpty ||
      table.grid.any((width) => !width.isFinite || width <= 0) ||
      table.rows.any(
        (row) =>
            row.gridBefore != 0 ||
            row.gridAfter != 0 ||
            row.cells.length != table.grid.length ||
            row.cells.any(
              (cell) => cell.gridSpan != 1 || cell.vMerge != WmlVMerge.none,
            ),
      )) {
    _refuse('requires a rectangular, unmerged table with a complete grid.');
  }
}

void _plainParagraph(WmlParagraph paragraph) {
  final props = paragraph.properties;
  if (paragraph.contentControlWrappers.isNotEmpty ||
      props.fieldInstruction != null ||
      props.fieldBegin ||
      props.fieldSeparate ||
      props.fieldEnd ||
      props.pageNumberField ||
      props.bookmarkName != null ||
      props.sourceBookmarkName != null ||
      props.noteId != null) {
    _refuse('requires cell text without fields, bookmarks, notes or controls.');
  }
  for (final inline in paragraph.inlines) {
    if (inline is! WmlRun ||
        inline.isAtomic ||
        inline.hyperlink != null ||
        inline.commentIds.isNotEmpty) {
      _refuse(
        'requires ordinary text runs without anchored or opaque content.',
      );
    }
    try {
      _text(inline.text);
    } on ArgumentError {
      _refuse('requires existing cell text without structural markers.');
    }
  }
}

void _anchors(WmlDocument document, WmlParagraph target) {
  final paragraphs = document.paragraphs.toList(growable: false);
  final targetIndex = paragraphs.indexOf(target);
  for (final revision in document.revisions) {
    if (identical(revision.targetParagraph, target) ||
        (!revision.hasCapturedTarget &&
            revision.paragraphIndex == targetIndex)) {
      _refuse('requires the cell\'s tracked changes to be resolved first.');
    }
  }
  for (final range in WordBookmarks.ranges(document)) {
    if (range.paragraphs.any((paragraph) => identical(paragraph, target))) {
      _refuse('cannot edit inside a bookmarked range.');
    }
  }
  var fieldDepth = 0;
  for (final paragraph in paragraphs) {
    if (identical(paragraph, target) && fieldDepth != 0) {
      _refuse('cannot edit inside a cross-paragraph field.');
    }
    for (final inline in paragraph.inlines.whereType<WmlFieldBoundary>()) {
      if (inline.kind == WmlFieldBoundaryKind.begin) fieldDepth++;
      if (inline.kind == WmlFieldBoundaryKind.end) {
        if (fieldDepth == 0) _refuse('requires balanced main-story fields.');
        fieldDepth--;
      }
    }
  }
  if (fieldDepth != 0) _refuse('requires balanced main-story fields.');
}

bool _word(XmlElement node, String name) =>
    node.namespaceUri == _w && node.localName == name;

void _source(WmlDocument document, List<WmlTable> tables) {
  final package = document.package;
  if (package == null) return;
  final offices = package.packageRelationships
      .byType(RelationshipTypes.officeDocument)
      .toList(growable: false);
  if (offices.length != 1 ||
      offices.single.targetMode != RelationshipTargetMode.internal ||
      package.packageRelationships.items
              .where((item) => item.id == offices.single.id)
              .length !=
          1) {
    _refuse('requires one internal native document relationship.');
  }
  final part = package.getPart(
    package.packageRelationships.resolve(offices.single),
  );
  final root = part == null ? null : XmlDocument.parse(part.readText()).root;
  if (root == null || !_word(root, 'document')) {
    _refuse('requires a native Word document part.');
  }
  final bodies = root.childrenNamed('body', namespaceUri: _w);
  if (bodies.length != 1) _refuse('requires one native main story.');
  final body = bodies.single;
  final sourceTables = <XmlElement>[];
  final openComments = <String>{};
  var fieldDepth = 0;
  void inspect(XmlElement node) {
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
      _refuse('cannot number alternate or ProcessContent table markup.');
    }
    if (_word(node, 'tbl')) {
      if (!identical(node.parent, body)) {
        _refuse('requires direct native main-story tables.');
      }
      if (openComments.isNotEmpty || fieldDepth != 0) {
        _refuse('cannot edit inside an enclosing native comment or field.');
      }
      sourceTables.add(node);
    } else if (_word(node, 'commentRangeStart')) {
      final id = node.getAttribute('id', namespaceUri: _w);
      if (id == null || !openComments.add(id)) {
        _refuse('requires unambiguous native comment ranges.');
      }
    } else if (_word(node, 'commentRangeEnd')) {
      final id = node.getAttribute('id', namespaceUri: _w);
      if (id == null || !openComments.remove(id)) {
        _refuse('requires balanced native comment ranges.');
      }
    } else if (_word(node, 'fldChar')) {
      final kind = node.getAttribute('fldCharType', namespaceUri: _w);
      if (kind == 'begin') fieldDepth++;
      if (kind == 'end') {
        if (fieldDepth == 0) _refuse('requires balanced native fields.');
        fieldDepth--;
      }
    }
    for (final child in node.childElements) {
      inspect(child);
    }
  }

  inspect(body);
  if (openComments.isNotEmpty || fieldDepth != 0) {
    _refuse('requires balanced native comment and field ranges.');
  }
  if (sourceTables.length != tables.length) {
    _refuse('requires matching native and modeled table collections.');
  }
  for (var index = 0; index < tables.length; index++) {
    _sourceTable(sourceTables[index], tables[index]);
  }
}

void _sourceTable(XmlElement source, WmlTable table) {
  _attributes(source);
  _containerText(source);
  final seen = <String>{};
  final rows = <XmlElement>[];
  for (final child in source.childElements) {
    if (_word(child, 'tr')) {
      rows.add(child);
    } else if ((_word(child, 'tblPr') || _word(child, 'tblGrid')) &&
        seen.add(child.localName)) {
      if (_word(child, 'tblGrid')) {
        _attributes(child);
        _containerText(child);
        final grid = child.childElements.toList(growable: false);
        if (grid.length != table.grid.length) {
          _refuse('requires matching native and modeled table grids.');
        }
        for (final column in grid) {
          if (!_word(column, 'gridCol')) {
            _refuse('refuses unsupported grid metadata.');
          }
          _attributes(column, word: {'w'});
          _empty(column);
          _twips(column, 'w', positive: true);
        }
      }
    } else {
      _refuse('refuses unpreserved native table structure.');
    }
  }
  if (!seen.contains('tblGrid') || rows.length != table.rows.length) {
    _refuse('requires matching native and modeled rows and a complete grid.');
  }
  for (var r = 0; r < rows.length; r++) {
    final row = rows[r];
    _attributes(row);
    _containerText(row);
    final cells = <XmlElement>[];
    var properties = false;
    for (final child in row.childElements) {
      if (_word(child, 'tc')) {
        cells.add(child);
      } else if (_word(child, 'trPr') && !properties) {
        properties = true;
        _rowProperties(child);
      } else {
        _refuse('refuses unpreserved row content or properties.');
      }
    }
    if (cells.length != table.rows[r].cells.length) {
      _refuse('requires matching native and modeled row cells.');
    }
    for (final cell in cells) {
      _attributes(cell);
      _containerText(cell);
      var properties = false;
      var paragraphs = 0;
      for (final child in cell.childElements) {
        if (_word(child, 'tcPr') && !properties) {
          properties = true;
          _cellProperties(child, table);
        } else if (_word(child, 'p')) {
          paragraphs++;
          _sourceParagraph(child);
        } else {
          _refuse('requires native cells containing ordinary paragraphs.');
        }
      }
      if (paragraphs == 0) _refuse('requires a native paragraph in each cell.');
    }
  }
}

void _rowProperties(XmlElement source) {
  _attributes(source);
  _containerText(source);
  final seen = <String>{};
  for (final child in source.childElements) {
    if (child.namespaceUri != _w || !seen.add(child.localName)) {
      _refuse('refuses ambiguous native row properties.');
    }
    if (_word(child, 'cantSplit')) {
      _attributes(child, word: {'val'});
      final value = child.getAttribute('val', namespaceUri: _w);
      if (value != null &&
          !{'1', 'true', 'on', '0', 'false', 'off'}.contains(value)) {
        _refuse('refuses unsupported row split controls.');
      }
    } else if (_word(child, 'trHeight')) {
      _attributes(child, word: {'val', 'hRule'});
      if (child.getAttribute('hRule', namespaceUri: _w) != 'atLeast') {
        _refuse('cannot preserve this native row-height rule.');
      }
      _twips(child, 'val');
    } else {
      _refuse('cannot preserve this native row property.');
    }
    _empty(child);
  }
}

void _cellProperties(XmlElement source, WmlTable table) {
  _attributes(source);
  _containerText(source);
  final seen = <String>{};
  for (final child in source.childElements) {
    if (child.namespaceUri != _w || !seen.add(child.localName)) {
      _refuse('refuses ambiguous native cell properties.');
    }
    if (_word(child, 'tcW')) {
      // The current preferred-width packet is retained separately by the model.
      _attributes(child, word: {'w', 'type'});
    } else if (_word(child, 'shd')) {
      _attributes(child, word: {'val', 'fill'});
      if (child.getAttribute('val', namespaceUri: _w) != 'clear') {
        _refuse('cannot preserve a patterned cell background.');
      }
      final fill = child.getAttribute('fill', namespaceUri: _w);
      if (fill == null ||
          !RegExp(r'^(?:[0-9a-fA-F]{6}|auto)$').hasMatch(fill)) {
        _refuse('requires a supported explicit cell background.');
      }
    } else if (_word(child, 'gridSpan')) {
      _attributes(child, word: {'val'});
      if (child.getAttribute('val', namespaceUri: _w) != '1') {
        _refuse('requires unmerged native cells.');
      }
    } else if (_word(child, 'tcBorders')) {
      _attributes(child);
      _containerText(child);
      final sides = <String>{};
      for (final side in child.childElements) {
        if (side.namespaceUri != _w ||
            !{'top', 'left', 'bottom', 'right'}.contains(side.localName) ||
            !sides.add(side.localName)) {
          _refuse('cannot preserve this native cell border.');
        }
        _attributes(side, word: {'val', 'sz', 'space', 'color'});
        final value = side.getAttribute('val', namespaceUri: _w);
        if (value != 'nil' &&
            value != 'none' &&
            (value != 'single' ||
                side.getAttribute('sz', namespaceUri: _w) !=
                    '${(table.properties.borderWidth * 8).round()}' ||
                (side.getAttribute('space', namespaceUri: _w) ?? '0') != '0' ||
                side.getAttribute('color', namespaceUri: _w) !=
                    (table.properties.borderColor ?? '000000'))) {
          _refuse('cannot preserve independent cell-border formatting.');
        }
        _empty(side);
      }
      continue;
    } else {
      _refuse('cannot preserve this native cell property.');
    }
    _empty(child);
  }
}

void _sourceParagraph(XmlElement paragraph) {
  _attributes(paragraph);
  _containerText(paragraph);
  var properties = false;
  for (final child in paragraph.childElements) {
    if (_word(child, 'pPr') && !properties) {
      properties = true;
      _propertyHistory(child);
      continue;
    }
    if (!_word(child, 'r')) {
      _refuse(
        'requires native cell paragraphs without anchored or opaque content.',
      );
    }
    _attributes(child);
    _containerText(child);
    var runProperties = false;
    for (final item in child.childElements) {
      if (_word(item, 'rPr') && !runProperties) {
        runProperties = true;
        _propertyHistory(item);
      } else if (_word(item, 't')) {
        _attributes(item, xml: {'space'});
        if (item.childElements.isNotEmpty) {
          _refuse('requires plain native text.');
        }
      } else if (_word(item, 'tab')) {
        _attributes(item);
        _empty(item);
      } else {
        _refuse(
          'requires native cell text and tabs without structural markers.',
        );
      }
    }
  }
}

void _propertyHistory(XmlElement element) {
  if (element.namespaceUri == _w &&
      (element.localName.endsWith('Change') || element.localName == 'sectPr')) {
    _refuse('refuses tracked or structural paragraph/run properties.');
  }
  for (final child in element.childElements) {
    _propertyHistory(child);
  }
}

void _twips(XmlElement element, String name, {bool positive = false}) {
  final raw = element.getAttribute(name, namespaceUri: _w);
  final value = raw == null || !RegExp(r'^\+?[0-9]+$').hasMatch(raw)
      ? null
      : int.tryParse(raw);
  if (value == null || value < (positive ? 1 : 0) || value > 2147483647) {
    _refuse('requires supported integer-twip native geometry.');
  }
}

void _attributes(
  XmlElement element, {
  Set<String> word = const {},
  Set<String> xml = const {},
}) {
  final seen = <(String, String)>{};
  for (final attribute in element.attributes) {
    if (attribute.prefix == 'xmlns' || attribute.qualifiedName == 'xmlns') {
      continue;
    }
    if (!seen.add((attribute.namespaceUri, attribute.localName)) ||
        !(attribute.namespaceUri == _w && word.contains(attribute.localName) ||
            attribute.namespaceUri == OfficeNamespaces.xml &&
                xml.contains(attribute.localName))) {
      _refuse('refuses unpreserved native structural attributes.');
    }
  }
}

void _containerText(XmlElement element) {
  for (final child in element.children) {
    final value = switch (child) {
      XmlText(:final text) => text,
      XmlCdata(:final text) => text,
      _ => '',
    };
    if (value.trim().isNotEmpty) _refuse('refuses unmodeled container text.');
  }
}

void _empty(XmlElement element) {
  _containerText(element);
  if (element.childElements.isNotEmpty) {
    _refuse('requires empty native markers.');
  }
}
