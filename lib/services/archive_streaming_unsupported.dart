import 'archive_types.dart';

/// An unsupported streamed profile may use the existing bounded workspace.
class ArchiveStreamingUnsupported extends ArchiveViewException {
  const ArchiveStreamingUnsupported(super.message);
}
