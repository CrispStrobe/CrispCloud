// Reproducible synthetic acceptance for actual LibreOffice file saves.
// This tool does not install or exercise a Zotero plugin or CSL processor.
//
// create ORIGINAL
// verify SAVED ORIGINAL
// reexport SAVED ORIGINAL REEXPORTED
// Append --fixture=NAME to select one of the named fixtures explicitly.
//
// After create, use LibreOffice to save ORIGINAL/*.odt into SAVED. After
// reexport, save REEXPORTED/*.odt into a second directory and verify it against
// ORIGINAL again. Reexport checks the native model, saves/reopens DOCX, checks
// the model again, and emits another editable ODT with the same expected data.
// Full Zotero JSON and text compare exactly. Model geometry is represented in
// Word twips; generated ODT names and native style/note IDs are not identities.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';

const _names = [
  'body-bibliography',
  'table-only',
  'endnote-only',
  'uppercase-citations',
  'table-padding',
];
const _fieldCounts = [3, 6, 2, 2, 9];
const _textNamespace = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _styleNamespace = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';

ZoteroCitation _citation(String id, {int noteIndex = 0}) =>
    ZoteroCitation.fromJson({
      'citationID': id,
      'citationItems': [
        {
          'id': 'http://zotero.org/users/42/items/ABCD1234',
          'uris': ['http://zotero.org/users/42/items/ABCD1234'],
          'locator': '12–14',
          'label': 'page',
          'prefix': 'see ',
          'suffix': ' et seq.',
          'suppress-author': true,
          'itemData': {
            'id': 17,
            'type': 'book',
            'title': 'Über العربية 😀 & <source>',
            'futureItemData': {'preserve': true},
          },
          'futureItem': ['retain', 3, null],
        },
      ],
      'properties': {
        'plainCitation': '(Source $id)',
        'formattedCitation': '<i>(Source $id)</i>',
        'noteIndex': noteIndex,
        'futureProperty': {'enabled': false},
      },
      'futureCitation': [true, null, 'العربية 😀'],
    });

String _preferences({bool notes = false}) => jsonEncode({
  'dataVersion': 4,
  'sessionID': 'synthetic-native-roundtrip',
  'style': {
    'styleID': notes
        ? 'http://www.zotero.org/styles/chicago-fullnote-bibliography'
        : 'http://www.zotero.org/styles/apa',
    'locale': 'de-DE',
    'hasBibliography': true,
    'futureStyle': {'keep': 'العربية'},
  },
  'prefs': {
    'fieldType': 'Field',
    'noteType': notes ? 2 : 0,
    'futurePreference': ['retain', false],
  },
  'futureDocument': {'payload': 'preserve 😀', 'nullable': null},
});

WmlParagraph _plain(String text) => WmlParagraph(
  inlines: [WmlRun(text: text)],
  properties: WmlParagraphProps(spacingAfter: 6),
);

WmlParagraph _cited(String id, String text, {int noteIndex = 0}) {
  final paragraph = _plain('$text  tail');
  paragraph.inlines.whereType<WmlRun>().first.properties.bold = true;
  final citation = _citation(id, noteIndex: noteIndex);
  WordZotero.insertNativeCitation(
    paragraph,
    instruction: citation.fieldInstruction,
    text: citation.plainCitation,
    index: text.length + 1,
    preservedResultRuns: [
      WmlRun(
        text: citation.plainCitation,
        properties: WmlRunProps(italic: true),
      ),
    ],
  );
  return paragraph;
}

WmlDocument _bodyBibliography() {
  final bibliography = WordZotero.nativeBibliographyParagraphs(
    instruction:
        ' ADDIN ZOTERO_BIBL '
        '{"uncited":[["http://zotero.org/users/42/items/EFGH5678"]],'
        '"omitted":[],"custom":[],"futureBibliography":{"keep":[true,null,7]}} '
        'CSL_BIBLIOGRAPHY ',
    text: 'Alpha source.\n\nBeta source.',
    paragraphProperties: WmlParagraphProps(
      indent: WmlIndent(left: 36, hanging: 36),
      spacingAfter: 6,
    ),
  );
  bibliography.first.inlines.whereType<WmlRun>().first.properties.italic = true;
  return WmlDocument(
    zoteroDocumentData: _preferences(),
    sections: [
      WmlSection(
        blocks: [
          _cited('body-first', 'First'),
          _cited('body-second', 'Second'),
          _plain('References'),
          ...bibliography,
          _plain('After references'),
        ],
      ),
    ],
  );
}

// The text includes Unicode characters whose uppercase presentation expands.
// Raw text and citation offsets must survive each real converter save. A
// normal-case suffix exercises the explicit override beside uppercase runs.
WmlDocument _uppercaseCitations() => WmlDocument(
  zoteroDocumentData: _preferences(),
  sections: [
    WmlSection(
      blocks: [
        for (final id in ['first', 'second'])
          () {
            final paragraph = _cited('caps-$id', 'Before 😀 straße ﬃ');
            final runs = paragraph.inlines.whereType<WmlRun>().toList();
            for (final run in runs) {
              run.properties.allCaps = true;
              run.properties.explicitProperties.add('allCaps');
            }
            runs.last.properties.allCaps = false;
            return paragraph;
          }(),
      ],
    ),
  ],
);

WmlDocument _tableOnly() => WmlDocument(
  zoteroDocumentData: _preferences(),
  sections: [
    WmlSection(
      blocks: [
        _plain('Before table'),
        for (final alignment in [
          WmlJustification.left,
          WmlJustification.center,
          WmlJustification.right,
        ]) ...[
          WmlTable(
            grid: [72, 108],
            properties: WmlTableProps(
              alignment: alignment,
              borders: false,
              cellMargin: 0,
            ),
            rows: [
              WmlTableRow(
                cells: [
                  WmlTableCell(
                    width: 180,
                    gridSpan: 2,
                    blocks: [
                      _cited('table-${alignment.name}-merged', 'Merged'),
                    ],
                  ),
                ],
              ),
              WmlTableRow(
                cells: [
                  WmlTableCell(width: 72, blocks: [_plain('Left')]),
                  WmlTableCell(
                    width: 108,
                    blocks: [_cited('table-${alignment.name}-right', 'Right')],
                  ),
                ],
              ),
            ],
          ),
          _plain('After ${alignment.name} table'),
        ],
        _plain('After table'),
      ],
    ),
  ],
);

// Each outer table carries its own uniform padding, including explicit zero.
// Nested tables use a different positive value so style inheritance cannot
// accidentally substitute the parent table's padding and still pass the oracle.
WmlDocument _tablePadding() => WmlDocument(
  zoteroDocumentData: _preferences(),
  sections: [
    WmlSection(
      blocks: [
        _plain('Before padded tables'),
        for (final margin in const <double>[0, 6, 12]) ...[
          WmlTable(
            grid: [180, 180],
            properties: WmlTableProps(borders: false, cellMargin: margin),
            rows: [
              WmlTableRow(
                cells: [
                  WmlTableCell(
                    width: 360,
                    gridSpan: 2,
                    blocks: [
                      _cited('padding-${margin.toInt()}-merged', 'Merged'),
                    ],
                  ),
                ],
              ),
              WmlTableRow(
                cells: [
                  WmlTableCell(
                    width: 180,
                    blocks: [_cited('padding-${margin.toInt()}-left', 'Left')],
                  ),
                  WmlTableCell(
                    width: 180,
                    blocks: [
                      _plain('Before nested table'),
                      WmlTable(
                        grid: [120],
                        properties: WmlTableProps(
                          borders: false,
                          cellMargin: 3,
                        ),
                        rows: [
                          WmlTableRow(
                            cells: [
                              WmlTableCell(
                                width: 120,
                                blocks: [
                                  _cited(
                                    'padding-${margin.toInt()}-nested',
                                    'Nested',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                      _plain('After nested table'),
                    ],
                  ),
                ],
              ),
            ],
          ),
          _plain('After ${margin.toInt()} point table'),
        ],
        _plain('After padded tables'),
      ],
    ),
  ],
);

WmlDocument _endnoteOnly() {
  final document = WmlDocument(
    zoteroDocumentData: _preferences(notes: true),
    sections: [
      WmlSection(
        sourceProperties: WmlSectionSource(
          xml:
              '<w:sectPr xmlns:w="${OfficeNamespaces.w}">'
              '<w:endnotePr><w:numFmt w:val="decimal"/></w:endnotePr>'
              '</w:sectPr>',
          values: const {},
        ),
        blocks: [],
      ),
    ],
  );
  for (var index = 0; index < 2; index++) {
    // Deliberately use IDs different from displayed ordinals.
    final id = index == 0 ? 7 : 19;
    final anchor = _plain('Anchor ${index + 1} ')
      ..inlines.add(
        WmlRun(
          text: '$id',
          noteRefId: id,
          noteRefEndnote: true,
          properties: WmlRunProps(vertAlign: WmlVertAlign.superscript),
        ),
      );
    document.sections.single.blocks.add(anchor);
    final paragraph = _cited(
      'endnote-${index + 1}',
      'Endnote ${index + 1}',
      noteIndex: index + 1,
    );
    paragraph.inlines.insert(
      0,
      WmlNoteMarker(
        endnote: true,
        properties: WmlRunProps(vertAlign: WmlVertAlign.superscript),
      ),
    );
    document.endnotes.add(
      WmlNote(
        id: id,
        endnote: true,
        addReference: false,
        addReferenceSpace: false,
        blocks: [paragraph],
      ),
    );
  }
  return document;
}

// DOCX geometry is discrete in twentieths of a point. Encode that unit instead
// of comparing floating-point representations of LibreOffice's centimetres.
int _twips(double value) => (value * 20).round();

Object? _canonical(Object? value) {
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List<Object?>) return value.map(_canonical).toList();
  return value;
}

String _json(Object? value) => jsonEncode(_canonical(value));

Map<String, Object?> _runStyle(WmlRunProps p) => {
  'bold': p.bold,
  'italic': p.italic,
  'underline': p.underline.name,
  'strike': p.strike,
  'allCaps': p.allCaps,
  'smallCaps': p.smallCaps,
  'color': p.color.toUpperCase(),
  'fontSizeHalfPoints': p.fontSizeHalfPoints,
  'asciiFont': p.asciiFont,
  'csFont': p.csFont,
  'verticalAlignment': p.vertAlign.name,
  'positionHalfPoints': p.positionHalfPoints,
};

Map<String, Object?> _model(WmlDocument document) {
  final numbering = WordNoteNumbering(
    document,
    emptyReferencesAreAutomatic: true,
  );
  final owners = <WmlParagraph, String>{};

  Map<String, Object?> paragraph(WmlParagraph paragraph, String path) {
    owners[paragraph] = path;
    final segments = <Map<String, Object?>>[];
    for (final inline in paragraph.inlines) {
      if (inline is WmlFieldBoundary) continue;
      if (inline is WmlNoteMarker) {
        segments.add({
          'kind': inline.endnote ? 'endnoteMarker' : 'footnoteMarker',
          'style': _runStyle(inline.properties),
        });
        continue;
      }
      if (inline is! WmlRun) {
        throw StateError('Unexpected acceptance-fixture inline at $path.');
      }
      if (inline.noteRefId != null) {
        final label = numbering.referenceLabel(inline);
        if (label == null) throw StateError('Inexact note label at $path.');
        segments.add({
          'kind': inline.noteRefEndnote
              ? 'endnoteReference'
              : 'footnoteReference',
          'label': label,
          'style': _runStyle(inline.properties),
        });
        continue;
      }
      if (inline.text.isEmpty) continue;
      final style = _runStyle(inline.properties);
      if (segments.isNotEmpty &&
          segments.last['kind'] == 'text' &&
          _json(segments.last['style']) == _json(style)) {
        segments.last['text'] = '${segments.last['text']}${inline.text}';
      } else {
        segments.add({'kind': 'text', 'text': inline.text, 'style': style});
      }
    }
    final p = paragraph.properties;
    return {
      'kind': 'paragraph',
      'segments': segments,
      'alignment': p.justification.name,
      'indentTwips': {
        'left': _twips(p.indent.left),
        'right': _twips(p.indent.right),
        'firstLine': _twips(p.indent.firstLine),
        'hanging': _twips(p.indent.hanging),
      },
      'spacingBeforeTwips': _twips(p.spacingBefore),
      'spacingAfterTwips': _twips(p.spacingAfter),
      'lineSpacing': p.lineSpacing,
      'lineSpacingRule': p.lineSpacingRule.name,
      'keepTogether': p.keepTogether,
      'pageBreakBefore': p.pageBreakBefore,
    };
  }

  List<Object?> blocks(List<WmlBlock> values, String parent) => [
    for (var index = 0; index < values.length; index++)
      switch (values[index]) {
        final WmlParagraph p => paragraph(p, '$parent/$index'),
        final WmlTable table => {
          'kind': 'table',
          'gridTwips': table.grid.map(_twips).toList(),
          'alignment': table.properties.alignment.name,
          'borders': table.properties.borders,
          'cellMarginTwips': _twips(table.properties.cellMargin),
          'rows': [
            for (var row = 0; row < table.rows.length; row++)
              {
                'cantSplit': table.rows[row].cantSplit,
                'cells': [
                  for (
                    var cell = 0;
                    cell < table.rows[row].cells.length;
                    cell++
                  )
                    {
                      'span': table.rows[row].cells[cell].gridSpan,
                      'verticalMerge': table.rows[row].cells[cell].vMerge.name,
                      'widthTwips': table.rows[row].cells[cell].width == null
                          ? null
                          : _twips(table.rows[row].cells[cell].width!),
                      'blocks': blocks(
                        table.rows[row].cells[cell].blocks,
                        '$parent/$index/row$row/cell$cell',
                      ),
                    },
                ],
              },
          ],
        },
        _ => throw StateError('Unexpected fixture block at $parent/$index.'),
      },
  ];

  final body = [
    for (var index = 0; index < document.sections.length; index++)
      {
        'pageWidthTwips': _twips(document.sections[index].pageSize.width),
        'pageHeightTwips': _twips(document.sections[index].pageSize.height),
        'marginTwips': {
          'left': _twips(document.sections[index].margins.left),
          'right': _twips(document.sections[index].margins.right),
          'top': _twips(document.sections[index].margins.top),
          'bottom': _twips(document.sections[index].margins.bottom),
        },
        'columns': document.sections[index].columnCount,
        'columnSpaceTwips': _twips(document.sections[index].columnSpace),
        'blocks': blocks(document.sections[index].blocks, 'body$index'),
      },
  ];
  final notes = [
    for (var index = 0; index < numbering.notes.length; index++)
      {
        'kind': numbering.notes[index].endnote ? 'endnote' : 'footnote',
        'label': numbering.labelFor(numbering.notes[index]),
        'exactLabel': numbering.hasExactLabel(numbering.notes[index]),
        'blocks': blocks(numbering.notes[index].blocks, 'note$index'),
      },
  ];
  return {
    'preferences': jsonDecode(WordZoteroDocumentData.read(document)),
    'body': body,
    'notes': notes,
    'fields': [
      for (final field in WordZotero.fields(document))
        {
          'kind': field.kind.name,
          'canEdit': field.canEdit,
          'metadata': field.metadata,
          'cache': field.cachedText,
          'start': field.start,
          'end': field.end,
          'paragraphOwners': [
            for (final paragraph in field.paragraphs)
              owners[paragraph] ??
                  (throw StateError('An active field has no native owner.')),
          ],
        },
    ],
  };
}

Iterable<XmlElement> _elements(XmlElement root) sync* {
  yield root;
  for (final child in root.childElements) {
    yield* _elements(child);
  }
}

List<Object?> _noteStyleInventory(XmlElement root, XmlElement styles) {
  final noteClasses = <String>{
    for (final element in _elements(root))
      if (element.namespaceUri == _textNamespace && element.localName == 'note')
        element.getAttribute('note-class', namespaceUri: _textNamespace)!,
  };

  String? position(String? name, [Set<String> seen = const <String>{}]) {
    if (name == null || name.isEmpty) return null;
    if (seen.length > 16 || seen.contains(name)) {
      throw StateError('Cyclic fixture note character style.');
    }
    final matches = <XmlElement>[
      for (final tree in [styles, root])
        for (final element in _elements(tree))
          if (element.namespaceUri == _styleNamespace &&
              element.localName == 'style' &&
              element.getAttribute('family', namespaceUri: _styleNamespace) ==
                  'text' &&
              element.getAttribute('name', namespaceUri: _styleNamespace) ==
                  name)
            element,
    ];
    if (matches.length != 1) {
      throw StateError(
        'Missing or ambiguous fixture note character style: $name.',
      );
    }
    final style = matches.single;
    var result = position(
      style.getAttribute('parent-style-name', namespaceUri: _styleNamespace),
      {...seen, name},
    );
    for (final properties in style.childrenNamed(
      'text-properties',
      namespaceUri: _styleNamespace,
    )) {
      result =
          properties.getAttribute(
            'text-position',
            namespaceUri: _styleNamespace,
          ) ??
          result;
    }
    return result;
  }

  return [
    for (final kind in noteClasses.toList()..sort())
      () {
        final matches = <XmlElement>[
          for (final tree in [styles, root])
            for (final element in _elements(tree))
              if (element.namespaceUri == _textNamespace &&
                  element.localName == 'notes-configuration' &&
                  element.getAttribute(
                        'note-class',
                        namespaceUri: _textNamespace,
                      ) ==
                      kind)
                element,
        ];
        if (matches.length != 1) {
          throw StateError('Ambiguous fixture note configuration.');
        }
        final configuration = matches.single;
        final positions = {
          for (final attribute in [
            'citation-style-name',
            'citation-body-style-name',
          ])
            attribute: position(
              configuration.getAttribute(
                attribute,
                namespaceUri: _textNamespace,
              ),
            ),
        };
        if (positions.values.any((value) => value != 'super 65%')) {
          throw StateError(
            'The canonical note fixture must retain both 65% superscript styles.',
          );
        }
        return {'kind': kind, 'positions': positions};
      }(),
  ];
}

Future<Map<String, Object?>> _inventory(Uint8List bytes) async {
  final inventory = await OdfZotero.inspect(bytes);
  if (inventory.issues.isNotEmpty ||
      !inventory.preferences.usesReferenceMarks ||
      inventory.fields.any((field) => !field.isImportCandidate)) {
    throw StateError('The ODT native Zotero inventory is not complete.');
  }
  final package = OpcPackage.openBytes(bytes);
  final root = XmlDocument.parse(
    package.getPart('/content.xml')!.readText(),
  ).root!;
  final styles = XmlDocument.parse(
    package.getPart('/styles.xml')!.readText(),
  ).root!;
  return {
    'preferences': jsonDecode(inventory.preferences.rawData!),
    'fields': [
      for (final field in inventory.fields)
        {
          'kind': field.kind!.name,
          'storage': field.storage.name,
          'metadata': field.metadata,
          'cache': field.cachedText,
          'paragraphs': field.ranges.map((range) => range.text).toList(),
          'story': field.starts.single.story.name,
          'tableOwnerCount': field.starts.single.owners
              .where((owner) => owner.localName == 'table-cell')
              .length,
        },
    ],
    'notes': [
      for (final element in _elements(root))
        if (element.namespaceUri == _textNamespace &&
            element.localName == 'note')
          {
            'kind': element.getAttribute(
              'note-class',
              namespaceUri: _textNamespace,
            ),
            'label': element
                .firstChild('note-citation', namespaceUri: _textNamespace)!
                .text,
          },
    ],
    'noteConfigurations': _noteStyleInventory(root, styles),
  };
}

void _writeJson(File file, Object? value) => file.writeAsStringSync(
  '${const JsonEncoder.withIndent('  ').convert(_canonical(value))}\n',
);

void _equal(Object? actual, Object? expected, String label, Directory output) {
  if (_json(actual) == _json(expected)) return;
  _writeJson(File('${output.path}/$label.actual.json'), actual);
  throw StateError('$label differs; see $label.actual.json.');
}

Future<WmlDocument> _verify(
  String name,
  Directory saved,
  Map<String, Object?> expected,
) async {
  final bytes = File('${saved.path}/$name.odt').readAsBytesSync();
  _equal(
    await _inventory(bytes),
    expected['inventory'],
    '$name.inventory',
    saved,
  );
  final document = await OdtDocumentReader.readBytes(bytes);
  _equal(_model(document), expected['model'], '$name.model', saved);
  return document;
}

Future<void> main(List<String> args) async {
  final selected = <String>[..._names];
  if (args.isNotEmpty && args.last.startsWith('--fixture=')) {
    final name = args.last.substring('--fixture='.length);
    if (!_names.contains(name)) {
      throw ArgumentError('Unknown fixture $name; use ${_names.join(', ')}.');
    }
    selected
      ..clear()
      ..add(name);
    args = args.sublist(0, args.length - 1);
  }
  final valid =
      args.isNotEmpty &&
      ((args.first == 'create' && args.length == 2) ||
          (args.first == 'verify' && args.length == 3) ||
          (args.first == 'reexport' && args.length == 4));
  if (!valid) {
    throw ArgumentError(
      'Use create ORIGINAL, verify SAVED ORIGINAL, or '
      'reexport SAVED ORIGINAL REEXPORTED; optionally append --fixture=NAME.',
    );
  }
  final input = Directory(args[1]);
  if (args.first == 'create') {
    input.createSync(recursive: true);
    final documents = [
      _bodyBibliography(),
      _tableOnly(),
      _endnoteOnly(),
      _uppercaseCitations(),
      _tablePadding(),
    ];
    for (var index = 0; index < _names.length; index++) {
      final name = _names[index];
      if (!selected.contains(name)) continue;
      final document = documents[index];
      final docx = WordSerializer().writeBytes(document);
      if (WordZotero.fields(document).length != _fieldCounts[index]) {
        throw StateError('The $name fixture has an unexpected field count.');
      }
      final bytes = OdtDocumentWriter.writeEditableZoteroBytes(document);
      File('${input.path}/$name.source.docx').writeAsBytesSync(docx);
      File('${input.path}/$name.odt').writeAsBytesSync(bytes);
      final expected = <String, Object?>{
        'schema': 1,
        'name': name,
        'geometryUnit': 'Word twips (1/20 point)',
        'model': _model(document),
        'inventory': await _inventory(bytes),
      };
      _writeJson(File('${input.path}/$name.expected.json'), expected);
      await _verify(name, input, expected);
      stdout.writeln(
        jsonEncode({'created': name, 'fields': _fieldCounts[index]}),
      );
    }
    return;
  }
  final expectedDirectory = Directory(args[2]);
  final output = args.first == 'reexport' ? Directory(args[3]) : null;
  output?.createSync(recursive: true);
  for (final name in selected) {
    final Object? decoded = jsonDecode(
      File('${expectedDirectory.path}/$name.expected.json').readAsStringSync(),
    );
    if (decoded is! Map<String, Object?> ||
        decoded['schema'] != 1 ||
        decoded['name'] != name) {
      throw FormatException('Invalid expected fixture data for $name.');
    }
    final document = await _verify(name, input, decoded);
    if (output != null) {
      final docx = WordSerializer().writeBytes(document);
      File('${output.path}/$name.docx').writeAsBytesSync(docx);
      final reopened = WordDeserializer().readBytes(docx);
      _equal(_model(reopened), decoded['model'], '$name.docx-model', output);
      final bytes = OdtDocumentWriter.writeEditableZoteroBytes(reopened);
      _equal(
        await _inventory(bytes),
        decoded['inventory'],
        '$name.reexport-inventory',
        output,
      );
      File('${output.path}/$name.odt').writeAsBytesSync(bytes);
      _writeJson(File('${output.path}/$name.expected.json'), decoded);
      await _verify(name, output, decoded);
    }
    stdout.writeln(
      jsonEncode({
        'file': name,
        'nativeModelMatched': true,
        'inventoryMatched': true,
        'docxAndEditableOdtReexported': output != null,
      }),
    );
  }
}
