import '../models/file_item.dart';

/// How the expression in a Commander selection dialog is interpreted.
enum FilePatternMode { wildcard, regex }

/// Selection marks are separate from the cursor and from the visible filter.
enum SelectionAction { select, deselect, invert, replace }

/// A compiled, reusable filename/path matcher.
///
/// Wildcards match the whole name (or path). `*` matches any number of
/// characters, `?` matches one, `;` separates alternatives, and `|` starts
/// exclusions: `*.jpg;*.png|thumb*`. As in Commander, `*.*` includes names
/// without an extension. Regex mode uses [RegExp.hasMatch]; use `^` and `$`
/// when an expression must match the whole name.
class FileSelectionPattern {
  FileSelectionPattern(
    this.expression, {
    this.mode = FilePatternMode.wildcard,
    this.caseSensitive = false,
    this.matchFullPath = false,
    this.includeFiles = true,
    this.includeFolders = true,
  }) {
    if (expression.trim().isEmpty) {
      throw const FormatException(
        'Enter a wildcard mask or regular expression.',
      );
    }
    if (!includeFiles && !includeFolders) {
      throw const FormatException('Include files, folders, or both.');
    }
    if (expression.length > 4096) {
      throw const FormatException(
        'The expression is too long (maximum 4096 characters).',
      );
    }
    if (mode == FilePatternMode.regex) {
      _includes = [
        RegExp(expression, caseSensitive: caseSensitive, unicode: true),
      ];
      _excludes = const [];
      return;
    }

    final sections = expression.split('|');
    if (sections.length > 2) {
      throw const FormatException(
        'Use one | between included and excluded masks.',
      );
    }
    final includes = _masks(sections.first);
    final excludes = sections.length == 2 ? _masks(sections.last) : <String>[];
    if (sections.length == 2 && excludes.isEmpty) {
      throw const FormatException('Enter an excluded mask after |.');
    }
    if (includes.isEmpty && excludes.isEmpty) {
      throw const FormatException('Enter at least one wildcard mask.');
    }
    _includes = (includes.isEmpty ? ['*'] : includes)
        .map(_compileWildcard)
        .toList();
    _excludes = excludes.map(_compileWildcard).toList();
  }

  final String expression;
  final FilePatternMode mode;
  final bool caseSensitive;
  final bool matchFullPath;
  final bool includeFiles;
  final bool includeFolders;
  late final List<RegExp> _includes;
  late final List<RegExp> _excludes;

  /// Store matching options only; a history entry never changes the requested
  /// select/deselect action when recalled from another command.
  Map<String, Object> toJson() => {
    'expression': expression,
    'mode': mode.name,
    'caseSensitive': caseSensitive,
    'matchFullPath': matchFullPath,
    'includeFiles': includeFiles,
    'includeFolders': includeFolders,
  };

  factory FileSelectionPattern.fromJson(Map<String, dynamic> json) {
    final expression = json['expression'];
    final mode = json['mode'];
    if (expression is! String ||
        !FilePatternMode.values.any((value) => value.name == mode) ||
        const [
          'caseSensitive',
          'matchFullPath',
          'includeFiles',
          'includeFolders',
        ].any((key) => json[key] is! bool)) {
      throw const FormatException('Invalid saved selection pattern.');
    }
    return FileSelectionPattern(
      expression,
      mode: FilePatternMode.values.byName(mode as String),
      caseSensitive: json['caseSensitive'] as bool,
      matchFullPath: json['matchFullPath'] as bool,
      includeFiles: json['includeFiles'] as bool,
      includeFolders: json['includeFolders'] as bool,
    );
  }

  static List<String> _masks(String text) => text
      .split(';')
      .map((mask) => mask.trim())
      .where((mask) => mask.isNotEmpty)
      .toList();

  RegExp _compileWildcard(String mask) {
    if (mask == '*.*') mask = '*';
    final pattern = StringBuffer('^');
    for (final rune in mask.runes) {
      final char = String.fromCharCode(rune);
      pattern.write(switch (char) {
        '*' => '[\\s\\S]*',
        '?' => '[\\s\\S]',
        _ => RegExp.escape(char),
      });
    }
    pattern.write(r'$');
    return RegExp(
      pattern.toString(),
      caseSensitive: caseSensitive,
      unicode: true,
    );
  }

  /// Parent-directory entries never receive selection marks.
  bool matches(FileItem item) {
    if (item.name == '..' || item.name == '.') return false;
    if (item.isFolder ? !includeFolders : !includeFiles) return false;
    final value = matchFullPath ? item.path : item.name;
    if (value == null || value.isEmpty) return false;
    return _includes.any((pattern) => pattern.hasMatch(value)) &&
        !_excludes.any((pattern) => pattern.hasMatch(value));
  }
}
