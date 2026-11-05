import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/panel_source_provider.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/widgets/panel_source_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('local source label follows selected locale', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ProviderScope(
      overrides: [availableSourcesProvider.overrideWithValue([
        const AvailableSource(key: 'local', label: 'Local', source: LocalPanelSource('/')),
      ])],
      child: const MaterialApp(
        locale: Locale('de'), supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(body: PanelSourceSelector(side: PanelSide.local)),
      ),
    ));
    await tester.pump();
    expect(find.text('Lokal'), findsOneWidget);
  });
}
