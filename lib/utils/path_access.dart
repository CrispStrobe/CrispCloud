// lib/utils/path_access.dart
//
// Path containment checks for security-scoped access. The macOS bookmark
// picker may return a path with a trailing slash or different casing, so a
// raw startsWith() check wrongly reports "outside the granted directory".

import 'dart:io';

/// Normalize separators and trailing slashes for access comparisons.
String normalizeAccessPath(String value) {
  var normalized = value.replaceAll('\\', '/');
  while (normalized.length > 1 && normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

/// True when [path] equals [base] or is contained in it.
///
/// [caseInsensitive] should be true on macOS/Windows (default filesystems are
/// case-insensitive there).
bool isSameOrUnderPath(
  String path,
  String base, {
  bool? caseInsensitive,
}) {
  final ignoreCase =
      caseInsensitive ?? (Platform.isMacOS || Platform.isWindows);
  var normalizedPath = normalizeAccessPath(path);
  var normalizedBase = normalizeAccessPath(base);
  if (ignoreCase) {
    normalizedPath = normalizedPath.toLowerCase();
    normalizedBase = normalizedBase.toLowerCase();
  }
  return normalizedPath == normalizedBase ||
      normalizedPath.startsWith('$normalizedBase/');
}
