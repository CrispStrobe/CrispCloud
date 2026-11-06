import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/sftp_operation_strings.dart';
import 'package:crisp_cloud/l10n/sftp_key_strings.dart';
import 'package:crisp_cloud/services/sftp_client_adapter.dart';
import 'package:crisp_cloud/services/sftp_operation_failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SFTP form builds IPv6 and WebSocket bridge identities safely', () {
    expect(SFTPClientAdapter.identityFromFields(
      username: ' user ', host: '2001:db8::1', port: 2222),
      'user@[2001:db8::1]:2222');
    expect(SFTPClientAdapter.identityFromFields(
      username: 'user', host: '[2001:db8::1]', port: 22),
      'user@[2001:db8::1]:22');
    expect(SFTPClientAdapter.identityFromFields(
      username: 'user', host: 'wss://bridge.example/ssh', port: 443, web: true),
      'user@wss://bridge.example:443/ssh');
    expect(SFTPClientAdapter.webSocketEndpoint('2001:db8::1', 2222).toString(),
        'wss://[2001:db8::1]:2222');
    expect(SFTPClientAdapter.webSocketEndpoint('wss://bridge.example:443/ssh', 443).path,
        '/ssh');
    expect(() => SFTPClientAdapter.identityFromFields(
      username: 'user', host: 'bad host', port: 22), throwsFormatException);
  });
  test('invalid SFTP identity retains legacy exception text', () async {
    final adapter = SFTPClientAdapter(config: null);
    await expectLater(adapter.login('invalid', 'password'), throwsA(
      isA<SftpOperationException>()
          .having((e) => e.code, 'code', SftpOperationCode.invalidIdentity)
          .having((e) => e.toString(), 'legacy text',
              'Exception: Format must be user@host (e.g. u12345@u123.your-storagebox.de)'),
    ));
    expect(SftpOperationFormatException(SftpOperationCode.invalidAddress,
        'Invalid SFTP server address'), isA<FormatException>());
  });
  test('invalid private key never leaks its contents in the error', () async {
    final adapter = SFTPClientAdapter(config: null);
    await expectLater(
      adapter.loginWithPrivateKey('reader@example.com:22', 'SECRET_BAD_KEY', 'SECRET_PASSPHRASE'),
      throwsA(isA<SftpOperationFormatException>()
          .having((e) => e.code, 'code', SftpOperationCode.invalidPrivateKey)
          .having((e) => e.toString(), 'message', isNot(contains('SECRET')))),
    );
  });
  testWidgets('private key labels and failures are available in all languages', (tester) async {
    for (final locale in AppLocalizations.supportedLocales) {
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(builder: (context) {
          final s = SftpKeyStrings(context);
          return SingleChildScrollView(child: Column(children: [
            Text(s.authentication), Text(s.password), Text(s.privateKey),
            Text(s.chooseKey), Text(s.keySelected), Text(s.passphrase),
            Text(s.storageHelp), Text(s.keyRequired), Text(s.invalidKey), Text(s.readFailed),
          ]));
        }),
      ));
      expect(tester.takeException(), isNull);
      expect(find.byType(Text), findsNWidgets(10));
    }
  });
  testWidgets('list errors retain path and external detail in every locale', (tester) async {
    final failure = SftpOperationException(SftpOperationCode.listFailed,
        'Failed to list path /docs: denied', {'path': '/docs', 'error': 'denied'});
    for (final locale in AppLocalizations.supportedLocales) {
      await tester.pumpWidget(MaterialApp(
        locale: locale, supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(builder: (context) => Text(localizedSftpOperationError(context, failure))),
      ));
      expect(find.textContaining('/docs'), findsOneWidget);
      expect(find.textContaining('denied'), findsOneWidget);
      expect(find.textContaining('{path}'), findsNothing);
    }
  });
}
