// test/sftp_adapter_test.dart
//
// Unit tests for SftpCliAdapter: identity parsing and config construction.
// Does NOT make real network calls.

import 'package:test/test.dart';

import 'package:crisp/adapters/sftp_adapter.dart';
import 'package:crisp/config/cli_config.dart';

void main() {
  group('SftpCliAdapter.parseIdentity', () {
    test('parses user@host', () {
      final result = SftpCliAdapter.parseIdentity('alice@my.server.com', 'password');
      expect(result['username'], equals('alice'));
      expect(result['host'], equals('my.server.com'));
      expect(result['port'], equals('22'));
      expect(result['password'], equals('password'));
    });

    test('parses user@host:port', () {
      final result = SftpCliAdapter.parseIdentity('bob@example.com:2222', 'secret');
      expect(result['username'], equals('bob'));
      expect(result['host'], equals('example.com'));
      expect(result['port'], equals('2222'));
    });

    test('throws on missing @ separator', () {
      expect(
        () => SftpCliAdapter.parseIdentity('nohostseparator', 'pw'),
        throwsA(isA<CliConfigException>()),
      );
    });
  });

  group('SftpCliAdapter.fromConfig', () {
    test('constructs from valid config', () {
      final adapter = SftpCliAdapter.fromConfig({
        'type': 'sftp',
        'username': 'alice',
        'password': 'secret',
        'host': 'my.server.com',
        'port': '22',
      });
      expect(adapter.providerName, equals('SFTP'));
    });

    test('defaults port to 22 when missing', () {
      final adapter = SftpCliAdapter.fromConfig({
        'type': 'sftp',
        'username': 'alice',
        'password': 'secret',
        'host': 'my.server.com',
      });
      expect(adapter.providerName, equals('SFTP'));
    });

    test('throws on missing required fields', () {
      expect(
        () => SftpCliAdapter.fromConfig({'type': 'sftp', 'username': 'u'}),
        throwsA(isA<CliConfigException>()),
      );
    });
  });

  group('SftpCliAdapter.share', () {
    test('throws UnsupportedError', () async {
      final adapter = SftpCliAdapter(
        username: 'u',
        password: 'p',
        host: 'h',
      );
      expect(
        () => adapter.share('/some/file'),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
