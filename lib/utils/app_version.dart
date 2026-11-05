// Version label formatting shared by the About dialog and tests.

/// Format a human-readable app version without hiding useful build metadata.
///
/// The git hash is optional: local builds that did not pass
/// `--dart-define=GIT_HASH=...` still show the version and build number.
String formatAppVersion({
  required String version,
  String? buildNumber,
  String? gitHash,
}) {
  final parts = <String>[];
  final build = buildNumber?.trim();
  if (build != null && build.isNotEmpty && build != '0') {
    parts.add('build $build');
  }
  final hash = gitHash?.trim();
  if (hash != null && hash.isNotEmpty) {
    // A 12-character prefix is enough to identify a commit while staying
    // readable in the dialog. Full hashes are trimmed for display only.
    parts.add(hash.length > 12 ? hash.substring(0, 12) : hash);
  }
  return parts.isEmpty
      ? 'Version $version'
      : 'Version $version (${parts.join(', ')})';
}
