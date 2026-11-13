// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:convert';

import 'package:file_viewer_documents/src/hosts/host.dart';
import 'package:file_viewer_documents/src/hosts/host_linux.dart';
import 'package:file_viewer_documents/src/hosts/linux_host_probe.dart';
import 'package:file_viewer_documents/src/models.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _session = '0123456789abcdef0123456789abcdef';

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var index = 0; index < 100 && !condition(); index++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(
    condition(),
    isTrue,
    reason: 'The host did not finish the requested lifecycle step.',
  );
}

Future<void> _event(WidgetTester tester, Map<String, Object?> event) async {
  final completed = Completer<void>();
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    documentLinuxHostChannel.name,
    const StandardMethodCodec().encodeMethodCall(MethodCall('event', event)),
    (_) => completed.complete(),
  );
  await completed.future;
}

void main() {
  testWidgets('missing native plugin produces an immediate bounded error', (
    tester,
  ) async {
    final errors = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      documentLinuxHostChannel,
      (_) async => throw MissingPluginException('Document plugin absent'),
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        documentLinuxHostChannel,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: buildLinuxDocumentHost(
          session: _session,
          onConnected: (_) {},
          onMessage: (_) {},
          onError: errors.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(errors.single, contains('does not contain the Linux browser host'));
    expect(find.byType(Texture), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('unavailable or malformed runtime probes never create a view', (
    tester,
  ) async {
    final calls = <String>[];
    final errors = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      documentLinuxHostChannel,
      (call) async {
        calls.add(call.method);
        return {'runtime': 'unexpected-engine', 'available': true};
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        documentLinuxHostChannel,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: buildLinuxDocumentHost(
          session: _session,
          onConnected: (_) {},
          onMessage: (_) {},
          onError: errors.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, ['probe']);
    expect(errors.single, contains('invalid runtime response'));
    expect(find.byType(Texture), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets(
    'Linux document host routes typing, trusted messages and disposal',
    (tester) async {
      final calls = <MethodCall>[];
      final errors = <String>[];
      final received = <DocumentJson>[];
      DocumentHostSender? sender;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        documentLinuxHostChannel,
        (call) async {
          calls.add(call);
          return switch (call.method) {
            'probe' => {
              'runtime': 'webkitgtk-4.1',
              'available': true,
              'version': 'test',
            },
            'create' => {'id': 11, 'textureId': 12},
            _ => null,
          };
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          documentLinuxHostChannel,
          null,
        ),
      );
      final after = FocusNode();
      addTearDown(after.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(
                  width: 400,
                  height: 300,
                  child: buildLinuxDocumentHost(
                    session: _session,
                    onConnected: (value) => sender = value,
                    onMessage: received.add,
                    onError: errors.add,
                  ),
                ),
                TextButton(
                  focusNode: after,
                  onPressed: () {},
                  child: const Text('After document'),
                ),
              ],
            ),
          ),
        ),
      );
      await _pumpUntil(
        tester,
        () => calls.any((call) => call.method == 'start') || errors.isNotEmpty,
      );
      expect(errors, isEmpty);
      expect(find.byType(Texture), findsOneWidget);
      final started =
          calls.singleWhere((call) => call.method == 'start').arguments as Map;
      expect(started['session'], _session);
      expect(Uri.parse(started['url'] as String).path, '/$_session/index.html');
      await sender!({
        'channel': documentPreviewChannel,
        'session': _session,
        'type': 'begin',
        'fonts': [
          {'url': 'https://untrusted.invalid/font.ttf'},
        ],
      });
      final begun =
          jsonDecode((calls.last.arguments as Map)['message'] as String) as Map;
      // The host controls the catalog; caller messages cannot add font URLs.
      expect(begun['fonts'], isEmpty);
      await sender!({
        'channel': documentPreviewChannel,
        'session': _session,
        'type': 'open',
      });
      expect(
        jsonDecode((calls.last.arguments as Map)['message'] as String)['type'],
        'open',
      );
      await expectLater(
        sender!({
          'channel': documentPreviewChannel,
          'session': 'wrong',
          'type': 'open',
        }),
        throwsArgumentError,
      );

      await _event(tester, {
        'id': 11,
        'type': 'message',
        'data': jsonEncode({
          'channel': documentPreviewChannel,
          'session': _session,
          'type': 'loaded',
        }),
      });
      await _event(tester, {
        'id': 11,
        'type': 'message',
        'data': jsonEncode({
          'channel': documentPreviewChannel,
          'session': 'other',
          'type': 'ready',
        }),
      });
      await _event(tester, {
        'id': 11,
        'type': 'message',
        'data': 'x' * (1024 * 1024 + 1),
      });
      expect(received.map((message) => message['type']), ['loaded']);

      await tester.tapAt(
        tester.getCenter(find.byType(Texture)),
        kind: PointerDeviceKind.mouse,
      );
      calls.clear();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS, character: 's');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      final keys = calls
          .where((call) => call.method == 'key')
          .map((call) => call.arguments as Map)
          .toList();
      expect(keys.take(2).map((key) => key['character']), [115, 115]);
      expect(keys.skip(2).map((key) => key['name']), [
        'BackSpace',
        'BackSpace',
        'Left',
        'Left',
      ]);
      expect(keys.map((key) => key['pressed']), [
        true,
        false,
        true,
        false,
        true,
        false,
      ]);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(after.hasFocus, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      expect(calls.where((call) => call.method == 'dispose').length, 1);
      await expectLater(
        sender!({
          'channel': documentPreviewChannel,
          'session': _session,
          'type': 'open',
        }),
        throwsStateError,
      );
      await _event(tester, {'id': 11, 'type': 'error', 'data': 'late event'});
      expect(errors, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'a view created after widget disposal is released without starting',
    (tester) async {
      final created = Completer<Map<String, Object?>>();
      final calls = <MethodCall>[];
      final errors = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        documentLinuxHostChannel,
        (call) async {
          calls.add(call);
          return switch (call.method) {
            'probe' => {'runtime': 'webkitgtk-4.1', 'available': true},
            'create' => created.future,
            _ => null,
          };
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          documentLinuxHostChannel,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: buildLinuxDocumentHost(
            session: _session,
            onConnected: (_) => fail('Disposed host must not connect'),
            onMessage: (_) {},
            onError: errors.add,
          ),
        ),
      );
      await _pumpUntil(
        tester,
        () => calls.any((call) => call.method == 'create') || errors.isNotEmpty,
      );
      expect(errors, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      created.complete({'id': 23, 'textureId': 24});
      await _pumpUntil(
        tester,
        () => calls.any((call) => call.method == 'dispose'),
      );
      expect(calls.where((call) => call.method == 'start'), isEmpty);
      expect(errors, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}
