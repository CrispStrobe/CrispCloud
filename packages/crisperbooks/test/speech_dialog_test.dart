import 'dart:async';

import 'package:crisperbooks/crisperbooks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _SpeechHost {
  final controller = CrispEbookController();
  final calls = <(String, EbookJson)>[];
  String status = 'stopped';
  String voice = 'local-en';
  double rate = 1;
  String reason = '';
  bool requiresGesture = false;
  bool available = true;
  int revision = 0;
  Object? nextError;
  Completer<dynamic>? pendingStart;

  _SpeechHost() {
    controller.attach(_send);
    controller.updateBookInfo(
      const EbookBookInfo(
        title: 'Read-aloud fixture',
        authors: [],
        toc: [],
        sectionCount: 2,
        sourceFormat: 'epub',
      ),
    );
  }

  EbookJson get state => {
    'status': available ? status : 'unavailable',
    'voices': available
        ? [
            {'uri': 'local-en', 'name': 'English', 'language': 'en-US'},
            {'uri': 'local-de', 'name': 'Deutsch', 'language': 'de-DE'},
          ]
        : [],
    'voiceUri': voice,
    'rate': rate,
    'reason': reason,
    'requiresGesture': requiresGesture,
    'revision': ++revision,
  };

  Future<dynamic> _send(String method, EbookJson args) async {
    calls.add((method, args));
    final error = nextError;
    nextError = null;
    if (error != null) throw error;
    if (method == 'speechStart' && pendingStart != null) {
      return pendingStart!.future;
    }
    switch (method) {
      case 'speechStart':
      case 'speechResume':
        status = 'speaking';
      case 'speechPause':
        status = 'paused';
      case 'speechStop':
        status = 'stopped';
      case 'speechOptions':
        if (status == 'speaking') status = 'paused';
        voice = args['voiceUri'] as String? ?? voice;
        rate = (args['rate'] as num?)?.toDouble() ?? rate;
    }
    return state;
  }
}

Future<void> _open(WidgetTester tester, _SpeechHost host) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => EbookSpeechDialog(
                controller: host.controller,
                translate: (text) => text,
              ),
            ),
            child: const Text('Open controls'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open controls'));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey('ebook-speech-$key'));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'controls follow live state and closing keeps foreground reading',
    (tester) async {
      final host = _SpeechHost();
      addTearDown(host.controller.dispose);
      await _open(tester, host);
      expect(host.calls.single.$1, 'speechStatus');
      expect(find.text('Start reading'), findsOneWidget);

      await _tap(tester, 'primary');
      expect(host.calls.last.$1, 'speechStart');
      expect(find.text('Reading aloud'), findsOneWidget);
      await _tap(tester, 'primary');
      expect(host.calls.last.$1, 'speechPause');
      expect(find.text('Read-aloud paused'), findsOneWidget);
      await _tap(tester, 'primary');
      expect(host.calls.last.$1, 'speechResume');
      await _tap(tester, 'stop');
      expect(host.calls.last.$1, 'speechStop');
      expect(find.text('Ready to read'), findsOneWidget);

      await _tap(tester, 'primary');
      final count = host.calls.length;
      await _tap(tester, 'close');
      expect(find.byType(EbookSpeechDialog), findsNothing);
      expect(host.controller.speech.isActive, isTrue);
      expect(
        host.calls.length,
        count,
        reason: 'The reader owns speech lifetime',
      );
    },
  );

  testWidgets('unavailable voices stay explained and can be refreshed', (
    tester,
  ) async {
    final host = _SpeechHost()..available = false;
    addTearDown(host.controller.dispose);
    await _open(tester, host);
    expect(
      find.text(
        'No locally installed speech voice is available in this reader.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('ebook-speech-primary')),
          )
          .onPressed,
      isNull,
    );
    expect(find.byKey(const ValueKey('ebook-speech-voice')), findsNothing);
    host.available = true;
    await _tap(tester, 'refresh');
    expect(find.byKey(const ValueKey('ebook-speech-voice')), findsOneWidget);
    await _tap(tester, 'primary');
    expect(host.controller.speech.isActive, isTrue);
  });

  testWidgets('command failure is recoverable without closing the book', (
    tester,
  ) async {
    final host = _SpeechHost();
    addTearDown(host.controller.dispose);
    await _open(tester, host);
    host.nextError = StateError('The local voice could not start.');
    await _tap(tester, 'primary');
    expect(
      find.textContaining('The local voice could not start.'),
      findsOneWidget,
    );
    expect(host.controller.isReady, isTrue);
    expect(host.controller.speech.isActive, isFalse);
    await _tap(tester, 'primary');
    expect(find.byKey(const ValueKey('ebook-speech-error')), findsNothing);
    expect(host.controller.speech.isActive, isTrue);
  });

  testWidgets('voice and speed changes pause without implicitly restarting', (
    tester,
  ) async {
    final host = _SpeechHost();
    addTearDown(host.controller.dispose);
    await _open(tester, host);
    await _tap(tester, 'primary');

    final dropdown = find.byKey(const ValueKey('ebook-speech-voice'));
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deutsch (de-DE)').last);
    await tester.pumpAndSettle();
    expect(host.calls.last.$1, 'speechOptions');
    expect(host.calls.last.$2, {'voiceUri': 'local-de'});
    expect(host.controller.speech.isPaused, isTrue);
    await _tap(tester, 'primary');

    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('ebook-speech-rate')),
    );
    slider.onChanged!(1.5);
    slider.onChangeEnd!(1.5);
    await tester.pumpAndSettle();
    expect(host.calls.last.$1, 'speechOptions');
    expect(host.calls.last.$2, {'rate': 1.5});
    expect(host.controller.speech.rate, 1.5);
    expect(host.controller.speech.isPaused, isTrue);
    expect(find.text('Reading speed: 1.5×'), findsOneWidget);
  });

  testWidgets(
    'gesture handoff returns to the book without resubmitting audio',
    (tester) async {
      final host = _SpeechHost()
        ..status = 'paused'
        ..requiresGesture = true;
      addTearDown(host.controller.dispose);
      await _open(tester, host);
      expect(
        find.text(
          'Use Continue reading inside the book, then reopen these controls.',
        ),
        findsOneWidget,
      );
      final count = host.calls.length;
      await _tap(tester, 'return');
      expect(find.byType(EbookSpeechDialog), findsNothing);
      expect(host.calls.length, count);
    },
  );

  testWidgets('closing during a command tolerates its late failure', (
    tester,
  ) async {
    final host = _SpeechHost()..pendingStart = Completer<dynamic>();
    addTearDown(host.controller.dispose);
    await _open(tester, host);
    await _tap(tester, 'primary');
    await _tap(tester, 'close');
    host.pendingStart!.completeError(StateError('The reader was replaced.'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(EbookSpeechDialog), findsNothing);
  });

  testWidgets('voice-list replacement and small layouts remain usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final host = _SpeechHost();
    addTearDown(host.controller.dispose);
    await _open(tester, host);
    host.controller.updateSpeech(
      EbookSpeechState.fromJson({
        ...host.state,
        'voiceUri': 'removed-voice',
        'voices': [
          {'uri': 'local-en', 'name': 'English', 'language': 'en-US'},
          {'uri': 'local-en', 'name': 'English', 'language': 'en-US'},
        ],
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('Choose a local voice'), findsOneWidget);
    expect(tester.takeException(), isNull);
    host.available = false;
    host.controller.updateSpeech(EbookSpeechState.fromJson(host.state));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ebook-speech-voice')), findsNothing);
    expect(find.text('Read-aloud unavailable'), findsOneWidget);
    await _tap(tester, 'close');
    expect(tester.takeException(), isNull);
  });
}
