import 'package:crisp_cloud/providers/auth_provider.dart';
import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/screens/screen_dialogs.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crisp_cloud/services/filen_client_adapter.dart';
import 'package:crisp_cloud/services/filen_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';

class _FilenLogoutStorage extends InMemorySecureStorage {
  String failure = '';

  @override
  bool get isPersistent => true;

  @override
  Future<void> delete(String key) async {
    if (failure == 'throw') throw StateError('Synthetic private platform detail');
    if (failure == 'drop') return;
    await super.delete(key);
  }

  @override
  Future<String?> read(String key) async {
    if (failure == 'read') throw StateError('Synthetic private read detail');
    return super.read(key);
  }
}

const _savedFilenCredentials = {
  'email': 'fixture@example.test',
  'apiKey': 'synthetic-filen-api-key',
  'masterKeys': 'synthetic-key-one|synthetic-key-two',
  'baseFolderUUID': 'synthetic-folder',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FilenClientAdapter adapter;
  late FilenConfigService configService;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    configService = FilenConfigService(configPath: '/tmp/filen_test_config', secureStorage: InMemorySecureStorage());
    adapter = FilenClientAdapter(config: configService);
  });

  group('FilenClientAdapter', () {
    test('providerName returns Filen', () {
      expect(adapter.providerName, equals('Filen'));
    });

    test('rootPath returns /', () {
      expect(adapter.rootPath, equals('/'));
    });

    test('isAuthenticated returns false initially', () {
      expect(adapter.isAuthenticated, isFalse);
    });

    test('isAuthenticated returns true after setAuth with apiKey', () {
      adapter.client.setAuth({
        'apiKey': 'test-api-key-123',
        'masterKeys': 'key1|key2',
        'baseFolderUUID': 'some-uuid',
      });
      expect(adapter.isAuthenticated, isTrue);
    });

    test('is2faNeeded always returns false', () async {
      final result = await adapter.is2faNeeded('test@example.com');
      expect(result, isFalse);
    });

    test('logout clears auth state', () async {
      // First set some auth
      adapter.client.setAuth({
        'apiKey': 'test-api-key-123',
        'masterKeys': 'key1|key2',
        'baseFolderUUID': 'some-uuid',
      });
      expect(adapter.isAuthenticated, isTrue);

      // Now logout
      await adapter.logout();
      expect(adapter.isAuthenticated, isFalse);
    });

    for (final failure in ['throw', 'drop', 'read']) {
      test('logout reports $failure storage failure after discarding session keys', () async {
        final storage = _FilenLogoutStorage();
        final config = FilenConfigService(configPath: 'fixture', secureStorage: storage);
        await config.saveCredentials(_savedFilenCredentials);
        final client = FilenClientAdapter(config: config);
        client.client.setAuth(_savedFilenCredentials);
        storage.failure = failure;

        await expectLater(
          client.logout(),
          throwsA(isA<FilenCredentialDeletionFailure>().having(
            (error) => error.toString(),
            'safe message',
            isNot(contains('private')),
          )),
        );

        expect(client.isAuthenticated, isFalse);
        expect(client.client.apiKey, isEmpty);
        expect(client.client.masterKeys, isEmpty);
        storage.failure = '';
        if (failure != 'read') {
          expect(await config.readCredentials(), _savedFilenCredentials);
        }
        await client.logout();
        expect(await config.readCredentials(), isNull);
      });
    }

    test('persistent logout removes retained legacy login before secure deletion', () async {
      SharedPreferences.setMockInitialValues({
        'filen_credentials': '{"email":"old@example.test","apiKey":"obsolete"}',
      });
      final storage = _FilenLogoutStorage();
      final config = FilenConfigService(configPath: 'fixture', secureStorage: storage);
      await config.saveCredentials(_savedFilenCredentials);

      await config.clearCredentials();
      await CredentialMigration.migrateIfNeeded(storage);

      expect(await config.readCredentials(), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('filen_credentials'), isFalse);
    });

    test('ephemeral logout leaves durable legacy login untouched and unimported', () async {
      const legacy = '{"email":"old@example.test","apiKey":"obsolete"}';
      SharedPreferences.setMockInitialValues({'filen_credentials': legacy});
      final storage = InMemorySecureStorage();
      final config = FilenConfigService(configPath: 'fixture', secureStorage: storage);
      await config.saveCredentials(_savedFilenCredentials);

      await config.clearCredentials();
      await CredentialMigration.migrateIfNeeded(storage);

      expect(await config.readCredentials(), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('filen_credentials'), legacy);
    });

    test('auth state disconnects on failed cleanup and retains the adapter for retry', () async {
      final storage = _FilenLogoutStorage();
      final config = FilenConfigService(configPath: 'fixture', secureStorage: storage);
      await config.saveCredentials(_savedFilenCredentials);
      final container = ProviderContainer(overrides: [
        authProvider.overrideWith((ref) => AuthNotifier(
          ref,
          initialProvider: CloudProvider.filen,
          config: config,
          configPath: 'fixture',
          secureStorage: storage,
        )),
      ]);
      addTearDown(container.dispose);
      final auth = container.read(authProvider);
      await Future<void>.delayed(Duration.zero);
      expect(auth.isConnected, isTrue);
      final client = auth.client;
      storage.failure = 'throw';

      await expectLater(auth.logout(), throwsA(isA<FilenCredentialDeletionFailure>()));

      expect(auth.isConnected, isFalse);
      expect(auth.userEmail, isNull);
      expect(auth.client, same(client));
      expect(client.isAuthenticated, isFalse);
      storage.failure = '';
      await auth.logout();
      expect(await config.readCredentials(), isNull);
    });

    testWidgets('logout dialog reports cleanup failure and succeeds only after retry', (tester) async {
      final storage = _FilenLogoutStorage();
      final config = FilenConfigService(configPath: 'fixture', secureStorage: storage);
      await config.saveCredentials(_savedFilenCredentials);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => AuthNotifier(
            ref,
            initialProvider: CloudProvider.filen,
            config: config,
            configPath: 'fixture',
            secureStorage: storage,
          )),
        ],
        child: MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Consumer(builder: (context, ref, _) {
            ref.watch(authProvider);
            return Scaffold(body: ElevatedButton(
              onPressed: () => confirmLogoutRiverpod(context, ref),
              child: const Text('Open logout'),
            ));
          }),
        ),
      ));
      await tester.pumpAndSettle();
      storage.failure = 'throw';
      await tester.tap(find.text('Open logout'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Logout'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Saved Filen credentials could not be removed'), findsOneWidget);
      expect(find.text('Logged out successfully'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
      expect(tester.takeException(), isNull);
      storage.failure = '';
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Logged out successfully'), findsOneWidget);
      expect(await config.readCredentials(), isNull);
    });

    test('userId returns null when not authenticated', () {
      expect(adapter.userId, anyOf(isNull, isEmpty));
    });

    test('bucketId always returns null', () {
      expect(adapter.bucketId, isNull);
    });

    test('debugMode defaults to false', () {
      expect(adapter.debugMode, isFalse);
    });

    test('debugMode can be set', () {
      adapter.debugMode = true;
      expect(adapter.debugMode, isTrue);
    });

    test('filenConfig is accessible', () {
      expect(adapter.filenConfig, same(configService));
    });

    test('client is accessible', () {
      expect(adapter.client, isNotNull);
    });
  });
}
