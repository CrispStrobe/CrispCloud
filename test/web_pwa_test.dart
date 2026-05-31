// test/web_pwa_test.dart
//
// Unit tests for the Web PWA services.
//
// These tests run on the native/VM test runner (not in a browser), so all web
// implementations are replaced by their platform stubs.  The tests therefore
// exercise:
//   - Public API contracts (method signatures, return types)
//   - Default / stub behaviour (isSupported = false, no-ops, null returns)
//   - Domain model classes (SharedContent, SharedFile, FsaFileResult,
//     PushNotificationType)
//   - Manifest / HTML content validation (read files and assert fields)
//   - Service-worker cache-strategy comments / structure

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:crisp_cloud/services/web_push_service.dart';
import 'package:crisp_cloud/services/file_system_access_service.dart';
import 'package:crisp_cloud/services/web_share_target_service.dart';
import 'package:crisp_cloud/services/opfs_service.dart';

// ============================================================================
// Helpers
// ============================================================================

/// Absolute path to the web/ directory.
/// The test runner sets the CWD to the package root, so we can resolve from
/// there directly.  We also support the case where the script path is known.
String get _webDir {
  // First try: CWD is the package root (standard `flutter test` behaviour).
  final cwd = Directory.current.path;
  final candidate = p.join(cwd, 'web');
  if (Directory(candidate).existsSync()) return candidate;

  // Second try: resolve relative to this script's location.
  final scriptDir = p.dirname(Platform.script.toFilePath());
  return p.normalize(p.join(scriptDir, '..', 'web'));
}

String _webFile(String name) => p.join(_webDir, name);

// ============================================================================
// WebPushService (stub on non-web)
// ============================================================================

void main() {
  // --------------------------------------------------------------------------
  // WebPushService — stub behaviour
  // --------------------------------------------------------------------------
  group('WebPushService (stub)', () {
    late WebPushService svc;

    setUp(() => svc = WebPushService());

    test('factory returns an instance', () {
      expect(svc, isNotNull);
    });

    test('isSupported is false on non-web', () {
      expect(svc.isSupported, isFalse);
    });

    test('requestPermission returns false on non-web', () async {
      final granted = await svc.requestPermission();
      expect(granted, isFalse);
    });

    test('showNotification completes without error on non-web', () async {
      await expectLater(
        svc.showNotification(
          type: PushNotificationType.transferComplete,
          title: 'Done',
          body: 'File uploaded',
        ),
        completes,
      );
    });

    test('notifyTransferComplete completes without error', () async {
      await expectLater(svc.notifyTransferComplete('photo.jpg'), completes);
    });

    test('notifySyncComplete completes without error', () async {
      await expectLater(svc.notifySyncComplete('Filen'), completes);
    });

    test('notifyError completes without error', () async {
      await expectLater(svc.notifyError('Upload failed'), completes);
    });
  });

  // --------------------------------------------------------------------------
  // PushNotificationType enum
  // --------------------------------------------------------------------------
  group('PushNotificationType', () {
    test('has all expected values', () {
      expect(PushNotificationType.values, hasLength(4));
      expect(PushNotificationType.values, containsAll([
        PushNotificationType.transferComplete,
        PushNotificationType.syncComplete,
        PushNotificationType.error,
        PushNotificationType.info,
      ]));
    });

    test('name strings are stable', () {
      expect(PushNotificationType.transferComplete.name, 'transferComplete');
      expect(PushNotificationType.syncComplete.name, 'syncComplete');
      expect(PushNotificationType.error.name, 'error');
      expect(PushNotificationType.info.name, 'info');
    });
  });

  // --------------------------------------------------------------------------
  // FileSystemAccessService — stub behaviour
  // --------------------------------------------------------------------------
  group('FileSystemAccessService (stub)', () {
    late FileSystemAccessService svc;

    setUp(() => svc = FileSystemAccessService());

    test('factory returns an instance', () {
      expect(svc, isNotNull);
    });

    test('isSupported is false on non-web', () {
      expect(svc.isSupported, isFalse);
    });

    test('openFilePicker returns null on non-web', () async {
      final result = await svc.openFilePicker();
      expect(result, isNull);
    });

    test('openFilePicker with acceptedTypes returns null', () async {
      final result = await svc.openFilePicker(
          acceptedTypes: ['image/png', 'image/jpeg']);
      expect(result, isNull);
    });

    test('saveFilePicker returns null on non-web', () async {
      final result = await svc.saveFilePicker(
        data: Uint8List.fromList([1, 2, 3]),
        suggestedName: 'export.csv',
      );
      expect(result, isNull);
    });

    test('openDirectoryPicker returns null on non-web', () async {
      final result = await svc.openDirectoryPicker();
      expect(result, isNull);
    });

    test('persistHandle completes without error', () async {
      await expectLater(svc.persistHandle('key', Object()), completes);
    });

    test('getPersistedHandle returns null on non-web', () async {
      final result = await svc.getPersistedHandle('key');
      expect(result, isNull);
    });

    test('removePersistedHandle completes without error', () async {
      await expectLater(svc.removePersistedHandle('key'), completes);
    });
  });

  // --------------------------------------------------------------------------
  // FsaFileResult model
  // --------------------------------------------------------------------------
  group('FsaFileResult', () {
    test('stores name and bytes', () {
      final bytes = Uint8List.fromList([10, 20, 30]);
      final result = FsaFileResult(name: 'test.txt', bytes: bytes);
      expect(result.name, 'test.txt');
      expect(result.bytes, bytes);
    });

    test('empty bytes is valid', () {
      final result = FsaFileResult(name: 'empty.bin', bytes: Uint8List(0));
      expect(result.bytes.isEmpty, isTrue);
    });

    test('large byte array is stored correctly', () {
      final bytes = Uint8List.fromList(List.generate(1024, (i) => i % 256));
      final result = FsaFileResult(name: 'big.bin', bytes: bytes);
      expect(result.bytes.length, 1024);
      expect(result.bytes[255], 255);
      expect(result.bytes[256], 0);
    });
  });

  // --------------------------------------------------------------------------
  // WebShareTargetService — stub behaviour
  // --------------------------------------------------------------------------
  group('WebShareTargetService (stub)', () {
    late WebShareTargetService svc;

    setUp(() => svc = WebShareTargetService());

    test('factory returns an instance', () {
      expect(svc, isNotNull);
    });

    test('hasSharedContent is false before initialize', () {
      expect(svc.hasSharedContent, isFalse);
    });

    test('sharedContent is null on non-web', () {
      expect(svc.sharedContent, isNull);
    });

    test('initialize completes without error', () async {
      await expectLater(svc.initialize(), completes);
    });

    test('hasSharedContent remains false after initialize on non-web', () async {
      await svc.initialize();
      expect(svc.hasSharedContent, isFalse);
    });

    test('clear completes without error', () {
      expect(() => svc.clear(), returnsNormally);
    });
  });

  // --------------------------------------------------------------------------
  // SharedContent model
  // --------------------------------------------------------------------------
  group('SharedContent', () {
    test('isEmpty when no fields set', () {
      const content = SharedContent();
      expect(content.isEmpty, isTrue);
    });

    test('isEmpty is false when title is set', () {
      const content = SharedContent(title: 'My file');
      expect(content.isEmpty, isFalse);
    });

    test('isEmpty is false when url is set', () {
      const content = SharedContent(url: 'https://example.com');
      expect(content.isEmpty, isFalse);
    });

    test('isEmpty is false when text is set', () {
      const content = SharedContent(text: 'some text');
      expect(content.isEmpty, isFalse);
    });

    test('hasUrl is true when url is non-empty', () {
      const content = SharedContent(url: 'https://example.com/file.pdf');
      expect(content.hasUrl, isTrue);
    });

    test('hasUrl is false when url is null', () {
      const content = SharedContent();
      expect(content.hasUrl, isFalse);
    });

    test('hasUrl is false when url is empty string', () {
      const content = SharedContent(url: '');
      expect(content.hasUrl, isFalse);
    });

    test('hasFiles is false when files list is empty', () {
      const content = SharedContent();
      expect(content.hasFiles, isFalse);
    });

    test('hasFiles is true when files are present', () {
      final file = SharedFile(
        name: 'photo.jpg',
        mimeType: 'image/jpeg',
        bytes: Uint8List(100),
      );
      final content = SharedContent(files: [file]);
      expect(content.hasFiles, isTrue);
    });

    test('toString includes title and url', () {
      const content =
          SharedContent(title: 'Hello', url: 'https://example.com');
      final s = content.toString();
      expect(s, contains('Hello'));
      expect(s, contains('https://example.com'));
    });

    test('default files list is empty', () {
      const content = SharedContent();
      expect(content.files, isEmpty);
    });
  });

  // --------------------------------------------------------------------------
  // SharedFile model
  // --------------------------------------------------------------------------
  group('SharedFile', () {
    test('stores all fields', () {
      final bytes = Uint8List.fromList([0xFF, 0xD8, 0xFF]);
      final file = SharedFile(
        name: 'image.jpg',
        mimeType: 'image/jpeg',
        bytes: bytes,
      );
      expect(file.name, 'image.jpg');
      expect(file.mimeType, 'image/jpeg');
      expect(file.bytes, bytes);
    });
  });

  // --------------------------------------------------------------------------
  // OpfsService — stub behaviour
  // --------------------------------------------------------------------------
  group('OpfsService (stub)', () {
    late OpfsService svc;

    setUp(() => svc = OpfsService());

    test('factory returns an instance', () {
      expect(svc, isNotNull);
    });

    test('isSupported is false on non-web', () {
      expect(svc.isSupported, isFalse);
    });

    test('initialize completes without error', () async {
      await expectLater(svc.initialize(), completes);
    });

    test('writeFile completes without error', () async {
      await expectLater(
        svc.writeFile('cache/file.txt', Uint8List.fromList([1, 2, 3])),
        completes,
      );
    });

    test('readFile returns null on non-web', () async {
      final result = await svc.readFile('cache/file.txt');
      expect(result, isNull);
    });

    test('deleteFile completes without error', () async {
      await expectLater(svc.deleteFile('cache/file.txt'), completes);
    });

    test('exists returns false on non-web', () async {
      final result = await svc.exists('cache/file.txt');
      expect(result, isFalse);
    });

    test('clearAll completes without error', () async {
      await expectLater(svc.clearAll(), completes);
    });

    test('multiple operations in sequence complete without error', () async {
      final data = Uint8List.fromList(List.generate(100, (i) => i));
      await svc.initialize();
      await svc.writeFile('a/b/c.bin', data);
      expect(await svc.readFile('a/b/c.bin'), isNull);
      expect(await svc.exists('a/b/c.bin'), isFalse);
      await svc.deleteFile('a/b/c.bin');
      await svc.clearAll();
    });
  });

  // --------------------------------------------------------------------------
  // Manifest JSON structure
  // --------------------------------------------------------------------------
  group('manifest.json', () {
    late Map<String, dynamic> manifest;

    setUpAll(() {
      final file = File(_webFile('manifest.json'));
      manifest = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    });

    test('name is CrispCloud', () {
      expect(manifest['name'], 'CrispCloud');
    });

    test('short_name is CrispCloud', () {
      expect(manifest['short_name'], 'CrispCloud');
    });

    test('display is standalone', () {
      expect(manifest['display'], 'standalone');
    });

    test('has icons array with at least 2 entries', () {
      final icons = manifest['icons'] as List;
      expect(icons.length, greaterThanOrEqualTo(2));
    });

    test('icons include 192x192 and 512x512', () {
      final icons = (manifest['icons'] as List).cast<Map<String, dynamic>>();
      final sizes = icons.map((i) => i['sizes'] as String).toSet();
      expect(sizes, containsAll(['192x192', '512x512']));
    });

    test('has maskable icons', () {
      final icons = (manifest['icons'] as List).cast<Map<String, dynamic>>();
      final hasMaskable = icons.any((i) =>
          (i['purpose'] as String?)?.contains('maskable') ?? false);
      expect(hasMaskable, isTrue);
    });

    test('has categories field', () {
      expect(manifest.containsKey('categories'), isTrue);
      final cats = manifest['categories'] as List;
      expect(cats, isNotEmpty);
    });

    test('categories includes productivity or utilities', () {
      final cats = (manifest['categories'] as List).cast<String>();
      expect(
        cats.any((c) => c == 'productivity' || c == 'utilities'),
        isTrue,
      );
    });

    test('has screenshots field', () {
      expect(manifest.containsKey('screenshots'), isTrue);
      final screenshots = manifest['screenshots'] as List;
      expect(screenshots, isNotEmpty);
    });

    test('has shortcuts field', () {
      expect(manifest.containsKey('shortcuts'), isTrue);
      final shortcuts = manifest['shortcuts'] as List;
      expect(shortcuts, isNotEmpty);
    });

    test('shortcuts have required fields', () {
      final shortcuts = (manifest['shortcuts'] as List)
          .cast<Map<String, dynamic>>();
      for (final s in shortcuts) {
        expect(s.containsKey('name'), isTrue,
            reason: 'shortcut missing name: $s');
        expect(s.containsKey('url'), isTrue,
            reason: 'shortcut missing url: $s');
      }
    });

    test('has share_target field', () {
      expect(manifest.containsKey('share_target'), isTrue);
    });

    test('share_target has action field', () {
      final st = manifest['share_target'] as Map<String, dynamic>;
      expect(st.containsKey('action'), isTrue);
      expect(st['action'], isA<String>());
    });

    test('share_target method is POST', () {
      final st = manifest['share_target'] as Map<String, dynamic>;
      expect(st['method'], 'POST');
    });

    test('share_target accepts files', () {
      final st = manifest['share_target'] as Map<String, dynamic>;
      final params = st['params'] as Map<String, dynamic>;
      expect(params.containsKey('files'), isTrue);
    });

    test('theme_color is set', () {
      expect(manifest.containsKey('theme_color'), isTrue);
      expect((manifest['theme_color'] as String).startsWith('#'), isTrue);
    });
  });

  // --------------------------------------------------------------------------
  // index.html structure
  // --------------------------------------------------------------------------
  group('index.html', () {
    late String html;

    setUpAll(() {
      html = File(_webFile('index.html')).readAsStringSync();
    });

    test('title is CrispCloud', () {
      expect(html, contains('<title>CrispCloud</title>'));
    });

    test('registers service worker', () {
      expect(html, contains('serviceWorker'));
      expect(html, contains("register('service-worker.js')"));
    });

    test('has apple-mobile-web-app-capable meta tag', () {
      expect(html, contains('apple-mobile-web-app-capable'));
    });

    test('apple-mobile-web-app-capable content is yes', () {
      expect(
        html,
        contains('name="apple-mobile-web-app-capable" content="yes"'),
      );
    });

    test('has apple-mobile-web-app-title meta tag', () {
      expect(html, contains('apple-mobile-web-app-title'));
    });

    test('apple-mobile-web-app-title content is CrispCloud', () {
      expect(
        html,
        contains('content="CrispCloud"'),
      );
    });

    test('has manifest link', () {
      expect(html, contains('rel="manifest"'));
      expect(html, contains('manifest.json'));
    });

    test('has flutter_bootstrap.js script', () {
      expect(html, contains('flutter_bootstrap.js'));
    });

    test('has viewport meta tag', () {
      expect(html, contains('name="viewport"'));
    });

    test('has apple-touch-icon link', () {
      expect(html, contains('apple-touch-icon'));
    });
  });

  // --------------------------------------------------------------------------
  // service-worker.js structure
  // --------------------------------------------------------------------------
  group('service-worker.js', () {
    late String sw;

    setUpAll(() {
      sw = File(_webFile('service-worker.js')).readAsStringSync();
    });

    test('file exists and is non-empty', () {
      expect(sw, isNotEmpty);
    });

    test('defines CACHE_VERSION', () {
      expect(sw, contains('CACHE_VERSION'));
    });

    test('defines STATIC_CACHE', () {
      expect(sw, contains('STATIC_CACHE'));
    });

    test('defines DYNAMIC_CACHE', () {
      expect(sw, contains('DYNAMIC_CACHE'));
    });

    test('handles install event', () {
      expect(sw, contains("addEventListener('install'"));
    });

    test('handles activate event', () {
      expect(sw, contains("addEventListener('activate'"));
    });

    test('handles fetch event', () {
      expect(sw, contains("addEventListener('fetch'"));
    });

    test('implements cache-first strategy', () {
      expect(sw, contains('cacheFirst'));
    });

    test('implements network-first strategy', () {
      expect(sw, contains('networkFirst'));
    });

    test('includes index.html in APP_SHELL pre-cache', () {
      expect(sw, contains('/index.html'));
    });

    test('includes manifest.json in APP_SHELL pre-cache', () {
      expect(sw, contains('/manifest.json'));
    });

    test('calls skipWaiting on install', () {
      expect(sw, contains('skipWaiting'));
    });

    test('calls clients.claim on activate', () {
      expect(sw, contains('clients.claim'));
    });

    test('deletes old caches on activate', () {
      expect(sw, contains('caches.delete'));
    });

    test('handles push event for push notifications', () {
      expect(sw, contains("addEventListener('push'"));
    });

    test('handles notificationclick event', () {
      expect(sw, contains("addEventListener('notificationclick'"));
    });

    test('uses version-based cache names', () {
      // Cache names should embed CACHE_VERSION so bumping the version
      // automatically busts old caches.
      expect(sw, contains('crisp-cloud-static'));
      expect(sw, contains('crisp-cloud-dynamic'));
    });

    test('provides offline fallback in cache-first', () {
      // Should fall back to /index.html when network is unavailable.
      expect(sw, contains("'/index.html'"));
    });
  });

  // --------------------------------------------------------------------------
  // Cross-service integration: stub factory chain
  // --------------------------------------------------------------------------
  group('PWA service factory chain', () {
    test('all services can be instantiated in sequence', () {
      final push = WebPushService();
      final fsa = FileSystemAccessService();
      final share = WebShareTargetService();
      final opfs = OpfsService();

      expect(push, isNotNull);
      expect(fsa, isNotNull);
      expect(share, isNotNull);
      expect(opfs, isNotNull);
    });

    test('none of the stubs throw during basic operations', () async {
      final push = WebPushService();
      final fsa = FileSystemAccessService();
      final share = WebShareTargetService();
      final opfs = OpfsService();

      await push.requestPermission();
      await fsa.openFilePicker();
      await share.initialize();
      share.clear();
      await opfs.initialize();
      await opfs.clearAll();
    });

    test('all stubs report isSupported = false', () {
      expect(WebPushService().isSupported, isFalse);
      expect(FileSystemAccessService().isSupported, isFalse);
      expect(OpfsService().isSupported, isFalse);
    });
  });
}
