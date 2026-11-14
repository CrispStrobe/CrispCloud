import 'dart:io';
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final code = input.config.code;
    final key = '${code.targetOS.name}/${code.targetArchitecture.name}';
    final triple = switch (key) {
      'macos/arm64' => 'aarch64-apple-darwin',
      'macos/x64' => 'x86_64-apple-darwin',
      'linux/arm64' => 'aarch64-unknown-linux-gnu',
      'linux/x64' => 'x86_64-unknown-linux-gnu',
      'windows/arm64' => 'aarch64-pc-windows-msvc',
      'windows/x64' => 'x86_64-pc-windows-msvc',
      _ => throw UnsupportedError(
        'crisp_catalog currently supports desktop native targets: $key',
      ),
    };
    const stem = 'crisp_catalog_bridge';
    final filename = code.targetOS == OS.windows
        ? '$stem.dll'
        : code.targetOS == OS.macOS
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
    if (code.targetOS == OS.macOS) {
      final sdk = await Process.run('xcrun', [
        '--sdk',
        'macosx',
        '--show-sdk-path',
      ]);
      if (sdk.exitCode != 0) {
        throw StateError('Cannot locate macOS SDK: ${sdk.stderr}');
      }
      env['SDKROOT'] = (sdk.stdout as String).trim();
      // ignore: deprecated_member_use
      env['MACOSX_DEPLOYMENT_TARGET'] = '${code.macOS.targetVersion}.0';
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
