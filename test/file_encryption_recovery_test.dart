import 'dart:typed_data';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/key_management_strings.dart';
import 'package:crisp_cloud/providers/auth_provider.dart';
import 'package:crisp_cloud/providers/core_providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/encryption_service.dart';
import 'package:crisp_cloud/services/filen_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/utils/secure_clipboard.dart';
import 'package:crisp_cloud/widgets/connection_dialog.dart';
import 'package:crisp_cloud/widgets/file_encryption_recovery_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _confirmation = Key('file_encryption_recovery_confirmation');
const _confirm = Key('file_encryption_recovery_confirm');
const _cancel = Key('file_encryption_recovery_cancel');
const _phrase = Key('file_encryption_recovery_phrase');
const _toggle = Key('connection_file_encryption_toggle');
const _passphrase = Key('connection_file_encryption_passphrase');

Widget _app(Widget body, {Locale locale = const Locale('en')}) => MaterialApp(
  locale: locale,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  home: Scaffold(body: body),
);

Widget _recoveryHost(void Function(bool) onResult) => _app(
  Builder(
    builder: (context) => TextButton(
      onPressed: () async {
        final result = await showFileEncryptionRecoveryDialog(
          context,
          encryptionKey: Uint8List(32),
          salt: Uint8List.fromList(List.filled(16, 17)),
        );
        onResult(result);
      },
      child: const Text('Open recovery'),
    ),
  ),
);

Widget _connectionHost(
  InMemorySecureStorage storage,
  List<Override> overrides,
) => ProviderScope(
  overrides: [
    secureStorageProvider.overrideWithValue(storage),
    ...overrides,
  ],
  child: _app(
    Builder(
      builder: (context) => TextButton(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => const ConnectionDialog(),
        ),
        child: const Text('Open connection'),
      ),
    ),
  ),
);

class _PreflightClient extends Fake implements CloudStorageClient {
  int twoFactorChecks = 0;

  @override
  bool get isAuthenticated => false;

  @override
  Future<bool> is2faNeeded(String email) async {
    twoFactorChecks++;
    return false;
  }
}

class _RecordingAuth extends AuthNotifier {
  _RecordingAuth(Ref ref, InMemorySecureStorage storage)
    : super(
        ref,
        initialProvider: CloudProvider.filen,
        config: FilenConfigService(
          configPath: '/unused-file-recovery-test',
          secureStorage: storage,
        ),
        configPath: '/unused-file-recovery-test',
        secureStorage: storage,
      );

  final preflight = _PreflightClient();
  int loginCalls = 0;
  int encryptionCalls = 0;

  @override
  CloudStorageClient get client => preflight;

  @override
  Future<void> login(String email, String password, String? tfaCode) async {
    loginCalls++;
    throw StateError('Login must wait for recovery confirmation');
  }

  @override
  void enableEncryptionWithKey(Uint8List key, Uint8List salt) {
    encryptionCalls++;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    SecureClipboard.cancelAutoClear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('cancel does not authorize encryption', (tester) async {
    bool? accepted;
    await tester.pumpWidget(_recoveryHost((value) => accepted = value));
    await tester.tap(find.text('Open recovery'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byKey(_confirm)).onPressed, isNull);
    await tester.tap(find.byKey(_cancel));
    await tester.pumpAndSettle();
    expect(accepted, isFalse);
  });

  testWidgets('requires the exact 24 words and accepts normalized re-entry', (
    tester,
  ) async {
    bool? accepted;
    await tester.pumpWidget(_recoveryHost((value) => accepted = value));
    await tester.tap(find.text('Open recovery'));
    await tester.pumpAndSettle();
    final phrase = tester.widget<Text>(find.byKey(_phrase)).data!;
    expect(phrase.split(' '), hasLength(24));
    final otherPhrase = EncryptionService.generateMnemonic(
      Uint8List.fromList(List.filled(32, 1)),
      Uint8List(16),
    )['mnemonic']!;
    for (final wrong in [
      otherPhrase,
      phrase.split(' ').take(23).join(' '),
      '$phrase abandon',
    ]) {
      await tester.enterText(find.byKey(_confirmation), wrong);
      await tester.pump();
      expect(tester.widget<FilledButton>(find.byKey(_confirm)).onPressed, isNull);
      expect(accepted, isNull);
    }
    await tester.enterText(
      find.byKey(_confirmation),
      ' \n${phrase.toUpperCase().split(' ').join(' \t\n')}\t ',
    );
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byKey(_confirm)).onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(_confirm));
    await tester.pumpAndSettle();
    expect(accepted, isTrue);

    // Existing nonce | ciphertext | tag, independently verified with Python
    // cryptography AESGCM: zero 256-bit key, zero 96-bit nonce, 16 zero bytes.
    // Recovering the displayed phrase needs neither the old session nor salt.
    const existingHex =
        '000000000000000000000000'
        'cea7403d4d606b6e074ec5d3baf39d18'
        'd0d1c8a799996bf0265b98b5d48ab919';
    final existing = Uint8List.fromList([
      for (var i = 0; i < existingHex.length; i += 2)
        int.parse(existingHex.substring(i, i + 2), radix: 16),
    ]);
    final restoredKey = EncryptionService.recoverKeyFromMnemonic(phrase);
    expect(EncryptionService.decrypt(existing, restoredKey), Uint8List(16));
  });

  testWidgets('copy exports the phrase but does not confirm the backup', (
    tester,
  ) async {
    String? clipboard;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
    await tester.pumpWidget(_recoveryHost((_) {}));
    await tester.tap(find.text('Open recovery'));
    await tester.pumpAndSettle();
    final phrase = tester.widget<Text>(find.byKey(_phrase)).data!;
    await tester.tap(find.byKey(const Key('file_encryption_recovery_copy')));
    await tester.pumpAndSettle();
    expect(clipboard, phrase);
    expect(tester.widget<FilledButton>(find.byKey(_confirm)).onPressed, isNull);
    await tester.tap(find.byKey(_cancel));
    await tester.pumpAndSettle();
    SecureClipboard.cancelAutoClear();
  });

  testWidgets('empty selected passphrase stops before authentication', (
    tester,
  ) async {
    var authReads = 0;
    await tester.pumpWidget(
      _connectionHost(InMemorySecureStorage(), [
        authProvider.overrideWith((ref) {
          authReads++;
          throw StateError('Authentication must not start');
        }),
      ]),
    );
    await tester.tap(find.text('Open connection'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(_toggle));
    await tester.tap(find.byKey(_toggle));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(_passphrase), '   ');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Connect'));
    await tester.pumpAndSettle();
    expect(authReads, 0);
    expect(
      find.text('Enter a passphrase before enabling file encryption.'),
      findsOneWidget,
    );
    expect(find.byType(FileEncryptionRecoveryDialog), findsNothing);
  });

  testWidgets('connection cancellation stops after 2FA and before login', (
    tester,
  ) async {
    final storage = InMemorySecureStorage();
    late _RecordingAuth auth;
    await tester.pumpWidget(
      _connectionHost(storage, [
        authProvider.overrideWith((ref) => auth = _RecordingAuth(ref, storage)),
      ]),
    );
    await tester.tap(find.text('Open connection'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'test@example.invalid');
    await tester.ensureVisible(find.byKey(_toggle));
    await tester.tap(find.byKey(_toggle));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(_passphrase), 'a test-only passphrase');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Connect'));
    // The underlying connection dialog deliberately remains busy while the
    // recovery dialog is open, so its progress animation cannot settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(FileEncryptionRecoveryDialog), findsOneWidget);
    expect(auth.preflight.twoFactorChecks, 1);
    expect(auth.loginCalls, 0);
    expect(auth.encryptionCalls, 0);
    await tester.tap(find.byKey(_cancel));
    await tester.pumpAndSettle();
    expect(auth.loginCalls, 0);
    expect(auth.encryptionCalls, 0);
    expect(auth.isEncryptionEnabled, isFalse);
    expect(
      tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Connect'),
      ).onPressed,
      isNotNull,
    );
  });

  testWidgets('delegated providers hide and reset generic encryption setup', (
    tester,
  ) async {
    await tester.pumpWidget(
      _connectionHost(InMemorySecureStorage(), const []),
    );
    await tester.tap(find.text('Open connection'));
    await tester.pumpAndSettle();
    final providerField = find.byType(DropdownButtonFormField<CloudProvider>);
    for (final provider in [CloudProvider.azure, CloudProvider.b2]) {
      await tester.ensureVisible(find.byKey(_toggle));
      await tester.tap(find.byKey(_toggle));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_passphrase), 'discarded setup secret');
      tester.widget<DropdownButtonFormField<CloudProvider>>(providerField)
          .onChanged!(provider);
      await tester.pumpAndSettle();
      expect(find.byKey(_toggle), findsNothing);
      expect(find.byKey(_passphrase), findsNothing);
      expect(find.textContaining('configured separately'), findsOneWidget);
      tester.widget<DropdownButtonFormField<CloudProvider>>(providerField)
          .onChanged!(CloudProvider.filen);
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(find.byKey(_toggle)).value, isFalse);
      expect(find.byKey(_passphrase), findsNothing);
      await tester.ensureVisible(find.byKey(_toggle));
      await tester.tap(find.byKey(_toggle));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byKey(_passphrase)).controller!.text,
        isEmpty,
      );
      await tester.tap(find.byKey(_toggle));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('all recovery and active-key messages cover all nine locales', (
    tester,
  ) async {
    const keys = [
      'fileEncryptionDelegated',
      'fileRecoveryTitle',
      'fileRecoveryWarning',
      'fileRecoveryConfirm',
      'fileRecoveryConfirmHelp',
      'fileRecoveryMismatch',
      'fileRecoveryContinue',
      'fileRecoveryCopyFailed',
      'passphraseRequired',
      'encryptionAlreadyEnabled',
    ];
    final translations = {for (final key in keys) key: <String>{}};
    for (final locale in AppLocalizations.supportedLocales) {
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) {
              final strings = KeyManagementStrings(context);
              for (final key in keys) {
                final value = strings.text(key);
                expect(value.trim(), isNotEmpty, reason: '${locale.languageCode}: $key');
                translations[key]!.add(value);
              }
              return const SizedBox.shrink();
            },
          ),
          locale: locale,
        ),
      );
      await tester.pumpAndSettle();
    }
    expect(AppLocalizations.supportedLocales, hasLength(9));
    for (final entry in translations.entries) {
      expect(entry.value, hasLength(9), reason: '${entry.key} must not fall back to English');
    }
  });
}
