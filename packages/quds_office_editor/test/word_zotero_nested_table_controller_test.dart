import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _documentId = 'nested-research-controller';
const _sources = <(String, String)>[
  ('ABC123', 'outer-before'),
  ('DEF456', 'inner-merged'),
  ('GHI789', 'deep'),
  ('JKL012', 'outer-after'),
  ('MNO345', 'outer-right'),
];

String _placeholder(String key) =>
    '<a href="https://www.zotero.org/?$key">(old)</a>';

// Three table levels, independent outer/inner vertical merges, an inner
// horizontal merge, and a cell whose final authored block is another table.
// Citations before and after that cell exercise the generated trailing native
// paragraph's contribution to every subsequent field's paragraph identity.
String get _html =>
    '<div data-schema-version="9"><table><tbody><tr>'
    '<td rowspan="2" data-colwidth="320" style="background-color:#fff1d6">'
    '<p>Outer before ${_placeholder('ABC123')}</p><div><table><tbody><tr>'
    '<td rowspan="2" colspan="2" data-colwidth="80,100">'
    '<p><b>Inner merged ${_placeholder('DEF456')}</b></p></td>'
    '<td data-colwidth="140"><p>Inner upper</p></td></tr>'
    '<tr><td data-colwidth="140"><p>Inner lower</p></td></tr>'
    '<tr><td colspan="3" data-colwidth="80,100,140"><p>Inner final</p>'
    '<table><tr><td data-colwidth="200" style="background-color:#d8eaff">'
    '<p>Deep last ${_placeholder('GHI789')}</p></td></tr></table>'
    '</td></tr></tbody></table></div>'
    '<p><i>Outer after ${_placeholder('JKL012')}</i></p></td>'
    '<td data-colwidth="200"><p>Outer right ${_placeholder('MNO345')}</p></td>'
    '</tr><tr><td data-colwidth="200"><p>Outer lower</p></td></tr>'
    '</tbody></table></div>';

String _preferences(int type) => jsonEncode(<String, Object>{
  'dataVersion': 4,
  'sessionID': 'nested-research-session',
  'zoteroVersion': '10.0',
  'style': <String, Object>{
    'styleID': type == 0
        ? 'http://www.zotero.org/styles/apa'
        : 'http://www.zotero.org/styles/chicago-note-bibliography',
    'locale': 'de-DE',
  },
  'prefs': <String, Object>{'fieldType': 'Http', 'noteType': type},
});

String _citation(String id, int noteIndex) =>
    'ITEM CSL_CITATION ${jsonEncode(ZoteroCitation(
      citationId: id,
      plainCitation: '($id)',
      noteIndex: noteIndex,
      items: [
        ZoteroCitationItem.fromCsl(itemData: {'id': id, 'type': 'book', 'title': 'Source $id'}, uris: ['http://zotero.org/users/42/items/ABCD1234'], locator: '7', label: 'page'),
      ],
    ).toJson())}';

typedef _Target = ({WordEditorController controller, WmlNote? note});

_Target _target(int type) {
  final package = OpcPackage.create(OpcPackageKind.word);
  package.createPart(
    '/word/media/preserved.bin',
    'application/octet-stream',
    Uint8List.fromList([11, 17, 23]),
  );
  package
      .relationshipsFor('/word/document.xml')
      .add(type: RelationshipTypes.image, target: 'media/preserved.bin');
  final document = WmlDocument(
    package: package,
    sections: [
      WmlSection(
        // Native DOCX page dimensions are integral twentieths of a point.
        // Fix the page and link styling so exact raster checks measure the
        // nested import rather than unrelated serialization defaults.
        pageSize: const WmlPageSize(width: 600, height: 800),
        blocks: [
          WmlParagraph(
            inlines: [
              WmlRun(
                text: 'Before chosen',
                properties: WmlRunProps(bold: true),
              ),
              WmlRun(
                text: ' After',
                properties: WmlRunProps(
                  italic: true,
                  color: '0563C1',
                  underline: WmlUnderline.single,
                ),
                hyperlink: const WmlHyperlink(url: 'https://example.org/tail'),
              ),
            ],
          ),
          WmlParagraph(inlines: [WmlRun(text: 'Unrelated')]),
        ],
      ),
    ],
  );
  final note = type == 0
      ? null
      : WordNotes.insert(
          document,
          document.paragraphs.last,
          text: 'Before chosen After',
          endnote: type == 2,
        );
  final controller = WordEditorController(document: document);
  controller.proofing.enabled = false;
  controller.caret
    ..paragraphIndex = 0
    ..logicalIndex = 13
    ..selectionAnchor = 7
    ..selectionAnchorParagraph = 0;
  if (note != null) {
    controller.setNoteEditingTarget(
      note,
      TextSelection(
        baseOffset: type == 2 ? 13 : 7,
        extentOffset: type == 2 ? 7 : 13,
      ),
    );
  }
  addTearDown(() {
    if (!controller.isDisposed) controller.dispose();
  });
  return (controller: controller, note: note);
}

WordZoteroTransaction _begin(_Target target, ZoteroCitingCommand command) =>
    target.controller.beginZoteroTransaction(
      documentId: _documentId,
      command: command,
    );

Object? _call(
  WordZoteroTransaction transaction,
  String command, [
  List<Object?> arguments = const [],
]) {
  transaction.assertCurrent();
  return transaction.session.handle(command, [_documentId, ...arguments]);
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
  final requested = _sources.reversed.toList();
  final fields =
      (_call(transaction, 'Document.convertPlaceholdersToFields', [
                requested.map((source) => source.$1).toList(),
                type,
                'Http',
              ])!
              as List<Object?>)
          .cast<Map<String, Object>>();
  expect(fields, hasLength(_sources.length));
  for (var index = 0; index < fields.length; index++) {
    final field = fields[index];
    final id = requested[index].$2;
    _call(transaction, 'Field.setCode', [
      field['id'],
      _citation(id, field['noteIndex']! as int),
    ]);
    _call(transaction, 'Field.setText', [field['id'], '<i>($id)</i>', true]);
  }
  _call(transaction, 'Document.complete');
  transaction.session.prepareReview();
}

Object _block(WmlBlock block) {
  if (block is WmlTable) {
    return [
      'table',
      block.grid,
      for (final row in block.rows)
        [
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
    for (final inline in paragraph.inlines)
      if (inline is WmlRun)
        [
          inline.text,
          inline.properties.bold,
          inline.properties.italic,
          inline.hyperlink?.url,
          inline.fieldInstruction,
          inline.noteRefId,
          inline.noteRefEndnote,
        ]
      else if (inline is WmlNoteMarker)
        ['marker', inline.endnote],
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
        for (final relationship in package.relationshipsFor(uri).items)
          [
            relationship.id,
            relationship.type,
            relationship.target,
            relationship.targetMode.name,
          ],
      ],
  ]);
}

List<WmlBlock> _story(WmlDocument document, int type) => type == 0
    ? document.sections.single.blocks
    : (type == 1 ? document.footnotes : document.endnotes).single.blocks;

({WmlTable outer, WmlTable inner, WmlTable deep}) _tables(
  WmlDocument document,
  int type,
) {
  final outer = _story(document, type).whereType<WmlTable>().single;
  final inner = outer.rows.first.cells.first.blocks
      .whereType<WmlTable>()
      .single;
  final deep = inner.rows.last.cells.single.blocks.whereType<WmlTable>().single;
  return (outer: outer, inner: inner, deep: deep);
}

void _expectNested(WmlDocument document, int type) {
  final (:outer, :inner, :deep) = _tables(document, type);
  expect(outer.grid, [240.0, 150.0]);
  expect(inner.grid, [60.0, 75.0, 105.0]);
  expect(deep.grid, [150.0]);
  expect(outer.rows.map((row) => row.cells.first.vMerge), [
    WmlVMerge.restart,
    WmlVMerge.cont,
  ]);
  expect(
    inner.rows.map((row) => row.cells.map((cell) => cell.gridSpan).toList()),
    [
      [2, 1],
      [2, 1],
      [3],
    ],
  );
  expect(inner.rows.take(2).map((row) => row.cells.first.vMerge), [
    WmlVMerge.restart,
    WmlVMerge.cont,
  ]);
  for (final table in [outer, inner, deep]) {
    expect(WordTable.supportsGridAddressing(table), isTrue);
  }
  expect(
    WordTable.cellAtGrid(inner, 1, 1)!.cell,
    same(inner.rows.first.cells.first),
  );
  expect(
    WordTree.paragraphs(outer.rows[1].cells.first.blocks).single.text,
    isEmpty,
    reason: 'Outer continuation must not duplicate the nested tree',
  );
  expect(
    WordTree.paragraphs(inner.rows[1].cells.first.blocks).single.text,
    isEmpty,
  );
  final finalCell = inner.rows.last.cells.single;
  expect(finalCell.blocks.last, isA<WmlParagraph>());
  expect((finalCell.blocks.last as WmlParagraph).text, isEmpty);
  final fields = WordZotero.fields(document);
  expect(fields.map((field) => field.citation!.citationId), [
    for (final source in _sources) source.$2,
  ]);
  expect(fields.map((field) => field.cachedText), [
    for (final source in _sources) '(${source.$2})',
  ]);
  expect(fields.every((field) => field.canEdit), isTrue);
  expect(
    fields.every((field) => field.citation!.items.single.locator == '7'),
    isTrue,
  );
  expect(fields[1].paragraph, same(inner.rows.first.cells.first.blocks.single));
  expect(
    fields[2].paragraph,
    same(deep.rows.single.cells.single.blocks.single),
  );
  expect(fields[3].paragraph, same(outer.rows.first.cells.first.blocks.last));
  expect(fields[4].paragraph, same(outer.rows.first.cells.last.blocks.single));
  expect(WordFieldSpans.unbalanced(document), isEmpty);
  expect(document.footnotes, hasLength(type == 1 ? 1 : 0));
  expect(document.endnotes, hasLength(type == 2 ? 1 : 0));
  if (type != 0) {
    final note = (type == 1 ? document.footnotes : document.endnotes).single;
    expect(
      fields.every((field) => note.allParagraphs.contains(field.paragraph)),
      isTrue,
    );
  }
}

void _expectUnchanged(_Target target, String before, String packageBefore) {
  final controller = target.controller;
  expect(_state(controller.document), before);
  expect(_packageState(controller.document), packageBefore);
  expect(controller.zoteroFields, isEmpty);
  expect(controller.canUndo, isFalse);
  expect(controller.isDirty, isFalse);
}

class _CancelledDesktop {
  final requests = <ZoteroHttpRequest>[];
  String fieldId = '';
  String documentId = '';

  Future<ZoteroHttpResponse> send(ZoteroHttpRequest request) async {
    final index = requests.length;
    requests.add(request);
    final Object? decoded = jsonDecode(request.body!);
    if (index == 0) {
      documentId = (decoded! as Map<String, Object?>)['docId']! as String;
    } else if (decoded case {'id': final String id}) {
      fieldId = id;
    }
    final (command, arguments) = switch (index) {
      0 => ('Application.getActiveDocument', <Object?>[]),
      1 => ('Document.getDocumentData', <Object?>[documentId]),
      2 => ('Document.setDocumentData', <Object?>[documentId, _preferences(0)]),
      3 => ('Document.insertField', <Object?>[documentId, 'Http', 0]),
      4 => ('Field.delete', <Object?>[documentId, fieldId]),
      5 => ('Document.insertText', <Object?>[documentId, _html]),
      6 => ('Document.complete', <Object?>[documentId]),
      _ => throw StateError('Unexpected request after completed cleanup'),
    };
    return ZoteroHttpResponse(
      statusCode: 200,
      headers: const {},
      body: jsonEncode({'command': command, 'arguments': arguments}),
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
      test(
        '${command.name} nested tables preserve $story citation order, undo and DOCX saves',
        () {
          final target = _target(type);
          final controller = target.controller;
          final document = controller.document;
          final before = _state(document);
          final packageBefore = _packageState(document);
          final noteSelection = controller.noteEditingTarget?.selection;
          final transaction = _begin(target, command);
          _stage(transaction, type);
          _expectUnchanged(target, before, packageBefore);
          transaction.apply();
          _expectNested(document, type);
          final tables = _tables(document, type);
          final after = _state(document);
          expect(controller.canUndo, isTrue);
          final storyBlocks = _story(document, type);
          expect((storyBlocks.first as WmlParagraph).text.trim(), 'Before');
          expect(
            (storyBlocks[storyBlocks.indexOf(tables.outer) + 1] as WmlParagraph)
                .text,
            ' After',
          );
          controller.undo();
          expect(_state(document), before);
          expect(_packageState(document), packageBefore);
          expect(
            controller.canUndo,
            isFalse,
            reason: 'The entire import is one edit',
          );
          if (type == 0) {
            expect(controller.caret.logicalIndex, 13);
            expect(controller.caret.selectionAnchor, 7);
          } else {
            expect(controller.noteEditingTarget?.selection, noteSelection);
          }
          controller.redo();
          expect(_state(document), after);
          expect(_tables(document, type).outer, same(tables.outer));
          _expectNested(document, type);
          var reopened = document;
          for (var cycle = 0; cycle < 3; cycle++) {
            reopened = WordDeserializer().readBytes(
              WordSerializer().writeBytes(reopened),
            );
            _expectNested(reopened, type);
            expect(
              reopened.package!
                  .getPart('/word/media/preserved.bin')!
                  .readBytes(),
              [11, 17, 23],
            );
          }
        },
      );
    }

    test(
      '${command.name} invalid inner merge refuses the whole authored note',
      () {
        final target = _target(1);
        final before = _state(target.controller.document);
        final packageBefore = _packageState(target.controller.document);
        final transaction = _begin(target, command);
        final malformed = _html.replaceFirst(
          'rowspan="2" colspan="2"',
          'rowspan="4" colspan="2"',
        );
        expect(
          () => _insert(transaction, 1, malformed),
          throwsUnsupportedError,
        );
        expect(transaction.apply, throwsStateError);
        _expectUnchanged(target, before, packageBefore);
      },
    );

    test(
      '${command.name} nested payload keeps the existing table destination guard',
      () {
        final target = _target(0);
        final controller = target.controller;
        final paragraph = controller.document.paragraphs.first;
        controller.document.sections.single.blocks[0] = WmlTable(
          rows: [
            WmlTableRow(
              cells: [
                WmlTableCell(blocks: [paragraph]),
              ],
            ),
          ],
        );
        controller.relayout();
        final before = _state(controller.document);
        final packageBefore = _packageState(controller.document);
        final transaction = _begin(target, command);
        expect(() => _insert(transaction, 0, _html), throwsUnsupportedError);
        _expectUnchanged(target, before, packageBefore);
      },
    );
  }

  for (final type in [0, 1, 2]) {
    test(
      'nested insertion refuses a stale ${['body', 'footnote', 'endnote'][type]} selection',
      () {
        final target = _target(type);
        final controller = target.controller;
        final before = _state(controller.document);
        final packageBefore = _packageState(controller.document);
        final transaction = _begin(target, ZoteroCitingCommand.addNote);
        _stage(transaction, type);
        if (target.note == null) {
          controller.caret.logicalIndex = 12;
        } else {
          controller.setNoteEditingTarget(
            target.note!,
            const TextSelection.collapsed(offset: 2),
          );
        }
        expect(transaction.apply, throwsStateError);
        _expectUnchanged(target, before, packageBefore);
      },
    );
  }

  test(
    'cancellation after nested content staging drains Desktop without applying',
    () async {
      final target = _target(0);
      final before = _state(target.controller.document);
      final packageBefore = _packageState(target.controller.document);
      final transaction = _begin(target, ZoteroCitingCommand.addAnnotation);
      final cancellation = ZoteroCitingCancellation();
      final desktop = _CancelledDesktop();
      var staged = false;
      await expectLater(
        ZoteroCitingClient(transport: desktop.send).execute(
          command: ZoteroCitingCommand.addAnnotation,
          documentId: _documentId,
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
                (error) => error.kind,
                'kind',
                ZoteroCitingErrorKind.cancelled,
              )
              .having(
                (error) => error.desktopMayNeedRestart,
                'cleanup incomplete',
                isFalse,
              ),
        ),
      );
      expect(staged, isTrue);
      expect(desktop.requests, hasLength(7));
      expect(jsonDecode(desktop.requests.last.body!), contains('error'));
      expect(transaction.apply, throwsStateError);
      _expectUnchanged(target, before, packageBefore);
    },
  );

  testWidgets(
    'nested cited cells remain visible and contained through three DOCX saves',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(680, 960);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final target = _target(0);
      final transaction = _begin(target, ZoteroCitingCommand.addNote);
      _stage(transaction, 0);
      transaction.apply();
      var document = target.controller.document;
      Uint8List? reference;
      const artifacts = String.fromEnvironment('QUDS_NESTED_RENDER_ARTIFACTS');
      for (var cycle = 0; cycle <= 3; cycle++) {
        final laid = WordLayoutEngine(font: null).layout(document);
        if (artifacts.isNotEmpty) {
          Directory(artifacts).createSync(recursive: true);
          File('$artifacts/cycle-$cycle-layout.txt').writeAsStringSync(
            wordLayoutFingerprint(laid).replaceAllMapped(
              RegExp(r'\b(srcPara|table|frame|eq)=[0-9]+'),
              (match) => '${match[1]}=model',
            ),
          );
        }
        expect(laid.pages, hasLength(1));
        final (:outer, :inner, :deep) = _tables(document, 0);
        final frames = laid.pages.single.frames
            .where((frame) => frame.kind == LaidOutBoxKind.tableCell)
            .toList();
        final outerFrame = frames.singleWhere(
          (frame) =>
              identical(frame.table, outer) &&
              frame.tableRow == 0 &&
              frame.tableCol == 0,
        );
        final innerFrames = frames
            .where((frame) => identical(frame.table, inner))
            .toList();
        final deepFrame = frames.singleWhere(
          (frame) => identical(frame.table, deep),
        );
        expect(innerFrames, isNotEmpty);
        for (final child in [...innerFrames, deepFrame]) {
          expect(child.x, greaterThanOrEqualTo(outerFrame.x));
          expect(
            child.x + child.width,
            lessThanOrEqualTo(outerFrame.x + outerFrame.width + .01),
          );
          expect(child.y, greaterThanOrEqualTo(outerFrame.y));
          expect(
            child.y + child.height,
            lessThanOrEqualTo(outerFrame.y + outerFrame.height + .01),
          );
        }
        for (final paragraph in WordTree.paragraphs([
          outer,
        ]).where((paragraph) => paragraph.text.isNotEmpty)) {
          final lines = laid.pages.single.lines
              .where((line) => identical(line.sourceParagraph, paragraph))
              .toList();
          expect(lines, isNotEmpty, reason: paragraph.text);
          final offsets =
              lines
                  .expand((line) => line.glyphs)
                  .where((glyph) => !glyph.glyph.isSpace)
                  .map((glyph) => glyph.glyph.logicalIndex)
                  .toList()
                ..sort();
          expect(
            offsets,
            [
              for (var index = 0; index < paragraph.text.length; index++)
                if (paragraph.text.codeUnitAt(index) != 32) index,
            ],
            reason:
                'Every authored/cited character must be drawn: ${paragraph.text}',
          );
        }
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: RepaintBoundary(
              key: const ValueKey('nested-zotero-page'),
              child: WordCanvas(
                key: UniqueKey(),
                document: document,
                laidOut: laid,
                caret: CaretEngine(),
                config: OfficeSurfaceConfig(
                  mode: OfficeInteractionMode.viewing,
                  theme: OfficeTheme.light.copyWith(fontFamily: 'Arial'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('nested-zotero-page')),
        );
        final imageData = await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          try {
            final data = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            final png = (await image.toByteData(
              format: ui.ImageByteFormat.png,
            ))!;
            return (
              rgba: data.buffer.asUint8List(),
              png: png.buffer.asUint8List(),
              width: image.width,
              height: image.height,
            );
          } finally {
            image.dispose();
          }
        });
        expect(imageData, isNotNull);
        final pixels = imageData!.rgba;
        if (artifacts.isNotEmpty) {
          File('$artifacts/cycle-$cycle.png').writeAsBytesSync(imageData.png);
        }
        if (reference == null) {
          reference = pixels;
          var shadedPixels = 0;
          for (var offset = 0; offset < reference.length; offset += 4) {
            if (reference[offset] == 0xd8 &&
                reference[offset + 1] == 0xea &&
                reference[offset + 2] == 0xff) {
              shadedPixels++;
            }
          }
          expect(
            shadedPixels,
            greaterThan(100),
            reason: 'The deepest cell must paint its authored blue fill',
          );
        } else {
          expect(pixels.length, reference.length);
          var changedPixels = 0;
          var maximumChannelDelta = 0;
          for (var offset = 0; offset < pixels.length; offset += 4) {
            var changed = false;
            for (var channel = 0; channel < 4; channel++) {
              final delta =
                  (pixels[offset + channel] - reference[offset + channel])
                      .abs();
              if (delta != 0) changed = true;
              if (delta > maximumChannelDelta) maximumChannelDelta = delta;
            }
            if (changed) changedPixels++;
          }
          if (artifacts.isNotEmpty) {
            File('$artifacts/cycle-$cycle-difference.json').writeAsStringSync(
              jsonEncode({
                'changedPixels': changedPixels,
                'maximumChannelDelta': maximumChannelDelta,
                'width': imageData.width,
                'height': imageData.height,
              }),
            );
          }
          expect(
            changedPixels,
            0,
            reason:
                'Save $cycle preserves exact pixels (maximum channel delta $maximumChannelDelta)',
          );
        }
        if (cycle < 3) {
          document = WordDeserializer().readBytes(
            WordSerializer().writeBytes(document),
          );
        }
      }
    },
  );
}
