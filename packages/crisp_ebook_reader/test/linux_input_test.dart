import 'package:crisp_ebook_reader/src/hosts/host_linux.dart';
import 'package:crisp_ebook_reader/src/hosts/linux_host_probe.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Linux focus and native keyboard shortcuts follow the reader', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    final errors = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      ebookLinuxHostChannel,
      (call) async {
        calls.add(call);
        return switch (call.method) {
          'probe' => {
            'runtime': 'webkitgtk-4.1',
            'available': true,
            'version': 'test',
          },
          'create' => {'id': 1, 'textureId': 2},
          _ => null,
        };
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        ebookLinuxHostChannel,
        null,
      ),
    );
    final before = FocusNode(debugLabel: 'before-book');
    final after = FocusNode(debugLabel: 'after-book');
    addTearDown(before.dispose);
    addTearDown(after.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TextButton(
                focusNode: before,
                onPressed: () {},
                child: const Text('Before'),
              ),
              SizedBox(
                width: 400,
                height: 300,
                child: buildLinuxEbookHost(
                  session: '12345678901234567890123456789012',
                  onConnected: (_) {},
                  onMessage: (_) {},
                  onError: errors.add,
                ),
              ),
              TextButton(
                focusNode: after,
                onPressed: () {},
                child: const Text('After'),
              ),
            ],
          ),
        ),
      ),
    );
    for (var i = 0; i < 50 && find.byType(Texture).evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(errors, isEmpty);
    expect(find.byType(Texture), findsOneWidget);
    calls.clear();
    await tester.tapAt(
      tester.getCenter(find.byType(Texture)),
      kind: PointerDeviceKind.mouse,
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(
      calls.where((call) => call.method == 'key').map((call) => call.arguments),
      [
        {'id': 1, 'name': 'a', 'pressed': true, 'modifiers': 2},
        {'id': 1, 'name': 'a', 'pressed': false, 'modifiers': 2},
      ],
    );
    expect(calls.where((call) => call.method == 'focus').last.arguments, {
      'id': 1,
      'focused': true,
    });

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(after.hasFocus, isTrue);
    expect(calls.where((call) => call.method == 'focus').last.arguments, {
      'id': 1,
      'focused': false,
    });

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    expect(errors, isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
