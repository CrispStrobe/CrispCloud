// Runs in a real Linux Flutter application under Xvfb, not flutter_tester.
import 'dart:convert';
import 'dart:io';

import 'package:crisp_ebook_reader/crisp_ebook_reader.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const native = MethodChannel('crisp_ebook_reader/linux_host');

Future<Map<String, dynamic>> stats() async =>
    Map<String, dynamic>.from((await native.invokeMethod('stats')) as Map);

Future<void> until(WidgetTester tester, Future<bool> Function() condition,
    String reason) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  do {
    await tester.pump(const Duration(milliseconds: 100));
    if (await condition()) return;
  } while (DateTime.now().isBefore(deadline));
  fail(reason);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const testName = bool.fromEnvironment('EXPECT_RUNTIME_UNAVAILABLE')
      ? 'installed Linux runtime fails safely before creating a reader'
      : bool.fromEnvironment('EXPECT_PORTABLE')
          ? 'portable-only Linux build launches and reports its capability'
          : 'real inline Linux rendering, input, isolation and teardown';
  testWidgets(testName, (tester) async {
    if (const bool.fromEnvironment('EXPECT_RUNTIME_UNAVAILABLE')) {
      // Exercise direct create before any cached probe, plus concurrent probes.
      // None may create an in-process WebKit view after the canary fails.
      final create = native.invokeMethod<dynamic>('create').then<dynamic>(
            (value) => value,
            onError: (Object error) => error,
          );
      final statuses = await Future.wait([
        probeEbookLinuxHost(),
        probeEbookLinuxHost(),
        probeEbookLinuxHost(),
      ]);
      for (final status in statuses) {
        expect(status.available, isFalse);
        expect(status.version, isNotEmpty);
        expect(
            status.reason, contains('sandboxed WebKit startup check failed'));
      }
      expect(await create, isA<PlatformException>());
      final current = await stats();
      expect(current['views'], 0);
      expect(current['surfaceSlots'], 0);
      expect(current['canaryAttempts'], 1);
      expect(current['canaryRunning'], isFalse);
      expect(current['canaryReady'], isFalse);
      await expectLater(
        native.invokeMethod<dynamic>('create'),
        throwsA(isA<PlatformException>()),
      );
      expect((await stats())['canaryAttempts'], 1);
      var clicks = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TextButton(
            onPressed: () => clicks++,
            child: const Text('Portable reader available'),
          ),
        ),
      ));
      await tester.tap(find.text('Portable reader available'));
      await tester.pump();
      expect(clicks, 1);
      debugPrint(
          'linux-host test: installed runtime safely unavailable; Flutter remains responsive');
      return;
    }
    debugPrint('linux-host test: probing native host');
    final statuses = await Future.wait([
      probeEbookLinuxHost(),
      probeEbookLinuxHost(),
      probeEbookLinuxHost(),
    ]);
    final status = statuses.first;
    debugPrint('linux-host test: probe completed');
    if (const bool.fromEnvironment('EXPECT_PORTABLE')) {
      expect(status.available, isFalse);
      expect(status.reason, contains('build'));
      return;
    }
    expect(status.available, isTrue, reason: status.reason);
    expect(status.runtime, 'webkitgtk-4.1');
    expect(status.version, isNotEmpty);
    expect(statuses.every((value) => value.available), isTrue);
    expect((await stats())['canaryAttempts'], 1);
    expect((await stats())['canaryRunning'], isFalse);
    expect((await stats())['views'], 0);

    // The self-authored book contains script, image, iframe and CSS requests to
    // this distinct origin. Opening and interacting with the real WebKit book
    // must never send any of them, even though the local endpoint is reachable.
    final blockedRequests = <String>[];
    final resourceProbe =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 18189);
    debugPrint('linux-host test: resource probe listening');
    resourceProbe.listen((request) {
      blockedRequests.add(request.uri.toString());
      request.response.statusCode = HttpStatus.forbidden;
      request.response.close();
    });
    addTearDown(() => resourceProbe.close(force: true));

    final bytes =
        (await rootBundle.load('assets/host-smoke.epub')).buffer.asUint8List();
    final controller = CrispEbookController();
    final errors = <String>[];
    final size = ValueNotifier(const Size(720, 500));
    EbookBookInfo? book;
    EbookSelection? selection;
    var overlayClicks = 0;
    Widget reader() => MaterialApp(
          home: Scaffold(
            body: Center(
              child: ValueListenableBuilder<Size>(
                valueListenable: size,
                builder: (context, value, child) => SizedBox(
                  width: value.width,
                  height: value.height,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CrispEbookReader(
                          bytes: bytes,
                          filename: 'host-smoke.epub',
                          controller: controller,
                          onReady: (value) => book = value,
                          onSelection: (value) => selection = value,
                          onError: errors.add,
                        ),
                      ),
                      Positioned(
                        right: 20,
                        top: 20,
                        child: GestureDetector(
                          key: const ValueKey('flutter-overlay'),
                          onTap: () => overlayClicks++,
                          child: const SizedBox(
                            width: 35,
                            height: 35,
                            child: ColoredBox(color: Color(0xffff00ff)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

    await tester.pumpWidget(reader());
    debugPrint('linux-host test: reader widget mounted');
    await until(tester, () async {
      if (errors.isNotEmpty) fail(errors.join('\n'));
      if (!controller.isReady) return false;
      final value = await stats();
      final items = value['items'] as List;
      return items.length == 1 &&
          (items.single['frames'] as int) > 0 &&
          (items.single['consumed'] as int) > 0 &&
          items.single['nonUniform'] == true;
    }, 'The real WebKit page did not reach Flutter’s texture renderer.');
    expect(book!.title, 'Linux inline library');
    debugPrint('linux-host test: real texture populated');
    expect(book!.sectionCount, 2);
    expect(errors, isEmpty);

    // Capture the X server's actual framebuffer. This detects a blank external
    // texture and native-overlay composition bugs that widget finders miss.
    final screenshot = await Process.run('python3', [
      'tool/capture_linux_host.py',
      'build/linux-host-evidence/inline.png',
    ]);
    expect(screenshot.exitCode, 0, reason: '${screenshot.stderr}');
    final pixels = jsonDecode('${screenshot.stdout}') as Map;
    expect(pixels['greenBookPixels'], greaterThan(50));
    expect(pixels['magentaFlutterPixels'], greaterThan(200));
    await tester.tap(find.byKey(const ValueKey('flutter-overlay')));
    await tester.pump();
    expect(overlayClicks, 1);

    final content = tester.getRect(find.byType(Texture));
    await tester.tapAt(content.topLeft + const Offset(200, 100),
        kind: PointerDeviceKind.mouse);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await until(tester, () async => selection?.text.contains('Library') == true,
        'Native keyboard selection did not produce a Foliate CFI.');
    expect(selection!.cfi, startsWith('epubcfi('));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await until(tester, () async {
      final value = await Clipboard.getData(Clipboard.kTextPlain);
      return value?.text?.contains('Library') == true;
    }, 'Native WebKit selection did not reach the system clipboard.');

    final fullSelection = selection!.cfi;
    final gesture = await tester.startGesture(
      content.topLeft + const Offset(95, 105),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(content.topLeft + const Offset(480, 150));
    await gesture.up();
    await until(
        tester,
        () async =>
            selection != null &&
            selection!.cfi != fullSelection &&
            selection!.text.isNotEmpty,
        'Dragging in the native content did not update text selection.');

    final oldLocation = controller.location?.cfi;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await until(tester, () async => controller.location?.cfi != oldLocation,
        'The native keyboard page-turn did not reach Foliate.');
    final results = await controller.search('Second library shelf');
    expect(results, isNotEmpty);
    await controller.goTo(results.first.cfi);
    await until(tester, () async => controller.location?.sectionIndex == 1,
        'Whole-book search did not navigate to the second chapter.');

    final beforeResize = ((await stats())['items'] as List).single['width'];
    size.value = const Size(520, 360);
    await until(tester, () async {
      final item = ((await stats())['items'] as List).single;
      return item['width'] != beforeResize &&
          (item['frames'] as int) > 0 &&
          (item['consumed'] as int) > 0;
    }, 'The native texture did not resize with Flutter.');
    expect(errors, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await until(tester, () async => (await stats())['views'] == 0,
        'Disposing the reader retained a native WebKit view.');
    expect((await stats())['surfaceSlots'], 1);

    // Native URL validation is independent of the Dart/JavaScript bridge.
    final rejected =
        Map<String, dynamic>.from((await native.invokeMethod('create')) as Map);
    await expectLater(
        native.invokeMethod('start', {
          'id': rejected['id'],
          'url': 'https://example.com/',
          'session': 'a' * 32,
        }),
        throwsA(isA<PlatformException>()));
    await native.invokeMethod('dispose', {'id': rejected['id']});

    // Exercise both immediate disposal and normal reuse after a complete close.
    for (var attempt = 0; attempt < 3; attempt++) {
      await tester.pumpWidget(reader());
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await until(tester, () async => (await stats())['views'] == 0,
          'An interrupted startup left a native view behind.');
    }
    await tester.pumpWidget(reader());
    await until(tester, () async => controller.isReady,
        'The same controller could not reopen after teardown.');
    expect(errors, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await until(tester, () async => (await stats())['views'] == 0,
        'The reopened reader did not tear down.');
    expect((await stats())['surfaceSlots'], 1,
        reason: 'Repeated book opens must reuse the bounded surface pool.');

    final pair = [CrispEbookController(), CrispEbookController()];
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      home: Scaffold(
        body: Row(children: [
          for (var index = 0; index < pair.length; index++)
            Expanded(
              child: CrispEbookReader(
                key: ValueKey('reader-$index'),
                bytes: bytes,
                filename: 'host-smoke.epub',
                controller: pair[index],
                onError: errors.add,
              ),
            ),
        ]),
      ),
    ));
    await until(tester, () async {
      if (errors.isNotEmpty) fail(errors.join('\n'));
      return pair.every((controller) => controller.isReady) &&
          (await stats())['views'] == 2;
    }, 'Two independent native readers did not become ready.');
    for (var focused = 0; focused < pair.length; focused++) {
      final before =
          pair.map((controller) => controller.location?.cfi).toList();
      final texture = find.descendant(
          of: find.byKey(ValueKey('reader-$focused')),
          matching: find.byType(Texture));
      await tester.tapAt(tester.getRect(texture).topLeft + const Offset(80, 80),
          kind: PointerDeviceKind.mouse);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await until(
          tester,
          () async => pair[focused].location?.cfi != before[focused],
          'Keyboard input did not reach the focused reader.');
      expect(pair[1 - focused].location?.cfi, before[1 - focused],
          reason: 'A key event leaked to the other reader instance.');
    }
    final beforeModal =
        pair.map((controller) => controller.location?.cfi).toList();
    final modal = showDialog<void>(
      context: navigator.currentContext!,
      builder: (context) => AlertDialog(
        title: const Text('Flutter input above the book'),
        content: const TextField(autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'))
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'café 日本語');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.text('café 日本語'), findsOneWidget);
    expect(pair.map((controller) => controller.location?.cfi).toList(),
        beforeModal,
        reason: 'Modal keyboard input reached an obscured native reader.');
    expect(
        ((await stats())['items'] as List)
            .every((item) => item['focused'] == false),
        isTrue);
    await tester.tap(find.text('Done'));
    await modal;
    await tester.pumpWidget(const SizedBox.shrink());
    await until(tester, () async => (await stats())['views'] == 0,
        'The simultaneous reader instances did not tear down.');
    expect((await stats())['surfaceSlots'], 2);
    expect(blockedRequests, isEmpty,
        reason:
            'A hostile publication escaped the native reader security boundary.');
    for (final controller in pair) {
      controller.dispose();
    }
    size.dispose();
    controller.dispose();
  }, timeout: const Timeout(Duration(minutes: 5)));
}
