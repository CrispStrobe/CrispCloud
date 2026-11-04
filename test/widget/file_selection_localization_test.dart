import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/filen_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/widgets/file_selection_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('selection bar labels follow the selected language', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = InMemorySecureStorage();
    final config = FilenConfigService(
        configPath: Directory.systemTemp.path, secureStorage: storage);
    await tester.pumpWidget(ProviderScope(
      overrides: [authProvider.overrideWith((ref) => AuthNotifier(ref,
          initialProvider: CloudProvider.filen, config: config,
          configPath: Directory.systemTemp.path, secureStorage: storage))],
      child: MaterialApp(
        locale: const Locale('es'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(body: FileSelectionBar(
          side: PanelSide.local,
          selection: {FileItem(name: 'report.txt', path: '/report.txt', isFolder: false)},
        )),
      ),
    ));
    expect(find.text('1 seleccionado(s)'), findsOneWidget);
    expect(find.byTooltip('Copiar a...'), findsOneWidget);
    expect(find.byTooltip('Eliminar'), findsOneWidget);
  });
}
