import 'dart:io';
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final code = input.config.code;
    final key = '${code.targetOS.name}/${code.targetArchitecture.name}';
    final simulator =
        code.targetOS == OS.iOS && code.iOS.targetSdk == IOSSdk.iPhoneSimulator;
    final triple = switch (key) {
      'macos/arm64' => 'aarch64-apple-darwin',
      'macos/x64' => 'x86_64-apple-darwin',
      'linux/arm64' => 'aarch64-unknown-linux-gnu',
      'linux/x64' => 'x86_64-unknown-linux-gnu',
      'windows/arm64' => 'aarch64-pc-windows-msvc',
      'windows/x64' => 'x86_64-pc-windows-msvc',
      'ios/arm64' => simulator ? 'aarch64-apple-ios-sim' : 'aarch64-apple-ios',
      'ios/x64' => 'x86_64-apple-ios',
      'android/arm64' => 'aarch64-linux-android',
      'android/arm' => 'armv7-linux-androideabi',
      'android/x64' => 'x86_64-linux-android',
      'android/ia32' => 'i686-linux-android',
      _ => null,
    };
    if (triple == null) {
      return; // Optional desktop engine; preserve other app builds.
    }
    const stem = 'crisp_catalog_bridge';
    final filename = code.targetOS == OS.windows
        ? '$stem.dll'
        : code.targetOS == OS.macOS || code.targetOS == OS.iOS
        ? 'lib$stem.dylib'
        : 'lib$stem.so';
    final native = Directory.fromUri(input.packageRoot.resolve('native/'));
    for (final file in native.listSync(recursive: true).whereType<File>()) {
      if (file.path.contains('/target/')) continue;
      output.dependencies.add(file.uri);
    }
    final target = Directory.fromUri(
      input.outputDirectoryShared.resolve('cargo/'),
    );
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    final cargoHome =
        Platform.environment['CARGO_HOME'] ??
        (home == null ? null : '$home/.cargo');
    final candidate = cargoHome == null
        ? null
        : '$cargoHome/bin/cargo${Platform.isWindows ? '.exe' : ''}';
    final cargo =
        Platform.environment['CARGO'] ??
        (candidate != null && File(candidate).existsSync()
            ? candidate
            : 'cargo');
    final env = <String, String>{'CARGO_TARGET_DIR': target.path};
    if (code.targetOS == OS.macOS || code.targetOS == OS.iOS) {
      final sdk = await Process.run('xcrun', [
        '--sdk',
        code.targetOS == OS.macOS
            ? 'macosx'
            : simulator
            ? 'iphonesimulator'
            : 'iphoneos',
        '--show-sdk-path',
      ]);
      if (sdk.exitCode != 0) {
        throw StateError('Cannot locate macOS SDK: ${sdk.stderr}');
      }
      env['SDKROOT'] = (sdk.stdout as String).trim();
      if (code.targetOS == OS.macOS) {
        // ignore: deprecated_member_use
        env['MACOSX_DEPLOYMENT_TARGET'] = '${code.macOS.targetVersion}.0';
      } else {
        // ignore: deprecated_member_use
        env['IPHONEOS_DEPLOYMENT_TARGET'] = '${code.iOS.targetVersion}.0';
      }
    }
    if (code.targetOS == OS.android) {
      var ndk =
          Platform.environment['ANDROID_NDK_HOME'] ??
          Platform.environment['ANDROID_NDK_ROOT'];
      if (ndk == null) {
        final sdk =
            Platform.environment['ANDROID_HOME'] ??
            Platform.environment['ANDROID_SDK_ROOT'];
        if (sdk != null) {
          final versions = Directory('$sdk/ndk').existsSync()
              ? Directory('$sdk/ndk').listSync().whereType<Directory>().toList()
              : <Directory>[];
          versions.sort((a, b) => b.path.compareTo(a.path));
          if (versions.isNotEmpty) ndk = versions.first.path;
        }
      }
      if (ndk == null) {
        throw StateError(
          'Set ANDROID_NDK_HOME for the native catalogue engine.',
        );
      }
      final host = Platform.isMacOS
          ? 'darwin-x86_64'
          : Platform.isWindows
          ? 'windows-x86_64'
          : 'linux-x86_64';
      final bin = '$ndk/toolchains/llvm/prebuilt/$host/bin';
      final api = code.android.targetNdkApi;
      if (api < 21) {
        throw UnsupportedError(
          'The catalogue engine requires Android API 21 or newer.',
        );
      }
      final clangTarget = triple == 'armv7-linux-androideabi'
          ? 'armv7a-linux-androideabi'
          : triple;
      final clang =
          '$bin/$clangTarget$api-clang${Platform.isWindows ? '.cmd' : ''}';
      if (!File(clang).existsSync()) {
        throw StateError('Android NDK compiler is missing: $clang');
      }
      env['CARGO_TARGET_${triple.toUpperCase().replaceAll('-', '_')}_LINKER'] =
          clang;
      env['CC_${triple.replaceAll('-', '_')}'] = clang;
      env['AR_${triple.replaceAll('-', '_')}'] =
          '$bin/llvm-ar${Platform.isWindows ? '.exe' : ''}';
      env['CARGO_ENCODED_RUSTFLAGS'] = '-Clink-arg=-Wl,-z,max-page-size=16384';
    }
    final result = await Process.run(cargo, [
      'build',
      '--release',
      '--locked',
      '--manifest-path',
      '${native.path}Cargo.toml',
      '--target',
      triple,
    ], environment: env);
    if (result.exitCode != 0) {
      throw StateError(
        'Catalogue Cargo build failed for $triple.\n${result.stdout}\n${result.stderr}',
      );
    }
    final library = File('${target.path}$triple/release/$filename');
    final bundled = File.fromUri(input.outputDirectory.resolve(filename));
    await library.copy(bundled.path);
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: stem,
        linkMode: DynamicLoadingBundled(),
        file: bundled.uri,
      ),
    );
  });
}
