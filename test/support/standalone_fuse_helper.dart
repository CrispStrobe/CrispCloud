import 'dart:io';

/// Prepare only the standalone test executable. The packaged helper retains its
/// sandbox-inheritance signature and must be tested from a sandboxed app host.
Future<String> prepareStandaloneFuseHelper(
  String sourcePath,
  Directory temporaryDirectory,
) async {
  final signature = await Process.run('/usr/bin/codesign', [
    '-d',
    '--entitlements',
    ':-',
    sourcePath,
  ]);
  if (signature.exitCode != 0) {
    if ('${signature.stderr}'.contains('code object is not signed at all')) {
      return sourcePath;
    }
    throw StateError('Could not inspect the FUSE fixture helper signature');
  }
  if (!RegExp(
    r'<key>com\.apple\.security\.inherit</key>\s*<true\s*/>',
  ).hasMatch('${signature.stdout}')) {
    return sourcePath;
  }

  // A helper with inherit=true traps before main when its parent is the
  // unsandboxed Flutter test runner. Re-sign a disposable copy, never the input.
  final directory = await temporaryDirectory.createTemp('standalone-helper-');
  final source = File(sourcePath);
  final name = source.uri.pathSegments.last;
  final copy = await source.copy('${directory.path}/$name');
  final entitlements = File('${directory.path}/empty.entitlements');
  await entitlements.writeAsString(
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
    '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    '<plist version="1.0"><dict/></plist>',
  );
  final signing = await Process.run('/usr/bin/codesign', [
    '--force',
    '--sign',
    '-',
    '--entitlements',
    entitlements.path,
    copy.path,
  ]);
  if (signing.exitCode != 0) {
    throw StateError('Could not sign the disposable standalone FUSE helper');
  }
  final verification = await Process.run('/usr/bin/codesign', [
    '--verify',
    '--all-architectures',
    '--strict',
    copy.path,
  ]);
  if (verification.exitCode != 0) {
    throw StateError('Disposable standalone FUSE helper signature is invalid');
  }
  return copy.path;
}
