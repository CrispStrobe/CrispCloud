import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

// Independently encoded 3x2 RGBA PNG, with red/green/blue above
// yellow/cyan/magenta. Neither an Office writer nor an image encoder under
// test generates the native input or its raster oracle.
const _pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAMAAAACCAYAAACddGYaAAAAF0lEQVR4nGP4z8DwHwwZ/v8HIyABZgEAqm8O8tH19KMAAAAASUVORK5CYII=';
final _png = base64Decode(_pngBase64);
const _documentId = 'native-odt-picture';
const _citationText = '(Author, 2026, p. 4)';
const _updatedCitationText = '(Author, 2026, pp. 4–6)';
const _prefix = 'Figure 😀 \uFFFC ';
const _suffix = ' remains linked.';
const _canvasKey = ValueKey('native-odt-picture-canvas');

Map<String, dynamic> _citationData(String text) => {
  'citationID': 'native-figure-source',
  'citationItems': [
    {
      'id': 42,
      'uris': ['http://zotero.org/users/42/items/ABCD1234'],
      'locator': '4',
      'label': 'page',
      'prefix': 'see ',
      'suffix': ', emphasis added',
      'itemData': {
        'id': 42,
        'type': 'book',
        'title': 'Research figures',
        'author': [
          {'family': 'Author', 'given': 'Ada'},
        ],
      },
    },
  ],
  'properties': {
    'plainCitation': text,
    'formattedCitation': text,
    'noteIndex': 0,
  },
  'schema':
      'https://github.com/citation-style-language/schema/raw/master/csl-citation.json',
};

String _picture(String path) =>
    '<text:a xlink:href="https://example.org/figure" xlink:type="simple">'
    '<draw:frame draw:name="Native diagram" text:anchor-type="as-char" '
    'svg:width="72.375pt" svg:height="48.25pt">'
    '<draw:image xlink:href="$path" xlink:type="simple" '
    'xlink:show="embed" xlink:actuate="onLoad"/>'
    '<svg:title>Research figure</svg:title>'
    '<svg:desc>Six colored samples</svg:desc>'
    '</draw:frame></text:a>';

Uint8List _odt({String? badMedia}) {
  final name = encodeXmlAttribute(
    'ZOTERO_ITEM CSL_CITATION ${jsonEncode(_citationData(_citationText))}'
    ' RND0123456789',
  );
  final zip = ZipWriter()
    ..addFile(
      'mimetype',
      utf8.encode('application/vnd.oasis.opendocument.text'),
      store: true,
    )
    ..addFile('Pictures/figure.png', _png)
    ..addFile(
      'content.xml',
      utf8.encode(
        '<office:document-content '
        'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
        'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" '
        'xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0" '
        'xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0" '
        'xmlns:xlink="http://www.w3.org/1999/xlink">'
        '<office:body><office:text><text:p>Figure 😀 '
        '${_picture('Pictures/figure.png')} '
        '<text:reference-mark-start text:name="$name"/>'
        '$_citationText<text:reference-mark-end text:name="$name"/>'
        '$_suffix</text:p>'
        '${badMedia == null ? '' : '<text:p>Later picture ${_picture('Pictures/$badMedia.png')}</text:p>'}'
        '</office:text></office:body></office:document-content>',
      ),
    );
  if (badMedia == 'invalid') {
    zip.addFile('Pictures/invalid.png', utf8.encode('This is not a PNG.'));
  }
  return zip.close();
}

WordEditorController _controller() {
  final controller = WordEditorController(
    document: WmlDocument.empty(text: 'Keep this draft'),
    config: const OfficeSurfaceConfig(autofocus: false),
    proofingService: OfficeProofingService(providers: []),
  );
  addTearDown(() {
    if (!controller.isDisposed) controller.dispose();
  });
  return controller;
}

void _expectPicture(WmlDocument document) {
  final images = document.paragraphs
      .expand((paragraph) => paragraph.inlines.whereType<WmlRun>())
      .where((run) => run.inlineVisual != null)
      .toList();
  expect(images, hasLength(1));
  final run = images.single;
  final visual = run.inlineVisual!.visual;
  expect(run.text, '\uFFFC');
  expect(run.isAtomic, isTrue);
  expect(run.hyperlink?.url, 'https://example.org/figure');
  expect(visual.title, 'Native diagram');
  expect(visual.width, closeTo(72.375, 1 / 12700));
  expect(visual.height, closeTo(48.25, 1 / 12700));
  expect(visual.picture.altTitle, 'Research figure');
  expect(visual.picture.altDescription, 'Six colored samples');
  expect(visual.imageBytes, orderedEquals(_png));
}

void _expectCitation(
  WmlDocument document, {
  String text = _citationText,
  bool refreshed = false,
}) {
  expect(document.paragraphs.single.text, '$_prefix$text$_suffix');
  final field = WordZotero.fields(document).single;
  expect(field.canEdit, isTrue);
  expect(field.cachedText, text);
  final expected = _citationData(text);
  if (refreshed) {
    (expected['properties'] as Map<String, dynamic>)['qudsFormat'] =
        'zotero-desktop';
  }
  expect(field.citation!.toJson(), expected);
  // The non-BMP emoji consumes two UTF-16 units and the picture exactly one.
  expect(field.start, 12);
  expect(field.end, 12 + text.length);
  final span = WordFieldSpans.zoteroCitations(
    document.paragraphs.single,
  ).single;
  expect(span.start, 12);
  expect(span.end, 12 + text.length);
  expect(span.canEdit, isTrue);
  expect(WordFieldSpans.unbalanced(document), isEmpty);
}

Object _caretState(WordEditorController controller) => (
  paragraph: controller.caret.paragraphIndex,
  index: controller.caret.logicalIndex,
  anchorParagraph: controller.caret.selectionAnchorParagraph,
  anchor: controller.caret.selectionAnchor,
);

Object? _call(
  WordZoteroTransaction transaction,
  String command, [
  List<Object?> arguments = const [],
]) {
  transaction.assertCurrent();
  return transaction.session.handle(command, [_documentId, ...arguments]);
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

  test(
    'native picture and following citation survive load and DOCX reopen',
    () async {
      final bytes = _odt();
      final originalBytes = Uint8List.fromList(bytes);
      final controller = _controller()..insertText('Draft ');
      final original = controller.document;
      await controller.loadBytesAsync(
        bytes,
        onProgress: (_) => expect(controller.document, same(original)),
      );
      _expectPicture(controller.document);
      _expectCitation(controller.document);
      expect(controller.isDirty, isFalse);
      expect(controller.canUndo, isFalse);
      expect(controller.canRedo, isFalse);
      expect(
        controller.revealZoteroField(controller.zoteroFields.single),
        isTrue,
      );
      expect(
        controller.zoteroFieldAtCaret!.citation!.citationId,
        'native-figure-source',
      );

      final saved = controller.saveBytes();
      expect(OdtDocumentReader.isOdt(saved), isFalse);
      final reopened = _controller();
      await reopened.loadBytesAsync(saved);
      _expectPicture(reopened.document);
      _expectCitation(reopened.document);
      expect(reopened.isDirty, isFalse);
      expect(reopened.canUndo, isFalse);
      final media = reopened.document.package!.parts
          .where((part) => part.contentType == 'image/png')
          .toList();
      expect(media, hasLength(1));
      expect(media.single.readBytes(), orderedEquals(_png));
      expect(bytes, orderedEquals(originalBytes));
    },
  );

  test(
    'refresh after a native picture is staged and is one undoable edit',
    () async {
      final controller = _controller();
      await controller.loadBytesAsync(_odt());
      controller.caret
        ..logicalIndex = 4
        ..selectionAnchorParagraph = 0
        ..selectionAnchor = 1;
      final beforeCaret = _caretState(controller);
      final beforeRevision = controller.contentRevision;
      final transaction = controller.beginZoteroTransaction(
        documentId: _documentId,
        command: ZoteroCitingCommand.refresh,
      );
      final field =
          (_call(transaction, 'Document.getFields', ['Http'])! as List)
              .cast<Map<String, Object>>()
              .single;
      expect(field['text'], _citationText);
      _call(transaction, 'Field.setCode', [
        field['id'],
        'ITEM CSL_CITATION ${jsonEncode(_citationData(_updatedCitationText))}',
      ]);
      _call(transaction, 'Field.setText', [
        field['id'],
        '<i>$_updatedCitationText</i>',
        true,
      ]);
      _call(transaction, 'Document.complete');
      transaction.session.prepareReview();
      _expectPicture(controller.document);
      _expectCitation(controller.document);
      expect(controller.contentRevision, beforeRevision);
      expect(controller.canUndo, isFalse);
      expect(controller.isDirty, isFalse);

      transaction.apply();
      _expectPicture(controller.document);
      _expectCitation(
        controller.document,
        text: _updatedCitationText,
        refreshed: true,
      );
      expect(controller.isDirty, isTrue);
      expect(controller.canUndo, isTrue);
      expect(
        controller.document.paragraphs.single.inlines
            .whereType<WmlRun>()
            .singleWhere((run) => run.text == _updatedCitationText)
            .properties
            .italic,
        isTrue,
      );
      controller.undo();
      _expectPicture(controller.document);
      _expectCitation(controller.document);
      expect(_caretState(controller), beforeCaret);
      expect(controller.canUndo, isFalse);
      expect(controller.canRedo, isTrue);
      controller.redo();
      _expectPicture(controller.document);
      _expectCitation(
        controller.document,
        text: _updatedCitationText,
        refreshed: true,
      );
      expect(controller.canUndo, isTrue);
      expect(controller.canRedo, isFalse);

      final reopened = _controller();
      await reopened.loadBytesAsync(controller.saveBytes());
      _expectPicture(reopened.document);
      _expectCitation(
        reopened.document,
        text: _updatedCitationText,
        refreshed: true,
      );
    },
  );

  for (final badMedia in ['missing', 'invalid']) {
    test(
      'a later $badMedia picture preserves current work and history',
      () async {
        final controller = _controller()..insertText('Draft ');
        // Exercise both a pending undo and a pending redo history.
        if (badMedia == 'missing') controller.undo();
        controller.caret
          ..logicalIndex = 4
          ..selectionAnchorParagraph = 0
          ..selectionAnchor = 1;
        final original = controller.document;
        final text = original.paragraphs.single.text;
        final revision = controller.contentRevision;
        final caret = _caretState(controller);
        final dirty = controller.isDirty;
        final undo = controller.canUndo;
        final redo = controller.canRedo;

        await expectLater(
          controller.loadBytesAsync(_odt(badMedia: badMedia)),
          throwsA(isA<StateError>()),
        );
        expect(controller.document, same(original));
        expect(original.paragraphs.single.text, text);
        expect(controller.contentRevision, revision);
        expect(_caretState(controller), caret);
        expect(controller.isDirty, dirty);
        expect(controller.canUndo, undo);
        expect(controller.canRedo, redo);
        expect(controller.document.inlineVisuals, isEmpty);
        expect(controller.zoteroFields, isEmpty);
        if (badMedia == 'missing') {
          controller.redo();
          expect(
            controller.document.paragraphs.single.text,
            'Draft Keep this draft',
          );
        } else {
          controller.undo();
          expect(controller.document.paragraphs.single.text, 'Keep this draft');
        }
      },
    );
  }

  test(
    'editing during picture import prevents stale document publication',
    () async {
      final controller = _controller();
      final original = controller.document;
      var edited = false;
      await expectLater(
        controller.loadBytesAsync(
          _odt(),
          onProgress: (_) {
            if (edited) return;
            edited = true;
            controller.insertText('Newer ');
          },
        ),
        throwsA(isA<StateError>()),
      );
      expect(edited, isTrue);
      expect(controller.document, same(original));
      expect(original.paragraphs.single.text, 'Newer Keep this draft');
      expect(controller.document.inlineVisuals, isEmpty);
      expect(controller.zoteroFields, isEmpty);
      expect(controller.caret.logicalIndex, 6);
      expect(controller.isDirty, isTrue);
      expect(controller.canUndo, isTrue);
      controller.undo();
      expect(original.paragraphs.single.text, 'Keep this draft');
    },
  );

  test(
    'disposing during picture import prevents document publication',
    () async {
      final controller = _controller()..insertText('Draft ');
      final original = controller.document;
      final text = original.paragraphs.single.text;
      final revision = controller.contentRevision;
      final caret = _caretState(controller);
      await expectLater(
        controller.loadBytesAsync(
          _odt(),
          onProgress: (_) {
            if (!controller.isDisposed) controller.dispose();
          },
        ),
        throwsA(isA<StateError>()),
      );
      expect(controller.isDisposed, isTrue);
      expect(controller.document, same(original));
      expect(original.paragraphs.single.text, text);
      expect(controller.contentRevision, revision);
      expect(_caretState(controller), caret);
      expect(controller.document.inlineVisuals, isEmpty);
      expect(controller.zoteroFields, isEmpty);
    },
  );

  testWidgets('native imported PNG paints beside the editable citation', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final controller = _controller();
    await tester.runAsync(() => controller.loadBytesAsync(_odt()));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: _canvasKey,
            child: QudsWordEditor(
              controller: controller,
              enableLiveProofing: false,
            ),
          ),
        ),
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
    _expectPicture(controller.document);
    _expectCitation(controller.document);
    // Wait for actual raster decode/repaint with a bound. A live editor has
    // caret timers, so a generic pumpAndSettle would not be an appropriate gate.
    var painted = (red: 0, green: 0);
    for (var attempt = 0; attempt < 10; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      painted = await _paintedColors(tester);
      if (painted.red > 4 && painted.green > 4) break;
    }
    expect(painted.red, greaterThan(4), reason: 'PNG red pixels must paint.');
    expect(
      painted.green,
      greaterThan(4),
      reason: 'PNG green pixels must paint.',
    );
    expect(tester.takeException(), isNull);
  });
}
