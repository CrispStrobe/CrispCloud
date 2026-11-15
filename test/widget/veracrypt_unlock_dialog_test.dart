import 'dart:async';
import 'dart:typed_data';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/services/veracrypt_service.dart';
import 'package:crisp_cloud/widgets/veracrypt_unlock_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _dialog(
  WidgetTester tester, {
  required ValueChanged<VeraCryptCredentials?> onResult,
  VeraCryptKeyfilePicker? pickKeyfiles,
  bool trueCryptMode = false,
  bool allowArgon2id = true,
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              final result = await showDialog<VeraCryptCredentials>(
                context: context,
                builder: (_) => VeraCryptUnlockDialog(
                  name: 'private.vc',
                  trueCryptMode: trueCryptMode,
                  allowArgon2id: allowArgon2id,
                  pickKeyfiles: pickKeyfiles,
                ),
              );
              onResult(result);
            },
            child: const Text('Start'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Start'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('password whitespace and explicit PIM survive one attempt', (
    tester,
  ) async {
    VeraCryptCredentials? result;
    await _dialog(tester, onResult: (value) => result = value);
    await tester.enterText(
      find.byKey(const ValueKey('veracrypt-password')),
      '  secret\t ',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('veracrypt-pim')));
    await tester.enterText(find.byKey(const ValueKey('veracrypt-pim')), '7');
    await tester.tap(find.byKey(const ValueKey('veracrypt-open')));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.password, '  secret\t ');
    expect(result!.options.pim, 7);
    expect(result!.options.kdf, VeraCryptKdf.auto);
    expect(result.toString(), isNot(contains('secret')));
    result!.dispose();
    expect(() => result!.password, throwsStateError);
  });

  testWidgets('keyfile-only unlock transfers a copy and clears dialog bytes', (
    tester,
  ) async {
    final selected = Uint8List.fromList([11, 42, 93]);
    VeraCryptCredentials? result;
    await _dialog(
      tester,
      onResult: (value) => result = value,
      pickKeyfiles: () async => [
        VeraCryptKeyfile(name: 'unlock.key', bytes: selected),
      ],
    );
    final keyfiles = find.byKey(const ValueKey('veracrypt-keyfiles'));
    await tester.ensureVisible(keyfiles);
    await tester.tap(keyfiles);
    await tester.pumpAndSettle();
    expect(find.text('unlock.key'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('veracrypt-open')));
    await tester.pumpAndSettle();
    expect(result!.password, isEmpty);
    expect(result!.options.keyfiles.single, [11, 42, 93]);
    expect(selected, [0, 0, 0]);
    result!.dispose();
    expect(result!.options.keyfiles.single, [0, 0, 0]);
  });

  testWidgets('cancelled keyfile selection clears a late picker result', (
    tester,
  ) async {
    final pending = Completer<List<VeraCryptKeyfile>?>();
    final selected = Uint8List.fromList([1, 2, 3]);
    var receivedResult = false;
    await _dialog(
      tester,
      onResult: (value) {
        expect(value, isNull);
        receivedResult = true;
      },
      pickKeyfiles: () => pending.future,
    );
    final keyfiles = find.byKey(const ValueKey('veracrypt-keyfiles'));
    await tester.ensureVisible(keyfiles);
    await tester.tap(keyfiles);
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    pending.complete([VeraCryptKeyfile(name: 'late.key', bytes: selected)]);
    await tester.pumpAndSettle();
    expect(receivedResult, isTrue);
    expect(selected, [0, 0, 0]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TrueCrypt hides PIM and incompatible KDF choices', (
    tester,
  ) async {
    await _dialog(tester, onResult: (_) {}, trueCryptMode: true);
    expect(find.byKey(const ValueKey('veracrypt-pim')), findsNothing);
    final selector = find.byKey(const ValueKey('veracrypt-kdf-true'));
    await tester.ensureVisible(selector);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    expect(find.text('Argon2id'), findsNothing);
    expect(find.text('PBKDF2 / SHA-256'), findsNothing);
    expect(find.text('PBKDF2 / RIPEMD-160'), findsOneWidget);
  });

  testWidgets('unavailable Argon2id is explained and cannot be selected', (
    tester,
  ) async {
    await _dialog(tester, onResult: (_) {}, allowArgon2id: false);
    expect(
      find.text('Argon2id containers require the native app.'),
      findsOneWidget,
    );
    final selector = find.byKey(const ValueKey('veracrypt-kdf-false'));
    await tester.ensureVisible(selector);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    final option = tester.widget<DropdownMenuItem<VeraCryptKdf>>(
      find.widgetWithText(DropdownMenuItem<VeraCryptKdf>, 'Argon2id').last,
    );
    expect(option.enabled, isFalse);
  });

  testWidgets('empty credentials and out-of-range PIM remain in the dialog', (
    tester,
  ) async {
    var returned = false;
    await _dialog(tester, onResult: (_) => returned = true);
    await tester.tap(find.byKey(const ValueKey('veracrypt-open')));
    await tester.pumpAndSettle();
    expect(returned, isFalse);
    expect(find.text('Enter a password or choose keyfiles.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('veracrypt-password')),
      'password',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('veracrypt-pim')));
    await tester.enterText(
      find.byKey(const ValueKey('veracrypt-pim')),
      '2147469',
    );
    await tester.tap(find.byKey(const ValueKey('veracrypt-open')));
    await tester.pumpAndSettle();
    expect(returned, isFalse);
    expect(find.text('Enter a PIM from 0 to 2147468.'), findsOneWidget);
  });

  testWidgets('German controls remain reachable in a narrow dialog', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _dialog(tester, onResult: (_) {}, locale: const Locale('de'));
    expect(find.text('Verschlüsselten Container öffnen'), findsOneWidget);
    expect(find.text('Schreibgeschützt öffnen'), findsOneWidget);
    final keyfiles = find.byKey(const ValueKey('veracrypt-keyfiles'));
    await tester.ensureVisible(keyfiles);
    await tester.pumpAndSettle();
    expect(find.text('Schlüsseldateien hinzufügen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('format-valid excessive PIM is stopped before submitting work', (
    tester,
  ) async {
    var returned = false;
    await _dialog(tester, onResult: (_) => returned = true);
    await tester.enterText(
      find.byKey(const ValueKey('veracrypt-password')),
      'password',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('veracrypt-pim')));
    await tester.enterText(find.byKey(const ValueKey('veracrypt-pim')), '5000');
    await tester.pump();
    expect(
      find.text('PBKDF2: up to 5015000 iterations per hash.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('veracrypt-open')));
    await tester.pumpAndSettle();
    expect(returned, isFalse);
    expect(
      find.text('This PIM exceeds the bundled reader work limit.'),
      findsOneWidget,
    );
  });

  test(
    'keyfile reader cancels after the format-defined one-MiB prefix',
    () async {
      var readTail = false;
      var closed = false;
      Stream<List<int>> stream() async* {
        try {
          yield Uint8List(1024 * 1024)..[0] = 99;
          readTail = true;
          throw StateError('The unused tail must not be requested.');
        } finally {
          closed = true;
        }
      }

      final bytes = await readVeraCryptKeyfilePrefix(stream());
      expect(bytes.length, 1024 * 1024);
      expect(bytes.first, 99);
      expect(readTail, isFalse);
      expect(closed, isTrue);
    },
  );

  test('empty keyfiles are refused and stream errors are propagated', () async {
    await expectLater(
      readVeraCryptKeyfilePrefix(const Stream<List<int>>.empty()),
      throwsFormatException,
    );
    await expectLater(
      readVeraCryptKeyfilePrefix(Stream<List<int>>.error(StateError('gone'))),
      throwsStateError,
    );
  });
}
