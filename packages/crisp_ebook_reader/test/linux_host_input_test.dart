import 'package:crisp_ebook_reader/src/hosts/host_linux.dart';
import 'package:crisp_ebook_reader/src/hosts/linux_host_probe.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'routes the first shortcut after pointer focus to the native host',
      (tester) async {
    final calls = <MethodCall>[];
    final errors = <String>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(ebookLinuxHostChannel, (call) async {
      calls.add(call);
      if (call.method == 'probe') {
        return {
          'available': true,
          'runtime': 'webkitgtk-4.1',
          'version': '2.50.4',
        };
      }
      if (call.method == 'create') return {'id': 1, 'textureId': 1};
      return null;
    });
    addTearDown(
        () => messenger.setMockMethodCallHandler(ebookLinuxHostChannel, null));
    var overlayClicks = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 720,
          height: 500,
          child: Stack(children: [
            Positioned.fill(
              child: buildLinuxEbookHost(
                session: 'a' * 32,
                onConnected: (_) {},
                onMessage: (_) {},
                onError: errors.add,
              ),
            ),
            Positioned(
              top: 20,
              right: 20,
              child: GestureDetector(
                key: const ValueKey('overlay'),
                onTap: () => overlayClicks++,
                child: const SizedBox(
                  width: 35,
                  height: 35,
                  child: ColoredBox(color: Colors.pink),
                ),
              ),
            ),
          ]),
        ),
      ),
    ));

    // Allow the real instance-scoped asset server to bind. The platform channel
    // alone is mocked; focus, hit testing and hardware-key dispatch are real.
    await tester.runAsync(() async {
      for (var attempt = 0;
          attempt < 100 &&
              !calls.any((call) => call.method == 'start') &&
              errors.isEmpty;
          attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
      }
    });
    expect(errors, isEmpty);
    expect(calls.where((call) => call.method == 'start'), hasLength(1));

    await tester.tap(find.byKey(const ValueKey('overlay')));
    await tester.pump();
    expect(overlayClicks, 1);
    calls.clear();
    await tester.tapAt(
      tester.getRect(find.byType(Texture)).topLeft + const Offset(200, 100),
      kind: PointerDeviceKind.mouse,
    );
    expect(
        FocusManager.instance.primaryFocus?.debugLabel, 'ebook-linux-content');

    // Deliberately do not pump between the pointer and keyboard actions. Native
    // WebProcess acknowledgement is a separate concern covered by the real
    // Linux integration test; Flutter must forward this first shortcut now.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(
      calls.where((call) => call.method == 'key').map((call) => call.arguments),
      [
        {'id': 1, 'name': 'a', 'pressed': true, 'modifiers': 2},
        {'id': 1, 'name': 'a', 'pressed': false, 'modifiers': 2},
      ],
    );
    expect(
      calls
          .where((call) => call.method == 'pointer')
          .map((call) => [call.arguments['type'], call.arguments['buttons']]),
      [
        ['down', 1],
        ['up', 1],
      ],
    );
    expect(calls.where((call) => call.method == 'focus').single.arguments,
        {'id': 1, 'focused': true});
    expect(errors, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 10)));
    expect(calls.where((call) => call.method == 'dispose').single.arguments,
        {'id': 1});
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
