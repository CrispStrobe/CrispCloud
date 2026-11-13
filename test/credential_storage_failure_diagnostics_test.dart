import 'dart:convert';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/main.dart';
import 'package:crisp_cloud/providers/core_providers.dart';
import 'package:crisp_cloud/services/app_lock_service.dart';
import 'package:crisp_cloud/services/credential_storage_bootstrap.dart';
import 'package:crisp_cloud/services/credential_storage_config.dart';
import 'package:crisp_cloud/services/credential_storage_diagnostics.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/secure_storage_macos_keychain.dart';
import 'package:crisp_cloud/widgets/lock_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Store extends InMemorySecureStorage
    implements CredentialStorageIdentity {
  int deletes = 0;
  @override
  String get credentialStoreName => 'Custom macOS keychain';
  @override
  String get credentialStoreLocation => '/synthetic/original.keychain-db';
  @override
  Future<void> deleteAll() async {
    deletes++;
    await super.deleteAll();
  }
}

class _Policy extends AppLockService {
  _Policy(super.storage);
  bool fail = true;
  String failureCode = 'custom_keychain_locked';
  bool failVerification = false;
  int reads = 0;
  @override
  Future<bool> isEnabled() async {
    reads++;
    if (fail) {
      throw PlatformException(
        code: failureCode,
        message: 'The selected keychain is locked.',
        details: {'status': -25308, 'credential': 'MUST_NOT_RENDER'},
      );
    }
    return true;
  }

  @override
  Future<int> getTimeout() async => 300;
  @override
  Future<bool> isBiometricEnabled() async => false;
  @override
  Future<bool> verify(String code) async {
    if (failVerification) {
      throw PlatformException(
        code: 'custom_keychain_locked',
        message: 'The selected keychain is locked.',
        details: {'status': -25308},
      );
    }
    return false;
  }
}

Widget _gate(
  SecureStorage store,
  _Policy policy, {
  Future<void> Function()? restart,
}) => ProviderScope(
  overrides: [
    secureStorageProvider.overrideWithValue(store),
    appLockServiceProvider.overrideWithValue(policy),
    credentialRecoveryRestartProvider.overrideWithValue(restart ?? () async {}),
  ],
  child: const MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: AppLockGate(),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'late policy failure identifies the exact store and retains its original stack',
    (tester) async {
      final store = _Store();
      final policy = _Policy(store);
      await tester.pumpWidget(_gate(store, policy));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('/synthetic/original.keychain-db'),
        findsWidgets,
      );
      expect(find.textContaining('OSStatus -25308'), findsWidgets);
      expect(
        find.byKey(const ValueKey('startup-choose-store')),
        findsOneWidget,
      );
      expect(find.textContaining('MUST_NOT_RENDER'), findsNothing);
      await tester.tap(find.text('Technical details and original stack trace'));
      await tester.pumpAndSettle();
      expect(find.textContaining('_Policy.isEnabled'), findsWidgets);
      policy.fail = false;
      await tester.ensureVisible(find.text('Retry'));
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('startup-choose-store')), findsNothing);
      expect(policy.reads, 2);
    },
  );

  testWidgets(
    'locked stores offer unlock retry; only missing file grants offer a picker',
    (tester) async {
      final store = MacOsCustomKeychainStorage(
        path: '/synthetic/original.keychain-db',
      );
      final policy = _Policy(store);
      await tester.pumpWidget(_gate(store, policy));
      await tester.pumpAndSettle();
      expect(find.text('Restore keychain access'), findsNothing);
      expect(
        find.byKey(const ValueKey('startup-choose-store')),
        findsOneWidget,
      );
      policy.failureCode = 'custom_keychain_access_required';
      await tester.ensureVisible(find.text('Retry'));
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Restore keychain access'), findsOneWidget);
    },
  );

  testWidgets(
    'late failure offers a confirmed replacement without deleting the original store',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = _Store();
      final policy = _Policy(store);
      await store.write('original_credential', 'retained');
      await CredentialStorageConfig.writeSelection(
        mode: CredentialStorageMode.systemKeychain,
        customKeychainPath: store.credentialStoreLocation,
      );
      var restarts = 0;
      await tester.pumpWidget(
        _gate(
          store,
          policy,
          restart: () async {
            restarts++;
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('startup-choose-store')),
      );
      await tester.tap(find.byKey(const ValueKey('startup-choose-store')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        (await CredentialStorageConfig.readSelection()).mode,
        CredentialStorageMode.systemKeychain,
      );
      expect(restarts, 0);
      await tester.tap(find.byKey(const ValueKey('startup-choose-store')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('startup-choose-store-confirm')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('This session only'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('credential-setup-continue')));
      await tester.pumpAndSettle();
      expect(
        (await CredentialStorageConfig.readSelection()).mode,
        CredentialStorageMode.sessionOnly,
      );
      expect(restarts, 1);
      expect(await store.read('original_credential'), 'retained');
      expect(store.deletes, 0);
    },
  );

  testWidgets('credential recovery remains reachable in a small window', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      StartupFailureApp(
        error: CredentialStorageUnavailable(
          diagnostics: CredentialStorageDiagnostics.capture(
            StateError('Stored app-lock policy is incomplete.'),
            StackTrace.current,
            operation: 'Read App Lock policy',
            store: 'Custom keychain',
            location: '/a/very/long/path/to/original.keychain-db',
          ),
        ),
        onRetry: () {},
        onChooseStorage: (_) {},
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('startup-choose-store')),
    );
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('startup-choose-store')).hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets(
    'a store error during PIN verification returns to actionable recovery',
    (tester) async {
      final store = _Store();
      final policy = _Policy(store)
        ..fail = false
        ..failVerification = true;
      await tester.pumpWidget(_gate(store, policy));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(find.textContaining('OSStatus -25308'), findsWidgets);
      expect(
        find.byKey(const ValueKey('startup-choose-store')),
        findsOneWidget,
      );
    },
  );

  test('preflight rejects unreadable existing policy metadata despite an available store', () async {
    final store = _Store();
    await store.write('app_lock_enabled', 'true');
    await store.write('app_lock_hash', List.filled(64, 'a').join());
    // An incomplete persisted policy must remain protected, with a real cause.
    await expectLater(
      AppLockService(store).validateStartupPolicy(),
      throwsStateError,
    );
    await store.write('app_lock_salt', base64Encode(List.filled(16, 1)));
    expect(await AppLockService(store).validateStartupPolicy(), isTrue);
  });
}
