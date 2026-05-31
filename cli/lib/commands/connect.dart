// lib/commands/connect.dart
//
// crisp connect <type> <identity>
//   --secret <secret>   credential secret (password / secret key)
//   --name <name>       provider alias (default: type + index)
//   --default           set as the default provider after connecting
//
// Examples:
//   crisp connect s3 AKID@s3.amazonaws.com/mybucket --secret wJal... --name prod-s3 --default
//   crisp connect sftp user@my.server.com --secret pass123 --name home-sftp
//   crisp connect webdav alice@https://dav.example.com --secret pw --name dav

import 'dart:io';

import 'package:args/command_runner.dart';

import '../adapters/cli_adapter_factory.dart';
import '../adapters/s3_adapter.dart';
import '../adapters/sftp_adapter.dart';
import '../adapters/webdav_adapter.dart';
import '../config/cli_config.dart';

class ConnectCommand extends Command<int> {
  @override
  final String name = 'connect';

  @override
  final String description =
      'Connect a cloud storage provider and save its credentials.';

  @override
  String get invocation => 'crisp connect <type> <identity>';

  final CliConfig config;

  ConnectCommand(this.config) {
    argParser
      ..addOption(
        'secret',
        abbr: 's',
        help: 'Credential secret: password (SFTP/WebDAV) or secret key (S3).',
      )
      ..addOption(
        'name',
        abbr: 'n',
        help: 'Alias for this provider (used in subsequent commands).',
      )
      ..addFlag(
        'default',
        abbr: 'd',
        negatable: false,
        help: 'Set as the default provider.',
      );
  }

  @override
  Future<int> run() async {
    final args = argResults!;
    final rest = args.rest;

    if (rest.length < 2) {
      usageException('Usage: crisp connect <type> <identity>');
    }

    final type = rest[0].toLowerCase();
    final identity = rest[1];
    final secret = args['secret'] as String?;
    final makeDefault = args['default'] as bool;

    if (secret == null || secret.isEmpty) {
      // Read from stdin if not provided
      stderr.write('Enter secret (password/secret-key): ');
      final input = stdin.readLineSync();
      if (input == null || input.isEmpty) {
        stderr.writeln('Error: secret is required.');
        return 1;
      }
      return _doConnect(type, identity, input, args['name'] as String?, makeDefault);
    }

    return _doConnect(type, identity, secret, args['name'] as String?, makeDefault);
  }

  Future<int> _doConnect(
    String type,
    String identity,
    String secret,
    String? aliasArg,
    bool makeDefault,
  ) async {
    Map<String, dynamic> providerMap;

    switch (type) {
      case 's3':
        final parsed = S3CliAdapter.parseIdentity(identity, secret);
        providerMap = {'type': 's3', ...parsed};
        break;
      case 'sftp':
        final parsed = SftpCliAdapter.parseIdentity(identity, secret);
        providerMap = {'type': 'sftp', ...parsed};
        break;
      case 'webdav':
        final parsed = WebDavCliAdapter.parseIdentity(identity, secret);
        providerMap = {'type': 'webdav', ...parsed};
        break;
      default:
        stderr.writeln('Unknown provider type: $type. Supported: s3, sftp, webdav');
        return 2;
    }

    // Derive a name
    final existingNames = config.providerNames();
    final alias = aliasArg ??
        _uniqueName(type, existingNames);

    // Validate the connection
    stdout.write('Testing connection to $type/$alias...');
    try {
      final adapter = createAdapter(alias, providerMap);
      await adapter.list('/');
      stdout.writeln(' OK');
      await adapter.dispose();
    } catch (e) {
      stdout.writeln(' FAILED');
      stderr.writeln('Connection test failed: $e');
      return 1;
    }

    config.saveProvider(alias, providerMap);
    stdout.writeln('Provider "$alias" saved to ${config.configPath}');

    if (makeDefault) {
      config.defaultProvider = alias;
      stdout.writeln('"$alias" is now the default provider.');
    }

    return 0;
  }

  String _uniqueName(String type, List<String> existing) {
    if (!existing.contains(type)) return type;
    for (int i = 2; i < 100; i++) {
      final candidate = '$type-$i';
      if (!existing.contains(candidate)) return candidate;
    }
    return '$type-${DateTime.now().millisecondsSinceEpoch}';
  }
}
