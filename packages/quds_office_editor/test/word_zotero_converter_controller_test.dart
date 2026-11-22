import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _id = 'zotero-converter-controller';
const _fixtures = '../quds_office_engine/test/fixtures/zotero/converter';

Future<WmlDocument> _open(String format, String story) async {
  final bytes = File(
    '$_fixtures/$format-cycle-2/$story.$format',
  ).readAsBytesSync();
  return format == 'odt'
      ? OdtDocumentReader.readBytes(bytes)
      : WordDeserializer().readBytes(bytes);
}

List<WmlParagraph> _story(WmlDocument document, String story) {
  if (story == 'footnote') {
    return document.footnotes.single.allParagraphs.toList();
  }
  if (story == 'cell') {
    final table = document.sections.single.blocks.whereType<WmlTable>().single;
    return WordTree.paragraphs(table.rows.single.cells.first.blocks).toList();
  }
  return document.paragraphs.toList();
}

WordEditorController _controller(WmlDocument document) {
  final controller = WordEditorController(document: document);
  controller.proofing.enabled = false;
  addTearDown(() {
    if (!controller.isDisposed) controller.dispose();
  });
  return controller;
}

// Include note and metadata parts: checking just document.xml would miss a
// premature commit to the detached footnote story or document preferences.
// Namespace declarations can be repeated when an imported separator is saved;
// compare resolved names, attributes and ordered content instead of prefixes.
String _state(WmlDocument document) {
  final package = WordSerializer().write(document);
  return jsonEncode({
    for (final name in [
      '/word/document.xml',
      '/word/footnotes.xml',
      '/word/endnotes.xml',
      '/docProps/custom.xml',
    ])
      name: package.getPart(name) == null
          ? null
          : _xmlNode(
              XmlDocument.parse(package.getPart(name)!.readText()).root!,
            ),
    'preferences': WordZoteroDocumentData.read(document),
  });
}

Object _xmlNode(XmlNode node) {
  if (node is XmlElement) {
    final attributes = [
      for (final attribute in node.attributes)
        if (attribute.prefix != 'xmlns' && attribute.qualifiedName != 'xmlns')
          '${attribute.namespaceUri}/${attribute.localName}=${attribute.value}',
    ]..sort();
    return [
      node.namespaceUri,
      node.localName,
      attributes,
      node.children.map(_xmlNode).toList(),
    ];
  }
  final writer = XmlWriter();
  node.writeTo(writer);
  return writer.toString();
}

List<int> _selection(WordEditorController controller) => [
  controller.caret.paragraphIndex,
  controller.caret.logicalIndex,
  controller.caret.selectionAnchorParagraph,
  controller.caret.selectionAnchor,
];

List<Map<String, Object?>> _presentation(WmlDocument document, String story) =>
    [
      for (final paragraph in _story(document, story))
        {
          'rtl': paragraph.properties.rightToLeft,
          'alignment': paragraph.properties.justification.name,
          'left': paragraph.properties.indent.left,
          'right': paragraph.properties.indent.right,
          'heading': paragraph.properties.headingLevel,
        },
    ];

List<Map<String, Object?>> _tableBorders(WmlDocument document) => [
  for (final table in document.sections.expand(
    (section) => section.blocks.whereType<WmlTable>(),
  ))
    {
      'color': (table.properties.borderColor ?? '000000').toUpperCase(),
      'width': table.properties.borderWidth,
      'sides': [
        for (final row in table.rows)
          [
            for (final cell in row.cells)
              [
                cell.borderTop ?? table.properties.borders,
                cell.borderBottom ?? table.properties.borders,
                cell.borderLeft ?? table.properties.borders,
                cell.borderRight ?? table.properties.borders,
              ],
          ],
      ],
    },
];

void _expectTableBorders(
  WmlDocument document,
  List<Map<String, Object?>> expected,
) {
  final actual = _tableBorders(document);
  expect(actual, hasLength(expected.length));
  for (var i = 0; i < expected.length; i++) {
    expect(actual[i]['color'], expected[i]['color']);
    expect(actual[i]['width'], closeTo(expected[i]['width']! as num, .02));
    expect(actual[i]['sides'], expected[i]['sides']);
  }
}

String _outsideStory(WmlDocument document, String story) {
  final target = _story(document, story).toSet();
  return jsonEncode({
    'body': [
      for (final paragraph in document.paragraphs)
        if (!target.contains(paragraph)) paragraph.text,
    ],
    'notes': [
      for (final note in [...document.footnotes, ...document.endnotes])
        [
          note.id,
          note.endnote,
          for (final paragraph in note.allParagraphs)
            if (!target.contains(paragraph)) paragraph.text,
        ],
    ],
  });
}

Object? _call(
  WordZoteroTransaction transaction,
  String command, [
  List<Object?> arguments = const [],
]) => transaction.handle(command, [_id, ...arguments]);

WordZoteroTransaction _begin(WordEditorController controller) =>
    controller.beginZoteroTransaction(
      documentId: _id,
      command: ZoteroCitingCommand.refresh,
    );

String _refreshedText(String citationId) => '($citationId refreshed 2026)';

Map<String, ZoteroCitation> _stageRefresh(
  WordEditorController controller,
  WordZoteroTransaction transaction,
  String story,
) {
  final originals = {
    for (final field in controller.zoteroFields)
      field.citation!.citationId: field,
  };
  expect(originals.keys, unorderedEquals(['FIRST1', 'SECOND2']));
  final fields =
      (_call(transaction, 'Document.getFields', ['Http']) as List<Object?>)
          .cast<Map<String, Object>>();
  expect(fields, hasLength(2));
  final expected = <String, ZoteroCitation>{};
  final selection = _selection(controller);
  final originalState = _state(controller.document);
  for (final field in fields) {
    final original = originals.values.singleWhere(
      (candidate) => (field['code']! as String).contains(
        '"citationID":"${candidate.citation!.citationId}"',
      ),
    );
    final citation = original.citation!;
    expect(original.canEdit, isTrue);
    expect(controller.canEditZoteroFieldNatively(original), isTrue);
    expect(field['noteIndex'], story == 'footnote' ? 1 : 0);

    _call(transaction, 'Field.select', [field['id']]);
    final context = transaction.selectedFieldContext!;
    expect(context.sourceField!.paragraph, same(original.paragraph));
    expect(context.sourceField!.citation!.toJson(), citation.toJson());
    expect(context.sourceText, original.cachedText);
    expect(context.sourceRanges, hasLength(1));
    final range = context.sourceRanges.single;
    expect(range.paragraph, same(original.paragraph));
    expect(
      range.paragraph.text.substring(range.start, range.end),
      original.cachedText,
    );
    if (story == 'footnote') {
      expect(context.sourceNote, same(controller.document.footnotes.single));
    } else {
      expect(context.sourceNote, isNull);
    }
    expect(controller.zoteroFieldContext!.sourceText, original.cachedText);
    expect(controller.noteEditingTarget, isNull);
    expect(_selection(controller), selection);

    final text = _refreshedText(citation.citationId);
    final html = citation.citationId == 'FIRST1'
        ? '<i>$text</i>'
        : '<b>$text</b>';
    final updated = citation.withItems(
      citation.items,
      plainCitation: text,
      formattedCitation: html,
      noteIndex: citation.noteIndex,
    );
    expected[citation.citationId] = updated;
    _call(transaction, 'Field.setCode', [
      field['id'],
      'ITEM CSL_CITATION ${jsonEncode(updated.toJson())}',
    ]);
    _call(transaction, 'Field.setText', [field['id'], html, true]);
    // Field.select continues to identify the original source after Zotero has
    // supplied a replacement; staged text must never become editor context.
    expect(transaction.selectedFieldContext!.sourceText, original.cachedText);
    expect(_state(controller.document), originalState);
    expect(controller.canUndo, isFalse);
    expect(controller.isDirty, isFalse);
  }
  return expected;
}

void _complete(WordZoteroTransaction transaction) {
  _call(transaction, 'Document.complete');
  transaction.session.prepareReview();
}

void _expectRefreshed(
  WmlDocument document,
  String story,
  Map<String, ZoteroCitation> expected,
  List<String> expectedText,
  List<Map<String, Object?>> presentation,
  String outsideStory,
) {
  final paragraphs = _story(document, story);
  expect(paragraphs.map((paragraph) => paragraph.text), expectedText);
  expect(_outsideStory(document, story), outsideStory);
  final actualPresentation = _presentation(document, story);
  expect(actualPresentation, hasLength(presentation.length));
  for (var i = 0; i < presentation.length; i++) {
    for (final entry in presentation[i].entries) {
      expect(
        actualPresentation[i][entry.key],
        entry.value is num ? closeTo(entry.value! as num, .02) : entry.value,
        reason: 'Paragraph $i ${entry.key}',
      );
    }
  }
  final fields = WordZotero.fields(document);
  expect(fields, hasLength(2));
  expect(WordFieldSpans.unbalanced(document), isEmpty);
  for (final field in fields) {
    final citationId = field.citation!.citationId;
    expect(field.canEdit, isTrue);
    expect(field.isValid, isTrue);
    expect(paragraphs.contains(field.paragraph), isTrue);
    expect(field.citation!.toJson(), expected[citationId]!.toJson());
    expect(field.cachedText, _refreshedText(citationId));
    final runs = WordZotero.copyCitationResult(field);
    expect(runs, isNotEmpty);
    expect(
      runs.every(
        (run) => citationId == 'FIRST1'
            ? run.properties.italic
            : run.properties.bold,
      ),
      isTrue,
    );
  }
  for (final marker in ['RTL_COLOUR', 'LTR_COLOUR']) {
    final run = paragraphs
        .expand((paragraph) => paragraph.inlines)
        .whereType<WmlRun>()
        .singleWhere((run) => run.text.contains(marker));
    expect(run.properties.color, marker == 'RTL_COLOUR' ? '123456' : '224466');
    expect(
      run.properties.highlight,
      marker == 'RTL_COLOUR' ? 'FAE696' : 'CCDDEE',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final format in ['docx', 'odt']) {
    for (final story in ['body', 'footnote', 'cell']) {
      test(
        'retained Writer $format $story Refresh is detached, undoable and editable after save',
        () async {
          final document = await _open(format, story);
          final controller = _controller(document);
          final paragraphs = _story(document, story);
          final before = _state(document);
          final beforeRevision = controller.contentRevision;
          final preferences = WordZoteroDocumentData.read(document);
          final presentation = _presentation(document, story);
          final borders = _tableBorders(document);
          final outsideStory = _outsideStory(document, story);
          final selection = _selection(controller);
          final expectedText = paragraphs
              .map(
                (paragraph) => paragraph.text
                    .replaceAll('(FIRST1)', _refreshedText('FIRST1'))
                    .replaceAll('(SECOND2)', _refreshedText('SECOND2')),
              )
              .toList();
          final transaction = _begin(controller);
          final expected = _stageRefresh(controller, transaction, story);
          _complete(transaction);
          expect(_state(document), before);
          expect(controller.zoteroFieldContext, isNull);
          expect(controller.contentRevision, beforeRevision);
          expect(controller.canUndo, isFalse);

          transaction.apply();
          _expectRefreshed(
            document,
            story,
            expected,
            expectedText,
            presentation,
            outsideStory,
          );
          expect(_story(document, story), orderedEquals(paragraphs));
          _expectTableBorders(document, borders);
          expect(WordZoteroDocumentData.read(document), preferences);
          expect(_selection(controller), selection);
          expect(controller.canUndo, isTrue);
          expect(controller.canRedo, isFalse);
          expect(controller.isDirty, isTrue);
          final after = _state(document);

          controller.undo();
          expect(_state(document), before);
          _expectTableBorders(document, borders);
          expect(controller.canUndo, isFalse);
          expect(controller.canRedo, isTrue);
          expect(_selection(controller), selection);
          controller.redo();
          expect(_state(document), after);
          _expectTableBorders(document, borders);
          _expectRefreshed(
            document,
            story,
            expected,
            expectedText,
            presentation,
            outsideStory,
          );

          final docx = WordDeserializer().readBytes(controller.saveBytes());
          _expectTableBorders(docx, borders);
          _expectRefreshed(
            docx,
            story,
            expected,
            expectedText,
            presentation,
            outsideStory,
          );
          if (format == 'odt' || story == 'cell') {
            var odt = await OdtDocumentReader.readBytes(
              OdtDocumentWriter.writeEditableZoteroBytes(document),
            );
            _expectRefreshed(
              odt,
              story,
              expected,
              expectedText,
              presentation,
              outsideStory,
            );
            _expectTableBorders(odt, borders);
            // The retained DOCX cell fixture has visible borders. Keep its
            // original stroke and active fields through both portable formats,
            // including a second editable ODT save after native DOCX reopening.
            final exchanged = WordDeserializer().readBytes(
              WordSerializer().writeBytes(odt),
            );
            _expectTableBorders(exchanged, borders);
            odt = await OdtDocumentReader.readBytes(
              OdtDocumentWriter.writeEditableZoteroBytes(exchanged),
            );
            _expectRefreshed(
              odt,
              story,
              expected,
              expectedText,
              presentation,
              outsideStory,
            );
            _expectTableBorders(odt, borders);
          }
          expect(_state(document), after);
        },
      );

      test(
        'retained Writer $format $story rejects a stale completed Refresh',
        () async {
          final document = await _open(format, story);
          final controller = _controller(document);
          final before = _state(document);
          final transaction = _begin(controller);
          _stageRefresh(controller, transaction, story);
          _complete(transaction);
          controller.insertText('Draft ');
          final edited = _state(document);
          final revision = controller.contentRevision;
          final selection = _selection(controller);
          expect(edited, isNot(before));
          expect(() => transaction.apply(), throwsStateError);
          expect(_state(document), edited);
          expect(controller.contentRevision, revision);
          expect(_selection(controller), selection);
          expect(controller.zoteroFieldContext, isNull);
          expect(controller.zoteroFields.map((field) => field.cachedText), [
            '(FIRST1)',
            '(SECOND2)',
          ]);
          controller.undo();
          expect(_state(document), before);
          expect(controller.canUndo, isFalse);
        },
      );
    }
  }
}
