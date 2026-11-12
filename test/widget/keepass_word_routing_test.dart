import 'dart:async';
import 'dart:typed_data';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/providers/office_conversion_provider.dart';
import 'package:crisp_cloud/services/installed_office_converter.dart';
import 'package:crisp_cloud/services/legacy_word_conversion.dart';
import 'package:crisp_cloud/widgets/file_editor_dialog.dart';
import 'package:crisp_cloud/widgets/internal_viewer_dialog.dart';
import 'package:crisp_cloud/widgets/keepass_editor_dialog.dart';
import 'package:crisp_cloud/widgets/legacy_word_conversion_dialog.dart';
import 'package:crisp_cloud/widgets/office_editor_dialog.dart';
import 'package:crisp_cloud/widgets/preview_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

import '../support/legacy_word_fixture.dart';
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
  testWidgets('KeePass preview stays locked without downloading the vault', (
    tester,
  ) async {
    final harness = await WorkspaceTestHarness.create();
    addTearDown(harness.dispose);
    harness.cloud.put('/vault.kdbx', [1, 2, 3]);
    final panel = harness.container.read(panelProvider(_side));
    await panel.refresh();
    final file = panel.displayedFiles!.singleWhere(
      (file) => file.name == 'vault.kdbx',
    );
    await _mount(
      tester,
      harness,
      (_, _) => PreviewPane(file: file, side: _side),
    );
    expect(harness.cloud.downloads, isEmpty);
    expect(find.text('KeePass database locked'), findsOneWidget);
    expect(find.byType(KeePassEditorDialog), findsNothing);

    await tester.tap(find.byKey(const ValueKey('preview-open-keepass')));
    await tester.pumpAndSettle();
    final dialog = tester.widget<KeePassEditorDialog>(
      find.byType(KeePassEditorDialog),
    );
    expect(dialog.readOnly, isTrue);
    expect(harness.cloud.downloads, ['/vault.kdbx']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'F3 routes detached KDBX attachments to the read-only unlock UI',
    (tester) async {
      final harness = await WorkspaceTestHarness.create();
      addTearDown(harness.dispose);
      final attached = Uint8List.fromList([1, 2, 3]);
      await _mount(
        tester,
        harness,
        (context, _) => TextButton(
          onPressed: () => showInternalViewer(
            context,
            file: FileItem(name: 'message.eml', isFolder: false),
            side: _side,
            displayName: 'attachment.kdbx',
            bytesOverride: attached,
          ),
          child: const Text('F3'),
        ),
      );
      await tester.tap(find.text('F3'));
      await tester.pumpAndSettle();
      final dialog = tester.widget<KeePassEditorDialog>(
        find.byType(KeePassEditorDialog),
      );
      expect(dialog.file.name, 'attachment.kdbx');
      expect(dialog.bytesOverride, same(attached));
      expect(dialog.readOnly, isTrue);
      expect(dialog.targetOverride, isNull);
      expect(find.byType(InternalViewerDialog), findsNothing);
      expect(harness.cloud.downloads, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final edit in [false, true]) {
    testWidgets('${edit ? 'F4' : 'F3'} opens the correct KeePass mode', (
      tester,
    ) async {
      final harness = await WorkspaceTestHarness.create();
      addTearDown(harness.dispose);
      harness.cloud.put('/vault.kdbx', [1, 2, 3]);
      final panel = harness.container.read(panelProvider(_side));
      await panel.refresh();
      final file = panel.displayedFiles!.singleWhere(
        (file) => file.name == 'vault.kdbx',
      );
      await _mount(
        tester,
        harness,
        (context, ref) => TextButton(
          onPressed: () {
            if (edit) {
              unawaited(showFileEditorDialog(context, ref, file, _side));
            } else {
              unawaited(showInternalViewer(context, file: file, side: _side));
            }
          },
          child: const Text('Open'),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final dialog = tester.widget<KeePassEditorDialog>(
        find.byType(KeePassEditorDialog),
      );
      expect(dialog.readOnly, !edit);
      expect(
        find.byKey(const ValueKey('keepass-master-password')),
        findsOneWidget,
      );
      expect(harness.cloud.downloads, ['/vault.kdbx']);
      expect(find.byType(InternalViewerDialog), findsNothing);
      expect(tester.takeException(), isNull);
      // Complete the editor Future while its WidgetRef is still mounted.
      await tester.tap(find.byKey(const ValueKey('keepass-close')));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('F4 DOC creates a sibling and opens its captured rich editor', (
    tester,
  ) async {
    final harness = await WorkspaceTestHarness.create(
      extraOverrides: [
        installedOfficeDiscoveryProvider.overrideWithValue(() async => []),
      ],
    );
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
    await tester.runAsync(
      () => _until(
        tester,
        () => find
            .byKey(const ValueKey('word-conversion-method'))
            .evaluate()
            .isNotEmpty,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('word-conversion-method')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Text only (built in)').last);
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
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
    'installed conversion saves exact bytes beside source and initially opens F3',
    (tester) async {
      final original = legacyWordFixture('Original Word body\r');
      final converted = convertLegacyWordToDocx(
        legacyWordFixture('Converted body\r'),
      );
      const installation = InstalledOfficeInstallation(
        kind: InstalledOfficeKind.libreOffice,
        displayName: 'LibreOffice',
        executablePath: '/fake/soffice',
      );
      var calls = 0;
      final harness = await WorkspaceTestHarness.create(
        extraOverrides: [
          installedOfficeDiscoveryProvider.overrideWithValue(
            () async => [installation],
          ),
          installedOfficeConversionProvider.overrideWithValue(({
            required bytes,
            required sourceName,
            required installation,
            output = InstalledOfficeOutput.docx,
          }) async {
            calls++;
            expect(bytes, orderedEquals(original));
            return InstalledOfficeConversionResult(
              bytes: converted,
              installation: installation,
              output: output,
              elapsed: Duration.zero,
            );
          }),
        ],
      );
      addTearDown(harness.dispose);
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
      await tester.runAsync(
        () => _until(
          tester,
          () => find
              .byKey(const ValueKey('word-conversion-method'))
              .evaluate()
              .isNotEmpty,
        ),
      );
      await panel.navigateToPath('/other');
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('word-conversion-primary')));
        await _until(
          tester,
          () => find.text('Review converted copy').evaluate().isNotEmpty,
        );
      });
      expect(harness.cloud.writes, isEmpty);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('word-conversion-primary')));
        await _until(
          tester,
          () => find.byType(InternalViewerDialog).evaluate().isNotEmpty,
        );
      });
      const output = '/one/legacy (converted).docx';
      expect(calls, 1);
      expect(harness.cloud.files[output], orderedEquals(converted));
      expect(harness.cloud.files['/one/legacy.doc'], orderedEquals(original));
      expect(
        harness.cloud.files.keys.where((p) => p.startsWith('/other/')),
        isEmpty,
      );
      final viewer = tester.widget<InternalViewerDialog>(
        find.byType(InternalViewerDialog),
      );
      expect(viewer.file.path, output);
      expect(viewer.origin, isNotNull);
      expect(find.byType(OfficeEditorDialog), findsNothing);
      expect(panel.currentPath, '/other');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
