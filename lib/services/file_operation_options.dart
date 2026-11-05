import '../models/file_item.dart';
import '../models/file_search_query.dart';
import 'file_selection_pattern.dart';

enum FileOperationKind { copy, move }

enum FileConflictPolicy {
  ask,
  skip,
  replace,
  replaceIfNewer,
  keepBoth,
  replaceIfLarger,
  replaceIfSmaller,
  resumeVerified,
  append,
}

enum DirectoryConflictPolicy { ask, merge, skip }

enum FileOperationOutcome {
  pending,
  copied,
  moved,
  directoryCreated,
  skipped,
  filtered,
  cancelled,
  failed,
  needsDecision,
}

/// Frozen and serializable settings; credentials and account objects never
/// belong in saved profiles or operation manifests.
class FileOperationOptions {
  const FileOperationOptions({
    this.kind = FileOperationKind.copy,
    this.fileConflict = FileConflictPolicy.ask,
    this.directoryConflict = DirectoryConflictPolicy.merge,
    this.recursive = true,
    this.preserveRelativePaths = false,
    this.relativeBase,
    this.preserveModified = false,
    this.preservePermissions = false,
    this.preserveOwnership = false,
    this.preserveExtendedAttributes = false,
    this.preserveAcl = false,
    this.verifyContents = false,
    this.stopOnError = true,
    this.copySymbolicLinks = false,
    this.pattern,
    this.destinationName,
    this.destinationMask = '*.*',
    this.minimumSize,
    this.maximumSize,
    this.modifiedAfter,
    this.modifiedBefore,
    this.excludedDirectories,
    this.excludeEmptyDirectories = false,
    this.includeHidden = true,
    this.preferNative = true,
  });

  final FileOperationKind kind;
  final FileConflictPolicy fileConflict;
  final DirectoryConflictPolicy directoryConflict;
  final bool recursive;
  final bool preserveRelativePaths;
  final String? relativeBase;
  final bool preserveModified;
  final bool preservePermissions;
  final bool preserveOwnership;
  final bool preserveExtendedAttributes;
  final bool preserveAcl;
  final bool verifyContents;
  final bool stopOnError;
  final bool copySymbolicLinks;
  final FileSelectionPattern? pattern;

  /// An exact new name for a single selected root (including directories).
  final String? destinationName;

  /// Applied to regular file names at every selected depth.
  final String destinationMask;
  final int? minimumSize;
  final int? maximumSize;
  final DateTime? modifiedAfter;
  final DateTime? modifiedBefore;
  final FileSelectionPattern? excludedDirectories;
  final bool excludeEmptyDirectories;
  final bool includeHidden;
  final bool preferNative;

  FileSearchQuery get searchFilter => FileSearchQuery(
    namePattern: pattern?.expression ?? '*',
    nameMode: pattern?.mode ?? FilePatternMode.wildcard,
    caseSensitive: pattern?.caseSensitive ?? false,
    matchFullPath: pattern?.matchFullPath ?? false,
    includeHidden: includeHidden,
    minSize: minimumSize,
    maxSize: maximumSize,
    modifiedAfter: modifiedAfter,
    modifiedBefore: modifiedBefore,
  );

  bool matchesFile(FileItem item) =>
      (pattern?.matches(item) ?? true) &&
      (includeHidden || !item.name.startsWith('.')) &&
      searchFilter.matchesMetadata(item);

  Map<String, dynamic> toJson() => {
    'version': 1,
    'kind': kind.name,
    'fileConflict': fileConflict.name,
    'directoryConflict': directoryConflict.name,
    'recursive': recursive,
    'preserveRelativePaths': preserveRelativePaths,
    'relativeBase': relativeBase,
    'preserveModified': preserveModified,
    'preservePermissions': preservePermissions,
    'preserveOwnership': preserveOwnership,
    'preserveExtendedAttributes': preserveExtendedAttributes,
    'preserveAcl': preserveAcl,
    'verifyContents': verifyContents,
    'stopOnError': stopOnError,
    'copySymbolicLinks': copySymbolicLinks,
    'pattern': _patternJson(pattern),
    'destinationName': destinationName,
    'destinationMask': destinationMask,
    'minimumSize': minimumSize,
    'maximumSize': maximumSize,
    'modifiedAfter': modifiedAfter?.toUtc().toIso8601String(),
    'modifiedBefore': modifiedBefore?.toUtc().toIso8601String(),
    'excludedDirectories': _patternJson(excludedDirectories),
    'excludeEmptyDirectories': excludeEmptyDirectories,
    'includeHidden': includeHidden,
    'preferNative': preferNative,
  };

  factory FileOperationOptions.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported transfer options version.');
    }
    return FileOperationOptions(
      kind: FileOperationKind.values.byName(json['kind'] as String),
      fileConflict: FileConflictPolicy.values.byName(
        json['fileConflict'] as String,
      ),
      directoryConflict: DirectoryConflictPolicy.values.byName(
        json['directoryConflict'] as String,
      ),
      recursive: json['recursive'] != false,
      preserveRelativePaths: json['preserveRelativePaths'] == true,
      relativeBase: json['relativeBase'] as String?,
      preserveModified: json['preserveModified'] == true,
      preservePermissions: json['preservePermissions'] == true,
      preserveOwnership: json['preserveOwnership'] == true,
      preserveExtendedAttributes: json['preserveExtendedAttributes'] == true,
      preserveAcl: json['preserveAcl'] == true,
      verifyContents: json['verifyContents'] == true,
      stopOnError: json['stopOnError'] != false,
      copySymbolicLinks: json['copySymbolicLinks'] == true,
      pattern: _readPattern(json['pattern']),
      destinationName: json['destinationName'] as String?,
      destinationMask: json['destinationMask'] as String? ?? '*.*',
      minimumSize: json['minimumSize'] as int?,
      maximumSize: json['maximumSize'] as int?,
      modifiedAfter: _date(json['modifiedAfter']),
      modifiedBefore: _date(json['modifiedBefore']),
      excludedDirectories: _readPattern(json['excludedDirectories']),
      excludeEmptyDirectories: json['excludeEmptyDirectories'] == true,
      includeHidden: json['includeHidden'] != false,
      preferNative: json['preferNative'] != false,
    );
  }

  static DateTime? _date(dynamic value) =>
      value == null ? null : DateTime.parse(value as String);

  static Map<String, dynamic>? _patternJson(FileSelectionPattern? value) =>
      value == null
      ? null
      : {
          'expression': value.expression,
          'mode': value.mode.name,
          'caseSensitive': value.caseSensitive,
          'matchFullPath': value.matchFullPath,
          'includeFiles': value.includeFiles,
          'includeFolders': value.includeFolders,
        };

  static FileSelectionPattern? _readPattern(dynamic value) => value == null
      ? null
      : FileSelectionPattern(
          value['expression'] as String,
          mode: FilePatternMode.values.byName(value['mode'] as String),
          caseSensitive: value['caseSensitive'] == true,
          matchFullPath: value['matchFullPath'] == true,
          includeFiles: value['includeFiles'] != false,
          includeFolders: value['includeFolders'] != false,
        );
}
