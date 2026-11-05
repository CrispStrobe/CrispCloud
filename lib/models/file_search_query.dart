import '../services/file_selection_pattern.dart';
import 'file_item.dart';

/// Serializable search semantics. An empty roots list means the current panel
/// directory; explicit roots are retained exactly in saved searches.
class FileSearchQuery {
  const FileSearchQuery({
    this.namePattern = '*',
    this.nameMode = FilePatternMode.wildcard,
    this.caseSensitive = false,
    this.matchFullPath = false,
    this.roots = const [],
    this.recursive = true,
    this.maxDepth,
    this.includeFiles = true,
    this.includeFolders = true,
    this.includeHidden = true,
    this.excludeDirectories = '',
    this.contentPattern = '',
    this.contentRegex = false,
    this.contentCaseSensitive = false,
    this.contentEncoding = 'auto',
    this.contentNegated = false,
    this.searchArchives = false,
    this.maxContentBytes = 64 * 1024 * 1024,
    this.extensions = const [],
    this.minSize,
    this.maxSize,
    this.modifiedAfter,
    this.modifiedBefore,
  });
  final String namePattern;
  final FilePatternMode nameMode;
  final bool caseSensitive;
  final bool matchFullPath;
  final List<String> roots;
  final bool recursive;
  final int? maxDepth;
  final bool includeFiles;
  final bool includeFolders;
  final bool includeHidden;
  final String excludeDirectories;
  final String contentPattern;
  final bool contentRegex;
  final bool contentCaseSensitive;
  final String contentEncoding;
  final bool contentNegated;
  final bool searchArchives;
  final int maxContentBytes;
  final List<String> extensions;
  final int? minSize;
  final int? maxSize;
  final DateTime? modifiedAfter;
  final DateTime? modifiedBefore;

  FileSelectionPattern get nameMatcher => FileSelectionPattern(
    namePattern,
    mode: nameMode,
    caseSensitive: caseSensitive,
    matchFullPath: matchFullPath,
    includeFiles: includeFiles,
    includeFolders: includeFolders,
  );

  void validate() {
    nameMatcher;
    if (contentRegex && contentPattern.isNotEmpty) {
      RegExp(
        contentPattern,
        caseSensitive: contentCaseSensitive,
        multiLine: true,
        unicode: true,
      );
    }
    if (excludeDirectories.isNotEmpty) FileSelectionPattern(excludeDirectories);
    if (maxDepth != null && maxDepth! < 0) {
      throw const FormatException('Depth must be zero or greater.');
    }
    if (maxContentBytes <= 0 || maxContentBytes > 256 * 1024 * 1024) {
      throw const FormatException(
        'Content limit must be between 1 byte and 256 MiB.',
      );
    }
    if ((minSize != null && minSize! < 0) ||
        (maxSize != null && maxSize! < 0) ||
        (minSize != null && maxSize != null && minSize! > maxSize!)) {
      throw const FormatException('Enter a valid minimum and maximum size.');
    }
    if (modifiedAfter != null &&
        modifiedBefore != null &&
        modifiedAfter!.isAfter(modifiedBefore!)) {
      throw const FormatException('The date range ends before it starts.');
    }
  }

  bool matchesMetadata(FileItem file) {
    if (!file.isFolder) {
      if (extensions.isNotEmpty && !extensions.contains(file.extension))
        return false;
      if ((minSize != null || maxSize != null) && file.size == null)
        return false;
      if (minSize != null && file.size! < minSize!) return false;
      if (maxSize != null && file.size! > maxSize!) return false;
    }
    if (modifiedAfter != null &&
        (file.updatedAt == null || file.updatedAt!.isBefore(modifiedAfter!)))
      return false;
    if (modifiedBefore != null &&
        (file.updatedAt == null || file.updatedAt!.isAfter(modifiedBefore!)))
      return false;
    return true;
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'namePattern': namePattern,
    'nameMode': nameMode.name,
    'caseSensitive': caseSensitive,
    'matchFullPath': matchFullPath,
    'roots': roots,
    'recursive': recursive,
    'maxDepth': maxDepth,
    'includeFiles': includeFiles,
    'includeFolders': includeFolders,
    'includeHidden': includeHidden,
    'excludeDirectories': excludeDirectories,
    'contentPattern': contentPattern,
    'contentRegex': contentRegex,
    'contentCaseSensitive': contentCaseSensitive,
    'contentEncoding': contentEncoding,
    'contentNegated': contentNegated,
    'searchArchives': searchArchives,
    'maxContentBytes': maxContentBytes,
    'extensions': extensions,
    'minSize': minSize,
    'maxSize': maxSize,
    'modifiedAfter': modifiedAfter?.toIso8601String(),
    'modifiedBefore': modifiedBefore?.toIso8601String(),
  };

  factory FileSearchQuery.fromJson(
    Map<String, dynamic> json,
  ) => FileSearchQuery(
    namePattern: json['namePattern'] as String? ?? '*',
    nameMode: FilePatternMode.values.byName(
      json['nameMode'] as String? ?? 'wildcard',
    ),
    caseSensitive: json['caseSensitive'] as bool? ?? false,
    matchFullPath: json['matchFullPath'] as bool? ?? false,
    roots: List<String>.from(json['roots'] as List? ?? []),
    recursive: json['recursive'] as bool? ?? true,
    maxDepth: json['maxDepth'] as int?,
    includeFiles: json['includeFiles'] as bool? ?? true,
    includeFolders: json['includeFolders'] as bool? ?? true,
    includeHidden: json['includeHidden'] as bool? ?? true,
    excludeDirectories: json['excludeDirectories'] as String? ?? '',
    contentPattern: json['contentPattern'] as String? ?? '',
    contentRegex: json['contentRegex'] as bool? ?? false,
    contentCaseSensitive: json['contentCaseSensitive'] as bool? ?? false,
    contentEncoding: json['contentEncoding'] as String? ?? 'auto',
    contentNegated: json['contentNegated'] as bool? ?? false,
    searchArchives: json['searchArchives'] as bool? ?? false,
    maxContentBytes: json['maxContentBytes'] as int? ?? 64 * 1024 * 1024,
    extensions: List<String>.from(json['extensions'] as List? ?? []),
    minSize: json['minSize'] as int?,
    maxSize: json['maxSize'] as int?,
    modifiedAfter: DateTime.tryParse(json['modifiedAfter'] as String? ?? ''),
    modifiedBefore: DateTime.tryParse(json['modifiedBefore'] as String? ?? ''),
  );
}
