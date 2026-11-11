/// A bounded, metadata-only size observation for one exact listed folder.
/// Partial measurements never become a folder's complete calculated size.
enum FolderSizePhase {
  queued,
  scanning,
  stopping,
  complete,
  partial,
  cancelled,
  failed,
}

class FolderSizeMeasurement {
  const FolderSizeMeasurement({
    required this.phase,
    this.bytes = 0,
    this.files = 0,
    this.folders = 0,
    this.unknownSizes = 0,
    this.skippedLinks = 0,
    this.issueCount = 0,
    this.limited = false,
    this.sourceChanged = false,
  });

  final FolderSizePhase phase;
  final int bytes;
  final int files;
  final int folders;
  final int unknownSizes;
  final int skippedLinks;
  final int issueCount;
  final bool limited;
  final bool sourceChanged;

  bool get isActive => switch (phase) {
    FolderSizePhase.queued ||
    FolderSizePhase.scanning ||
    FolderSizePhase.stopping => true,
    _ => false,
  };

  FolderSizeMeasurement withPhase(FolderSizePhase value) =>
      FolderSizeMeasurement(
        phase: value,
        bytes: bytes,
        files: files,
        folders: folders,
        unknownSizes: unknownSizes,
        skippedLinks: skippedLinks,
        issueCount: issueCount,
        limited: limited,
        sourceChanged: sourceChanged,
      );
}
