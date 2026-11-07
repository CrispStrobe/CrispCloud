import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data' show Endian;

import 'package:ffi/ffi.dart';

// Direct libc / Win32 calls keep normal file operations free of `Process.run`.
// The only remaining subprocesses in the app are features that *are* external
// tools (PTY, FUSE helper, VeraCrypt CLI, user-defined commands); those are
// disabled in the Mac App Store build.

typedef _PathCallNative = Int32 Function(Pointer<Utf8>, Pointer<Uint8>);
typedef _PathCallDart = int Function(Pointer<Utf8>, Pointer<Uint8>);

typedef _UidNative = Uint32 Function();
typedef _UidDart = int Function();

typedef _ChmodNative = Int32 Function(Pointer<Utf8>, Uint32);
typedef _ChmodDart = int Function(Pointer<Utf8>, int);

typedef _LinkNative = Int32 Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _LinkDart = int Function(Pointer<Utf8>, Pointer<Utf8>);

typedef _GetDiskFreeSpaceExNative = Int32 Function(
  Pointer<Utf16>,
  Pointer<Uint64>,
  Pointer<Uint64>,
  Pointer<Uint64>,
);
typedef _GetDiskFreeSpaceExDart = int Function(
  Pointer<Utf16>,
  Pointer<Uint64>,
  Pointer<Uint64>,
  Pointer<Uint64>,
);

final DynamicLibrary _libc = DynamicLibrary.process();
final DynamicLibrary? _kernel32 = Platform.isWindows
    ? DynamicLibrary.open('kernel32.dll')
    : null;

int? currentUserId() {
  if (Platform.isWindows) return null;
  try {
    final getuid = _libc.lookupFunction<_UidNative, _UidDart>('getuid');
    return getuid();
  } catch (_) {
    return null;
  }
}

int? fileOwnerUserId(String path) {
  if (Platform.isWindows) return null;
  final nativePath = path.toNativeUtf8();
  // The struct is larger than 128 bytes on every supported POSIX platform;
  // we only read the owner uid at its documented ABI offset.
  final buffer = calloc<Uint8>(512);
  try {
    final stat = _libc.lookupFunction<_PathCallNative, _PathCallDart>('stat');
    if (stat(nativePath, buffer) != 0) return null;
    final data = buffer.asTypedList(512).buffer.asByteData();
    // Darwin: dev(0) mode(4) nlink(6) ino(8) uid(16).
    // Linux x86_64: dev(0) ino(8) nlink(16) mode(24) uid(28).
    return data.getUint32(Platform.isMacOS ? 16 : 28, Endian.host);
  } catch (_) {
    return null;
  } finally {
    calloc.free(nativePath);
    calloc.free(buffer);
  }
}

int? freeDiskBytes(String path) {
  if (Platform.isWindows) return _windowsFreeDiskBytes(path);
  if (!Platform.isMacOS && !Platform.isLinux) return null;
  final nativePath = path.toNativeUtf8();
  final buffer = calloc<Uint8>(4096);
  try {
    final statfs = _libc.lookupFunction<_PathCallNative, _PathCallDart>(
      'statfs',
    );
    if (statfs(nativePath, buffer) != 0) return null;
    final data = buffer.asTypedList(4096).buffer.asByteData();
    final blockSize = data.getUint32(Platform.isMacOS ? 0 : 8, Endian.host);
    final availableBlocks = data.getUint64(
      Platform.isMacOS ? 24 : 32,
      Endian.host,
    );
    if (blockSize == 0) return null;
    return availableBlocks * blockSize;
  } catch (_) {
    return null;
  } finally {
    calloc.free(nativePath);
    calloc.free(buffer);
  }
}

int? _windowsFreeDiskBytes(String path) {
  final kernel32 = _kernel32;
  if (kernel32 == null) return null;
  final nativePath = path.toNativeUtf16();
  final available = calloc<Uint64>();
  final total = calloc<Uint64>();
  final totalFree = calloc<Uint64>();
  try {
    final getFree = kernel32
        .lookupFunction<_GetDiskFreeSpaceExNative, _GetDiskFreeSpaceExDart>(
          'GetDiskFreeSpaceExW',
        );
    if (getFree(nativePath, available, total, totalFree) == 0) return null;
    return available.value;
  } catch (_) {
    return null;
  } finally {
    calloc.free(nativePath);
    calloc.free(available);
    calloc.free(total);
    calloc.free(totalFree);
  }
}

bool setFileMode(String path, int mode) {
  if (Platform.isWindows) return false;
  final nativePath = path.toNativeUtf8();
  try {
    final chmod = _libc.lookupFunction<_ChmodNative, _ChmodDart>('chmod');
    return chmod(nativePath, mode) == 0;
  } catch (_) {
    return false;
  } finally {
    calloc.free(nativePath);
  }
}

bool createHardLink(String target, String linkPath) {
  if (Platform.isWindows) return false;
  final nativeTarget = target.toNativeUtf8();
  final nativeLink = linkPath.toNativeUtf8();
  try {
    final link = _libc.lookupFunction<_LinkNative, _LinkDart>('link');
    return link(nativeTarget, nativeLink) == 0;
  } catch (_) {
    return false;
  } finally {
    calloc.free(nativeTarget);
    calloc.free(nativeLink);
  }
}

/// PATH lookup without a `which`/`where` subprocess.
bool commandExists(String command) {
  final path = Platform.environment['PATH'] ?? '';
  final candidates = Platform.isWindows
      ? <String>[
          '$command.exe',
          '$command.com',
          '$command.bat',
          '$command.cmd',
          command,
        ]
      : <String>[command];
  for (final directory in path.split(Platform.isWindows ? ';' : ':')) {
    if (directory.isEmpty) continue;
    for (final candidate in candidates) {
      try {
        if (File('$directory${Platform.pathSeparator}$candidate')
            .existsSync()) {
          return true;
        }
      } catch (_) {
        // Continue searching.
      }
    }
  }
  return false;
}

/// True when [path] is a mount point (its device differs from its parent's).
bool isMountPoint(String path) {
  if (Platform.isWindows) return false;
  final parent = Directory(path).parent.path;
  if (parent == path) return true; // filesystem root
  final device = _deviceId(path);
  final parentDevice = _deviceId(parent);
  return device != null && parentDevice != null && device != parentDevice;
}

int? _deviceId(String path) {
  final nativePath = path.toNativeUtf8();
  final buffer = calloc<Uint8>(512);
  try {
    final stat = _libc.lookupFunction<_PathCallNative, _PathCallDart>('stat');
    if (stat(nativePath, buffer) != 0) return null;
    final data = buffer.asTypedList(512).buffer.asByteData();
    return Platform.isMacOS
        ? data.getUint32(0, Endian.host)
        : data.getUint64(0, Endian.host);
  } catch (_) {
    return null;
  } finally {
    calloc.free(nativePath);
    calloc.free(buffer);
  }
}
