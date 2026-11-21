import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/biometric_vault_strings.dart';
import 'package:crisp_cloud/main.dart';
import 'package:crisp_cloud/providers/core_providers.dart';
import 'package:crisp_cloud/services/biometric_vault_unlock.dart';
import 'package:crisp_cloud/services/secure_storage_web.dart';
import 'package:crisp_cloud/services/web_crypto_provider.dart';
import 'package:crisp_cloud/widgets/biometric_vault_settings_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stands in for the native keychain helper. The OS-enforced biometry itself
/// cannot be unit tested; this models the statuses the channel returns.
class FakeBiometricStore implements BiometricSecretStore {
  @override
  bool isSupported = true;
  BiometricAvailability available = BiometricAvailability.available;
  BiometricReadStatus nextRead = BiometricReadStatus.ok;
  Uint8List? stored;
  Uint8List? lastStoreArgument;
  final reasons = <String>[];
  int deletes = 0;

  @override
  Future<BiometricAvailability> availability() async =>
      isSupported ? available : BiometricAvailability.unsupportedPlatform;

  @override
  Future<BiometricAvailability?> store(Uint8List secret) async {
    if (available != BiometricAvailability.available) return available;
    lastStoreArgument = secret;
    stored = Uint8List.fromList(secret);
    return null;
  }

  @override
  Future<BiometricReadResult> read(String reason) async {
    reasons.add(reason);
    if (nextRead != BiometricReadStatus.ok) {
      return BiometricReadResult(nextRead);
    }
    final value = stored;
    if (value == null) {
      return const BiometricReadResult(BiometricReadStatus.notFound);
    }
    return BiometricReadResult(nextRead, Uint8List.fromList(value));
  }

  @override
  Future<void> delete() async {
    deletes++;
    stored = null;
  }
}

class _ContendedBackend extends InMemoryWebStorageBackend {
  bool contended = false;
  @override
  Future<String?> getItem(String key) async {
    if (contended) {
      throw StateError(
        'Credential vault is in use or could not be locked; retry',
      );
    }
    return super.getItem(key);
  }
}

WebEncryptedStorage _vault(
  WebStorageBackend backend, {
  WebCryptoProvider? crypto,
}) => WebEncryptedStorage(
  backend,
  newVaultIterations: 10,
  cryptoProvider: crypto,
);

Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('WebEncryptedStorage key unlock', () {
    for (final entry in <String, WebCryptoProvider?>{
      'default native provider': null,
      'pointycastle': const PointycastleCryptoProvider(),
    }.entries) {
      test('exported key reopens the same vault (${entry.key})', () async {
        final backend = InMemoryWebStorageBackend();
        final original = _vault(backend, crypto: entry.value);
        await original.initialize('correct horse');
        await original.write('token', 'secret-value');
        final key = await original.exportUnlockKey();
        expect(key, isNotNull);
        expect(key, hasLength(32));

        final reopened = _vault(backend, crypto: entry.value);
        await reopened.initializeWithKey(key!);
        expect(reopened.isInitialized, isTrue);
        expect(await reopened.read('token'), 'secret-value');
        // The caller may zero its buffer; the storage kept its own copy.
        key.fillRange(0, key.length, 0);
        expect(await reopened.read('token'), 'secret-value');
      });
    }

    test(
      'a key for another vault generation fails like a wrong password',
      () async {
        final backend = InMemoryWebStorageBackend();
        final first = _vault(backend);
        await first.initialize('first password');
        final key = (await first.exportUnlockKey())!;

        final replaced = InMemoryWebStorageBackend();
        await _vault(replaced).initialize('first password'); // new salt
        final other = _vault(replaced);
        await expectLater(
          other.initializeWithKey(key),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'Incorrect master password or damaged vault',
            ),
          ),
        );
        expect(other.isInitialized, isFalse);
        await expectLater(
          other.initializeWithKey(Uint8List(5)),
          throwsA(isA<StateError>()),
        );
      },
    );

    test('key unlock never creates a missing vault', () async {
      final backend = InMemoryWebStorageBackend();
      await expectLater(
        _vault(backend).initializeWithKey(Uint8List(32)),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Credential vault is missing',
          ),
        ),
      );
      expect(await backend.allKeys(), isEmpty);
    });

    test('a locked vault cannot export a key', () async {
      final backend = InMemoryWebStorageBackend();
      await _vault(backend).initialize('pw');
      await expectLater(_vault(backend).exportUnlockKey(), throwsStateError);
    });
  });

  group('BiometricVaultUnlock', () {
    late FakeBiometricStore store;
    late BiometricVaultUnlock unlock;
    late InMemoryWebStorageBackend backend;
    late WebEncryptedStorage vault;

    setUp(() async {
      store = FakeBiometricStore();
      unlock = BiometricVaultUnlock(store: store, preferences: _prefs);
      backend = InMemoryWebStorageBackend();
      vault = _vault(backend);
      await vault.initialize('correct horse');
    });

    test(
      'enrolment stores the derived key, not the password, and zeroes it',
      () async {
        expect(await unlock.shouldOffer(), isTrue);
        expect(await unlock.enable(vault), isNull);
        expect(await unlock.isEnabled(), isTrue);
        expect(store.stored, hasLength(32));
        expect(store.stored, isNot(equals('correct horse'.codeUnits)));
        expect(store.lastStoreArgument!.every((b) => b == 0), isTrue);
        expect(await unlock.shouldOffer(), isFalse);
      },
    );

    test('Touch ID unlock opens a fresh handle', () async {
      await unlock.enable(vault);
      final fresh = _vault(backend);
      expect(
        await unlock.tryUnlock(fresh, 'unlock'),
        BiometricUnlockOutcome.unlocked,
      );
      expect(fresh.isInitialized, isTrue);
      expect(store.reasons, ['unlock']);
    });

    test('cancel or failure keeps the item and falls back', () async {
      await unlock.enable(vault);
      for (final status in [
        BiometricReadStatus.cancelled,
        BiometricReadStatus.failed,
      ]) {
        store.nextRead = status;
        final fresh = _vault(backend);
        expect(
          await unlock.tryUnlock(fresh, 'unlock'),
          BiometricUnlockOutcome.cancelled,
        );
        expect(fresh.isInitialized, isFalse);
      }
      store.nextRead = BiometricReadStatus.unavailable;
      expect(
        await unlock.tryUnlock(_vault(backend), 'unlock'),
        BiometricUnlockOutcome.notAttempted,
      );
      expect(store.deletes, 0);
      expect(await unlock.isEnabled(), isTrue);
    });

    test('biometry change invalidates, removes and re-offers', () async {
      await unlock.declineOffer();
      await unlock.enable(vault);
      for (final status in [
        BiometricReadStatus.notFound,
        BiometricReadStatus.invalidated,
      ]) {
        await unlock.enable(vault);
        store.nextRead = status;
        expect(
          await unlock.tryUnlock(_vault(backend), 'unlock'),
          BiometricUnlockOutcome.invalidated,
        );
        expect(await unlock.isEnabled(), isFalse);
        expect(store.stored, isNull);
        expect(await unlock.shouldOffer(), isTrue);
      }
    });

    test('a re-keyed vault invalidates the stored key', () async {
      await unlock.enable(vault);
      // Simulate a password change / reset: new metadata, same location.
      for (final key in await backend.allKeys()) {
        await backend.removeItem(key);
      }
      await _vault(backend).initialize('new password');
      final fresh = _vault(backend);
      expect(
        await unlock.tryUnlock(fresh, 'unlock'),
        BiometricUnlockOutcome.invalidated,
      );
      expect(fresh.isInitialized, isFalse);
      expect(store.deletes, 1);
      expect(await unlock.isEnabled(), isFalse);
    });

    test('transient vault errors keep the item', () async {
      final contended = _ContendedBackend();
      final original = _vault(contended);
      await original.initialize('pw');
      await unlock.enable(original);
      contended.contended = true;
      expect(
        await unlock.tryUnlock(_vault(contended), 'unlock'),
        BiometricUnlockOutcome.notAttempted,
      );
      expect(store.deletes, 0);
      expect(await unlock.isEnabled(), isTrue);
    });

    test(
      'unavailable Touch ID or missing entitlement is never offered',
      () async {
        for (final availability in [
          BiometricAvailability.missingEntitlement,
          BiometricAvailability.notEnrolled,
          BiometricAvailability.noBiometrics,
        ]) {
          store.available = availability;
          expect(await unlock.shouldOffer(), isFalse);
          expect(await unlock.enable(vault), availability);
          expect(await unlock.isEnabled(), isFalse);
        }
        store.isSupported = false;
        expect(await unlock.shouldOffer(), isFalse);
        expect(await unlock.isEnabled(), isFalse);
      },
    );

    test(
      'declining suppresses the offer; disabling and mode change remove',
      () async {
        await unlock.declineOffer();
        expect(await unlock.shouldOffer(), isFalse);
        await unlock.enable(vault);
        await unlock.disable();
        expect(store.stored, isNull);
        expect(await unlock.isEnabled(), isFalse);

        await unlock.enable(vault);
        await unlock.removeIfEnabled(); // storage mode changed / vault reset
        expect(store.stored, isNull);
        expect(await unlock.isEnabled(), isFalse);
        final deletes = store.deletes;
        await unlock.removeIfEnabled();
        expect(store.deletes, deletes, reason: 'nothing to remove');
      },
    );
  });

  group('MethodChannelBiometricSecretStore', () {
    const channel = MethodChannel(
      MethodChannelBiometricSecretStore.channelName,
    );
    TestWidgetsFlutterBinding.ensureInitialized();
    final calls = <MethodCall>[];
    Map<String, Object?> reply = const {};

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return reply;
          });
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('maps native statuses and passes the reason', () async {
      final store = MethodChannelBiometricSecretStore(supported: true);
      reply = {'status': 'missingEntitlement'};
      expect(
        await store.availability(),
        BiometricAvailability.missingEntitlement,
      );
      reply = {'status': 'notEnrolled'};
      expect(await store.availability(), BiometricAvailability.notEnrolled);
      reply = {'status': 'ok'};
      expect(await store.store(Uint8List(32)), isNull);
      expect(calls.last.arguments['secret'], hasLength(32));
      reply = {
        'status': 'ok',
        'secret': Uint8List.fromList(List.filled(32, 7)),
      };
      final read = await store.read('unlock the vault');
      expect(read.status, BiometricReadStatus.ok);
      expect(read.secret, hasLength(32));
      expect(calls.last.arguments['reason'], 'unlock the vault');
      for (final status in ['cancelled', 'notFound', 'invalidated', 'failed']) {
        reply = {'status': status};
        expect((await store.read('r')).status.name, status);
      }
      reply = {'status': 'bogus'};
      expect((await store.read('r')).status, BiometricReadStatus.error);
      reply = {'status': 'ok'};
      await store.delete();
      expect(calls.last.method, 'delete');
    });

    test('other platforms never touch the channel', () async {
      final store = MethodChannelBiometricSecretStore(supported: false);
      expect(
        await store.availability(),
        BiometricAvailability.unsupportedPlatform,
      );
      expect((await store.read('r')).status, BiometricReadStatus.unavailable);
      await store.delete();
      expect(calls, isEmpty);
    });
  });

  group('master password gate', () {
    late FakeBiometricStore store;
    late BiometricVaultUnlock unlock;
    late InMemoryWebStorageBackend backend;

    setUp(() async {
      store = FakeBiometricStore();
      unlock = BiometricVaultUnlock(store: store, preferences: _prefs);
      backend = InMemoryWebStorageBackend();
      final original = _vault(backend);
      await original.initialize('correct horse');
      // A damaged App Lock policy keeps the next screen a light failure view.
      await backend.setItem('crisp_enc_app_lock_enabled', 'damaged');
    });

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<WebEncryptedStorage> pumpGate(WidgetTester tester) async {
      final storage = _vault(backend);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureStorageProvider.overrideWithValue(storage),
            biometricVaultUnlockProvider.overrideWithValue(unlock),
          ],
          child: const MaterialApp(home: WebMasterPasswordGate()),
        ),
      );
      await tester.pumpAndSettle();
      return storage;
    }

    Future<void> typePassword(WidgetTester tester) async {
      await tester.enterText(find.byType(TextField), 'correct horse');
      await tester.tap(find.text('Unlock'));
      // The gate's spinner stays behind the offer dialog: no pumpAndSettle.
      await settle(tester);
    }

    final en = BiometricVaultStrings.forLanguage('en');

    testWidgets('password unlock offers Touch ID; accepting enrols', (
      tester,
    ) async {
      final storage = await pumpGate(tester);
      expect(store.reasons, isEmpty, reason: 'not enabled yet');
      await typePassword(tester);
      expect(find.text(en.offerTitle), findsOneWidget);
      await tester.tap(find.text(en.enable));
      await tester.pumpAndSettle();
      expect(storage.isInitialized, isTrue);
      expect(store.stored, hasLength(32));
      expect(await unlock.isEnabled(), isTrue);
      expect(find.byType(AppLockGate), findsOneWidget);
    });

    testWidgets('"Not now" stores nothing and is remembered', (tester) async {
      await pumpGate(tester);
      await typePassword(tester);
      await tester.tap(find.text(en.notNow));
      await tester.pumpAndSettle();
      expect(store.stored, isNull);
      expect(await unlock.shouldOffer(), isFalse);
      expect(find.byType(AppLockGate), findsOneWidget);
    });

    testWidgets('no offer when the build lacks the keychain entitlement', (
      tester,
    ) async {
      store.available = BiometricAvailability.missingEntitlement;
      await pumpGate(tester);
      await typePassword(tester);
      expect(find.text(en.offerTitle), findsNothing);
      expect(find.byType(AppLockGate), findsOneWidget);
    });

    testWidgets('enabled Touch ID unlocks first without the password', (
      tester,
    ) async {
      final enrolled = _vault(backend);
      await enrolled.initialize('correct horse');
      await unlock.enable(enrolled);
      final storage = await pumpGate(tester);
      expect(store.reasons, [en.reason]);
      expect(storage.isInitialized, isTrue);
      expect(find.text(en.offerTitle), findsNothing);
      expect(find.byType(AppLockGate), findsOneWidget);
    });

    testWidgets('cancel falls back to the password and keeps Touch ID', (
      tester,
    ) async {
      final enrolled = _vault(backend);
      await enrolled.initialize('correct horse');
      await unlock.enable(enrolled);
      store.nextRead = BiometricReadStatus.cancelled;
      final storage = await pumpGate(tester);
      expect(storage.isInitialized, isFalse);
      expect(find.byType(TextField), findsOneWidget);
      expect(
        find.byKey(const ValueKey('biometric-vault-unlock')),
        findsOneWidget,
      );

      // Retrying from the button succeeds.
      store.nextRead = BiometricReadStatus.ok;
      await tester.tap(find.byKey(const ValueKey('biometric-vault-unlock')));
      await tester.pumpAndSettle();
      expect(storage.isInitialized, isTrue);
      expect(store.reasons, hasLength(2));
      expect(find.byType(AppLockGate), findsOneWidget);
    });

    testWidgets('cancel then password: no re-offer while still enabled', (
      tester,
    ) async {
      final enrolled = _vault(backend);
      await enrolled.initialize('correct horse');
      await unlock.enable(enrolled);
      store.nextRead = BiometricReadStatus.cancelled;
      await pumpGate(tester);
      await typePassword(tester);
      expect(find.text(en.offerTitle), findsNothing);
      expect(await unlock.isEnabled(), isTrue);
      expect(find.byType(AppLockGate), findsOneWidget);
    });

    testWidgets('invalidated biometry falls back, then re-offers enrolment', (
      tester,
    ) async {
      final enrolled = _vault(backend);
      await enrolled.initialize('correct horse');
      await unlock.declineOffer();
      await unlock.enable(enrolled);
      store.nextRead = BiometricReadStatus.invalidated;
      final storage = await pumpGate(tester);
      expect(storage.isInitialized, isFalse);
      expect(find.text(en.invalidated), findsOneWidget);
      expect(
        find.byKey(const ValueKey('biometric-vault-unlock')),
        findsNothing,
      );
      expect(store.stored, isNull);

      store.nextRead = BiometricReadStatus.ok;
      await typePassword(tester);
      expect(find.text(en.offerTitle), findsOneWidget);
      await tester.tap(find.text(en.enable));
      await tester.pumpAndSettle();
      expect(store.stored, hasLength(32));
      expect(await unlock.isEnabled(), isTrue);
    });

    testWidgets('a missing (reset) vault removes the stale Touch ID key', (
      tester,
    ) async {
      final enrolled = _vault(backend);
      await enrolled.initialize('correct horse');
      await unlock.enable(enrolled);
      for (final key in await backend.allKeys()) {
        await backend.removeItem(key);
      }
      await pumpGate(tester);
      expect(store.reasons, isEmpty);
      expect(store.stored, isNull);
      expect(await unlock.isEnabled(), isFalse);
    });
  });

  group('settings toggle', () {
    late FakeBiometricStore store;
    late BiometricVaultUnlock unlock;
    late WebEncryptedStorage vault;

    setUp(() async {
      store = FakeBiometricStore();
      unlock = BiometricVaultUnlock(store: store, preferences: _prefs);
      vault = _vault(InMemoryWebStorageBackend());
      await vault.initialize('pw');
    });

    Future<void> pumpTile(WidgetTester tester, {Locale? locale}) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [biometricVaultUnlockProvider.overrideWithValue(unlock)],
          child: MaterialApp(
            home: Scaffold(body: BiometricVaultSettingsTile(storage: vault)),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    SwitchListTile tile(WidgetTester tester) => tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('settings-biometric-vault-unlock')),
    );

    testWidgets('turns Touch ID on and off', (tester) async {
      await pumpTile(tester);
      expect(tile(tester).value, isFalse);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(tile(tester).value, isTrue);
      expect(store.stored, hasLength(32));
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(tile(tester).value, isFalse);
      expect(store.stored, isNull);
    });

    testWidgets('explains and disables when the build cannot use it', (
      tester,
    ) async {
      store.available = BiometricAvailability.missingEntitlement;
      await pumpTile(tester);
      expect(tile(tester).onChanged, isNull);
      expect(
        find.text(BiometricVaultStrings.forLanguage('en').missingEntitlement),
        findsOneWidget,
      );
    });

    testWidgets('hidden on platforms without an implementation', (
      tester,
    ) async {
      store.isSupported = false;
      await pumpTile(tester);
      expect(find.byType(SwitchListTile), findsNothing);
    });
  });

  test('every app language has complete Touch ID strings', () {
    final english = BiometricVaultStrings.translations['en']!;
    for (final language in AppLocalizations.supportedLocales.map(
      (locale) => locale.languageCode,
    )) {
      final values = BiometricVaultStrings.translations[language];
      expect(values, isNotNull, reason: language);
      expect(values, hasLength(english.length), reason: language);
      for (var i = 0; i < values!.length; i++) {
        expect(values[i].trim(), isNotEmpty, reason: '$language/$i');
      }
    }
  });
}
