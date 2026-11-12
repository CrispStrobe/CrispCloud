import 'dart:convert';

import '../../opc/package_part.dart';
import '../../xml/namespaces.dart';
import '../../xml/xml_node.dart';
import '../serial/sheet_drawing_io.dart';
import 'sml_workbook.dart';

/// A checked, reversible worksheet rename. Preparing never mutates the model
/// or native XML. Stale apply/undo operations reject before writing anything.
class SheetRenameEdit {
  SheetRenameEdit._(this._book, this._changes, this._nativeChanges)
    : _before = _modelState(_book),
      _preparedPackage = _packageState(_book);

  final SmlWorkbook _book;
  final List<({void Function() apply, void Function() undo})> _changes;
  final List<_NativeRenamePart> _nativeChanges;
  final List<Object?> _before;
  final List<Object?> _preparedPackage;
  List<Object?>? _after;
  var _applied = false;

  /// Whether this changes any sheet name or reference.
  bool get isEmpty => _changes.isEmpty && _nativeChanges.isEmpty;

  /// Applies the prepared values, or redoes a previously undone rename.
  void apply() => _run(false);

  /// Restores the original reference values. Native XML changes made by an
  /// ordinary save are retained; reference slots are restored individually.
  void undo() => _run(true);

  void _run(bool reverse) {
    if (isEmpty) return;
    if (_applied != reverse ||
        !_same(_modelState(_book), reverse ? _after! : _before) ||
        (!reverse &&
            _after == null &&
            !_same(_packageState(_book), _preparedPackage))) {
      throw StateError('The prepared worksheet rename is stale');
    }
    // Parse, locate and verify every native slot before changing any field.
    final writes = [
      for (final part in _nativeChanges) part.prepare(_book, reverse),
    ];
    for (final change in reverse ? _changes.reversed : _changes) {
      if (reverse) {
        change.undo();
      } else {
        change.apply();
      }
    }
    for (final write in writes) {
      write();
    }
    _applied = !reverse;
    if (!reverse) _after ??= _modelState(_book);
  }

  static bool _same(List<Object?> a, List<Object?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // Cached values and generated OPC owner paths are intentionally excluded:
  // recalculation and saving do not change the reference edit's assumptions.
  static List<Object?> _modelState(SmlWorkbook book) => [
    book.sourceDefinedNameState,
    book.definedNameState(),
    for (final name in book.namedRanges) name,
    for (final sheet in book.sheets) ...[
      sheet,
      sheet.name,
      sheet.sheetId,
      sheet.sourceValidationState,
      sheet.validationState(),
      sheet.sourceConditionalFormatState,
      sheet.conditionalFormatState(),
      for (final rule in sheet.validations) rule,
      for (final rule in sheet.conditionalFormats) rule,
      for (final cell in sheet.allCells)
        if (cell.formula != null) ...[cell, cell.ref.a1, cell.formula],
      for (final pivot in sheet.pivots) ...[
        pivot,
        pivot.sourceSheetName,
        pivot.source.start.a1,
        pivot.source.end.a1,
        pivot.rowField,
        pivot.dataField,
      ],
      for (final drawing in sheet.drawings) ...[
        drawing,
        drawing.sourceSheetName,
        drawing.sourceChartState,
        SheetDrawingIo.chartState(drawing, sheet),
      ],
    ],
  ];

  static List<Object?> _packageState(SmlWorkbook book) => [
    book.package,
    book.package?.contentTypes.toXml(),
    book.package?.packageRelationships.toXml(),
    for (final part in book.package?.parts ?? <PackagePart>[]) ...[
      part,
      part.uri,
      part.contentType,
      book.package!.relationshipsFor(part.uri).toXml(),
      if (_xmlPart(part)) book.package!.getPart(part.uri)!.readText(),
    ],
  ];
}

class _NativeRenamePart {
  _NativeRenamePart(this.uri, this.fields, this.beforeState, this.afterState);
  final String uri;
  final List<({String key, String before, String after})> fields;
  final String beforeState;
  final String afterState;

  void Function() prepare(SmlWorkbook book, bool reverse) {
    final part = book.package?.getPart(uri);
    if (part == null) {
      throw StateError('The native rename owner is missing: $uri');
    }
    final document = XmlDocument.parse(part.readText());
    final root = document.root;
    if (root == null ||
        _nativeState(root) != (reverse ? afterState : beforeState)) {
      throw StateError('The native rename owner has newer edits: $uri');
    }
    final slots = _xmlSlots(root);
    for (final field in fields) {
      final slot = slots[field.key];
      if (slot == null ||
          slot.read() != (reverse ? field.after : field.before)) {
        throw StateError('The native reference has newer edits: $uri');
      }
    }
    for (final field in fields) {
      slots[field.key]!.write(reverse ? field.before : field.after);
    }
    final text = document.toXmlString();
    return () => part.writeText(text);
  }
}

bool _xmlPart(PackagePart part) {
  final type = part.contentType.toLowerCase();
  return type.endsWith('+xml') ||
      type == 'application/xml' ||
      type == 'text/xml' ||
      part.uri.toLowerCase().endsWith('.xml');
}

typedef _XmlSlot = ({String Function() read, void Function(String) write});

// Stable semantic keys tolerate namespace prefix/attribute-order changes and
// worksheet row/cell serialization. They do not alias repeated native owners.
Map<String, _XmlSlot> _xmlSlots(
  XmlElement root, {
  bool preserved = false,
  bool cellFormulas = true,
}) {
  String identity(XmlElement node) {
    final attributes = node.namespaceUri == OfficeNamespaces.x
        ? switch (node.localName) {
            'c' || 'row' => ['r'],
            'sheet' => ['sheetId'],
            'definedName' => ['name', 'localSheetId'],
            'conditionalFormatting' || 'dataValidation' => ['sqref'],
            'cfRule' => ['priority'],
            _ => <String>[],
          }
        : <String>[];
    return jsonEncode([
      node.namespaceUri,
      node.localName,
      for (final attribute in attributes) node.getAttribute(attribute),
    ]);
  }

  final result = <String, _XmlSlot>{};
  void visit(XmlElement node, String parent, int ordinal) {
    final x = node.namespaceUri == OfficeNamespaces.x;
    final c = node.namespaceUri == OfficeNamespaces.c;
    // The cell model is authoritative for worksheet formulas. The serializer
    // replaces sheetData, including buffered edits, removed formulas and newly
    // created cells. A native patch must not restore its older projection.
    if (!cellFormulas &&
        root.localName == 'worksheet' &&
        x &&
        node.localName == 'f' &&
        node.parent?.localName == 'c' &&
        node.parent?.parent?.localName == 'row') {
      return;
    }
    if (preserved &&
        ((node.parent == root &&
                x &&
                ((root.localName == 'worksheet' &&
                        <String>{
                          'sheetViews',
                          'cols',
                          'sheetData',
                          'sheetProtection',
                          'autoFilter',
                          'mergeCells',
                          'headerFooter',
                          'drawing',
                        }.contains(node.localName)) ||
                    (root.localName == 'workbook' &&
                        node.localName == 'sheets'))) ||
            (c && node.localName == 'numCache'))) {
      return;
    }
    final path = '$parent/${identity(node)}[$ordinal]';
    result['$path/#element'] = (read: () => '', write: (_) {});
    for (final attr in node.attributes) {
      if (attr.qualifiedName.startsWith('xmlns') ||
          attr.namespaceUri == 'http://www.w3.org/2000/xmlns/' ||
          (preserved &&
              node == root &&
              x &&
              root.localName == 'pivotCacheDefinition' &&
              attr.localName == 'refreshOnLoad')) {
        continue;
      }
      final key = '$path/@${jsonEncode([attr.namespaceUri, attr.localName])}';
      result[key] = (
        read: () => attr.value,
        write: (value) => attr.value = value,
      );
    }
    if (node.childElements.isEmpty) {
      result['$path/#text'] = (
        read: () => node.text,
        write: (value) => node.text = value,
      );
    }
    final counts = <String, int>{};
    for (final child in node.childElements) {
      final kind = identity(child);
      final index = counts[kind] ?? 0;
      counts[kind] = index + 1;
      visit(child, path, index);
    }
  }

  visit(root, '', 0);
  return result;
}

String _nativeState(XmlElement root) {
  final values = _xmlSlots(root, preserved: true);
  final keys = values.keys.toList()..sort();
  return jsonEncode([
    for (final key in keys) [key, values[key]!.read()],
  ]);
}

/// Renames local sheet qualifiers without changing formula strings, structured
/// column names, external-workbook references, or unrelated sheet names.
///
/// Native-only reference owners are rewritten with the editable projection.
/// Worksheet formula XML is published from the model by SheetSerializer.
/// Unknown reference-bearing XML, opaque executable/data-model owners, and
/// modified lossy native projections reject before any workbook mutation.
abstract final class SheetRename {
  /// Preflights every modeled and native reference before producing an edit.
  static SheetRenameEdit prepare(
    SmlWorkbook book,
    SmlWorksheet sheet,
    String name,
  ) {
    if (!book.sheets.any((other) => identical(other, sheet))) {
      throw ArgumentError('The worksheet does not belong to this workbook');
    }
    if (name.trim().isEmpty ||
        name.length > 31 ||
        RegExp(r'[\x00-\x1f\x7f\[\]:*?/\\]').hasMatch(name) ||
        name.startsWith("'") ||
        name.endsWith("'") ||
        book.sheets.any(
          (other) =>
              !identical(other, sheet) &&
              other.name.toLowerCase() == name.toLowerCase(),
        )) {
      throw ArgumentError('Invalid or duplicate worksheet name');
    }
    final old = sheet.name;
    final changes = <({void Function() apply, void Function() undo})>[];
    final nativeChanges = <_NativeRenamePart>[];
    if (name == old) return SheetRenameEdit._(book, changes, nativeChanges);
    if (book.sheets.any(
      (other) =>
          !identical(other, sheet) &&
          other.name.toLowerCase() == old.toLowerCase(),
    )) {
      throw ArgumentError('The original worksheet name is ambiguous');
    }
    bool matches(String? value) => value?.toLowerCase() == old.toLowerCase();
    String rewrite(String value) => rewriteFormula(value, old, name);
    void change<T>(T before, T after, void Function(T) set) {
      if (before == after) return;
      changes.add((apply: () => set(after), undo: () => set(before)));
    }

    for (final tab in book.sheets) {
      for (final cell in tab.allCells) {
        final formula = cell.formula;
        if (formula != null) {
          change(formula, rewrite(formula), (v) => cell.formula = v);
        }
      }
      for (final rule in tab.validations) {
        change(rule.formula1, rewrite(rule.formula1), (v) => rule.formula1 = v);
        change(rule.formula2, rewrite(rule.formula2), (v) => rule.formula2 = v);
      }
      for (final rule in tab.conditionalFormats) {
        change(rule.formula, rewrite(rule.formula), (v) => rule.formula = v);
      }
      for (final pivot in tab.pivots) {
        if (matches(pivot.sourceSheetName)) {
          change(pivot.sourceSheetName, name, (v) => pivot.sourceSheetName = v);
        }
      }
      for (final drawing in tab.drawings) {
        if (matches(drawing.sourceSheetName)) {
          change(
            drawing.sourceSheetName,
            name,
            (v) => drawing.sourceSheetName = v,
          );
        }
        if (drawing.sourceChartState != null &&
            drawing.sourceChartState ==
                SheetDrawingIo.chartState(drawing, tab)) {
          change(
            drawing.sourceChartState,
            SheetDrawingIo.chartState(
              drawing,
              tab,
              ownerName: identical(tab, sheet) ? name : tab.name,
              sourceName: matches(drawing.sourceSheetName)
                  ? name
                  : drawing.sourceSheetName,
            ),
            (v) => drawing.sourceChartState = v,
          );
        }
      }
      if (tab.sourceValidationState == tab.validationState()) {
        change(
          tab.sourceValidationState,
          tab.validationState(rewrite),
          (v) => tab.sourceValidationState = v,
        );
      }
      if (tab.sourceConditionalFormatState == tab.conditionalFormatState()) {
        change(
          tab.sourceConditionalFormatState,
          tab.conditionalFormatState(rewrite),
          (v) => tab.sourceConditionalFormatState = v,
        );
      }
    }
    for (final range in book.namedRanges) {
      if (matches(range.sheetName)) {
        change(range.sheetName, name, (v) => range.sheetName = v);
      }
    }
    if (book.sourceDefinedNameState == book.definedNameState()) {
      change(
        book.sourceDefinedNameState,
        book.definedNameState(from: old, to: name),
        (v) => book.sourceDefinedNameState = v,
      );
    }
    for (final part in book.package?.parts ?? <PackagePart>[]) {
      final uri = part.uri.toLowerCase();
      final type = part.contentType.toLowerCase();
      if (type.contains('vbaproject') ||
          type.contains('macrosheet') ||
          uri.startsWith('/xl/model/') ||
          uri.startsWith('/xl/activex/')) {
        throw UnsupportedError(
          'Cannot rename sheets with opaque executable/data-model owners: ${part.uri}',
        );
      }
      if (!(type.endsWith('+xml') ||
              type == 'application/xml' ||
              type == 'text/xml' ||
              uri.endsWith('.xml')) ||
          uri.startsWith('/docprops/') ||
          uri.endsWith('.rels')) {
        continue;
      }
      // Enumerating OPC parts does not materialize lazy archive payloads.
      final loaded = book.package!.getPart(part.uri)!;
      final document = XmlDocument.parse(loaded.readText());
      final root = document.root;
      if (root == null) throw FormatException('Missing XML root: ${part.uri}');
      // Names and formulas inside these parts belong to another workbook or
      // are user-visible string/style payloads, not local sheet references.
      if (root.namespaceUri == OfficeNamespaces.x &&
              <String>{
                'externalLink',
                'sst',
                'styleSheet',
                'theme',
              }.contains(root.localName) ||
          (root.namespaceUri == OfficeNamespaces.a &&
              root.localName == 'theme')) {
        continue;
      }
      final beforeState = _nativeState(root);
      final beforeSlots = {
        for (final slot in _xmlSlots(root, cellFormulas: false).entries)
          slot.key: slot.value.read(),
      };
      final changed = _rewriteNative(
        root,
        old,
        name,
        sheet.sheetId,
        part.uri,
        modeledCellFormulas: {
          for (final tab in book.sheets)
            if (tab.sourcePartUri == part.uri)
              for (final cell in tab.allCells)
                if (cell.formula != null && cell.formula!.isNotEmpty)
                  cell.ref.a1,
        },
      );
      if (!changed) continue;
      if (root.localName == 'workbook' &&
          root.firstChild('definedNames') != null &&
          book.sourceDefinedNameState != book.definedNameState()) {
        throw UnsupportedError(
          'Commit or reopen edited native defined names before renaming a worksheet',
        );
      }
      for (final tab in book.sheets) {
        if (tab.sourcePartUri == part.uri &&
            ((root.firstChild('dataValidations') != null &&
                    tab.sourceValidationState != tab.validationState()) ||
                (root.firstChild('conditionalFormatting') != null &&
                    tab.sourceConditionalFormatState !=
                        tab.conditionalFormatState()))) {
          throw UnsupportedError(
            'Cannot rename through an edited native rule projection',
          );
        }
        for (final drawing in tab.drawings) {
          if (drawing.sourceChartPartUri == part.uri &&
              drawing.sourceChartState !=
                  SheetDrawingIo.chartState(drawing, tab)) {
            throw UnsupportedError(
              'Cannot rename through an edited native chart projection',
            );
          }
        }
      }
      final afterSlots = _xmlSlots(root, cellFormulas: false);
      nativeChanges.add(
        _NativeRenamePart(
          part.uri,
          [
            for (final slot in afterSlots.entries)
              if (slot.value.read() != beforeSlots[slot.key])
                (
                  key: slot.key,
                  before: beforeSlots[slot.key]!,
                  after: slot.value.read(),
                ),
          ],
          beforeState,
          _nativeState(root),
        ),
      );
    }
    change(sheet.name, name, (value) => sheet.name = value);
    return SheetRenameEdit._(book, changes, nativeChanges);
  }

  /// Prepares and applies a rename; returns the exact reversible edit.
  static SheetRenameEdit rename(
    SmlWorkbook book,
    SmlWorksheet sheet,
    String name,
  ) {
    final edit = prepare(book, sheet, name);
    edit.apply();
    return edit;
  }

  /// Rewrites only local sheet qualifiers. Both endpoints of 3-D references
  /// are handled, including individually quoted and collectively quoted names.
  static String rewriteFormula(String formula, String oldName, String newName) {
    final out = StringBuffer();
    var index = 0;
    var referenceStart = -1;
    while (index < formula.length) {
      final start = index;
      if (formula[index] == '"') {
        index++;
        var closed = false;
        while (index < formula.length) {
          if (formula[index++] != '"') continue;
          if (index < formula.length && formula[index] == '"') {
            index++;
            continue;
          }
          closed = true;
          break;
        }
        if (!closed) throw FormatException('Unterminated formula string');
        out.write(formula.substring(start, index));
        continue;
      }
      final first = _name(formula, index);
      if (first != null) {
        var end = first.end;
        final names = <String>[first.value];
        // A qualified cell, full-column or full-row range endpoint is not
        // the first worksheet of a 3-D qualifier.
        final qualifiedCell = start == referenceStart;
        if (!qualifiedCell && end < formula.length && formula[end] == ':') {
          final last = _name(formula, end + 1);
          if (last != null) {
            names.add(last.value);
            end = last.end;
          }
        }
        if (end < formula.length && formula[end] == '!') {
          final external = names.any(
            (value) => value.contains('[') || value.contains(']'),
          );
          final endpoints = names.length == 1 ? names.single.split(':') : names;
          if (!external &&
              endpoints.length <= 2 &&
              !(!first.quoted && first.value.startsWith('#')) &&
              endpoints.any(
                (value) => value.toLowerCase() == oldName.toLowerCase(),
              )) {
            final renamed = endpoints
                .map(
                  (value) => value.toLowerCase() == oldName.toLowerCase()
                      ? newName
                      : value,
                )
                .join(':');
            out.write("'${renamed.replaceAll("'", "''")}'!");
          } else {
            out.write(formula.substring(start, end + 1));
          }
          index = end + 1;
          referenceStart = index;
          continue;
        }
        if (first.quoted) {
          throw FormatException('Quoted sheet name has no reference qualifier');
        }
      }
      if (formula[index] == '[') {
        var depth = 0;
        do {
          final char = formula[index++];
          if (char == "'" &&
              index < formula.length &&
              "[]#'@".contains(formula[index])) {
            index++;
            continue;
          }
          if (char == '[') depth++;
          if (char == ']') depth--;
        } while (index < formula.length && depth > 0);
        if (depth != 0) {
          throw FormatException('Unterminated structured reference');
        }
        out.write(formula.substring(start, index));
      } else if (first != null) {
        index = first.end;
        out.write(formula.substring(start, index));
      } else {
        out.write(formula[index++]);
      }
    }
    return out.toString();
  }

  static ({String value, int end, bool quoted})? _name(String text, int start) {
    if (start >= text.length) return null;
    var end = start;
    if (text[start] == "'") {
      final value = StringBuffer();
      end++;
      while (end < text.length) {
        final char = text[end++];
        if (char != "'") {
          value.write(char);
          continue;
        }
        if (end < text.length && text[end] == "'") {
          value.write("'");
          end++;
          continue;
        }
        return (value: value.toString(), end: end, quoted: true);
      }
      throw FormatException('Unterminated quoted sheet name');
    }
    if (text[start] == '[') {
      final close = text.indexOf(']', start + 1);
      if (close < 0) return null;
      end = close + 1;
    }
    while (end < text.length && !_delimiter.hasMatch(text[end])) {
      end++;
    }
    if (end == start) return null;
    return (value: text.substring(start, end), end: end, quoted: false);
  }

  static final _delimiter = RegExp(r'''[\s!"'\[\]+*/^&=<>%,;(){}:\-]''');

  static bool _rewriteNative(
    XmlElement root,
    String old,
    String name,
    int sheetId,
    String uri, {
    required Set<String> modeledCellFormulas,
  }) {
    var changed = false;
    bool matches(String? value) => value?.toLowerCase() == old.toLowerCase();
    String rewrite(String value) => rewriteFormula(value, old, name);
    void visit(XmlElement node) {
      final x = node.namespaceUri == OfficeNamespaces.x;
      final c =
          node.namespaceUri ==
          'http://schemas.openxmlformats.org/drawingml/2006/chart';
      final formula =
          (x &&
              <String>{
                'f',
                'definedName',
                'formula',
                'formula1',
                'formula2',
                'calculatedColumnFormula',
                'totalsRowFormula',
              }.contains(node.localName)) ||
          (c && node.localName == 'f');
      if (formula) {
        // Complete shared formulas are expanded by the deserializer into
        // independent model formulas. Missing masters, array ownership and
        // data-table ownership cannot be reconstructed safely on save.
        final kind = node.getAttribute('t');
        final expandedShared =
            kind == 'shared' &&
            node.getAttribute('si') != null &&
            node.parent?.localName == 'c' &&
            modeledCellFormulas.contains(node.parent?.getAttribute('r'));
        if (x &&
            node.localName == 'f' &&
            !<String?>{null, 'normal'}.contains(kind) &&
            !expandedShared) {
          throw UnsupportedError('Unmodeled native formula topology in $uri');
        }
        final next = rewrite(node.text);
        if (next != node.text) {
          if (node.childElements.isNotEmpty) {
            throw UnsupportedError('Non-scalar native formula in $uri');
          }
          node.text = next;
          changed = true;
        }
        return;
      }
      if (x &&
          node.localName == 'sheet' &&
          matches(node.getAttribute('name')) &&
          node.getAttribute('sheetId') == '$sheetId') {
        node.setAttribute('name', name);
        changed = true;
      }
      final foreign =
          x &&
          <String>{'worksheetSource', 'dataRef'}.contains(node.localName) &&
          node.getAttribute('id', namespaceUri: OfficeNamespaces.r) != null;
      for (final attr in node.attributes) {
        if (attr.namespaceUri == 'http://www.w3.org/2000/xmlns/' ||
            attr.qualifiedName.startsWith('xmlns')) {
          continue;
        }
        final sheetOwner =
            x &&
            <String>{'worksheetSource', 'dataRef'}.contains(node.localName) &&
            attr.localName == 'sheet';
        final location =
            x &&
            !foreign &&
            ((node.localName == 'hyperlink' && attr.localName == 'location') ||
                (node.localName == 'worksheetSource' &&
                    attr.localName == 'name'));
        if (sheetOwner && !foreign && matches(attr.value)) {
          attr.value = name;
          changed = true;
        } else if (location) {
          final next = rewrite(attr.value);
          if (next != attr.value) {
            attr.value = next;
            changed = true;
          }
        } else if (!foreign &&
            !_literalAttribute(node, attr) &&
            ((RegExp(
                      'formula|sheet|ref|location',
                      caseSensitive: false,
                    ).hasMatch(attr.localName) &&
                    matches(attr.value)) ||
                (_mayRefer(attr.value, old) &&
                    rewrite(attr.value) != attr.value))) {
          throw UnsupportedError(
            'Unmodeled native reference ${node.qualifiedName}/@${attr.qualifiedName} in $uri',
          );
        }
      }
      // Shared strings, inline string cells and drawing text are literal text.
      final literal =
          (x && <String>{'is', 't', 'v'}.contains(node.localName)) ||
          (node.namespaceUri == OfficeNamespaces.a && node.localName == 't') ||
          (c && node.localName == 'v');
      if (literal || foreign) return;
      if (node.childElements.isEmpty &&
          _mayRefer(node.text, old) &&
          rewrite(node.text) != node.text) {
        throw UnsupportedError(
          'Unmodeled native reference ${node.qualifiedName} in $uri',
        );
      }
      for (final child in node.childElements) {
        visit(child);
      }
    }

    visit(root);
    return changed;
  }

  static bool _literalAttribute(XmlElement node, XmlAttribute attr) {
    if (node.namespaceUri == OfficeNamespaces.x) {
      if (node.localName == 'dataValidation' &&
          <String>{
            'error',
            'errorTitle',
            'prompt',
            'promptTitle',
          }.contains(attr.localName)) {
        return true;
      }
      if (node.localName == 'hyperlink' &&
          <String>{'display', 'tooltip'}.contains(attr.localName)) {
        return true;
      }
    }
    return <String>{
          OfficeNamespaces.a,
          OfficeNamespaces.xdr,
        }.contains(node.namespaceUri) &&
        node.localName == 'cNvPr' &&
        <String>{'name', 'descr', 'title'}.contains(attr.localName);
  }

  static bool _mayRefer(String text, String name) =>
      text.contains('!') &&
      text.replaceAll("''", "'").toLowerCase().contains(name.toLowerCase());
}
