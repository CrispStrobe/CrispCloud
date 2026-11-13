import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/mbox_viewer_strings.dart';
import 'package:crisp_cloud/services/email_message_service.dart';
import 'package:crisp_cloud/services/mbox_message_service.dart';
import 'package:crisp_cloud/widgets/email_message_view.dart';
import 'package:crisp_cloud/widgets/mbox_message_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

MboxDocument _mailbox(List<String> subjects) => parseMboxDocument(
  Uint8List.fromList(
    utf8.encode(
      subjects
          .map(
            (subject) =>
                'From sender@example.test Fri Nov 13 12:34:56 2026\n'
                'Subject: $subject\nFrom: sender@example.test\n\nBody of $subject\n',
          )
          .join(),
    ),
  ),
);

Widget _host(
  MboxDocument document, {
  Locale locale = const Locale('en'),
  double textScale = 1,
  VoidCallback? onShowSource,
  ValueChanged<int>? onSelected,
  ValueChanged<EmailAttachment>? onOpenAttachment,
}) {
  var selected = 0;
  return MaterialApp(
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      body: StatefulBuilder(
        builder: (context, setState) {
          EmailMessageDocument? message;
          MboxMessageError? error;
          if (document.messages.isNotEmpty) {
            try {
              message = document.parseMessage(selected);
            } on MboxMessageException catch (failure) {
              error = failure.code;
            }
          }
          return MboxMessageView(
            document: document,
            selectedIndex: selected,
            message: message,
            messageError: error,
            onSelectMessage: (index) {
              setState(() => selected = index);
              onSelected?.call(index);
            },
            onShowSource: onShowSource ?? () {},
            onOpenAttachment: onOpenAttachment,
          );
        },
      ),
    ),
  );
}

void main() {
  testWidgets('navigates all messages and resets the selected message view', (
    tester,
  ) async {
    final selected = <int>[];
    await tester.pumpWidget(
      _host(_mailbox(['First', 'Second', 'Third']), onSelected: selected.add),
    );
    expect(find.text('Message 1 of 3'), findsOneWidget);
    expect(find.text('Body of First\n'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('mbox-previous')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey('mbox-next')));
    await tester.pump();
    expect(find.text('Body of Second\n'), findsOneWidget);
    expect(find.text('Body of First\n'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('mbox-next')));
    await tester.pump();
    expect(find.text('Message 3 of 3'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('mbox-next')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey('mbox-previous')));
    await tester.pump();
    expect(selected, [1, 2, 1]);
    expect(find.byType(EmailMessageView), findsOneWidget);
  });

  testWidgets('searchable chooser reaches the last of 1000 messages', (
    tester,
  ) async {
    final document = _mailbox(
      List.generate(1000, (index) => 'Message number $index'),
    );
    await tester.pumpWidget(_host(document));
    await tester.tap(find.byKey(const ValueKey('mbox-choose')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('mbox-message-search')),
      'number 999',
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('mbox-entry-999')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mbox-entry-999')));
    await tester.pumpAndSettle();
    expect(find.text('Message 1000 of 1000'), findsOneWidget);
    expect(find.text('Body of Message number 999\n'), findsOneWidget);
  });

  testWidgets('a chooser from a replaced mailbox cannot select a stale index', (
    tester,
  ) async {
    var document = _mailbox(['Old first', 'Old second']);
    late StateSetter updateHost;
    final selections = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              updateHost = setState;
              return MboxMessageView(
                document: document,
                selectedIndex: 0,
                message: document.parseMessage(0),
                onSelectMessage: selections.add,
                onShowSource: () {},
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('mbox-choose')));
    await tester.pumpAndSettle();
    updateHost(() => document = _mailbox(['Replacement']));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mbox-entry-1')));
    await tester.pumpAndSettle();
    expect(selections, isEmpty);
    expect(find.text('Body of Replacement\n'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'malformed selected message leaves later entries and source usable',
    (tester) async {
      final document = parseMboxDocument(
        Uint8List.fromList(
          utf8.encode(
            'From sender@example.test Fri Nov 13 12:34:56 2026\n'
            'Subject: broken\nContent-Type: multipart/mixed\n\nBad\n'
            '${utf8.decode(_mailbox(['Good']).sourceBytes)}',
          ),
        ),
      );
      var sourceOpened = false;
      await tester.pumpWidget(
        _host(document, onShowSource: () => sourceOpened = true),
      );
      expect(find.textContaining('This message is malformed'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mbox-source')));
      expect(sourceOpened, isTrue);
      await tester.tap(find.byKey(const ValueKey('mbox-next')));
      await tester.pump();
      expect(find.text('Body of Good\n'), findsOneWidget);
    },
  );

  testWidgets(
    'attachment callbacks preserve bytes and do not load remote HTML',
    (tester) async {
      final document = parseMboxDocument(
        Uint8List.fromList(
          utf8.encode(
            'From sender@example.test Fri Nov 13 12:34:56 2026\n'
            'Subject: attachment\nContent-Type: multipart/mixed; boundary=x\n\n'
            '--x\nContent-Type: text/html\n\n<p>Body</p><img src="https://tracker.test/a">\n'
            '--x\nContent-Type: application/octet-stream\n'
            'Content-Disposition: attachment; filename="a.bin"\n'
            'Content-Transfer-Encoding: base64\n\nAP8=\n--x--\n',
          ),
        ),
      );
      EmailAttachment? opened;
      await tester.pumpWidget(
        _host(document, onOpenAttachment: (value) => opened = value),
      );
      expect(find.byType(Image), findsNothing);
      await tester.tap(find.byTooltip('Open attachment'));
      expect(opened?.name, 'a.bin');
      expect(opened?.bytes, orderedEquals([0, 255]));
    },
  );

  testWidgets(
    'empty mailbox offers source without enabled message navigation',
    (tester) async {
      var opened = false;
      await tester.pumpWidget(
        _host(
          parseMboxDocument(Uint8List(0)),
          onShowSource: () => opened = true,
        ),
      );
      expect(find.text('This mailbox is empty.'), findsOneWidget);
      expect(find.text('Message 0 of 0'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('mbox-choose')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('mbox-source')));
      expect(opened, isTrue);
    },
  );

  testWidgets('length-delimited quoting policy is disclosed', (tester) async {
    const body = '>From preserved';
    final document = parseMboxDocument(
      Uint8List.fromList(
        utf8.encode(
          'From sender@example.test Fri Nov 13 12:34:56 2026\n'
          'Subject: quoted\nContent-Length: ${body.length}\n\n$body',
        ),
      ),
    );
    await tester.pumpWidget(_host(document));
    expect(find.text(body), findsOneWidget);
    expect(
      find.textContaining('length-delimited mailbox variant'),
      findsOneWidget,
    );
  });

  testWidgets(
    'narrow high-text-scale layout remains scrollable without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(360, 280);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        _host(
          _mailbox(['A long subject that can wrap in a small window']),
          textScale: 2.4,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('mbox-source')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('mbox-choose')));
      await tester.tap(find.byKey(const ValueKey('mbox-choose')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('mbox-message-search')), findsOneWidget);
    },
  );

  testWidgets('all supported locales provide mailbox labels and typed errors', (
    tester,
  ) async {
    for (final locale in AppLocalizations.supportedLocales) {
      await tester.pumpWidget(_host(_mailbox(['One']), locale: locale));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(MboxMessageView));
      final strings = MboxViewerStrings(context);
      expect(find.text(strings.position(1, 1)), findsOneWidget);
      for (final error in MboxPreviewError.values) {
        expect(strings.previewError(error), isNotEmpty);
      }
      for (final error in MboxMessageError.values) {
        expect(strings.messageError(error), isNotEmpty);
      }
      expect(strings.text('sourceChanged'), isNotEmpty);
      expect(tester.takeException(), isNull);
    }
  });
}
