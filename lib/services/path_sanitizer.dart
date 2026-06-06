// lib/services/path_sanitizer.dart
//
// Utility class for sanitizing and validating file paths and filenames.
// Protects against path traversal attacks, reserved names, and dangerous
// characters that can cause issues on various operating systems and
// cloud storage providers.

/// Utility for sanitizing filenames and detecting dangerous path patterns.
class PathSanitizer {
  /// Maximum filename length allowed (matches most filesystem limits).
  static const int maxFilenameLength = 255;

  /// Windows reserved device names that cannot be used as filenames.
  static const List<String> windowsReservedNames = [
    'CON',
    'PRN',
    'AUX',
    'NUL',
    'COM1',
    'COM2',
    'COM3',
    'COM4',
    'COM5',
    'COM6',
    'COM7',
    'COM8',
    'COM9',
    'LPT1',
    'LPT2',
    'LPT3',
    'LPT4',
    'LPT5',
    'LPT6',
    'LPT7',
    'LPT8',
    'LPT9',
  ];

  /// Pattern for detecting path traversal sequences.
  static final RegExp _traversalPattern = RegExp(
    r'(\.\.[\\/]|[\\/]\.\.)',
    caseSensitive: false,
  );

  /// Pattern for percent-encoded path traversal (%2e%2e%2f, %2e%2e%5c, etc.).
  static final RegExp _encodedTraversalPattern = RegExp(
    r'%2e%2e[%2f5c]|%2e\.|\.%2e',
    caseSensitive: false,
  );

  /// Sanitizes a filename by removing or replacing dangerous characters and
  /// trimming it to the maximum allowed length.
  ///
  /// - Removes null bytes and control characters
  /// - Replaces dangerous special characters with underscores
  /// - Trims leading/trailing dots and spaces (Windows compatibility)
  /// - Truncates to [maxFilenameLength] characters
  /// - Returns '_' for empty or whitespace-only names
  static String sanitizeFilename(String name) {
    if (name.isEmpty) return '_';

    // Remove null bytes first
    var result = name.replaceAll('\x00', '');

    // Remove other control characters (0x01–0x1F, 0x7F)
    result = result.replaceAll(RegExp(r'[\x01-\x1F\x7F]'), '');

    // Replace Windows/shell forbidden and dangerous characters
    result = result.replaceAll(RegExp(r'[<>:"/\\|?*;`$&!]'), '_');

    // Trim trailing dots and spaces (Windows rejects these)
    result = result.trimRight().replaceAll(RegExp(r'[. ]+$'), '');

    // Trim leading spaces
    result = result.trimLeft();

    if (result.isEmpty) return '_';

    // Truncate to max length, preserving the extension if possible
    if (result.length > maxFilenameLength) {
      final dotIndex = result.lastIndexOf('.');
      if (dotIndex > 0 && result.length - dotIndex <= 16) {
        final ext = result.substring(dotIndex);
        result = result.substring(0, maxFilenameLength - ext.length) + ext;
      } else {
        result = result.substring(0, maxFilenameLength);
      }
    }

    return result;
  }

  /// Returns `true` if [path] contains path traversal sequences.
  ///
  /// Detects:
  /// - `../` and `..\` (Unix and Windows)
  /// - Absolute paths starting with `/` or a drive letter like `C:\`
  /// - Percent-encoded traversal sequences (`%2e%2e%2f`)
  /// - Null bytes embedded in paths
  static bool isPathTraversal(String path) {
    if (path.isEmpty) return false;

    // Null bytes are always suspicious
    if (path.contains('\x00')) return true;

    // Absolute Unix path injected into a relative context
    if (path.startsWith('/')) return true;

    // Windows absolute path (e.g. C:\...)
    if (RegExp(r'^[A-Za-z]:[/\\]').hasMatch(path)) return true;

    // Classic traversal sequences
    if (_traversalPattern.hasMatch(path)) return true;

    // Bare `..` component (the whole path is just "..")
    if (path == '..') return true;

    // Percent-encoded traversal
    if (_encodedTraversalPattern.hasMatch(path)) return true;

    // Double-encoded: %252e%252e = URL-decoded once gives %2e%2e
    if (path.toLowerCase().contains('%252e')) return true;

    return false;
  }

  /// Normalizes all path separators to forward slashes.
  ///
  /// Converts `\` to `/` and collapses consecutive slashes (except a
  /// leading `//` which may indicate a UNC path).
  static String normalizePathSeparators(String path) {
    if (path.isEmpty) return path;

    // Replace all backslashes with forward slashes
    var result = path.replaceAll('\\', '/');

    // Collapse consecutive slashes, but preserve leading // (UNC)
    if (result.startsWith('//')) {
      result = '//${result.substring(2).replaceAll(RegExp(r'/+'), '/')}';
    } else {
      result = result.replaceAll(RegExp(r'/+'), '/');
    }

    return result;
  }

  /// Returns `true` if [name] is a Windows reserved device name.
  ///
  /// Checks are case-insensitive. The check also handles names with
  /// extensions (e.g. `CON.txt` is reserved on Windows).
  static bool isReservedName(String name) {
    if (name.isEmpty) return false;

    // Strip any extension for the comparison
    final baseName =
        name.contains('.') ? name.substring(0, name.indexOf('.')).toUpperCase() : name.toUpperCase();

    return windowsReservedNames.contains(baseName);
  }

  /// Returns `true` if [filename] consists only of whitespace.
  static bool isWhitespaceOnly(String filename) {
    return filename.trim().isEmpty && filename.isNotEmpty;
  }

  /// Returns `true` if [filename] has no characters other than dots.
  static bool isDotsOnly(String filename) {
    return filename.isNotEmpty && filename.replaceAll('.', '').isEmpty;
  }

  /// Returns the extension of a filename (including the dot), or an empty
  /// string if there is none.
  static String getExtension(String filename) {
    final lastDot = filename.lastIndexOf('.');
    if (lastDot <= 0) return ''; // hidden files like ".gitignore" have no ext
    return filename.substring(lastDot);
  }

  /// Returns `true` if [filename] starts with a UTF-8 BOM (U+FEFF).
  static bool hasBom(String filename) {
    return filename.startsWith('\uFEFF');
  }
}
