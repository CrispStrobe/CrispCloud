// Controlled Zotero/file-converter acceptance; this does not run a Zotero UI.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

const _sessionId = 'footnote-separator-acceptance';

void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

WmlFootnoteSeparator geometry(String name) => switch (name) {
  'custom' => const WmlFootnoteSeparator(
    beforeSpacing: 4,
    thickness: 1,
    afterSpacing: 7,
    relativeWidth: 0.5,
    alignment: WmlFootnoteSeparatorAlignment.right,
    color: 0x176346,
  ),
  'zero' => const WmlFootnoteSeparator(
    beforeSpacing: 0,
    thickness: 0.5,
    afterSpacing: 0,
    relativeWidth: 0.5,
    alignment: WmlFootnoteSeparatorAlignment.center,
  ),
  'hidden' => const WmlFootnoteSeparator(
    beforeSpacing: 4,
    thickness: 2,
    afterSpacing: 7,
    relativeWidth: 0.5,
    lineStyle: WmlFootnoteSeparatorLineStyle.none,
  ),
  _ => throw ArgumentError('Unknown separator preset: $name'),
};

WmlParagraph cited(String id, String text) {
  final paragraph = WmlParagraph(inlines: [WmlRun(text: '$text ')]);
  WordZotero.insertCitation(
    paragraph,
    ZoteroCitation.fromJson({
      'citationID': id,
      'citationItems': [
        {
          'id': 17,
          'uris': ['http://zotero.org/users/42/items/ABCD1234'],
          'locator': '12',
          'itemData': {'id': 17, 'type': 'book', 'title': 'Source العربية 😀'},
          'futureItem': {'preserve': true},
        },
      ],
      'properties': {
        'plainCitation': '($id)',
        'noteIndex': id == 'note' ? 1 : 0,
      },
      'futureCitation': ['keep', 42],
    }),
    index: paragraph.text.length,
  );
  return paragraph;
}

WmlDocument create(String preset) {
  final body = cited('body', 'Research body العربية 😀');
  body.inlines.add(WmlRun(text: '1', noteRefId: 1));
  return WmlDocument(
    footnoteSeparator: geometry(preset),
    sections: [
      WmlSection(
        blocks: [
          body,
          WmlParagraph(inlines: [WmlRun(text: 'After the reference.')]),
        ],
      ),
    ],
    footnotes: [
      WmlNote(
        id: 1,
        endnote: false,
        paragraphs: [cited('note', 'Authored footnote العربية 😀')],
      ),
    ],
    zoteroDocumentData: jsonEncode({
      'dataVersion': 4,
      'style': {
        'styleID': 'http://www.zotero.org/styles/apa',
        'locale': 'en-US',
      },
      'prefs': {'fieldType': 'Field', 'noteType': 0},
      'futureDocument': {'preserve': true},
    }),
  );
}

Map<String, Object?> inspect(WmlDocument document, String preset) {
  final separator = document.footnoteSeparator;
  require(separator != null, 'Missing active separator');
  final actual = separator!;
  final expected = geometry(preset);
  for (final pair in [
    (actual.beforeSpacing, expected.beforeSpacing),
    (actual.thickness, expected.thickness),
    (actual.afterSpacing, expected.afterSpacing),
  ]) {
    require(
      (pair.$1 - pair.$2).abs() <= 0.05,
      'Separator length changed: $pair',
    );
  }
  require(
    (actual.relativeWidth - expected.relativeWidth).abs() < 0.00001,
    'Separator relative width changed',
  );
  require(
    actual.alignment == expected.alignment,
    'Separator alignment changed',
  );
  require(actual.color == expected.color, 'Separator color changed');
  require(
    actual.lineStyle == expected.lineStyle,
    'Separator line style changed',
  );
  require(
    document.footnotes.length == 1 && document.endnotes.isEmpty,
    'Note ownership changed',
  );
  final fields = WordZotero.fields(document);
  require(fields.length == 2, 'Expected two active citations');
  require(
    fields.map((f) => f.citation?.citationId).join(',') == 'body,note',
    'Citation order changed',
  );
  for (final field in fields) {
    final id = field.citation!.citationId;
    require(field.canEdit, 'Citation is no longer editable');
    require(
      field.cachedText == '($id)' || field.cachedText == '(Refreshed $id)',
      'Citation cache changed',
    );
    require(
      jsonEncode(field.metadata!['futureCitation']) == '["keep",42]',
      'Future citation metadata changed',
    );
    final item = (field.metadata!['citationItems'] as List).single as Map;
    require(
      (item['futureItem'] as Map)['preserve'] == true,
      'Future item metadata changed',
    );
    require(item['locator'] == '12', 'Locator changed');
  }
  require(
    document.footnotes.single.allParagraphs.contains(fields.last.paragraph),
    'Footnote citation moved out of its note',
  );
  final data = jsonDecode(WordZoteroDocumentData.read(document)) as Map;
  require(
    (data['futureDocument'] as Map)['preserve'] == true,
    'Document preferences changed',
  );
  return {
    'preset': preset,
    'separator': {
      'beforeSpacing': actual.beforeSpacing,
      'thickness': actual.thickness,
      'afterSpacing': actual.afterSpacing,
      'relativeWidth': actual.relativeWidth,
      'alignment': actual.alignment.name,
      'color': actual.color.toRadixString(16).padLeft(6, '0'),
      'lineStyle': actual.lineStyle.name,
      'reservedHeight': actual.reservedHeight,
    },
    'activeFields': fields.length,
    'citationIds': fields.map((f) => f.citation!.citationId).toList(),
    'caches': fields.map((f) => f.cachedText).toList(),
    'footnotes': document.footnotes.length,
    'ownershipAndUnknownMetadataPreserved': true,
  };
}

void refresh(WmlDocument document) {
  final session = WordZoteroCitingSession(
    document: document,
    documentId: _sessionId,
    insertionParagraph: document.paragraphs.first,
  );
  Object? call(String command, [List<Object?> arguments = const []]) =>
      session.handle(command, [_sessionId, ...arguments]);
  final nativeFields = WordZotero.fields(document);
  final fields = (call('Document.getFields', ['Http']) as List)
      .cast<Map<String, Object?>>();
  for (var index = 0; index < fields.length; index++) {
    final old = nativeFields[index].citation!;
    final label = '(Refreshed ${old.citationId})';
    final updated = old.withItems(
      old.items,
      plainCitation: label,
      formattedCitation: label,
    );
    call('Field.setCode', [
      fields[index]['id'],
      'ITEM CSL_CITATION ${jsonEncode(updated.toJson())}',
    ]);
    call('Field.setText', [fields[index]['id'], label, false]);
  }
  call('Document.complete');
  session.prepareReview();
  session.apply();
}

Future<void> main(List<String> args) async {
  if (args.length < 2 || !{'create', 'inspect', 'cycle'}.contains(args[0])) {
    throw ArgumentError(
      'create OUTPUT.odt [PRESET] | inspect INPUT.odt [PRESET] | cycle INPUT.odt OUTPUT_DIR [PRESET]',
    );
  }
  final command = args[0];
  final preset = args.length > (command == 'cycle' ? 3 : 2)
      ? args.last
      : 'custom';
  if (command == 'create') {
    final document = create(preset);
    final bytes = OdtDocumentWriter.writeEditableZoteroBytes(document);
    final file = File(args[1]);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
    final reopened = await OdtDocumentReader.readBytes(bytes);
    stdout.writeln(
      jsonEncode({
        'accepted': true,
        'file': file.path,
        'sha256': sha256.convert(bytes).toString(),
        ...inspect(reopened, preset),
      }),
    );
    return;
  }
  final source = File(args[1]).readAsBytesSync();
  var document = await OdtDocumentReader.readBytes(source);
  final reports = <Map<String, Object?>>[inspect(document, preset)];
  if (command == 'cycle') {
    require(args.length >= 3, 'Missing output directory');
    final directory = Directory(args[2])..createSync(recursive: true);
    refresh(document);
    reports.add(inspect(document, preset));
    for (var index = 1; index <= 2; index++) {
      final docx = WordSerializer().writeBytes(document);
      File('${directory.path}/native-$index.docx').writeAsBytesSync(docx);
      document = WordDeserializer().readBytes(docx);
      reports.add(inspect(document, preset));
      final odt = OdtDocumentWriter.writeEditableZoteroBytes(document);
      File('${directory.path}/native-$index.odt').writeAsBytesSync(odt);
      document = await OdtDocumentReader.readBytes(odt);
      reports.add(inspect(document, preset));
    }
  }
  require(
    base64Encode(source) == base64Encode(File(args[1]).readAsBytesSync()),
    'Input file changed',
  );
  stdout.writeln(
    jsonEncode({
      'accepted': true,
      'input': args[1],
      'sourceSha256': sha256.convert(source).toString(),
      'stages': reports,
      'controlledRefresh': command == 'cycle',
    }),
  );
}
