import 'package:code_assets/code_assets.dart';

import '../hook/build.dart' as build_hook;

/// Exercise the actual hook with validated cross-target input. These checks
/// require neither Xcode nor an Android NDK on the host running the tests.
Future<void> verifyIosAssets() => _verifyNoAssets(OS.iOS);

Future<void> verifyAndroidAssets() => _verifyNoAssets(OS.android);

Future<void> _verifyNoAssets(OS platform) => testCodeBuildHook(
  mainMethod: build_hook.main,
  targetOS: platform,
  targetArchitecture: Architecture.arm64,
  check: (input, output) {
    if (output.assets.encodedAssets.isNotEmpty) {
      throw StateError('$platform must not bundle a local PTY native asset');
    }
  },
);

Future<void> main() async {
  await verifyIosAssets();
  await verifyAndroidAssets();
}
