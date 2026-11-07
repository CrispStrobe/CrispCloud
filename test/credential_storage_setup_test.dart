import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/services/credential_storage_config.dart';
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

      await tester.enterText(fields.at(0), 'correct horse battery staple');
      await tester.enterText(fields.at(1), 'correct horse battery staple');
      await tester.tap(find.byKey(const ValueKey('credential-setup-continue')));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.mode, CredentialStorageMode.encryptedFile);
      expect(result!.masterPassword, 'correct horse battery staple');
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
    await tester.tap(find.byKey(const ValueKey('credential-setup-continue')));
    await tester.pumpAndSettle();

    expect(result, isNull);
    expect(find.text('Master passwords do not match.'), findsOneWidget);
  });
}
