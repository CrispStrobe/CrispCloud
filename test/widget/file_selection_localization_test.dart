import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/widgets/file_selection_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/workspace_fixture.dart';

void main() {
  testWidgets('selection bar labels follow the selected language', (
    tester,
  ) async {
    final harness = await WorkspaceTestHarness.create();
    addTearDown(harness.dispose);
    harness.cloud.put('/report.txt', [1, 2]);
    final panel = harness.container.read(panelProvider(PanelSide.remote));
    await panel.refresh();
    final file = panel.files!.singleWhere((file) => file.name == 'report.txt');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp(
          locale: const Locale('es'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: FileSelectionBar(side: PanelSide.remote, selection: {file}),
          ),
        ),
      ),
    );
    expect(find.text('1 seleccionado(s)'), findsOneWidget);
    expect(find.byTooltip('Copiar a...'), findsOneWidget);
    expect(find.byTooltip('Eliminar'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
