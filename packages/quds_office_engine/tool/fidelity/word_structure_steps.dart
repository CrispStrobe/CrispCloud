import 'package:quds_office_engine/quds_office_engine.dart';

import 'step_input.dart';
import 'table_selector.dart';

/// Structural commands use body indexes exposed by `inspect`. They validate
/// before mutating and reject unsupported merged-grid surgery explicitly.
const wordStructureOperations = <String, List<String>>{
  'tableAdd': ['section', 'index', 'rows', 'columns', 'width'],
  'tableFormat': [
    'table',
    'alignment',
    'rtl',
    'borders',
    'borderColor',
    'borderWidth',
  ],
  'tableRowInsert': ['table', 'row'],
  'tableRowDelete': ['table', 'row'],
  'tableColumnInsert': ['table', 'column'],
  'tableColumnDelete': ['table', 'column'],
  'tableMerge': ['table', 'row', 'column', 'endRow', 'endColumn'],
  'tableUnmerge': ['table', 'row', 'column', 'gridColumn'],
  'tableRowFormat': ['table', 'row', 'height', 'cantSplit'],
  'tableCellFormat': ['table', 'row', 'column', 'gridColumn', 'fill', 'width'],
  'tocAdd': [
    'section',
    'index',
    'title',
    'minLevel',
    'maxLevel',
    'showPageNumbers',
  ],
  'tocUpdate': ['toc', 'title', 'minLevel', 'maxLevel', 'showPageNumbers'],
  'tocRemove': ['toc'],
  'bookmarkSet': ['paragraph', 'name'],
  'reference': ['paragraph', 'bookmark'],
  'commentAdd': [
    'paragraph',
    'start',
    'end',
    'text',
    'author',
    'initials',
    'date',
  ],
  'commentReply': ['id', 'text', 'author', 'initials', 'date'],
  'commentEdit': ['id', 'text'],
  'commentResolve': ['id', 'resolved'],
  'commentDelete': ['id'],
  'imageWrap': [
    'image',
    'wrap',
    'top',
    'bottom',
    'left',
    'right',
    'rotation',
    'altTitle',
    'altDescription',
  ],
  'frameAdd': [
    'section',
    'index',
    'text',
    'x',
    'y',
    'width',
    'height',
    'anchor',
    'wrap',
    'fill',
    'stroke',
  ],
  'frameFormat': [
    'frame',
    'x',
    'y',
    'width',
    'height',
    'anchor',
    'wrap',
    'fill',
    'stroke',
  ],
  'frameRemove': ['frame'],
};

Iterable<WmlBlock> bodyBlocks(WmlDocument doc) sync* {
  for (final section in doc.sections) {
    yield* WordTree.descendants(section.blocks);
  }
}

void applyWordStructureStep(WmlDocument doc, Map<String, Object?> values) {
  final s = StepInput(values);
  final op = s.string('op');
  final fields = wordStructureOperations[op];
  if (fields == null) throw ArgumentError('Unknown DOCX operation: $op');
  s.fields(fields);
  WmlParagraph paragraph() => s.item('paragraph', doc.paragraphs);
  WmlTable table() => s.item('table', bodyBlocks(doc).whereType<WmlTable>());
  WmlComment comment() {
    final found = WordComment.byId(doc, s.integer('id'));
    if (found == null) throw ArgumentError('Unknown comment id');
    return found;
  }

  void insert(WmlBlock block) {
    final blocks = s.item('section', doc.sections, fallback: 0).blocks;
    final at = s.integer('index', fallback: blocks.length, max: blocks.length);
    blocks.insert(at, block);
  }

  WmlComment makeComment({int? parentId}) {
    final date = s.string('date', fallback: '');
    if (date.isNotEmpty && DateTime.tryParse(date) == null) {
      throw ArgumentError('date must be an ISO-8601 timestamp');
    }
    return WmlComment(
      id: WordComment.nextId(doc),
      text: s.string('text'),
      author: s.string('author', fallback: 'Quds Office'),
      initials: s.string('initials', fallback: 'QO'),
      dateIso: date,
      parentId: parentId,
    );
  }

  switch (op) {
    case 'tableAdd':
      final rows = s.integer('rows', min: 1, max: 1000);
      final columns = s.integer('columns', min: 1, max: 63);
      final width = s.number('width', min: 1);
      insert(
        WmlTable(
          grid: List<double>.filled(columns, width / columns, growable: true),
          rows: [
            for (var r = 0; r < rows; r++)
              WmlTableRow(
                cells: [
                  for (var c = 0; c < columns; c++)
                    WordTable.emptyCell()..width = width / columns,
                ],
              ),
          ],
        ),
      );
    case 'tableFormat':
      final t = table();
      final p = t.properties.copy();
      if (s.has('alignment')) {
        p.alignment = WmlJustification.values.byName(s.string('alignment'));
        p.importedValues?.remove('jc');
      }
      if (s.has('rtl')) {
        p.rightToLeft = s.boolean('rtl');
        p.importedValues?.remove('bidiVisual');
      }
      if (s.has('borders')) p.borders = s.boolean('borders');
      if (s.has('borderColor')) p.borderColor = s.color('borderColor');
      if (s.has('borderWidth')) {
        p.borderWidth = s.number('borderWidth', min: 0.25, max: 12);
      }
      if (s.has('borders') || s.has('borderColor') || s.has('borderWidth')) {
        p.importedValues?.remove('tblBorders');
      }
      t.properties = p;
    case 'tableRowInsert':
    case 'tableRowDelete':
    case 'tableColumnInsert':
    case 'tableColumnDelete':
      final t = table();
      _plainGrid(t);
      final isRow = op.startsWith('tableRow');
      final adding = op.endsWith('Insert');
      final count = isRow ? t.rows.length : WordTable.columnCount(t);
      final at = s.integer(
        isRow ? 'row' : 'column',
        max: adding ? count : count - 1,
      );
      if (!adding && count == 1) {
        throw ArgumentError('Cannot delete the final table row or column');
      }
      if (!adding) {
        final cells = isRow
            ? t.rows[at].cells
            : t.rows.map((row) => row.cells[at]);
        _checkBookmarkRemoval(
          doc,
          _removedParagraphs(cells.expand((cell) => cell.blocks)),
        );
      }
      if (isRow) {
        if (adding) {
          WordTable.insertRow(t, at);
        } else {
          WordTable.deleteRow(t, at);
        }
      } else {
        if (adding) {
          WordTable.insertColumn(t, at);
        } else {
          WordTable.deleteColumn(t, at);
        }
      }
    case 'tableMerge':
      final t = table();
      final row = s.integer('row', max: t.rows.length - 1);
      final col = s.integer('column', max: WordTable.columnCount(t) - 1);
      final endRow = s.integer('endRow', min: row, max: t.rows.length - 1);
      final endCol = s.integer(
        'endColumn',
        min: col,
        max: WordTable.columnCount(t) - 1,
      );
      if (!WordTable.canMerge(t, row, col, endRow, endCol)) {
        throw ArgumentError('Range cannot be merged');
      }
      WordTable.merge(t, row, col, endRow, endCol);
    case 'tableUnmerge':
      final t = table();
      final selected = selectTableCell(t, s);
      if (!WordTable.canUnmerge(t, selected.row, selected.column)) {
        throw ArgumentError('Cell is not merged');
      }
      WordTable.unmerge(t, selected.row, selected.column);
    case 'tableRowFormat':
      final row = s.item('row', table().rows);
      final height = s.has('height')
          ? s.number('height', min: 0.05)
          : row.height;
      final cantSplit = s.boolean('cantSplit', fallback: row.cantSplit);
      row
        ..height = height
        ..cantSplit = cantSplit;
    case 'tableCellFormat':
      final cell = selectTableCell(table(), s).cell;
      final fill = s.has('fill')
          ? (values['fill'] == null ? null : s.color('fill'))
          : cell.fillColor;
      final width = s.has('width') ? s.number('width', min: 0.05) : cell.width;
      cell
        ..fillColor = fill
        ..width = width;
    case 'tocAdd':
      final toc = WmlToc();
      _configureToc(toc, s);
      insert(toc);
      WordToc.refresh(toc, doc);
    case 'tocUpdate':
      final toc = s.item('toc', WordToc.tocs(doc));
      WordToc.assertCanRefresh(toc);
      _configureToc(toc, s);
      WordToc.refresh(toc, doc);
    case 'tocRemove':
      final toc = s.item('toc', WordToc.tocs(doc));
      final location = WordTree.locate(doc, toc);
      if (location == null) {
        throw ArgumentError('TOC is not attached to an editable block owner');
      }
      final removed = _removedParagraphs([toc]);
      _checkBookmarkRemoval(doc, removed);
      if (doc.revisions.any(
        (revision) =>
            revision.accepted == null &&
            removed.contains(WordRevisions.resolveParagraph(doc, revision)),
      )) {
        throw ArgumentError(
          'Resolve tracked changes in the TOC before removing it',
        );
      }
      location.parent.removeAt(location.index);
    case 'bookmarkSet':
      final p = paragraph();
      final name = s.string('name');
      if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]{0,39}$').hasMatch(name)) {
        throw ArgumentError('Invalid bookmark name');
      }
      final native = WordBookmarks.byName(doc, name);
      if (native != null && !identical(native.startParagraph, p)) {
        throw ArgumentError('Bookmark name already exists');
      }
      if (doc.paragraphs.any(
        (other) =>
            !identical(other, p) && other.properties.bookmarkName == name,
      )) {
        throw ArgumentError('Bookmark name already exists');
      }
      final old = p.properties.bookmarkName;
      if (old != null && old != name) {
        throw ArgumentError(
          'Replacing an existing bookmark is unsupported; references may depend on it',
        );
      }
      p.properties.bookmarkName = name;
    case 'reference':
      final p = paragraph();
      final name = s.string('bookmark');
      final native = WordBookmarks.byName(doc, name);
      final target = WordBookmarks.paragraphByName(doc, name);
      if (target == null ||
          identical(target, p) ||
          (native?.paragraphs.contains(p) ?? false)) {
        throw ArgumentError('Reference requires a distinct existing bookmark');
      }
      WordFields.stamp(
        p,
        WmlFieldKind.ref,
        argument: name,
        result: WordBookmarks.textByName(doc, name)!,
      );
    case 'commentAdd':
      final p = paragraph();
      final start = s.integer('start', fallback: 0, max: p.text.length);
      final end = s.integer(
        'end',
        fallback: p.text.length,
        min: start,
        max: p.text.length,
      );
      if (start == end) {
        throw ArgumentError('Comment requires a non-empty anchor range');
      }
      _boundary(p, start);
      _boundary(p, end);
      final added = makeComment();
      WordComment.applyRange(p, start, end, added.id);
      doc.comments.add(added);
    case 'commentReply':
      final root = WordComment.threadRootId(doc, comment().id);
      doc.comments.add(makeComment(parentId: root));
    case 'commentEdit':
      comment().text = s.string('text');
    case 'commentResolve':
      comment().resolved = s.boolean('resolved');
    case 'commentDelete':
      WordComment.removeId(doc, comment().id);
    case 'imageWrap':
      final visual = s.item('image', doc.visuals).visual;
      if (!visual.isPicture) throw ArgumentError('image must select a picture');
      final p = visual.picture.copy();
      if (s.has('wrap')) p.wrap = PictureWrap.values.byName(s.string('wrap'));
      if (s.has('top')) p.wrapDistT = s.number('top', min: 0);
      if (s.has('bottom')) p.wrapDistB = s.number('bottom', min: 0);
      if (s.has('left')) p.wrapDistL = s.number('left', min: 0);
      if (s.has('right')) p.wrapDistR = s.number('right', min: 0);
      if (s.has('rotation')) {
        p.rotationDeg = s.number('rotation', min: -360, max: 360);
      }
      if (s.has('altTitle')) p.altTitle = s.string('altTitle');
      if (s.has('altDescription')) {
        p.altDescription = s.string('altDescription');
      }
      visual.picture = p;
    case 'frameAdd':
      final frame = WmlFrame(
        blocks: [
          WmlParagraph(inlines: [WmlRun(text: s.string('text'))]),
        ],
      );
      _configureFrame(frame, s);
      insert(frame);
    case 'frameFormat':
      _configureFrame(
        s.item('frame', bodyBlocks(doc).whereType<WmlFrame>()),
        s,
      );
    case 'frameRemove':
      final frame = s.item('frame', bodyBlocks(doc).whereType<WmlFrame>());
      final location = WordTree.locate(doc, frame);
      if (location == null) throw StateError('Frame container not found');
      location.parent.removeAt(location.index);
  }
}

Set<WmlParagraph> _removedParagraphs(Iterable<WmlBlock> blocks) => {
  ...WordTree.paragraphs(blocks),
  // A field-only native TOC paragraph has no live title/item counterpart.
  // Bookmark pairing binds its endpoints to this retained source paragraph.
  for (final toc in WordTree.descendants(blocks).whereType<WmlToc>())
    for (final source
        in toc.sourcePresentation?.paragraphs ?? <WmlTocSourceParagraph>[])
      source.paragraph,
};

void _checkBookmarkRemoval(WmlDocument doc, Set<WmlParagraph> removed) {
  if (WordBookmarks.ranges(doc).any(
    (range) =>
        removed.contains(range.startParagraph) !=
        removed.contains(range.endParagraph),
  )) {
    throw ArgumentError(
      'Removing these blocks would orphan a cross-paragraph bookmark endpoint',
    );
  }
}

void _plainGrid(WmlTable t) {
  final columns = WordTable.columnCount(t);
  if (t.rows.any(
    (r) =>
        r.cells.length != columns ||
        r.cells.any((c) => c.gridSpan != 1 || c.vMerge != WmlVMerge.none),
  )) {
    throw ArgumentError(
      'Unmerge the table before inserting/deleting rows or columns',
    );
  }
}

void _configureToc(WmlToc toc, StepInput s) {
  final min = s.integer('minLevel', fallback: toc.minLevel, min: 1, max: 9);
  final max = s.integer('maxLevel', fallback: toc.maxLevel, min: min, max: 9);
  final title = s.string('title', fallback: toc.title);
  final pages = s.boolean('showPageNumbers', fallback: toc.showPageNumbers);
  toc
    ..minLevel = min
    ..maxLevel = max
    ..showPageNumbers = pages
    ..title = title;
  if (s.has('showPageNumbers')) {
    // An explicit toggle applies to all levels. Preserve imported partial
    // suppression only when the operation did not change page visibility.
    toc
      ..omitPageNumbersFromLevel = null
      ..omitPageNumbersThroughLevel = null;
  }
  WmlRunEdit.replaceRange(
    toc.titleParagraph,
    0,
    toc.titleParagraph.text.length,
    title,
  );
}

void _configureFrame(WmlFrame f, StepInput s) {
  final x = s.number('x', fallback: f.x);
  final y = s.number('y', fallback: f.y);
  final width = s.number('width', fallback: f.width, min: 0.05);
  final height = s.number('height', fallback: f.height, min: 0.05);
  final anchor = s.has('anchor')
      ? WmlFrameAnchor.values.byName(s.string('anchor'))
      : f.anchor;
  final wrap = s.has('wrap')
      ? WmlFrameWrap.values.byName(s.string('wrap'))
      : f.wrap;
  final fill = s.has('fill')
      ? (s.values['fill'] == null ? null : s.color('fill'))
      : f.fillColor;
  final stroke = s.has('stroke')
      ? (s.values['stroke'] == null ? null : s.color('stroke'))
      : f.strokeColor;
  f
    ..x = x
    ..y = y
    ..width = width
    ..height = height
    ..anchor = anchor
    ..wrap = wrap
    ..fillColor = fill
    ..strokeColor = stroke;
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
  var offset = 0;
  for (final run in p.inlines.whereType<WmlRun>()) {
    if (run.isAtomic && at > offset && at < offset + run.text.length) {
      throw ArgumentError('Offset splits an atomic note or field result');
    }
    offset += run.text.length;
  }
}
