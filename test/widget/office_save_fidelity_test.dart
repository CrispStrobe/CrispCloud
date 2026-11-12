// Exercise the actual F4 host and captured remote target, not only the package
// controller. A delayed upload exposes edits that arrive after serialization.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/file_cache_service.dart';
import 'package:crisp_cloud/widgets/office_editor_dialog.dart';
import 'package:crisp_cloud/widgets/office_editor_ribbon.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart' as xml;

import '../support/workflow_fake_client.dart';
import '../support/workspace_fixture.dart';

class _DelayedCloud extends WorkflowFakeClient {
  Completer<void>? _nextUpload;
  Completer<void>? _activeUpload;
  Uint8List? pendingBytes;
  Uint8List? attemptedBytes;
  int uploadAttempts = 0;

  void pauseNextUpload() {
    _nextUpload = Completer<void>();
    pendingBytes = null;
  }

  void releaseUpload() => _activeUpload!.complete();

  @override
  Future<void> uploadFile(
    List<int> bytes,
    String name,
    String targetPath, {
    Function(int, int)? onProgress,
  }) async {
    uploadAttempts++;
    attemptedBytes = Uint8List.fromList(bytes);
    final gate = _nextUpload;
    _nextUpload = null;
    if (gate != null) {
      _activeUpload = gate;
      pendingBytes = Uint8List.fromList(bytes);
      await gate.future;
      _activeUpload = null;
    }
    await super.uploadFile(bytes, name, targetPath, onProgress: onProgress);
  }
}

class _Cache extends FileCacheService {
  @override
  Future<void> remove(String remotePath, String provider) async {}
}

class _ImagePicker extends FilePicker {
  _ImagePicker(this.bytes);
  final Uint8List bytes;
  int calls = 0;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    expect(type, FileType.image);
    expect(withData, isTrue);
    calls++;
    return FilePickerResult([
      PlatformFile(
        name: 'ribbon-picture.png',
        size: bytes.length,
        bytes: bytes,
      ),
    ]);
  }
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() complete,
  String reason,
) async {
  final elapsed = Stopwatch()..start();
  do {
    await tester.pump(const Duration(milliseconds: 20));
    await Future<void>.delayed(const Duration(milliseconds: 1));
    if (elapsed.elapsed > const Duration(seconds: 15)) {
      throw TimeoutException(reason);
    }
  } while (!complete());
  await tester.pump();
}

OfficeEditorRibbon _ribbon(WidgetTester tester) =>
    tester.widget<OfficeEditorRibbon>(find.byType(OfficeEditorRibbon));

Future<WordEditorController> _open(
  WidgetTester tester,
  _DelayedCloud cloud, {
  bool keepExisting = false,
}) async => await _openFixture(
  tester,
  cloud,
  name: 'report.docx',
  fixture: 'word.docx',
  editorType: QudsWordEditor,
  keepExisting: keepExisting,
) as WordEditorController;

Future<OfficeController> _openFixture(
  WidgetTester tester,
  _DelayedCloud cloud, {
  required String name,
  required String fixture,
  required Type editorType,
  bool keepExisting = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  if (!keepExisting) {
    cloud.put(
      '/$name',
      File('packages/quds_office_engine/test/fixtures/fidelity/$fixture')
          .readAsBytesSync(),
    );
  }
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith((_) => WorkspaceTestAuth(cloud)),
      fileCacheProvider.overrideWithValue(_Cache()),
    ],
  );
  addTearDown(container.dispose);
  final panel = container.read(panelProvider(PanelSide.remote));
  await panel.refresh();
  final file = panel.files!.single;
  expect(panel.originForOperation(file), isNotNull);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      OfficeEditorDialog(file: file, side: PanelSide.remote),
                ),
              ),
              child: const Text('Open fixture'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open fixture'));
  await _pumpUntil(
    tester,
    () => find.byType(editorType).evaluate().isNotEmpty,
    'The real Office host did not finish importing the remote fixture.',
  );
  await tester.pump(const Duration(milliseconds: 400));
  return _ribbon(tester).controller;
}

Future<void> _beginSave(WidgetTester tester, _DelayedCloud cloud) async {
  cloud.pauseNextUpload();
  await tester.tap(find.byTooltip('Save'));
  await _pumpUntil(
    tester,
    () => cloud.pendingBytes != null,
    'The real Office host did not start its remote upload.',
  );
  expect(_ribbon(tester).saving, isTrue);
}

Future<void> _finishSave(WidgetTester tester, _DelayedCloud cloud) async {
  cloud.releaseUpload();
  await _pumpUntil(
    tester,
    () => !_ribbon(tester).saving,
    'The real Office host did not finish its remote upload.',
  );
}

xml.XmlDocument _part(Uint8List bytes, String name) {
  final archive = ZipDecoder().decodeBytes(bytes);
  return xml.XmlDocument.parse(utf8.decode(archive.findFile(name)!.content));
}

String _text(xml.XmlDocument document) => document.descendants
    .whereType<xml.XmlElement>()
    .where((element) => element.name.local == 't')
    .map((element) => element.innerText)
    .join();

String _firstValue(xml.XmlDocument document, String local, String attribute) =>
    document.descendants
        .whereType<xml.XmlElement>()
        .firstWhere((element) => element.name.local == local)
        .attributes
        .firstWhere((value) => value.name.local == attribute)
        .value;

void _evidence(String name, Uint8List bytes, {String extension = 'docx'}) {
  final file = File('build/fidelity-host/$name.$extension');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes);
}

const _wordNs = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

String _storyText(xml.XmlElement node) {
  final result = StringBuffer();
  for (final child in node.descendants.whereType<xml.XmlElement>()) {
    if (child.name.namespaceUri != _wordNs) continue;
    switch (child.name.local) {
      case 't':
        result.write(child.innerText);
      case 'br':
        if (child.parent is xml.XmlElement &&
            (child.parent! as xml.XmlElement).name.local == 'r') {
          result.write('\n');
        }
      case 'tab':
        // Paragraph tab-stop definitions share the local name with run tabs.
        if (child.parent is xml.XmlElement &&
            (child.parent! as xml.XmlElement).name.local == 'r') {
          result.write('\t');
        }
    }
  }
  return result.toString();
}

void _assertRibbonExport(Uint8List bytes, Uint8List pickedImage) {
  final document = _part(bytes, 'word/document.xml');
  final paragraph = document.findAllElements('p', namespace: _wordNs).first;
  final properties = paragraph.getElement('pPr', namespace: _wordNs)!;
  String? value(String element, String attribute) => properties
      .getElement(element, namespace: _wordNs)
      ?.getAttribute(attribute, namespace: _wordNs);
  expect(value('pStyle', 'val'), 'Heading2');
  expect(value('jc', 'val'), 'center');
  expect(value('ind', 'left'), '360');
  expect(value('spacing', 'before'), '120');
  expect(value('spacing', 'after'), '360');
  expect(value('spacing', 'line'), '360');
  expect(
    properties
        .findAllElements('tab', namespace: _wordNs)
        .map(
          (node) => (
            node.getAttribute('pos', namespace: _wordNs),
            node.getAttribute('val', namespace: _wordNs),
            node.getAttribute('leader', namespace: _wordNs) ?? 'none',
          ),
        )
        .toList(),
    [('1440', 'center', 'dot'), ('2880', 'decimal', 'underscore')],
  );
  expect(
    paragraph
        .findAllElements('b', namespace: _wordNs)
        .map((node) => node.getAttribute('val', namespace: _wordNs)),
    contains('0'),
    reason:
        'The explicit unbold edit must override Heading2 style inheritance.',
  );
  expect(_storyText(paragraph), 'Imported heading');
  expect(
    document
        .findAllElements('footnoteReference', namespace: _wordNs)
        .map((node) => node.getAttribute('id', namespace: _wordNs))
        .toSet(),
    {'12', '13'},
  );
  expect(
    document
        .findAllElements('endnoteReference', namespace: _wordNs)
        .map((node) => node.getAttribute('id', namespace: _wordNs))
        .toSet(),
    {'3', '4'},
  );
  final footnote = _part(bytes, 'word/footnotes.xml')
      .findAllElements('footnote', namespace: _wordNs)
      .singleWhere(
        (node) => node.getAttribute('id', namespace: _wordNs) == '13',
      );
  final endnote = _part(bytes, 'word/endnotes.xml')
      .findAllElements('endnote', namespace: _wordNs)
      .singleWhere(
        (node) => node.getAttribute('id', namespace: _wordNs) == '4',
      );
  expect(_storyText(footnote), '  Footnote first\nsecond\tline  ');
  expect(_storyText(endnote), ' Endnote from the ribbon');
  expect(
    footnote.findAllElements('footnoteRef', namespace: _wordNs),
    hasLength(1),
  );
  expect(
    endnote.findAllElements('endnoteRef', namespace: _wordNs),
    hasLength(1),
  );

  const drawingNs = 'http://schemas.openxmlformats.org/drawingml/2006/main';
  const relNs =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
  const placementNs =
      'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing';
  final blips = document.findAllElements('blip', namespace: drawingNs).toList();
  expect(blips, hasLength(2));
  expect(
    document
        .findAllElements(
          'extent',
          namespace: 'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing',
        )
        .map((node) => (node.getAttribute('cx'), node.getAttribute('cy'))),
    contains(('19050', '19050')),
    reason:
        'The authored 2 by 2 pixel PNG stays square at 1.5 points at 96 dpi.',
  );
  // Read the authored PNG header independently of the production image decoder.
  expect(pickedImage.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
  expect(utf8.decode(pickedImage.sublist(12, 16)), 'IHDR');
  final imageHeader = ByteData.sublistView(pickedImage);
  expect((imageHeader.getUint32(16), imageHeader.getUint32(20)), (2, 2));
  final archive = ZipDecoder().decodeBytes(bytes);
  final relationships = _part(bytes, 'word/_rels/document.xml.rels');
  final payloads = <List<int>>[];
  var pickedDrawings = 0;
  for (final blip in blips) {
    final id = blip.getAttribute('embed', namespace: relNs);
    final relation = relationships.rootElement.childElements.singleWhere(
      (node) => node.getAttribute('Id') == id,
    );
    expect(relation.getAttribute('TargetMode'), isNot('External'));
    final path = Uri.parse('/word/document.xml')
        .resolve(relation.getAttribute('Target')!)
        .path
        .substring(1);
    final payload = archive.findFile(path)!.content;
    payloads.add(payload);
    if (base64Encode(payload) == base64Encode(pickedImage)) {
      pickedDrawings++;
      final placement = blip.ancestors.whereType<xml.XmlElement>().firstWhere(
        (node) =>
            node.name.namespaceUri == placementNs &&
            (node.name.local == 'inline' || node.name.local == 'anchor'),
      );
      final extent = placement
          .findElements('extent', namespace: placementNs)
          .single;
      expect(
        (extent.getAttribute('cx'), extent.getAttribute('cy')),
        ('19050', '19050'),
        reason:
            'The picked 2-pixel square retains its 1.5-point size at 96 dpi.',
      );
    }
  }
  expect(pickedDrawings, 1);
  expect(payloads, contains(orderedEquals(pickedImage)));
  final original = ZipDecoder().decodeBytes(
    File('packages/quds_office_engine/test/fixtures/fidelity/word.docx')
        .readAsBytesSync(),
  );
  final originalImage = original.files
      .singleWhere((file) => file.name.startsWith('word/media/'))
      .content;
  expect(
    payloads,
    contains(orderedEquals(originalImage)),
    reason: 'Inserting a picture must not overwrite the imported picture.',
  );
}

Future<void> _tapSettled(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

InlineCellEditor _inlineEditor(OfficeController controller) =>
    switch (controller) {
      SheetEditorController() => controller.cellEditor,
      SlideEditorController() => controller.textEditor,
      _ => throw ArgumentError('Expected a sheet or slide editor'),
    };

String _liveDraftValue(OfficeController controller) => switch (controller) {
  SheetEditorController() => controller.sheet.cellA1('A1').asString,
  SlideEditorController() =>
    controller.slide.shapes.singleWhere((shape) => shape.id == 2).text,
  _ => throw ArgumentError('Expected a sheet or slide editor'),
};

Future<void> _beginInlineDraft(
  WidgetTester tester,
  OfficeController controller,
) async {
  final FocusNode? focus;
  if (controller is SheetEditorController) {
    controller.selection.selectCell(const SmlCellRef(0, 0));
    focus = tester
        .widget<QudsSheetEditor>(find.byType(QudsSheetEditor))
        .focusNode;
  } else if (controller is SlideEditorController) {
    controller.selectShape(
      controller.slide.shapes.singleWhere((shape) => shape.id == 2),
    );
    focus = tester
        .widget<QudsSlideEditor>(find.byType(QudsSlideEditor))
        .focusNode;
  } else {
    throw ArgumentError('Expected a sheet or slide editor');
  }
  expect(focus, isNotNull);
  focus!.requestFocus();
  await tester.pump();
  await tester.sendKeyEvent(LogicalKeyboardKey.f2);
  await tester.pump();
  expect(_inlineEditor(controller).editing, isTrue);
  expect(_inlineEditor(controller).bridge.isAttached, isTrue);
  expect(tester.testTextInput.hasAnyClients, isTrue);
}

Future<void> _saveShortcut(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

Future<void> _saveDraft(WidgetTester tester, {required bool close}) async {
  if (close) {
    await tester.tap(find.byTooltip('Close').last);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Unsaved changes'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
  } else {
    await _saveShortcut(tester);
  }
}

Future<void> _runAsyncDraftCase(
  WidgetTester tester,
  Future<void> Function() body,
) async {
  (Object, StackTrace)? failure;
  await tester.runAsync(() async {
    try {
      await body();
    } catch (error, stack) {
      failure = (error, stack);
    }
  });
  if (failure case final error?) {
    Error.throwWithStackTrace(error.$1, error.$2);
  }
}

String _savedDraftValue(Uint8List bytes, {required bool sheet}) {
  if (sheet) {
    const ns = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
    final cell = _part(bytes, 'xl/worksheets/sheet1.xml')
        .findAllElements('c', namespace: ns)
        .singleWhere((node) => node.getAttribute('r') == 'A1');
    if (cell.getAttribute('t') == 's') {
      final index = int.parse(cell.getElement('v', namespace: ns)!.innerText);
      return _part(bytes, 'xl/sharedStrings.xml')
          .findAllElements('si', namespace: ns)
          .elementAt(index)
          .findAllElements('t', namespace: ns)
          .map((node) => node.innerText)
          .join();
    }
    if (cell.getAttribute('t') == 'inlineStr') {
      return cell
          .findAllElements('t', namespace: ns)
          .map((node) => node.innerText)
          .join();
    }
    return cell.getElement('v', namespace: ns)?.innerText ?? '';
  }
  const presentationNs =
      'http://schemas.openxmlformats.org/presentationml/2006/main';
  const drawingNs = 'http://schemas.openxmlformats.org/drawingml/2006/main';
  final title = _part(bytes, 'ppt/slides/slide1.xml')
      .findAllElements('sp', namespace: presentationNs)
      .singleWhere(
        (shape) =>
            shape
                .getElement('nvSpPr', namespace: presentationNs)!
                .getElement('cNvPr', namespace: presentationNs)!
                .getAttribute('id') ==
            '2',
      );
  return title
      .findAllElements('p', namespace: drawingNs)
      .map(
        (paragraph) => paragraph
            .findAllElements('t', namespace: drawingNs)
            .map((node) => node.innerText)
            .join(),
      )
      .join('\n');
}

void main() {
  testWidgets(
    'ribbon headings, paragraphs, notes and pictures survive three host saves',
    (tester) async {
      tester.view.physicalSize = const Size(2000, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final picture = File(
        'packages/quds_office_engine/test/fixtures/fidelity/scripts/replacement.png',
      ).readAsBytesSync();
      final picker = _ImagePicker(picture);
      // File-picker plugins have no registered instance in the widget-test
      // isolate. Install the deterministic boundary used by this scenario.
      FilePicker.platform = picker;
      await tester.runAsync(() async {
        final cloud = _DelayedCloud();
        var controller = await _open(tester, cloud);
        controller.jumpToParagraph(0);
        await tester.pump();
        await _tapSettled(tester, find.text('Heading 1').last);
        await _tapSettled(tester, find.text('Heading 2').last);
        final title = controller.document.paragraphs.first;
        controller.caret
          ..paragraphIndex = 0
          ..logicalIndex = title.text.length
          ..selectionAnchorParagraph = 0
          ..selectionAnchor = 0;
        controller.refresh();
        await tester.pump();
        expect(controller.activeRunProps.bold, isTrue);
        await _tapSettled(tester, find.byTooltip('Bold (Ctrl+B)'));
        await _tapSettled(tester, find.byIcon(Icons.format_align_center).first);
        await _tapSettled(tester, find.byTooltip('Paragraph settings…'));
        for (final entry in {
          'Left indent (pt)': '18',
          'Space before (pt)': '6',
          'Space after (pt)': '18',
          'Line spacing': '1.5',
        }.entries) {
          await tester.enterText(
            find.widgetWithText(TextField, entry.key),
            entry.value,
          );
        }
        for (var index = 0; index < 2; index++) {
          final add = find.byKey(const ValueKey<String>('word-tab-add'));
          await tester.ensureVisible(add);
          await _tapSettled(tester, add);
          final field = find.byKey(
            ValueKey<String>('word-tab-position-$index'),
          );
          await tester.ensureVisible(field);
          await tester.enterText(field, '${72 * (index + 1)}');
        }
        for (final (key, label) in [
          ('alignment-0', 'Center'),
          ('leader-0', 'Dots'),
          ('alignment-1', 'Decimal'),
          ('leader-1', 'Underline'),
        ]) {
          final field = find.byKey(ValueKey<String>('word-tab-$key'));
          await tester.ensureVisible(field);
          await _tapSettled(tester, field);
          await _tapSettled(tester, find.text(label).last);
        }
        await _tapSettled(tester, find.widgetWithText(ElevatedButton, 'Apply'));

        controller.jumpToParagraph(0);
        controller.caret.logicalIndex = 7;
        controller.caret.collapseSelection();
        controller.refresh();
        await _tapSettled(tester, find.text('Insert').last);
        await _tapSettled(tester, find.text('Footnote'));
        expect(find.text('Insert footnote'), findsOneWidget);
        await tester.enterText(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextField),
          ),
          '  Footnote first\nsecond\tline  ',
        );
        await _tapSettled(
          tester,
          find.widgetWithText(ElevatedButton, 'Insert'),
        );
        await _tapSettled(tester, find.text('Endnote'));
        expect(find.text('Insert endnote'), findsOneWidget);
        await tester.enterText(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextField),
          ),
          'Endnote from the ribbon',
        );
        await _tapSettled(
          tester,
          find.widgetWithText(ElevatedButton, 'Insert'),
        );
        // Return from the note story before choosing a body picture.
        controller.jumpToParagraph(0);
        controller.caret.collapseSelection();
        controller.refresh();
        await tester.pump();
        await _tapSettled(tester, find.text('Picture'));
        expect(picker.calls, 1);
        await _pumpUntil(
          tester,
          () => controller.document.visuals.length == 2,
          'The decoded ribbon picture was not inserted.',
        );
        expect(controller.document.visuals, hasLength(2));

        for (var cycle = 1; cycle <= 3; cycle++) {
          await tester.tap(find.byTooltip('Save'));
          await _pumpUntil(
            tester,
            () => !_ribbon(tester).saving && cloud.writes.length == cycle,
            'The ribbon-edited document was not uploaded in cycle $cycle.',
          );
          final bytes = cloud.files['/report.docx']!;
          _assertRibbonExport(bytes, picture);
          _evidence('ribbon-edits-$cycle', bytes);
          await _tapSettled(tester, find.byTooltip('Close').last);
          controller = await _open(tester, cloud, keepExisting: true);
          expect(
            controller.document.paragraphs.first.properties.styleId,
            'Heading2',
          );
          expect(controller.document.footnotes, hasLength(2));
          expect(controller.document.endnotes, hasLength(2));
          expect(controller.document.visuals, hasLength(2));
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'new text, style, note and image edits stay dirty during upload',
    (tester) async {
      await tester.runAsync(() async {
        final cloud = _DelayedCloud();
        final controller = await _open(tester, cloud);
        controller.jumpToParagraph(0);
        controller.insertText('Saved prefix ');
        await tester.pump();
        await _beginSave(tester, cloud);

        controller.jumpToParagraph(0);
        controller.insertText('Unsaved prefix ');
        controller.applyStyle('Heading2');
        controller.applyParagraphFormat(
          (paragraph) => paragraph.spacingAfter = 18,
        );
        controller.insertFootnote(text: 'Note added during upload');
        controller.selectVisual(controller.document.visuals.single);
        controller.mutateSelectedVisual((visual) => visual.width = 72);

        await _finishSave(tester, cloud);
        expect(controller.isDirty, isTrue);
        expect(_ribbon(tester).dirty, isTrue);
        expect(find.text('report.docx •'), findsOneWidget);
        expect(cloud.files['/report.docx'], cloud.pendingBytes);

        // Independent ZIP/XML inspection checks the bytes actually uploaded.
        final firstBytes = cloud.files['/report.docx']!;
        final first = _part(firstBytes, 'word/document.xml');
        expect(_text(first), contains('Saved prefix Imported heading'));
        expect(_text(first), isNot(contains('Unsaved prefix')));
        expect(_firstValue(first, 'pStyle', 'val'), 'Heading1');
        expect(_firstValue(first, 'extent', 'cx'), '457200');
        expect(
          _text(_part(firstBytes, 'word/footnotes.xml')),
          isNot(contains('Note added during upload')),
        );
        _evidence('before-late-edits', firstBytes);

        await tester.tap(find.byTooltip('Save'));
        await _pumpUntil(
          tester,
          () => !_ribbon(tester).saving && cloud.writes.length == 2,
          'The subsequent save did not write the newer revision.',
        );
        expect(controller.isDirty, isFalse);
        expect(_ribbon(tester).dirty, isFalse);
        final secondBytes = cloud.files['/report.docx']!;
        final second = _part(secondBytes, 'word/document.xml');
        expect(_text(second), contains('Unsaved prefix '));
        expect(_firstValue(second, 'pStyle', 'val'), 'Heading2');
        expect(_firstValue(second, 'spacing', 'after'), '360');
        expect(_firstValue(second, 'extent', 'cx'), '914400');
        expect(
          _text(_part(secondBytes, 'word/footnotes.xml')),
          contains('Note added during upload'),
        );
        _evidence('after-late-edits', secondBytes);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Save and Close keeps newer edits open until they are saved', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final cloud = _DelayedCloud();
      final controller = await _open(tester, cloud);
      controller.insertText('First edit ');
      await tester.pump();
      await tester.tap(find.byTooltip('Close').last);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Unsaved changes'), findsOneWidget);
      cloud.pauseNextUpload();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await _pumpUntil(
        tester,
        () => cloud.pendingBytes != null,
        'Save and Close did not start the upload.',
      );
      controller.insertFootnote(text: 'Late footnote must remain open');
      await _finishSave(tester, cloud);
      expect(find.byType(QudsWordEditor), findsOneWidget);
      expect(controller.isDirty, isTrue);
      expect(
        _text(_part(cloud.files['/report.docx']!, 'word/footnotes.xml')),
        isNot(contains('Late footnote must remain open')),
      );
      _evidence('close-before-late-edit', cloud.files['/report.docx']!);

      await tester.tap(find.byTooltip('Close').last);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Unsaved changes'), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await _pumpUntil(
        tester,
        () => find.byType(OfficeEditorDialog).evaluate().isEmpty,
        'Save and Close did not close after writing the latest revision.',
      );
      expect(find.text('Open fixture'), findsOneWidget);
      expect(
        _text(_part(cloud.files['/report.docx']!, 'word/footnotes.xml')),
        contains('Late footnote must remain open'),
      );
      _evidence('close-after-late-edit', cloud.files['/report.docx']!);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
    expect(tester.takeException(), isNull);
  });

  for (final saveAndClose in [false, true]) {
    testWidgets(
      saveAndClose
          ? 'Save and Close retains pending note typing until its next upload'
          : 'pending note typing stays dirty until its next upload',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.runAsync(() async {
          final cloud = _DelayedCloud();
          final controller = await _open(tester, cloud);
          controller.insertText('First saved edit ');
          await tester.pump();
          if (saveAndClose) {
            await tester.tap(find.byTooltip('Close').last);
            await tester.pump(const Duration(milliseconds: 400));
            expect(find.text('Unsaved changes'), findsOneWidget);
            cloud.pauseNextUpload();
            await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
            await _pumpUntil(
              tester,
              () => cloud.pendingBytes != null,
              'Save and Close did not start its pending-note upload.',
            );
          } else {
            await _beginSave(tester, cloud);
          }

          final capturedRevision = controller.contentRevision;
          var commands = 0;
          void onCommand() => commands++;
          controller.commands.addListener(onCommand);
          final field = find.byKey(const ValueKey<String>('notes-edit-12'));
          expect(field, findsOneWidget);
          // Keep focus in the actual notes-pane field. No focus-loss command
          // may conceal a missing revision change while the upload is waiting.
          await tester.enterText(
            field,
            'New note text while upload waits\nNote link',
          );
          await tester.pump();
          expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
          expect(commands, 0);
          expect(controller.contentRevision, greaterThan(capturedRevision));
          expect(controller.isDirty, isTrue);

          cloud.releaseUpload();
          await _pumpUntil(
            tester,
            () =>
                find.byType(OfficeEditorDialog).evaluate().isEmpty ||
                !_ribbon(tester).saving,
            'The older pending-note upload did not finish.',
          );
          expect(find.byType(OfficeEditorDialog), findsOneWidget);
          expect(commands, 0);
          controller.commands.removeListener(onCommand);
          expect(controller.isDirty, isTrue);
          expect(_ribbon(tester).dirty, isTrue);
          expect(find.text('report.docx •'), findsOneWidget);
          expect(cloud.files['/report.docx'], cloud.pendingBytes);

          List<String> noteParagraphs(Uint8List bytes) =>
              _part(bytes, 'word/footnotes.xml')
                  .findAllElements('footnote', namespace: _wordNs)
                  .singleWhere(
                    (note) =>
                        note.getAttribute('id', namespace: _wordNs) == '12',
                  )
                  .findElements('p', namespace: _wordNs)
                  .map(_storyText)
                  .toList();
          expect(noteParagraphs(cloud.files['/report.docx']!), [
            ' Footnote text',
            'Note link',
          ]);
          final prefix = saveAndClose ? 'pending-note-close' : 'pending-note';
          _evidence('$prefix-before-save', cloud.files['/report.docx']!);

          if (saveAndClose) {
            await tester.tap(find.byTooltip('Close').last);
            await tester.pump(const Duration(milliseconds: 400));
            expect(find.text('Unsaved changes'), findsOneWidget);
            await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
            await _pumpUntil(
              tester,
              () => find.byType(OfficeEditorDialog).evaluate().isEmpty,
              'Save and Close did not close after uploading pending note text.',
            );
            expect(find.text('Open fixture'), findsOneWidget);
          } else {
            await tester.tap(find.byTooltip('Save'));
            await _pumpUntil(
              tester,
              () => !_ribbon(tester).saving && cloud.writes.length == 2,
              'The next save did not upload the pending note text.',
            );
            expect(controller.isDirty, isFalse);
            expect(_ribbon(tester).dirty, isFalse);
          }
          expect(cloud.writes, hasLength(2));
          expect(noteParagraphs(cloud.files['/report.docx']!), [
            ' New note text while upload waits',
            'Note link',
          ]);
          _evidence('$prefix-after-save', cloud.files['/report.docx']!);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        });
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final sheet in [true, false]) {
    for (final saveAndClose in [false, true]) {
      final kind = sheet ? 'cell' : 'slide';
      final extension = sheet ? 'xlsx' : 'pptx';
      final name = sheet ? 'budget.xlsx' : 'deck.pptx';
      testWidgets(
        'pending $kind typing survives ${saveAndClose ? 'Save and Close' : 'Save'} uploads and retries',
        (tester) async {
          tester.view.physicalSize = const Size(1600, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await _runAsyncDraftCase(tester, () async {
            final cloud = _DelayedCloud();
            final controller = await _openFixture(
              tester,
              cloud,
              name: name,
              fixture: 'native.$extension',
              editorType: sheet ? QudsSheetEditor : QudsSlideEditor,
            );
            final originalText = sheet ? 'Region' : 'Native slide 1';
            expect(
              _savedDraftValue(cloud.files['/$name']!, sheet: sheet),
              originalText,
            );
            expect(controller.isDirty, isFalse);
            final cleanRevision = controller.contentRevision;
            await _beginInlineDraft(tester, controller);
            expect(controller.contentRevision, cleanRevision);
            expect(controller.isDirty, isFalse);
            tester.testTextInput.updateEditingValue(
              TextEditingValue(
                text: originalText,
                selection: const TextSelection.collapsed(offset: 0),
              ),
            );
            await tester.pump();
            expect(controller.contentRevision, cleanRevision);
            expect(controller.isDirty, isFalse);
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pump();
            expect(_inlineEditor(controller).editing, isFalse);
            expect(controller.isDirty, isFalse);
            expect(controller.canUndo, isFalse);

            // Real IME input followed by Escape must restore a clean document.
            await _beginInlineDraft(tester, controller);
            tester.testTextInput.enterText('Cancelled $kind draft');
            await tester.pump();
            expect(controller.isDirty, isTrue);
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pump();
            expect(_liveDraftValue(controller), originalText);
            expect(controller.isDirty, isFalse);
            expect(_ribbon(tester).dirty, isFalse);
            expect(controller.canUndo, isFalse);

            final firstText = 'First saved $kind draft';
            await _beginInlineDraft(tester, controller);
            tester.testTextInput.enterText(firstText);
            await tester.pump();
            expect(_inlineEditor(controller).editing, isTrue);
            expect(controller.isDirty, isTrue);
            expect(controller.commands.canUndo, isFalse);
            cloud.pauseNextUpload();
            await _saveDraft(tester, close: saveAndClose);
            await _pumpUntil(
              tester,
              () => cloud.pendingBytes != null,
              'The host did not upload its first pending $kind draft.',
            );
            expect(_inlineEditor(controller).editing, isFalse);
            expect(
              _savedDraftValue(cloud.pendingBytes!, sheet: sheet),
              firstText,
            );

            await _beginInlineDraft(tester, controller);
            final capturedRevision = controller.contentRevision;
            var commands = 0;
            void onCommand() => commands++;
            controller.commands.addListener(onCommand);
            final newerText = 'New $kind text while upload waits';
            tester.testTextInput.enterText(newerText);
            await tester.pump();
            expect(_inlineEditor(controller).formulaBar, newerText);
            expect(_inlineEditor(controller).editing, isTrue);
            expect(_inlineEditor(controller).bridge.isAttached, isTrue);
            expect(commands, 0);
            expect(controller.contentRevision, greaterThan(capturedRevision));
            expect(controller.isDirty, isTrue);

            cloud.releaseUpload();
            await _pumpUntil(
              tester,
              () =>
                  find.byType(OfficeEditorDialog).evaluate().isEmpty ||
                  !_ribbon(tester).saving,
              'The older $kind upload did not finish.',
            );
            expect(find.byType(OfficeEditorDialog), findsOneWidget);
            expect(commands, 0);
            controller.commands.removeListener(onCommand);
            expect(_inlineEditor(controller).editing, isTrue);
            expect(controller.isDirty, isTrue);
            expect(_ribbon(tester).dirty, isTrue);
            expect(find.text('$name •'), findsOneWidget);
            expect(cloud.files['/$name'], cloud.pendingBytes);
            expect(
              _savedDraftValue(cloud.files['/$name']!, sheet: sheet),
              firstText,
            );
            final prefix = 'pending-$kind${saveAndClose ? '-close' : ''}';
            _evidence(
              '$prefix-before-save',
              cloud.files['/$name']!,
              extension: extension,
            );

            // A failed write must keep the newer draft and original bytes so
            // the same host can retry, including the Save and Close path.
            cloud.failUploads = true;
            await _saveDraft(tester, close: saveAndClose);
            await _pumpUntil(
              tester,
              () =>
                  cloud.uploadAttempts == 2 &&
                  !_ribbon(tester).saving &&
                  find.textContaining('Save failed').evaluate().isNotEmpty,
              'The failed $kind upload did not return to the editor.',
            );
            expect(find.textContaining('Save failed'), findsOneWidget);
            expect(find.byType(OfficeEditorDialog), findsOneWidget);
            expect(controller.isDirty, isTrue);
            expect(_ribbon(tester).dirty, isTrue);
            expect(cloud.writes, hasLength(1));
            expect(
              _savedDraftValue(cloud.files['/$name']!, sheet: sheet),
              firstText,
            );
            expect(
              _savedDraftValue(cloud.attemptedBytes!, sheet: sheet),
              newerText,
            );

            cloud.failUploads = false;
            await _saveDraft(tester, close: saveAndClose);
            await _pumpUntil(
              tester,
              () => saveAndClose
                  ? find.byType(OfficeEditorDialog).evaluate().isEmpty
                  : !_ribbon(tester).saving && cloud.writes.length == 2,
              'The retry did not save the pending $kind text.',
            );
            if (saveAndClose) {
              expect(find.text('Open fixture'), findsOneWidget);
            } else {
              expect(controller.isDirty, isFalse);
              expect(_ribbon(tester).dirty, isFalse);
            }
            expect(cloud.writes, hasLength(2));
            expect(cloud.uploadAttempts, 3);
            expect(
              _savedDraftValue(cloud.files['/$name']!, sheet: sheet),
              newerText,
            );
            _evidence(
              '$prefix-after-save',
              cloud.files['/$name']!,
              extension: extension,
            );
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
          });
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('selection changes during upload do not create unsaved edits', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final cloud = _DelayedCloud();
      final controller = await _open(tester, cloud);
      controller.insertText('Saved edit ');
      await tester.pump();
      await _beginSave(tester, cloud);
      controller.jumpToParagraph(1);
      controller.selectParagraphAtCaret();
      controller.refresh();
      await _finishSave(tester, cloud);
      expect(controller.isDirty, isFalse);
      expect(_ribbon(tester).dirty, isFalse);
      expect(cloud.writes.length, 1);
      expect(
        _text(_part(cloud.files['/report.docx']!, 'word/document.xml')),
        contains('Saved edit '),
      );
      _evidence('selection-save', cloud.files['/report.docx']!);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed upload preserves the original and retains dirty edits', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final cloud = _DelayedCloud();
      final controller = await _open(tester, cloud);
      final original = Uint8List.fromList(cloud.files['/report.docx']!);
      controller.insertText('Pending edit ');
      await tester.pump();
      cloud.failUploads = true;
      await tester.tap(find.byTooltip('Save'));
      await _pumpUntil(
        tester,
        () => cloud.uploadAttempts == 1 && !_ribbon(tester).saving,
        'The failed upload was not surfaced by the host.',
      );
      expect(find.textContaining('Save failed'), findsOneWidget);
      expect(controller.isDirty, isTrue);
      expect(_ribbon(tester).dirty, isTrue);
      expect(cloud.files['/report.docx'], original);
      expect(cloud.writes, isEmpty);
      expect(
        _text(_part(cloud.attemptedBytes!, 'word/document.xml')),
        contains('Pending edit '),
      );
      _evidence('failed-upload-attempt', cloud.attemptedBytes!);

      cloud.failUploads = false;
      await tester.tap(find.byTooltip('Save'));
      await _pumpUntil(
        tester,
        () => cloud.writes.length == 1 && !_ribbon(tester).saving,
        'Retry did not save the retained edit.',
      );
      expect(controller.isDirty, isFalse);
      expect(
        _text(_part(cloud.files['/report.docx']!, 'word/document.xml')),
        contains('Pending edit '),
      );
      _evidence('retry-after-failure', cloud.files['/report.docx']!);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
    expect(tester.takeException(), isNull);
  });
}
