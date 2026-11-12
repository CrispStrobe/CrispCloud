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
  // Counts and focus flags identify a Flutter-to-native transport failure
  // without logging publication text or evaluating arbitrary page scripts.
  try {
    debugPrint('linux-host test: last native status ${jsonEncode(await stats())}');
  } catch (_) {
    debugPrint('linux-host test: native status unavailable after failure');
  }
  fail(reason);
}

Future<void> focusReader(WidgetTester tester, Finder texture, Offset point) async {
  final focus = Focus.of(tester.element(texture));
  final textureId = tester.widget<Texture>(texture).textureId;
  await tester.tapAt(tester.getRect(texture).topLeft + point,
      kind: PointerDeviceKind.mouse);
  await until(tester, () async {
    final items = (await stats())['items'] as List;
    return focus.hasPrimaryFocus &&
        items.any((item) =>
            item['textureId'] == textureId && item['focused'] == true);
  }, 'Clicking the publication did not focus its Flutter and native surfaces.');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const portable = bool.fromEnvironment('EXPECT_PORTABLE');
  const blocked = bool.fromEnvironment('EXPECT_RUNTIME_BLOCKED');

  testWidgets(
      portable
          ? 'portable-only Linux host remains usable'
          : blocked
              ? 'unusable Linux runtime keeps Flutter responsive'
              : 'real inline Linux rendering, input, isolation and teardown',
      (tester) async {
    expect(portable && blocked, isFalse,
        reason: 'The native gate must select one distinct runtime scenario.');
    debugPrint('linux-host test: probing native host');
    final status = await probeEbookLinuxHost();
    debugPrint('linux-host test: probe completed');
    if (portable) {
      expect(status.available, isFalse);
      expect(status.reason, contains('build'));
      return;
    }
    if (blocked) {
      // This is a distinct fallback test, never a substitute for the required
      // successful enhanced-rendering run below. The runtime must be present:
      // the isolated startup failure must leave the application responsive.
      expect(status.available, isFalse);
      expect(status.runtime, 'webkitgtk-4.1');
      expect(status.version, isNotEmpty);
      expect(status.reason, contains('sandboxed Linux browser'));
      await expectLater(
          native.invokeMethod('create'), throwsA(isA<PlatformException>()));
      expect((await stats())['views'], 0);
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Text('Portable reader remains available')),
      ));
      expect(find.text('Portable reader remains available'), findsOneWidget);
      return;
    }
    expect(status.available, isTrue, reason: status.reason);
    expect(status.runtime, 'webkitgtk-4.1');
    expect(status.version, isNotEmpty);

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
    final beforeReader = FocusNode(debugLabel: 'before-book');
    final afterReader = FocusNode(debugLabel: 'after-book');
    addTearDown(beforeReader.dispose);
    addTearDown(afterReader.dispose);
    Widget reader() => MaterialApp(
          home: Scaffold(
            body: Column(children: [
              TextButton(
                focusNode: beforeReader,
                onPressed: () {},
                child: const Text('Before book'),
              ),
              Expanded(
                  child: Center(
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
              )),
              TextButton(
                focusNode: afterReader,
                onPressed: () {},
                child: const Text('After book'),
              ),
            ]),
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
    await focusReader(tester, find.byType(Texture), const Offset(200, 100));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await until(tester, () async {
      final items = (await stats())['items'] as List;
      return items.single['keyEvents'] >= 2;
    }, 'The selection shortcut did not reach native keyboard dispatch.');
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

    // The first link returns to chapter one and the second remains here. Tab,
    // Tab, Shift+Tab, Enter must activate the first link using actual WebKit
    // keyboard focus, rather than simulating the controller's navigation API.
    await focusReader(tester, find.byType(Texture), const Offset(550, 20));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await until(tester, () async => controller.location?.sectionIndex == 0,
        'Tab and Shift+Tab did not reach the publication link.');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await until(tester, () async => afterReader.hasFocus,
        'Control Tab trapped focus inside the publication.');
    expect(((await stats())['items'] as List).single['focused'], false);
    await tester.tapAt(
        tester.getRect(find.byType(Texture)).topLeft + const Offset(550, 20),
        kind: PointerDeviceKind.mouse);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await until(tester, () async => beforeReader.hasFocus,
        'Control Shift Tab did not return to the previous Flutter control.');
    expect(((await stats())['items'] as List).single['focused'], false);

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
      await focusReader(tester, texture, const Offset(80, 80));
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
