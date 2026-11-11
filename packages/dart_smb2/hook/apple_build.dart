// Crisp patch to the BSD-3-Clause dart_smb2 hook. See ../CRISP_PATCHES.md.
import 'dart:io';
import 'package:hooks/hooks.dart';

/// Rebuild the pinned r10 source with space for Dart/Flutter install-name edits.
/// Every input is tracked. Builds use their own output directory and never write
/// to the package cache or share partially compiled binaries between targets.
Future<File> buildApple(
  BuildInput input,
  BuildOutputBuilder output,
  String asset,
) async {
  if (!Platform.isMacOS) {
    throw UnsupportedError('Apple SMB assets require macOS with Xcode.');
  }
  final platform = switch (asset) {
    'libsmb2_macos.xcframework.zip' => 'macos',
    'libsmb2_ios.xcframework.zip' => 'ios',
    _ => throw ArgumentError('Unsupported Apple SMB asset'),
  };
  final source = Directory.fromUri(input.packageRoot.resolve('native/'));
  final work = Directory.fromUri(
    input.outputDirectory.resolve('apple-source/'),
  );
  if (work.existsSync()) await work.delete(recursive: true);
  await work.create(recursive: true);
  await for (final entity in source.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    output.dependencies.add(entity.uri);
    final relative = entity.path.substring(source.path.length);
    final destination = File('${work.path}/$relative');
    await destination.parent.create(recursive: true);
    await entity.copy(destination.path);
  }
  // The only supported override is the documented local-library hook setting.
  // Do not let unrelated build variables change the pinned source or recipe.
  final environment = Map<String, String>.from(Platform.environment)
    ..removeWhere(
      (key, _) =>
          key.startsWith('LIBSMB2_') ||
          const {
            'BUILD_DIR',
            'DEPLOYMENT_TARGET',
            'PATCH_PLATFORM',
            'FORCE_DOWNLOAD',
            'KEEP_BUILD',
            'JOBS',
            'BASH_ENV',
            'ENV',
          }.contains(key),
    );
  final process = await Process.start(
    '/bin/bash',
    ['scripts/build_libsmb2_$platform.sh'],
    workingDirectory: work.path,
    environment: environment,
    includeParentEnvironment: false,
  );
  // Native compiler output must not corrupt the hook's structured stdout.
  final stdoutDone = process.stdout.forEach(stderr.add);
  final stderrDone = process.stderr.forEach(stderr.add);
  // Drain both pipes concurrently and preserve compiler diagnostics.
  final exitCode = await process.exitCode;
  await stdoutDone;
  await stderrDone;
  if (exitCode != 0) {
    throw ProcessException(
      '/bin/bash',
      ['scripts/build_libsmb2_$platform.sh'],
      'Pinned Apple SMB source build failed; check Xcode and the build log.',
      exitCode,
    );
  }
  final result = File('${work.path}/release_builds/$asset');
  if (!await result.exists()) {
    throw StateError('Apple SMB build produced no asset.');
  }
  return result;
}
