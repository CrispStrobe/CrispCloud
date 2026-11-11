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

String _preserveSheetParts(
  String? source,
  String generated,
  Set<String> modeled,
  List<String> order,
) {
  if (source == null || source.trim().isEmpty) return generated;
  final old = XmlDocument.parse(source);
  final current = XmlDocument.parse(generated);
  for (final a in current.root!.attributes) {
    old.root!.setAttribute(
      a.localName,
      a.value,
      prefix: a.prefix,
      namespaceUri: a.namespaceUri,
    );
  }
  old.root!.children.removeWhere(
    (n) => n is XmlElement && modeled.contains(n.localName),
  );
  for (final child in current.root!.childElements) {
    old.root!.addChild(child.copy());
  }
  int rank(XmlNode n) {
    final i = n is XmlElement ? order.indexOf(n.localName) : -1;
    return i < 0 ? order.length : i;
  }

  old.root!.children.sort((a, b) => rank(a).compareTo(rank(b)));
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
