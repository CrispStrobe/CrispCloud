import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/biometric_strings.dart';
import 'package:crisp_cloud/services/app_lock_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';

class _FakeAuth extends LocalAuthentication {
  String? reason;
  @override
  Future<bool> authenticate({required String localizedReason,
      Iterable<dynamic> authMessages = const <dynamic>[],
      AuthenticationOptions options = const AuthenticationOptions()}) async {
    reason = localizedReason;
    return true;
  }
}

void main() {
  test('native authentication receives the requested localized reason', () async {
    final fake = _FakeAuth();
    final service = AppLockService(InMemorySecureStorage(), localAuth: fake);
    expect(await service.authenticateWithBiometric(localizedReason: 'Desbloquear CrispCloud'), isTrue);
    expect(fake.reason, 'Desbloquear CrispCloud');
  });
  testWidgets('biometric names follow locale while platform brands remain intact', (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('es'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(builder: (context) => Column(children: [
        Text(BiometricStrings(context).label('Fingerprint')),
        Text(BiometricStrings(context).label('Windows Hello')),
        Text(BiometricStrings(context).label('Face ID')),
      ])),
    ));
    expect(find.text('Huella digital'), findsOneWidget);
    expect(find.text('Windows Hello'), findsOneWidget);
    expect(find.text('Face ID'), findsOneWidget);
  });
}
