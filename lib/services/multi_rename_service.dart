import 'dart:convert';

import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import 'rename_mask.dart';
import 'search_replace.dart';

export 'rename_mask.dart'
    show RenameMaskDialect, RenameDateSource, RenameDateZone;

/// Changes are applied after masks and search/replace, independently for the
/// name and extension. Directories always use the name settings only.
enum RenameCase { unchanged, lower, upper, title, sentence }

enum RenameReplaceScope { fullName, name, extension }

enum RenameCollisionPolicy { error, number }

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
    this.dialect = RenameMaskDialect.crispCloud,
    this.dateSource = RenameDateSource.modified,
    this.dateZone = RenameDateZone.original,
    this.dateOffsetMinutes = 0,
    this.variables = const {},
    this.multipleLiteralPairs = false,
    this.additionalSteps = const [],
    this.collisionPolicy = RenameCollisionPolicy.error,
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
  final RenameMaskDialect dialect;
  final RenameDateSource dateSource;
  final RenameDateZone dateZone;
  final int dateOffsetMinutes;
  final Map<String, String> variables;
  final bool multipleLiteralPairs;
  final List<MultiRenameOptions> additionalSteps;
  final RenameCollisionPolicy collisionPolicy;

  Map<String, Object> toJson() => {
    'version': 2,
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
    'dialect': dialect.name,
    'dateSource': dateSource.name,
    'dateZone': dateZone.name,
    'dateOffsetMinutes': dateOffsetMinutes,
    'variables': variables,
    'multipleLiteralPairs': multipleLiteralPairs,
    'additionalSteps': additionalSteps.map((step) => step.toJson()).toList(),
    'collisionPolicy': collisionPolicy.name,
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
      dialect: choice(
        RenameMaskDialect.values,
        'dialect',
        RenameMaskDialect.crispCloud,
      ),
      dateSource: choice(
        RenameDateSource.values,
        'dateSource',
        RenameDateSource.modified,
      ),
      dateZone: choice(
        RenameDateZone.values,
        'dateZone',
        RenameDateZone.original,
      ),
      dateOffsetMinutes: number('dateOffsetMinutes', 0),
      variables: value['variables'] is Map
          ? {
              for (final entry in (value['variables'] as Map).entries)
                entry.key.toString(): entry.value.toString(),
            }
          : const {},
      multipleLiteralPairs: flag('multipleLiteralPairs', false),
      additionalSteps: value['additionalSteps'] is List
          ? (value['additionalSteps'] as List)
                .whereType<Map>()
                .map(
                  (step) => MultiRenameOptions.fromJson(
                    Map<String, dynamic>.from(step),
                  ),
                )
                .toList()
          : const [],
      collisionPolicy: choice(
        RenameCollisionPolicy.values,
        'collisionPolicy',
        RenameCollisionPolicy.error,
      ),
    );
  }

  MultiRenameOptions copyWith({
    String? nameMask,
    String? extensionMask,
    String? find,
    String? replace,
    bool? useRegex,
    bool? caseSensitive,
    bool? firstMatchOnly,
    RenameReplaceScope? replaceScope,
    RenameCase? nameCase,
    RenameCase? extensionCase,
    int? counterStart,
    int? counterStep,
    int? counterWidth,
    RenameMaskDialect? dialect,
    RenameDateSource? dateSource,
    RenameDateZone? dateZone,
    int? dateOffsetMinutes,
    Map<String, String>? variables,
    bool? multipleLiteralPairs,
    List<MultiRenameOptions>? additionalSteps,
    RenameCollisionPolicy? collisionPolicy,
  }) => MultiRenameOptions(
    nameMask: nameMask ?? this.nameMask,
    extensionMask: extensionMask ?? this.extensionMask,
    find: find ?? this.find,
    replace: replace ?? this.replace,
    useRegex: useRegex ?? this.useRegex,
    caseSensitive: caseSensitive ?? this.caseSensitive,
    firstMatchOnly: firstMatchOnly ?? this.firstMatchOnly,
    replaceScope: replaceScope ?? this.replaceScope,
    nameCase: nameCase ?? this.nameCase,
    extensionCase: extensionCase ?? this.extensionCase,
    counterStart: counterStart ?? this.counterStart,
    counterStep: counterStep ?? this.counterStep,
    counterWidth: counterWidth ?? this.counterWidth,
    dialect: dialect ?? this.dialect,
    dateSource: dateSource ?? this.dateSource,
    dateZone: dateZone ?? this.dateZone,
    dateOffsetMinutes: dateOffsetMinutes ?? this.dateOffsetMinutes,
    variables: variables ?? this.variables,
    multipleLiteralPairs: multipleLiteralPairs ?? this.multipleLiteralPairs,
    additionalSteps: additionalSteps ?? this.additionalSteps,
    collisionPolicy: collisionPolicy ?? this.collisionPolicy,
  );
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

  bool get changed => sourcePath != targetPath;
  bool get directChange => file.name != newName;
  bool get isValid => errors.isEmpty;

  FileItem get renamedFile => file.copyWith(name: newName, path: targetPath);
}

class MultiRenamePlan {
  MultiRenamePlan._(
    List<MultiRenameEntry> entries,
    List<String> errors, {
    required this.pathContext,
    required this.referenceTime,
    required this.caseSensitivePaths,
    this.requiresStaging = false,
  }) : entries = List.unmodifiable(entries),
       errors = List.unmodifiable(errors);

  final List<MultiRenameEntry> entries;
  final List<String> errors;
  final p.Context pathContext;
  final DateTime referenceTime;
  final bool caseSensitivePaths;
  final bool requiresStaging;

  String pathKey(String path) {
    final normalized = pathContext.normalize(path);
    return caseSensitivePaths ? normalized : normalized.toLowerCase();
  }

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
/// Masks, metadata and ordered transformations are pure preview operations.
/// The selected dialect and a fixed reference time make presets reproducible.
/// Optional dependency planning resolves case changes, cycles and selected
/// ancestors; those plans must use the recoverable batch executor. The legacy
/// callback executor intentionally accepts only independent, direct renames.
class MultiRenameService {
  const MultiRenameService();

  MultiRenamePlan preview(
    List<FileItem> files,
    MultiRenameOptions options, {
    required String directory,
    p.Context? pathContext,
    Map<String, String> targetNames = const {},
    Iterable<String> existingPaths = const [],
    bool caseSensitivePaths = false,
    bool allowDependencies = false,
    DateTime? referenceTime,
    DateTime? optionsChangedAt,
  }) {
    final paths = pathContext ?? p.posix;
    final capturedTime = referenceTime ?? DateTime.now();
    final capturedOptionsTime = optionsChangedAt ?? capturedTime;
    final errors = <String>[];
    final steps = [options, ...options.additionalSteps];
    if (steps.length > 101 ||
        options.additionalSteps.any(
          (step) => step.additionalSteps.isNotEmpty,
        )) {
      errors.add(
        'A pipeline supports up to 100 flat additional transformation steps.',
      );
    }
    final patterns = <RegExp?>[];
    for (var stepIndex = 0; stepIndex < steps.length; stepIndex++) {
      final step = steps[stepIndex];
      void problem(String message) => errors.add(
        stepIndex == 0 ? message : 'Step ${stepIndex + 1}: $message',
      );
      if (step.counterStart.abs() > 999999999999 ||
          (step.counterStart < 0 &&
              step.dialect == RenameMaskDialect.crispCloud)) {
        problem('Counter start is outside the supported range.');
      }
      if (step.counterStep.abs() > 999999999999) {
        problem('Counter step is too large.');
      }
      if (step.counterWidth < 1 || step.counterWidth > 12) {
        problem('Counter width must be between 1 and 12.');
      }
      if (step.multipleLiteralPairs && step.useRegex) {
        problem(
          'Multiple literal pairs and regular expressions are separate modes.',
        );
      }
      RegExp? pattern;
      if (step.find.isNotEmpty) {
        try {
          pattern = RegExp(
            step.useRegex ? step.find : RegExp.escape(step.find),
            caseSensitive: step.caseSensitive,
            unicode: true,
          );
        } on FormatException catch (error) {
          problem('Invalid regular expression: ${error.message}');
        }
      }
      patterns.add(pattern);
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
      final manualName = targetNames[source];
      if (errors.isEmpty) {
        try {
          if (targetNames.containsKey(source)) {
            newName = targetNames[source]!;
          } else {
            for (var stepIndex = 0; stepIndex < steps.length; stepIndex++) {
              final current = file.copyWith(
                name: newName,
                path: paths.join(paths.dirname(source), newName),
              );
              newName = _transform(
                current,
                index,
                steps[stepIndex],
                patterns[stepIndex],
                current.path!,
                paths,
                capturedTime,
                optionsChangedAt: capturedOptionsTime,
              );
            }
          }
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

    String key(String path) => caseSensitivePaths
        ? paths.normalize(path)
        : paths.normalize(path).toLowerCase();
    if (options.collisionPolicy == RenameCollisionPolicy.number) {
      final vacated = rows
          .where((row) => row.directChange)
          .map((row) => key(row.sourcePath))
          .toSet();
      final occupied = existingPaths
          .map(key)
          .where((path) => !vacated.contains(path))
          .toSet();
      final reserved = rows
          .where((row) => !row.directChange)
          .map((row) => key(row.targetPath))
          .toSet();
      for (var index = 0; index < rows.length; index++) {
        final row = rows[index];
        if (!row.directChange) continue;
        var name = row.newName;
        var target = row.targetPath;
        final parts = _parts(name, row.file.isFolder);
        var suffix = 1;
        while (reserved.contains(key(target)) ||
            occupied.contains(key(target))) {
          name = _join('${parts.$1} (${suffix++})', parts.$2);
          target = paths.join(paths.dirname(row.sourcePath), name);
        }
        reserved.add(key(target));
        rows[index] = MultiRenameEntry._(
          file: row.file,
          sourcePath: row.sourcePath,
          targetPath: target,
          newName: name,
        );
        final invalid = validateName(name);
        if (invalid != null) rowErrors[index].add(invalid);
      }
    }
    final directTargets = rows.map((row) => row.targetPath).toList();
    if (allowDependencies) {
      final ancestors =
          rows
              .where(
                (row) =>
                    row.file.isFolder &&
                    row.file.isSymlink != true &&
                    row.directChange,
              )
              .toList()
            ..sort(
              (a, b) => b.sourcePath.length.compareTo(a.sourcePath.length),
            );
      for (var index = 0; index < rows.length; index++) {
        final row = rows[index];
        var target = row.targetPath;
        for (final ancestor in ancestors) {
          if (paths.isWithin(key(ancestor.sourcePath), key(row.sourcePath))) {
            target = paths.join(
              paths.dirname(ancestor.sourcePath),
              ancestor.newName,
              paths.relative(target, from: ancestor.sourcePath),
            );
          }
        }
        rows[index] = MultiRenameEntry._(
          file: row.file,
          sourcePath: row.sourcePath,
          targetPath: target,
          newName: row.newName,
        );
      }
    }
    final sources = <String, List<int>>{};
    final targets = <String, List<int>>{};
    final vacated = rows
        .where((row) => row.directChange)
        .map((row) => key(row.sourcePath))
        .toSet();
    final occupied = existingPaths
        .map(key)
        .where((path) => !vacated.contains(path))
        .toSet();
    for (var index = 0; index < rows.length; index++) {
      sources.putIfAbsent(key(rows[index].sourcePath), () => []).add(index);
      targets.putIfAbsent(key(rows[index].targetPath), () => []).add(index);
    }
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      if (row.directChange && occupied.contains(key(directTargets[index]))) {
        rowErrors[index].add(
          'The destination already exists. Choose another name or enable collision numbering.',
        );
      }
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
          !allowDependencies &&
          (sources[key(directTargets[index])] ?? []).any(
            (other) => other != index,
          )) {
        rowErrors[index].add(
          'This name belongs to another selected item. Use an intermediate name first.',
        );
      }
      if (!allowDependencies && row.changed && row.file.isFolder) {
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
    return MultiRenamePlan._(
      [
        for (var index = 0; index < rows.length; index++)
          MultiRenameEntry._(
            file: rows[index].file,
            sourcePath: rows[index].sourcePath,
            targetPath: rows[index].targetPath,
            newName: rows[index].newName,
            errors: rowErrors[index],
          ),
      ],
      errors,
      pathContext: paths,
      referenceTime: capturedTime,
      caseSensitivePaths: caseSensitivePaths,
      requiresStaging:
          allowDependencies &&
          rows.any(
            (row) =>
                row.changed &&
                (key(row.sourcePath) == key(row.targetPath) ||
                    row.sourcePath.toLowerCase() ==
                        row.targetPath.toLowerCase() ||
                    rows.any(
                      (other) =>
                          !identical(row, other) &&
                          (key(
                                    paths.join(
                                      paths.dirname(row.sourcePath),
                                      row.newName,
                                    ),
                                  ) ==
                                  key(other.sourcePath) ||
                              (other.file.isFolder &&
                                  other.file.isSymlink != true &&
                                  other.directChange &&
                                  paths.isWithin(
                                    key(other.sourcePath),
                                    key(row.sourcePath),
                                  ))),
                    )),
          ),
    );
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
    if (plan.requiresStaging) {
      throw MultiRenamePreflightException({
        '': 'This plan requires the recoverable batch rename executor.',
      });
    }
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
    DateTime referenceTime, {
    required DateTime optionsChangedAt,
    bool allowUnavailableValues = false,
  }) {
    final original = _parts(file.name, file.isFolder);
    String mask(String value) => expandRenameMask(
      value,
      RenameMaskContext(
        file: file,
        name: original.$1,
        extension: original.$2,
        sourcePath: source,
        paths: paths,
        index: index,
        counterStart: options.counterStart,
        counterStep: options.counterStep,
        counterWidth: options.counterWidth,
        referenceTime: referenceTime,
        optionsChangedAt: optionsChangedAt,
        dialect: options.dialect,
        dateSource: options.dateSource,
        dateZone: options.dateZone,
        dateOffsetMinutes: options.dateOffsetMinutes,
        variables: options.variables,
      ),
      allowUnavailableValues: allowUnavailableValues,
    );
    var name = mask(options.nameMask);
    var extension = file.isFolder ? '' : mask(options.extensionMask);

    String replace(String value) {
      if (pattern == null) return value;
      if (options.multipleLiteralPairs) {
        final from = options.find.split('|');
        final to = options.replace.split('|');
        if (from.any((word) => word.isEmpty) ||
            (to.length != 1 && to.length != from.length)) {
          throw const FormatException(
            'Enter nonempty search pairs and one replacement or a matching number of replacements.',
          );
        }
        final expression = RegExp(
          from.map((word) => '(${RegExp.escape(word)})').join('|'),
          caseSensitive: options.caseSensitive,
          unicode: true,
        );
        String substitute(Match match) {
          if (to.length == 1) return to.single;
          // Unicode regexp folding also matches characters such as long s
          // and final sigma. Lowercase equality cannot identify those matches.
          // Capturing each escaped alternative keeps the replacement tied to
          // the exact alternative selected by the same regexp engine.
          for (var index = 0; index < from.length; index++) {
            if (match.group(index + 1) != null) return to[index];
          }
          throw const FormatException(
            'The matched literal replacement pair could not be identified.',
          );
        }

        return options.firstMatchOnly
            ? value.replaceFirstMapped(expression, substitute)
            : value.replaceAllMapped(expression, substitute);
      }
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
}
