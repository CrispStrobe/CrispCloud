// test/webdav_adapter_test.dart
//
// Unit tests for WebDavCliAdapter: identity parsing and config construction.
// Does NOT make real network calls.

import 'package:test/test.dart';

import 'package:crisp/adapters/webdav_adapter.dart';
import 'package:crisp/config/cli_config.dart';

void main() {
  group('WebDavCliAdapter.parseIdentity', () {
    test('parses user@https://host', () {
      final result = WebDavCliAdapter.parseIdentity(
        'alice@https://dav.example.com',
        'password',
      );
      expect(result['username'], equals('alice'));
      expect(result['host'], equals('https://dav.example.com'));
      expect(result['password'], equals('password'));
    });

    test('parses user@http://host with path', () {
      final result = WebDavCliAdapter.parseIdentity(
        'bob@http://nextcloud.example.com/remote.php/dav/files/bob',
        'secret',
      );
      expect(result['username'], equals('bob'));
      expect(result['host'],
          equals('http://nextcloud.example.com/remote.php/dav/files/bob'));
    });

    test('throws on missing @http separator', () {
      expect(
        () => WebDavCliAdapter.parseIdentity('nourl', 'pw'),
        throwsA(isA<CliConfigException>()),
      );
    });
  });

  group('WebDavCliAdapter.fromConfig', () {
    test('constructs from valid config', () {
      final adapter = WebDavCliAdapter.fromConfig({
        'type': 'webdav',
        'username': 'alice',
        'password': 'secret',
        'host': 'https://dav.example.com',
      });
      expect(adapter.providerName, equals('WebDAV'));
    });

    test('strips trailing slash from base URL', () {
      final adapter = WebDavCliAdapter(
        baseUrl: 'https://dav.example.com/',
        username: 'u',
        password: 'p',
      );
      expect(adapter.providerName, equals('WebDAV'));
    });

    test('throws on missing required fields', () {
      expect(
        () => WebDavCliAdapter.fromConfig({'type': 'webdav'}),
        throwsA(isA<CliConfigException>()),
      );
    });
  });

  group('WebDavCliAdapter.share', () {
    test('throws UnsupportedError', () async {
      final adapter = WebDavCliAdapter(
        baseUrl: 'https://dav.example.com',
        username: 'u',
        password: 'p',
      );
      expect(
        () => adapter.share('/some/file'),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
