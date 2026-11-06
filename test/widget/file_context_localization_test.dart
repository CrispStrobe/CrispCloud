import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/widgets/file_context_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/workspace_fixture.dart';

void main() {
  testWidgets('file properties use localized field labels', (tester) async {
    final harness = await WorkspaceTestHarness.create();
    addTearDown(harness.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp(
          locale: const Locale('es'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showPropertiesDialog(
                  context,
                  FileItem(
                    name: 'report.txt',
                    isFolder: false,
                    size: 12,
                    isSymlink: true,
                    symlinkTarget: '/target',
                  ),
                ),
                child: const Text('Show'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    expect(find.text('Archivo (TXT)'), findsOneWidget);
    expect(find.text('Tamaño'), findsOneWidget);
    expect(find.text('→ Destino'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('delete confirmation uses the selected language and count', (
    tester,
  ) async {
    final harness = await WorkspaceTestHarness.create();
    addTearDown(harness.dispose);
    harness.cloud.put('/a.txt', [1]);
    harness.cloud.put('/b.txt', [2]);
    final panel = harness.container.read(panelProvider(PanelSide.remote));
    await panel.refresh();
    final files = panel.files!.where((file) => !file.isFolder).toList();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp(
          locale: const Locale('es'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                return TextButton(
                  onPressed: () =>
                      confirmDelete(context, ref, PanelSide.remote, files),
                  child: const Text('Show'),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    expect(find.text('2 elemento(s) seleccionado(s)'), findsOneWidget);
    expect(find.text('Eliminar sin restauración'), findsOneWidget);
    expect(
      find.textContaining('CrispCloud no puede restaurar esta eliminación.'),
      findsOneWidget,
    );
    expect(harness.cloud.files.keys, containsAll(['/a.txt', '/b.txt']));
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(harness.cloud.files.keys, containsAll(['/a.txt', '/b.txt']));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
