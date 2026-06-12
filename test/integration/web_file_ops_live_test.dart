// test/integration/web_file_ops_live_test.dart
//
// Live deployment verification for web file operations.
// Verifies the deployed Flutter web app loads correctly and contains
// the expected JavaScript code for multi-root FSA handles and
// web file operations (copy, move, rename, mkdir).
//
// Usage:
//   flutter test test/integration/web_file_ops_live_test.dart --tags deploy --run-skipped
//
// Requires network access. Excluded from default `flutter test` via dart_test.yaml.

@Tags(['deploy'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

final _baseUrl = Platform.environment['DEPLOY_URL'] ??
    'https://crisp-cloud.vercel.app';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Future<String> _fetchBody(String path) async {
  final url = '$_baseUrl$path';
  final result = await Process.run('curl', ['-s', '-L', url]);
  return result.stdout as String;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Web file ops deploy verification', () {
    late String indexHtml;

    setUpAll(() async {
      indexHtml = await _fetchBody('/');
    });

    test('site loads (index.html has flutter content)', () {
      expect(indexHtml, contains('flutter'));
    });

    test('main.dart.js is referenced', () {
      // Flutter web embeds a script tag referencing the compiled JS
      expect(indexHtml, contains('main.dart.js'));
    });

    test('main.dart.js loads successfully', () async {
      // Fetch a small portion of main.dart.js to verify it exists
      final result = await Process.run('curl', [
        '-s', '-L', '-o', '/dev/null', '-w', '%{http_code}',
        '$_baseUrl/main.dart.js',
      ]);
      final statusCode = (result.stdout as String).trim();
      expect(statusCode, equals('200'),
          reason: 'main.dart.js should return 200');
    });

    test('service worker is present', () async {
      final result = await Process.run('curl', [
        '-s', '-L', '-o', '/dev/null', '-w', '%{http_code}',
        '$_baseUrl/flutter_service_worker.js',
      ]);
      final statusCode = (result.stdout as String).trim();
      expect(statusCode, equals('200'),
          reason: 'flutter_service_worker.js should return 200');
    });

    test('manifest.json is present for PWA', () async {
      final body = await _fetchBody('/manifest.json');
      expect(body, contains('CrispCloud'));
    });
  });

  group('Compiled code contains web file op fixes', () {
    late String mainJs;

    setUpAll(() async {
      // Fetch the compiled JS — it's large but we only need to search for markers
      mainJs = await _fetchBody('/main.dart.js');
    });

    test('contains multi-root handle logic (findRootHandle pattern)', () {
      // The compiled JS should contain our _findRootHandle or _rootHandles logic.
      // Dart compiles to minified JS, so look for characteristic patterns.
      // The string "rootHandles" or "findRootHandle" may survive in debug builds,
      // but in release/minified builds we check for the log message instead.
      final hasRootHandles = mainJs.contains('rootHandles') ||
          mainJs.contains('findRootHandle') ||
          mainJs.contains('No root handle for path');
      final hasMultiRoot = mainJs.contains('Attempting write via directory handle navigation') ||
          mainJs.contains('directory handle navigation');
      expect(hasRootHandles || hasMultiRoot, isTrue,
          reason: 'Compiled JS should contain multi-root handle code');
    });

    test('contains createDirectory log marker', () {
      // Our createDirectory method logs "createDirectory:"
      expect(mainJs.contains('createDirectory'), isTrue,
          reason: 'Compiled JS should contain createDirectory code');
    });

    test('does NOT contain old _rootDirHandle pattern', () {
      // The old single-handle pattern should be gone.
      // In minified code this won't match literally, so we check the log message
      // that was unique to the old code.
      expect(mainJs.contains('Attempting direct write to folder handle'), isFalse,
          reason: 'Old saveFile log message should be gone');
    });

    test('contains source-aware copy/move logic', () {
      // The isLocalSource check string or panelSourceProvider reference
      // should be in the compiled output
      final hasSourceAware = mainJs.contains('isLocalSource') ||
          mainJs.contains('panelSourceProvider') ||
          mainJs.contains('Folder move not yet supported on web');
      expect(hasSourceAware, isTrue,
          reason: 'Compiled JS should contain source-aware file op logic');
    });
  });
}
