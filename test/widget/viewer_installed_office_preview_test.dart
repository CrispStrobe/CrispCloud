import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/office_conversion_provider.dart';
import 'package:crisp_cloud/services/installed_office_converter.dart';
import 'package:crisp_cloud/widgets/installed_office_preview_dialog.dart';
import 'package:crisp_cloud/widgets/internal_viewer_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/workspace_fixture.dart';

Uint8List _document() {
  final parts = <String, String>{
    '[Content_Types].xml':
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '</Types>',
    '_rels/.rels':
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
        '</Relationships>',
    'word/document.xml':
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:body><w:p><w:r><w:t>Preview integration document</w:t></w:r></w:p></w:body>'
        '</w:document>',
  };
  final archive = Archive();
  for (final entry in parts.entries) {
    archive.addFile(ArchiveFile.bytes(entry.key, utf8.encode(entry.value)));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  final elapsed = Stopwatch()..start();
  while (!ready()) {
    await tester.pump(const Duration(milliseconds: 20));
    await Future<void>.delayed(const Duration(milliseconds: 1));
    if (elapsed.elapsed > const Duration(seconds: 20)) {
      throw TimeoutException('The document preview did not become ready.');
    }
  }
}

void main() {
  testWidgets(
    'F3 exposes installed preview without converting or saving during discovery',
    (tester) async {
      final discovered = Completer<List<InstalledOfficeInstallation>>();
      var discoveries = 0;
      var conversions = 0;
      final harness = await WorkspaceTestHarness.create(
        extraOverrides: [
          installedOfficeDiscoveryProvider.overrideWithValue(() {
            discoveries++;
            return discovered.future;
          }),
          installedOfficeConversionProvider.overrideWithValue(({
            required bytes,
            required sourceName,
            required installation,
            output = InstalledOfficeOutput.docx,
          }) async {
            conversions++;
            throw StateError(
              'Conversion must require a separate explicit action.',
            );
          }),
        ],
      );
      addTearDown(harness.dispose);
      final bytes = _document();
      final original = Uint8List.fromList(bytes);
      harness.cloud.put('/report.docx', original);
      final pathsBefore = harness.cloud.files.keys.toSet();
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: harness.container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showInternalViewer(
                    context,
                    file: FileItem(
                      name: 'report.docx',
                      isFolder: false,
                      size: bytes.length,
                    ),
                    side: PanelSide.remote,
                    bytesOverride: bytes,
                  ),
                  child: const Text('Open F3'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open F3'));
      await tester.runAsync(
        () => _until(
          tester,
          () => find
              .textContaining(
                'Preview integration document',
                findRichText: true,
              )
              .evaluate()
              .isNotEmpty,
        ),
      );
      await tester.pumpAndSettle();
      final action = find.byKey(
        const ValueKey('viewer-installed-office-preview'),
      );
      expect(action, findsOneWidget);
      expect(discoveries, 0);
      expect(conversions, 0);
      expect(harness.cloud.downloads, isEmpty);
      expect(harness.cloud.writes, isEmpty);

      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(InstalledOfficePreviewDialog), findsOneWidget);
      expect(discoveries, 1);
      expect(conversions, 0);
      expect(find.text('Checking installed applications…'), findsOneWidget);
      discovered.complete(const [
        InstalledOfficeInstallation(
          kind: InstalledOfficeKind.libreOffice,
          displayName: 'LibreOffice fixture',
          executablePath: '/not-executed/libreoffice',
        ),
      ]);
      await tester.pumpAndSettle();
      final dialog = tester.widget<InstalledOfficePreviewDialog>(
        find.byType(InstalledOfficePreviewDialog),
      );
      expect(dialog.sourceName, 'report.docx');
      expect(dialog.bytes, orderedEquals(original));
      expect(find.text('LibreOffice fixture (installed)'), findsOneWidget);
      expect(conversions, 0);
      expect(harness.cloud.writes, isEmpty);
      expect(harness.cloud.downloads, isEmpty);
      expect(harness.cloud.files.keys.toSet(), pathsBefore);
      expect(harness.cloud.files['/report.docx'], orderedEquals(original));
      expect(bytes, orderedEquals(original));
      await tester.tap(find.byKey(const ValueKey('installed-preview-close')));
      await tester.pumpAndSettle();
      expect(find.byType(InstalledOfficePreviewDialog), findsNothing);
      expect(find.byType(InternalViewerDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}
