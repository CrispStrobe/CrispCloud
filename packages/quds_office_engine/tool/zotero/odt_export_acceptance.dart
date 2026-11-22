// Reproducible synthetic fixtures for actual LibreOffice file-save checks.
// This does not install or exercise the Zotero plugin.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';

const _names = ['body-bibliography', 'table-notes'];
const _odfText = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';

ZoteroCitation _citation(String id) => ZoteroCitation.fromJson({
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
        'id': 1,
        'type': 'book',
        'title': 'Research العربية 😀 & <source>',
      },
      'futureItem': {'preserve': true},
    },
  ],
  'properties': {'plainCitation': '(Source)', 'noteIndex': 0},
  'futureCitation': [true, null, 42],
});

WmlParagraph _paragraph(String text, [String? id]) {
  final paragraph = WmlParagraph(inlines: [WmlRun(text: text)]);
  if (id != null) WordZotero.insertCitation(paragraph, _citation(id));
  return paragraph;
}

String _preferences() => jsonEncode({
  'dataVersion': 4,
  'sessionID': 'synthetic-converter-check',
  'style': {
    'styleID': 'http://www.zotero.org/styles/apa',
    'locale': 'de-DE',
    'hasBibliography': true,
  },
  'prefs': {'fieldType': 'Field', 'noteType': 0},
  'futureDocument': List.filled(160, 'العربية 😀').join(' '),
});

WmlDocument _bodyBibliography() {
  final entries = WordZotero.nativeBibliographyParagraphs(
    instruction:
        ' ADDIN ZOTERO_BIBL '
        '{"uncited":[["http://zotero.org/users/42/items/EFGH5678"]],'
        '"omitted":[],"custom":[],"futureBibliography":{"keep":true}} '
        'CSL_BIBLIOGRAPHY ',
    text: 'Alpha source.\n\nBeta source.',
    paragraphProperties: WmlParagraphProps(
      indent: WmlIndent(left: 36, hanging: 36),
      spacingAfter: 6,
    ),
  );
  entries.first.inlines.whereType<WmlRun>().first.properties.italic = true;
  return WmlDocument(
    zoteroDocumentData: _preferences(),
    sections: [
      WmlSection(
        blocks: [
          _paragraph('First ', 'first'),
          _paragraph('Second ', 'second'),
          _paragraph('References'),
          ...entries,
          _paragraph('After references'),
        ],
      ),
    ],
  );
}

WmlDocument _tableNotes() {
  final body = _paragraph('Body ', 'body');
  final footAnchor = _paragraph('Footnote anchor');
  final endAnchor = _paragraph('Endnote anchor');
  final document = WmlDocument(
    zoteroDocumentData: _preferences(),
    sections: [
      WmlSection(
        sourceProperties: WmlSectionSource(
          xml:
              '<w:sectPr xmlns:w="${OfficeNamespaces.w}">'
              '<w:endnotePr><w:numFmt w:val="decimal"/></w:endnotePr>'
              '</w:sectPr>',
          values: const {},
        ),
        blocks: [
          body,
          WmlTable(
            grid: [144, 144],
            rows: [
              WmlTableRow(
                cells: [
                  WmlTableCell(
                    width: 288,
                    gridSpan: 2,
                    blocks: [_paragraph('Merged cell ', 'cell')],
                  ),
                ],
              ),
              WmlTableRow(
                cells: [
                  WmlTableCell(width: 144, blocks: [_paragraph('Left')]),
                  WmlTableCell(width: 144, blocks: [_paragraph('Right')]),
                ],
              ),
            ],
          ),
          footAnchor,
          endAnchor,
        ],
      ),
    ],
  );
  final foot = WordNotes.insert(
    document,
    footAnchor,
    endnote: false,
    text: 'Footnote ',
  );
  final end = WordNotes.insert(
    document,
    endAnchor,
    endnote: true,
    text: 'Endnote ',
  );
  WordZotero.insertCitation(foot.paragraphs.single, _citation('foot'));
  WordZotero.insertCitation(end.paragraphs.single, _citation('end'));
  return document;
}

Future<Map<String, Object?>> _summary(Uint8List bytes) async {
  final inventory = await OdfZotero.inspect(bytes);
  if (inventory.issues.isNotEmpty ||
      !inventory.preferences.usesReferenceMarks ||
      inventory.fields.any((field) => !field.isImportCandidate)) {
    throw StateError('ODT does not retain a complete native Zotero inventory.');
  }
  final content = XmlDocument.parse(
    OpcPackage.openBytes(bytes).getPart('/content.xml')!.readText(),
  ).root!;
  return {
    'preferences': inventory.preferences.rawData,
    'notes': [
      for (final element in _elements(content))
        if (element.namespaceUri == _odfText && element.localName == 'note')
          {
            'class': element.getAttribute('note-class', namespaceUri: _odfText),
            'label': element
                .firstChild('note-citation', namespaceUri: _odfText)!
                .text,
          },
    ],
    'fields': [
      for (final field in inventory.fields)
        {
          'name': field.name,
          'kind': field.kind!.name,
          'storage': field.storage.name,
          'metadata': field.metadata,
          'cache': field.cachedText,
          'story': field.starts.single.story.name,
          'paragraphs': field.ranges.map((range) => range.text).toList(),
          'tableOwners': field.starts.single.owners
              .where((owner) => owner.localName == 'table-cell')
              .length,
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

Future<void> main(List<String> args) async {
  if (args.length < 2 || !['create', 'verify'].contains(args.first)) {
    throw ArgumentError(
      'Use create OUTPUT_DIR or verify SAVED_DIR EXPECTED_DIR.',
    );
  }
  final directory = Directory(args[1]);
  if (args.first == 'create') {
    directory.createSync(recursive: true);
    final documents = [_bodyBibliography(), _tableNotes()];
    for (var index = 0; index < _names.length; index++) {
      final bytes = OdtDocumentWriter.writeEditableZoteroBytes(
        documents[index],
      );
      File('${directory.path}/${_names[index]}.odt').writeAsBytesSync(bytes);
      File(
        '${directory.path}/${_names[index]}.expected.json',
      ).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(await _summary(bytes)),
      );
    }
    stdout.writeln(jsonEncode({'created': _names}));
    return;
  }
  if (args.length != 3) {
    throw ArgumentError('An expected directory is required.');
  }
  for (final name in _names) {
    final bytes = File('${directory.path}/$name.odt').readAsBytesSync();
    final actual = await _summary(bytes);
    final expected = jsonDecode(
      File('${args[2]}/$name.expected.json').readAsStringSync(),
    );
    if (jsonEncode(actual) != jsonEncode(expected)) {
      File(
        '${directory.path}/$name.actual.json',
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(actual));
      throw StateError('Native Zotero data or ownership changed in $name.');
    }
    stdout.writeln(jsonEncode({'file': name, 'matched': true}));
  }
}
