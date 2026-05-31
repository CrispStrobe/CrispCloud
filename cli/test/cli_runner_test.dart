// test/cli_runner_test.dart
//
// Integration-style tests for the CommandRunner wiring.
// Uses a temp config directory so no real network calls are needed for
// commands that operate purely on config (providers, config show, etc.).

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:test/test.dart';

import 'package:crisp/cli_app.dart';
import 'package:crisp/config/cli_config.dart';

void main() {
  late Directory tmp;
  late String configPath;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('crisp_runner_test_');
    configPath = '${tmp.path}/config.yaml';
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  CommandRunner<int> runner() => buildRunner(configPath: configPath);

  // ---------------------------------------------------------------------------
  // providers command
  // ---------------------------------------------------------------------------

  group('crisp providers', () {
    test('exits 0 with no providers configured', () async {
      final code = await runner().run(['providers']);
      expect(code, equals(0));
    });

    test('exits 0 with providers configured', () async {
      CliConfig(path: configPath).saveProvider('my-s3', {
        'type': 's3',
        'access_key': 'A',
        'secret_key': 'S',
        'endpoint': 'https://s3.amazonaws.com',
        'bucket': 'b',
        'region': 'us-east-1',
      });
      final code = await runner().run(['providers']);
      expect(code, equals(0));
    });
  });

  // ---------------------------------------------------------------------------
  // config subcommands
  // ---------------------------------------------------------------------------

  group('crisp config', () {
    test('config path exits 0', () async {
      final code = await runner().run(['config', 'path']);
      expect(code, equals(0));
    });

    test('config show exits 0 with no file', () async {
      final code = await runner().run(['config', 'show']);
      expect(code, equals(0));
    });

    test('config set-default exits 1 for unknown provider', () async {
      final code = await runner().run(['config', 'set-default', 'nonexistent']);
      expect(code, equals(1));
    });

    test('config remove exits 1 for unknown provider', () async {
      final code = await runner().run(['config', 'remove', 'nonexistent']);
      expect(code, equals(1));
    });

    test('config set-default works for known provider', () async {
      CliConfig(path: configPath).saveProvider('p1', {'type': 's3'});
      final code = await runner().run(['config', 'set-default', 'p1']);
      expect(code, equals(0));
      expect(CliConfig(path: configPath).defaultProvider, equals('p1'));
    });

    test('config remove works for known provider', () async {
      CliConfig(path: configPath).saveProvider('p1', {'type': 's3'});
      final code = await runner().run(['config', 'remove', 'p1']);
      expect(code, equals(0));
      expect(CliConfig(path: configPath).providerNames(), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // completion command
  // ---------------------------------------------------------------------------

  group('crisp completion', () {
    test('bash completion exits 0', () async {
      final code = await runner().run(['completion', 'bash']);
      expect(code, equals(0));
    });

    test('zsh completion exits 0', () async {
      final code = await runner().run(['completion', 'zsh']);
      expect(code, equals(0));
    });

    test('fish completion exits 0', () async {
      final code = await runner().run(['completion', 'fish']);
      expect(code, equals(0));
    });

    test('unknown shell exits 2', () async {
      final code = await runner().run(['completion', 'powershell']);
      expect(code, equals(2));
    });
  });

  // ---------------------------------------------------------------------------
  // share duration parsing (via ShareCommand internals)
  // ---------------------------------------------------------------------------

  group('duration parsing', () {
    test('share with no providers throws CliConfigException', () async {
      // No providers configured and no default — resolveProviderName throws.
      expect(
        () => runner().run(['share', '/file.txt']),
        throwsA(isA<CliConfigException>()),
      );
    });
  });
}
