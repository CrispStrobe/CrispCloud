import 'package:crisp_cloud/l10n/ftp_security_strings.dart';
import 'package:crisp_cloud/services/ftp_security_mode.dart';
import 'package:crisp_cloud/widgets/ftp_security_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all supported locales include security modes and validation', () {
    final messages = FtpSecurityStrings.translations;
    expect(messages.keys.toSet(), {
      'en',
      'de',
      'fr',
      'es',
      'pt',
      'ar',
      'ja',
      'ko',
      'zh',
    });
    for (final language in messages.values) {
      expect(language.keys.toSet(), messages['en']!.keys.toSet());
      expect(language.values.every((text) => text.trim().isNotEmpty), isTrue);
    }
  });

  testWidgets('explicit, implicit and plaintext modes can be selected', (
    tester,
  ) async {
    var selected = FtpSecurityMode.explicitTls;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => FtpSecurityField(
              value: selected,
              onChanged: (mode) => setState(() => selected = mode),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Explicit TLS (FTPES)'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<FtpSecurityMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Implicit TLS (FTPS)').last);
    await tester.pumpAndSettle();
    expect(selected, FtpSecurityMode.implicitTls);
    await tester.tap(find.byType(DropdownButtonFormField<FtpSecurityMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FTP · unencrypted').last);
    await tester.pumpAndSettle();
    expect(selected, FtpSecurityMode.plain);
  });

  testWidgets('restoring a saved mode updates the form selection', (
    tester,
  ) async {
    Widget form(FtpSecurityMode mode) => MaterialApp(
      home: Scaffold(
        body: FtpSecurityField(value: mode, onChanged: (_) {}),
      ),
    );
    await tester.pumpWidget(form(FtpSecurityMode.explicitTls));
    await tester.pumpWidget(form(FtpSecurityMode.implicitTls));
    expect(find.text('Implicit TLS (FTPS)'), findsOneWidget);
    expect(find.text('Explicit TLS (FTPES)'), findsNothing);
  });
}
