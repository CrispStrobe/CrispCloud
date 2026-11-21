import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as image;
import 'package:quds_office_engine/quds_office_engine.dart';

/// Exercise nested research content through the existing transfer handshake.
/// Citation responses are controlled fixtures, not a live Zotero CSL session.
/// An independent converter supplies the DOCX consumed by the verify command.
void main(List<String> arguments) {
  if (arguments.length != 2 ||
      !{'generate', 'verify', 'diagnose'}.contains(arguments.first)) {
    throw ArgumentError(
      'Usage: nested_table_acceptance.dart generate DIR | verify FILE.docx | diagnose FILE.docx',
    );
  }
  if (arguments.first == 'generate') {
    final directory = Directory(arguments[1])..createSync(recursive: true);
    final document = _fixture();
    _verifyRestored(document);
    final active = WordSerializer().writeBytes(document);
    _verifyRestored(WordDeserializer().readBytes(active));
    File('${directory.path}/nested-active.docx').writeAsBytesSync(active);

    final session = WordZoteroCitingSession(
      document: document,
      documentId: _documentId,
    );
    _call(session, 'Document.setDocumentData', [
      WordZoteroDocumentData.toHttp(_preferences),
    ]);
    _call(session, 'Document.exportDocument', [
      'Http',
      'Open this document in another word processor and click Zotero Refresh to restore active citations.',
    ]);
    _call(session, 'Document.setDocumentData', [
      WordZoteroDocumentData.toHttp(_preferences),
    ]);
    _call(session, 'Document.activate');
    _call(session, 'Document.complete');
    session.apply();
    _require(
      WordZotero.fields(document).isEmpty,
      'export removed active fields',
    );
    _verifyContent(document);
    File(
      '${directory.path}/nested-transfer.docx',
    ).writeAsBytesSync(WordSerializer().writeBytes(document));
    File(
      '${directory.path}/nested-transfer.odt',
    ).writeAsBytesSync(OdtDocumentWriter.writeBytes(document));
    stdout.writeln(
      jsonEncode({
        'generated': directory.path,
        'citationOrder': _citationIds,
        'tableCount': 3,
        'tableDepth': 3,
        'pictureCount': 1,
        'scope':
            'Synthetic Add Note, controlled native formatting, transfer carriers.',
      }),
    );
    return;
  }

  _diagnose = arguments.first == 'diagnose';
  final input = File(arguments[1]);
  final document = WordDeserializer().readBytes(input.readAsBytesSync());
  _require(WordZoteroTransfer.isTransferDocument(document), 'transfer marker');
  _verifyContent(document);
  final before = document.paragraphs
      .map((paragraph) => paragraph.text)
      .toList();
  final session = WordZoteroCitingSession(
    document: document,
    documentId: _documentId,
  );
  _require(
    _call(session, 'Document.getDocumentData') == WordZoteroTransfer.marker,
    'protocol transfer marker',
  );
  _require(
    _call(session, 'Document.importDocument', ['Http']) == true,
    'import callback',
  );
  final fields = _fields(session);
  _require(fields.length == _citationIds.length, 'complete imported field set');
  final ids = <String>[];
  for (final field in fields) {
    final code = field['code']! as String;
    final metadata = WordZotero.metadataOf(' ADDIN ZOTERO_$code ');
    _require(metadata != null, 'imported citation metadata');
    final citation = ZoteroCitation.fromJson(metadata!);
    ids.add(citation.citationId);
    _call(session, 'Field.setText', [
      field['id'],
      '<i>(${citation.citationId})</i>',
      true,
    ]);
  }
  _require(
    jsonEncode(ids) == jsonEncode(_citationIds),
    'recursive citation order',
  );
  _require(
    jsonEncode(
          document.paragraphs.map((paragraph) => paragraph.text).toList(),
        ) ==
        jsonEncode(before),
    'import remains detached before completion',
  );
  _call(session, 'Document.setDocumentData', [
    WordZoteroDocumentData.toHttp(session.documentData),
  ]);
  _call(session, 'Document.activate');
  _call(session, 'Document.complete');
  session.prepareReview();
  _require(session.formattingWarnings.isEmpty, 'supported import formatting');
  session.apply();
  _phase = 'restored';
  _verifyRestored(document);
  var current = document;
  for (var round = 1; round <= 3; round++) {
    final bytes = WordSerializer().writeBytes(current);
    final output = File('${input.path}.restored-$round.docx');
    output.writeAsBytesSync(bytes);
    current = WordDeserializer().readBytes(bytes);
    _phase = 'save-reopen-$round';
    _verifyRestored(current);
  }
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'input': input.path,
      'result': _findings.isEmpty ? 'passed' : 'failed',
      'citationOrder': ids,
      'tableCount': 3,
      'tableDepth': 3,
      'outerRowspan': 2,
      'innerColspan': 2,
      'expectedListLabels': ['4.', '5.'],
      'observedListLabels': _listLabels(current),
      'findings': _findings,
      'pictureCount': 1,
      'qudsSaveReopenCycles': 3,
      'scope':
          'Independent file conversion and controlled Quds import/format callbacks; no live Zotero/Word/LibreOffice plugin acceptance.',
    }),
  );
  if (_findings.isNotEmpty) exitCode = 1;
}

// Diagnostic mode preserves a failed outcome while allowing citation and image
// checks to complete after an observed converter list-instance mismatch.
bool _diagnose = false;
String _phase = 'converted-carrier';
final _findings = <Map<String, Object?>>[];

const _documentId = 'quds-nested-transfer-acceptance';
const _citationIds = ['BEFORE1', 'OUTER2', 'DEEP3', 'AFTER4'];
const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==';
final _preferences = jsonEncode(<String, Object?>{
  'dataVersion': 4,
  'sessionID': 'synthetic-nested-transfer',
  'style': <String, Object?>{
    'styleID': 'http://www.zotero.org/styles/apa',
    'locale': 'de-DE',
    'hasBibliography': true,
    'bibliographyStyleHasBeenSet': false,
  },
  'prefs': <String, Object?>{'fieldType': 'Field', 'noteType': 0},
  'future': <String, Object?>{'preserve': 'العربية Ä 😀'},
});

String _placeholder(String id) =>
    '<a href="https://www.zotero.org/?$id">($id old)</a>';

String _payload() =>
    '<p>Before ${_placeholder('BEFORE1')}</p>'
    '<table><tbody><tr><td rowspan="2" data-colwidth="300">'
    '<p>Outer ${_placeholder('OUTER2')}</p>'
    '<table><tr><td colspan="2" data-colwidth="120,180">'
    '<p>Nested heading</p></td></tr>'
    '<tr><td data-colwidth="120"><ol start="4">'
    '<li>First nested list ${_placeholder('DEEP3')}</li>'
    '<li>Second nested list</li></ol>'
    '<table><tr><td style="background-color:#d8eaff">'
    '<p>Deepest content</p><p><img src="data:image/png;base64,$_png" '
    'width="24" height="18" title="Nested illustration" '
    'alt="Synthetic red pixel"></p></td></tr></table></td>'
    '<td data-colwidth="180"><p>Inner sibling</p></td></tr></table></td>'
    '<td data-colwidth="140"><p>Outer sibling</p></td></tr>'
    '<tr><td data-colwidth="140"><p>Outer bottom</p></td></tr>'
    '</tbody></table><p>After ${_placeholder('AFTER4')}</p>';

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
            'title': 'Nested Übertragung العربية 😀 $id',
          },
        },
      ],
      'future': <String, Object?>{
        'keep': true,
        'nested': ['one', 2],
      },
    });

WmlDocument _fixture() {
  final document = WmlDocument.empty(text: 'Target');
  final session = WordZoteroCitingSession(
    document: document,
    documentId: _documentId,
    insertionParagraph: document.paragraphs.single,
    insertionOffset: 0,
    insertionEndOffset: 6,
  );
  _call(session, 'Document.setDocumentData', [
    WordZoteroDocumentData.toHttp(_preferences),
  ]);
  final temporary =
      _call(session, 'Document.insertField', ['Http', 0])!
          as Map<String, Object>;
  _call(session, 'Field.delete', [temporary['id']]);
  _call(session, 'Document.insertText', [_payload()]);
  final ids = _citationIds.reversed.toList();
  final converted =
      (_call(session, 'Document.convertPlaceholdersToFields', [ids, 0, 'Http'])!
              as List<Object?>)
          .cast<Map<String, Object>>();
  for (final (index, field) in converted.indexed) {
    final citation = _citation(ids[index]);
    _call(session, 'Field.setCode', [
      field['id'],
      'ITEM CSL_CITATION ${jsonEncode(citation.toJson())}',
    ]);
    _call(session, 'Field.setText', [
      field['id'],
      '<i>(${citation.citationId})</i>',
      true,
    ]);
  }
  _call(session, 'Document.complete');
  session.apply();
  return document;
}

void _verifyContent(WmlDocument document) {
  final tables = WordTree.descendants(
    document.sections.expand((section) => section.blocks),
  ).whereType<WmlTable>().toList();
  _require(tables.length == 3, 'three native tables');
  final outer = tables[0];
  final inner = tables[1];
  final deep = tables[2];
  _require(outer.rows.length == 2, 'outer row count');
  final origin = outer.rows.first.cells.first;
  final continuation = outer.rows.last.cells.first;
  _require(
    origin.vMerge == WmlVMerge.restart && continuation.vMerge == WmlVMerge.cont,
    'outer vertical span',
  );
  _require(
    origin.blocks.whereType<WmlTable>().single == inner &&
        !continuation.blocks.any((block) => block is WmlTable),
    'inner table belongs only to outer merge origin',
  );
  _require(
    inner.rows.length == 2 && inner.rows.first.cells.single.gridSpan == 2,
    'inner horizontal span',
  );
  _require(
    inner.rows.last.cells.first.blocks.whereType<WmlTable>().single == deep,
    'three-level native ownership',
  );
  _require(
    deep.rows.single.cells.single.fillColor == 'D8EAFF',
    'deep cell background',
  );
  final paragraphs = document.paragraphs.toList();
  for (final text in [
    'Nested heading',
    'Deepest content',
    'Inner sibling',
    'Outer sibling',
    'Outer bottom',
  ]) {
    _require(
      paragraphs.where((paragraph) => paragraph.text == text).length == 1,
      'single retained paragraph: $text',
    );
  }
  final first = paragraphs.singleWhere(
    (paragraph) => paragraph.text.startsWith('First nested list '),
  );
  final second = paragraphs.singleWhere(
    (paragraph) => paragraph.text == 'Second nested list',
  );
  final labels = [
    first.properties.listLabel?.trim(),
    second.properties.listLabel?.trim(),
  ];
  if (jsonEncode(labels) != '["4.","5."]') {
    if (!_diagnose) {
      throw StateError(
        'Nested transfer acceptance failed: independent list numbering; '
        'expected [4., 5.], observed $labels',
      );
    }
    _findings.add({
      'phase': _phase,
      'check': 'independent list numbering',
      'expected': ['4.', '5.'],
      'observed': labels,
      'numberingIds': [first.properties.numId, second.properties.numId],
    });
  }
  final pictures = document.inlineVisuals.toList();
  _require(pictures.length == 1, 'one nested inline picture');
  _require(
    WordTree.paragraphs(deep.rows.single.cells.single.blocks)
        .expand((paragraph) => paragraph.inlines)
        .whereType<WmlRun>()
        .any((run) => identical(run.inlineVisual, pictures.single)),
    'picture remains owned by the deepest cell',
  );
  final actual = image.decodePng(pictures.single.visual.imageBytes!);
  final expected = image.decodePng(base64Decode(_png))!;
  _require(
    actual != null && actual.width == 1 && actual.height == 1,
    'retained PNG raster dimensions',
  );
  final pixel = actual!.getPixel(0, 0);
  final expectedPixel = expected.getPixel(0, 0);
  _require(
    pixel.r == expectedPixel.r &&
        pixel.g == expectedPixel.g &&
        pixel.b == expectedPixel.b &&
        pixel.a == expectedPixel.a,
    'retained PNG pixel channels',
  );
  _require(
    (pictures.single.visual.width - 18).abs() < .05 &&
        (pictures.single.visual.height - 13.5).abs() < .05,
    'retained 18 by 13.5 point picture dimensions',
  );
}

List<String?> _listLabels(WmlDocument document) => [
  for (final prefix in ['First nested list ', 'Second nested list'])
    document.paragraphs
        .singleWhere((paragraph) => paragraph.text.startsWith(prefix))
        .properties
        .listLabel
        ?.trim(),
];

void _verifyRestored(WmlDocument document) {
  _verifyContent(document);
  _require(
    !WordZoteroTransfer.isTransferDocument(document),
    'removed carrier framing',
  );
  final fields = WordZotero.fields(document);
  _require(
    fields.length == 4 && fields.every((field) => field.isValid),
    'four active valid citation fields',
  );
  _require(
    jsonEncode(fields.map((field) => field.citation?.citationId).toList()) ==
        jsonEncode(_citationIds),
    'retained recursive citation order',
  );
  for (final field in fields) {
    final citation = field.citation!;
    final id = citation.citationId;
    final item = citation.items.single;
    _require(item.locator == '27–29' && item.label == 'page', 'locator $id');
    _require(
      item.itemData?['title'] == 'Nested Übertragung العربية 😀 $id',
      'Unicode source metadata $id',
    );
    _require(
      jsonEncode(item.uris) == '["http://zotero.org/users/42/items/ABCD1234"]',
      'source URI $id',
    );
    _require(
      jsonEncode(citation.toJson()['future']) ==
          '{"keep":true,"nested":["one",2]}',
      'unknown citation metadata $id',
    );
    _require(field.cachedText == '($id)', 'formatted citation $id');
    _require(
      field.paragraph.inlines.whereType<WmlRun>().any(
        (run) =>
            run.text == '($id)' &&
            run.properties.italic &&
            run.hyperlink == null,
      ),
      'native italic citation after carrier removal $id',
    );
  }
  _require(
    WordZoteroDocumentData.read(document).contains('العربية Ä 😀'),
    'unknown document preference data',
  );
}

List<Map<String, Object>> _fields(WordZoteroCitingSession session) =>
    (_call(session, 'Document.getFields', ['Http'])! as List<Object?>)
        .cast<Map<String, Object>>();

Object? _call(
  WordZoteroCitingSession session,
  String command, [
  List<Object?> arguments = const [],
]) => session.handle(command, [_documentId, ...arguments]);

void _require(bool value, String label) {
  if (!value) throw StateError('Nested transfer acceptance failed: $label');
}
