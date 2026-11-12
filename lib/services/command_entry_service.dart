import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/command_entry.dart';
import '../models/custom_toolbar_command.dart';
import 'macos_app_store.dart';
import 'toolbar_command_runner.dart';

export '../models/command_entry.dart';

/// Available filesystem evidence, including the resolved target of a symlink.
/// The process API does not offer an atomic open-and-execute handle; native
/// acceptance must not present this metadata comparison as such a guarantee.
class CommandEntryFileIdentity {
  const CommandEntryFileIdentity({
    required this.resolvedPath,
    required this.isDirectory,
    required this.size,
    required this.modified,
    required this.changed,
    required this.mode,
  });
  final String resolvedPath;
  final bool isDirectory;
  final int size, mode;
  final DateTime modified, changed;

  @override
  bool operator ==(Object other) =>
      other is CommandEntryFileIdentity &&
      resolvedPath == other.resolvedPath &&
      isDirectory == other.isDirectory &&
      size == other.size &&
      modified == other.modified &&
      changed == other.changed &&
      mode == other.mode;

  @override
  int get hashCode =>
      Object.hash(resolvedPath, isDirectory, size, modified, changed, mode);
}

abstract interface class CommandEntryHost {
  String? get platform;
  List<String> get searchPath;
  Future<CommandEntryFileIdentity?> inspect(String path);
}

class NativeCommandEntryHost implements CommandEntryHost {
  const NativeCommandEntryHost();

  @override
  String? get platform =>
      kIsWeb ||
          !const {
            'linux',
            'macos',
            'windows',
          }.contains(Platform.operatingSystem) ||
          isMacAppStoreBuild()
      ? null
      : Platform.operatingSystem;

  @override
  List<String> get searchPath {
    if (platform == null) return const [];
    return (Platform.environment['PATH'] ?? '').split(
      platform == 'windows' ? ';' : ':',
    );
  }

  @override
  Future<CommandEntryFileIdentity?> inspect(String path) async {
    try {
      final resolved = await File(path).resolveSymbolicLinks();
      final stat = await FileStat.stat(resolved);
      if (stat.type != FileSystemEntityType.file &&
          stat.type != FileSystemEntityType.directory) {
        return null;
      }
      // Detect a symlink changing while its target was inspected.
      if (await File(path).resolveSymbolicLinks() != resolved) return null;
      final after = await FileStat.stat(resolved);
      if (after.type != stat.type ||
          after.size != stat.size ||
          after.modified != stat.modified ||
          after.changed != stat.changed ||
          after.mode != stat.mode) {
        return null;
      }
      return CommandEntryFileIdentity(
        resolvedPath: resolved,
        isDirectory: stat.type == FileSystemEntityType.directory,
        size: stat.size,
        modified: stat.modified,
        changed: stat.changed,
        mode: stat.mode,
      );
    } on FileSystemException {
      return null;
    }
  }
}

class PreparedCommandEntry {
  PreparedCommandEntry._({
    required this.command,
    required this.prepared,
    required this.context,
    required this.platform,
    required this.isDraftCurrent,
    required this.requiresTarget,
    required Map<String, CommandEntryFileIdentity> identities,
  }) : _identities = Map.unmodifiable(identities);

  final CustomToolbarCommand command;
  final PreparedToolbarCommand prepared;
  final CommandEntryContext context;
  final String platform;
  final bool Function() isDraftCurrent;
  final bool requiresTarget;
  final Map<String, CommandEntryFileIdentity> _identities;
  bool _used = false;
}

/// A transient, source-bound argv review. Program lookup reads absolute PATH
/// entries only and pins a resolved executable; it never invokes a shell,
/// searches the current directory implicitly, or saves a lookup result.
class CommandEntryService {
  const CommandEntryService({
    this.host = const NativeCommandEntryHost(),
    this.processStarter,
  });
  final CommandEntryHost host;
  final CommandProcessStarter? processStarter;
  String? get platform => host.platform;

  p.Context get _paths => platform == 'windows' ? p.windows : p.posix;

  void _check(CommandEntryContext captured, bool Function() isCurrent) {
    final invocation = captured.invocation;
    if (platform == null) {
      throw const CommandEntryException(CommandEntryFailure.unsupported);
    }
    if (!invocation.storage.isLocal ||
        !_paths.isAbsolute(invocation.currentPath) ||
        invocation.currentPath.contains('\u0000')) {
      throw const CommandEntryException(CommandEntryFailure.localRequired);
    }
    if (captured.isDisposed || !invocation.isCurrent() || !isCurrent()) {
      throw const CommandEntryException(CommandEntryFailure.changed);
    }
    if (captured.selection.length > 256) {
      throw const CommandEntryException(CommandEntryFailure.selectionLimit);
    }
    if (!listEquals(
          captured.selection.map((row) => row.path).toList(),
          invocation.selectedPaths,
        ) ||
        captured.selection.any(
          (row) =>
              !_paths.isAbsolute(row.path) ||
              row.path.contains('\u0000') ||
              row.name.isEmpty ||
              row.name != _paths.basename(row.path) ||
              !_paths.equals(_paths.dirname(row.path), invocation.currentPath),
        )) {
      throw const CommandEntryException(
        CommandEntryFailure.selectionUnavailable,
      );
    }
  }

  Future<CommandEntryFileIdentity> _inspectAccessible(
    String path,
    CommandEntryContext captured,
    void Function() check,
  ) async {
    check();
    final access = await captured.hasExistingAccess(path);
    check();
    if (!access) {
      throw const CommandEntryException(CommandEntryFailure.accessUnavailable);
    }
    final identity = await host.inspect(path);
    check();
    if (identity == null) {
      throw const CommandEntryException(CommandEntryFailure.accessUnavailable);
    }
    // A symlink cannot extend an existing grant into another target.
    if (identity.resolvedPath != path) {
      final targetAccess = await captured.hasExistingAccess(
        identity.resolvedPath,
      );
      check();
      if (!targetAccess) {
        throw const CommandEntryException(
          CommandEntryFailure.accessUnavailable,
        );
      }
    }
    return identity;
  }

  bool _canExecute(CommandEntryFileIdentity identity) =>
      !identity.isDirectory &&
      (platform == 'windows'
          ? identity.resolvedPath.toLowerCase().endsWith('.exe')
          : identity.mode & 0x49 != 0);

  void _checkProgramModel(String program, List<String> arguments) {
    final name = _paths.basename(program).toLowerCase();
    final executableName = name.endsWith('.exe')
        ? name.substring(0, name.length - 4)
        : name;
    if ((platform == 'windows' && !name.endsWith('.exe')) ||
        const {
          'sh',
          'bash',
          'zsh',
          'dash',
          'ksh',
          'fish',
          'csh',
          'tcsh',
          'cmd',
          'powershell',
          'pwsh',
        }.contains(executableName)) {
      throw const CommandEntryException(CommandEntryFailure.unsupportedProgram);
    }
    final options =
        RegExp(r'^python(?:\d+(?:\.\d+)*)?$').hasMatch(executableName)
        ? _pythonOptions
        : _interpreterOptions[executableName];
    if (options != null && !options.supports(arguments)) {
      throw const CommandEntryException(CommandEntryFailure.unsupportedProgram);
    }
  }

  Future<(String, CommandEntryFileIdentity)> _resolve(
    String program,
    List<String> arguments,
    CommandEntryContext captured,
    void Function() check,
  ) async {
    if (program.isEmpty ||
        program.length > 4096 ||
        program.contains(RegExp(r'[\x00\r\n]'))) {
      throw const CommandEntryException(CommandEntryFailure.invalidProgram);
    }
    final absolute = _paths.isAbsolute(program);
    if (!absolute &&
        (program.contains('/') ||
            program.contains('\\') ||
            program.contains(':'))) {
      throw const CommandEntryException(CommandEntryFailure.invalidProgram);
    }
    var name = program;
    if (platform == 'windows' && !absolute && _paths.extension(name).isEmpty) {
      name = '$name.exe';
    }
    _checkProgramModel(name, arguments);
    final candidates = absolute
        ? <String>[program]
        : <String>[
            for (final directory in host.searchPath.take(128))
              if (directory.length <= 4096 &&
                  !directory.contains('\u0000') &&
                  _paths.isAbsolute(directory))
                _paths.join(directory, name),
          ];
    for (final candidate in candidates.toSet()) {
      check();
      final found = await host.inspect(candidate);
      check();
      if (found == null || !_canExecute(found)) continue;
      _checkProgramModel(found.resolvedPath, arguments);
      final identity = await _inspectAccessible(candidate, captured, check);
      if (identity != found) {
        throw const CommandEntryException(CommandEntryFailure.changed);
      }
      return (candidate, identity);
    }
    throw const CommandEntryException(
      CommandEntryFailure.executableUnavailable,
    );
  }

  Future<PreparedCommandEntry> prepare(
    CommandEntryDraft draft,
    CommandEntryContext captured, {
    required bool Function() isDraftCurrent,
  }) async {
    final saved = draft.savedCommand;
    final requiresTarget =
        saved?.arguments.any((arg) => arg.contains('{TARGET}')) ?? false;
    void check() {
      _check(captured, isDraftCurrent);
      if (requiresTarget &&
          captured.invocation.targetIsCurrent?.call() != true) {
        throw const CommandEntryException(CommandEntryFailure.changed);
      }
    }

    check();
    final extra = parseCommandEntryArguments(draft.arguments);
    PreparedToolbarCommand? configured;
    if (saved != null) {
      try {
        configured = prepareToolbarCommand(saved, captured.invocation);
      } catch (_) {
        throw const CommandEntryException(CommandEntryFailure.savedUnavailable);
      }
    }
    final arguments = <String>[...?configured?.arguments, ...extra];
    if (arguments.length > 10000 ||
        arguments.any((arg) => arg.contains('\u0000')) ||
        arguments.fold<int>(
              0,
              (size, arg) => size + utf8.encode(arg).length + 1,
            ) >
            1024 * 1024) {
      throw const CommandEntryException(CommandEntryFailure.invalidArguments);
    }
    final directory =
        configured?.workingDirectory ?? captured.invocation.currentPath;
    if (!_paths.isAbsolute(directory) || directory.contains('\u0000')) {
      throw const CommandEntryException(CommandEntryFailure.localRequired);
    }
    final identities = <String, CommandEntryFileIdentity>{};
    for (final path in {
      captured.invocation.currentPath,
      directory,
      if (requiresTarget) captured.invocation.targetPath!,
    }) {
      final identity = await _inspectAccessible(path, captured, check);
      if (!identity.isDirectory) {
        throw const CommandEntryException(CommandEntryFailure.localRequired);
      }
      identities[path] = identity;
    }
    for (final row in captured.selection) {
      final identity = await _inspectAccessible(row.path, captured, check);
      if (identity.isDirectory != row.isDirectory ||
          (!row.isDirectory && row.size != null && identity.size != row.size) ||
          (row.modified != null && identity.modified != row.modified)) {
        throw const CommandEntryException(
          CommandEntryFailure.selectionUnavailable,
        );
      }
      identities[row.path] = identity;
    }
    final (candidate, executable) = await _resolve(
      configured?.executable ?? draft.program.trim(),
      arguments,
      captured,
      check,
    );
    identities[candidate] = executable;
    identities[executable.resolvedPath] = executable;
    check();
    return PreparedCommandEntry._(
      command: CustomToolbarCommand(
        id: 'command-entry',
        label: saved?.label ?? _paths.basename(executable.resolvedPath),
        executable: executable.resolvedPath,
        timeoutSeconds: saved?.timeoutSeconds ?? 300,
      ),
      prepared: PreparedToolbarCommand(
        executable.resolvedPath,
        arguments,
        directory,
      ),
      context: captured,
      platform: platform!,
      isDraftCurrent: isDraftCurrent,
      requiresTarget: requiresTarget,
      identities: identities,
    );
  }

  Future<RunningToolbarCommand> start(
    PreparedCommandEntry review, {
    required bool Function() isReviewCurrent,
  }) async {
    void check() {
      _check(
        review.context,
        () => review.isDraftCurrent() && isReviewCurrent(),
      );
      if (review.platform != platform) {
        throw const CommandEntryException(CommandEntryFailure.changed);
      }
      if (review.requiresTarget &&
          review.context.invocation.targetIsCurrent?.call() != true) {
        throw const CommandEntryException(CommandEntryFailure.changed);
      }
    }

    check();
    if (review._used) {
      throw const CommandEntryException(CommandEntryFailure.changed);
    }
    review._used = true;
    for (final entry in review._identities.entries) {
      final current = await _inspectAccessible(
        entry.key,
        review.context,
        check,
      );
      if (current != entry.value) {
        throw const CommandEntryException(CommandEntryFailure.changed);
      }
    }
    check();
    // No awaited work may be inserted between the final guard and the runner's
    // synchronous call to Process.start. The immutable argv is already reviewed.
    try {
      return await RunningToolbarCommand.startPrepared(
        review.prepared,
        review.context.invocation,
        timeoutSeconds: review.command.timeoutSeconds,
        processStarter: processStarter,
      );
    } catch (_) {
      throw const CommandEntryException(CommandEntryFailure.launchFailed);
    }
  }
}

/// A finite subset of each interpreter's documented CLI grammar, not a claim
/// to recognize every interpreter, version, wrapper, or executable behavior.
/// Unknown prefix options fail closed. Once the interpreter reaches a script
/// or `--`, later arguments are script data and must not be scanned as flags.
/// See docs/command-entry.md for the supported subset and primary references.
class _InterpreterOptions {
  const _InterpreterOptions({
    this.shortFlags = '',
    this.shortValues = '',
    this.flags = const {},
    this.longValues = const {},
    this.reservedEntryPoints = const {},
  });

  final String shortFlags, shortValues;
  final Set<String> flags, longValues, reservedEntryPoints;

  bool supports(List<String> arguments) {
    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      if (argument == '--') {
        return index + 1 == arguments.length ||
            !reservedEntryPoints.contains(arguments[index + 1]);
      }
      if (argument == '-') return true;
      if (!argument.startsWith('-')) {
        return !reservedEntryPoints.contains(argument);
      }
      if (flags.contains(argument)) continue;
      if (argument.startsWith('--')) {
        final separator = argument.indexOf('=');
        final option = separator < 0
            ? argument
            : argument.substring(0, separator);
        if (!longValues.contains(option)) return false;
        if (separator < 0 && ++index == arguments.length) return false;
        continue;
      }
      for (var offset = 1; offset < argument.length; offset++) {
        final option = argument[offset];
        if (shortFlags.contains(option)) continue;
        if (!shortValues.contains(option)) return false;
        // An attached value consumes the rest of this argument. A separate
        // value consumes exactly one argument, even when it begins with `-`.
        if (offset == argument.length - 1 && ++index == arguments.length) {
          return false;
        }
        break;
      }
    }
    return true;
  }
}

const _pythonOptions = _InterpreterOptions(
  shortFlags: 'bBdEhiIOPqRsSuvVx?',
  shortValues: 'W',
  flags: {'--help', '--help-env', '--help-xoptions', '--help-all', '--version'},
  longValues: {'--check-hash-based-pycs'},
);

const _nodeOptions = _InterpreterOptions(
  flags: {
    '-c',
    '--check',
    '-h',
    '--help',
    '-v',
    '--version',
    '--no-warnings',
    '--trace-warnings',
    '--enable-source-maps',
  },
  // Node's inspector has its own option grammar, including another eval mode.
  // An actual file with this name can be addressed explicitly as ./inspect.
  reservedEntryPoints: {'inspect'},
);

const _interpreterOptions = {
  'node': _nodeOptions,
  'nodejs': _nodeOptions,
  'ruby': _InterpreterOptions(
    shortFlags: 'acdlhnpsvw',
    shortValues: 'CEI',
    flags: {
      '-W',
      '-W0',
      '-W1',
      '-W2',
      '--debug',
      '--verbose',
      '--version',
      '--help',
    },
    longValues: {'--encoding', '--external-encoding', '--internal-encoding'},
  ),
  'perl': _InterpreterOptions(
    shortFlags: 'acfhlnpTtuvVwWX',
    shortValues: 'I',
    flags: {'--help', '--version'},
  ),
  'php': _InterpreterOptions(
    shortFlags: 'eHhilmnsvw?',
    // -f/--file consume a filename but do not end PHP's option parsing. Only a
    // positional filename or `--` makes later option-looking values data.
    shortValues: 'f',
    flags: {
      '--profile-info',
      '--no-php-ini',
      '--help',
      '--usage',
      '--info',
      '--lint',
      '--modules',
      '--version',
      '--syntax-highlight',
      '--syntax-highlighting',
      '--strip',
      '--ini',
    },
    longValues: {'--file'},
  ),
  'lua': _InterpreterOptions(flags: {'-i', '-v', '-E', '-W'}),
};
