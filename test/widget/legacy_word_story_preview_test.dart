import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/office_document_service.dart';
import 'package:crisp_cloud/widgets/hex_viewer.dart';
import 'package:crisp_cloud/widgets/internal_viewer_dialog.dart';
import 'package:crisp_cloud/widgets/internal_viewer_views.dart';
import 'package:crisp_cloud/widgets/preview_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import '../../packages/legacy_doc_parser/test/support/story_word_fixture.dart';
import '../../packages/legacy_doc_parser/test/support/structured_word_fixture.dart';
import '../support/workspace_fixture.dart';

Uint8List _notes() {
  const main = 'Body\x02\r', note = '\x02Auxiliary needle <tag>\r';
  return storyWordFixture(
    main: main,
    footnotes: '$note\r',
    tablePairs: {
      2: storyPlc([main.indexOf('\x02'), 0xffffffff], wordU16(1)),
      3: storyPlc([0, note.length, 0xffffffff]),
    },
  );
}

Widget _app(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
  locale: locale,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  home: Scaffold(body: child),
);

Future<void> _open(
  WidgetTester tester,
  Uint8List bytes, {
  String name = 'notes.doc',
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      child: _app(
        InternalViewerDialog(
          file: FileItem(name: name, isFolder: false, size: bytes.length),
          side: PanelSide.local,
          bytesOverride: bytes,
        ),
        locale: locale,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'F3 formatted, search and Copy all share the complete DOC projection',
    (tester) async {
      final bytes = _notes();
      await _open(tester, bytes);
      final html = tester.widget<HtmlWidget>(find.byType(HtmlWidget)).html;
      expect(html, contains('<h2>Footnote 1</h2>'));
      expect(html, contains('Auxiliary needle &lt;tag&gt;'));
      expect(
        find.textContaining('without their original page positions'),
        findsOneWidget,
      );
      String? copied;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy all text'));
      await tester.pumpAndSettle();
      expect(copied, (await parseOfficeDocument(bytes, 'notes.doc')).plainText);
      expect(copied, contains('Footnote 1\nAuxiliary needle <tag>'));
      await tester.tap(find.byTooltip('Search (Ctrl+F)'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('viewer-search-input')),
        'needle',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('1/1'), findsOneWidget);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Office'))
            .selected,
        isTrue,
      );
      final lines = tester.widget<MonoLineListView>(
        find.byType(MonoLineListView),
      );
      expect(
        lines.lines.join('\n'),
        contains('Footnote 1\nAuxiliary needle <tag>'),
      );
      expect(lines.activeMatchLine, isNotNull);
      expect(
        find.textContaining('Searched extracted document text'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(ChoiceChip, 'Hex'));
      await tester.pumpAndSettle();
      final hex = tester.widget<HexViewer>(find.byType(HexViewer));
      expect(hex.source.readSync(0, bytes.length), orderedEquals(bytes));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Office'));
      await tester.pumpAndSettle();
      expect(find.text('1/1'), findsOneWidget);
      expect(
        tester
            .widget<MonoLineListView>(find.byType(MonoLineListView))
            .lines
            .join('\n'),
        contains('Auxiliary needle <tag>'),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('DOT auxiliary headings localize in the real F3 formatted view', (
    tester,
  ) async {
    await _open(
      tester,
      _notes(),
      name: 'notes.dot',
      locale: const Locale('de'),
    );
    final html = tester.widget<HtmlWidget>(find.byType(HtmlWidget)).html;
    expect(html, contains('<h2>Fußnote 1</h2>'));
    expect(html, contains('Auxiliary needle &lt;tag&gt;'));
    expect(find.textContaining('Seitenpositionen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final pane in [false, true]) {
    testWidgets(
      '${pane ? 'Side preview' : 'F3'} displays native textbox-only document',
      (tester) async {
        final bytes = File(
          'packages/legacy_doc_parser/test/fixtures/word_native/word14-margin-origin.doc',
        ).readAsBytesSync();
        final parsed = parseLegacyWordDocument(bytes);
        expect(
          parsed.stories.where(
            (item) => item.kind == LegacyWordStoryKind.textbox,
          ),
          hasLength(6),
        );
        if (pane) {
          final harness = await WorkspaceTestHarness.create();
          addTearDown(harness.dispose);
          harness.cloud.put('/textboxes.doc', bytes);
          final panel = harness.container.read(panelProvider(PanelSide.remote));
          await panel.refresh();
          final file = panel.files!.singleWhere(
            (item) => item.name == 'textboxes.doc',
          );
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: harness.container,
              child: _app(PreviewPane(file: file, side: PanelSide.remote)),
            ),
          );
          await tester.pumpAndSettle();
        } else {
          await _open(tester, bytes, name: 'textboxes.doc');
        }
        final html = tester.widget<HtmlWidget>(find.byType(HtmlWidget)).html;
        expect(html, contains('<h2>Text box 6</h2>'));
        for (final story in parsed.stories) {
          expect(html, contains(story.safeHtml));
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}
