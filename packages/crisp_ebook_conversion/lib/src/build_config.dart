import 'package:code_assets/code_assets.dart';

/// Native targets supported by the bundled Kindling source build. A mapping is
/// not a claim that a target has passed a runtime smoke test.
class KindlingBuildTarget {
  const KindlingBuildTarget(this.triple, this.library);
  final String triple;
  final String library;

  /// Preserve the exact minimum Apple OS version selected by Flutter. The
  /// deprecated code-assets targetVersion contains only the major component.
  static String appleDeploymentTarget(AppleVersion version) =>
      '${version.major}.${version.minor}.${version.patch}';

  static KindlingBuildTarget? forPlatform(
    String os,
    String architecture, {
    bool iosSimulator = false,
  }) {
    const dylib = 'libcrisp_kindling_bridge.dylib';
    const so = 'libcrisp_kindling_bridge.so';
    const dll = 'crisp_kindling_bridge.dll';
    return switch ((os.toLowerCase(), architecture, iosSimulator)) {
      ('linux', 'x64', _) => const KindlingBuildTarget(
        'x86_64-unknown-linux-gnu',
        so,
      ),
      ('linux', 'arm64', _) => const KindlingBuildTarget(
        'aarch64-unknown-linux-gnu',
        so,
      ),
      ('macos', 'x64', _) => const KindlingBuildTarget(
        'x86_64-apple-darwin',
        dylib,
      ),
      ('macos', 'arm64', _) => const KindlingBuildTarget(
        'aarch64-apple-darwin',
        dylib,
      ),
      ('windows', 'x64', _) => const KindlingBuildTarget(
        'x86_64-pc-windows-msvc',
        dll,
      ),
      ('windows', 'arm64', _) => const KindlingBuildTarget(
        'aarch64-pc-windows-msvc',
        dll,
      ),
      ('ios', 'arm64', false) => const KindlingBuildTarget(
        'aarch64-apple-ios',
        dylib,
      ),
      ('ios', 'arm64', true) => const KindlingBuildTarget(
        'aarch64-apple-ios-sim',
        dylib,
      ),
      ('ios', 'x64', true) => const KindlingBuildTarget(
        'x86_64-apple-ios',
        dylib,
      ),
      ('android', 'arm64', _) => const KindlingBuildTarget(
        'aarch64-linux-android',
        so,
      ),
      ('android', 'x64', _) => const KindlingBuildTarget(
        'x86_64-linux-android',
        so,
      ),
      ('android', 'arm', _) => const KindlingBuildTarget(
        'armv7-linux-androideabi',
        so,
      ),
      _ => null,
    };
  }
}
