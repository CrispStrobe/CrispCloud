import 'dart:typed_data';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/widgets/internal_viewer_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('viewer actions follow the selected locale', (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: InternalViewerDialog(
          file: FileItem(name: 'test.txt', isFolder: false),
          side: PanelSide.local,
          bytesOverride: Uint8List.fromList([65, 66]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Suchen (Strg+F)'), findsOneWidget);
    expect(find.byTooltip('Schließen (Esc)'), findsOneWidget);
    await tester.tap(find.byTooltip('Suchen (Strg+F)'));
    await tester.pumpAndSettle();
    expect(find.text('Text oder 0x…-Bytes suchen'), findsOneWidget);
    await tester.tap(find.byTooltip('Suche schließen (Esc)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Mehr'));
    await tester.pumpAndSettle();
    expect(find.text('Vergrößern'), findsOneWidget);
    expect(find.text('Hex: 8 Bytes pro Zeile'), findsOneWidget);
    expect(find.text('Gesamten Text kopieren'), findsOneWidget);
    await tester.tap(find.text('Zu Zeile / Position…'));
    await tester.pumpAndSettle();
    expect(find.text('Zu Zeile'), findsOneWidget);
    expect(find.text('Zeilennummer'), findsOneWidget);
    expect(find.text('Abbrechen'), findsOneWidget);
  });
}
