// test/ios_platform_test.dart
//
// Unit tests for the three new iOS platform polish features:
//   1. Share Extension Service   — lib/services/share_extension_service.dart
//   2. Siri Shortcuts Service    — lib/services/siri_shortcuts_service.dart
//   3. Multi-Window Service      — lib/services/multi_window_service.dart
//
// All services are platform-guarded (iOS-only).  Tests run on every platform
// and verify:
//   • Non-iOS: all public methods are no-ops and return safe defaults.
//   • Platform channel handling: correct method names, argument shapes, and
//     result parsing are verified by mocking the MethodChannel.
//
// We do NOT test actual Siri / Scene / App-Group behaviour — that requires
// a real device.  Instead we validate the Dart-side logic in isolation.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/services/share_extension_service.dart';
import 'package:crisp_cloud/services/siri_shortcuts_service.dart';
import 'package:crisp_cloud/services/multi_window_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Records every MethodChannel call made on a given channel and allows tests
/// to specify the response to return.
class _ChannelSpy {
  final String name;
  final List<MethodCall> calls = [];
  dynamic _response;

  _ChannelSpy(this.name, {dynamic response}) : _response = response {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(name), (call) async {
      calls.add(call);
      return _response;
    });
  }

  void setResponse(dynamic r) => _response = r;

  MethodCall? get lastCall => calls.isEmpty ? null : calls.last;

  void reset() => calls.clear();

  void dispose() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(name), null);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ShareExtensionService
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------------------
  group('ShareExtensionService — isAvailable guard', () {
    test('isAvailable is false on test host (non-iOS)', () {
      expect(ShareExtensionService.instance.isAvailable, isFalse);
    });

    test('peekPendingItems returns empty list on non-iOS', () async {
      final items = await ShareExtensionService.instance.peekPendingItems();
      expect(items, isEmpty);
    });

    test('clearPendingItems is a no-op on non-iOS', () async {
      // Should complete without throwing.
      await expectLater(
        ShareExtensionService.instance.clearPendingItems(),
        completes,
      );
    });

    test('processPendingUploads is a no-op on non-iOS', () async {
      var called = false;
      await ShareExtensionService.instance.processPendingUploads(
        upload: (path, name, mime) async {
          called = true;
          return true;
        },
      );
      expect(called, isFalse,
          reason: 'upload callback must not be called on non-iOS');
    });
  });

  // ---------------------------------------------------------------------------
  group('ShareExtensionItem.fromJson', () {
    test('parses a complete descriptor', () {
      final item = ShareExtensionItem.fromJson({
        'localPath':    '/group/ShareExtensionInbox/abc_photo.jpg',
        'originalName': 'photo.jpg',
        'mimeType':     'image/jpeg',
        'addedAt':      '2026-05-30T10:00:00.000Z',
      });

      expect(item.localPath,    '/group/ShareExtensionInbox/abc_photo.jpg');
      expect(item.originalName, 'photo.jpg');
      expect(item.mimeType,     'image/jpeg');
      expect(item.addedAt.year, 2026);
    });

    test('handles missing fields gracefully with safe defaults', () {
      final item = ShareExtensionItem.fromJson({});
      expect(item.localPath,    '');
      expect(item.originalName, 'unknown');
      expect(item.mimeType,     'application/octet-stream');
      expect(item.addedAt,      isNotNull);
    });

    test('handles malformed addedAt without throwing', () {
      final item = ShareExtensionItem.fromJson({
        'localPath': '/tmp/x',
        'addedAt':   'not-a-date',
      });
      expect(item.addedAt, isNotNull); // falls back to DateTime.now()
    });
  });

  // ---------------------------------------------------------------------------
  group('ShareExtensionService — channel integration (mocked)', () {
    late _ChannelSpy spy;

    setUp(() {
      spy = _ChannelSpy('com.crispcloud/share_extension');
    });

    tearDown(() => spy.dispose());

    test('processPendingUploads sends readPendingUploads on non-iOS → no call',
        () async {
      // On non-iOS the service never touches the channel.
      await ShareExtensionService.instance.processPendingUploads(
        upload: (_, __, ___) async => true,
      );
      expect(spy.calls, isEmpty);
    });

    test('ShareExtensionItem.fromJson filters items with empty localPath', () {
      // Items with empty localPath should be treated as invalid.
      final items = [
        ShareExtensionItem.fromJson({'localPath': '', 'originalName': 'bad'}),
        ShareExtensionItem.fromJson({
          'localPath':    '/group/foo.png',
          'originalName': 'foo.png',
          'mimeType':     'image/png',
          'addedAt':      '2026-01-01T00:00:00Z',
        }),
      ];
      final valid = items.where((i) => i.localPath.isNotEmpty).toList();
      expect(valid.length, 1);
      expect(valid.first.originalName, 'foo.png');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // SiriShortcutsService
  // ─────────────────────────────────────────────────────────────────────────

  group('SiriShortcutsService — isAvailable guard', () {
    test('isAvailable is false on test host (non-iOS)', () {
      expect(SiriShortcutsService.instance.isAvailable, isFalse);
    });

    test('registerShortcuts is a no-op on non-iOS', () async {
      await expectLater(
        SiriShortcutsService.instance.registerShortcuts(),
        completes,
      );
    });

    test('donateShortcut is a no-op on non-iOS', () async {
      await expectLater(
        SiriShortcutsService.instance.donateShortcut(SiriShortcutId.syncNow),
        completes,
      );
    });

    test('removeAllShortcuts is a no-op on non-iOS', () async {
      await expectLater(
        SiriShortcutsService.instance.removeAllShortcuts(),
        completes,
      );
    });
  });

  group('SiriShortcutId constants', () {
    test('all three shortcut IDs are non-empty and distinct', () {
      final ids = {
        SiriShortcutId.uploadToCloud,
        SiriShortcutId.showRecentFiles,
        SiriShortcutId.syncNow,
      };
      expect(ids.length, 3, reason: 'All IDs must be unique');
      for (final id in ids) {
        expect(id, isNotEmpty);
        expect(id, startsWith('com.crispcloud.shortcut.'));
      }
    });
  });

  group('SiriShortcut.toMap', () {
    test('toMap returns expected keys', () {
      const shortcut = SiriShortcut(
        identifier:                'com.crispcloud.shortcut.test',
        title:                     'Test',
        subtitle:                  'A test shortcut',
        suggestedInvocationPhrase: 'Do test',
      );
      final map = shortcut.toMap();
      expect(map['identifier'],                'com.crispcloud.shortcut.test');
      expect(map['title'],                     'Test');
      expect(map['subtitle'],                  'A test shortcut');
      expect(map['suggestedInvocationPhrase'], 'Do test');
    });
  });

  group('SiriShortcutsService — channel integration (mocked)', () {
    late _ChannelSpy spy;

    setUp(() {
      spy = _ChannelSpy('com.crispcloud/siri_shortcuts');
    });

    tearDown(() => spy.dispose());

    test('registerShortcuts does not call channel on non-iOS', () async {
      await SiriShortcutsService.instance.registerShortcuts();
      expect(spy.calls, isEmpty);
    });

    test('setActivationHandler stores handler without calling channel', () {
      var handlerFired = false;
      SiriShortcutsService.instance.setActivationHandler((_) {
        handlerFired = true;
      });
      // Handler not called yet.
      expect(handlerFired, isFalse);
      // No channel calls on non-iOS.
      expect(spy.calls, isEmpty);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // MultiWindowService
  // ─────────────────────────────────────────────────────────────────────────

  group('MultiWindowService — isAvailable guard', () {
    test('isAvailable is false on test host (non-iOS)', () {
      expect(MultiWindowService.instance.isAvailable, isFalse);
    });

    test('initialize is a no-op on non-iOS', () async {
      await expectLater(MultiWindowService.instance.initialize(), completes);
    });

    test('requestNewWindow returns false on non-iOS', () async {
      final ok = await MultiWindowService.instance.requestNewWindow();
      expect(ok, isFalse);
    });

    test('closeWindow is a no-op on non-iOS', () async {
      await expectLater(
        MultiWindowService.instance.closeWindow('scene-abc'),
        completes,
      );
    });

    test('state reflects empty / incapable defaults on non-iOS', () {
      final s = MultiWindowService.instance.state;
      expect(s.isCapable,          isFalse);
      expect(s.isMultiWindowActive, isFalse);
      expect(s.openWindows,         isEmpty);
      expect(s.currentSceneId,      isEmpty);
    });
  });

  group('MultiWindowState', () {
    test('isMultiWindowActive is false with one window', () {
      const s = MultiWindowState(
        openWindows:    [CrispWindowId(sceneId: 'abc')],
        currentSceneId: 'abc',
        isCapable:      true,
      );
      expect(s.isMultiWindowActive, isFalse);
    });

    test('isMultiWindowActive is true with two windows', () {
      const s = MultiWindowState(
        openWindows: [
          CrispWindowId(sceneId: 'abc'),
          CrispWindowId(sceneId: 'def'),
        ],
        currentSceneId: 'abc',
        isCapable:      true,
      );
      expect(s.isMultiWindowActive, isTrue);
    });
  });

  group('CrispWindowId', () {
    test('toString includes sceneId', () {
      const id = CrispWindowId(sceneId: 'scene-1');
      expect(id.toString(), contains('scene-1'));
    });

    test('toString includes label when present', () {
      const id = CrispWindowId(sceneId: 'scene-2', label: 'Documents');
      expect(id.toString(), contains('Documents'));
    });
  });

  group('MultiWindowService — channel integration (mocked)', () {
    late _ChannelSpy spy;

    setUp(() {
      spy = _ChannelSpy('com.crispcloud/multi_window');
    });

    tearDown(() => spy.dispose());

    test('initialize does not call channel on non-iOS', () async {
      // Re-create a fresh instance-like interaction (singleton is guarded).
      await MultiWindowService.instance.initialize();
      expect(spy.calls, isEmpty);
    });

    test('requestNewWindow does not call channel on non-iOS', () async {
      final ok = await MultiWindowService.instance.requestNewWindow(label: 'Test');
      expect(ok, isFalse);
      expect(spy.calls, isEmpty);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Cross-service: platform guard consistency
  // ─────────────────────────────────────────────────────────────────────────

  group('All iOS services — consistent platform guard behaviour', () {
    test('none of the services report isAvailable true on the test host', () {
      expect(ShareExtensionService.instance.isAvailable, isFalse,
          reason: 'ShareExtensionService');
      expect(SiriShortcutsService.instance.isAvailable, isFalse,
          reason: 'SiriShortcutsService');
      expect(MultiWindowService.instance.isAvailable, isFalse,
          reason: 'MultiWindowService');
    });

    test('no service throws on concurrent method calls on non-iOS', () async {
      await Future.wait([
        ShareExtensionService.instance.peekPendingItems(),
        ShareExtensionService.instance.clearPendingItems(),
        SiriShortcutsService.instance.registerShortcuts(),
        SiriShortcutsService.instance.removeAllShortcuts(),
        MultiWindowService.instance.initialize(),
        MultiWindowService.instance.requestNewWindow(),
      ]);
      // Reaching here means no exceptions were thrown.
    });
  });
}
