import 'backend.dart';
import 'bundle.dart';

/// Import-safe on web. No native library loading or remote fallback exists.
final class SpacyNativeBackendFactory implements SpacyBackendFactory {
  SpacyNativeBackendFactory({
    required this.bundleDirectory,
    required this.libraryPath,
    required this.librarySha256,
  });
  final String bundleDirectory;
  final String libraryPath;
  final String librarySha256;
  @override
  Future<SpacyBackend> open(SpacyBundle bundle) async =>
      throw const SpacyUnavailableException(
        'Native spaCy is unavailable on this platform.',
      );
}
