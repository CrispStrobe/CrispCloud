import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/connection_dialog_extra_strings.dart';
import 'package:crisp_cloud/providers/auth_provider.dart';
import 'package:crisp_cloud/providers/core_providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/connection_profiles.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/widgets/connection_dialog.dart';
import 'package:crisp_cloud/widgets/smb_backend_field.dart';
import 'package:crisp_storage/crisp_storage.dart' show SmbBackend;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _profiles = [
  ConnectionProfile(
    name: 'Rust profile',
    provider: 'smb',
    fields: {
      'host': 'smb://first.example/First/',
      'user': 'first-user',
      'requireEncryption': 'false',
      'smbBackend': 'rust',
    },
  ),
  ConnectionProfile(
    name: 'Invalid profile',
    provider: 'smb',
    fields: {
      'host': 'smb://invalid.example/Invalid/',
      'user': 'invalid-user',
      'requireEncryption': 'true',
      'smbBackend': 'unknown-transport',
    },
  ),
  ConnectionProfile(
    name: 'Compatible profile',
    provider: 'smb',
    fields: {
      'host': 'smb://second.example/Second/',
      'user': 'second-user',
      'requireEncryption': 'true',
      'smbBackend': 'libsmb2',
    },
  ),
  ConnectionProfile(
    name: 'Legacy profile',
    provider: 'smb',
    fields: {'host': 'smb://legacy.example/Legacy/', 'user': 'legacy-user'},
  ),
];

Future<void> _openConnection(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
  VoidCallback? onAuthRead,
}) async {
  await tester.binding.setSurfaceSize(const Size(1000, 1200));
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
        authProvider.overrideWith((ref) {
          onAuthRead?.call();
          throw StateError('Invalid profile must not start authentication');
        }),
      ],
      child: MaterialApp(
        locale: locale,
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
  await _selectProvider(tester, CloudProvider.smb);
}

Future<void> _selectProvider(
  WidgetTester tester,
  CloudProvider provider,
) async {
  tester
      .widget<DropdownButtonFormField<CloudProvider>>(
        find.byType(DropdownButtonFormField<CloudProvider>),
      )
      .onChanged!(provider);
  await tester.pumpAndSettle();
}

Future<void> _loadProfile(WidgetTester tester, String name) async {
  final dropdown = find.byType(DropdownButtonFormField<String>);
  await tester.ensureVisible(dropdown);
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

ConnectionDialogExtraStrings _strings(WidgetTester tester) =>
    ConnectionDialogExtraStrings(tester.element(find.byType(ConnectionDialog)));

ElevatedButton _connectButton(WidgetTester tester) {
  final l10n = AppLocalizations.of(
    tester.element(find.byType(ConnectionDialog)),
  )!;
  return tester.widget<ElevatedButton>(
    find.widgetWithText(ElevatedButton, l10n.connect),
  );
}

void _expectFields(
  WidgetTester tester, {
  required String host,
  required String user,
  required bool requireEncryption,
  required SmbBackend backend,
}) {
  final l10n = AppLocalizations.of(
    tester.element(find.byType(ConnectionDialog)),
  )!;
  for (final entry in {l10n.serverUrl: host, l10n.username: user}.entries) {
    final field = tester.widget<TextField>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == entry.key,
      ),
    );
    expect(field.controller!.text, entry.value);
  }
  expect(
    tester.widget<SmbBackendField>(find.byType(SmbBackendField)).value,
    backend,
  );
  expect(
    tester
        .state<FormFieldState<SmbBackend>>(find.byKey(const Key('smb-backend')))
        .value,
    backend,
  );
  expect(
    tester
        .widget<CheckboxListTile>(
          find.widgetWithText(
            CheckboxListTile,
            _strings(tester).text('requireSmb'),
          ),
        )
        .value,
    requireEncryption,
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('invalid saved SMB profile is atomic and blocks stale login', (
    tester,
  ) async {
    var authReads = 0;
    await _openConnection(tester, onAuthRead: () => authReads++);
    await _loadProfile(tester, 'Rust profile');
    final previousConnect = _connectButton(tester).onPressed!;

    await _loadProfile(tester, 'Invalid profile');

    expect(tester.takeException(), isNull);
    _expectFields(
      tester,
      host: 'smb://first.example/First/',
      user: 'first-user',
      requireEncryption: false,
      backend: SmbBackend.rust,
    );
    expect(
      find.text(_strings(tester).text('invalidSmbBackendProfile')),
      findsOneWidget,
    );
    expect(_connectButton(tester).onPressed, isNull);
    // A callback captured before the invalid profile was selected is blocked
    // by the action guard too, before any authentication provider is read.
    previousConnect();
    await tester.pumpAndSettle();
    expect(authReads, 0);
    expect(tester.takeException(), isNull);

    // Reaffirming the same valid transport is an explicit recovery decision.
    final backendField = find.byKey(const Key('smb-backend'));
    await tester.ensureVisible(backendField);
    await tester.tap(backendField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rust (experimental)').last);
    await tester.pumpAndSettle();
    expect(_connectButton(tester).onPressed, isNotNull);
    expect(
      find.text(_strings(tester).text('invalidSmbBackendProfile')),
      findsNothing,
    );
    _expectFields(
      tester,
      host: 'smb://first.example/First/',
      user: 'first-user',
      requireEncryption: false,
      backend: SmbBackend.rust,
    );
  });

  testWidgets('valid and legacy profiles recover from an invalid SMB profile', (
    tester,
  ) async {
    await _openConnection(tester);
    await _loadProfile(tester, 'Rust profile');
    await _loadProfile(tester, 'Invalid profile');
    await _loadProfile(tester, 'Compatible profile');
    _expectFields(
      tester,
      host: 'smb://second.example/Second/',
      user: 'second-user',
      requireEncryption: true,
      backend: SmbBackend.libsmb2,
    );
    expect(_connectButton(tester).onPressed, isNotNull);
    expect(
      find.text(_strings(tester).text('invalidSmbBackendProfile')),
      findsNothing,
    );

    await _loadProfile(tester, 'Rust profile');
    await _loadProfile(tester, 'Invalid profile');
    await _loadProfile(tester, 'Legacy profile');
    _expectFields(
      tester,
      host: 'smb://legacy.example/Legacy/',
      user: 'legacy-user',
      requireEncryption: true,
      backend: SmbBackend.libsmb2,
    );
    expect(_connectButton(tester).onPressed, isNotNull);
    expect(
      find.text(_strings(tester).text('invalidSmbBackendProfile')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('localized SMB profile error survives switching providers', (
    tester,
  ) async {
    await _openConnection(tester, locale: const Locale('de'));
    await _loadProfile(tester, 'Invalid profile');
    final message = ConnectionDialogExtraStrings
        .translations['de']!['invalidSmbBackendProfile']!;
    expect(find.text(message), findsOneWidget);
    expect(_connectButton(tester).onPressed, isNull);

    await _selectProvider(tester, CloudProvider.webdav);
    expect(find.text(message), findsNothing);
    expect(_connectButton(tester).onPressed, isNotNull);
    await _selectProvider(tester, CloudProvider.smb);
    expect(find.text(message), findsOneWidget);
    expect(_connectButton(tester).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  test(
    'invalid SMB profile recovery message covers every supported locale',
    () {
      final translations = ConnectionDialogExtraStrings.translations;
      final english = translations['en']!['invalidSmbBackendProfile'];
      for (final locale in AppLocalizations.supportedLocales) {
        final message =
            translations[locale.languageCode]!['invalidSmbBackendProfile'];
        expect(message, isNotEmpty, reason: locale.languageCode);
        if (locale.languageCode != 'en') {
          expect(message, isNot(english), reason: locale.languageCode);
        }
      }
    },
  );
}
