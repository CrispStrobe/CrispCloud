import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/standalone_fuse_helper.dart';

void main() {
  test('standalone fixture preserves the signed sandbox helper input', () async {
    final directory = await Directory.systemTemp.createTemp('cc_fuse_fixture_');
    addTearDown(() => directory.delete(recursive: true));
    final root = Directory.current.path;
    final build = await Process.run(
      '/bin/sh',
      ['$root/macos/build_fuse_bridge.sh'],
      environment: {
        'SRCROOT': '$root/macos',
        'CRISP_BUILD_PROFILE': 'github',
        'DART_DEFINES': 'Q1JJU1BfRU5BQkxFX0ZVU0U9dHJ1ZQ==,Q1JJU1BfRElTVFJJQlVUSU9OPWdpdGh1Yg==',
        'TARGET_BUILD_DIR': '${directory.path}/build',
        'UNLOCALIZED_RESOURCES_FOLDER_PATH': 'Resources',
        'EXPANDED_CODE_SIGN_IDENTITY': '-',
      },
    );
    expect(build.exitCode, 0, reason: '${build.stderr}');
    final original = File(
      '${directory.path}/build/Resources/crispcloud_fuse_bridge',
    );
    // The supported build is direct-distribution. Exercise the legacy
    // inherit-entitled fixture separately without weakening the build policy.
    final signing = await Process.run('/usr/bin/codesign', [
      '--force',
      '--sign',
      '-',
      '--entitlements',
      '$root/macos/Runner/FuseBridge.entitlements',
      original.path,
    ]);
    expect(signing.exitCode, 0, reason: '${signing.stderr}');
    final originalBytes = await original.readAsBytes();
    final standalone = await prepareStandaloneFuseHelper(
      original.path,
      directory,
    );
    expect(standalone, isNot(original.path));
    expect(await original.readAsBytes(), originalBytes);
    final originalSignature = await Process.run('/usr/bin/codesign', [
      '-d',
      '--entitlements',
      ':-',
      original.path,
    ]);
    expect(originalSignature.exitCode, 0);
    expect(
      '${originalSignature.stdout}',
      contains('com.apple.security.inherit'),
    );
    final standaloneSignature = await Process.run('/usr/bin/codesign', [
      '-d',
      '--entitlements',
      ':-',
      standalone,
    ]);
    expect(standaloneSignature.exitCode, 0);
    expect(
      '${standaloneSignature.stdout}',
      isNot(contains('com.apple.security.inherit')),
    );
    // No arguments reaches only the usage check, before dlopen, IPC, or mounting.
    // A sandbox-inherit helper would instead trap before main from this runner.
    final usage = await Process.run(standalone, []);
    expect(usage.exitCode, 2);
    expect('${usage.stderr}', contains('usage:'));
    // Reusing an already standalone input must not copy or re-sign it again.
    expect(
      await prepareStandaloneFuseHelper(standalone, directory),
      standalone,
    );
  }, skip: !Platform.isMacOS);
}
