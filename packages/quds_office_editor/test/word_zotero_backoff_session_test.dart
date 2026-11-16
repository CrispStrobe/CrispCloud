import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

ZoteroHttpResponse _limited() => ZoteroHttpResponse(
  statusCode: 429,
  body: '',
  headers: {'Retry-After': '3600'},
);

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<WordEditorController> _open(
  WidgetTester tester, {
  required ZoteroSession session,
  required ZoteroTransport transport,
  ZoteroTransport? localTransport,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1280, 1100);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final controller = WordEditorController(
    document: WmlDocument.empty(text: 'Unchanged document'),
  );
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showWordZoteroDialog(
              context,
              controller: controller,
              session: session,
              transport: transport,
              localTransport: localTransport,
            ),
            child: const Text('Open references'),
          ),
        ),
      ),
    ),
  );
  await _tap(tester, find.text('Open references'));
  return controller;
}

Future<void> _connect(WidgetTester tester) =>
    _tap(tester, find.widgetWithText(FilledButton, 'Connect'));

Future<void> _publicLibrary(WidgetTester tester, String id) async {
  await _tap(tester, find.text('Open a library by ID'));
  final field = find.byWidgetPredicate(
    (widget) =>
        widget is TextField &&
        widget.decoration?.labelText == 'Numeric library ID',
  );
  await tester.ensureVisible(field);
  await tester.enterText(field, id);
  await _tap(tester, find.text('Open library'));
}

void _expectKept(WidgetTester tester, WordEditorController controller) {
  expect(controller.document.paragraphs.single.text, 'Unchanged document');
  expect(controller.canUndo, isFalse);
  expect(controller.zoteroFields, isEmpty);
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('reconnecting and reopening keep an online session pause', (
    tester,
  ) async {
    final requests = <ZoteroHttpRequest>[];
    final session = ZoteroSession()..apiKey = 'test-session-key';
    final controller = await _open(
      tester,
      session: session,
      transport: (request) async {
        requests.add(request);
        return _limited();
      },
    );
    await _connect(tester);
    expect(requests, hasLength(1));
    expect(find.textContaining('Zotero is limiting requests'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('zotero-api-key')),
      'another-session-key',
    );
    await tester.pumpAndSettle();
    await _connect(tester);
    expect(requests, hasLength(1));
    expect(find.textContaining('Zotero requested a pause'), findsOneWidget);
    await _tap(tester, find.byTooltip('Close Zotero'));
    await _tap(tester, find.text('Open references'));
    await _connect(tester);
    expect(requests, hasLength(1));
    expect(find.textContaining('Zotero requested a pause'), findsOneWidget);
    _expectKept(tester, controller);
  });

  testWidgets(
    'disconnect and public library switching do not discard backoff',
    (tester) async {
      final requests = <ZoteroHttpRequest>[];
      final session = ZoteroSession()..apiKey = 'test-session-key';
      final controller = await _open(
        tester,
        session: session,
        transport: (request) async {
          requests.add(request);
          return _limited();
        },
      );
      await _connect(tester);
      await _tap(tester, find.text('Disconnect & forget'));
      expect(session.apiKey, isNull);
      await _publicLibrary(tester, '77');
      expect(requests, hasLength(1));
      expect(find.textContaining('Zotero requested a pause'), findsOneWidget);
      _expectKept(tester, controller);
    },
  );

  testWidgets('desktop works during online backoff and does not clear it', (
    tester,
  ) async {
    var onlineRequests = 0;
    final localRequests = <ZoteroHttpRequest>[];
    final session = ZoteroSession()..apiKey = 'test-session-key';
    final controller = await _open(
      tester,
      session: session,
      transport: (_) async {
        onlineRequests++;
        return _limited();
      },
      localTransport: (request) async {
        localRequests.add(request);
        expect(request.uri.host, 'localhost');
        expect(request.headers['Zotero-API-Key'], isNull);
        return ZoteroHttpResponse(
          statusCode: 200,
          body: request.uri.path == '/api/' ? 'Local API' : '[]',
          headers: {
            'Zotero-API-Version': '3',
            'Zotero-Server-ID': 'independent-desktop',
          },
        );
      },
    );
    await _connect(tester);
    await _tap(tester, find.byKey(const ValueKey('zotero-library-source')));
    await _tap(tester, find.text('Zotero desktop (this computer)').last);
    await _tap(tester, find.byKey(const ValueKey('zotero-connect-desktop')));
    expect(localRequests, hasLength(4));
    expect(find.textContaining('Connected to Zotero desktop'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('zotero-library-source')));
    await _tap(tester, find.text('Online Zotero library').last);
    await _connect(tester);
    expect(onlineRequests, 1);
    expect(find.textContaining('Zotero requested a pause'), findsOneWidget);
    _expectKept(tester, controller);
  });

  testWidgets(
    'a response after closing the dialog still pauses the same session',
    (tester) async {
      var requests = 0;
      final response = Completer<ZoteroHttpResponse>();
      final session = ZoteroSession()..apiKey = 'test-session-key';
      final controller = await _open(
        tester,
        session: session,
        transport: (_) {
          requests++;
          return response.future;
        },
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
      await tester.pump();
      expect(requests, 1);
      await _tap(tester, find.byTooltip('Close Zotero'));
      await _tap(tester, find.text('Open references'));
      response.complete(_limited());
      await tester.pumpAndSettle();
      await _connect(tester);
      expect(requests, 1);
      expect(find.textContaining('Zotero requested a pause'), findsOneWidget);
      _expectKept(tester, controller);
    },
  );

  testWidgets('successful Backoff survives public library recreation', (
    tester,
  ) async {
    var requests = 0;
    final controller = await _open(
      tester,
      session: ZoteroSession(),
      transport: (_) async {
        requests++;
        return ZoteroHttpResponse(
          statusCode: 200,
          body: '[]',
          headers: {'Backoff': '3600'},
        );
      },
    );
    await _publicLibrary(tester, '77');
    expect(requests, 1);
    // The first collection response is valid, but its Backoff prevents the
    // following item request. Reopening another public library must not reset it.
    final field = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'Numeric library ID',
    );
    await tester.enterText(field, '88');
    await _tap(tester, find.text('Open library'));
    expect(requests, 1);
    expect(find.textContaining('Zotero requested a pause'), findsOneWidget);
    _expectKept(tester, controller);
  });
}
