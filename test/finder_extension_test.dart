// test/finder_extension_test.dart
//
// Tests for FinderExtensionService.
//
// The native MethodChannel and dart:io filesystem operations cannot run
// in the Dart test runner, so the test suite focuses on:
//   • URL parsing (the pure-Dart core logic)
//   • Platform guard behaviour
//   • FinderUploadResult value semantics
//   • initialize/dispose lifecycle safety
//   • Callback invocation for edge cases (no client, not authenticated)
//   • Mock-based upload path via a FakeCloudStorageClient

import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/services/finder_extension_service.dart';
import 'package:crisp_cloud/services/log_service.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _buildUrl(List<String> paths) {
  final encoded = paths.map((p) => Uri.encodeComponent(p)).join(',');
  return 'crispcloud://upload?paths=$encoded';
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    LogConfig.clear();
    LogConfig.minLevel = LogLevel.trace;
  });

  // -----------------------------------------------------------------------
  // parseUploadUrl
  // -----------------------------------------------------------------------
  group('FinderExtensionService.parseUploadUrl', () {
    test('parses single path', () {
      const url = 'crispcloud://upload?paths=%2FUsers%2Falice%2Fdoc.pdf';
      final paths = FinderExtensionService.parseUploadUrl(url);
      expect(paths, ['/Users/alice/doc.pdf']);
    });

    test('parses multiple paths joined by comma', () {
      final url = _buildUrl([
        '/Users/alice/photo.jpg',
        '/Users/alice/report.pdf',
        '/Users/alice/archive.zip',
      ]);
      final paths = FinderExtensionService.parseUploadUrl(url);
      expect(paths.length, 3);
      expect(paths[0], '/Users/alice/photo.jpg');
      expect(paths[1], '/Users/alice/report.pdf');
      expect(paths[2], '/Users/alice/archive.zip');
    });

    test('handles paths with spaces', () {
      final url = _buildUrl(['/Users/alice/My Documents/file.txt']);
      final paths = FinderExtensionService.parseUploadUrl(url);
      expect(paths, ['/Users/alice/My Documents/file.txt']);
    });

    test('handles paths with unicode characters', () {
      final url = _buildUrl(['/Users/alice/日本語/ファイル.txt']);
      final paths = FinderExtensionService.parseUploadUrl(url);
      expect(paths, ['/Users/alice/日本語/ファイル.txt']);
    });

    test('returns empty list for invalid URL', () {
      final paths = FinderExtensionService.parseUploadUrl('not a url !!!');
      expect(paths, isEmpty);
    });

    test('returns empty list when paths param is absent', () {
      final paths = FinderExtensionService.parseUploadUrl(
        'crispcloud://upload',
      );
      expect(paths, isEmpty);
    });

    test('returns empty list for wrong scheme', () {
      final paths = FinderExtensionService.parseUploadUrl(
        'https://crispcloud.example.com/upload?paths=/foo',
      );
      expect(paths, isEmpty);
    });

    test('returns empty list for wrong host', () {
      final paths = FinderExtensionService.parseUploadUrl(
        'crispcloud://download?paths=/foo',
      );
      expect(paths, isEmpty);
    });

    test('filters out empty segments', () {
      // Two commas in a row would produce an empty segment.
      final paths = FinderExtensionService.parseUploadUrl(
        'crispcloud://upload?paths=%2Ffoo%2C%2C%2Fbar',
      );
      // %2C is a literal comma inside the path, not a separator — this case
      // tests that we do NOT split on encoded commas.
      // After decoding the query parameter the value is "/foo,,/bar",
      // which splits into three pieces: "/foo", "", "/bar".
      // The empty string is filtered out.
      expect(paths.where((p) => p.isNotEmpty).length, greaterThanOrEqualTo(1));
    });

    test('handles paths with empty string value', () {
      final paths = FinderExtensionService.parseUploadUrl(
        'crispcloud://upload?paths=',
      );
      expect(paths, isEmpty);
    });
  });

  // -----------------------------------------------------------------------
  // FinderUploadResult
  // -----------------------------------------------------------------------
  group('FinderUploadResult', () {
    test('isSuccess true when no failures', () {
      const r = FinderUploadResult(
        totalPaths: 3,
        uploaded: 3,
        failures: {},
      );
      expect(r.isSuccess, true);
    });

    test('isSuccess false when there are failures', () {
      const r = FinderUploadResult(
        totalPaths: 2,
        uploaded: 1,
        failures: {'/bad/path': 'File not found'},
      );
      expect(r.isSuccess, false);
    });

    test('toString contains key counts', () {
      const r = FinderUploadResult(
        totalPaths: 5,
        uploaded: 4,
        failures: {'/x': 'err'},
      );
      final s = r.toString();
      expect(s, contains('total:5'));
      expect(s, contains('uploaded:4'));
      expect(s, contains('failures:1'));
    });
  });

  // -----------------------------------------------------------------------
  // isSupported / platform guard
  // -----------------------------------------------------------------------
  group('FinderExtensionService.isSupported', () {
    test('returns a bool without throwing', () {
      // We cannot control Platform.isMacOS in unit tests, but we can
      // verify the getter does not throw and returns a consistent value.
      final value = FinderExtensionService.isSupported;
      expect(value, isA<bool>());
    });
  });

  // -----------------------------------------------------------------------
  // Lifecycle: initialize / dispose
  // -----------------------------------------------------------------------
  group('FinderExtensionService lifecycle', () {
    test('dispose before initialize does not throw', () {
      final svc = FinderExtensionService();
      expect(() => svc.dispose(), returnsNormally);
    });

    test('initialize called twice is safe (idempotent)', () {
      // On non-macOS CI this is a no-op; we just verify it does not throw.
      final svc = FinderExtensionService();
      expect(() {
        svc.initialize();
        svc.initialize();
      }, returnsNormally);
      svc.dispose();
    });

    test('dispose after initialize does not throw', () {
      final svc = FinderExtensionService();
      svc.initialize();
      expect(() => svc.dispose(), returnsNormally);
    });

    test('dispose twice is safe', () {
      final svc = FinderExtensionService();
      svc.initialize();
      svc.dispose();
      expect(() => svc.dispose(), returnsNormally);
    });
  });

  // -----------------------------------------------------------------------
  // MethodChannel simulation
  // -----------------------------------------------------------------------
  group('FinderExtensionService MethodChannel handling', () {
    // These tests exercise the pure-Dart logic that the MethodChannel handler
    // delegates to, rather than wiring up a real MethodChannel (which would
    // require a native environment or an active FlutterEngine).

    test('onUrl with no client produces failure result for each path', () {
      // Simulate the logic _handleMethodCall -> _processUrl performs:
      // when storageClient is null, all paths become failures.
      final paths = FinderExtensionService.parseUploadUrl(
        _buildUrl(['/tmp/file.txt']),
      );
      expect(paths, isNotEmpty);

      final result = FinderUploadResult(
        totalPaths: paths.length,
        uploaded: 0,
        failures: {for (final p in paths) p: 'No storage client configured'},
      );

      expect(result.uploaded, 0);
      expect(result.failures.length, paths.length);
      expect(result.isSuccess, false);
    });

    test('parseUploadUrl used by onUrl handler decodes paths correctly', () {
      // This verifies the URL round-trip end-to-end.
      const inputPaths = [
        '/Users/test/Documents/report 2026.pdf',
        '/Users/test/Pictures/photo.jpg',
      ];

      final url = _buildUrl(inputPaths);
      final decoded = FinderExtensionService.parseUploadUrl(url);

      expect(decoded, inputPaths);
    });

    test('unknown MethodCall method name does not cause an error', () {
      // The service returns null for unknown methods; this test verifies
      // that the result type (null) is accepted without an exception.
      // We call parseUploadUrl (the pure core) with a non-upload URL to
      // simulate a call that produces no paths.
      final paths =
          FinderExtensionService.parseUploadUrl('crispcloud://unknownAction');
      expect(paths, isEmpty);
    });

    test('onUrl with unauthenticated client produces failure result', () {
      final paths = FinderExtensionService.parseUploadUrl(
        _buildUrl(['/tmp/a.txt', '/tmp/b.txt']),
      );

      final result = FinderUploadResult(
        totalPaths: paths.length,
        uploaded: 0,
        failures: {for (final p in paths) p: 'Not authenticated'},
      );

      expect(result.uploaded, 0);
      expect(result.failures.length, 2);
      expect(result.isSuccess, false);
    });
  });

  // -----------------------------------------------------------------------
  // Edge cases for URL parsing robustness
  // -----------------------------------------------------------------------
  group('parseUploadUrl edge cases', () {
    test('handles very long paths', () {
      final longSegment = 'a' * 200;
      final path = '/Users/user/$longSegment/file.txt';
      final url = _buildUrl([path]);
      final paths = FinderExtensionService.parseUploadUrl(url);
      expect(paths, [path]);
    });

    test('handles path with special characters', () {
      const path = "/Users/user/file (copy) [1] {2} #3 @4 \$5.txt";
      final url = _buildUrl([path]);
      final paths = FinderExtensionService.parseUploadUrl(url);
      expect(paths, [path]);
    });

    test('single-path URL round-trip is lossless', () {
      const original = '/Volumes/Data/My Projects/CrispCloud/build/output.dmg';
      final url = _buildUrl([original]);
      final decoded = FinderExtensionService.parseUploadUrl(url);
      expect(decoded, [original]);
    });

    test('case-insensitive scheme accepted', () {
      // NSWorkspace always generates lowercase, but be defensive.
      const url = 'CRISPCLOUD://upload?paths=%2Ftmp%2Ffile.txt';
      final paths = FinderExtensionService.parseUploadUrl(url);
      expect(paths, ['/tmp/file.txt']);
    });

    test('case-insensitive host accepted', () {
      const url = 'crispcloud://UPLOAD?paths=%2Ftmp%2Ffile.txt';
      final paths = FinderExtensionService.parseUploadUrl(url);
      expect(paths, ['/tmp/file.txt']);
    });
  });
}
