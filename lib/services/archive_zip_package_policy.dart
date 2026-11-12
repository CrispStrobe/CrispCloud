import 'dart:convert';

import 'archive_write_model.dart';

/// ZIP-compatible formats that do not require a package-specific rebuild.
bool isEditableZipAlias(String name) {
  final lower = name.toLowerCase();
  return const ['.cbz', '.kmz', '.jar', '.war', '.ear'].any(lower.endsWith);
}

/// Applied to both the original and the proposed member set. In particular,
/// renaming or replacing a manifest must not smuggle a stale signature into
/// an otherwise unsigned Java archive.
Future<String?> archiveZipPackageIssue(
  String name,
  List<ArchiveWriteEntry> entries,
) async {
  final lower = name.toLowerCase();
  final java = const ['.jar', '.war', '.ear'].any(lower.endsWith);
  if (java) {
    for (final entry in entries) {
      final upper = entry.path.toUpperCase();
      if (RegExp(r'^META-INF/[^/]+\.(SF|RSA|DSA|EC)$').hasMatch(upper) ||
          RegExp(r'^META-INF/SIG-[^/]+$').hasMatch(upper)) {
        return 'This Java archive contains signing records. Rebuilding it requires its signing workflow; signatures will not be removed.';
      }
      if (upper == 'META-INF/MANIFEST.MF' && !entry.isDirectory) {
        if (entry.size > 1024 * 1024) {
          return 'The Java manifest exceeds the supported one MiB inspection limit.';
        }
        final manifest = latin1.decode(await entry.read(maxBytes: 1024 * 1024));
        if (RegExp(
              r'^([^\r\n:]*-)?Digest([^\r\n:]*):',
              caseSensitive: false,
              multiLine: true,
            ).hasMatch(manifest) ||
            RegExp(
              r'^Signature-Version:',
              caseSensitive: false,
              multiLine: true,
            ).hasMatch(manifest)) {
          return 'This Java manifest contains signature digests. A package signing workflow is required to rebuild it.';
        }
      }
    }
  }
  if (lower.endsWith('.kmz') &&
      !entries.any(
        (entry) =>
            !entry.isDirectory &&
            !entry.path.contains('/') &&
            entry.path.toLowerCase().endsWith('.kml'),
      )) {
    return 'A KMZ archive requires a KML document at its top level.';
  }
  return null;
}
