import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _id = 'vertical-research-controller';
const _first = '<a href="https://www.zotero.org/?ABC123">(old first)</a>';
const _second = '<a href="https://www.zotero.org/?DEF456">(old second)</a>';
// Independent 3x2 RGBA PNG, shared with the existing research-image fixture.
const _pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAMAAAACCAYAAACddGYaAAAAF0lEQVR4nGP4z8DwHwwZ/v8HIyABZgEAqm8O8tH19KMAAAAASUVORK5CYII=';
const _image =
    '<a href="https://example.org/figure"><img '
    'src="data:image/png;base64,$_pngBase64" width="48" height="32" '
    'alt="Six colored samples" title="Merged-cell figure"></a>';
const _html =
    '<div data-schema-version="9"><table><tbody><tr>'
    '<td rowspan="3" colspan="2" data-colwidth="120,160" '
    'style="background-color: #ffeedd"><ol start="3">'
    '<li>First $_first $_image</li><li><i>Detail</i></li></ol></td>'
    '<td data-colwidth="240"><p>Top right</p></td></tr>'
    '<tr><td data-colwidth="240"><p>Middle right</p></td></tr>'
    '<tr><td data-colwidth="240"><p><b>Second $_second</b></p></td></tr>'
    '<tr><td colspan="3" data-colwidth="120,160,240">'
    '<p>Independent final row</p></td></tr></tbody></table></div>';

String _preferences(int type) => jsonEncode({
  'dataVersion': 4,
  'sessionID': 'vertical-research-session',
  'zoteroVersion': '10.0',
  'style': {
    'styleID': type == 0
        ? 'http://www.zotero.org/styles/apa'
        : 'http://www.zotero.org/styles/chicago-note-bibliography',
    'locale': 'de-DE',
  },
  'prefs': {'fieldType': 'Http', 'noteType': type},
});

String _code(String id, String text, int noteIndex) =>
    'ITEM CSL_CITATION ${jsonEncode(ZoteroCitation(
      citationId: id,
      plainCitation: text,
      noteIndex: noteIndex,
      items: [
        ZoteroCitationItem.fromCsl(itemData: {'id': id, 'type': 'book', 'title': 'Source $id'}, uris: ['http://zotero.org/users/42/items/${id == 'first' ? 'ABCD1234' : 'EFGH5678'}'], locator: '4', label: 'page'),
      ],
    ).toJson())}';

WmlDocument _document() {
  final package = OpcPackage.create(OpcPackageKind.word);
  package.createPart(
    '/word/media/preserved.bin',
    'application/octet-stream',
    Uint8List.fromList([7, 11, 13]),
  );
  package
      .relationshipsFor('/word/document.xml')
      .add(type: RelationshipTypes.image, target: 'media/preserved.bin');
  return WmlDocument(
    package: package,
    sections: [
      WmlSection(
        blocks: [
          WmlParagraph(
            inlines: [
              WmlRun(text: 'Before', properties: WmlRunProps(bold: true)),
              WmlRun(
                text: 'After',
                properties: WmlRunProps(italic: true),
                hyperlink: const WmlHyperlink(url: 'https://example.org/tail'),
              ),
            ],
          ),
          WmlParagraph(inlines: [WmlRun(text: 'Unrelated')]),
        ],
      ),
    ],
  );
}

typedef _Target = ({WordEditorController controller, WmlNote? note});

_Target _target(int type, {bool reverse = false}) {
  final document = _document();
  final note = type == 0
      ? null
      : WordNotes.insert(
          document,
          document.paragraphs.last,
          text: 'Left chosen Right',
          endnote: type == 2,
        );
  final controller = WordEditorController(document: document);
  controller.proofing.enabled = false;
  controller.caret
    ..logicalIndex = reverse ? 1 : 6
    ..selectionAnchor = reverse ? 6 : 1
    ..selectionAnchorParagraph = 0;
  if (note != null) {
    controller.setNoteEditingTarget(
      note,
      TextSelection(
        baseOffset: reverse ? 11 : 5,
        extentOffset: reverse ? 5 : 11,
      ),
    );
  }
  addTearDown(() {
    if (!controller.isDisposed) controller.dispose();
  });
  return (controller: controller, note: note);
}

WordZoteroTransaction _begin(_Target target, ZoteroCitingCommand command) =>
    target.controller.beginZoteroTransaction(documentId: _id, command: command);

Object? _call(
  WordZoteroTransaction transaction,
  String command, [
  List<Object?> arguments = const [],
]) {
  transaction.assertCurrent();
  return transaction.session.handle(command, [_id, ...arguments]);
}

void _insert(WordZoteroTransaction transaction, int type, String html) {
  _call(transaction, 'Document.setDocumentData', [_preferences(type)]);
  final temporary =
      _call(transaction, 'Document.insertField', ['Http', type])!
          as Map<String, Object>;
  _call(transaction, 'Field.delete', [temporary['id']]);
  _call(transaction, 'Document.insertText', [html]);
}

void _stage(WordZoteroTransaction transaction, int type) {
  _insert(transaction, type, _html);
  // Zotero may return placeholders in an order different from document order.
  final fields =
      (_call(transaction, 'Document.convertPlaceholdersToFields', [
                ['DEF456', 'ABC123'],
                type,
                'Http',
              ])!
              as List<Object?>)
          .cast<Map<String, Object>>();
  for (var i = 0; i < fields.length; i++) {
    final field = fields[i];
    final id = i == 0 ? 'second' : 'first';
    final text = i == 0 ? '(Second, 2025)' : '(First, 2024)';
    _call(transaction, 'Field.setCode', [
      field['id'],
      _code(id, text, field['noteIndex']! as int),
    ]);
    _call(transaction, 'Field.setText', [field['id'], '<i>$text</i>', true]);
  }
}

void _complete(WordZoteroTransaction transaction) {
  _call(transaction, 'Document.complete');
  transaction.session.prepareReview();
}

Object? _block(WmlBlock block) {
  if (block is WmlTable) {
    return [
      'table',
      block.grid,
      for (final row in block.rows)
        [
          row.height,
          for (final cell in row.cells)
            [
              cell.gridSpan,
              cell.vMerge.name,
              cell.width,
              cell.fillColor,
              for (final child in cell.blocks) _block(child),
            ],
        ],
    ];
  }
  final paragraph = block as WmlParagraph;
  return [
    'paragraph',
    paragraph.text,
    paragraph.properties.numId,
    paragraph.properties.ilvl,
    paragraph.properties.listLabel,
    for (final run in paragraph.inlines.whereType<WmlRun>())
      [
        run.text,
        run.properties.bold,
        run.properties.italic,
        run.hyperlink?.url,
        run.fieldInstruction,
        run.noteRefId,
        run.noteRefEndnote,
        if (run.inlineVisual case final WmlVisual image)
          [
            image.visual.width,
            image.visual.height,
            base64Encode(image.visual.imageBytes!),
          ],
      ],
  ];
}

String _state(WmlDocument document) => jsonEncode({
  'body': [
    for (final section in document.sections)
      [for (final block in section.blocks) _block(block)],
  ],
  'notes': [
    for (final note in [...document.footnotes, ...document.endnotes])
      [note.id, note.endnote, for (final block in note.blocks) _block(block)],
  ],
  'preferences': WordZoteroDocumentData.read(document),
});

String _packageState(WmlDocument document) {
  final package = document.package!;
  final names = package.partNames.toList()..sort();
  return jsonEncode([
    for (final uri in names)
      [
        uri,
        package.getPart(uri)!.contentType,
        base64Encode(package.getPart(uri)!.readBytes()),
        for (final rel in package.relationshipsFor(uri).items)
          [rel.id, rel.type, rel.target, rel.targetMode.name],
      ],
  ]);
}

List<WmlBlock> _blocks(_Target target) =>
    target.note?.blocks ?? target.controller.document.sections.single.blocks;

WmlTable _table(_Target target) => _blocks(target).whereType<WmlTable>().single;

void _expectResearch(WmlDocument document, WmlTable table, int type) {
  expect(table.grid, [90.0, 120.0, 180.0]);
  expect(table.rows.map((r) => r.cells.map((c) => c.gridSpan).toList()), [
    [2, 1],
    [2, 1],
    [2, 1],
    [3],
  ]);
  expect(table.rows.take(3).map((r) => r.cells.first.vMerge), [
    WmlVMerge.restart,
    WmlVMerge.cont,
    WmlVMerge.cont,
  ]);
  final master = table.rows.first.cells.first;
  expect(master.width, 210);
  expect(master.fillColor, 'FFEEDD');
  expect(WordTable.supportsGridAddressing(table), isTrue);
  for (var row = 0; row < 3; row++) {
    for (var col = 0; col < 2; col++) {
      final selected = WordTable.cellAtGrid(table, row, col)!;
      expect((selected.row, selected.col), (0, 0));
      expect(selected.cell, same(master));
    }
  }
  final masterParagraphs = WordTree.paragraphs(master.blocks).toList();
  expect(masterParagraphs.map((p) => p.properties.listLabel), ['3. ', '4. ']);
  expect(masterParagraphs.first.text, 'First (First, 2024) \uFFFC');
  expect(masterParagraphs.last.text, 'Detail');
  expect(
    masterParagraphs.last.inlines.whereType<WmlRun>().single.properties.italic,
    isTrue,
  );
  for (final row in table.rows.skip(1).take(2)) {
    final placeholder = row.cells.first;
    expect(placeholder.blocks, hasLength(1));
    final paragraph = placeholder.blocks.single as WmlParagraph;
    expect(paragraph.text, isEmpty);
    expect(paragraph.properties.listLabel, isNull);
    expect(
      paragraph.inlines.whereType<WmlRun>().any((r) => r.inlineVisual != null),
      isFalse,
    );
  }
  expect(table.rows.last.cells.single.vMerge, WmlVMerge.none);
  expect(
    WordTree.paragraphs(table.rows.last.cells.single.blocks).single.text,
    'Independent final row',
  );
  final pictures = WordTree.paragraphs([table])
      .expand((p) => p.inlines.whereType<WmlRun>())
      .where((run) => run.inlineVisual != null)
      .toList();
  expect(pictures, hasLength(1));
  final pictureRun = pictures.single;
  expect(masterParagraphs.first.inlines, contains(same(pictureRun)));
  expect(pictureRun.isAtomic, isTrue);
  expect(pictureRun.hyperlink?.url, 'https://example.org/figure');
  final picture = pictureRun.inlineVisual!.visual;
  expect(picture.imageBytes, orderedEquals(base64Decode(_pngBase64)));
  expect(picture.width, closeTo(36, .001));
  expect(picture.height, closeTo(24, .001));
  expect(picture.picture.altTitle, 'Merged-cell figure');
  expect(picture.picture.altDescription, 'Six colored samples');

  final fields = WordZotero.fields(document);
  expect(fields.map((f) => f.citation!.citationId), ['first', 'second']);
  expect(fields.map((f) => f.cachedText), ['(First, 2024)', '(Second, 2025)']);
  expect(fields.every((f) => f.canEdit), isTrue);
  expect(fields.first.paragraph, same(masterParagraphs.first));
  expect(fields.last.paragraph, same(table.rows[2].cells.last.blocks.single));
  expect(fields.every((f) => f.citation!.items.single.locator == '4'), isTrue);
  expect(WordFieldSpans.unbalanced(document), isEmpty);
  expect(document.footnotes, hasLength(type == 1 ? 1 : 0));
  expect(document.endnotes, hasLength(type == 2 ? 1 : 0));
}

void _expectReopened(WmlDocument document, int type) {
  var reopened = document;
  for (var cycle = 0; cycle < 2; cycle++) {
    reopened = WordDeserializer().readBytes(
      WordSerializer().writeBytes(reopened),
    );
    final blocks = type == 0
        ? reopened.sections.single.blocks
        : (type == 1 ? reopened.footnotes : reopened.endnotes).single.blocks;
    _expectResearch(reopened, blocks.whereType<WmlTable>().single, type);
    expect(
      reopened.package!.getPart('/word/media/preserved.bin')!.readBytes(),
      [7, 11, 13],
    );
    final media = reopened.package!.parts.where(
      (p) => p.contentType == 'image/png',
    );
    expect(media, hasLength(1));
    expect(media.single.readBytes(), orderedEquals(base64Decode(_pngBase64)));
  }
}

typedef _Step = Map<String, Object?> Function(_Desktop desktop);

class _Desktop {
  _Desktop(this.type, {this.cancelAfterStaging = false});
  final int type;
  final bool cancelAfterStaging;
  final requests = <ZoteroHttpRequest>[];
  final fields = <Map<String, Object?>>[];
  String documentId = '';
  String fieldId = '';
  String command = '';

  Map<String, Object?> message(String name, List<Object?> args) => {
    'command': name,
    'arguments': args,
  };

  List<_Step> get steps => [
    (d) => d.message('Application.getActiveDocument', []),
    (d) => d.message('Document.getDocumentData', [d.documentId]),
    (d) => d.message('Document.setDocumentData', [
      d.documentId,
      _preferences(type),
    ]),
    (d) => d.message('Document.insertField', [d.documentId, 'Http', type]),
    (d) => d.message('Field.delete', [d.documentId, d.fieldId]),
    (d) => d.message('Document.insertText', [d.documentId, _html]),
    if (!cancelAfterStaging) ...[
      (d) => d.message('Document.convertPlaceholdersToFields', [
        d.documentId,
        ['DEF456', 'ABC123'],
        type,
        'Http',
      ]),
      for (var i = 0; i < 2; i++) ...[
        (d) => d.message('Field.setCode', [
          d.documentId,
          d.fields[i]['id'],
          _code(
            i == 0 ? 'second' : 'first',
            i == 0 ? '(Second, 2025)' : '(First, 2024)',
            d.fields[i]['noteIndex']! as int,
          ),
        ]),
        (d) => d.message('Field.setText', [
          d.documentId,
          d.fields[i]['id'],
          i == 0 ? '<i>(Second, 2025)</i>' : '<i>(First, 2024)</i>',
          true,
        ]),
      ],
    ],
    (d) => d.message('Document.complete', [d.documentId]),
  ];

  Future<ZoteroHttpResponse> send(ZoteroHttpRequest request) async {
    final index = requests.length;
    requests.add(request);
    final Object? decoded = jsonDecode(request.body!);
    if (index == 0) {
      final initial = decoded! as Map<String, Object?>;
      documentId = initial['docId']! as String;
      command = initial['command']! as String;
    } else if (decoded case {'id': final String id}) {
      fieldId = id;
    } else if (decoded is List<Object?>) {
      fields
        ..clear()
        ..addAll(decoded.cast<Map<String, Object?>>());
    }
    expect(index, lessThan(steps.length));
    return ZoteroHttpResponse(
      statusCode: 200,
      headers: const {},
      body: jsonEncode(steps[index](this)),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);

  for (final command in [
    ZoteroCitingCommand.addNote,
    ZoteroCitingCommand.addAnnotation,
  ]) {
    for (final type in [0, 1, 2]) {
      final story = ['body', 'footnote', 'endnote'][type];
      for (final reverse in [false, true]) {
        test(
          '${command.name} rowspan/colspan in $story restores ${reverse ? 'backward' : 'forward'} selection, rich owners and package on undo',
          () {
            final target = _target(type, reverse: reverse);
            final controller = target.controller;
            final document = controller.document;
            final before = _state(document);
            final packageBefore = _packageState(document);
            final selectionBefore = controller.noteEditingTarget?.selection;
            final transaction = _begin(target, command);
            _stage(transaction, type);
            _complete(transaction);
            expect(_state(document), before);
            expect(_packageState(document), packageBefore);
            expect(controller.canUndo, isFalse);
            transaction.apply();
            final table = _table(target);
            _expectResearch(document, table, type);
            final masterParagraph = table.rows.first.cells.first.blocks.first;
            if (type == 0) {
              final blocks = _blocks(target);
              expect((blocks.first as WmlParagraph).text, 'B');
              final suffix = blocks[blocks.indexOf(table) + 1] as WmlParagraph;
              expect(suffix.text, 'After');
              expect(
                suffix.inlines.whereType<WmlRun>().last.hyperlink?.url,
                'https://example.org/tail',
              );
              expect(
                document.paragraphs.elementAt(controller.caret.paragraphIndex),
                same(suffix),
              );
              expect(controller.caret.logicalIndex, 0);
            } else {
              expect(controller.noteEditingTarget?.note, same(target.note));
              expect(
                controller.noteEditingTarget?.selection,
                const TextSelection.collapsed(offset: 6),
              );
              expect(controller.noteEditText(target.note!), 'Left \n Right');
            }
            final after = _state(document);
            controller.undo();
            expect(_state(document), before);
            expect(_packageState(document), packageBefore);
            expect(controller.canUndo, isFalse);
            expect(_blocks(target).whereType<WmlTable>(), isEmpty);
            if (type == 0) {
              expect(controller.caret.selectionAnchor, reverse ? 6 : 1);
              expect(controller.caret.logicalIndex, reverse ? 1 : 6);
            } else {
              expect(controller.noteEditingTarget?.selection, selectionBefore);
            }
            controller.redo();
            expect(_state(document), after);
            expect(_table(target), same(table));
            expect(
              controller.zoteroFields.first.paragraph,
              same(masterParagraph),
            );
            _expectResearch(document, table, type);
            _expectReopened(document, type);
          },
        );
      }

      test(
        '${command.name} abandoned vertical table in $story leaks no media, numbering or fields',
        () {
          final target = _target(type);
          final before = _state(target.controller.document);
          final packageBefore = _packageState(target.controller.document);
          final transaction = _begin(target, command);
          _stage(transaction, type);
          expect(transaction.apply, throwsStateError);
          expect(_state(target.controller.document), before);
          expect(_packageState(target.controller.document), packageBefore);
          expect(target.controller.canUndo, isFalse);
          expect(target.controller.isDirty, isFalse);
        },
      );

      test(
        '${command.name} stale $story selection rejects the entire vertical table',
        () {
          final target = _target(type);
          final controller = target.controller;
          final before = _state(controller.document);
          final packageBefore = _packageState(controller.document);
          final transaction = _begin(target, command);
          _stage(transaction, type);
          _complete(transaction);
          if (target.note == null) {
            controller.caret.logicalIndex = 5;
          } else {
            controller.setNoteEditingTarget(
              target.note!,
              const TextSelection(baseOffset: 5, extentOffset: 10),
            );
          }
          expect(transaction.apply, throwsStateError);
          expect(_state(controller.document), before);
          expect(_packageState(controller.document), packageBefore);
          expect(controller.canUndo, isFalse);
          expect(controller.isDirty, isFalse);
        },
      );

      test(
        '${command.name} cancellation after staging a vertical table in $story drains without applying',
        () async {
          final target = _target(type);
          final controller = target.controller;
          final before = _state(controller.document);
          final packageBefore = _packageState(controller.document);
          final selection = controller.noteEditingTarget?.selection;
          final transaction = _begin(target, command);
          final cancellation = ZoteroCitingCancellation();
          final desktop = _Desktop(type, cancelAfterStaging: true);
          var staged = false;
          await expectLater(
            ZoteroCitingClient(transport: desktop.send).execute(
              command: command,
              documentId: _id,
              cancellation: cancellation,
              guard: transaction.assertCurrent,
              handler: (name, arguments) {
                final result = transaction.session.handle(name, arguments);
                if (name == 'Document.insertText') {
                  staged = transaction.session.hasInsertedNoteText;
                  cancellation.cancel();
                }
                return result;
              },
            ),
            throwsA(
              isA<ZoteroCitingException>()
                  .having(
                    (e) => e.kind,
                    'kind',
                    ZoteroCitingErrorKind.cancelled,
                  )
                  .having(
                    (e) => e.desktopMayNeedRestart,
                    'cleanup incomplete',
                    isFalse,
                  ),
            ),
          );
          expect(staged, isTrue);
          expect(desktop.requests, hasLength(7));
          expect(jsonDecode(desktop.requests.last.body!), contains('error'));
          expect(transaction.apply, throwsStateError);
          expect(_state(controller.document), before);
          expect(_packageState(controller.document), packageBefore);
          expect(controller.noteEditingTarget?.selection, selection);
          expect(controller.zoteroFields, isEmpty);
          expect(controller.canUndo, isFalse);
          expect(controller.isDirty, isFalse);
        },
      );

      for (final (defect, malformed) in <(String, String)>[
        (
          'outlives rows',
          '<table><tbody><tr><td rowspan="2">Bad</td></tr></tbody></table>',
        ),
        (
          'crosses row group',
          '<table><tbody><tr><td rowspan="2">Bad</td></tr></tbody><tbody><tr><td>Next</td></tr></tbody></table>',
        ),
        ('zero span', '<table><tr><td rowspan="0">Bad</td></tr></table>'),
        (
          'overlap',
          '<table><tr><td>Left</td><td rowspan="2">Master</td></tr><tr><td colspan="2">Collision</td></tr></table>',
        ),
      ]) {
        test(
          '${command.name} $defect after rich vertical content leaves $story unchanged',
          () {
            final target = _target(type);
            final controller = target.controller;
            final before = _state(controller.document);
            final packageBefore = _packageState(controller.document);
            final transaction = _begin(target, command);
            expect(
              () => _insert(transaction, type, '$_html$malformed'),
              throwsUnsupportedError,
            );
            expect(_state(controller.document), before);
            expect(_packageState(controller.document), packageBefore);
            expect(controller.canUndo, isFalse);
            expect(controller.isDirty, isFalse);
          },
        );
      }

      testWidgets(
        '${command.name} dialog inserts a rich vertical table in $story as one undo step',
        (tester) async {
          final target = _target(type);
          final controller = target.controller;
          final before = _state(controller.document);
          final desktop = _Desktop(type);
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(1200, 900);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => FilledButton(
                    onPressed: () => showWordZoteroDialog(
                      context,
                      controller: controller,
                      localTransport: desktop.send,
                      initialCommand: command,
                      closeAfterCommand: true,
                    ),
                    child: const Text('Insert vertical research table'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Insert vertical research table'));
          await tester.pumpAndSettle();
          expect(desktop.command, command.name);
          expect(desktop.requests, hasLength(12));
          _expectResearch(controller.document, _table(target), type);
          expect(tester.takeException(), isNull);
          final after = _state(controller.document);
          controller.undo();
          expect(_state(controller.document), before);
          expect(controller.canUndo, isFalse);
          controller.redo();
          expect(_state(controller.document), after);
          _expectResearch(controller.document, _table(target), type);
        },
      );
    }
  }
}
