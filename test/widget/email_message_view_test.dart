import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/services/email_message_service.dart';
import 'package:crisp_cloud/widgets/email_message_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'shows message and opens original attachment bytes through host',
    (tester) async {
      final attachment = EmailAttachment(
        name: 'hello.txt',
        contentType: 'text/plain',
        bytes: Uint8List.fromList([72, 105]),
      );
      EmailAttachment? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmailMessageView(
              message: EmailMessageDocument(
                subject: 'Project note',
                from: 'author@example.test',
                to: 'reader@example.test',
                cc: '',
                bcc: '',
                date: '12 Nov 2026',
                plainText: 'Message contents',
                safeHtml: null,
                attachments: [attachment],
                warnings: const [],
              ),
              onOpenAttachment: (value) => opened = value,
            ),
          ),
        ),
      );
      expect(find.text('Project note'), findsOneWidget);
      expect(find.text('author@example.test'), findsOneWidget);
      expect(find.text('Message contents'), findsOneWidget);
      await tester.tap(find.byTooltip('Open attachment'));
      expect(opened, same(attachment));
    },
  );

  testWidgets('German labels and formatting-only HTML work without images', (
    tester,
  ) async {
    final message = parseEmailMessage(
      Uint8List.fromList(
        utf8.encode(
          'Subject: Beispiel\nFrom: sender@example.test\nContent-Type: text/html; charset=utf-8\n\n'
          '<p>Hello <strong>world</strong></p><img src="https://tracker.test/pixel">',
        ),
      ),
      'html.eml',
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(body: EmailMessageView(message: message)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Von'), findsOneWidget);
    expect(find.text('Formatiert'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    await tester.tap(find.text('Text'));
    await tester.pump();
    expect(find.text('Hello world'), findsOneWidget);
  });
}
