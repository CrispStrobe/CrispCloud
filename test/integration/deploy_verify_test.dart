// test/integration/deploy_verify_test.dart
//
// Live deployment verification tests.
// Runs curl against the production Vercel deployment to confirm
// the site is up, assets are served, and critical headers are present.
//
// Usage:
//   flutter test test/integration/deploy_verify_test.dart --tags deploy --run-skipped
//
// These tests require network access and hit the live deployment.
// They are excluded from the default `flutter test` run via dart_test.yaml.

@Tags(['deploy'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

/// The production URL to test against.
/// Can be overridden via the DEPLOY_URL environment variable.
final _baseUrl = Platform.environment['DEPLOY_URL'] ??
    'https://web-nu-peach-46.vercel.app';

// ---------------------------------------------------------------------------
// Helpers — use curl via Process.run to avoid flutter_test HTTP interception
// ---------------------------------------------------------------------------

class _CurlResult {
  final int statusCode;
  final Map<String, String> headers;
  final String body;

  _CurlResult(this.statusCode, this.headers, this.body);
}

Future<_CurlResult> _curl(String path, {bool headersOnly = false}) async {
  final url = '$_baseUrl$path';
  final args = [
    '-s',       // silent
    '-L',       // follow redirects
    '-D', '-',  // dump headers to stdout
    if (headersOnly) '--head',
    url,
  ];

  final result = await Process.run('curl', args);
  final output = result.stdout as String;

  // Parse status code from first HTTP line
  int statusCode = 0;
  final headers = <String, String>{};
  String body = '';

  // Split at double newline to separate headers from body
  final parts = output.split('\r\n\r\n');
  if (parts.length >= 2) {
    final headerBlock = parts.first;
    body = parts.sublist(1).join('\r\n\r\n');

    for (final line in headerBlock.split('\r\n')) {
      if (line.startsWith('HTTP/')) {
        final match = RegExp(r'HTTP/[\d.]+ (\d+)').firstMatch(line);
        if (match != null) statusCode = int.parse(match.group(1)!);
      } else if (line.contains(':')) {
        final idx = line.indexOf(':');
        final key = line.substring(0, idx).trim().toLowerCase();
        final value = line.substring(idx + 1).trim();
        headers[key] = value;
      }
    }
  }

  return _CurlResult(statusCode, headers, body);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Deployment health', () {
    test('index page returns 200', () async {
      final result = await _curl('/');
      expect(result.statusCode, equals(200));
    });

    test('index page has text/html content type', () async {
      final result = await _curl('/');
      expect(result.headers['content-type'], contains('text/html'));
    });

    test('index page contains Flutter bootstrap', () async {
      final result = await _curl('/');
      expect(result.body, contains('flutter'),
          reason: 'index.html should reference flutter bootstrap');
      expect(result.body, contains('<base href="/">'),
          reason: 'index.html should have base href for SPA routing');
    });
  });

  group('Flutter assets', () {
    test('flutter.js is served', () async {
      final result = await _curl('/flutter.js');
      expect(result.statusCode, equals(200));
      expect(result.body.length, greaterThan(1000),
          reason: 'flutter.js should be a substantial JS file');
    });

    test('main.dart.js is served', () async {
      final result = await _curl('/main.dart.js');
      expect(result.statusCode, equals(200));
    });
  });

  group('Security headers (COOP/COEP)', () {
    test('Cross-Origin-Opener-Policy is same-origin', () async {
      final result = await _curl('/');
      expect(result.headers['cross-origin-opener-policy'], equals('same-origin'),
          reason: 'COOP header required for SharedArrayBuffer / WASM threading');
    });

    test('Cross-Origin-Embedder-Policy is require-corp', () async {
      final result = await _curl('/');
      expect(result.headers['cross-origin-embedder-policy'], equals('require-corp'),
          reason: 'COEP header required for SharedArrayBuffer / WASM threading');
    });
  });

  group('SPA routing', () {
    test('arbitrary deep path returns index.html (SPA rewrite)', () async {
      final result = await _curl('/some/deep/path/that/does/not/exist');
      expect(result.statusCode, equals(200));
      expect(result.body, contains('flutter'),
          reason: 'SPA rewrite should serve index.html for unknown client-side routes');
    });
  });

  group('Caching and performance', () {
    test('static assets have cache headers', () async {
      final result = await _curl('/flutter.js');
      expect(result.headers['cache-control'], isNotNull,
          reason: 'Static assets should have cache-control headers');
    });

    test('server header indicates Vercel', () async {
      final result = await _curl('/');
      expect(result.headers['server']?.toLowerCase(), contains('vercel'),
          reason: 'Should be deployed on Vercel');
    });

    test('HSTS header is present', () async {
      final result = await _curl('/');
      expect(result.headers['strict-transport-security'], isNotNull,
          reason: 'HTTPS should be enforced via HSTS');
    });
  });
}
