import 'dart:convert';

import 'package:path/path.dart' as p;

/// Interchange format for Commander file lists: one original path per line.
///
/// Lists contain no account credentials or provider identities. Importers
/// resolve every path against the explicitly chosen, current panel source.
class FileListPaths {
  const FileListPaths._();

  static List<String> parse(
    String text, {
    required String basePath,
    required bool local,
    int maxItems = 10000,
  }) {
    if (text.length > 4 * 1024 * 1024 ||
        utf8.encode(text).length > 4 * 1024 * 1024) {
      throw const FormatException(
        'The file list is too large (maximum 4 MiB of text).',
      );
    }
    final windows =
        local &&
        (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(basePath) ||
            basePath.startsWith(r'\\'));
    final paths = p.Context(style: windows ? p.Style.windows : p.Style.posix);
    final result = <String>[];
    final seen = <String>{};
    var lineNumber = 0;
    for (var line
        in text.replaceFirst(RegExp('^\uFEFF'), '').split(RegExp(r'\r?\n'))) {
      lineNumber++;
      line = line.trim();
      if (line.isEmpty) continue;
      if (line.length >= 2 && line.startsWith('"') && line.endsWith('"')) {
        line = line.substring(1, line.length - 1);
      }
      if (line.isEmpty) {
        throw FormatException(
          'Line $lineNumber contains an empty quoted path.',
        );
      }
      if (line.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
        throw FormatException('Line $lineNumber contains a control character.');
      }
      if (line.toLowerCase().startsWith('file:')) {
        if (!local) {
          throw FormatException(
            'Line $lineNumber is a local file URL. Choose a local panel first.',
          );
        }
        try {
          line = Uri.parse(line).toFilePath(windows: windows);
        } on FormatException {
          throw FormatException(
            'Line $lineNumber is not a valid local file URL.',
          );
        } on UnsupportedError {
          throw FormatException(
            'Line $lineNumber is not a file URL for this local filesystem.',
          );
        }
      } else if (line.contains('://')) {
        throw FormatException(
          'Line $lineNumber is a URL. File lists use paths in the current source.',
        );
      }
      // Validate again after URI decoding, which can introduce encoded newlines
      // or nulls that were not visible in the source text.
      if (line.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
        throw FormatException('Line $lineNumber contains a control character.');
      }
      if (!windows &&
          (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(line) ||
              line.startsWith(r'\\'))) {
        throw FormatException(
          'Line $lineNumber is a Windows path. Choose its Windows filesystem first.',
        );
      }
      final resolved = paths.normalize(
        paths.isAbsolute(line) ? line : paths.join(basePath, line),
      );
      if (!paths.isAbsolute(resolved)) {
        throw FormatException(
          'Line $lineNumber could not be resolved to an absolute path.',
        );
      }
      if (paths.dirname(resolved) == resolved) {
        throw FormatException(
          'Line $lineNumber names a filesystem root. List files or subfolders instead.',
        );
      }
      final key = windows ? resolved.toLowerCase() : resolved;
      if (seen.add(key)) result.add(resolved);
      if (result.length > maxItems) {
        throw FormatException('The file list exceeds $maxItems entries.');
      }
    }
    if (result.isEmpty) throw const FormatException('The file list is empty.');
    return result;
  }

  static String encode(Iterable<String> paths) {
    final unique = <String>{};
    for (final path in paths) {
      if (path.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
        throw const FormatException(
          'A path contains a control character and cannot be exported as a text list.',
        );
      }
      if (path.isNotEmpty) unique.add(path);
    }
    return unique
        .map((path) => path.trim() == path ? path : '"$path"')
        .join('\n');
  }
}
