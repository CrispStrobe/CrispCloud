import 'dart:convert';

import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import 'search_replace.dart';

/// Changes are applied after masks and search/replace, independently for the
/// name and extension. Directories always use the name settings only.
enum RenameCase { unchanged, lower, upper, title, sentence }

enum RenameReplaceScope { fullName, name, extension }

class MultiRenameOptions {
  const MultiRenameOptions({
    this.nameMask = '[N]',
    this.extensionMask = '[E]',
    this.find = '',
    this.replace = '',
    this.useRegex = false,
    this.caseSensitive = true,
    this.firstMatchOnly = false,
    this.replaceScope = RenameReplaceScope.fullName,
    this.nameCase = RenameCase.unchanged,
    this.extensionCase = RenameCase.unchanged,
    this.counterStart = 1,
    this.counterStep = 1,
    this.counterWidth = 3,
  });

  final String nameMask;
  final String extensionMask;
  final String find;
  final String replace;
  final bool useRegex;
  final bool caseSensitive;
  final bool firstMatchOnly;
  final RenameReplaceScope replaceScope;
  final RenameCase nameCase;
  final RenameCase extensionCase;
  final int counterStart;
  final int counterStep;
  final int counterWidth;

  Map<String, Object> toJson() => {
    'nameMask': nameMask,
    'extensionMask': extensionMask,
    'find': find,
    'replace': replace,
    'useRegex': useRegex,
    'caseSensitive': caseSensitive,
    'firstMatchOnly': firstMatchOnly,
    'replaceScope': replaceScope.name,
    'nameCase': nameCase.name,
    'extensionCase': extensionCase.name,
    'counterStart': counterStart,
    'counterStep': counterStep,
    'counterWidth': counterWidth,
  };

  factory MultiRenameOptions.fromJson(Map<String, dynamic> value) {
    T choice<T extends Enum>(List<T> choices, String key, T fallback) {
      for (final item in choices) {
        if (item.name == value[key]) return item;
      }
      return fallback;
    }

    String text(String key, String fallback) =>
        value[key] is String ? value[key] as String : fallback;
    bool flag(String key, bool fallback) =>
        value[key] is bool ? value[key] as bool : fallback;
    int number(String key, int fallback) =>
        value[key] is int ? value[key] as int : fallback;

    return MultiRenameOptions(
      nameMask: text('nameMask', '[N]'),
      extensionMask: text('extensionMask', '[E]'),
      find: text('find', ''),
      replace: text('replace', ''),
      useRegex: flag('useRegex', false),
      caseSensitive: flag('caseSensitive', true),
      firstMatchOnly: flag('firstMatchOnly', false),
      replaceScope: choice(
        RenameReplaceScope.values,
        'replaceScope',
        RenameReplaceScope.fullName,
      ),
      nameCase: choice(RenameCase.values, 'nameCase', RenameCase.unchanged),
      extensionCase: choice(
        RenameCase.values,
        'extensionCase',
        RenameCase.unchanged,
      ),
      counterStart: number('counterStart', 1),
      counterStep: number('counterStep', 1),
      counterWidth: number('counterWidth', 3),
    );
  }
}

class MultiRenameEntry {
  MultiRenameEntry._({
    required this.file,
    required this.sourcePath,
    required this.targetPath,
    required this.newName,
    List<String> errors = const [],
  }) : errors = List.unmodifiable(errors);

  final FileItem file;
  final String sourcePath;
  final String targetPath;
  final String newName;
  final List<String> errors;

  bool get changed => file.name != newName;
  bool get isValid => errors.isEmpty;

  FileItem get renamedFile => file.copyWith(name: newName, path: targetPath);
}

class MultiRenamePlan {
  MultiRenamePlan._(List<MultiRenameEntry> entries, List<String> errors)
    : entries = List.unmodifiable(entries),
      errors = List.unmodifiable(errors);

  final List<MultiRenameEntry> entries;
  final List<String> errors;

  int get changeCount => entries.where((entry) => entry.changed).length;
  bool get isValid => errors.isEmpty && entries.every((entry) => entry.isValid);
  bool get canExecute => isValid && changeCount > 0;
}

enum MultiRenameStatus { unchanged, renamed, failed, notRun }

class MultiRenameOutcome {
  const MultiRenameOutcome(this.entry, this.status, {this.message});

  final MultiRenameEntry entry;
  final MultiRenameStatus status;
  final String? message;
}

class MultiRenameResult {
  MultiRenameResult(List<MultiRenameOutcome> outcomes, {this.cancelled = false})
    : outcomes = List.unmodifiable(outcomes);

  final List<MultiRenameOutcome> outcomes;
  final bool cancelled;

  int get renamed =>
      outcomes.where((item) => item.status == MultiRenameStatus.renamed).length;
  int get failed =>
      outcomes.where((item) => item.status == MultiRenameStatus.failed).length;
  int get unchanged => outcomes
      .where((item) => item.status == MultiRenameStatus.unchanged)
      .length;
  int get notRun =>
      outcomes.where((item) => item.status == MultiRenameStatus.notRun).length;

  Map<String, FileItem> get changes => {
    for (final outcome in outcomes)
      if (outcome.status == MultiRenameStatus.renamed)
        outcome.entry.sourcePath: outcome.entry.renamedFile,
  };
}

class MultiRenamePreflightException implements Exception {
  MultiRenamePreflightException(Map<String, String> problems)
    : problems = Map.unmodifiable(problems);

  /// Keys are the original full paths, so duplicate basenames stay distinct.
  final Map<String, String> problems;

  @override
  String toString() => problems.values.join('\n');
}

enum MultiRenamePhase { checking, renaming }

class MultiRenameProgress {
  const MultiRenameProgress(this.phase, this.completed, this.total, this.path);

  final MultiRenamePhase phase;
  final int completed;
  final int total;
  final String path;
}

/// Commander-style multi-rename planning, independent of a provider or widget.
///
/// Masks support [N], [E], [C], [C:4], [P], [N1-4], [N3-], [N-4--1],
/// [Y], [M], [D], [h], [m], and [s]. Positions are one-based Unicode code
/// points; negative positions count from the end. Date tokens use the item's
/// modified time, never the current clock. Escape brackets with [[ and ]].
///
/// Planning is conservative about case collisions because a remote provider's
/// case rules may differ from the host's. Existing destinations, rename cycles,
/// and parent/child batches are blocked instead of replacing any file. The
/// execution callback must also refuse overwrites; remote APIs cannot generally
/// offer a transaction spanning an entire batch.
class MultiRenameService {
  const MultiRenameService();

  MultiRenamePlan preview(
    List<FileItem> files,
    MultiRenameOptions options, {
    required String directory,
    p.Context? pathContext,
  }) {
    final paths = pathContext ?? p.posix;
    final errors = <String>[];
    if (options.counterStart < 0 || options.counterStart > 999999999999) {
      errors.add('Counter start must be between 0 and 999999999999.');
    }
    if (options.counterStep.abs() > 999999999999) {
      errors.add('Counter step is too large.');
    }
    if (options.counterWidth < 1 || options.counterWidth > 12) {
      errors.add('Counter width must be between 1 and 12.');
    }
    RegExp? pattern;
    if (options.find.isNotEmpty) {
      try {
        pattern = RegExp(
          options.useRegex ? options.find : RegExp.escape(options.find),
          caseSensitive: options.caseSensitive,
          unicode: true,
        );
      } on FormatException catch (error) {
        errors.add('Invalid regular expression: ${error.message}');
      }
    }

    final rows = <MultiRenameEntry>[];
    final rowErrors = <List<String>>[];
    for (var index = 0; index < files.length; index++) {
      final file = files[index];
      final problems = <String>[];
      final source = paths.normalize(
        file.path ?? paths.join(directory, file.name),
      );
      if (!paths.isAbsolute(source)) {
        problems.add(
          'The original path must be absolute. Refresh the listing.',
        );
      } else if (paths.basename(source) != file.name) {
        problems.add(
          'The name does not match its original path. Refresh the listing.',
        );
      }
      var newName = file.name;
      if (errors.isEmpty) {
        try {
          newName = _transform(file, index, options, pattern, source, paths);
          if (newName != file.name) {
            final invalid = validateName(newName);
            if (invalid != null) problems.add(invalid);
          }
        } on FormatException catch (error) {
          problems.add(error.message);
        }
      }
      rows.add(
        MultiRenameEntry._(
          file: file,
          sourcePath: source,
          targetPath: paths.join(paths.dirname(source), newName),
          newName: newName,
        ),
      );
      rowErrors.add(problems);
    }

    String key(String path) => paths.normalize(path).toLowerCase();
    final sources = <String, List<int>>{};
    final targets = <String, List<int>>{};
    for (var index = 0; index < rows.length; index++) {
      sources.putIfAbsent(key(rows[index].sourcePath), () => []).add(index);
      targets.putIfAbsent(key(rows[index].targetPath), () => []).add(index);
    }
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      if (sources[key(row.sourcePath)]!.length > 1) {
        rowErrors[index].add(
          'The selection contains duplicate or case-ambiguous paths.',
        );
      }
      if (targets[key(row.targetPath)]!.length > 1 && row.changed) {
        rowErrors[index].add(
          'More than one item would have this name in the same folder.',
        );
      }
      if (row.changed &&
          (sources[key(row.targetPath)] ?? []).any((other) => other != index)) {
        rowErrors[index].add(
          'This name belongs to another selected item. Use an intermediate name first.',
        );
      }
      if (row.changed && row.file.isFolder) {
        for (var other = 0; other < rows.length; other++) {
          if (other == index) continue;
          if (paths.isWithin(
            key(row.sourcePath),
            key(rows[other].sourcePath),
          )) {
            const problem =
                'Rename a folder and items inside it in separate batches.';
            if (!rowErrors[index].contains(problem)) {
              rowErrors[index].add(problem);
            }
            rowErrors[other].add(problem);
          }
        }
      }
    }
    return MultiRenamePlan._([
      for (var index = 0; index < rows.length; index++)
        MultiRenameEntry._(
          file: rows[index].file,
          sourcePath: rows[index].sourcePath,
          targetPath: rows[index].targetPath,
          newName: rows[index].newName,
          errors: rowErrors[index],
        ),
    ], errors);
  }

  /// Return a portable-name validation error, or null. Checking names before
  /// I/O avoids partial batches caused by platform/provider-specific failures.
  static String? validateName(String name) {
    if (name.trim().isEmpty || name == '.' || name == '..') {
      return 'The new name must not be empty, ".", or "..".';
    }
    if (RegExp(r'[\x00-\x1f\x7f/\\<>:"|?*]').hasMatch(name)) {
      return 'Names cannot contain path separators, control characters, or <>:"|?*.';
    }
    if (name.endsWith(' ') || name.endsWith('.')) {
      return 'Names cannot end with a space or dot.';
    }
    if (RegExp(
      r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)',
      caseSensitive: false,
    ).hasMatch(name)) {
      return 'This is a reserved device name.';
    }
    if (utf8.encode(name).length > 255) {
      return 'The new name exceeds 255 UTF-8 bytes.';
    }
    return null;
  }

  /// Check the entire plan before the first write, and re-check each item just
  /// before renaming. Exceptions from [exists] must propagate: lack of access
  /// must never be interpreted as a vacant destination.
  ///
  /// [rename] must throw on failure and remain bound to the captured storage
  /// account; returning normally means that the specific rename succeeded.
  /// Cancellation is cooperative between I/O operations. Completed renames are
  /// retained and returned, with unattempted items reported separately.
  Future<MultiRenameResult> execute(
    MultiRenamePlan plan, {
    required Future<bool> Function(String path) exists,
    required Future<void> Function(FileItem file, String newName) rename,
    bool Function()? isCancelled,
    bool continueOnError = false,
    void Function(MultiRenameProgress progress)? onProgress,
  }) async {
    if (!plan.isValid) {
      throw MultiRenamePreflightException({
        if (plan.errors.isNotEmpty) '': plan.errors.join('\n'),
        for (final entry in plan.entries)
          if (!entry.isValid) entry.sourcePath: entry.errors.join('\n'),
      });
    }
    final outcomes = [
      for (final entry in plan.entries)
        MultiRenameOutcome(
          entry,
          entry.changed
              ? MultiRenameStatus.notRun
              : MultiRenameStatus.unchanged,
        ),
    ];
    MultiRenameResult cancelled() =>
        MultiRenameResult(outcomes, cancelled: true);
    final changes = plan.entries.where((entry) => entry.changed).toList();
    final problems = <String, String>{};
    for (var index = 0; index < changes.length; index++) {
      if (isCancelled?.call() ?? false) return cancelled();
      final entry = changes[index];
      onProgress?.call(
        MultiRenameProgress(
          MultiRenamePhase.checking,
          index,
          changes.length,
          entry.sourcePath,
        ),
      );
      try {
        if (!await exists(entry.sourcePath)) {
          problems[entry.sourcePath] = 'Original item no longer exists.';
        } else if (await exists(entry.targetPath)) {
          problems[entry.sourcePath] = _occupiedMessage(entry);
        }
      } catch (error) {
        problems[entry.sourcePath] = 'Could not verify the paths: $error';
      }
    }
    if (isCancelled?.call() ?? false) return cancelled();
    if (problems.isNotEmpty) throw MultiRenamePreflightException(problems);

    var completed = 0;
    for (var index = 0; index < plan.entries.length; index++) {
      final entry = plan.entries[index];
      if (!entry.changed) continue;
      if (isCancelled?.call() ?? false) return cancelled();
      onProgress?.call(
        MultiRenameProgress(
          MultiRenamePhase.renaming,
          completed,
          changes.length,
          entry.sourcePath,
        ),
      );
      try {
        if (!await exists(entry.sourcePath)) {
          throw StateError('Original item no longer exists.');
        }
        if (await exists(entry.targetPath)) {
          throw StateError(_occupiedMessage(entry));
        }
        if (isCancelled?.call() ?? false) return cancelled();
        await rename(
          entry.file.copyWith(path: entry.sourcePath),
          entry.newName,
        );
        outcomes[index] = MultiRenameOutcome(entry, MultiRenameStatus.renamed);
      } catch (error) {
        outcomes[index] = MultiRenameOutcome(
          entry,
          MultiRenameStatus.failed,
          message: error.toString(),
        );
        if (!continueOnError) break;
      }
      completed++;
      onProgress?.call(
        MultiRenameProgress(
          MultiRenamePhase.renaming,
          completed,
          changes.length,
          entry.sourcePath,
        ),
      );
    }
    return MultiRenameResult(outcomes, cancelled: isCancelled?.call() ?? false);
  }

  static String _occupiedMessage(MultiRenameEntry entry) {
    if (entry.sourcePath.toLowerCase() == entry.targetPath.toLowerCase()) {
      return 'The destination already exists. For a case-only rename on this '
          'filesystem, rename to an intermediate name first.';
    }
    return 'The destination already exists; it will not be replaced.';
  }

  String _transform(
    FileItem file,
    int index,
    MultiRenameOptions options,
    RegExp? pattern,
    String source,
    p.Context paths,
  ) {
    final original = _parts(file.name, file.isFolder);
    final counter = options.counterStart + index * options.counterStep;
    String mask(String value) => _mask(
      value,
      original.$1,
      original.$2,
      counter,
      options.counterWidth,
      file.updatedAt,
      paths.basename(paths.dirname(source)),
    );
    var name = mask(options.nameMask);
    var extension = file.isFolder ? '' : mask(options.extensionMask);

    String replace(String value) {
      if (pattern == null) return value;
      String replacement(Match match) => options.useRegex
          ? expandReplacementTemplate(options.replace, match)
          : options.replace;
      if (options.firstMatchOnly) {
        return value.replaceFirstMapped(pattern, replacement);
      }
      return value.replaceAllMapped(pattern, replacement);
    }

    switch (options.replaceScope) {
      case RenameReplaceScope.name:
        name = replace(name);
      case RenameReplaceScope.extension:
        if (!file.isFolder) extension = replace(extension);
      case RenameReplaceScope.fullName:
        if (pattern != null) {
          final replaced = replace(_join(name, extension));
          final parts = _parts(replaced, file.isFolder);
          name = parts.$1;
          extension = parts.$2;
        }
    }
    return _join(
      _case(name, options.nameCase),
      _case(extension, options.extensionCase),
    );
  }

  static (String, String) _parts(String name, bool isFolder) {
    final dot = isFolder ? -1 : name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return (name, '');
    return (name.substring(0, dot), name.substring(dot + 1));
  }

  static String _join(String name, String extension) =>
      extension.isEmpty ? name : '$name.$extension';

  static String _case(String value, RenameCase mode) {
    switch (mode) {
      case RenameCase.unchanged:
        return value;
      case RenameCase.lower:
        return value.toLowerCase();
      case RenameCase.upper:
        return value.toUpperCase();
      case RenameCase.title:
        return value.toLowerCase().replaceAllMapped(
          RegExp(r'(^|[\s_\-])(\S)', unicode: true),
          (match) => '${match[1]}${match[2]!.toUpperCase()}',
        );
      case RenameCase.sentence:
        if (value.isEmpty) return value;
        final points = value.toLowerCase().runes.toList();
        return String.fromCharCode(points.first).toUpperCase() +
            String.fromCharCodes(points.skip(1));
    }
  }

  String _mask(
    String mask,
    String name,
    String extension,
    int counter,
    int width,
    DateTime? modified,
    String parent,
  ) {
    final result = StringBuffer();
    var position = 0;
    while (position < mask.length) {
      if (mask.startsWith('[[', position)) {
        result.write('[');
        position += 2;
      } else if (mask.startsWith(']]', position)) {
        result.write(']');
        position += 2;
      } else if (mask[position] == '[') {
        final end = mask.indexOf(']', position + 1);
        if (end < 0) {
          throw const FormatException('A mask token is missing its closing ].');
        }
        final token = mask.substring(position + 1, end);
        result.write(
          _token(token, name, extension, counter, width, modified, parent),
        );
        position = end + 1;
      } else {
        result.write(mask[position]);
        position++;
      }
    }
    return result.toString();
  }

  String _token(
    String token,
    String name,
    String extension,
    int counter,
    int width,
    DateTime? modified,
    String parent,
  ) {
    if (token == 'N') return name;
    if (token == 'E') return extension;
    if (token == 'P') return parent;
    final count = RegExp(r'^C(?::([0-9]+))?$').firstMatch(token);
    if (count != null) {
      final digits = count[1] == null ? width : int.tryParse(count[1]!) ?? 0;
      if (digits < 1 || digits > 12) {
        throw const FormatException('Counter width must be between 1 and 12.');
      }
      if (counter < 0 || counter > 999999999999) {
        throw const FormatException(
          'A counter value is outside 0–999999999999.',
        );
      }
      return counter.toString().padLeft(digits, '0');
    }
    if (const {'Y', 'M', 'D', 'h', 'm', 's'}.contains(token)) {
      if (modified == null) {
        throw const FormatException(
          'This item has no modified time for the date mask.',
        );
      }
      final value = switch (token) {
        'Y' => modified.year,
        'M' => modified.month,
        'D' => modified.day,
        'h' => modified.hour,
        'm' => modified.minute,
        _ => modified.second,
      };
      return value.toString().padLeft(token == 'Y' ? 4 : 2, '0');
    }
    final slice = RegExp(r'^([NE])(-?[1-9][0-9]*)(?:-(-?[1-9][0-9]*)?)?$')
        .firstMatch(token);
    if (slice != null) {
      final points = (slice[1] == 'N' ? name : extension).runes.toList();
      final startPosition = int.tryParse(slice[2]!);
      if (startPosition == null) {
        throw const FormatException('The mask position is too large.');
      }
      int offset(int n) => n < 0 ? points.length + n : n - 1;
      final start = offset(startPosition).clamp(0, points.length);
      final hasRange = token.substring(1 + slice[2]!.length).startsWith('-');
      final int end;
      if (!hasRange) {
        // An out-of-range single position produces no characters.
        if (offset(startPosition) < 0 ||
            offset(startPosition) >= points.length) {
          return '';
        }
        end = start + 1;
      } else if (slice[3] == null) {
        end = points.length;
      } else {
        final endPosition = int.tryParse(slice[3]!);
        if (endPosition == null) {
          throw const FormatException('The mask position is too large.');
        }
        end = (offset(endPosition) + 1).clamp(0, points.length);
      }
      return end < start
          ? ''
          : String.fromCharCodes(points.sublist(start, end));
    }
    throw FormatException('Unknown mask token [$token].');
  }
}
