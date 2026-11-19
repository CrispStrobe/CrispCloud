// Test-only Flutter entrypoint: no preferences, credentials or production startup.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/fuse_filesystem.dart';

class _Fixture implements CloudStorageClient {
  @override
  String get providerName => 'IPC fixture';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final fs = FuseFilesystem(client: _Fixture(), remotePath: '/fixture');
  final serving = fs.serveRequests();
  Socket? peer;
  try {
    final path = await fs.ready.timeout(const Duration(seconds: 10));
    peer = await Socket.connect(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    );
    // Root getattr requires no provider calls; test the actual protocol response.
    final request = ByteData(17)
      ..setUint32(0, FuseOpcode.getattr, Endian.big)
      ..setUint32(4, 1, Endian.big)
      ..setUint32(8, 5, Endian.big)
      ..setUint32(12, 1, Endian.big)
      ..setUint8(16, 47);
    peer.add(request.buffer.asUint8List());
    final response = await peer.first.timeout(const Duration(seconds: 10));
    final header = ByteData.sublistView(response);
    if (header.lengthInBytes < 12 ||
        header.getUint32(0, Endian.big) != 1 ||
        header.getUint32(4, Endian.big) != 0) {
      throw StateError('IPC getattr failed');
    }
    stdout.writeln(
      jsonEncode({
        'probe': 'signed-sandbox-fuse-ipc',
        'passed': true,
        'temporaryRoot': Directory.systemTemp.path,
        'socketBytes': utf8.encode(path).length,
      }),
    );
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    exitCode = 1;
  } finally {
    peer?.destroy();
    await fs.dispose();
    await serving;
  }
  exit(exitCode);
}
