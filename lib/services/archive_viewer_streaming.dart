import 'archive_streaming_unsupported.dart';
import 'archive_types.dart';

/// The native viewer can stream these containers and inspected data images.
/// Other profiles retain their existing bounded browsing readers.
bool isStreamedArchiveViewerName(String name) {
  final lower = name.toLowerCase();
  return const [
    '.zip',
    '.cbz',
    '.7z',
    '.cb7',
    '.tar',
    '.cbt',
    '.tgz',
    '.tar.gz',
    '.iso',
    '.udf',
    '.rar',
    '.cbr',
    '.dmg',
  ].any(lower.endsWith);
}

/// Filename routing must not remove the viewer's content-sniffing behavior.
/// This is only a cheap hint; the chosen reader still validates all metadata.
bool matchesStreamedArchiveViewerSignature(String name, List<int> prefix) {
  bool startsWith(List<int> signature) {
    if (prefix.length < signature.length) return false;
    for (var index = 0; index < signature.length; index++) {
      if (prefix[index] != signature[index]) return false;
    }
    return true;
  }

  final lower = name.toLowerCase();
  if (lower.endsWith('.zip') || lower.endsWith('.cbz')) {
    return prefix.length >= 4 && startsWith(const [0x50, 0x4b]);
  }
  if (lower.endsWith('.7z') || lower.endsWith('.cb7')) {
    return startsWith(const [0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c]);
  }
  if (lower.endsWith('.tgz') || lower.endsWith('.tar.gz')) {
    return startsWith(const [0x1f, 0x8b]);
  }
  if (lower.endsWith('.rar') || lower.endsWith('.cbr')) {
    return startsWith(const [0x52, 0x61, 0x72, 0x21, 0x1a, 0x07]);
  }
  // ISO descriptors begin at sector 16 and the UDIF signature is a trailer.
  // Their readers validate the actual signature before accepting the source.
  if (lower.endsWith('.iso') ||
      lower.endsWith('.udf') ||
      lower.endsWith('.dmg'))
    return true;
  // Historic TARs have several valid header variants. Let the reader decide;
  // an explicit decoded-format mismatch can still use the sniffing fallback.
  return lower.endsWith('.tar') || lower.endsWith('.cbt');
}

/// Writable-profile restrictions and explicit format mismatches may still be
/// browsed. Corruption, size limits, source revocation and cancellation cannot
/// be turned into a second decode attempt by this fallback.
bool useBoundedArchiveViewerFallback(Object error) =>
    error is ArchiveStreamingUnsupported ||
    error is ArchiveViewException &&
        (error.message == 'The archive does not match its filename.' ||
            error.message == 'The gzip payload is not a TAR archive.');
