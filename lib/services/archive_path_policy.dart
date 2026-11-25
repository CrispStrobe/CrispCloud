/// Thrown when a stored archive member name cannot be mapped to a safe path
/// below the extraction root.
class ArchivePathException implements Exception {
  const ArchivePathException(this.message);
  final String message;

  @override
  String toString() => 'ArchivePathException: $message';
}

/// Normalizes one archive member name without touching the filesystem.
///
/// Rejects absolute paths, drive-letter prefixes, parent traversal, NUL bytes
/// and names that normalize to an empty path. This code is deliberately pure
/// Dart so the property fuzzer and platform hosts share one implementation.
String safeArchiveMemberPath(String name) {
  final path = name.replaceAll('\\', '/');
  final parts = path.split('/').where((s) => s.isNotEmpty && s != '.').toList();
  if (path.startsWith('/') ||
      RegExp(r'^[a-zA-Z]:').hasMatch(path) ||
      path.contains('\u0000') ||
      parts.isEmpty ||
      parts.contains('..') ||
      parts.any((part) => part.contains(':'))) {
    throw ArchivePathException('Unsafe archive path: $name');
  }
  return parts.join('/');
}
