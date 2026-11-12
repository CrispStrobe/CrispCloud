import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' as archive;
import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/widgets/file_editor_dialog.dart';
import 'package:crisp_cloud/widgets/internal_viewer_dialog.dart';
import 'package:crisp_cloud/widgets/legacy_word_conversion_dialog.dart';
import 'package:crisp_cloud/widgets/office_editor_dialog.dart';
import 'package:crisp_cloud/widgets/office_editor_ribbon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:xml/xml.dart' as xml;

import '../../packages/quds_office_engine/test/support/legacy_word_fixture.dart';
import '../support/workspace_fixture.dart';

const _side = PanelSide.remote;

Future<void> _mount(
  WidgetTester tester,
  WorkspaceTestHarness harness,
  Widget Function(BuildContext, WidgetRef) build,
) async {
  await tester.binding.setSurfaceSize(const Size(1100, 850));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: harness.container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Consumer(
          builder: (context, ref, _) => Scaffold(body: build(context, ref)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  final elapsed = Stopwatch()..start();
  while (!ready()) {
    await tester.pump(const Duration(milliseconds: 20));
    await Future<void>.delayed(const Duration(milliseconds: 1));
    if (elapsed.elapsed > const Duration(seconds: 20)) {
      throw TimeoutException('The file workflow did not finish.');
    }
  }
}

void main() {
  testWidgets(
    'F3 offers conversion for a captured DOT and cancel keeps it intact',
    (tester) async {
      final harness = await WorkspaceTestHarness.create();
      addTearDown(harness.dispose);
      final original = legacyWordFixture('Template body\r');
      harness.cloud.put('/template.DOT', original);
      final panel = harness.container.read(panelProvider(_side));
      await panel.refresh();
      final file = panel.displayedFiles!.singleWhere(
        (file) => file.name == 'template.DOT',
      );
      await _mount(
        tester,
        harness,
        (context, _) => TextButton(
          onPressed: () => showInternalViewer(context, file: file, side: _side),
          child: const Text('F3'),
        ),
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('F3'));
        await _until(
          tester,
          () => find.byTooltip('Convert to DOCX').evaluate().isNotEmpty,
        );
      });
      await tester.tap(find.byTooltip('Convert to DOCX'));
      await tester.pumpAndSettle();
      expect(find.byType(LegacyWordConversionDialog), findsOneWidget);
      expect(find.text('template (text).docx'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(LegacyWordConversionDialog), findsNothing);
      expect(harness.cloud.writes, isEmpty);
      expect(harness.cloud.files['/template.DOT'], orderedEquals(original));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'a detached legacy attachment cannot create a source-bound copy',
    (tester) async {
      final harness = await WorkspaceTestHarness.create();
      addTearDown(harness.dispose);
      await _mount(
        tester,
        harness,
        (context, _) => TextButton(
          onPressed: () => showInternalViewer(
            context,
            file: FileItem(name: 'message.eml', isFolder: false),
            side: _side,
            displayName: 'attached.doc',
            bytesOverride: legacyWordFixture('Detached body\r'),
          ),
          child: const Text('F3'),
        ),
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('F3'));
        await _until(
          tester,
          () => find.textContaining('Detached body').evaluate().isNotEmpty,
        );
      });
      expect(find.byTooltip('Convert to DOCX'), findsNothing);
      expect(find.byType(LegacyWordConversionDialog), findsNothing);
      expect(harness.cloud.writes, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('F4 DOC creates a sibling and opens its captured rich editor', (
    tester,
  ) async {
    final harness = await WorkspaceTestHarness.create();
    addTearDown(harness.dispose);
    final original = legacyWordFixture('Body 世界\rSecond paragraph\r');
    harness.cloud.put('/one/legacy.doc', original);
    harness.cloud.directories.add('/other');
    final panel = harness.container.read(panelProvider(_side));
    await panel.navigateToPath('/one');
    final file = panel.displayedFiles!.singleWhere(
      (file) => file.name == 'legacy.doc',
    );
    await _mount(
      tester,
      harness,
      (context, ref) => TextButton(
        onPressed: () => showFileEditorDialog(context, ref, file, _side),
        child: const Text('F4'),
      ),
    );
    await tester.tap(find.text('F4'));
    await tester.pumpAndSettle();
    expect(find.byType(LegacyWordConversionDialog), findsOneWidget);
    expect(find.textContaining('Formatting, page layout'), findsOneWidget);
    // A pane navigation during the disclosure must not redirect the output.
    await panel.navigateToPath('/other');
    await tester.runAsync(() async {
      await tester.tap(find.text('Create text-only DOCX'));
      await _until(
        tester,
        () => find.byType(QudsWordEditor).evaluate().isNotEmpty,
      );
    });
    const output = '/one/legacy (text).docx';
    expect(harness.cloud.files['/one/legacy.doc'], orderedEquals(original));
    expect(harness.cloud.files.containsKey(output), isTrue);
    expect(
      harness.cloud.files.keys.where((p) => p.startsWith('/other/')),
      isEmpty,
    );
    final editor = tester.widget<OfficeEditorDialog>(
      find.byType(OfficeEditorDialog),
    );
    expect(editor.file.path, output);
    expect(editor.targetOverride!.reference.path, output);
    expect(editor.bytesOverride, isNull);
    expect(panel.currentPath, '/other');
    expect(find.textContaining('cannot be edited safely'), findsNothing);
    final controller =
        tester
                .widget<OfficeEditorRibbon>(find.byType(OfficeEditorRibbon))
                .controller
            as WordEditorController;
    controller.insertText('Edited copy ');
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Save'));
      await _until(tester, () => !controller.isDirty);
    });
    // Inspect the actual captured upload independently of the Quds reader.
    final saved = archive.ZipDecoder().decodeBytes(
      Uint8List.fromList(harness.cloud.files[output]!),
    );
    final body = xml.XmlDocument.parse(
      utf8.decode(saved.findFile('word/document.xml')!.content as List<int>),
    );
    const wordNs =
        'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
    final uploadedText = body
        .findAllElements('t', namespace: wordNs)
        .map((node) => node.innerText)
        .join();
    expect(uploadedText, contains('Edited copy Body 世界'));
    expect(uploadedText, contains('Second paragraph'));
    expect(harness.cloud.files['/one/legacy.doc'], orderedEquals(original));
    expect(
      harness.cloud.files.keys.where((path) => path.startsWith('/other/')),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
