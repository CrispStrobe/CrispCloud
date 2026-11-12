import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/connection_dialog_extra_strings.dart';
import 'package:crisp_cloud/widgets/cloud_engine_field.dart';
import 'package:crisp_storage/rust_cloud.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('offers Dart, Rust and Auto and reports the choice', (
    tester,
  ) async {
    var selected = CloudEngine.dart;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => CloudEngineField(
              value: selected,
              onChanged: (v) => setState(() => selected = v),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Dart (default)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('cloud-engine')));
    await tester.pumpAndSettle();
    expect(find.text('Auto'), findsWidgets);
    await tester.tap(find.text('Rust (experimental)').last);
    await tester.pumpAndSettle();
    expect(selected, CloudEngine.rust);
    await tester.tap(find.byKey(const Key('cloud-engine')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Auto').last);
    await tester.pumpAndSettle();
    expect(selected, CloudEngine.auto);
  });

  testWidgets('is read-only while connecting', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CloudEngineField(value: CloudEngine.auto)),
      ),
    );
    final field = tester.widget<DropdownButtonFormField<CloudEngine>>(
      find.byKey(const Key('cloud-engine')),
    );
    expect(field.onChanged, isNull);
  });

  testWidgets('uses the active locale', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const Scaffold(body: CloudEngineField(value: CloudEngine.dart)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Speicher-Engine'), findsOneWidget);
  });

  test('engine labels, help and errors exist in every locale', () {
    final translations = ConnectionDialogExtraStrings.translations;
    expect(translations.keys.toSet(), {
      'en',
      'de',
      'fr',
      'es',
      'pt',
      'zh',
      'ja',
      'ko',
      'ar',
    });
    for (final entry in translations.entries) {
      for (final key in [
        'cloudEngine',
        'cloudEngine_dart',
        'cloudEngine_rust',
        'cloudEngine_auto',
        'cloudEngineHelp',
        'invalidCloudEngineProfile',
        'rustEngineUnavailable',
      ]) {
        expect(entry.value[key], isNotEmpty, reason: '${entry.key}.$key');
      }
    }
    final english = translations['en']!.keys.toSet();
    for (final entry in translations.entries) {
      expect(entry.value.keys.toSet(), english, reason: entry.key);
    }
  });
}
