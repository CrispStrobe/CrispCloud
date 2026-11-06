import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/terminal_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('SSH host trust message retains host and fingerprint', (
    tester,
  ) async {
    for (final locale in AppLocalizations.supportedLocales) {
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Builder(
            builder: (context) => Text(
              TerminalStrings(context).trust('example.test:22', 'SHA256:abc'),
            ),
          ),
        ),
      );
      expect(find.textContaining('example.test:22'), findsOneWidget);
      expect(find.textContaining('SHA256:abc'), findsOneWidget);
      expect(find.textContaining('{fingerprint}'), findsNothing);
    }
  });

  testWidgets(
    'emulator chrome uses the selected locale, including the built-in shell',
    (tester) async {
      for (final locale in AppLocalizations.supportedLocales) {
        final labels = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: Builder(
              builder: (context) {
                labels
                  ..clear()
                  ..add(context.terminalTr('Sandbox shell'))
                  ..add(context.terminalTr('Copy selection'))
                  ..add(context.terminalTr('Enter a port from 1 to 65535'));
                return Text(labels.join('\n'));
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(labels, hasLength(3));
        expect(labels.every((label) => label.isNotEmpty), isTrue);
        if (locale.languageCode != 'en') {
          expect(labels[0], isNot('Sandbox shell'), reason: locale.toString());
          expect(labels[1], isNot('Copy selection'), reason: locale.toString());
          expect(
            labels[2],
            isNot('Enter a port from 1 to 65535'),
            reason: locale.toString(),
          );
        }
        expect(labels[2], contains('65535'));
      }
    },
  );
}
