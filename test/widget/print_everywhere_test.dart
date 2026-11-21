import 'dart:typed_data';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/browser_menu_layout.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/document_printing.dart';
import 'package:crisp_cloud/services/file_list_printing.dart';
import 'package:crisp_cloud/services/gallery_media_service.dart';
import 'package:crisp_cloud/services/office_editor_menu.dart';
import 'package:crisp_cloud/widgets/diff_viewer_dialog.dart';
import 'package:crisp_cloud/widgets/document_print_scope.dart';
import 'package:crisp_cloud/widgets/gallery_viewer_dialog.dart';
import 'package:crisp_cloud/widgets/office_editor_ribbon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:pdf_document/pdf_document.dart' as pdf;
import 'package:quds_office_editor/quds_office_editor.dart';

Widget _app(Widget home) => ProviderScope(
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  ),
);

/// Captures what would have gone to the platform print dialog.
List<(Uint8List, String)> _capturePrints() {
  final printed = <(Uint8List, String)>[];
  debugPrintPdfOverride = (bytes, title) async => printed.add((bytes, title));
  addTearDown(() => debugPrintPdfOverride = null);
  return printed;
}

void _expectPdf(Uint8List bytes) {
  expect(bytes, isNotEmpty);
  expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  expect(pdf.PdfDocument.open(bytes).pageCount, greaterThan(0));
}

void main() {
  testWidgets('toolbar Print button shares the guarded print action', (
    tester,
  ) async {
    var calls = 0;
    final enabled = ValueNotifier(true);
    addTearDown(enabled.dispose);
    await tester.pumpWidget(
      _app(
        ValueListenableBuilder<bool>(
          valueListenable: enabled,
          builder: (_, on, _) => DocumentPrintScope(
            enabled: on,
            onPrint: () async => calls++,
            child: Scaffold(
              appBar: AppBar(
                actions: const [DocumentPrintMenu(), DocumentPrintButton()],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Print…'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('document-print-button')));
    await tester.pumpAndSettle();
    expect(calls, 1);
    enabled.value = false;
    await tester.pumpAndSettle();
    final button = tester.widget<IconButton>(
      find.byKey(const ValueKey('document-print-button')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('Office ribbon shows a Print button beside Save', (tester) async {
    tester.view.physicalSize = const Size(1700, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const config = OfficeSurfaceConfig(
      mode: OfficeInteractionMode.editing,
      autofocus: false,
      adaptiveChrome: false,
    );
    final controller = WordEditorController(
      document: WmlDocument.empty(text: 'Body'),
      config: config,
    );
    controller.proofing.enabled = false;
    addTearDown(controller.dispose);
    var printed = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: OfficeEditorRibbon(
            controller: controller,
            kind: OfficeEditorKind.word,
            config: config,
            onSave: () {},
            onClose: () {},
            onPrint: () => printed++,
            onConfigChanged: (_) {},
            onFind: controller.requestFind,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('office-ribbon-print')));
    await tester.pump();
    expect(printed, 1);
  });

  testWidgets('gallery viewer prints the current image as a PDF', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final printed = _capturePrints();
    final pixels = image.Image(width: 40, height: 20);
    image.fill(pixels, color: image.ColorRgba8(200, 30, 30, 255));
    final data = GalleryImageData(
      bytes: Uint8List.fromList(image.encodePng(pixels)),
      width: 40,
      height: 20,
    );
    await tester.pumpWidget(
      _app(
        GalleryViewerDialog(
          files: [FileItem(name: 'red.png', path: '/red.png', isFolder: false)],
          imageLoader: (_) async => data,
          thumbnailLoader: (_) async => null,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('document-print-button')));
    await tester.pump();
    await tester.pump();
    expect(printed, hasLength(1));
    expect(printed.single.$2, 'red.png');
    _expectPdf(printed.single.$1);
  });

  testWidgets('version diff prints a unified text layout', (tester) async {
    final printed = _capturePrints();
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDiffViewerFromContent(
                context,
                leftContent: 'same\nold',
                rightContent: 'same\nnew',
                leftLabel: 'v1',
                rightLabel: 'v2',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('document-print-button')));
      for (var i = 0; i < 1200 && printed.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });
    expect(printed, hasLength(1));
    expect(printed.single.$2, 'v1 ↔ v2');
    _expectPdf(printed.single.$1);
  });

  test('diff print text marks removed and added lines', () {
    final text = diffPrintText(
      const [
        DiffLine(type: DiffType.equal, leftLine: 1, rightLine: 1, text: 'a'),
        DiffLine(type: DiffType.removed, leftLine: 2, text: 'b'),
        DiffLine(type: DiffType.added, rightLine: 2, text: 'c'),
      ],
      'left',
      'right',
    );
    expect(text, '--- left\n+++ right\n  a\n- b\n+ c\n');
  });

  test('file list print text keeps every name and aligns columns', () {
    final long = '${'x' * 60}.txt';
    final text = fileListPrintText(
      '/docs',
      [
        FileItem(name: 'sub', isFolder: true),
        FileItem(
          name: 'a.txt',
          isFolder: false,
          size: 2048,
          updatedAt: DateTime(2026, 11, 21, 9, 5),
        ),
        FileItem(name: long, isFolder: false, size: 1),
      ],
      (name: 'Name', size: 'Size', modified: 'Modified'),
    );
    final lines = text.split('\n');
    expect(lines.first, '/docs');
    expect(text, contains('sub/'));
    expect(text, contains('<DIR>'));
    expect(text, contains('2.0 KB  2026-11-21 09:05'));
    expect(lines, contains(long));
  });

  test('saved browser menus gain Print file list after Properties once', () {
    final layout = BrowserMenuLayout([
      BrowserMenuNode(
        id: 'file',
        kind: BrowserMenuNodeKind.submenu,
        labelKey: 'file',
        children: [
          BrowserMenuNode(
            id: 'p',
            kind: BrowserMenuNodeKind.command,
            commandId: 'workflow:properties',
          ),
          BrowserMenuNode(
            id: 'c',
            kind: BrowserMenuNodeKind.command,
            commandId: 'action:connect',
          ),
        ],
      ),
    ]);
    final upgraded = layout.withPrintFileListCommand();
    expect(upgraded.menus.single.children.map((e) => e.commandId), [
      'workflow:properties',
      'workflow:printFileList',
      'action:connect',
    ]);
    expect(identical(upgraded.withPrintFileListCommand(), upgraded), isTrue);
    expect(
      BrowserMenuLayout.defaults().nodes.map((e) => e.commandId),
      contains('workflow:printFileList'),
    );
  });
}
