import 'dart:typed_data';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/document_history.dart';
import 'package:crisp_cloud/widgets/new_document_dialog.dart';
import 'package:crisp_cloud/widgets/office_editor_ribbon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/office_test_harness.dart' show officePumpUntil;
import '../support/workflow_fake_client.dart';
import '../support/workspace_fixture.dart';

void main() {
  testWidgets(
    'File New creates a verified Word document and opens its matching editor',
    (tester) async {
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        final cloud = WorkflowFakeClient()
          ..put('/keep.txt', Uint8List.fromList([65]));
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith((_) => WorkspaceTestAuth(cloud)),
          ],
        );
        addTearDown(container.dispose);
        container.read(activePanelProvider.notifier).state = PanelSide.remote;
        await container.read(panelProvider(PanelSide.remote)).refresh();
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Consumer(
                builder: (context, ref, _) => Scaffold(
                  body: TextButton(
                    onPressed: () => showNewDocumentDialog(context, ref),
                    child: const Text('File New'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('File New'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('new-document-kind')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Word document (.docx)').last);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('new-document-name')),
          'Fresh.docx',
        );
        await tester.tap(find.byKey(const ValueKey('new-document-create')));
        await officePumpUntil(
          tester,
          () => find.byType(OfficeEditorRibbon).evaluate().isNotEmpty,
        );
        expect(cloud.files['/Fresh.docx'], isNotNull);
        expect(cloud.files['/keep.txt'], orderedEquals([65]));
        final history = container.read(documentHistoryProvider);
        await history.ready;
        expect(
          history.entries.any(
            (e) => e.file.path == '/Fresh.docx' && e.editedAt != null,
          ),
          isTrue,
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      });
    },
  );
}
