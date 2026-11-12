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
}) async {
  SharedPreferences.setMockInitialValues({});
  if (!keepExisting) {
    cloud.put(
      '/report.docx',
      File('packages/quds_office_engine/test/fixtures/fidelity/word.docx')
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
    () => find.byType(QudsWordEditor).evaluate().isNotEmpty,
    'The real Office host did not finish importing the remote fixture.',
  );
  await tester.pump(const Duration(milliseconds: 400));
  return tester.widget<QudsWordEditor>(find.byType(QudsWordEditor)).controller;
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

void _evidence(String name, Uint8List bytes) {
  final file = File('build/fidelity-host/$name.docx');
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
        .map((node) => node.getAttribute('pos', namespace: _wordNs))
        .toList(),
    ['1440', '2880'],
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
          'Tab stops (pt, comma separated)': '72, 144',
        }.entries) {
          await tester.enterText(
            find.widgetWithText(TextField, entry.key),
            entry.value,
          );
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
        await _tapSettled(tester, find.text('Picture'));
        expect(picker.calls, 1);
        await _pumpUntil(
          tester,
          () => controller.document.visuals.length == 2,
          'The picked picture was not decoded and inserted into the document.',
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
