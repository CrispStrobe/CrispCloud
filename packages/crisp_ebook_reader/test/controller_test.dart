import 'dart:async';
import 'dart:convert';

import 'package:crisp_ebook_reader/crisp_ebook_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const info = EbookBookInfo(
    title: 'Fixture',
    authors: ['CrispCloud'],
    toc: [],
    sectionCount: 2,
    sourceFormat: 'epub',
  );

  test('disposing a keyed old host cannot detach the replacement transport',
      () async {
    final controller = CrispEbookController();
    final calls = <String>[];
    Future<dynamic> oldHost(String method, EbookJson args) async {
      calls.add('old:$method');
    }

    Future<dynamic> newHost(String method, EbookJson args) async {
      calls.add('new:$method');
    }

    controller.attach(oldHost);
    controller.updateBookInfo(info);
    controller.updateLocation(const EbookLocation(cfi: 'old', fraction: 0.5));
    controller.attach(newHost);
    expect(controller.isReady, isFalse);
    expect(controller.location, isNull);
    controller.detach(sender: oldHost);
    controller.updateBookInfo(info);
    expect(controller.isReady, isTrue);
    await controller.next();
    expect(calls, ['new:next']);
    controller.detach(sender: newHost);
    expect(controller.isReady, isFalse);
    await expectLater(controller.next(), throwsStateError);
    controller.dispose();
  });

  test('speech exposes local voice state and bounds controls', () async {
    final controller = CrispEbookController();
    addTearDown(controller.dispose);
    final calls = <(String, EbookJson)>[];
    controller.attach((method, args) async {
      calls.add((method, args));
      return {
        'status': method == 'speechPause' ? 'paused' : 'speaking',
        'revision': calls.length,
        'voices': [
          {'uri': 'local', 'name': 'Local English', 'language': 'en-US'}
        ],
        'voiceUri': 'local',
        'rate': args['rate'] ?? 1,
      };
    });
    await controller.startSpeech(voiceUri: 'local', rate: 4);
    expect(calls.single.$1, 'speechStart');
    expect(calls.single.$2, {'voiceUri': 'local', 'rate': 2});
    expect(controller.speech.isAvailable, isTrue);
    expect(controller.speech.isActive, isTrue);
    expect(controller.speech.voices.single.language, 'en-US');
    await controller.pauseSpeech();
    expect(controller.speech.isPaused, isTrue);
    await controller.resumeSpeech();
    await controller.setSpeechOptions(rate: 0.1);
    expect(calls.last.$1, 'speechOptions');
    expect(calls.last.$2, {'rate': 0.5});
    expect(() => controller.startSpeech(rate: double.nan), throwsArgumentError);
    controller.updateSpeech(const EbookSpeechState(
        status: EbookSpeechStatus.stopped, revision: 20));
    controller.updateSpeech(const EbookSpeechState(
        status: EbookSpeechStatus.speaking, revision: 19));
    expect(controller.speech.status, EbookSpeechStatus.stopped,
        reason: 'Delayed speech state cannot replace a newer stop');
  });

  test('late speech reply cannot modify a replacement reader', () async {
    final controller = CrispEbookController();
    addTearDown(controller.dispose);
    final reply = Completer<dynamic>();
    controller.attach((method, args) => reply.future);
    final pending = controller.refreshSpeech();
    controller.attach((method, args) async => null);
    reply.complete({'status': 'speaking', 'revision': 50});
    await pending;
    expect(controller.speech.status, EbookSpeechStatus.unavailable);
    expect(controller.speech.revision, -1);
    controller.updateSpeech(
        const EbookSpeechState(status: EbookSpeechStatus.paused, revision: 1));
    controller.detach();
    expect(controller.speech.status, EbookSpeechStatus.unavailable);
  });

  test('speech decoder fails closed for unknown state and nonfinite rate', () {
    final state = EbookSpeechState.fromJson({
      'status': 'remote-streaming',
      'rate': double.infinity,
    });
    expect(state.status, EbookSpeechStatus.unavailable);
    expect(state.isAvailable, isFalse);
    expect(state.rate, 1);
  });

  test('normalized import requires a known schema and encoding', () {
    expect(() => EbookImportPayload.fromJson({'schemaVersion': 2}),
        throwsFormatException);
    final payload = EbookImportPayload.fromJson({
      'schemaVersion': 1,
      'sourceFormat': 'fb2',
      'resources': [
        {
          'href': 'chapters/0001.xhtml',
          'mediaType': 'application/xhtml+xml',
          'encoding': 'base64',
          'data': base64Encode(utf8.encode('café 日本語'))
        },
      ],
    });
    expect(utf8.decode(payload.resourceBytes(payload.resources.single)),
        'café 日本語');
    expect(() => payload.resourceBytes({'encoding': 'remote-url'}),
        throwsFormatException);
  });

  test('progress commands reject nonfinite input and bound finite fractions',
      () async {
    final controller = CrispEbookController();
    addTearDown(controller.dispose);
    final calls = <EbookJson>[];
    controller.attach((method, args) async {
      expect(method, 'goToFraction');
      calls.add(args);
    });
    await controller.goToFraction(-0.5);
    await controller.goToFraction(0.375);
    await controller.goToFraction(4);
    await expectLater(controller.goToFraction(double.nan), throwsArgumentError);
    await expectLater(
      controller.goToFraction(double.infinity),
      throwsArgumentError,
    );
    expect(calls, [
      {'fraction': 0},
      {'fraction': 0.375},
      {'fraction': 1},
    ]);
  });

  test('history commands use their own channel and reset on a new publication',
      () async {
    final controller = CrispEbookController();
    addTearDown(controller.dispose);
    final calls = <String>[];
    controller.attach((method, args) async {
      calls.add(method);
      return {
        'canGoBack': method == 'historyForward',
        'canGoForward': method == 'historyBack',
      };
    });
    controller.updateHistory(const EbookNavigationHistory(canGoBack: true));
    await controller.goBack();
    expect(controller.canGoBack, isFalse);
    expect(controller.canGoForward, isTrue);
    await controller.goForward();
    expect(controller.canGoBack, isTrue);
    expect(controller.canGoForward, isFalse);
    expect(calls, ['historyBack', 'historyForward']);
    controller.attach((method, args) async => null);
    expect(controller.history.toJson(), {
      'canGoBack': false,
      'canGoForward': false,
    });
    controller.updateHistory(const EbookNavigationHistory(canGoForward: true));
    controller.detach();
    expect(controller.canGoForward, isFalse);
  });

  test('appearance roundtrips and copying one option retains all other options',
      () {
    const appearance = EbookAppearance(
      fontSize: 22,
      lineHeight: 1.9,
      theme: 'sepia',
      flow: 'scrolled',
      fontFamily: 'sans-serif',
      maxColumnCount: 3,
      pageMargin: 42,
      pageWidth: 940,
      usePublisherStyles: false,
    );
    final restored = EbookAppearance.fromJson(
      jsonDecode(jsonEncode(appearance.toJson())) as EbookJson,
    );
    expect(restored.toJson(), appearance.toJson());
    expect(restored.copyWith(fontSize: 25).toJson(), {
      ...appearance.toJson(),
      'fontSize': 25,
    });
    expect(EbookAppearance.fromJson({'theme': 'dark'}).toJson(), {
      ...const EbookAppearance().toJson(),
      'theme': 'dark',
    });
  });

  test('appearance bounds untrusted persisted values before the CSS bridge',
      () {
    final appearance = EbookAppearance.fromJson({
      'fontSize': double.infinity,
      'lineHeight': 99,
      'theme': 'url(https://invalid.example)',
      'flow': 'outside',
      'fontFamily': 'serif; background: url(https://invalid.example)',
      'maxColumnCount': 1000,
      'pageMargin': -20,
      'pageWidth': double.nan,
      'usePublisherStyles': 'false',
    });
    expect(appearance.toJson(), {
      'fontSize': 18,
      'lineHeight': 2.5,
      'theme': 'light',
      'flow': 'paginated',
      'fontFamily': 'serif',
      'maxColumnCount': 3,
      'pageMargin': 0,
      'pageWidth': 780,
      'usePublisherStyles': true,
    });
    expect(
      const EbookAppearance(pageWidth: 1, pageMargin: double.infinity)
          .normalized
          .toJson(),
      {...const EbookAppearance().toJson(), 'pageWidth': 320},
    );
  });

  test('book capabilities disable reflow controls on fixed-layout pages', () {
    final fixed = EbookBookInfo.fromJson({
      'fixedLayout': true,
      'supportsProgressSeeking': true,
      'supportsNavigationHistory': true,
      'supportsTextAppearance': true,
      'supportsLayout': true,
      'supportsPublisherStyles': true,
    });
    expect(fixed.supportsProgressSeeking, isTrue);
    expect(fixed.supportsNavigationHistory, isTrue);
    expect(fixed.supportsTextAppearance, isFalse);
    expect(fixed.supportsLayout, isFalse);
    expect(fixed.supportsPublisherStyles, isFalse);
    final unavailable = EbookBookInfo.fromJson({
      'supportsProgressSeeking': false,
      'supportsNavigationHistory': false,
      'supportsTextAppearance': false,
      'supportsLayout': false,
      'supportsPublisherStyles': false,
    });
    expect(unavailable.supportsProgressSeeking, isFalse);
    expect(unavailable.supportsNavigationHistory, isFalse);
    expect(unavailable.supportsTextAppearance, isFalse);
    expect(unavailable.supportsLayout, isFalse);
    expect(unavailable.supportsPublisherStyles, isFalse);
  });

  test('platform capabilities do not advertise a bundled Linux renderer', () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(EbookReaderCapabilities.supportsEmbeddedReader, isFalse);
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(EbookReaderCapabilities.supportsEmbeddedReader, isTrue);
    expect(EbookReaderCapabilities.supportsDrm, isFalse);
    expect(EbookReaderCapabilities.supportsKfx, isFalse);
  });
}
