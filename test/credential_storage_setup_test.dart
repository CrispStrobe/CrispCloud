import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/services/credential_storage_config.dart';
import 'package:crisp_cloud/services/secure_storage_macos_keychain.dart';
import 'package:crisp_cloud/widgets/credential_storage_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'first run can create the encrypted-file backend with an eye toggle',
    (tester) async {
      CredentialStorageSetupResult? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CredentialStorageSetupPanel(
                firstRun: true,
                onComplete: (value) => result = value,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Choose credential storage'), findsOneWidget);
      await tester.tap(find.text('Encrypted file (master password)'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(2));
      expect(tester.widget<TextField>(fields.at(0)).obscureText, isTrue);
      await tester.tap(find.byIcon(Icons.visibility).first);
      await tester.pump();
      expect(tester.widget<TextField>(fields.at(0)).obscureText, isFalse);
      expect(tester.widget<TextField>(fields.at(0)).autocorrect, isFalse);
      expect(tester.widget<TextField>(fields.at(0)).enableSuggestions, isFalse);

      await tester.enterText(fields.at(0), '  correct horse battery staple  ');
      await tester.enterText(fields.at(1), '  correct horse battery staple  ');
      await tester.ensureVisible(find.byKey(const ValueKey('credential-setup-continue')));
      await tester.tap(find.byKey(const ValueKey('credential-setup-continue')));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.mode, CredentialStorageMode.encryptedFile);
      expect(result!.masterPassword, '  correct horse battery staple  ');
    },
  );

  testWidgets('mismatched master passwords are rejected', (tester) async {
    CredentialStorageSetupResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CredentialStorageSetupPanel(
              firstRun: true,
              onComplete: (value) => result = value,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Encrypted file (master password)'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'one password');
    await tester.enterText(fields.at(1), 'other password');
    await tester.ensureVisible(find.byKey(const ValueKey('credential-setup-continue')));
    await tester.tap(find.byKey(const ValueKey('credential-setup-continue')));
    await tester.pumpAndSettle();

    expect(result, isNull);
    expect(find.text('Master passwords do not match.'), findsOneWidget);
  });

  testWidgets('first-run passwords use the same minimum as the unlock gate', (tester) async {
    CredentialStorageSetupResult? result;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: SingleChildScrollView(child: CredentialStorageSetupPanel(
        firstRun: true,
        initialMode: CredentialStorageMode.encryptedFile,
        onComplete: (value) => result = value,
      )),
    )));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'short');
    await tester.enterText(fields.at(1), 'short');
    final button = find.byKey(const ValueKey('credential-setup-continue'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.text('Use at least 8 characters for the master password.'), findsOneWidget);
  });

  testWidgets('settings choice does not create a new vault or collect a password', (tester) async {
    CredentialStorageSetupResult? result;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: CredentialStorageSetupPanel(
        initialMode: CredentialStorageMode.encryptedFile,
        onComplete: (value) => result = value,
      ),
    )));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byKey(const ValueKey('credential-setup-continue')));
    await tester.pumpAndSettle();
    expect(result?.mode, CredentialStorageMode.encryptedFile);
    expect(result?.masterPassword, isNull);
  });

  testWidgets('macOS system default probes OS storage without selecting a discovered login file', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const customChannel = MethodChannel(MacOsCustomKeychainStorage.methodChannelName);
    const osChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    final customCalls = <String>[];
    final values = <String, String>{};
    messenger.setMockMethodCallHandler(customChannel, (call) async {
      customCalls.add(call.method);
      if (call.method == 'listKeychains') {
        return [{'label': 'login', 'path': '/synthetic/login.keychain-db'}];
      }
      throw StateError('Default selection must not open a file keychain.');
    });
    messenger.setMockMethodCallHandler(osChannel, (call) async {
      final args = call.arguments as Map;
      final key = args['key'] as String;
      switch (call.method) {
        case 'write': values[key] = args['value'] as String; return null;
        case 'read': return values[key];
        case 'delete': values.remove(key); return null;
        default: throw StateError('Unexpected OS storage method');
      }
    });
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(customChannel, null);
      messenger.setMockMethodCallHandler(osChannel, null);
    });
    CredentialStorageSetupResult? result;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: SingleChildScrollView(child: CredentialStorageSetupPanel(
        firstRun: true,
        onComplete: (value) => result = value,
      )),
    )));
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('credential-setup-continue'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(result?.mode, CredentialStorageMode.systemKeychain);
    expect(result?.keychainPath, isNull);
    expect(customCalls, ['listKeychains']);
    expect(values, isEmpty, reason: 'The availability probe must clean up its record.');
  });
}
