import 'dart:async';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/services/secure_storage_macos_keychain.dart';
import 'package:crisp_cloud/widgets/keychain_lock_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(MacOsCustomKeychainStorage.methodChannelName);
  const path = '/selected/private.keychain-db';
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  late Map<String, Object> policy;
  late MacOsCustomKeychainStorage storage;
  bool locked = false;
  bool denyWrite = false;
  Completer<void>? writeGate;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    calls.clear();
    locked = false;
    denyWrite = false;
    writeGate = null;
    policy = {
      'lockOnSleep': false,
      'lockAfterInactivity': false,
      'idleSeconds': 2147483647,
    };
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'unlock') {
        locked = false;
        return null;
      }
      if (call.method == 'readLockSettings') {
        if (locked) throw PlatformException(code: 'custom_keychain_locked');
        return Map<String, Object>.of(policy);
      }
      if (call.method == 'writeLockSettings') {
        if (denyWrite) {
          throw PlatformException(code: 'custom_keychain_permission_denied');
        }
        await writeGate?.future;
        final arguments = call.arguments as Map;
        policy = {
          for (final key in [
            'lockOnSleep',
            'lockAfterInactivity',
            'idleSeconds',
          ])
            key: arguments[key] as Object,
        };
        return policy;
      }
      return null;
    });
    storage = MacOsCustomKeychainStorage(path: path, channel: channel);
    try {
      await storage.initialize();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
    calls.clear();
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  Future<void> mount(
    WidgetTester tester, {
    MacOsCustomKeychainStorage? selected,
    Locale locale = const Locale('en'),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: KeychainLockSettings(storage: selected ?? storage),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  SwitchListTile tile(WidgetTester tester, String key) =>
      tester.widget(find.byKey(ValueKey(key)));

  Future<void> toggle(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
  }

  void testMacWidgets(
    String description,
    Future<void> Function(WidgetTester) body,
  ) {
    testWidgets(
      description,
      body,
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  testMacWidgets(
    'both default locks are off without any unlock or credential query',
    (tester) async {
      await mount(tester);
      expect(tile(tester, 'keychain-lock-on-sleep').value, isFalse);
      expect(tile(tester, 'keychain-lock-after-inactivity').value, isFalse);
      expect(find.byType(DropdownButtonFormField<int>), findsNothing);
      expect(calls.map((call) => call.method), ['readLockSettings']);
      expect((calls.single.arguments as Map)['path'], path);
    },
  );

  testMacWidgets(
    'independent switches and timeout survive reopening settings',
    (tester) async {
      await mount(tester);
      await toggle(tester, 'keychain-lock-on-sleep');
      expect(tile(tester, 'keychain-lock-on-sleep').value, isTrue);
      expect(tile(tester, 'keychain-lock-after-inactivity').value, isFalse);
      await toggle(tester, 'keychain-lock-after-inactivity');
      await tester.ensureVisible(find.byType(DropdownButtonFormField<int>));
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('30 minutes').last);
      await tester.pumpAndSettle();
      expect(policy, {
        'lockOnSleep': true,
        'lockAfterInactivity': true,
        'idleSeconds': 1800,
      });
      await tester.pumpWidget(const SizedBox());
      await mount(tester);
      expect(tile(tester, 'keychain-lock-on-sleep').value, isTrue);
      expect(tile(tester, 'keychain-lock-after-inactivity').value, isTrue);
      expect(find.text('30 minutes'), findsOneWidget);
      expect(
        calls.every((call) => (call.arguments as Map)['path'] == path),
        isTrue,
      );
    },
  );

  testMacWidgets(
    'a locked keychain waits for explicit Retry before requesting unlock',
    (tester) async {
      locked = true;
      await mount(tester);
      expect(calls.where((call) => call.method == 'unlock'), isEmpty);
      expect(find.byType(SwitchListTile), findsNothing);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(calls.where((call) => call.method == 'unlock'), hasLength(1));
      expect(tile(tester, 'keychain-lock-on-sleep').value, isFalse);
    },
  );

  testMacWidgets(
    'a denied write does not claim success or request another keychain',
    (tester) async {
      await mount(tester);
      denyWrite = true;
      await toggle(tester, 'keychain-lock-on-sleep');
      expect(
        find.text('Could not read or update keychain lock settings.'),
        findsOneWidget,
      );
      expect(policy['lockOnSleep'], isFalse);
      expect(calls.where((call) => call.method == 'unlock'), isEmpty);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(tile(tester, 'keychain-lock-on-sleep').value, isFalse);
    },
  );

  testMacWidgets(
    'pending writes disable both controls until native confirmation',
    (tester) async {
      await mount(tester);
      final gate = writeGate = Completer<void>();
      await tester.tap(find.byKey(const ValueKey('keychain-lock-on-sleep')));
      await tester.pump();
      expect(tile(tester, 'keychain-lock-on-sleep').onChanged, isNull);
      expect(tile(tester, 'keychain-lock-after-inactivity').onChanged, isNull);
      expect(tile(tester, 'keychain-lock-on-sleep').value, isFalse);
      gate.complete();
      await tester.pumpAndSettle();
      expect(tile(tester, 'keychain-lock-on-sleep').value, isTrue);
    },
  );

  testMacWidgets('German controls fit a compact scrollable settings pane', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await mount(tester, locale: const Locale('de'));
    expect(
      find.text('Schlüsselbund beim Ruhezustand des Macs sperren'),
      findsOneWidget,
    );
    await toggle(tester, 'keychain-lock-after-inactivity');
    expect(policy['lockAfterInactivity'], isTrue);
    expect(tester.takeException(), isNull);
  });
}
