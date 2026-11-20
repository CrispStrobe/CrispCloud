/// Metadata for the optional CrispOffice open font packs.
///
/// The files are hosted in a versioned GitHub release, never in this package.
/// Every file carries the SHA-256 that the host verifies before installing it.
library;

class OfficeFontPackFile {
  const OfficeFontPackFile({
    required this.fileName,
    required this.family,
    required this.sha256,
    required this.bytes,
    this.weight = 400,
    this.italic = false,
    this.aliases = const <String>[],
  });

  final String fileName;
  final String family;
  final String sha256;
  final int bytes;
  final int weight;
  final bool italic;
  final List<String> aliases;
}

class OfficeFontPack {
  const OfficeFontPack({
    required this.id,
    required this.title,
    required this.description,
    required this.source,
    required this.licence,
    required this.licenceUrl,
    required this.baseUrl,
    required this.bytes,
    required this.files,
  });

  final String id;
  final String title;
  final String description;

  /// Human-readable source, including the upstream revision.
  final String source;
  final String licence;
  final String licenceUrl;

  /// Immutable release directory. Files are addressed as `$baseUrl/$fileName`.
  final String baseUrl;

  /// Sum of the verified file sizes, used for review and progress.
  final int bytes;
  final List<OfficeFontPackFile> files;
}
