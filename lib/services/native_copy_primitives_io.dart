import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

bool get supportsNativePreallocation =>
    Platform.isLinux ||
    Platform.isAndroid ||
    Platform.isMacOS ||
    Platform.isIOS ||
    Platform.isWindows;
bool get supportsNativeCopyOnWrite => supportsNativePreallocation;
bool get supportsNativePermissions =>
    supportsNativePreallocation && !Platform.isWindows;

/// Reserve disk blocks for a new, empty private staging file. A false result
/// means this filesystem has no allocation primitive; ENOSPC and access errors
/// propagate. Extending a file with truncate alone is never reported as reserve.
Future<bool> preallocateNativeFile(String path, int length) =>
    Isolate.run(() => _preallocate(path, length));

/// Clone into a previously absent private staging path. Filesystems that cannot
/// share blocks return false; callers choose whether streaming is acceptable.
/// Windows clones complete clusters and copies at most one trailing cluster.
Future<bool> cloneNativeFile(String source, String destination) =>
    Isolate.run(() => _clone(source, destination));

Future<void> setNativeFileMode(String path, int mode) =>
    Isolate.run(() => _setMode(path, mode));

typedef _OpenN = Int32 Function(Pointer<Utf8>, Int32, VarArgs<(Int32,)>);
typedef _OpenD = int Function(Pointer<Utf8>, int, int);
typedef _CloseN = Int32 Function(Int32);
typedef _CloseD = int Function(int);
typedef _ErrnoN = Pointer<Int32> Function();
typedef _ErrnoD = Pointer<Int32> Function();
typedef _AllocateN = Int32 Function(Int32, Int32, Int64, Int64);
typedef _AllocateD = int Function(int, int, int, int);
typedef _TruncateN = Int32 Function(Int32, Int64);
typedef _TruncateD = int Function(int, int);
typedef _IoctlN = Int32 Function(Int32, UnsignedLong, VarArgs<(Int32,)>);
typedef _IoctlD = int Function(int, int, int);
typedef _CloneN = Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Int32);
typedef _CloneD = int Function(Pointer<Utf8>, Pointer<Utf8>, int);
typedef _ChmodN = Int32 Function(Int32, Uint32);
typedef _ChmodD = int Function(int, int);
typedef _FcntlN = Int32 Function(Int32, Int32, VarArgs<(Pointer<_FStore>,)>);
typedef _FcntlD = int Function(int, int, Pointer<_FStore>);

final class _FStore extends Struct {
  @Uint32()
  external int flags;
  @Int32()
  external int position;
  @Int64()
  external int offset;
  @Int64()
  external int length;
  @Int64()
  external int allocated;
}

bool get _darwin => Platform.isMacOS || Platform.isIOS;
int get _noFollow => _darwin ? 0x100 : 0x20000;
int get _nonBlock => _darwin ? 0x4 : 0x800;

void _validatePath(String path) {
  if (path.isEmpty || path.contains('\u0000')) {
    throw ArgumentError(
      'A file path cannot be empty or contain null characters.',
    );
  }
}

int _errno(DynamicLibrary libc) {
  final symbol = _darwin
      ? '__error'
      : libc.providesSymbol('__errno_location')
      ? '__errno_location'
      : '__errno';
  return libc.lookupFunction<_ErrnoN, _ErrnoD>(symbol)().value;
}

bool _unsupported(int error) =>
    const [18, 22, 25, 38, 45, 78, 95].contains(error);

Never _osError(String operation, String path, int error) =>
    throw FileSystemException(
      operation,
      path,
      OSError('OS error $error', error),
    );

int _open(DynamicLibrary libc, String path, int flags, {int mode = 0x180}) {
  final value = path.toNativeUtf8();
  try {
    final fd = libc.lookupFunction<_OpenN, _OpenD>('open')(value, flags, mode);
    if (fd < 0) _osError('Opening a transfer file failed', path, _errno(libc));
    return fd;
  } finally {
    calloc.free(value);
  }
}

bool _preallocate(String path, int length) {
  _validatePath(path);
  if (length < 0) throw ArgumentError.value(length, 'length');
  if (!supportsNativePreallocation) return false;
  if (FileSystemEntity.typeSync(path, followLinks: false) !=
          FileSystemEntityType.file ||
      File(path).lengthSync() != 0) {
    throw FileSystemException(
      'Allocation requires an empty regular staging file.',
      path,
    );
  }
  if (length == 0) return true;
  if (Platform.isWindows) return _allocateWindows(path, length);
  final libc = DynamicLibrary.process();
  final fd = _open(libc, path, 1 | _noFollow | _nonBlock);
  try {
    if (!_darwin) {
      // fallocate reserves actual blocks and extends EOF. Do not substitute
      // ftruncate, which can create a sparse file without reserving disk space.
      // https://man7.org/linux/man-pages/man2/fallocate.2.html
      final symbol = libc.providesSymbol('fallocate64')
          ? 'fallocate64'
          : 'fallocate';
      if (!libc.providesSymbol(symbol) ||
          (sizeOf<IntPtr>() == 4 && symbol != 'fallocate64')) {
        return false;
      }
      final result = libc.lookupFunction<_AllocateN, _AllocateD>(symbol)(
        fd,
        0,
        0,
        length,
      );
      if (result == 0) return true;
      final error = _errno(libc);
      if (_unsupported(error)) return false;
      _osError('Reserving disk space failed', path, error);
    }
    // Darwin F_PREALLOCATE with F_ALLOCATEALL guarantees the full requested
    // allocation. Its fstore_t layout and constants come from XNU fcntl.h.
    final request = calloc<_FStore>();
    try {
      request.ref
        ..flags = 0x4
        ..position = 3
        ..length = length;
      final result = libc.lookupFunction<_FcntlN, _FcntlD>('fcntl')(
        fd,
        42,
        request,
      );
      if (result != 0) {
        final error = _errno(libc);
        if (_unsupported(error)) return false;
        _osError('Reserving disk space failed', path, error);
      }
      if (request.ref.allocated < length) {
        throw FileSystemException(
          'The filesystem did not reserve the requested disk space.',
          path,
        );
      }
      if (libc.lookupFunction<_TruncateN, _TruncateD>('ftruncate')(
            fd,
            length,
          ) !=
          0) {
        _osError('Extending the allocated file failed', path, _errno(libc));
      }
      return true;
    } finally {
      calloc.free(request);
    }
  } finally {
    libc.lookupFunction<_CloseN, _CloseD>('close')(fd);
  }
}

bool _clone(String source, String destination) {
  _validatePath(source);
  _validatePath(destination);
  if (!supportsNativeCopyOnWrite) return false;
  if (FileSystemEntity.typeSync(source, followLinks: false) !=
      FileSystemEntityType.file) {
    throw FileSystemException(
      'Copy-on-write requires a regular source file.',
      source,
    );
  }
  if (Platform.isWindows) return _cloneWindows(source, destination);
  final libc = DynamicLibrary.process();
  if (_darwin) {
    if (!libc.providesSymbol('clonefile')) return false;
    final from = source.toNativeUtf8();
    final to = destination.toNativeUtf8();
    try {
      // CLONE_NOFOLLOW | CLONE_NOOWNERCOPY. clonefile never replaces a path.
      final result = libc.lookupFunction<_CloneN, _CloneD>('clonefile')(
        from,
        to,
        0x3,
      );
      if (result == 0) return true;
      final error = _errno(libc);
      if (_unsupported(error)) return false;
      _osError('Copy-on-write clone failed', source, error);
    } finally {
      calloc.free(from);
      calloc.free(to);
    }
  }
  final from = _open(libc, source, _noFollow | _nonBlock);
  int? to;
  var completed = false;
  try {
    // O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW. The containing staging
    // directory is private; normal creation mode still honors the user's umask.
    to = _open(libc, destination, 1 | 0x40 | 0x80 | _noFollow, mode: 0x1b6);
    final result = libc.lookupFunction<_IoctlN, _IoctlD>('ioctl')(
      to,
      0x40049409,
      from,
    );
    if (result == 0) return completed = true;
    final error = _errno(libc);
    if (_unsupported(error)) return false;
    _osError('Copy-on-write clone failed', source, error);
  } finally {
    final close = libc.lookupFunction<_CloseN, _CloseD>('close');
    close(from);
    if (to != null) {
      close(to);
      if (!completed) File(destination).deleteSync();
    }
  }
}

void _setMode(String path, int mode) {
  _validatePath(path);
  if (!supportsNativePermissions) {
    throw UnsupportedError('POSIX permission preservation is unavailable.');
  }
  final libc = DynamicLibrary.process();
  final fd = _open(libc, path, _noFollow | _nonBlock);
  try {
    if (libc.lookupFunction<_ChmodN, _ChmodD>('fchmod')(fd, mode & 0xfff) !=
        0) {
      _osError('Setting permissions failed', path, _errno(libc));
    }
  } finally {
    libc.lookupFunction<_CloseN, _CloseD>('close')(fd);
  }
}

typedef _CreateFileN = IntPtr Function(
  Pointer<Utf16>,
  Uint32,
  Uint32,
  Pointer<Void>,
  Uint32,
  Uint32,
  IntPtr,
);
typedef _CreateFileD = int Function(
  Pointer<Utf16>,
  int,
  int,
  Pointer<Void>,
  int,
  int,
  int,
);
typedef _WinCloseN = Int32 Function(IntPtr);
typedef _WinCloseD = int Function(int);
typedef _WinErrorN = Uint32 Function();
typedef _WinErrorD = int Function();
typedef _SetInfoN = Int32 Function(IntPtr, Int32, Pointer<Void>, Uint32);
typedef _SetInfoD = int Function(int, int, Pointer<Void>, int);
typedef _VolumeInfoN = Int32 Function(
  IntPtr,
  Pointer<Utf16>,
  Uint32,
  Pointer<Uint32>,
  Pointer<Uint32>,
  Pointer<Uint32>,
  Pointer<Utf16>,
  Uint32,
);
typedef _VolumeInfoD = int Function(
  int,
  Pointer<Utf16>,
  int,
  Pointer<Uint32>,
  Pointer<Uint32>,
  Pointer<Uint32>,
  Pointer<Utf16>,
  int,
);
typedef _VolumePathN = Int32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32);
typedef _VolumePathD = int Function(Pointer<Utf16>, Pointer<Utf16>, int);
typedef _DiskSpaceN = Int32 Function(
  Pointer<Utf16>,
  Pointer<Uint32>,
  Pointer<Uint32>,
  Pointer<Uint32>,
  Pointer<Uint32>,
);
typedef _DiskSpaceD = int Function(
  Pointer<Utf16>,
  Pointer<Uint32>,
  Pointer<Uint32>,
  Pointer<Uint32>,
  Pointer<Uint32>,
);
typedef _ControlN = Int32 Function(
  IntPtr,
  Uint32,
  Pointer<Void>,
  Uint32,
  Pointer<Void>,
  Uint32,
  Pointer<Uint32>,
  Pointer<Void>,
);
typedef _ControlD = int Function(
  int,
  int,
  Pointer<Void>,
  int,
  Pointer<Void>,
  int,
  Pointer<Uint32>,
  Pointer<Void>,
);
typedef _SeekN = Int32 Function(IntPtr, Int64, Pointer<Int64>, Uint32);
typedef _SeekD = int Function(int, int, Pointer<Int64>, int);
typedef _FileSizeN = Int32 Function(IntPtr, Pointer<Int64>);
typedef _FileSizeD = int Function(int, Pointer<Int64>);
typedef _ReadWriteN = Int32 Function(
  IntPtr,
  Pointer<Uint8>,
  Uint32,
  Pointer<Uint32>,
  Pointer<Void>,
);
typedef _ReadWriteD = int Function(
  int,
  Pointer<Uint8>,
  int,
  Pointer<Uint32>,
  Pointer<Void>,
);

final class _DuplicateExtents extends Struct {
  @IntPtr()
  external int source;
  @Int64()
  external int sourceOffset;
  @Int64()
  external int targetOffset;
  @Int64()
  external int length;
}

String _windowsPath(String path) {
  final absolute = File(path).absolute.path;
  if (absolute.startsWith(r'\\?\')) return absolute;
  if (absolute.startsWith(r'\\')) return r'\\?\UNC\' + absolute.substring(2);
  return r'\\?\' + absolute;
}

int _winError(DynamicLibrary kernel) =>
    kernel.lookupFunction<_WinErrorN, _WinErrorD>('GetLastError')();
bool _winUnsupported(int error) => const [1, 17, 50, 87, 120].contains(error);

int _winOpen(
  DynamicLibrary kernel,
  String path, {
  required bool write,
  bool create = false,
}) {
  final value = _windowsPath(path).toNativeUtf16();
  try {
    final handle =
        kernel.lookupFunction<_CreateFileN, _CreateFileD>('CreateFileW')(
          value,
          write ? 0xc0000000 : 0x80000000,
          7,
          nullptr,
          create ? 1 : 3,
          0x00200080,
          0,
        );
    if (handle == -1) {
      _osError('Opening a transfer file failed', path, _winError(kernel));
    }
    return handle;
  } finally {
    calloc.free(value);
  }
}

bool _winSetSize(
  DynamicLibrary kernel,
  int handle,
  int kind,
  int size,
  String path,
) {
  final value = calloc<Int64>()..value = size;
  try {
    final result = kernel.lookupFunction<_SetInfoN, _SetInfoD>(
      'SetFileInformationByHandle',
    )(handle, kind, value.cast(), sizeOf<Int64>());
    if (result != 0) return true;
    final error = _winError(kernel);
    if (_winUnsupported(error)) return false;
    _osError('Allocating the staging file failed', path, error);
  } finally {
    calloc.free(value);
  }
}

bool _allocateWindows(String path, int length) {
  final kernel = DynamicLibrary.open('kernel32.dll');
  final handle = _winOpen(kernel, path, write: true);
  try {
    // FILE_ALLOCATION_INFO reserves blocks; EOF then retains that allocation
    // across handle closure. Stream length is checked independently of EOF.
    return _winSetSize(kernel, handle, 5, length, path) &&
        _winSetSize(kernel, handle, 6, length, path);
  } finally {
    kernel.lookupFunction<_WinCloseN, _WinCloseD>('CloseHandle')(handle);
  }
}

bool _cloneWindows(String source, String destination) {
  final kernel = DynamicLibrary.open('kernel32.dll');
  final from = _winOpen(kernel, source, write: false);
  int? to;
  var completed = false;
  final flags = calloc<Uint32>();
  final volume = calloc<Uint16>(32768).cast<Utf16>();
  final values = calloc<Uint32>(4);
  final request = calloc<_DuplicateExtents>();
  try {
    to = _winOpen(kernel, destination, write: true, create: true);
    final volumeInfo = kernel.lookupFunction<_VolumeInfoN, _VolumeInfoD>(
      'GetVolumeInformationByHandleW',
    );
    if (volumeInfo(to, nullptr, 0, nullptr, nullptr, flags, nullptr, 0) == 0) {
      _osError(
        'Inspecting the destination filesystem failed',
        destination,
        _winError(kernel),
      );
    }
    // FILE_SUPPORTS_BLOCK_REFCOUNTING advertises FSCTL_DUPLICATE_EXTENTS_TO_FILE.
    if (flags.value & 0x08000000 == 0) return false;
    final path = _windowsPath(destination).toNativeUtf16();
    try {
      if (kernel.lookupFunction<_VolumePathN, _VolumePathD>(
                'GetVolumePathNameW',
              )(path, volume, 32768) ==
              0 ||
          kernel.lookupFunction<_DiskSpaceN, _DiskSpaceD>('GetDiskFreeSpaceW')(
                volume,
                values,
                values + 1,
                values + 2,
                values + 3,
              ) ==
              0) {
        _osError(
          'Inspecting clone alignment failed',
          destination,
          _winError(kernel),
        );
      }
    } finally {
      calloc.free(path);
    }
    final cluster = values[0] * values[1];
    if (cluster <= 0 || cluster > 2 * 1024 * 1024) return false;
    if (kernel.lookupFunction<_FileSizeN, _FileSizeD>('GetFileSizeEx')(
          from,
          values.cast<Int64>(),
        ) ==
        0) {
      _osError(
        'Inspecting clone source length failed',
        source,
        _winError(kernel),
      );
    }
    final length = values.cast<Int64>().value;
    if (!_winSetSize(kernel, to, 6, length, destination)) return false;
    final aligned = length ~/ cluster * cluster;
    final maxChunk = 1024 * 1024 * 1024 ~/ cluster * cluster;
    final control = kernel.lookupFunction<_ControlN, _ControlD>(
      'DeviceIoControl',
    );
    for (var offset = 0; offset < aligned; offset += maxChunk) {
      request.ref
        ..source = from
        ..sourceOffset = offset
        ..targetOffset = offset
        ..length = aligned - offset < maxChunk ? aligned - offset : maxChunk;
      if (control(
            to,
            0x00098344,
            request.cast(),
            sizeOf<_DuplicateExtents>(),
            nullptr,
            0,
            values,
            nullptr,
          ) ==
          0) {
        final error = _winError(kernel);
        if (_winUnsupported(error)) return false;
        _osError('Copy-on-write clone failed', source, error);
      }
    }
    // ReFS requires cluster-aligned ranges. Only the final partial cluster is
    // read into memory; it cannot grow with the length of the copied file.
    final tail = length - aligned;
    if (tail != 0) {
      final data = calloc<Uint8>(tail);
      try {
        final seek = kernel.lookupFunction<_SeekN, _SeekD>('SetFilePointerEx');
        if (seek(from, aligned, nullptr, 0) == 0 ||
            seek(to, aligned, nullptr, 0) == 0 ||
            kernel.lookupFunction<_ReadWriteN, _ReadWriteD>('ReadFile')(
                  from,
                  data,
                  tail,
                  values,
                  nullptr,
                ) ==
                0 ||
            values.value != tail ||
            kernel.lookupFunction<_ReadWriteN, _ReadWriteD>('WriteFile')(
                  to,
                  data,
                  tail,
                  values,
                  nullptr,
                ) ==
                0 ||
            values.value != tail) {
          _osError(
            'Copying the final clone block failed',
            source,
            _winError(kernel),
          );
        }
      } finally {
        calloc.free(data);
      }
    }
    return completed = true;
  } finally {
    final close = kernel.lookupFunction<_WinCloseN, _WinCloseD>('CloseHandle');
    close(from);
    if (to != null) {
      close(to);
      if (!completed) File(destination).deleteSync();
    }
    calloc.free(flags);
    calloc.free(volume);
    calloc.free(values);
    calloc.free(request);
  }
}
