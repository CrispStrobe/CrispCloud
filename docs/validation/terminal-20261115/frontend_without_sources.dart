import 'dart:io';

// Use Flutter's supported custom frontend starter to omit embedded source text
// from test kernels. Compilation, assertions, and executed code stay unchanged.
Future<void> main(List<String> arguments) async {
  final compiler = await Process.start(
    '/workspace/scratch/32cc0ca57b2f/.terminal-tools/flutter/bin/cache/dart-sdk/bin/dartaotruntime',
    [
      '/workspace/scratch/32cc0ca57b2f/.terminal-tools/flutter/bin/cache/artifacts/engine/linux-x64/frontend_server_aot.dart.snapshot',
      ...arguments,
      '--no-embed-source-text',
    ],
    mode: ProcessStartMode.inheritStdio,
  );
  exit(await compiler.exitCode);
}
