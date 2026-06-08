// lib/cli_app.dart
//
// Main CommandRunner for the crisp CLI.
// Wires all commands together and handles top-level flags.

import 'dart:io';

import 'package:args/command_runner.dart';

import 'commands/config.dart';
import 'commands/connect.dart';
import 'commands/download.dart';
import 'commands/ls.dart';
import 'commands/providers.dart';
import 'commands/search.dart';
import 'commands/share.dart';
import 'commands/sync.dart';
import 'commands/upload.dart';
import 'config/cli_config.dart';

/// Build and return a configured [CommandRunner] for the crisp CLI.
///
/// [configPath] overrides the default config file location (useful in tests).
CommandRunner<int> buildRunner({String? configPath}) {
  final config = CliConfig(path: configPath);

  final runner = CommandRunner<int>(
    'crisp',
    'CrispCloud CLI — manage cloud storage from the terminal.',
  );

  // Top-level flags
  runner.argParser.addFlag(
      'version',
      abbr: 'V',
      negatable: false,
      help: 'Print the crisp version.',
    );

  // Register commands
  runner
    ..addCommand(ConnectCommand(config))
    ..addCommand(LsCommand(config))
    ..addCommand(UploadCommand(config))
    ..addCommand(DownloadCommand(config))
    ..addCommand(SyncCommand(config))
    ..addCommand(SearchCommand(config))
    ..addCommand(ShareCommand(config))
    ..addCommand(ProvidersCommand(config))
    ..addCommand(ConfigCommand(config))
    ..addCommand(CompletionCommand());

  return runner;
}

// ---------------------------------------------------------------------------
// Shell completion command
// ---------------------------------------------------------------------------

class CompletionCommand extends Command<int> {
  @override
  final String name = 'completion';

  @override
  final String description = 'Print shell completion script.';

  @override
  String get invocation => 'crisp completion <bash|zsh|fish>';

  @override
  Future<int> run() async {
    final shell = argResults!.rest.isNotEmpty ? argResults!.rest.first : '';

    switch (shell.toLowerCase()) {
      case 'bash':
        stdout.writeln(_bashCompletion);
      case 'zsh':
        stdout.writeln(_zshCompletion);
      case 'fish':
        stdout.writeln(_fishCompletion);
      default:
        stderr.writeln('Usage: crisp completion <bash|zsh|fish>');
        stderr.writeln('');
        stderr.writeln('Then add to your shell profile:');
        stderr.writeln('  bash: eval "\$(crisp completion bash)"');
        stderr.writeln('  zsh:  eval "\$(crisp completion zsh)"');
        stderr.writeln('  fish: crisp completion fish | source');
        return 2;
    }
    return 0;
  }

  static const _bashCompletion = r'''
# crisp bash completion
_crisp_completion() {
  local cur prev words
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"

  local commands="connect ls upload download sync search share providers config completion"

  if [[ ${COMP_CWORD} -eq 1 ]]; then
    COMPREPLY=( $(compgen -W "${commands}" -- "${cur}") )
    return 0
  fi

  case "${COMP_WORDS[1]}" in
    ls|download|search|share|sync)
      COMPREPLY=( $(compgen -W "--provider --json" -- "${cur}") )
      ;;
    upload)
      COMPREPLY=( $(compgen -f -- "${cur}") )
      ;;
    connect)
      COMPREPLY=( $(compgen -W "s3 sftp webdav" -- "${cur}") )
      ;;
    config)
      COMPREPLY=( $(compgen -W "show path set-default remove" -- "${cur}") )
      ;;
    completion)
      COMPREPLY=( $(compgen -W "bash zsh fish" -- "${cur}") )
      ;;
  esac
}
complete -F _crisp_completion crisp
''';

  static const _zshCompletion = r'''
#compdef crisp

_crisp() {
  local state

  _arguments \
    '1: :->command' \
    '*: :->args'

  case $state in
    command)
      _values 'command' \
        'connect[Connect a provider]' \
        'ls[List files]' \
        'upload[Upload a file]' \
        'download[Download a file]' \
        'sync[Sync local to remote]' \
        'search[Search for files]' \
        'share[Generate share link]' \
        'providers[List providers]' \
        'config[Manage configuration]' \
        'completion[Shell completion]'
      ;;
    args)
      case $words[2] in
        connect)
          _values 'type' s3 sftp webdav
          ;;
        config)
          _values 'subcommand' show path set-default remove
          ;;
        completion)
          _values 'shell' bash zsh fish
          ;;
        *)
          _files
          ;;
      esac
      ;;
  esac
}

_crisp "$@"
''';

  static const _fishCompletion = r'''
# crisp fish completion

set -l commands connect ls upload download sync search share providers config completion

# Top-level commands
complete -c crisp -f -n "not __fish_seen_subcommand_from $commands" -a connect -d "Connect a provider"
complete -c crisp -f -n "not __fish_seen_subcommand_from $commands" -a ls -d "List files"
complete -c crisp -f -n "not __fish_seen_subcommand_from $commands" -a upload -d "Upload a file"
complete -c crisp -f -n "not __fish_seen_subcommand_from $commands" -a download -d "Download a file"
complete -c crisp -f -n "not __fish_seen_subcommand_from $commands" -a sync -d "Sync local to remote"
complete -c crisp -f -n "not __fish_seen_subcommand_from $commands" -a search -d "Search for files"
complete -c crisp -f -n "not __fish_seen_subcommand_from $commands" -a share -d "Generate share link"
complete -c crisp -f -n "not __fish_seen_subcommand_from $commands" -a providers -d "List providers"
complete -c crisp -f -n "not __fish_seen_subcommand_from $commands" -a config -d "Manage configuration"
complete -c crisp -f -n "not __fish_seen_subcommand_from $commands" -a completion -d "Shell completion"

# connect provider types
complete -c crisp -f -n "__fish_seen_subcommand_from connect" -a "s3 sftp webdav"

# config subcommands
complete -c crisp -f -n "__fish_seen_subcommand_from config" -a "show path set-default remove"

# completion shells
complete -c crisp -f -n "__fish_seen_subcommand_from completion" -a "bash zsh fish"

# common flags
complete -c crisp -n "__fish_seen_subcommand_from ls download search share sync" -l provider -s p -d "Provider name"
complete -c crisp -n "__fish_seen_subcommand_from ls download search share sync upload" -l json -s j -d "JSON output"
''';
}
