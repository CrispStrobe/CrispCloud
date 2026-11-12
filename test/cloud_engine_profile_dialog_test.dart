import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/connection_dialog_extra_strings.dart';
import 'package:crisp_cloud/providers/auth_provider.dart';
import 'package:crisp_cloud/providers/core_providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/connection_profiles.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/widgets/cloud_engine_field.dart';
import 'package:crisp_cloud/widgets/connection_dialog.dart';
import 'package:crisp_storage/rust_cloud.dart' show CloudEngine;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _profiles = [
  ConnectionProfile(
    name: 'Filen Rust',
    provider: 'filen',
    fields: {'email': 'rust@example.com', 'engine': 'rust'},
  ),
  ConnectionProfile(
    name: 'Filen Auto',
    provider: 'filen',
    fields: {'email': 'auto@example.com', 'engine': 'auto'},
  ),
  ConnectionProfile(
    name: 'Filen Legacy',
    provider: 'filen',
    fields: {'email': 'legacy@example.com'},
  ),
  ConnectionProfile(
    name: 'Filen Broken',
    provider: 'filen',
    fields: {'email': 'broken@example.com', 'engine': 'quantum'},
  ),
  ConnectionProfile(
    name: 'Internxt Rust',
    provider: 'internxt',
    fields: {'email': 'tests@example.com', 'engine': 'rust'},
  ),
];

Future<void> _open(WidgetTester tester, CloudProvider provider) async {
  await tester.binding.setSurfaceSize(const Size(1000, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final storage = InMemorySecureStorage();
  final profiles = ConnectionProfileService(storage);
  for (final profile in _profiles) {
    await profiles.save(profile);
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(storage),
        authProvider.overrideWith(
          (ref) => throw StateError('Loading profiles must not authenticate'),
        ),
      ],
      child: MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const ConnectionDialog(),
              ),
              child: const Text('Open connection'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open connection'));
  await tester.pumpAndSettle();
  tester
      .widget<DropdownButtonFormField<CloudProvider>>(
        find.byType(DropdownButtonFormField<CloudProvider>),
      )
      .onChanged!(provider);
  await tester.pumpAndSettle();
}

Future<void> _load(WidgetTester tester, String name) async {
  final dropdown = find.byType(DropdownButtonFormField<String>);
  await tester.ensureVisible(dropdown);
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

CloudEngine _engine(WidgetTester tester) =>
    tester.widget<CloudEngineField>(find.byType(CloudEngineField)).value;

String _email(WidgetTester tester) {
  final field = tester.widget<TextField>(
    find.byWidgetPredicate(
      (w) =>
          w is TextField &&
          w.decoration?.prefixIcon is Icon &&
          (w.decoration!.prefixIcon as Icon).icon == Icons.email_outlined,
    ),
  );
  return field.controller!.text;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Filen shows the engine selector with the build default', (
    tester,
  ) async {
    await _open(tester, CloudProvider.filen);
    expect(find.byType(CloudEngineField), findsOneWidget);
    expect(_engine(tester), CloudEngine.dart);
  });

  testWidgets('profiles restore their saved engine and e-mail', (
    tester,
  ) async {
    await _open(tester, CloudProvider.filen);
    await _load(tester, 'Filen Rust');
    expect(_engine(tester), CloudEngine.rust);
    expect(_email(tester), 'rust@example.com');
    await _load(tester, 'Filen Auto');
    expect(_engine(tester), CloudEngine.auto);
    await _load(tester, 'Filen Legacy');
    expect(_engine(tester), CloudEngine.dart);
    expect(_email(tester), 'legacy@example.com');
  });

  testWidgets('an invalid engine is reported and changes nothing', (
    tester,
  ) async {
    await _open(tester, CloudProvider.filen);
    await _load(tester, 'Filen Rust');
    await _load(tester, 'Filen Broken');
    expect(_engine(tester), CloudEngine.rust);
    expect(_email(tester), 'rust@example.com');
    final strings = ConnectionDialogExtraStrings(
      tester.element(find.byType(ConnectionDialog)),
    );
    expect(find.text(strings.text('invalidCloudEngineProfile')), findsOneWidget);
  });

  testWidgets('Internxt profiles carry the engine too', (tester) async {
    await _open(tester, CloudProvider.internxt);
    expect(find.byType(CloudEngineField), findsOneWidget);
    await _load(tester, 'Internxt Rust');
    expect(_engine(tester), CloudEngine.rust);
  });

  testWidgets('other providers do not show the engine selector', (
    tester,
  ) async {
    await _open(tester, CloudProvider.webdav);
    expect(find.byType(CloudEngineField), findsNothing);
  });
}
