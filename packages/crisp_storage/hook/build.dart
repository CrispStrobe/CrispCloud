// Build hook: optionally compiles the experimental Rust SMB bridge with Cargo
// and bundles it as the code asset `package:crisp_storage/crisp_smb_bridge`.
//
// Off by default, so libsmb2-only apps need no Rust toolchain. Enable it in
// the APP's pubspec:
//
//   hooks:
//     user_defines:
//       crisp_storage:
//         rust_smb: true
//         # optional: a prebuilt library used for every target instead of Cargo
//         # rust_smb_library: path/to/libcrisp_smb_bridge.dylib
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

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final enabled = input.userDefines['rust_smb'];
    if (enabled != true && enabled != 'true') return;
    final code = input.config.code;
    final target = RustTarget.of(
      os: code.targetOS.name,
      architecture: code.targetArchitecture.name,
      iosSimulator:
          code.targetOS == OS.iOS &&
          code.iOS.targetSdk == IOSSdk.iPhoneSimulator,
    );
    if (target == null) {
      stderr.writeln(
        'crisp_storage: Rust SMB is not built for ${code.targetOS} '
        '${code.targetArchitecture}; SmbBackend.auto will use libsmb2.',
      );
      return;
    }
    final out = File.fromUri(input.outputDirectory.resolve(target.fileName));

    final prebuilt = input.userDefines.path('rust_smb_library');
    if (prebuilt != null) {
      final file = File.fromUri(prebuilt);
      if (!file.existsSync()) {
        throw StateError(
          'crisp_storage: rust_smb_library ${file.path} is missing',
        );
      }
      output.dependencies.add(prebuilt);
      await file.copy(out.path);
    } else {
      final root = input.packageRoot;
      final manifest = root.resolve('rust/Cargo.toml');
      for (final dir in ['rust/', 'native/crisp_smb/']) {
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
        name: 'crisp_smb_bridge',
        linkMode: DynamicLoadingBundled(),
        file: out.uri,
      ),
    );
  });
}
