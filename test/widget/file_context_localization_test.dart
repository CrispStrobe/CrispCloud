import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/widgets/file_context_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('file properties use localized field labels', (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('es'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(body: Builder(builder: (context) => TextButton(
        onPressed: () => showPropertiesDialog(context,
            FileItem(name: 'report.txt', isFolder: false, size: 12, isSymlink: true, symlinkTarget: '/target')),
        child: const Text('Show'),
      ))),
    ));
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    expect(find.text('Archivo (TXT)'), findsOneWidget);
    expect(find.text('Tamaño'), findsOneWidget);
    expect(find.text('→ Destino'), findsOneWidget);
  });

  testWidgets('delete confirmation uses the selected language and count',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        locale: const Locale('es'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(body: Consumer(builder: (context, ref, _) {
          return TextButton(
            onPressed: () => confirmDelete(context, ref, PanelSide.local, [
              FileItem(name: 'a.txt', isFolder: false),
              FileItem(name: 'b.txt', isFolder: false),
            ]),
            child: const Text('Show'),
          );
        })),
      ),
    ));
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    expect(find.text('¿Seguro que quieres eliminar 2 elemento(s)?'), findsOneWidget);
    expect(find.text('Esta acción no se puede deshacer.'), findsOneWidget);
  });
}
