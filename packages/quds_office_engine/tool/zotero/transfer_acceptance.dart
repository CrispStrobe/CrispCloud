import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';

/// Generate a synthetic carrier, then verify a DOCX returned by an independent
/// word processor. The formatter responses below are controlled fixtures; this
/// qualifies file conversion and Quds import, not a live Zotero/plugin session.
void main(List<String> arguments) {
  if (arguments.length != 2 ||
      !{'generate', 'verify'}.contains(arguments.first)) {
    throw ArgumentError(
      'Usage: transfer_acceptance.dart generate DIR | verify FILE.docx',
    );
  }
  if (arguments.first == 'generate') {
    final directory = Directory(arguments[1])..createSync(recursive: true);
    final document = _fixture();
    File(
      '${directory.path}/active.docx',
    ).writeAsBytesSync(WordSerializer().writeBytes(document));
    final session = WordZoteroCitingSession(
      document: document,
      documentId: _id,
    );
    _call(session, 'Document.setDocumentData', [
      WordZoteroDocumentData.toHttp(_preferences),
    ]);
    _call(session, 'Document.exportDocument', ['Http', _instructions]);
    _call(session, 'Document.setDocumentData', [
      WordZoteroDocumentData.toHttp(_preferences),
    ]);
    _call(session, 'Document.activate');
    _call(session, 'Document.complete');
    session.apply();
    _require(WordZotero.fields(document).isEmpty, 'exported active fields');
    File(
      '${directory.path}/transfer.docx',
    ).writeAsBytesSync(WordSerializer().writeBytes(document));
    File(
      '${directory.path}/transfer.odt',
    ).writeAsBytesSync(OdtDocumentWriter.writeBytes(document));
    stdout.writeln(
      jsonEncode({
        'generated': directory.path,
        'citationCount': 5,
        'bibliographyCount': 1,
      }),
    );
    return;
  }

  final input = File(arguments[1]);
  final document = WordDeserializer().read(
    OpcPackage.openBytes(input.readAsBytesSync()),
  );
  _require(WordZoteroTransfer.isTransferDocument(document), 'leading marker');
  final sourceTexts = document.paragraphs.map((p) => p.text).toList();
  final session = WordZoteroCitingSession(document: document, documentId: _id);
  _require(
    _call(session, 'Document.getDocumentData') == WordZoteroTransfer.marker,
    'protocol marker',
  );
  _require(
    _call(session, 'Document.importDocument', ['Http']) == true,
    'import callback',
  );
  final fields =
      (_call(session, 'Document.getFields', ['Http'])! as List<Object?>)
          .cast<Map<String, Object>>();
  _require(fields.length == 6, 'all six field packets');
  final ids = <String>[];
  final noteIndexes = <String, int>{};
  for (final field in fields) {
    final code = field['code']! as String;
    if (code.startsWith('ITEM CSL_CITATION ')) {
      final citation = ZoteroCitation.fromJson(
        WordZotero.metadataOf(' ADDIN ZOTERO_$code ')!,
      );
      ids.add(citation.citationId);
      noteIndexes[citation.citationId] = field['noteIndex']! as int;
      _require(
        citation.items.single.locator == '27–29',
        'locator ${citation.citationId}',
      );
      _require(
        citation.toJson()['future'] is Map<String, Object?>,
        'unknown citation data',
      );
      _call(session, 'Field.setText', [
        field['id'],
        '<i>(${citation.citationId})</i>',
        true,
      ]);
    } else {
      final data = WordZotero.metadataOf(' ADDIN ZOTERO_$code ')!;
      _require(
        jsonEncode(data['uncited']) ==
            '[["http://zotero.org/users/42/items/UNCITED1"]]',
        'uncited bibliography data',
      );
      _call(session, 'Field.setText', [field['id'], _bibliographyHtml, true]);
    }
  }
  _require(
    ids.toSet().difference(_citationIds).isEmpty &&
        ids.length == _citationIds.length,
    'citation identities',
  );
  _require(
    noteIndexes['footnote']! > 0 && noteIndexes['endnote']! > 0,
    'note indexes',
  );
  _require(
    document.paragraphs.map((p) => p.text).join('\n') == sourceTexts.join('\n'),
    'detached staging',
  );
  _call(session, 'Document.setBibliographyStyle', [
    0,
    -360,
    240,
    120,
    <int>[],
    0,
  ]);
  _call(session, 'Document.setDocumentData', [
    WordZoteroDocumentData.toHttp(session.documentData),
  ]);
  _call(session, 'Document.activate');
  _call(session, 'Document.complete');
  session.prepareReview();
  _require(
    session.formattingWarnings.isEmpty,
    'unexpected formatting warnings: ${session.formattingWarnings.join('; ')}',
  );
  session.apply();
  _verifyRestored(document);
  final restored = File('${input.path}.restored.docx');
  restored.writeAsBytesSync(WordSerializer().writeBytes(document));
  final reopened = WordDeserializer().read(
    OpcPackage.openBytes(restored.readAsBytesSync()),
  );
  _verifyRestored(reopened);
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'input': input.path,
      'result': 'passed',
      'citations': ids,
      'noteIndexes': noteIndexes,
      'activeFieldsAfterReopen': WordZotero.fields(reopened).length,
      'restored': restored.path,
      'scope':
          'DOCX carrier preservation and controlled Quds import/format callbacks; converter provenance is recorded separately; no live Zotero plugin.',
    }),
  );
}

const _id = 'quds-transfer-file-acceptance';
const _instructions =
    'Open this document in another word processor and click Zotero Refresh to restore active citations.';
const _citationIds = {'body-a', 'body-b', 'table', 'footnote', 'endnote'};
const _bibliographyHtml =
    '<div class="csl-bib-body"><div class="csl-entry"><i>First source</i>.</div><div class="csl-entry">Second source.</div></div>';
final _preferences = jsonEncode(<String, Object?>{
  'dataVersion': 4,
  'sessionID': 'synthetic-transfer',
  'style': <String, Object?>{
    'styleID': 'http://www.zotero.org/styles/apa',
    'locale': 'de-DE',
    'hasBibliography': true,
    'bibliographyStyleHasBeenSet': false,
  },
  'prefs': <String, Object?>{'fieldType': 'Field', 'noteType': 0},
  'future': <String, Object?>{'preserve': 'العربية Ä 😀'},
});

ZoteroCitation _citation(String id) =>
    ZoteroCitation.fromJson(<String, Object?>{
      'citationID': id,
      'properties': <String, Object?>{'plainCitation': '($id)', 'noteIndex': 0},
      'citationItems': [
        <String, Object?>{
          'id': id,
          'uris': ['http://zotero.org/users/42/items/ABCD1234'],
          'locator': '27–29',
          'label': 'page',
          'itemData': <String, Object?>{
            'id': id,
            'type': 'book',
            'title': 'Übertragung العربية 😀 $id',
          },
        },
      ],
      'future': <String, Object?>{
        'keep': true,
        'looksLikeCode': 'ITEM CSL_CITATION {inside a title}',
      },
    });

WmlDocument _fixture() {
  final document = WmlDocument.empty(text: 'Research before ')
    ..zoteroDocumentData = _preferences;
  final paragraph = document.paragraphs.single;
  WordZotero.insertCitation(paragraph, _citation('body-a'));
  // Deliberately touching fields exercise link merging by another application.
  WordZotero.insertCitation(paragraph, _citation('body-b'));
  paragraph.inlines.addAll([
    WmlRun(text: ' after ', properties: WmlRunProps(bold: true)),
    WmlRun(
      text: 'ordinary link',
      hyperlink: const WmlHyperlink(url: 'https://example.org/research'),
    ),
    WmlRun(
      text: '\uFFFC',
      inlineVisual: WmlVisual(
        visual: OfficeVisual(
          kind: OfficeVisualKind.picture,
          title: 'Synthetic red pixel',
          imageBytes: base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
          ),
          width: 24,
          height: 18,
        ),
      ),
    ),
  ]);
  for (final endnote in [false, true]) {
    final note = WordNotes.insert(
      document,
      paragraph,
      endnote: endnote,
      text: 'Authored before ',
    );
    WordZotero.insertCitation(
      note.paragraphs.single,
      _citation(endnote ? 'endnote' : 'footnote'),
    );
    note.paragraphs.single.inlines.add(WmlRun(text: ' authored after'));
  }
  final tableParagraph = WmlParagraph(inlines: [WmlRun(text: 'Table before ')]);
  WordZotero.insertCitation(tableParagraph, _citation('table'));
  tableParagraph.inlines.add(WmlRun(text: ' table after'));
  document.sections.single.blocks.add(
    WmlTable(
      grid: [180, 180],
      rows: [
        WmlTableRow(
          cells: [
            WmlTableCell(blocks: [tableParagraph]),
            WmlTableCell(
              blocks: [
                WmlParagraph(inlines: [WmlRun(text: 'Other cell')]),
              ],
            ),
          ],
        ),
      ],
    ),
  );
  final formatted = ZoteroFormattedText.fromHtml(_bibliographyHtml);
  document.sections.single.blocks.addAll(
    WordZotero.nativeBibliographyParagraphs(
      instruction:
          ' ADDIN ZOTERO_BIBL {"uncited":[["http://zotero.org/users/42/items/UNCITED1"]],"omitted":[],"custom":[]} CSL_BIBLIOGRAPHY ',
      text: formatted.plainText,
      formattedText: formatted,
    ),
  );
  return document;
}

void _verifyRestored(WmlDocument document) {
  _require(
    !WordZoteroTransfer.isTransferDocument(document),
    'removed transfer framing',
  );
  final fields = WordZotero.fields(document);
  _require(
    fields.length == 6 && fields.every((field) => field.isValid),
    'active native fields',
  );
  final citationIds = fields
      .where((field) => field.citation != null)
      .map((field) => field.citation!.citationId)
      .toSet();
  _require(
    citationIds.length == 5 && citationIds.containsAll(_citationIds),
    'persisted citation identities',
  );
  for (final field in fields.where((field) => field.citation != null)) {
    final citation = field.citation!;
    final id = citation.citationId;
    final item = citation.items.single;
    _require(
      item.itemData?['title'] == 'Übertragung العربية 😀 $id',
      'exact Unicode title $id',
    );
    _require(
      item.locator == '27–29' && item.label == 'page',
      'exact locator $id',
    );
    _require(
      jsonEncode(item.uris) == '["http://zotero.org/users/42/items/ABCD1234"]',
      'exact URI $id',
    );
    _require(
      jsonEncode(citation.toJson()['future']) ==
          '{"keep":true,"looksLikeCode":"ITEM CSL_CITATION {inside a title}"}',
      'exact unknown metadata $id',
    );
    _require(field.cachedText == '($id)', 'formatted citation text $id');
    final run = field.paragraph.inlines.whereType<WmlRun>().singleWhere(
      (run) => run.text == '($id)',
    );
    _require(
      run.properties.italic && run.hyperlink == null,
      'rich citation formatting $id',
    );
    _require(
      run.properties.color == '000000' &&
          !{
            'Hyperlink',
            'InternetLink',
            'FollowedHyperlink',
            'VisitedInternetLink',
          }.contains(run.properties.styleId),
      'removed carrier hyperlink appearance $id',
    );
  }
  _require(
    document.paragraphs
        .expand((p) => p.inlines)
        .whereType<WmlRun>()
        .any((run) => run.text == ' after ' && run.properties.bold),
    'authored bold prose',
  );
  final bibliography = fields.singleWhere(
    (field) => field.kind == ZoteroFieldKind.bibliography,
  );
  _require(
    bibliography.paragraphs.map((p) => p.text).join('\n') ==
        'First source.\nSecond source.',
    'bibliography entry text',
  );
  _require(
    bibliography.paragraphs.first.inlines.whereType<WmlRun>().any(
      (run) => run.text == 'First source' && run.properties.italic,
    ),
    'bibliography rich emphasis',
  );
  _require(
    document.footnotes
        .where((note) => note.id > 0)
        .single
        .text
        .contains('Authored before (footnote) authored after'),
    'authored footnote prose',
  );
  _require(
    document.endnotes
        .where((note) => note.id > 0)
        .single
        .text
        .contains('Authored before (endnote) authored after'),
    'authored endnote prose',
  );
  _require(
    document.paragraphs.any(
      (p) => p.text.contains('Table before (table) table after'),
    ),
    'table citation/prose',
  );
  _require(
    document.paragraphs
        .expand((p) => p.inlines)
        .whereType<WmlRun>()
        .any((run) => run.hyperlink?.url == 'https://example.org/research'),
    'ordinary hyperlink',
  );
  _require(document.inlineVisuals.isNotEmpty, 'inline picture');
  _require(
    WordZoteroDocumentData.read(document).contains('العربية Ä 😀'),
    'unknown document preferences',
  );
  _require(
    fields
            .singleWhere((field) => field.kind == ZoteroFieldKind.bibliography)
            .paragraphs
            .length ==
        2,
    'native bibliography entries',
  );
}

Object? _call(
  WordZoteroCitingSession session,
  String name, [
  List<Object?> args = const [],
]) => session.handle(name, [_id, ...args]);
void _require(bool value, String label) {
  if (!value) throw StateError('Transfer acceptance failed: $label');
}
