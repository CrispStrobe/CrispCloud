part of 'sheet_serial.dart';

const _worksheetOrder = [
  'sheetPr',
  'dimension',
  'sheetViews',
  'sheetFormatPr',
  'cols',
  'sheetData',
  'sheetCalcPr',
  'sheetProtection',
  'protectedRanges',
  'scenarios',
  'autoFilter',
  'sortState',
  'dataConsolidate',
  'customSheetViews',
  'mergeCells',
  'phoneticPr',
  'conditionalFormatting',
  'dataValidations',
  'hyperlinks',
  'printOptions',
  'pageMargins',
  'pageSetup',
  'headerFooter',
  'rowBreaks',
  'colBreaks',
  'customProperties',
  'cellWatches',
  'ignoredErrors',
  'smartTags',
  'drawing',
  'legacyDrawing',
  'legacyDrawingHF',
  'picture',
  'oleObjects',
  'controls',
  'webPublishItems',
  'tableParts',
  'extLst',
];
const _workbookOrder = [
  'fileVersion',
  'fileSharing',
  'workbookPr',
  'workbookProtection',
  'bookViews',
  'sheets',
  'functionGroups',
  'externalReferences',
  'definedNames',
  'calcPr',
  'oleSize',
  'customWorkbookViews',
  'pivotCaches',
  'smartTagPr',
  'smartTagTypes',
  'webPublishing',
  'fileRecoveryPr',
  'webPublishObjects',
  'extLst',
];
const _pivotType = '${OfficeNamespaces.r}/pivotTable';
const _cacheType = '${OfficeNamespaces.r}/pivotCacheDefinition';

void _readExternalCellValues(
  XmlElement? workbook,
  OpcPackage package,
  RelationshipCollection relationships,
  SmlWorkbook book,
) {
  const x = OfficeNamespaces.x;
  final references = workbook
      ?.firstChild('externalReferences', namespaceUri: x)
      ?.childrenNamed('externalReference', namespaceUri: x);
  if (references == null) return;
  for (final (index, reference) in references.indexed) {
    final id = reference.getAttribute('id', namespaceUri: OfficeNamespaces.r);
    final link = id == null ? null : relationships.byId(id);
    if (link == null ||
        link.type != '${OfficeNamespaces.r}/externalLink' ||
        link.targetMode != RelationshipTargetMode.internal) {
      continue;
    }
    final part = package.getPart(relationships.resolve(link));
    if (part == null) continue;
    XmlElement? root;
    try {
      root = XmlDocument.parse(part.readText()).root;
    } on FormatException {
      continue;
    }
    if (root?.localName != 'externalLink' || root?.namespaceUri != x) continue;
    // Only read the package cache. The externalBook target is never resolved.
    final externalBook = root!.firstChild('externalBook', namespaceUri: x);
    final names = externalBook
        ?.firstChild('sheetNames', namespaceUri: x)
        ?.childrenNamed('sheetName', namespaceUri: x);
    final data = externalBook?.firstChild('sheetDataSet', namespaceUri: x);
    if (names == null || data == null) continue;
    for (final sheet in data.childrenNamed('sheetData', namespaceUri: x)) {
      final sheetIndex = int.tryParse(sheet.getAttribute('sheetId') ?? '');
      final refreshError = sheet.getAttribute('refreshError');
      if (sheetIndex == null ||
          sheetIndex < 0 ||
          sheetIndex >= names.length ||
          refreshError == '1' ||
          refreshError == 'true') {
        continue;
      }
      final name = names[sheetIndex].getAttribute('val')?.toLowerCase();
      if (name == null || name.isEmpty) continue;
      for (final row in sheet.childrenNamed('row', namespaceUri: x)) {
        for (final cell in row.childrenNamed('cell', namespaceUri: x)) {
          final address = cell.getAttribute('r')?.toUpperCase();
          final raw = cell.firstChild('v', namespaceUri: x)?.text;
          if (address == null || raw == null) continue;
          final value = switch (cell.getAttribute('t')) {
            null || 'n' => double.tryParse(raw),
            'str' => raw,
            'b' when raw == '1' || raw == '0' => raw == '1',
            'e' when raw.isNotEmpty => FormulaErrorValue(raw),
            _ => null,
          };
          if (value != null && (value is! double || value.isFinite)) {
            book.externalCellValues[(index + 1, name, address)] = value;
          }
        }
      }
    }
  }
}

String _preserveSheetParts(
  String? source,
  String generated,
  Set<String> modeled,
  List<String> order,
) {
  if (source == null || source.trim().isEmpty) return generated;
  final old = XmlDocument.parse(source);
  final current = XmlDocument.parse(generated);
  final root = old.root!;
  for (final a in current.root!.attributes) {
    root.setAttribute(
      a.localName,
      a.value,
      prefix: a.prefix,
      namespaceUri: a.namespaceUri,
    );
  }
  final replacements = <String, List<XmlElement>>{};
  for (final child in current.root!.childElements) {
    if (!modeled.contains(child.localName) &&
        root.firstChild(child.localName, namespaceUri: child.namespaceUri) !=
            null) {
      continue;
    }
    (replacements[child.localName] ??= []).add(child.copy()..parent = root);
  }
  // Native extensions can be legal only at particular positions. Keep every
  // retained element in its original order and replace modeled children in
  // place. Only newly introduced elements need a schema-order insertion.
  final sourceChildren = List<XmlNode>.of(root.children);
  root.children.clear();
  for (final child in sourceChildren) {
    if (child is XmlElement &&
        child.namespaceUri == OfficeNamespaces.x &&
        modeled.contains(child.localName)) {
      root.children.addAll(replacements.remove(child.localName) ?? const []);
    } else {
      root.children.add(child);
    }
  }
  for (final name in order) {
    final elements = replacements.remove(name);
    if (elements == null) continue;
    final rank = order.indexOf(name);
    final next = root.children.indexWhere((child) {
      return child is XmlElement &&
          child.namespaceUri == OfficeNamespaces.x &&
          order.indexOf(child.localName) > rank;
    });
    root.children.insertAll(next < 0 ? root.children.length : next, elements);
  }
  for (final elements in replacements.values) {
    root.children.addAll(elements);
  }
  return old.toXmlString();
}

void _readPivots(SmlWorksheet sheet, OpcPackage package, String sheetUri) {
  final rels = package.relationshipsFor(sheetUri);
  for (final relationship in rels.byType(_pivotType)) {
    final uri = rels.resolve(relationship);
    final part = package.getPart(uri);
    if (part == null) continue;
    final root = XmlDocument.parse(part.readText()).root!;
    final cacheRels = package.relationshipsFor(uri);
    final cache = cacheRels.firstByType(_cacheType);
    if (cache == null) continue;
    final cacheUri = cacheRels.resolve(cache);
    final cachePart = package.getPart(cacheUri);
    if (cachePart == null) continue;
    final source = XmlDocument.parse(
      cachePart.readText(),
    ).root?.firstChild('cacheSource')?.firstChild('worksheetSource');
    final ref = source?.getAttribute('ref');
    if (ref == null) continue;
    sheet.pivots.add(
      SmlPivotTable(
        source: SmlRange.parse(ref),
        rowField:
            int.tryParse(
              root
                      .firstChild('rowFields')
                      ?.firstChild('field')
                      ?.getAttribute('x') ??
                  '0',
            ) ??
            0,
        dataField:
            int.tryParse(
              root
                      .firstChild('dataFields')
                      ?.firstChild('dataField')
                      ?.getAttribute('fld') ??
                  '1',
            ) ??
            1,
        name: root.getAttribute('name') ?? 'Pivot',
        sourcePartUri: uri,
        cachePartUri: cacheUri,
        sourceSheetName: source?.getAttribute('sheet'),
      ),
    );
  }
}

void _writePivots(
  SmlWorkbook book,
  SmlWorksheet sheet,
  OpcPackage package,
  String sheetUri,
) {
  final rels = package.relationshipsFor(sheetUri);
  final active = <String>{};
  final workbook = XmlDocument.parse(
    package.getPart('/xl/workbook.xml')!.readText(),
  );
  XmlElement? caches = workbook.root!.firstChild('pivotCaches');
  final wbRels = package.relationshipsFor('/xl/workbook.xml');
  for (final pivot in sheet.pivots) {
    final sourceSheet =
        book.sheets
            .where((s) => s.name == (pivot.sourceSheetName ?? sheet.name))
            .firstOrNull ??
        sheet;
    final range = '${pivot.source.start.a1}:${pivot.source.end.a1}';
    String? uri = pivot.sourcePartUri;
    String? cacheUri = pivot.cachePartUri;
    if (uri == null || cacheUri == null) {
      var n = 1;
      while (package.getPart('/xl/pivotTables/pivotTable$n.xml') != null ||
          package.getPart('/xl/pivotCache/pivotCacheDefinition$n.xml') !=
              null) {
        n++;
      }
      uri = '/xl/pivotTables/pivotTable$n.xml';
      cacheUri = '/xl/pivotCache/pivotCacheDefinition$n.xml';
      var cacheId = 1;
      final ids =
          caches
              ?.childrenNamed('pivotCache')
              .map((e) => int.tryParse(e.getAttribute('cacheId') ?? '') ?? 0)
              .toSet() ??
          <int>{};
      while (ids.contains(cacheId)) {
        cacheId++;
      }
      final fields = pivot.source.maxCol - pivot.source.minCol + 1;
      final cache = XmlWriter()
        ..writeStartDocument()
        ..writeStartElement('pivotCacheDefinition')
        ..writeAttribute('xmlns', OfficeNamespaces.x)
        ..writeAttribute('refreshOnLoad', '1')
        ..writeAttribute('saveData', '0');
      cache.writeStartElement('cacheSource');
      cache.writeAttribute('type', 'worksheet');
      cache.writeEmptyElement(
        'worksheetSource',
        attributes: {'ref': range, 'sheet': sourceSheet.name},
      );
      cache.writeEndElement();
      cache.writeStartElement('cacheFields');
      cache.writeAttribute('count', '$fields');
      for (int col = 0; col < fields; col++) {
        final title = sourceSheet
            .cell(SmlCellRef(pivot.source.minCol + col, pivot.source.minRow))
            .asString;
        cache.writeEmptyElement(
          'cacheField',
          attributes: {'name': title.isEmpty ? 'Column ${col + 1}' : title},
        );
      }
      cache.writeEndElement();
      cache.writeEndElement();
      package.createPart(
        cacheUri,
        'application/vnd.openxmlformats-officedocument.spreadsheetml.pivotCacheDefinition+xml',
        utf8.encode(cache.toXml()),
      );
      final table = XmlWriter()
        ..writeStartDocument()
        ..writeStartElement('pivotTableDefinition')
        ..writeAttribute('xmlns', OfficeNamespaces.x)
        ..writeAttribute('name', pivot.name)
        ..writeAttribute('cacheId', '$cacheId')
        ..writeAttribute('dataCaption', 'Values');
      final origin = SmlCellRef(pivot.source.maxCol + 2, 0);
      table.writeEmptyElement(
        'location',
        attributes: {
          'ref': '${origin.a1}:${SmlCellRef(origin.col + 1, 2).a1}',
          'firstHeaderRow': '1',
          'firstDataRow': '1',
          'firstDataCol': '1',
        },
      );
      table.writeStartElement('pivotFields');
      table.writeAttribute('count', '$fields');
      for (int col = 0; col < fields; col++) {
        table.writeEmptyElement(
          'pivotField',
          attributes: {
            if (col == pivot.rowField) 'axis': 'axisRow',
            if (col == pivot.dataField) 'dataField': '1',
          },
        );
      }
      table.writeEndElement();
      table.writeStartElement('rowFields');
      table.writeAttribute('count', '1');
      table.writeEmptyElement('field', attributes: {'x': '${pivot.rowField}'});
      table.writeEndElement();
      table.writeStartElement('dataFields');
      table.writeAttribute('count', '1');
      table.writeEmptyElement(
        'dataField',
        attributes: {
          'name': 'Sum',
          'fld': '${pivot.dataField}',
          'subtotal': 'sum',
        },
      );
      table.writeEndElement();
      table.writeEndElement();
      package.createPart(
        uri,
        'application/vnd.openxmlformats-officedocument.spreadsheetml.pivotTable+xml',
        utf8.encode(table.toXml()),
      );
      package
          .relationshipsFor(uri)
          .add(type: _cacheType, target: OpcUris.relativize(uri, cacheUri));
      final cacheRel = wbRels.add(
        type: _cacheType,
        target: OpcUris.relativize('/xl/workbook.xml', cacheUri),
      );
      caches ??= XmlElement(localName: 'pivotCaches');
      caches.addChild(
        XmlElement(localName: 'pivotCache')
          ..setAttribute('cacheId', '$cacheId')
          ..setAttribute('id', cacheRel.id, prefix: 'r'),
      );
      pivot.sourcePartUri = uri;
      pivot.cachePartUri = cacheUri;
      pivot.sourceSheetName = sourceSheet.name;
    } else {
      final table = XmlDocument.parse(package.getPart(uri)!.readText());
      // The cache belongs to the pivot table through its package relationship
      // and cacheId, not an r:id attribute on pivotTableDefinition. Some
      // producers emit both; retain the relationship and normalize that XML.
      table.root!.removeAttribute('id', namespaceUri: OfficeNamespaces.r);
      table.root!.setAttribute('name', pivot.name);
      table.root!
          .firstChild('rowFields')
          ?.firstChild('field')
          ?.setAttribute('x', '${pivot.rowField}');
      table.root!
          .firstChild('dataFields')
          ?.firstChild('dataField')
          ?.setAttribute('fld', '${pivot.dataField}');
      package.getPart(uri)!.writeText(table.toXmlString());
      final cache = XmlDocument.parse(package.getPart(cacheUri)!.readText());
      final source = cache.root!
          .firstChild('cacheSource')
          ?.firstChild('worksheetSource');
      source?.setAttribute('ref', range);
      source?.setAttribute('sheet', sourceSheet.name);
      cache.root!.setAttribute('refreshOnLoad', '1');
      package.getPart(cacheUri)!.writeText(cache.toXmlString());
    }
    final rel =
        rels
            .byType(_pivotType)
            .where((r) => rels.resolve(r) == uri)
            .firstOrNull ??
        rels.add(type: _pivotType, target: OpcUris.relativize(sheetUri, uri));
    active.add(rel.id);
  }
  for (final rel in rels.byType(_pivotType).toList()) {
    if (!active.contains(rel.id)) rels.removeById(rel.id);
  }
  if (caches != null) {
    workbook.root!.setAttribute('r', OfficeNamespaces.r, prefix: 'xmlns');
    if (workbook.root!.firstChild('pivotCaches') == null) {
      workbook.root!.addChild(caches);
    }
    package.getPart('/xl/workbook.xml')!.writeText(workbook.toXmlString());
  }
}
