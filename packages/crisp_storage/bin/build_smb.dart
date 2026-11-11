// Build the optional host library. No Flutter installation is required.
import 'dart:io';

Future<void> main(List<String> arguments) async {
  if (arguments.isNotEmpty) {
    stderr.writeln('Usage: dart run crisp_storage:build_smb');
    exitCode = 64;
    return;
  }
  final root = File.fromUri(Platform.script).parent.parent;
  final process = await Process.start('cargo', [
    'build',
    '--manifest-path',
    '${root.path}/rust/Cargo.toml',
    '--release',
    '--locked',
  ], mode: ProcessStartMode.inheritStdio);
  exitCode = await process.exitCode;
  if (exitCode != 0) return;
  final name = Platform.isWindows
      ? 'crisp_smb_bridge.dll'
      : Platform.isMacOS
      ? 'libcrisp_smb_bridge.dylib'
      : 'libcrisp_smb_bridge.so';
  stdout.writeln('CRISP_SMB_LIBRARY=${root.path}/rust/target/release/$name');
}
