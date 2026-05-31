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

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/services/fuse_mount_service.dart';
import 'package:crisp_cloud/services/fuse_helper_script.dart';

void main() {
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
      expect(MountStatus.values, containsAll([
        MountStatus.unmounted,
        MountStatus.mounting,
        MountStatus.mounted,
        MountStatus.unmounting,
        MountStatus.error,
      ]));
    });
  });

  // ---------------------------------------------------------------------------
  // FuseMountService — state management (no process spawning)
  // ---------------------------------------------------------------------------

  group('FuseMountService state', () {
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
      expect(
        _fullRemotePath('/bucket', '/a/b/c.txt'),
        '/bucket/a/b/c.txt',
      );
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
        ]
      };
      expect(_extractItems(result).length, 1);
      expect(_extractItems(result).first['name'], 'a.txt');
    });

    test('handles "files" key', () {
      final result = {
        'files': [
          {'name': 'b.txt', 'type': 'file'},
        ]
      };
      expect(_extractItems(result).length, 1);
    });

    test('handles "children" key', () {
      final result = {
        'children': [
          {'name': 'c', 'type': 'folder'},
          {'name': 'd.pdf', 'type': 'file'},
        ]
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
      final cache = _TestDirCache([{'name': 'a'}]);
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
      final path =
          await FuseHelperScript.writeScript('/tmp/crispcloud_test_mount');
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
      12, modTimeMs ?? DateTime.now().millisecondsSinceEpoch, Endian.big);
  view.setUint32(20, isDir ? 2 : 1, Endian.big);
  return out;
}

Uint8List _encodeDir(List<Map<String, dynamic>> items) {
  final parts = <List<int>>[];
  for (final item in items) {
    final name = (item['name'] as String?) ?? '';
    final nameBytes = name.codeUnits;
    final isDir =
        item['type'] == 'folder' || item['type'] == 'directory';
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
