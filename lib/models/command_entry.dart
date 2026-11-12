import 'dart:convert';

import 'package:flutter/services.dart';

import 'custom_toolbar_command.dart';

enum CommandEntryFailure {
  unsupported,
  localRequired,
  changed,
  accessUnavailable,
  selectionUnavailable,
  selectionLimit,
  invalidArguments,
  invalidProgram,
  executableUnavailable,
  unsupportedProgram,
  savedUnavailable,
  launchFailed,
}

class CommandEntryException implements Exception {
  const CommandEntryException(this.failure);
  final CommandEntryFailure failure;
  @override
  String toString() => 'Command entry: ${failure.name}';
}

/// A snapshot of a verified local row, taken before any asynchronous lookup.
class CommandEntrySelection {
  const CommandEntrySelection({
    required this.path,
    required this.name,
    required this.isDirectory,
    this.size,
    this.modified,
  });
  final String path, name;
  final bool isDirectory;
  final int? size;
  final DateTime? modified;
}

class CommandEntryContext {
  CommandEntryContext({
    required this.invocation,
    required List<CommandEntrySelection> selection,
    required this.hasExistingAccess,
    this.onDispose,
  }) : selection = List.unmodifiable(selection);
  final CommandInvocationContext invocation;
  final List<CommandEntrySelection> selection;
  final Future<bool> Function(String path) hasExistingAccess;
  final void Function()? onDispose;
  bool _disposed = false;
  bool get isDisposed => _disposed;
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    onDispose?.call();
  }
}

/// The executable field is a path/name; only [arguments] has token syntax.
/// Saved command templates are expanded once, then these literal arguments are
/// appended. Nothing from this transient draft is saved or run on opening.
class CommandEntryDraft {
  CommandEntryDraft({
    required this.program,
    required this.arguments,
    CustomToolbarCommand? savedCommand,
  }) : savedCommand = savedCommand == null
           ? null
           : CustomToolbarCommand.fromJson(savedCommand.toJson());
  final String program, arguments;
  final CustomToolbarCommand? savedCommand;
}

bool _space(int value) =>
    value == 32 || value == 9 || value == 10 || value == 13;

/// Deliberately small, platform-independent argument syntax: whitespace
/// separates arguments; a JSON double-quoted string is one argument. Unquoted
/// backslashes, single quotes and shell punctuation remain ordinary data.
/// There are no substitutions, concatenated quoted fragments or shell escapes.
List<String> parseCommandEntryArguments(String input) {
  if (input.length > 64 * 1024 || input.contains('\u0000')) {
    throw const CommandEntryException(CommandEntryFailure.invalidArguments);
  }
  final result = <String>[];
  var index = 0;
  while (index < input.length) {
    while (index < input.length && _space(input.codeUnitAt(index))) {
      index++;
    }
    if (index == input.length) break;
    final start = index;
    String argument;
    if (input.codeUnitAt(index) == 34) {
      var escaped = false;
      var closed = false;
      index++;
      while (index < input.length) {
        final char = input.codeUnitAt(index++);
        if (escaped) {
          escaped = false;
        } else if (char == 92) {
          escaped = true;
        } else if (char == 34) {
          closed = true;
          break;
        }
      }
      if (!closed ||
          (index < input.length && !_space(input.codeUnitAt(index)))) {
        throw const CommandEntryException(CommandEntryFailure.invalidArguments);
      }
      try {
        argument = jsonDecode(input.substring(start, index)) as String;
      } catch (_) {
        throw const CommandEntryException(CommandEntryFailure.invalidArguments);
      }
    } else {
      while (index < input.length && !_space(input.codeUnitAt(index))) {
        if (input.codeUnitAt(index) < 32 || input.codeUnitAt(index) == 34) {
          throw const CommandEntryException(
            CommandEntryFailure.invalidArguments,
          );
        }
        index++;
      }
      argument = input.substring(start, index);
    }
    if (argument.contains('\u0000') || result.length == 1024) {
      throw const CommandEntryException(CommandEntryFailure.invalidArguments);
    }
    result.add(argument);
  }
  return List.unmodifiable(result);
}

String encodeCommandEntryArgument(String argument) {
  if (argument.contains('\u0000')) {
    throw const CommandEntryException(CommandEntryFailure.invalidArguments);
  }
  return jsonEncode(argument);
}

/// Insert whole literal arguments at the caret. A selection or caret inside an
/// existing token replaces that whole token, avoiding broken quoting and
/// accidental concatenation. Invalid/incomplete tokens can be replaced too.
TextEditingValue insertCommandEntryArguments(
  TextEditingValue value,
  Iterable<String> arguments,
) {
  final encoded = arguments.map(encodeCommandEntryArgument).join(' ');
  if (encoded.isEmpty) return value;
  final text = value.text;
  var start = value.selection.isValid
      ? value.selection.start.clamp(0, text.length)
      : text.length;
  var end = value.selection.isValid
      ? value.selection.end.clamp(0, text.length)
      : text.length;
  final collapsed = start == end;
  var index = 0;
  while (index < text.length) {
    if (_space(text.codeUnitAt(index))) {
      index++;
      continue;
    }
    final tokenStart = index;
    var quoted = false, escaped = false;
    while (index < text.length) {
      final char = text.codeUnitAt(index);
      if (!quoted && _space(char)) break;
      if (escaped) {
        escaped = false;
      } else if (quoted && char == 92) {
        escaped = true;
      } else if (char == 34) {
        quoted = !quoted;
      }
      index++;
    }
    final intersects = collapsed
        ? start > tokenStart && start < index
        : tokenStart < end && index > start;
    if (intersects) {
      if (tokenStart < start) start = tokenStart;
      if (index > end) end = index;
    }
  }
  final prefix = start > 0 && !_space(text.codeUnitAt(start - 1)) ? ' ' : '';
  final suffix = end < text.length && !_space(text.codeUnitAt(end)) ? ' ' : '';
  final replacement = '$prefix$encoded$suffix';
  final next = text.replaceRange(start, end, replacement);
  // Bound the entire field, including pre-existing and inserted arguments.
  parseCommandEntryArguments(next);
  return TextEditingValue(
    text: next,
    selection: TextSelection.collapsed(offset: start + replacement.length),
  );
}
