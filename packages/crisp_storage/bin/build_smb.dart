// Build the optional host library. No Flutter installation is required.
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  if (arguments.isNotEmpty) {
    stderr.writeln('Usage: dart run crisp_storage:build_smb');
    exitCode = 64;
    return;
  }
  final root = File.fromUri(Platform.script).parent.parent;
  final manifest = File(
    '${root.path}/rust/Cargo.toml',
  ).resolveSymbolicLinksSync();
  final process = await Process.start('cargo', [
    'build',
    '--manifest-path',
    manifest,
    '--release',
    '--locked',
    '--message-format=json-render-diagnostics',
  ]);
  await process.stdin.close();
  final libraries = <String>{};
  await Future.wait<void>([
    // Cargo renders compiler diagnostics normally while stdout carries artifact
    // metadata. Drain both streams concurrently so a verbose build cannot block.
    process.stderr.forEach(stderr.add),
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach((line) {
          Object? decoded;
          try {
            decoded = jsonDecode(line);
          } on FormatException {
            stdout.writeln(line);
            return;
          }
          if (decoded is! Map<String, dynamic>) {
            stdout.writeln(line);
            return;
          }
          switch (decoded['reason']) {
            case 'compiler-artifact':
              final target = decoded['target'];
              final filenames = decoded['filenames'];
              if (decoded['manifest_path'] == manifest &&
                  target is Map<String, dynamic> &&
                  target['name'] == 'crisp_smb_bridge' &&
                  target['crate_types'] is List &&
                  (target['crate_types'] as List).contains('cdylib') &&
                  filenames is List) {
                libraries.addAll(
                  filenames.whereType<String>().where(
                    (path) => RegExp(r'\.(so|dylib|dll)$').hasMatch(path),
                  ),
                );
              }
            case 'build-script-executed':
            case 'build-finished':
              break;
            default:
              // Preserve any additional Cargo diagnostics or tool output.
              stdout.writeln(line);
          }
        }),
  ]);
  exitCode = await process.exitCode;
  if (exitCode != 0) return;
  if (libraries.length != 1 || !File(libraries.single).existsSync()) {
    stderr.writeln(
      'Cargo did not report one existing SMB bridge library. '
      'Check the configured build target and artifact output.',
    );
    exitCode = 1;
    return;
  }
  stdout.writeln('CRISP_SMB_LIBRARY=${libraries.single}');
}
