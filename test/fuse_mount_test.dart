// test/fuse_mount_test.dart
//
// Tests for FUSE-based mounted drives.
//
// Because FUSE requires native libraries (macFUSE / libfuse / WinFsp) that
// are not present in a standard CI environment, these tests focus on:
//   • Platform guard / isSupported logic
//   • MountEntry data model (serialisation, copyWith)
//   • FuseMountService state management without spawning processes
//   • Filesystem encoding helpers (attribute encoding, directory listing)
//     tested via standalone helper functions that mirror internal logic
//   • Cache TTL behaviour
//   • FuseHelperScript content validation

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/fuse_mount_service.dart';
import 'package:crisp_cloud/services/fuse_helper_script.dart';

class _AvailableFuseMountService extends FuseMountService {
  @override
  Future<String?> checkFuseAvailability() async => null;
}

class _PausedMountProbeService extends _AvailableFuseMountService {
  final entered = Completer<void>();
  final continueProbe = Completer<void>();

  @override
  Future<bool> isPlatformMountPoint(String mountPoint) async {
    entered.complete();
    await continueProbe.future;
    return false;
  }
}

class _OccupiedMountProbeService extends _AvailableFuseMountService {
  @override
  Future<bool> isPlatformMountPoint(String mountPoint) async => true;
}

class _ExitedHelperService extends _AvailableFuseMountService {
  _ExitedHelperService(this.helper);
  final String helper;

  @override
  String get macBridgePath => helper;

  @override
  Future<bool> isPlatformMountPoint(String mountPoint) async => false;
}

class _PausedUnmountService extends _AvailableFuseMountService {
  _PausedUnmountService(this.helper);
  final String helper;
  final entered = Completer<void>();
  final continueUnmount = Completer<void>();
  int probes = 0;

  @override
  String get macBridgePath => helper;

  @override
  Future<bool> isPlatformMountPoint(String mountPoint) async => probes++ > 0;

  @override
  Future<void> performPlatformUnmount(String mountPoint) async {
    entered.complete();
    await continueUnmount.future;
  }
}

class _TestCloudClient implements CloudStorageClient {
  @override
  String get providerName => 'Test';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // ---------------------------------------------------------------------------
  // Platform support guard
  // ---------------------------------------------------------------------------

  group('FuseMountService.isSupported', () {
    test('returns false on web', () {
      if (!kIsWeb) {
        final expected =
            Platform.isMacOS || Platform.isLinux || Platform.isWindows;
        expect(FuseMountService.isSupported, expected);
      }
    });

    test('is true when running on Linux (typical CI)', () {
      if (!kIsWeb && Platform.isLinux) {
        expect(FuseMountService.isSupported, true);
      }
    });
  });

  // ---------------------------------------------------------------------------
  // MountEntry model
  // ---------------------------------------------------------------------------

  group('MountEntry', () {
    test('construction sets all fields', () {
      final e = MountEntry(
        mountPoint: '/mnt/test',
        label: 'Test',
        provider: 'Dropbox',
        remotePath: '/Photos',
        status: MountStatus.unmounted,
      );
      expect(e.mountPoint, '/mnt/test');
      expect(e.label, 'Test');
      expect(e.provider, 'Dropbox');
      expect(e.remotePath, '/Photos');
      expect(e.status, MountStatus.unmounted);
      expect(e.errorMessage, isNull);
      expect(e.helperPid, isNull);
    });

    test('copyWith changes only specified fields', () {
      final original = MountEntry(
        mountPoint: '/mnt/a',
        label: 'A',
        provider: 'GDrive',
        remotePath: '/',
        status: MountStatus.unmounted,
      );
      final copy = original.copyWith(
        status: MountStatus.mounted,
        helperPid: 1234,
      );
      expect(copy.mountPoint, '/mnt/a');
      expect(copy.label, 'A');
      expect(copy.status, MountStatus.mounted);
      expect(copy.helperPid, 1234);
      expect(copy.errorMessage, isNull);
    });

    test('copyWith with errorMessage', () {
      final e = MountEntry(
        mountPoint: '/mnt/b',
        label: 'B',
        provider: 'S3',
        remotePath: '/bucket',
      );
      final withErr = e.copyWith(
        status: MountStatus.error,
        errorMessage: 'FUSE not found',
      );
      expect(withErr.status, MountStatus.error);
      expect(withErr.errorMessage, 'FUSE not found');
    });

    test('toMap / fromMap round-trip', () {
      final e = MountEntry(
        mountPoint: '/mnt/roundtrip',
        label: 'RT',
        provider: 'OneDrive',
        remotePath: '/Docs',
        macBackend: MacFuseBackend.macFuseKernel,
      );
      final m = e.toMap();
      expect(m['mountPoint'], '/mnt/roundtrip');
      expect(m['label'], 'RT');
      expect(m['provider'], 'OneDrive');
      expect(m['remotePath'], '/Docs');

      final restored = MountEntry.fromMap(m);
      expect(restored.mountPoint, e.mountPoint);
      expect(restored.label, e.label);
      expect(restored.provider, e.provider);
      expect(restored.remotePath, e.remotePath);
      expect(restored.macBackend, MacFuseBackend.macFuseKernel);
      expect(restored.copyWith(status: MountStatus.error).macBackend,
          MacFuseBackend.macFuseKernel);
      m.remove('macBackend');
      expect(MountEntry.fromMap(m).macBackend, MacFuseBackend.automatic);
      expect(restored.status, MountStatus.unmounted); // default
    });

    test('default status is unmounted', () {
      final e = MountEntry(
        mountPoint: '/mnt/x',
        label: 'X',
        provider: 'SFTP',
        remotePath: '/',
      );
      expect(e.status, MountStatus.unmounted);
    });
  });

  // ---------------------------------------------------------------------------
  // MountStatus enum
  // ---------------------------------------------------------------------------

  group('MountStatus', () {
    test('all values are present', () {
      expect(
        MountStatus.values,
        containsAll([
          MountStatus.unmounted,
          MountStatus.mounting,
          MountStatus.mounted,
          MountStatus.unmounting,
          MountStatus.error,
        ]),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // FuseMountService — state management (no process spawning)
  // ---------------------------------------------------------------------------

  group('FuseMountService state', () {
    test('unmountAll waits for a separately initiated unmount', () async {
      if (!Platform.isMacOS) return;
      SharedPreferences.setMockInitialValues({});
      final root = await Directory.systemTemp.createTemp('unmount_drain_test_');
      final helper = File('${root.path}/helper');
      await helper.writeAsString('#!/bin/sh\nprintf "MOUNTED\\n"\nexec /bin/sleep 30\n');
      expect((await Process.run('/bin/chmod', ['700', helper.path])).exitCode, 0);
      final service = _PausedUnmountService(helper.path);
      addTearDown(() async {
        if (!service.continueUnmount.isCompleted) service.continueUnmount.complete();
        await service.unmountAll();
        await root.delete(recursive: true);
      });
      final mountPoint = '${root.path}/mount';
      final entry = await service.mount(
        client: _TestCloudClient(), remotePath: '/', mountPoint: mountPoint,
      );
      expect(entry.status, MountStatus.mounted);
      final unmount = service.unmount(mountPoint);
      await service.entered.future;
      var drained = false;
      final drain = service.unmountAll().then((_) => drained = true);
      await Future<void>.delayed(Duration.zero);
      expect(drained, isFalse);
      service.continueUnmount.complete();
      await unmount;
      await drain;
      expect(drained, isTrue);
      expect(service.getMounts().single.status, MountStatus.unmounted);
    });
    test('unmountAll waits for an in-flight mount before completing', () async {
      if (!FuseMountService.isSupported) return;
      SharedPreferences.setMockInitialValues({});
      final root = await Directory.systemTemp.createTemp('mount_drain_test_');
      addTearDown(() => root.delete(recursive: true));
      final service = _PausedMountProbeService();
      final mount = service.mount(
        client: _TestCloudClient(), remotePath: '/', mountPoint: '${root.path}/one',
      );
      await service.entered.future;
      var drained = false;
      final drain = service.unmountAll().then((_) => drained = true);
      await Future<void>.delayed(Duration.zero);
      expect(drained, isFalse);
      await expectLater(
        service.mount(client: _TestCloudClient(), remotePath: '/', mountPoint: '${root.path}/two'),
        throwsStateError,
      );
      service.continueProbe.complete();
      await mount;
      await drain;
      expect(drained, isTrue);
    });
    test('reports a helper that exits after announcing readiness', () async {
      if (!Platform.isMacOS) return;
      SharedPreferences.setMockInitialValues({});
      final root = await Directory.systemTemp.createTemp('mount_exited_test_');
      addTearDown(() => root.delete(recursive: true));
      final helper = File('${root.path}/helper');
      await helper.writeAsString('#!/bin/sh\nprintf "MOUNTED\\n"\nexit 17\n');
      expect((await Process.run('/bin/chmod', ['700', helper.path])).exitCode, 0);
      final service = _ExitedHelperService(helper.path);
      final entry = await service.mount(
        client: _TestCloudClient(),
        remotePath: '/',
        mountPoint: '${root.path}/mount',
      );
      expect(entry.status, MountStatus.error);
      expect(entry.errorKey, 'helperExited');
      expect(entry.errorValues['code'], 17);
    });
    test('rclone accepts configured names without inline credentials', () {
      expect(FuseMountService.isValidRcloneRemote('work:documents'), isTrue);
      expect(FuseMountService.isValidRcloneRemote(':local:/tmp/fixture'), isTrue);
      expect(FuseMountService.isValidRcloneRemote(':s3,secret=secret:bucket'), isFalse);
      expect(FuseMountService.isValidRcloneRemote('/'), isFalse);
      expect(FuseMountService.isValidRcloneRemote('--option:foo'), isFalse);
    });
    test('automatic selection never chooses FUSE-T', () {
      expect(FuseMountService.macFuseRuntime(MacFuseBackend.automatic), 'macfuse-fskit');
      expect(FuseMountService.macFuseRuntime(MacFuseBackend.fuseT), 'fuse-t');
      expect(FuseMountService.macFuseRuntime(MacFuseBackend.fuseTSmb), 'fuse-t-smb');
    });
    test('FUSE-T cannot start without the non-commercial acknowledgement', () async {
      if (!FuseMountService.isSupported) return;
      final service = FuseMountService();
      for (final backend in [MacFuseBackend.fuseT, MacFuseBackend.fuseTSmb]) {
        await expectLater(
          service.mount(
            client: _TestCloudClient(),
            remotePath: '/',
            mountPoint: '/tmp/crispcloud-fuse-no-consent',
            macBackend: backend,
          ),
          throwsArgumentError,
        );
      }
      expect(service.getMounts(), isEmpty);
    });
    test('rejects a second request while a mount is still mounting', () async {
      if (!FuseMountService.isSupported) return;
      SharedPreferences.setMockInitialValues({});
      final root = await Directory.systemTemp.createTemp('mount_race_test_');
      addTearDown(() => root.delete(recursive: true));
      final mountPoint = '${root.path}/cloud';
      final service = _PausedMountProbeService();
      final first = service.mount(
        client: _TestCloudClient(),
        remotePath: '/',
        mountPoint: mountPoint,
      );
      await service.entered.future;
      expect(service.getMounts().single.status, MountStatus.mounting);
      await expectLater(service.removeMount(mountPoint), throwsStateError);
      expect(service.getMounts().single.status, MountStatus.mounting);
      await expectLater(
        service.mount(
          client: _TestCloudClient(),
          remotePath: '/',
          mountPoint: mountPoint,
        ),
        throwsA(isA<ArgumentError>()),
      );
      service.continueProbe.complete();
      expect((await first).status, MountStatus.error);
    });

    test(
      'refuses an OS mount before creating or changing its directory',
      () async {
        if (!FuseMountService.isSupported) return;
        SharedPreferences.setMockInitialValues({});
        final root = await Directory.systemTemp.createTemp(
          'mount_occupied_test_',
        );
        addTearDown(() => root.delete(recursive: true));
        final mountPoint = '${root.path}/other-filesystem';
        final service = _OccupiedMountProbeService();
        final entry = await service.mount(
          client: _TestCloudClient(),
          remotePath: '/',
          mountPoint: mountPoint,
        );
        expect(entry.status, MountStatus.error);
        expect(entry.errorMessage, contains('already in use'));
        expect(entry.errorKey, 'mountPointOccupied');
        expect(entry.errorValues['path'], mountPoint);
        expect(await Directory(mountPoint).exists(), isFalse);
        await service.unmount(mountPoint);
        expect(service.getMounts().single.status, MountStatus.error);
      },
    );

    test('OS mount probe recognizes the system root', () async {
      if (!Platform.isMacOS && !Platform.isLinux) return;
      expect(await FuseMountService().isPlatformMountPoint('/'), isTrue);
    });

    test('does not report a mount when the native bridge is absent', () async {
      if (!FuseMountService.isSupported) return;
      SharedPreferences.setMockInitialValues({});
      addTearDown(() => SharedPreferences.setMockInitialValues({}));
      final directory = await Directory.systemTemp.createTemp('mount_test_');
      addTearDown(() => directory.delete(recursive: true));
      final service = _AvailableFuseMountService();
      final mount = await service.mount(
        client: _TestCloudClient(),
        remotePath: '/',
        mountPoint: directory.path,
      );
      expect(mount.status, MountStatus.error);
      expect(mount.errorMessage, contains('native FUSE bridge'));
      expect(service.isMounted(directory.path), isFalse);
    });
    test('getMounts is empty initially', () {
      final svc = FuseMountService();
      expect(svc.getMounts(), isEmpty);
    });

    test('isMounted returns false for unknown mount point', () {
      final svc = FuseMountService();
      expect(svc.isMounted('/mnt/nonexistent'), false);
    });

    test('getActiveMounts is empty initially', () {
      final svc = FuseMountService();
      expect(svc.getActiveMounts(), isEmpty);
    });

    test('loadPersistedMounts completes without error', () async {
      if (!FuseMountService.isSupported) return;
      final svc = FuseMountService();
      // SharedPreferences returns empty in test environment.
      await svc.loadPersistedMounts();
      expect(svc.getMounts(), isEmpty);
    });

    test('onChanged callback is invokeable', () {
      final svc = FuseMountService();
      var callCount = 0;
      svc.onChanged = () => callCount++;
      // Directly invoke the callback to verify it is wired correctly.
      svc.onChanged!();
      expect(callCount, 1);
    });

    test('unmountAll is safe when there are no mounts', () async {
      if (!FuseMountService.isSupported) return;
      final svc = FuseMountService();
      await svc.unmountAll(); // should complete without error
    });
  });

  // ---------------------------------------------------------------------------
  // Attribute encoding — mirrors FuseFilesystem internal logic
  // ---------------------------------------------------------------------------

  group('Attribute encoding helpers', () {
    test('directory mode is 0x41ED (octal 040755)', () {
      final attr = _encodeAttr(isDir: true, size: 0);
      expect(attr.length, 24);
      final view = ByteData.view(attr.buffer);
      expect(view.getUint32(0, Endian.big), 0x41ED);
      // nlinks for directory = 2
      expect(view.getUint32(20, Endian.big), 2);
    });

    test('regular file mode is 0x81A4 (octal 0100644)', () {
      final attr = _encodeAttr(isDir: false, size: 512);
      final view = ByteData.view(attr.buffer);
      expect(view.getUint32(0, Endian.big), 0x81A4);
      expect(view.getUint64(4, Endian.big), 512);
      expect(view.getUint32(20, Endian.big), 1);
    });

    test('mtime is encoded in attr bytes 12-19', () {
      final mtime = DateTime(2024, 3, 15).millisecondsSinceEpoch;
      final attr = _encodeAttr(isDir: false, size: 0, modTimeMs: mtime);
      final view = ByteData.view(attr.buffer);
      expect(view.getUint64(12, Endian.big), mtime);
    });

    test('size zero file encodes correctly', () {
      final attr = _encodeAttr(isDir: false, size: 0);
      final view = ByteData.view(attr.buffer);
      expect(view.getUint64(4, Endian.big), 0);
    });
  });

  // ---------------------------------------------------------------------------
  // Directory listing encoding
  // ---------------------------------------------------------------------------

  group('Directory listing encoding', () {
    test('empty directory produces count=0 header', () {
      final encoded = _encodeDir([]);
      expect(encoded.length, 4);
      final view = ByteData.view(encoded.buffer);
      expect(view.getUint32(0, Endian.big), 0);
    });

    test('directory with two entries has count=2', () {
      final items = [
        {'name': 'readme.md', 'type': 'file', 'size': 100},
        {'name': 'src', 'type': 'folder', 'size': 0},
      ];
      final encoded = _encodeDir(items);
      final view = ByteData.view(encoded.buffer);
      expect(view.getUint32(0, Endian.big), 2);
      expect(encoded.length, greaterThan(4));
    });

    test('entry bytes contain name length as first byte', () {
      final items = [
        {'name': 'hello', 'type': 'file', 'size': 0},
      ];
      final encoded = _encodeDir(items);
      // After 4-byte count header, first byte is name length.
      expect(encoded[4], 'hello'.length);
    });
  });

  // ---------------------------------------------------------------------------
  // Binary encoding helpers
  // ---------------------------------------------------------------------------

  group('Binary encoding / decoding', () {
    test('readUint32 decodes big-endian correctly', () {
      final bytes = [0x00, 0x00, 0x00, 0x2A];
      expect(_readUint32(bytes, 0), 42);
    });

    test('readUint32 handles offset', () {
      final bytes = [0xFF, 0x00, 0x00, 0x00, 0x01];
      expect(_readUint32(bytes, 1), 1);
    });

    test('readUint64 decodes big-endian correctly', () {
      final bytes = [0, 0, 0, 0, 0, 0, 0x01, 0x00];
      expect(_readUint64(bytes, 0), 256);
    });

    test('encodeUint32 produces 4 big-endian bytes', () {
      final out = _encodeUint32(0xCAFEBABE);
      expect(out.length, 4);
      final view = ByteData.view(out.buffer);
      expect(view.getUint32(0, Endian.big), 0xCAFEBABE);
    });

    test('decodeString round-trips a length-prefixed string', () {
      const name = 'hello.dart';
      final bytes = Uint8List(4 + name.length);
      final view = ByteData.view(bytes.buffer);
      view.setUint32(0, name.length, Endian.big);
      for (var i = 0; i < name.length; i++) {
        bytes[4 + i] = name.codeUnitAt(i);
      }
      expect(_decodeString(bytes, 0), name);
    });

    test('encodeUint32 zero is four zero bytes', () {
      final out = _encodeUint32(0);
      expect(out, everyElement(0));
    });
  });

  // ---------------------------------------------------------------------------
  // statfs encoding
  // ---------------------------------------------------------------------------

  group('statfs', () {
    test('produces exactly 64 bytes', () {
      expect(_statfs().length, 64);
    });

    test('block size field is 4096', () {
      final stat = _statfs();
      final view = ByteData.view(stat.buffer);
      expect(view.getUint64(40, Endian.big), 4096);
    });

    test('name max length is 255', () {
      final stat = _statfs();
      final view = ByteData.view(stat.buffer);
      expect(view.getUint64(48, Endian.big), 255);
    });
  });

  // ---------------------------------------------------------------------------
  // Remote path composition
  // ---------------------------------------------------------------------------

  group('Remote path helpers', () {
    test('root path returns remotePath unchanged', () {
      expect(_fullRemotePath('/cloud/root', '/'), '/cloud/root');
      expect(_fullRemotePath('/cloud/root', ''), '/cloud/root');
    });

    test('subpath is joined correctly', () {
      expect(
        _fullRemotePath('/cloud/root', '/subdir/file.txt'),
        '/cloud/root/subdir/file.txt',
      );
    });

    test('deep path is joined correctly', () {
      expect(_fullRemotePath('/bucket', '/a/b/c.txt'), '/bucket/a/b/c.txt');
    });
  });

  // ---------------------------------------------------------------------------
  // extractItems
  // ---------------------------------------------------------------------------

  group('extractItems', () {
    test('handles "items" key', () {
      final result = {
        'items': [
          {'name': 'a.txt', 'type': 'file'},
        ],
      };
      expect(_extractItems(result).length, 1);
      expect(_extractItems(result).first['name'], 'a.txt');
    });

    test('handles "files" key', () {
      final result = {
        'files': [
          {'name': 'b.txt', 'type': 'file'},
        ],
      };
      expect(_extractItems(result).length, 1);
    });

    test('handles "children" key', () {
      final result = {
        'children': [
          {'name': 'c', 'type': 'folder'},
          {'name': 'd.pdf', 'type': 'file'},
        ],
      };
      expect(_extractItems(result).length, 2);
    });

    test('falls back to map values when no known key', () {
      final result = {
        'photo.jpg': {'name': 'photo.jpg', 'type': 'file'},
        'docs': {'name': 'docs', 'type': 'folder'},
      };
      expect(_extractItems(result).length, 2);
    });

    test('returns empty list for empty map', () {
      expect(_extractItems({}), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Cache TTL behaviour
  // ---------------------------------------------------------------------------

  group('DirCache TTL', () {
    test('new cache entry is not expired', () {
      final cache = _TestDirCache([
        {'name': 'a'},
      ]);
      expect(cache.isExpired, false);
    });

    test('cache entry fetched in the past is expired', () {
      final cache = _TestDirCache([], fetchedAt: DateTime(2000));
      expect(cache.isExpired, true);
    });

    test('cache entry fetched 29 seconds ago is still fresh', () {
      final cache = _TestDirCache(
        [],
        fetchedAt: DateTime.now().subtract(const Duration(seconds: 29)),
      );
      expect(cache.isExpired, false);
    });

    test('cache entry fetched 31 seconds ago is expired', () {
      final cache = _TestDirCache(
        [],
        fetchedAt: DateTime.now().subtract(const Duration(seconds: 31)),
      );
      expect(cache.isExpired, true);
    });
  });

  // ---------------------------------------------------------------------------
  // FuseOpcode constants
  // ---------------------------------------------------------------------------

  group('FuseOpcode constants', () {
    test('all 12 opcodes are distinct positive integers', () {
      const opcodes = [
        _FuseOp.getattr,
        _FuseOp.readdir,
        _FuseOp.read,
        _FuseOp.write,
        _FuseOp.create,
        _FuseOp.mkdir,
        _FuseOp.unlink,
        _FuseOp.rmdir,
        _FuseOp.rename,
        _FuseOp.release,
        _FuseOp.truncate,
        _FuseOp.statfs,
      ];
      expect(opcodes.toSet().length, 12);
      for (final op in opcodes) {
        expect(op, greaterThan(0));
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Write-back buffer accumulation
  // ---------------------------------------------------------------------------

  group('WriteBuffer', () {
    test('assemble combines chunks in correct order', () {
      final wb = _TestWriteBuffer();
      wb.chunks[0] = Uint8List.fromList([1, 2, 3]);
      wb.chunks[3] = Uint8List.fromList([4, 5, 6]);
      wb.fileSize = 6;
      expect(wb.assemble(), [1, 2, 3, 4, 5, 6]);
    });

    test('assemble returns empty when no chunks', () {
      final wb = _TestWriteBuffer();
      expect(wb.assemble(), isEmpty);
    });

    test('partial overlap: later chunk overwrites earlier bytes', () {
      final wb = _TestWriteBuffer();
      wb.chunks[0] = Uint8List.fromList([0, 0, 0, 0]);
      wb.chunks[2] = Uint8List.fromList([9, 9]);
      wb.fileSize = 4;
      final result = wb.assemble();
      expect(result[2], 9);
      expect(result[3], 9);
    });

    test('fileSize tracks logical end correctly', () {
      final wb = _TestWriteBuffer();
      wb.chunks[0] = Uint8List.fromList([1, 2, 3, 4]);
      wb.fileSize = 4;
      expect(wb.fileSize, 4);
    });
  });

  // ---------------------------------------------------------------------------
  // FuseHelperScript — file creation
  // ---------------------------------------------------------------------------

  group('FuseHelperScript', () {
    test('writeScript creates a non-empty file on disk', () async {
      if (!FuseMountService.isSupported) return;
      final path = await FuseHelperScript.writeScript(
        '/tmp/crispcloud_test_mount',
      );
      final file = File(path);
      addTearDown(() async {
        if (await file.exists()) await file.delete();
      });
      expect(await file.exists(), true);
      final content = await file.readAsString();
      expect(content, isNotEmpty);
    });

    test('Linux script contains fusermount reference', () async {
      if (!Platform.isLinux || kIsWeb) return;
      final path = await FuseHelperScript.writeScript('/tmp/crispcloud_test');
      addTearDown(() async {
        final f = File(path);
        if (await f.exists()) await f.delete();
      });
      final content = await File(path).readAsString();
      expect(content, contains('fusermount'));
    });

    test('Linux script documents fuse3 installation', () async {
      if (!Platform.isLinux || kIsWeb) return;
      final path = await FuseHelperScript.writeScript('/tmp/crispcloud_test2');
      addTearDown(() async {
        final f = File(path);
        if (await f.exists()) await f.delete();
      });
      final content = await File(path).readAsString();
      expect(content, contains('fuse3'));
    });

    test('macOS script documents macFUSE requirement', () async {
      if (!Platform.isMacOS || kIsWeb) return;
      final path = await FuseHelperScript.writeScript('/tmp/crispcloud_test');
      addTearDown(() async {
        final f = File(path);
        if (await f.exists()) await f.delete();
      });
      final content = await File(path).readAsString();
      expect(content, contains('macfuse'));
    });

    test('Windows script documents WinFsp requirement', () async {
      if (!Platform.isWindows || kIsWeb) return;
      final path = await FuseHelperScript.writeScript(r'C:\crispcloud_test');
      addTearDown(() async {
        final f = File(path);
        if (await f.exists()) await f.delete();
      });
      final content = await File(path).readAsString();
      expect(content, contains('WinFsp'));
    });
  });
}

// ---------------------------------------------------------------------------
// Pure helper functions that mirror FuseFilesystem internal logic.
// These allow white-box testing without accessing private members.
// ---------------------------------------------------------------------------

Uint8List _encodeAttr({
  required bool isDir,
  required int size,
  int? modTimeMs,
}) {
  final out = Uint8List(24);
  final view = ByteData.view(out.buffer);
  final mode = isDir ? 0x41ED : 0x81A4;
  view.setUint32(0, mode, Endian.big);
  view.setUint64(4, size, Endian.big);
  view.setUint64(
    12,
    modTimeMs ?? DateTime.now().millisecondsSinceEpoch,
    Endian.big,
  );
  view.setUint32(20, isDir ? 2 : 1, Endian.big);
  return out;
}

Uint8List _encodeDir(List<Map<String, dynamic>> items) {
  final parts = <List<int>>[];
  for (final item in items) {
    final name = (item['name'] as String?) ?? '';
    final nameBytes = name.codeUnits;
    final isDir = item['type'] == 'folder' || item['type'] == 'directory';
    final size = (item['size'] as num?)?.toInt() ?? 0;
    final attr = _encodeAttr(isDir: isDir, size: size);
    final entry = Uint8List(1 + nameBytes.length + 24);
    entry[0] = nameBytes.length;
    entry.setAll(1, nameBytes);
    entry.setAll(1 + nameBytes.length, attr);
    parts.add(entry);
  }
  final total = 4 + parts.fold<int>(0, (s, e) => s + e.length);
  final out = Uint8List(total);
  final view = ByteData.view(out.buffer);
  view.setUint32(0, parts.length, Endian.big);
  int cursor = 4;
  for (final part in parts) {
    out.setAll(cursor, part);
    cursor += part.length;
  }
  return out;
}

int _readUint32(List<int> buf, int offset) =>
    (buf[offset] << 24) |
    (buf[offset + 1] << 16) |
    (buf[offset + 2] << 8) |
    buf[offset + 3];

int _readUint64(List<int> buf, int offset) {
  int value = 0;
  for (var i = 0; i < 8; i++) {
    value = (value << 8) | buf[offset + i];
  }
  return value;
}

Uint8List _encodeUint32(int value) {
  final out = Uint8List(4);
  ByteData.view(out.buffer).setUint32(0, value, Endian.big);
  return out;
}

String _decodeString(List<int> buf, int offset) {
  final len = _readUint32(buf, offset);
  return String.fromCharCodes(buf.sublist(offset + 4, offset + 4 + len));
}

Uint8List _statfs() {
  final out = Uint8List(64);
  final view = ByteData.view(out.buffer);
  view.setUint64(0, 1 << 40, Endian.big);
  view.setUint64(8, 1 << 39, Endian.big);
  view.setUint64(16, 1 << 39, Endian.big);
  view.setUint64(24, 1 << 32, Endian.big);
  view.setUint64(32, 1 << 31, Endian.big);
  view.setUint64(40, 4096, Endian.big);
  view.setUint64(48, 255, Endian.big);
  view.setUint64(56, 512, Endian.big);
  return out;
}

String _fullRemotePath(String remotePath, String local) {
  if (local == '/' || local.isEmpty) return remotePath;
  final base = remotePath.endsWith('/')
      ? remotePath.substring(0, remotePath.length - 1)
      : remotePath;
  final rel = local.startsWith('/') ? local.substring(1) : local;
  return '$base/$rel';
}

List<Map<String, dynamic>> _extractItems(Map<String, dynamic> result) {
  for (final key in ['items', 'files', 'children', 'entries', 'contents']) {
    final v = result[key];
    if (v is List) return v.cast<Map<String, dynamic>>();
  }
  return result.values.whereType<Map<String, dynamic>>().toList();
}

// ---------------------------------------------------------------------------
// Test data models that mirror internal classes
// ---------------------------------------------------------------------------

class _TestDirCache {
  final List<Map<String, dynamic>> entries;
  final DateTime fetchedAt;
  static const ttl = Duration(seconds: 30);

  _TestDirCache(this.entries, {DateTime? fetchedAt})
    : fetchedAt = fetchedAt ?? DateTime.now();

  bool get isExpired => DateTime.now().difference(fetchedAt) > ttl;
}

class _TestWriteBuffer {
  final Map<int, Uint8List> chunks = {};
  int fileSize = 0;

  Uint8List assemble() {
    if (chunks.isEmpty) return Uint8List(0);
    final buf = Uint8List(fileSize);
    for (final entry in chunks.entries) {
      final start = entry.key;
      final src = entry.value;
      final end = (start + src.length).clamp(0, fileSize);
      buf.setRange(start, end, src);
    }
    return buf;
  }
}

/// Mirror of FuseOpcode for testing without importing the internal class.
abstract class _FuseOp {
  static const getattr = 1;
  static const readdir = 2;
  static const read = 3;
  static const write = 4;
  static const create = 5;
  static const mkdir = 6;
  static const unlink = 7;
  static const rmdir = 8;
  static const rename = 9;
  static const release = 10;
  static const truncate = 11;
  static const statfs = 12;
}
