import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _id = 'research-image-controller';
const _placeholder = '<a href="https://www.zotero.org/?ABC123">(old)</a>';
// Independent 3x2 RGBA PNG: red/green/blue above yellow/cyan/magenta.
// Generated with Python struct/zlib; no Office encoder is the test oracle.
const _pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAMAAAACCAYAAACddGYaAAAAF0lEQVR4nGP4z8DwHwwZ/v8HIyABZgEAqm8O8tH19KMAAAAASUVORK5CYII=';
final _png = base64Decode(_pngBase64);
const _image =
    '<img src="data:image/png;base64,$_pngBase64" width="96" height="64" '
    'alt="Six colored samples" title="Research figure">';
const _html =
    '<div data-schema-version="9"><p><b>Figure</b> '
    '<a href="https://example.org/figure">$_image</a> '
    '$_placeholder Comment</p><p><i>Finish</i></p></div>';
const _canvasKey = ValueKey('research-image-canvas');
const _runKey = ValueKey('research-image-command');

String _preferences(int noteType) => jsonEncode({
  'dataVersion': 4,
  'sessionID': 'research-image-session',
  'zoteroVersion': '10.0',
  'style': {
    'styleID': noteType == 0
        ? 'http://www.zotero.org/styles/apa'
        : 'http://www.zotero.org/styles/chicago-note-bibliography',
    'locale': 'de-DE',
  },
  'prefs': {'fieldType': 'Http', 'noteType': noteType},
});

String _code({int noteIndex = 0}) =>
    'ITEM CSL_CITATION ${jsonEncode(ZoteroCitation(
      citationId: 'image-source',
      plainCitation: '(Author, 2026, p. 4)',
      noteIndex: noteIndex,
      items: [
        ZoteroCitationItem.fromCsl(itemData: {'id': 'figure-source', 'type': 'book', 'title': 'Research figures'}, uris: ['http://zotero.org/users/42/items/ABCD1234'], locator: '4', label: 'page'),
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
                hyperlink: const WmlHyperlink(
                  url: 'https://example.org/authored',
                ),
              ),
            ],
          ),
          WmlParagraph(inlines: [WmlRun(text: 'Unrelated')]),
        ],
      ),
    ],
  );
}

WordEditorController _controller() {
  final controller = WordEditorController(
    document: _document(),
    config: const OfficeSurfaceConfig(autofocus: false),
  );
  controller.proofing.enabled = false;
  controller.caret
    ..logicalIndex = 6
    ..collapseSelection();
  addTearDown(() {
    if (!controller.isDisposed) controller.dispose();
  });
  return controller;
}

WordZoteroTransaction _begin(
  WordEditorController controller,
  ZoteroCitingCommand command,
) => controller.beginZoteroTransaction(documentId: _id, command: command);

Object? _call(
  WordZoteroTransaction transaction,
  String command, [
  List<Object?> arguments = const [],
]) {
  transaction.assertCurrent();
  return transaction.session.handle(command, [_id, ...arguments]);
}

void _insert(
  WordZoteroTransaction transaction, {
  int noteType = 0,
  String html = _html,
}) {
  _call(transaction, 'Document.setDocumentData', [_preferences(noteType)]);
  final temporary =
      _call(transaction, 'Document.insertField', ['Http', noteType])!
          as Map<String, Object>;
  _call(transaction, 'Field.delete', [temporary['id']]);
  _call(transaction, 'Document.insertText', [html]);
}

void _stage(
  WordZoteroTransaction transaction, {
  int noteType = 0,
  String html = _html,
}) {
  _insert(transaction, noteType: noteType, html: html);
  final field =
      (_call(transaction, 'Document.convertPlaceholdersToFields', [
                ['ABC123'],
                noteType,
                'Http',
              ])!
              as List<Object?>)
          .cast<Map<String, Object>>()
          .single;
  _call(transaction, 'Field.setCode', [
    field['id'],
    _code(noteIndex: field['noteIndex']! as int),
  ]);
  _call(transaction, 'Field.setText', [
    field['id'],
    '<i>(Author, 2026, p. 4)</i>',
    true,
  ]);
  _call(transaction, 'Document.complete');
  transaction.session.prepareReview();
}

List<Object?> _paragraph(WmlParagraph paragraph) => [
  paragraph.text,
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
          image.visual.picture.altTitle,
          image.visual.picture.altDescription,
          base64Encode(image.visual.imageBytes!),
        ],
    ],
];

String _state(WmlDocument document) => jsonEncode({
  'body': [for (final p in document.paragraphs) _paragraph(p)],
  'footnotes': [
    for (final n in document.footnotes)
      [n.id, for (final p in n.allParagraphs) _paragraph(p)],
  ],
  'endnotes': [
    for (final n in document.endnotes)
      [n.id, for (final p in n.allParagraphs) _paragraph(p)],
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

void _expectImage(WmlDocument document, {bool saved = false}) {
  final run = document.paragraphs
      .expand((p) => p.inlines.whereType<WmlRun>())
      .singleWhere((r) => r.inlineVisual != null);
  final image = run.inlineVisual!.visual;
  expect(run.text, '\uFFFC');
  expect(run.isAtomic, isTrue);
  expect(run.hyperlink?.url, 'https://example.org/figure');
  expect(image.imageBytes, orderedEquals(_png));
  expect(image.width, closeTo(72, 0.001));
  expect(image.height, closeTo(48, 0.001));
  expect(image.picture.altTitle, 'Research figure');
  expect(image.picture.altDescription, 'Six colored samples');
  if (saved) {
    final media = document.package!.parts
        .where((p) => p.contentType == 'image/png')
        .toList();
    expect(media, hasLength(1));
    expect(media.single.readBytes(), orderedEquals(_png));
    expect(
      document.package!.getPart('/word/media/preserved.bin')!.readBytes(),
      [7, 11, 13],
    );
  }
}

void _expectCitation(WmlDocument document, int noteType) {
  final fields = WordZotero.fields(document);
  expect(fields, hasLength(1));
  expect(fields.single.canEdit, isTrue);
  expect(fields.single.citation!.citationId, 'image-source');
  expect(fields.single.citation!.items.single.locator, '4');
  expect(fields.single.citation!.items.single.uris, [
    'http://zotero.org/users/42/items/ABCD1234',
  ]);
  expect(fields.single.cachedText, '(Author, 2026, p. 4)');
  expect(WordFieldSpans.unbalanced(document), isEmpty);
  expect(document.footnotes, hasLength(noteType == 1 ? 1 : 0));
  expect(document.endnotes, hasLength(noteType == 2 ? 1 : 0));
}

typedef _Step = Map<String, Object?> Function(_Desktop desktop);

class _Desktop {
  _Desktop({this.pauseBeforeCompletion = false});
  final bool pauseBeforeCompletion;
  final completion = Completer<void>();
  final requests = <ZoteroHttpRequest>[];
  String documentId = '';
  String fieldId = '';
  String command = '';
  List<Map<String, Object?>> fields = [];
  bool reachedCompletion = false;

  Map<String, Object?> message(String name, List<Object?> args) => {
    'command': name,
    'arguments': args,
  };

  List<_Step> get steps => [
    (d) => d.message('Application.getActiveDocument', []),
    (d) =>
        d.message('Document.setDocumentData', [d.documentId, _preferences(0)]),
    (d) => d.message('Document.insertField', [d.documentId, 'Http', 0]),
    (d) => d.message('Field.delete', [d.documentId, d.fieldId]),
    (d) => d.message('Document.insertText', [d.documentId, _html]),
    (d) => d.message('Document.convertPlaceholdersToFields', [
      d.documentId,
      ['ABC123'],
      0,
      'Http',
    ]),
    (d) => d.message('Field.setCode', [
      d.documentId,
      d.fields.single['id'],
      _code(),
    ]),
    (d) => d.message('Field.setText', [
      d.documentId,
      d.fields.single['id'],
      '<i>(Author, 2026, p. 4)</i>',
      true,
    ]),
    (d) => d.message('Document.complete', [d.documentId]),
  ];

  Future<ZoteroHttpResponse> send(ZoteroHttpRequest request) async {
    final index = requests.length;
    requests.add(request);
    final Object? body = jsonDecode(request.body!);
    if (index == 0) {
      final initial = body! as Map<String, Object?>;
      documentId = initial['docId']! as String;
      command = initial['command']! as String;
    } else if (body case {'id': final String id}) {
      fieldId = id;
    } else if (body is List<Object?>) {
      fields = body.cast<Map<String, Object?>>();
    }
    expect(index, lessThan(steps.length));
    if (index == steps.length - 1) {
      reachedCompletion = true;
      if (pauseBeforeCompletion) await completion.future;
    }
    return ZoteroHttpResponse(
      statusCode: 200,
      headers: const {},
      body: jsonEncode(steps[index](this)),
    );
  }
}

Future<void> _pump(WidgetTester tester) async {
  // A live editor keeps a caret ticker; drain a bounded set of route frames.
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _open(
  WidgetTester tester,
  WordEditorController controller,
  _Desktop desktop,
  ZoteroCitingCommand command,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 900);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    if (!desktop.completion.isCompleted) desktop.completion.complete();
    await tester.pump();
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Column(
            children: [
              FilledButton(
                key: _runKey,
                onPressed: () => showWordZoteroDialog(
                  context,
                  controller: controller,
                  localTransport: desktop.send,
                  initialCommand: command,
                  closeAfterCommand: true,
                ),
                child: const Text('Insert research figure'),
              ),
              Expanded(
                child: RepaintBoundary(
                  key: _canvasKey,
                  child: QudsWordEditor(
                    controller: controller,
                    enableLiveProofing: false,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(_runKey));
  await _pump(tester);
}

Future<({int red, int green})> _paintedColors(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_canvasKey),
  );
  final raster = (await tester.runAsync(
    () => boundary.toImage(pixelRatio: 1),
  ))!;
  try {
    final data = (await tester.runAsync(
      () => raster.toByteData(format: ui.ImageByteFormat.rawRgba),
    ))!;
    final pixels = data.buffer.asUint8List();
    var red = 0;
    var green = 0;
    for (var i = 0; i < pixels.length; i += 4) {
      if (pixels[i] > 180 && pixels[i + 1] < 60 && pixels[i + 2] < 60) {
        red++;
      }
      if (pixels[i] < 60 && pixels[i + 1] > 180 && pixels[i + 2] < 60) {
        green++;
      }
    }
    return (red: red, green: green);
  } finally {
    raster.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);

  test('ordinary note fractional image extents survive repeated DOCX saves', () {
    final controller = _controller();
    final transaction = _begin(controller, ZoteroCitingCommand.addNote);
    // Zotero's note editor can fill a missing dimension from the natural aspect
    // ratio without rounding it before serialization. This 3x2 image at width
    // 53 therefore acquires height 35.333333333333336 CSS pixels.
    _stage(
      transaction,
      html: _html.replaceFirst(
        'width="96" height="64"',
        'width="53" height="35.333333333333336"',
      ),
    );
    transaction.apply();
    var reopened = controller.document;
    for (var cycle = 0; cycle < 4; cycle++) {
      final image = reopened.paragraphs
          .expand((paragraph) => paragraph.inlines.whereType<WmlRun>())
          .singleWhere((run) => run.inlineVisual != null)
          .inlineVisual!
          .visual;
      // One EMU is 1/12700 point; DOCX extents must keep native precision.
      expect(image.width, closeTo(39.75, 1 / 12700));
      expect(image.height, closeTo(26.5, 1 / 12700));
      expect(image.imageBytes, orderedEquals(_png));
      _expectCitation(reopened, 0);
      expect(
        reopened.paragraphs.first.text,
        startsWith('BeforeFigure \uFFFC '),
      );
      expect(reopened.paragraphs.elementAt(1).text, 'FinishAfter');
      if (cycle < 3) {
        reopened = WordDeserializer().readBytes(
          WordSerializer().writeBytes(reopened),
        );
      }
    }
    expect(controller.caret.paragraphIndex, 1);
    expect(controller.caret.logicalIndex, 6);
    controller.undo();
    expect(controller.document.inlineVisuals, isEmpty);
    expect(controller.canUndo, isFalse);
  });

  for (final command in [
    ZoteroCitingCommand.addNote,
    ZoteroCitingCommand.addAnnotation,
  ]) {
    for (final noteType in [0, 1, 2]) {
      test(
        '${command.name} image and style $noteType apply as one history step',
        () {
          final controller = _controller();
          final document = controller.document;
          final original = document.paragraphs.first;
          final unrelated = document.paragraphs.last;
          final before = _state(document);
          final beforePackage = _packageState(document);
          final transaction = _begin(controller, command);
          _stage(transaction, noteType: noteType);
          expect(_state(document), before);
          expect(_packageState(document), beforePackage);
          expect(controller.canUndo, isFalse);
          transaction.apply();
          _expectImage(document);
          _expectCitation(document, noteType);
          expect(document.paragraphs.first, same(original));
          expect(document.paragraphs.last, same(unrelated));
          final paragraphs = document.paragraphs.toList();
          expect(paragraphs[0].text, startsWith('BeforeFigure \uFFFC '));
          expect(paragraphs[0].text, endsWith(' Comment'));
          expect(paragraphs[1].text, 'FinishAfter');
          expect(
            paragraphs[0].inlines.whereType<WmlRun>().first.properties.bold,
            isTrue,
          );
          final tail = paragraphs[1].inlines.whereType<WmlRun>().last;
          expect(tail.text, 'After');
          expect(tail.properties.italic, isTrue);
          expect(tail.hyperlink?.url, 'https://example.org/authored');
          expect(controller.caret.paragraphIndex, 1);
          expect(controller.caret.logicalIndex, 6);
          expect(controller.caret.isCollapsed, isTrue);
          expect(controller.noteEditingTarget, isNull);
          final after = _state(document);
          controller.undo();
          expect(_state(document), before);
          expect(document.inlineVisuals, isEmpty);
          expect(controller.caret.paragraphIndex, 0);
          expect(controller.caret.logicalIndex, 6);
          expect(controller.canUndo, isFalse);
          controller.redo();
          expect(_state(document), after);
          expect(controller.caret.paragraphIndex, 1);
          expect(controller.caret.logicalIndex, 6);
          _expectImage(document);
          var reopened = document;
          for (var cycle = 0; cycle < 3; cycle++) {
            reopened = WordDeserializer().readBytes(
              WordSerializer().writeBytes(reopened),
            );
            _expectImage(reopened, saved: true);
            _expectCitation(reopened, noteType);
            expect(WordZoteroDocumentData.read(reopened), contains('de-DE'));
            expect(reopened.paragraphs.elementAt(1).text, 'FinishAfter');
          }
          // Saving media must not break the earlier undo command or its redo.
          controller.undo();
          expect(_state(document), before);
          final undone = WordDeserializer().readBytes(
            WordSerializer().writeBytes(document),
          );
          expect(undone.inlineVisuals, isEmpty);
          expect(WordZotero.fields(undone), isEmpty);
          controller.redo();
          _expectImage(document);
          _expectCitation(document, noteType);
          final redone = WordDeserializer().readBytes(
            WordSerializer().writeBytes(document),
          );
          _expectImage(redone, saved: true);
          _expectCitation(redone, noteType);
        },
      );
    }

    test(
      '${command.name} stale completed image has no live package effects',
      () {
        final controller = _controller();
        final before = _state(controller.document);
        final package = _packageState(controller.document);
        final transaction = _begin(controller, command);
        _stage(transaction);
        controller.caret
          ..logicalIndex = 1
          ..collapseSelection();
        expect(transaction.apply, throwsStateError);
        expect(_state(controller.document), before);
        expect(_packageState(controller.document), package);
        expect(controller.document.inlineVisuals, isEmpty);
        expect(controller.canUndo, isFalse);
        expect(controller.isDirty, isFalse);
      },
    );

    test(
      '${command.name} invalid later image rejects the full research result',
      () {
        final controller = _controller();
        final before = _state(controller.document);
        final package = _packageState(controller.document);
        final transaction = _begin(controller, command);
        expect(
          () => _insert(
            transaction,
            html:
                '<p>Accepted image $_image</p><p>'
                '<img src="data:image/png;base64,aW52YWxpZA=="></p>',
          ),
          throwsA(anyOf(isA<FormatException>(), isA<UnsupportedError>())),
        );
        expect(_state(controller.document), before);
        expect(_packageState(controller.document), package);
        expect(controller.document.inlineVisuals, isEmpty);
        expect(controller.canUndo, isFalse);
        expect(controller.isDirty, isFalse);
      },
    );

    for (final scenario in [
      'cross-paragraph selection',
      'viewing',
      'selecting',
    ]) {
      test('${command.name} image flow keeps the $scenario guard', () {
        final controller = _controller();
        final crossParagraph = scenario == 'cross-paragraph selection';
        if (crossParagraph) {
          controller.caret
            ..paragraphIndex = 1
            ..logicalIndex = 1
            ..selectionAnchor = 1
            ..selectionAnchorParagraph = 0;
        } else {
          controller.setMode(
            scenario == 'viewing'
                ? OfficeInteractionMode.viewing
                : OfficeInteractionMode.selecting,
          );
        }
        final before = _state(controller.document);
        final package = _packageState(controller.document);
        expect(
          () => _begin(controller, command),
          crossParagraph ? throwsUnsupportedError : throwsStateError,
        );
        expect(_state(controller.document), before);
        expect(_packageState(controller.document), package);
        expect(controller.canUndo, isFalse);
        expect(controller.isDirty, isFalse);
      });
    }

    testWidgets('${command.name} renders the imported PNG beside its citation', (
      tester,
    ) async {
      final controller = _controller();
      final desktop = _Desktop();
      await _open(tester, controller, desktop, command);
      expect(desktop.command, command.name);
      expect(desktop.reachedCompletion, isTrue);
      expect(desktop.requests, hasLength(9));
      expect(find.byKey(const ValueKey('zotero-direct-command')), findsNothing);
      _expectImage(controller.document);
      _expectCitation(controller.document, 0);
      // Wait only for actual engine image decoding and repaint; the word editor
      // has a periodic caret ticker, so it is not expected to settle forever.
      var painted = (red: 0, green: 0);
      for (var attempt = 0; attempt < 10; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        painted = await _paintedColors(tester);
        if (painted.red > 4 && painted.green > 4) break;
      }
      expect(
        painted.red,
        greaterThan(4),
        reason: 'The PNG red samples were painted.',
      );
      expect(
        painted.green,
        greaterThan(4),
        reason: 'The PNG green samples were painted.',
      );
      expect(tester.takeException(), isNull);
      controller.undo();
      await _pump(tester);
      expect(controller.document.inlineVisuals, isEmpty);
      expect(controller.canUndo, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      '${command.name} cancelled staged image leaves no media or preferences',
      (tester) async {
        final controller = _controller();
        final before = _state(controller.document);
        final package = _packageState(controller.document);
        final desktop = _Desktop(pauseBeforeCompletion: true);
        await _open(tester, controller, desktop, command);
        expect(desktop.reachedCompletion, isTrue);
        expect(desktop.requests, hasLength(9));
        expect(_state(controller.document), before);
        expect(_packageState(controller.document), package);
        await tester.tap(find.text('Cancel operation'));
        await tester.pump();
        expect(find.text('Cancelling…'), findsOneWidget);
        desktop.completion.complete();
        await _pump(tester);
        expect(
          find.byKey(const ValueKey('zotero-direct-command')),
          findsNothing,
        );
        expect(_state(controller.document), before);
        expect(_packageState(controller.document), package);
        expect(controller.document.inlineVisuals, isEmpty);
        expect(controller.canUndo, isFalse);
        expect(controller.isDirty, isFalse);
        expect(controller.caret.logicalIndex, 6);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
