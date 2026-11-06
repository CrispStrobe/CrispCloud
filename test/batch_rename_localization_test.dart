import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/batch_rename_strings.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/l10n/commander_strings.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/widgets/batch_rename_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/workspace_fixture.dart';

void main() {
  testWidgets('German batch rename updates its preview', (tester) async {
    final harness = await WorkspaceTestHarness.create();
    addTearDown(harness.dispose);
    harness.cloud.put('/one.txt', [1]);
    harness.cloud.put('/two.txt', [2]);
    final panel = harness.container.read(panelProvider(PanelSide.remote));
    await panel.refresh();
    final files = panel.files!.where((file) => !file.isFolder).toList();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp(
          locale: const Locale('de'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => BatchRenameDialog(
                parentRef: ref,
                side: PanelSide.remote,
                files: files,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        CommanderStrings.forLanguage('de', 'Multi-rename ({0} items)', [2]),
      ),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(const ValueKey('rename-find')), 'one');
    await tester.enterText(find.byKey(const ValueKey('rename-replace')), 'new');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('rename-preview')));
    await tester.pumpAndSettle();
    expect(find.text('→ new.txt'), findsOneWidget);
    expect(harness.cloud.writes, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('file counts interpolate in all locales', (tester) async {
    for (final locale in AppLocalizations.supportedLocales) {
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Builder(
            builder: (context) =>
                Text(BatchRenameStrings(context).text('title', {'count': 42})),
          ),
        ),
      );
      expect(find.textContaining('42'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
