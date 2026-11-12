// Build hook: optionally compiles the Rust bridges with Cargo and bundles
// them as code assets:
//
// - `rust_smb`   -> `package:crisp_storage/crisp_smb_bridge`   (rust/)
// - `rust_cloud` -> `package:crisp_storage/crisp_cloud_bridge` (rust_cloud/,
//                   Filen and Internxt)
//
// Both are off by default, so apps using only libsmb2 and the Dart cloud
// clients need no Rust toolchain. Enable them in the APP's pubspec:
//
//   hooks:
//     user_defines:
//       crisp_storage:
//         rust_smb: true
//         rust_cloud: true
//         # optional prebuilt libraries used for every target instead of Cargo
//         # rust_smb_library: path/to/libcrisp_smb_bridge.dylib
//         # rust_cloud_library: path/to/libcrisp_cloud_bridge.dylib
//
// Supported Cargo targets: iOS (device + simulator), macOS, Linux and Windows.
// Other targets (Android for now) bundle nothing; `SmbBackend.auto` then falls
// back to libsmb2 and strict `rust` reports the library as unavailable.
// Required rustup targets: aarch64-apple-ios, aarch64-apple-ios-sim,
// x86_64-apple-ios, aarch64-apple-darwin, x86_64-apple-darwin (as built).

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

import 'package:crisp_storage/src/rust_library.dart';

class _Bridge {
  const _Bridge(this.define, this.stem, this.manifest, this.sources);

  /// User define that enables the bridge; `<define>_library` names a
  /// prebuilt library.
  final String define;
  final String stem;
  final String manifest;
  final List<String> sources;
}

const _bridges = <_Bridge>[
  _Bridge('rust_smb', smbBridgeStem, 'rust/Cargo.toml', [
    'rust/',
    'native/crisp_smb/',
  ]),
  _Bridge('rust_cloud', cloudBridgeStem, 'rust_cloud/Cargo.toml', [
    'rust_cloud/',
    'native/crisp_filen/',
    'native/crisp_internxt/',
  ]),
];

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    for (final bridge in _bridges) {
      final enabled = input.userDefines[bridge.define];
      if (enabled != true && enabled != 'true') continue;
      await _buildBridge(input, output, bridge);
    }
  });
}

Future<void> _buildBridge(
  BuildInput input,
  BuildOutputBuilder output,
  _Bridge bridge,
) async {
    final code = input.config.code;
    final target = RustTarget.of(
      os: code.targetOS.name,
      architecture: code.targetArchitecture.name,
      iosSimulator:
          code.targetOS == OS.iOS &&
          code.iOS.targetSdk == IOSSdk.iPhoneSimulator,
      stem: bridge.stem,
    );
    if (target == null) {
      stderr.writeln(
        'crisp_storage: ${bridge.stem} is not built for ${code.targetOS} '
        '${code.targetArchitecture}; the Dart/libsmb2 engines remain available.',
      );
      return;
    }
    final out = File.fromUri(input.outputDirectory.resolve(target.fileName));

    final prebuilt = input.userDefines.path('${bridge.define}_library');
    if (prebuilt != null) {
      final file = File.fromUri(prebuilt);
      if (!file.existsSync()) {
        throw StateError(
          'crisp_storage: ${bridge.define}_library ${file.path} is missing',
        );
      }
      output.dependencies.add(prebuilt);
      await file.copy(out.path);
    } else {
      final root = input.packageRoot;
      final manifest = root.resolve(bridge.manifest);
      for (final dir in bridge.sources) {
        for (final entity in Directory.fromUri(
          root.resolve(dir),
        ).listSync(recursive: true).whereType<File>()) {
          final p = entity.path;
          if (p.contains('/target/')) continue;
          if (p.endsWith('.rs') ||
              p.endsWith('Cargo.toml') ||
              p.endsWith('Cargo.lock')) {
            output.dependencies.add(entity.uri);
          }
        }
      }
      final targetDir = Directory.fromUri(
        input.outputDirectoryShared.resolve('cargo/'),
      );
      final environment = <String, String>{
        'CARGO_TARGET_DIR': targetDir.path,
        if (code.targetOS == OS.iOS)
          // ignore: deprecated_member_use
          'IPHONEOS_DEPLOYMENT_TARGET': '${code.iOS.targetVersion}.0',
        if (code.targetOS == OS.macOS)
          // ignore: deprecated_member_use
          'MACOSX_DEPLOYMENT_TARGET': '${code.macOS.targetVersion}.0',
      };
      // Hooks run with a filtered environment: give C build scripts in the
      // Cargo graph (e.g. oslog) the SDK Xcode would otherwise provide.
      final sdk = appleSdkName(
        os: code.targetOS.name,
        iosSimulator:
            code.targetOS == OS.iOS &&
            code.iOS.targetSdk == IOSSdk.iPhoneSimulator,
      );
      if (sdk != null) {
        final xcrun = await Process.run('xcrun', [
          '--sdk',
          sdk,
          '--show-sdk-path',
        ]);
        if (xcrun.exitCode == 0) {
          environment['SDKROOT'] = (xcrun.stdout as String).trim();
        }
      }
      final cargo = findCargo(Platform.environment);
      final result = await Process.run(cargo, [
        'build',
        '--release',
        '--locked',
        '--manifest-path',
        File.fromUri(manifest).path,
        '--target',
        target.triple,
      ], environment: environment);
      if (result.exitCode != 0) {
        throw ProcessException(
          cargo,
          ['build', '--target', target.triple],
          'crisp_storage: cargo failed for ${target.triple}. Install the '
          'target with `rustup target add ${target.triple}`.\n'
          '${result.stdout}\n${result.stderr}',
          result.exitCode,
        );
      }
      final built = File(
        '${targetDir.path}${target.triple}/release/${target.cargoOutput}',
      );
      await built.copy(out.path);
    }

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: bridge.stem,
        linkMode: DynamicLoadingBundled(),
        file: out.uri,
      ),
    );
}
