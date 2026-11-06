import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

typedef _OpenN = Int32 Function(Pointer<Utf8>, Int32, VarArgs<(Int32,)>);
typedef _OpenD = int Function(Pointer<Utf8>, int, int);
typedef _FlockN = Int32 Function(Int32, Int32);
typedef _FlockD = int Function(int, int);
typedef _CloseN = Int32 Function(Int32);
typedef _CloseD = int Function(int);
typedef _FdOpenN = Pointer<Void> Function(Int32, Pointer<Utf8>);
typedef _FdOpenD = Pointer<Void> Function(int, Pointer<Utf8>);
typedef _ReleaseN = Int32 Function(Pointer<Void>);
typedef _ReleaseD = int Function(Pointer<Void>);
typedef _ErrnoN = Pointer<Int32> Function();
typedef _ErrnoD = Pointer<Int32> Function();
typedef _CreateN = Pointer<Void> Function(
  Pointer<Utf16>,
  Uint32,
  Uint32,
  Pointer<Void>,
  Uint32,
  Uint32,
  Pointer<Void>,
);
typedef _CreateD = Pointer<Void> Function(
  Pointer<Utf16>,
  int,
  int,
  Pointer<Void>,
  int,
  int,
  Pointer<Void>,
);
typedef _ErrorN = Uint32 Function();
typedef _ErrorD = int Function();
typedef _InfoN = Int32 Function(Pointer<Void>, Int32, Pointer<Uint32>, Uint32);
typedef _InfoD = int Function(Pointer<Void>, int, Pointer<Uint32>, int);

/// An OS-held lease, including between isolates in the same process. POSIX
/// flock is tied to the opened description; Dart's process-scoped record locks
/// cannot provide this isolation. Closing a FILE* or Windows handle also drops
/// the lease. Native finalization covers isolate-group shutdown; process exit
/// releases the OS resource even when Dart finally blocks cannot run.
class NativeJournalLease implements Finalizable {
  NativeJournalLease._(this._handle, this._release, this._finalizer) {
    _finalizer.attach(this, _handle, detach: this);
  }
  final Pointer<Void> _handle;
  final _ReleaseD _release;
  final NativeFinalizer _finalizer;
  bool _closed = false;

  void close() {
    if (_closed) return;
    _closed = true;
    _finalizer.detach(this);
    _release(_handle);
  }
}

Never _failure(String path, int code) => throw FileSystemException(
  'Cannot acquire background journal lease.',
  path,
  OSError('OS error $code', code),
);

Future<NativeJournalLease?> tryAcquireNativeJournalLease(String path) async {
  if (path.isEmpty || path.contains('\u0000') || !p.isAbsolute(path)) {
    throw ArgumentError('A journal lease requires an absolute local path.');
  }
  final kind = FileSystemEntity.typeSync(path, followLinks: false);
  if (kind != FileSystemEntityType.notFound &&
      kind != FileSystemEntityType.file) {
    throw FileSystemException('A journal lease must be a regular file.', path);
  }
  if (Platform.isWindows) return _windows(path);
  if (!(Platform.isLinux ||
      Platform.isAndroid ||
      Platform.isMacOS ||
      Platform.isIOS)) {
    throw UnsupportedError(
      'Native journal leases are unavailable on this platform.',
    );
  }
  final lib = DynamicLibrary.process();
  final mac = Platform.isMacOS || Platform.isIOS;
  final errnoName = mac
      ? '__error'
      : lib.providesSymbol('__errno_location')
      ? '__errno_location'
      : '__errno';
  int errno() => lib.lookupFunction<_ErrnoN, _ErrnoD>(errnoName)().value;
  final name = path.toNativeUtf8();
  late final int fd;
  try {
    final arm32 =
        Abi.current() == Abi.androidArm || Abi.current() == Abi.linuxArm;
    // RDWR | CREAT | NONBLOCK | NOFOLLOW | CLOEXEC; never truncate the file.
    final flags = mac ? 0x1000306 : 0x80842 | (arm32 ? 0x8000 : 0x20000);
    fd = lib.lookupFunction<_OpenN, _OpenD>('open')(name, flags, 0x180);
  } finally {
    calloc.free(name);
  }
  if (fd < 0) _failure(path, errno());
  var owned = true;
  try {
    // Verify the opened object, not just the pre-open pathname.
    final descriptorPath = mac ? '/dev/fd/$fd' : '/proc/self/fd/$fd';
    if (FileStat.statSync(descriptorPath).type != FileSystemEntityType.file) {
      throw FileSystemException(
        'A journal lease requires a regular file descriptor.',
        path,
      );
    }
    if (lib.lookupFunction<_FlockN, _FlockD>('flock')(fd, 2 | 4) != 0) {
      final code = errno();
      if (code == 11 || code == 35) return null; // EWOULDBLOCK/EAGAIN
      _failure(path, code);
    }
    final mode = 'r+'.toNativeUtf8();
    late final Pointer<Void> stream;
    try {
      stream = lib.lookupFunction<_FdOpenN, _FdOpenD>('fdopen')(fd, mode);
    } finally {
      calloc.free(mode);
    }
    if (stream == nullptr) _failure(path, errno());
    owned = false; // fclose now owns the descriptor, including its OS lease.
    final release = lib.lookupFunction<_ReleaseN, _ReleaseD>('fclose');
    final finalizer = NativeFinalizer(
      lib.lookup<NativeFunction<_ReleaseN>>('fclose').cast(),
    );
    return NativeJournalLease._(stream, release, finalizer);
  } finally {
    if (owned) lib.lookupFunction<_CloseN, _CloseD>('close')(fd);
  }
}

NativeJournalLease? _windows(String path) {
  final lib = DynamicLibrary.open('kernel32.dll');
  final release = lib.lookupFunction<_ReleaseN, _ReleaseD>('CloseHandle');
  final error = lib.lookupFunction<_ErrorN, _ErrorD>('GetLastError');
  final absolute = p.windows.normalize(path);
  final longPath = absolute.startsWith(r'\\?\')
      ? absolute
      : absolute.startsWith(r'\\')
      ? r'\\?\UNC\' + absolute.substring(2)
      : r'\\?\' + absolute;
  final name = longPath.toNativeUtf16();
  late final Pointer<Void> handle;
  try {
    handle = lib.lookupFunction<_CreateN, _CreateD>('CreateFileW')(
      name,
      0xc0000000,
      0,
      nullptr,
      4,
      0x00200080,
      nullptr,
    );
  } finally {
    calloc.free(name);
  }
  if (handle.address == -1 ||
      handle.address ==
          (sizeOf<IntPtr>() == 8 ? 0xffffffffffffffff : 0xffffffff)) {
    final code = error();
    if (code == 32 || code == 33) return null;
    _failure(path, code);
  }
  final attrs = calloc<Uint32>(2);
  try {
    if (lib.lookupFunction<_InfoN, _InfoD>('GetFileInformationByHandleEx')(
          handle,
          9,
          attrs,
          8,
        ) ==
        0) {
      _failure(path, error());
    }
    if ((attrs[0] & (0x400 | 0x10)) != 0) {
      throw FileSystemException(
        'Reparse points and directories cannot own a journal lease.',
        path,
      );
    }
  } catch (_) {
    release(handle);
    rethrow;
  } finally {
    calloc.free(attrs);
  }
  final finalizer = NativeFinalizer(
    lib.lookup<NativeFunction<_ReleaseN>>('CloseHandle').cast(),
  );
  return NativeJournalLease._(handle, release, finalizer);
}
