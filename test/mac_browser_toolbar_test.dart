import 'dart:async';
import 'dart:typed_data';

import 'package:crisp_cloud/services/mac_browser_toolbar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('crispcloud/browser_toolbar');
  const codec = StandardMethodCodec();
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => true,
    );
  });
  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });
  Future<void> nativeAction(String id) async {
    final completed = Completer<void>();
    binding.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(MethodCall('action', id)),
      (ByteData? _) => completed.complete(),
    );
    await completed.future;
  }

  test(
    'native commands obey current enabled state and ignore unknown IDs',
    () async {
      final actions = <String>[];
      final toolbar = MacBrowserToolbar((id) async => actions.add(id));
      expect(
        await toolbar.configure(
          title: 'CrispCloud',
          visible: true,
          dark: false,
          items: [
            {'id': 'swap', 'enabled': true},
            {'id': 'delete', 'enabled': false},
          ],
        ),
        isTrue,
      );
      await nativeAction('swap');
      await nativeAction('delete');
      await nativeAction('unregistered');
      expect(actions, ['swap']);
      await toolbar.configure(
        title: 'CrispCloud',
        visible: false,
        dark: false,
        items: [],
      );
      await nativeAction('swap');
      expect(actions, ['swap']);
      await toolbar.dispose();
    },
  );
  test(
    'late native acknowledgement cannot reactivate a disposed browser',
    () async {
      final reply = Completer<bool>();
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async =>
            (call.arguments as Map)['visible'] == true ? reply.future : true,
      );
      final toolbar = MacBrowserToolbar((_) async {});
      final configuring = toolbar.configure(
        title: 'CrispCloud',
        visible: true,
        dark: true,
        items: [
          {'id': 'swap', 'enabled': true},
        ],
      );
      await Future<void>.delayed(Duration.zero);
      await toolbar.dispose();
      reply.complete(true);
      expect(await configuring, isFalse);
    },
  );
}
