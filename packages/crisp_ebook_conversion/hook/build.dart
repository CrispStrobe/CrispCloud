import 'dart:io';
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:path/path.dart' as p;
import 'package:crisp_ebook_conversion/src/build_config.dart';

void main(List<String> arguments) async {
  await build(arguments, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    // A distribution may explicitly omit conversion; runtime capability then
    // reports unavailable. Default builds compile and bundle the engine.
    if (input.userDefines['enabled'] == false ||
        input.userDefines['enabled'] == 'false') {
      return;
    }
    final code = input.config.code;
    final simulator =
        code.targetOS == OS.iOS && code.iOS.targetSdk == IOSSdk.iPhoneSimulator;
    final target = KindlingBuildTarget.forPlatform(
      code.targetOS.name,
      code.targetArchitecture.name,
      iosSimulator: simulator,
    );
    if (target == null) return;
    final destination = File.fromUri(
      input.outputDirectory.resolve(target.library),
    );
    final prebuilt = input.userDefines.path('kindling_library');
    if (prebuilt != null) {
      output.dependencies.add(prebuilt);
      await File.fromUri(prebuilt).copy(destination.path);
    } else {
      final root = Directory.fromUri(input.packageRoot.resolve('native/'));
      for (final file
          in root
              .listSync(recursive: true, followLinks: false)
              .whereType<File>()) {
        if (p.split(file.path).contains('target')) continue;
        // include_bytes! inputs (for example Kindling's ordt_greek.bin)
        // affect the native output just as much as Rust sources do.
        output.dependencies.add(file.uri);
      }
      final cargoDir = Directory.fromUri(
        input.outputDirectoryShared.resolve('cargo/'),
      );
      final environment = <String, String>{
        'CARGO_TARGET_DIR': cargoDir.path,
        if (input.userDefines.path('cargo_home') case final Uri directory)
          'CARGO_HOME': directory.toFilePath(),
        if (input.userDefines.path('rustup_home') case final Uri directory)
          'RUSTUP_HOME': directory.toFilePath(),
        if (code.targetOS == OS.iOS)
          'IPHONEOS_DEPLOYMENT_TARGET':
              KindlingBuildTarget.appleDeploymentTarget(
                code.iOS.deploymentVersion,
              ),
        if (code.targetOS == OS.macOS)
          'MACOSX_DEPLOYMENT_TARGET': KindlingBuildTarget.appleDeploymentTarget(
            code.macOS.deploymentVersion,
          ),
      };
      if (code.targetOS == OS.iOS || code.targetOS == OS.macOS) {
        final sdk = code.targetOS == OS.macOS
            ? 'macosx'
            : (simulator ? 'iphonesimulator' : 'iphoneos');
        final result = await Process.run('xcrun', [
          '--sdk',
          sdk,
          '--show-sdk-path',
        ]);
        if (result.exitCode != 0) {
          throw StateError('Cannot locate Apple SDK for Kindle conversion.');
        }
        environment['SDKROOT'] = (result.stdout as String).trim();
      }
      if (code.targetOS == OS.android) {
        environment.addAll(_androidEnvironment(target));
      }
      final cargo =
          input.userDefines.path('cargo')?.toFilePath() ?? _findCargo();
      final result = await Process.run(cargo, [
        'build',
        '--release',
        '--locked',
        '--lib',
        '--manifest-path',
        p.join(root.path, 'Cargo.toml'),
        '--target',
        target.triple,
      ], environment: environment);
      if (result.exitCode != 0) {
        throw StateError(
          'Pinned Kindling native build failed for ${target.triple}. '
          'Install Rust 1.88+ and that rustup target; Android also needs its NDK. '
          'Use the documented prebuilt library setting for distribution builds.\n'
          '${result.stdout}\n${result.stderr}',
        );
      }
      await File(
        p.join(cargoDir.path, target.triple, 'release', target.library),
      ).copy(destination.path);
    }
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'kindling_bridge',
        linkMode: DynamicLoadingBundled(),
        file: destination.uri,
      ),
    );
  });
}

String _findCargo() {
  final env = Platform.environment;
  if (env['CARGO'] case final String explicit) {
    if (File(explicit).existsSync()) return explicit;
  }
  final executable = Platform.isWindows ? 'cargo.exe' : 'cargo';
  final candidates = <String>[
    for (final dir in (env['PATH'] ?? '').split(Platform.isWindows ? ';' : ':'))
      if (dir.isNotEmpty) p.join(dir, executable),
    if (env['CARGO_HOME'] case final String dir) p.join(dir, 'bin', executable),
    if (env['HOME'] ?? env['USERPROFILE'] case final String dir)
      p.join(dir, '.cargo', 'bin', executable),
  ];
  return candidates.firstWhere(
    (path) => File(path).existsSync(),
    orElse: () => executable,
  );
}

Map<String, String> _androidEnvironment(KindlingBuildTarget target) {
  final env = Platform.environment;
  var ndk = env['ANDROID_NDK_HOME'] ?? env['ANDROID_NDK_ROOT'];
  if (ndk == null) {
    final sdk = env['ANDROID_HOME'] ?? env['ANDROID_SDK_ROOT'];
    if (sdk != null && Directory(p.join(sdk, 'ndk')).existsSync()) {
      final versions =
          Directory(
              p.join(sdk, 'ndk'),
            ).listSync().whereType<Directory>().toList()
            ..sort((a, b) => b.path.compareTo(a.path));
      if (versions.isNotEmpty) ndk = versions.first.path;
    }
  }
  if (ndk == null) {
    throw StateError(
      'ANDROID_NDK_HOME is required for the Kindling Android build.',
    );
  }
  final host = Platform.isMacOS
      ? 'darwin-x86_64'
      : (Platform.isWindows ? 'windows-x86_64' : 'linux-x86_64');
  final bin = p.join(ndk, 'toolchains', 'llvm', 'prebuilt', host, 'bin');
  final clangTarget = target.triple == 'armv7-linux-androideabi'
      ? 'armv7a-linux-androideabi'
      : target.triple;
  final clang = p.join(
    bin,
    '${clangTarget}21-clang${Platform.isWindows ? '.cmd' : ''}',
  );
  if (!File(clang).existsSync()) {
    throw StateError('Android NDK compiler is missing: $clang');
  }
  return {
    'CARGO_TARGET_${target.triple.toUpperCase().replaceAll('-', '_')}_LINKER':
        clang,
    'CC_${target.triple.replaceAll('-', '_')}': clang,
    'AR_${target.triple.replaceAll('-', '_')}': p.join(
      bin,
      'llvm-ar${Platform.isWindows ? '.exe' : ''}',
    ),
    // Keep generated shared objects compatible with Android 16 KB pages.
    'CARGO_ENCODED_RUSTFLAGS': '-Clink-arg=-Wl,-z,max-page-size=16384',
  };
}
