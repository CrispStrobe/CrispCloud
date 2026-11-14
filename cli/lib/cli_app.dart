// lib/cli_app.dart
//
// Main CommandRunner for the crisp CLI.
// Wires all commands together and handles top-level flags.

import 'dart:io';

import 'package:args/command_runner.dart';

import 'commands/config.dart';
import 'commands/connect.dart';
import 'commands/download.dart';
import 'commands/du.dart';
import 'commands/catalog.dart';
import 'commands/ls.dart';
import 'commands/pdf.dart';
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

  final runner = PdfAwareCommandRunner(
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
    ..addCommand(DuCommand())
    ..addCommand(CatalogCommand())
    ..addCommand(ShareCommand(config))
    ..addCommand(ProvidersCommand(config))
    ..addCommand(ConfigCommand(config))
    ..addCommand(PdfCommand(config))
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

  local commands="connect ls upload download sync search du catalog share providers config pdf completion"

  if [[ ${COMP_CWORD} -eq 1 ]]; then
    COMPREPLY=( $(compgen -W "${commands}" -- "${cur}") )
    return 0
  fi

  case "${COMP_WORDS[1]}" in
    ls|download|search|share|sync)
      COMPREPLY=( $(compgen -W "--provider --json" -- "${cur}") )
      ;;
    du)
      COMPREPLY=( $(compgen -f -- "${cur}") $(compgen -W "--top --recursive --files-only --dirs-only --max-entries --max-depth --bytes --json --index" -- "${cur}") )
      ;;
    catalog)
      if [[ ${COMP_CWORD} -eq 2 ]]; then
        COMPREPLY=( $(compgen -W "scan import export info search" -- "${cur}") )
      else
        COMPREPLY=( $(compgen -f -- "${cur}") $(compgen -W "--output --replace --allow-lossy --top --max-entries --max-depth" -- "${cur}") )
      fi
      ;;
    upload)
      COMPREPLY=( $(compgen -f -- "${cur}") )
      ;;
    connect)
      COMPREPLY=( $(compgen -W "s3 sftp smb webdav" -- "${cur}") )
      ;;
    config)
      COMPREPLY=( $(compgen -W "show path set-default remove smb-backend" -- "${cur}") )
      ;;
    pdf)
      if [[ ${COMP_CWORD} -eq 2 ]]; then
        COMPREPLY=( $(compgen -W "info text search merge extract rotate reorder delete-pages watermark fill insert-image ocr" -- "${cur}") )
      else
        COMPREPLY=( $(compgen -f -- "${cur}") $(compgen -W "--output --pages --json --password-file --overwrite" -- "${cur}") )
      fi
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
        'catalog[Persistent indexes and CAF interchange]' \
        'du[Find largest local files and folders]' \
        'search[Search for files]' \
        'share[Generate share link]' \
        'providers[List providers]' \
        'config[Manage configuration]' \
        'pdf[Inspect and edit PDFs]' \
        'completion[Shell completion]'
      ;;
    args)
      case $words[2] in
        connect)
          _values 'type' s3 sftp smb webdav
          ;;
        config)
          _values 'subcommand' show path set-default remove smb-backend
          ;;
        catalog)
          if (( CURRENT == 3 )); then
            _values 'catalogue operation' scan import export info search
          else
            _files
          fi
          ;;
        du)
          _arguments '--top[Number of results]:count:' '--recursive[Rank all depths]' '--files-only[Largest individual files]' '--dirs-only[Directories only]' '--max-entries[Entry budget]:count:' '--max-depth[Depth budget]:depth:' '--bytes[Exact bytes]' '--json[JSON output]' '--index[Saved catalogue]:index:_files' '*:path:_files'
          ;;
        pdf)
          if (( CURRENT == 3 )); then
            _values 'PDF operation' info text search merge extract rotate reorder delete-pages watermark fill insert-image ocr
          else
            _files
          fi
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

set -l commands connect ls upload download sync search du catalog share providers config pdf completion

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
complete -c crisp -f -n "not __fish_seen_subcommand_from $commands" -a pdf -d "Inspect and edit PDFs"
complete -c crisp -f -n "not __fish_seen_subcommand_from $commands" -a completion -d "Shell completion"

complete -c crisp -n "not __fish_seen_subcommand_from $commands" -a du -d "Find largest local files and folders"
complete -c crisp -n "__fish_seen_subcommand_from du" -l top -s n -x
complete -c crisp -n "__fish_seen_subcommand_from du" -l recursive -s r
complete -c crisp -n "__fish_seen_subcommand_from du" -l files-only
complete -c crisp -n "__fish_seen_subcommand_from du" -l dirs-only
complete -c crisp -n "__fish_seen_subcommand_from du" -l max-entries -x
complete -c crisp -n "__fish_seen_subcommand_from du" -l max-depth -x
complete -c crisp -n "__fish_seen_subcommand_from du" -l bytes
complete -c crisp -n "__fish_seen_subcommand_from du" -l json -s j

complete -c crisp -n "not __fish_seen_subcommand_from $commands" -a catalog -d "Persistent indexes and CAF interchange"
complete -c crisp -n "__fish_seen_subcommand_from catalog; and not __fish_seen_subcommand_from scan import export info search" -a "scan import export info search"
complete -c crisp -n "__fish_seen_subcommand_from catalog" -l output -s o -r
complete -c crisp -n "__fish_seen_subcommand_from catalog" -l replace
complete -c crisp -n "__fish_seen_subcommand_from catalog" -l allow-lossy
complete -c crisp -n "__fish_seen_subcommand_from du" -l index -r

# connect provider types
complete -c crisp -f -n "__fish_seen_subcommand_from connect" -a "s3 sftp smb webdav"

# config subcommands
complete -c crisp -f -n "__fish_seen_subcommand_from config" -a "show path set-default remove smb-backend"

# completion shells
complete -c crisp -f -n "__fish_seen_subcommand_from completion" -a "bash zsh fish"

# PDF operations
complete -c crisp -f -n "__fish_seen_subcommand_from pdf; and not __fish_seen_subcommand_from info text search merge extract rotate reorder delete-pages watermark fill insert-image ocr" -a "info text search merge extract rotate reorder delete-pages watermark fill insert-image ocr"
complete -c crisp -n "__fish_seen_subcommand_from pdf" -l output -s o -r -d "Separate output PDF"
complete -c crisp -n "__fish_seen_subcommand_from pdf" -l pages -r -d "One-based page range"
complete -c crisp -n "__fish_seen_subcommand_from pdf" -l password-file -r -d "Private password file"
complete -c crisp -n "__fish_seen_subcommand_from pdf" -l json -s j -d "JSON output"

# common flags
complete -c crisp -n "__fish_seen_subcommand_from ls download search share sync" -l provider -s p -d "Provider name"
complete -c crisp -n "__fish_seen_subcommand_from ls download search share sync upload" -l json -s j -d "JSON output"
''';
}
