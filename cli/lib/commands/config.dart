// lib/commands/config.dart
//
// crisp config show         — print the config file path and contents
// crisp config set-default <name>  — set the default provider
// crisp config remove <name>       — remove a provider entry
// crisp config path         — print just the config file path

import 'dart:io';

import 'package:args/command_runner.dart';

import '../config/cli_config.dart';

class ConfigCommand extends Command<int> {
  @override
  final String name = 'config';

  @override
  final String description = 'Show or manage the crisp configuration.';

  final CliConfig config;

  ConfigCommand(this.config) {
    addSubcommand(_ConfigShowCommand(config));
    addSubcommand(_ConfigPathCommand(config));
    addSubcommand(_ConfigSetDefaultCommand(config));
    addSubcommand(_ConfigRemoveCommand(config));
  }

  @override
  Future<int> run() async {
    printUsage();
    return 0;
  }
}

class _ConfigShowCommand extends Command<int> {
  @override
  final String name = 'show';

  @override
  final String description = 'Print the configuration file contents.';

  final CliConfig config;

  _ConfigShowCommand(this.config);

  @override
  Future<int> run() async {
    stdout.writeln('Config file: ${config.configPath}');
    stdout.writeln('');
    final file = File(config.configPath);
    if (!file.existsSync()) {
      stdout.writeln('(No config file found — run "crisp connect" to add a provider)');
      return 0;
    }
    // Mask secrets before printing
    final raw = file.readAsStringSync();
    final masked = _maskSecrets(raw);
    stdout.writeln(masked);
    return 0;
  }

  /// Replace lines like "  secret_key: ..." or "  password: ..." with masked values.
  static String _maskSecrets(String yaml) {
    return yaml.replaceAllMapped(
      RegExp(r'^(\s*(?:secret_key|password|access_token|api_key):\s*)(.+)$',
          multiLine: true),
      (m) => '${m.group(1)}****',
    );
  }
}

class _ConfigPathCommand extends Command<int> {
  @override
  final String name = 'path';

  @override
  final String description = 'Print the config file path.';

  final CliConfig config;

  _ConfigPathCommand(this.config);

  @override
  Future<int> run() async {
    stdout.writeln(config.configPath);
    return 0;
  }
}

class _ConfigSetDefaultCommand extends Command<int> {
  @override
  final String name = 'set-default';

  @override
  final String description = 'Set the default provider.';

  final CliConfig config;

  _ConfigSetDefaultCommand(this.config);

  @override
  String get invocation => 'crisp config set-default <provider-name>';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      usageException('Usage: crisp config set-default <provider-name>');
    }
    final name = rest.first;

    if (!config.providerNames().contains(name)) {
      stderr.writeln('Unknown provider: $name');
      stderr.writeln('Known providers: ${config.providerNames().join(', ')}');
      return 1;
    }

    config.defaultProvider = name;
    stdout.writeln('"$name" is now the default provider.');
    return 0;
  }
}

class _ConfigRemoveCommand extends Command<int> {
  @override
  final String name = 'remove';

  @override
  final String description = 'Remove a configured provider.';

  final CliConfig config;

  _ConfigRemoveCommand(this.config);

  @override
  String get invocation => 'crisp config remove <provider-name>';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      usageException('Usage: crisp config remove <provider-name>');
    }
    final name = rest.first;

    if (!config.providerNames().contains(name)) {
      stderr.writeln('Provider "$name" not found.');
      return 1;
    }

    config.removeProvider(name);
    stdout.writeln('Removed provider "$name".');
    return 0;
  }
}
