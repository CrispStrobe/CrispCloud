import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/services/secure_storage_macos_keychain.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(MacOsCustomKeychainStorage.methodChannelName);
  final messenger = TestDefaultBinaryMessengerBinding
      .instance
      .defaultBinaryMessenger;
  final calls = <MethodCall>[];
  const path = '/selected/keychains/private.keychain-db';

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'read' => 'stored value',
        'containsKey' => true,
        'readAll' => <String, String>{'credential': 'stored value'},
        _ => null,
      };
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('every credential operation addresses the initialized custom path', () async {
    final storage = MacOsCustomKeychainStorage(path: path);
    await storage.initialize();
    expect(await storage.read('credential'), 'stored value');
    await storage.write('credential', 'replacement');
    expect(await storage.containsKey('credential'), isTrue);
    expect(await storage.readAll(), {'credential': 'stored value'});
    await storage.delete('credential');
    await storage.deleteAll();
    expect(calls.map((call) => call.method), [
      'initialize',
      'read',
      'write',
      'containsKey',
      'readAll',
      'delete',
      'deleteAll',
    ]);
    for (final call in calls) {
      expect((call.arguments as Map)['path'], path);
    }
    expect(calls[2].arguments, {
      'path': path,
      'key': 'credential',
      'value': 'replacement',
    });
    expect(calls.last.arguments, {'path': path});
  });

  test('uninitialized storage cannot read or write', () {
    final storage = MacOsCustomKeychainStorage(path: path);
    expect(() => storage.read('credential'), throwsStateError);
    expect(() => storage.write('credential', 'value'), throwsStateError);
    expect(() => storage.deleteAll(), throwsStateError);
    expect(calls, isEmpty);
  });

  test('invalid and locked custom paths propagate without a fallback', () async {
    for (final code in [
      'custom_keychain_locked',
      'custom_keychain_unavailable',
      'custom_keychain_access_required',
    ]) {
      calls.clear();
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        throw PlatformException(code: code);
      });
      final storage = MacOsCustomKeychainStorage(path: path);
      await expectLater(
        storage.initialize(),
        throwsA(isA<PlatformException>().having((error) => error.code, 'code', code)),
      );
      expect(calls.single.method, 'initialize');
      expect(calls.single.arguments, {'path': path});
      expect(() => storage.read('credential'), throwsStateError);
    }
  });

  test('errors after initialization do not retry a different store', () async {
    final storage = MacOsCustomKeychainStorage(path: path);
    await storage.initialize();
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      throw PlatformException(code: 'custom_keychain_locked');
    });
    await expectLater(storage.read('credential'), throwsA(isA<PlatformException>()));
    expect(calls.single.method, 'read');
    expect(calls.single.arguments, {'path': path, 'key': 'credential'});
  });

  test('Browse returns a path or cancellation without selecting a backend', () async {
    String? selection = path;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return selection;
    });
    expect(
      await MacOsCustomKeychainStorage.chooseKeychain(initialPath: '/previous.keychain'),
      path,
    );
    expect(calls.single.method, 'chooseKeychain');
    expect(calls.single.arguments, {'initialPath': '/previous.keychain'});
    selection = null;
    expect(await MacOsCustomKeychainStorage.chooseKeychain(), isNull);
    expect(calls.map((call) => call.method), ['chooseKeychain', 'chooseKeychain']);
  });

  test('other platforms never invoke the native custom-keychain channel', () async {
    for (final platform in [TargetPlatform.iOS, TargetPlatform.android, TargetPlatform.linux]) {
      debugDefaultTargetPlatformOverride = platform;
      await expectLater(
        MacOsCustomKeychainStorage(path: path).initialize(),
        throwsUnsupportedError,
      );
      await expectLater(MacOsCustomKeychainStorage.chooseKeychain(), throwsUnsupportedError);
    }
    expect(calls, isEmpty);
  });

  test('empty account keys cannot become service-wide queries', () async {
    final storage = MacOsCustomKeychainStorage(path: path);
    await storage.initialize();
    calls.clear();
    expect(() => storage.read(''), throwsArgumentError);
    expect(() => storage.write('', 'value'), throwsArgumentError);
    expect(() => storage.delete(''), throwsArgumentError);
    await expectLater(storage.containsKey(''), throwsArgumentError);
    expect(calls, isEmpty);
  });

  test('malformed boolean and collection responses fail explicitly', () async {
    final storage = MacOsCustomKeychainStorage(path: path);
    await storage.initialize();
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    await expectLater(storage.containsKey('credential'), throwsFormatException);
    await expectLater(storage.readAll(), throwsFormatException);
  });
}
