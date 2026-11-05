import 'dart:convert';

import 'package:path/path.dart' as p;

import 'storage_reference.dart';

/// An executable and separate argument templates. Old shell strings are kept
/// for migration but cannot run until converted to executable/arguments.
class CustomToolbarCommand {
  const CustomToolbarCommand({
    required this.id,
    required this.label,
    this.iconName = 'terminal',
    this.command = '',
    this.executable = '',
    this.arguments = const [],
    this.workingDir,
    this.useCurrentPanelPath = true,
    this.timeoutSeconds = 300,
  });
  final String id, label, iconName, command, executable;
  final List<String> arguments;
  final String? workingDir;
  final bool useCurrentPanelPath;
  final int timeoutSeconds;
  bool get requiresReview => executable.trim().isEmpty;

  Map<String, dynamic> toJson() => {
    'version': 2,
    'id': id,
    'label': label,
    'iconName': iconName,
    'command': command,
    'executable': executable,
    'arguments': arguments,
    'workingDir': workingDir,
    'useCurrentPanelPath': useCurrentPanelPath,
    'timeoutSeconds': timeoutSeconds,
  };

  factory CustomToolbarCommand.fromJson(Map<String, dynamic> json) {
    if (json['version'] != null && ![1, 2].contains(json['version'])) {
      throw const FormatException('Unsupported command version.');
    }
    final result = CustomToolbarCommand(
      id: json['id'] as String,
      label: json['label'] as String,
      iconName: json['iconName'] as String? ?? 'terminal',
      command: json['command'] as String? ?? '',
      executable: json['executable'] as String? ?? '',
      arguments: List<String>.unmodifiable(
        (json['arguments'] as List? ?? const []).cast<String>(),
      ),
      workingDir: json['workingDir'] as String?,
      useCurrentPanelPath: json['useCurrentPanelPath'] as bool? ?? true,
      timeoutSeconds: json['timeoutSeconds'] as int? ?? 300,
    );
    result.validate(allowLegacy: true);
    return result;
  }

  void validate({bool allowLegacy = false}) {
    if (id.isEmpty ||
        id.length > 128 ||
        label.trim().isEmpty ||
        label.length > 256 ||
        timeoutSeconds < 1 ||
        timeoutSeconds > 86400 ||
        jsonEncode(toJson()).length > 64 * 1024) {
      throw const FormatException(
        'Invalid command identity, label, size or timeout.',
      );
    }
    if (requiresReview) {
      if (allowLegacy && command.isNotEmpty) return;
      throw const FormatException(
        'Review this legacy shell command and set an executable with separate arguments.',
      );
    }
    if (executable.contains(RegExp(r'[\x00\r\n{}]')) ||
        executable.length > 4096 ||
        arguments.length > 1024 ||
        arguments.any((a) => a.contains('\u0000'))) {
      throw const FormatException('Invalid or oversized command definition.');
    }
    for (final argument in arguments) {
      if (argument.contains('{SELECTED}') && argument != '{SELECTED}') {
        throw const FormatException('{SELECTED} must occupy a whole argument.');
      }
      for (final token in RegExp(r'\{[A-Z_]+\}').allMatches(argument)) {
        if (!const {
          '{SELECTED}',
          '{CURRENT}',
          '{TARGET}',
          '{FILE}',
          '{NAME}',
          '{BASENAME}',
          '{EXT}',
        }.contains(token.group(0))) {
          throw FormatException(
            'Unknown argument placeholder: ${token.group(0)}',
          );
        }
      }
    }
    _validateInlineCode();
  }

  void _validateInlineCode() {
    final program = p.posix
        .basename(executable.replaceAll('\\', '/'))
        .toLowerCase();
    final shell = const {
      'sh',
      'bash',
      'zsh',
      'dash',
      'ksh',
      'fish',
    }.contains(program);
    final commandShell = const {
      'cmd',
      'cmd.exe',
      'powershell',
      'powershell.exe',
      'pwsh',
      'pwsh.exe',
    }.contains(program);
    final interpreter = RegExp(
      r'^(?:python(?:\d+(?:\.\d+)*)?|node|nodejs|ruby|perl|php|lua)(?:\.exe)?$',
    ).hasMatch(program);
    if (!shell && !commandShell && !interpreter) return;
    final placeholder = RegExp(r'\{[A-Z_]+\}');
    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index].toLowerCase();
      final codeFlag = commandShell
          ? const {
              '/c',
              '/k',
              '-command',
              '-c',
              '-encodedcommand',
              '-enc',
              '-commandwithargs',
            }.contains(argument)
          : shell
          ? (RegExp(r'^-[a-z]*c[a-z]*$').hasMatch(argument) ||
                argument == '--command')
          : const {'-c', '-e', '--eval', '-r'}.contains(argument);
      if ((argument.startsWith('--eval=') ||
              argument.startsWith('--command=')) &&
          placeholder.hasMatch(arguments[index])) {
        throw const FormatException(
          'Pass file placeholders as data arguments, not inline program code.',
        );
      }
      if (!codeFlag) continue;
      final last = commandShell
          ? arguments.length
          : (index + 2).clamp(0, arguments.length);
      for (var codeIndex = index + 1; codeIndex < last; codeIndex++) {
        if (placeholder.hasMatch(arguments[codeIndex])) {
          throw const FormatException(
            'Pass file placeholders as data arguments, not inline program code.',
          );
        }
      }
    }
  }
}

/// Captured from verified panel rows, never inferred from the panel label.
class CommandInvocationContext {
  CommandInvocationContext({
    required this.storage,
    required this.currentPath,
    required List<String> selectedPaths,
    required this.isCurrent,
    this.targetPath,
    this.targetIsCurrent,
  }) : selectedPaths = List.unmodifiable(selectedPaths);
  final StorageReference storage;
  final String currentPath;
  final List<String> selectedPaths;
  final bool Function() isCurrent;
  final String? targetPath;
  final bool Function()? targetIsCurrent;
  void validate() {
    if (!storage.isLocal || !isCurrent()) {
      throw StateError('Commands require a current, verified local source.');
    }
    if (!p.isAbsolute(currentPath) ||
        currentPath.contains('\u0000') ||
        selectedPaths.any(
          (path) => !p.isAbsolute(path) || path.contains('\u0000'),
        )) {
      throw StateError('Commands require absolute local paths.');
    }
  }
}

class PreparedToolbarCommand {
  PreparedToolbarCommand(
    this.executable,
    List<String> arguments,
    this.workingDirectory,
  ) : arguments = List.unmodifiable(arguments);
  final String executable;
  final List<String> arguments;
  final String workingDirectory;
}

PreparedToolbarCommand prepareToolbarCommand(
  CustomToolbarCommand command,
  CommandInvocationContext context,
) {
  command.validate();
  context.validate();
  final selected = context.selectedPaths;
  String expand(
    String argument,
  ) => argument.replaceAllMapped(RegExp(r'\{[A-Z_]+\}'), (match) {
    final token = match.group(0)!;
    if (token == '{CURRENT}') return context.currentPath;
    if (token == '{TARGET}') {
      if (context.targetPath == null ||
          context.targetIsCurrent?.call() != true ||
          !p.isAbsolute(context.targetPath!) ||
          context.targetPath!.contains('\u0000')) {
        throw StateError('The other panel must have a current local folder.');
      }
      return context.targetPath!;
    }
    if (selected.length != 1) {
      throw StateError('$token requires exactly one selected item.');
    }
    return switch (token) {
      '{FILE}' => selected.single,
      '{NAME}' => p.basename(selected.single),
      '{BASENAME}' => p.basenameWithoutExtension(selected.single),
      '{EXT}' => p.extension(selected.single).replaceFirst(RegExp(r'^\.'), ''),
      _ => throw FormatException('Unknown argument placeholder: $token'),
    };
  });
  final args = <String>[];
  for (final argument in command.arguments) {
    if (argument == '{SELECTED}') {
      if (selected.isEmpty) throw StateError('Select at least one local item.');
      args.addAll(selected);
    } else {
      args.add(expand(argument));
    }
  }
  final directory = command.useCurrentPanelPath
      ? context.currentPath
      : (command.workingDir ?? '');
  if (!p.isAbsolute(directory) || directory.contains('\u0000')) {
    throw StateError('Choose an absolute working directory.');
  }
  if (args.length > 10000 ||
      args.fold<int>(0, (n, a) => n + utf8.encode(a).length + 1) >
          1024 * 1024) {
    throw StateError('This selection is too large for command arguments.');
  }
  return PreparedToolbarCommand(command.executable.trim(), args, directory);
}
