import 'dart:io';

import 'package:crisp_cloud/services/fuse_mount_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('restricted mounts fail before credentials, filesystem probes or persistence', () async {
    final service = FuseMountService();
    final path = '${Directory.systemTemp.path}/crisp-opt-in-probe-$pid';
    expect(await Directory(path).exists(), isFalse);
    await expectLater(
      service.mount(
        client: null,
        remotePath: '/',
        mountPoint: path,
        macBackend: MacFuseBackend.fuseT,
        fuseTNonCommercialAcknowledged: true,
      ),
      // Opted-in builds reach normal client validation. Default builds refuse
      // the restricted integration before consulting credentials or the OS.
      nativeMacFuseEnabled ? throwsArgumentError : throwsUnsupportedError,
    );
    expect(await Directory(path).exists(), isFalse);
    if (!nativeMacFuseEnabled) {
      expect(availableMacMountBackends, isNot(contains(MacFuseBackend.fuseT)));
      expect(availableMacMountBackends, contains(MacFuseBackend.rcloneNfs));
    }
  }, skip: !Platform.isMacOS);
}
