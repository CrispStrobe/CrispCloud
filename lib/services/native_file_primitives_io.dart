import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

export 'native_copy_primitives_io.dart';

typedef _RenameAt2Native = Int32 Function(
  Int32,
  Pointer<Utf8>,
  Int32,
  Pointer<Utf8>,
  Uint32,
);
typedef _RenameAt2 = int Function(int, Pointer<Utf8>, int, Pointer<Utf8>, int);
typedef _RenameExclusiveNative = Int32 Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
  Uint32,
);
typedef _RenameExclusive = int Function(Pointer<Utf8>, Pointer<Utf8>, int);
typedef _ErrnoNative = Pointer<Int32> Function();
typedef _Errno = Pointer<Int32> Function();
typedef _MoveFileNative = Int32 Function(
  Pointer<Utf16>,
  Pointer<Utf16>,
  Uint32,
);
typedef _MoveFile = int Function(Pointer<Utf16>, Pointer<Utf16>, int);
typedef _LastErrorNative = Uint32 Function();
typedef _LastError = int Function();

bool get supportsNativeExclusiveRename =>
    Platform.isLinux ||
    Platform.isAndroid ||
    Platform.isMacOS ||
    Platform.isIOS ||
    Platform.isWindows;

/// Rename a file, link or directory without replacing anything at [destination].
///
/// A false result means the OS/filesystem cannot provide the required primitive
/// or that the paths are on different volumes. All other errors are propagated.
/// Checking existence and then calling Dart's replacing rename is deliberately
/// not a fallback: that would allow a concurrent file to be overwritten.
Future<bool> moveNativeNoReplace(String source, String destination) async {
  if (source.contains('\u0000') || destination.contains('\u0000')) {
    throw ArgumentError('Paths cannot contain a null character.');
  }
  if (Platform.isWindows) {
    final kernel = DynamicLibrary.open('kernel32.dll');
    final move = kernel.lookupFunction<_MoveFileNative, _MoveFile>(
      'MoveFileExW',
    );
    final lastError = kernel.lookupFunction<_LastErrorNative, _LastError>(
      'GetLastError',
    );
    final from = _windowsPath(source).toNativeUtf16();
    final to = _windowsPath(destination).toNativeUtf16();
    try {
      // MOVEFILE_WRITE_THROUGH, without REPLACE_EXISTING or COPY_ALLOWED.
      if (move(from, to, 0x8) != 0) return true;
      final error = lastError();
      if (error == 17 || error == 50 || error == 120) return false;
      throw FileSystemException(
        'Exclusive rename failed',
        source,
        OSError('Windows error $error', error),
      );
    } finally {
      calloc.free(from);
      calloc.free(to);
    }
  }
  if (!supportsNativeExclusiveRename) return false;
  final libc = DynamicLibrary.process();
  final from = source.toNativeUtf8();
  final to = destination.toNativeUtf8();
  try {
    int result;
    late _Errno errno;
    if (Platform.isLinux || Platform.isAndroid) {
      if (!libc.providesSymbol('renameat2')) return false;
      final rename = libc.lookupFunction<_RenameAt2Native, _RenameAt2>(
        'renameat2',
      );
      final errnoSymbol = libc.providesSymbol('__errno_location')
          ? '__errno_location'
          : '__errno';
      if (!libc.providesSymbol(errnoSymbol)) return false;
      errno = libc.lookupFunction<_ErrnoNative, _Errno>(errnoSymbol);
      // AT_FDCWD = -100; RENAME_NOREPLACE = 1.
      result = rename(-100, from, -100, to, 1);
    } else {
      if (!libc.providesSymbol('renamex_np')) return false;
      final rename = libc
          .lookupFunction<_RenameExclusiveNative, _RenameExclusive>(
            'renamex_np',
          );
      errno = libc.lookupFunction<_ErrnoNative, _Errno>('__error');
      // Darwin RENAME_EXCL; this also applies to directories and links.
      result = rename(from, to, 0x4);
    }
    if (result == 0) return true;
    final error = errno().value;
    // EXDEV, ENOSYS and unsupported flags/filesystem. Never retry a replacing
    // rename for these errors; a streaming copy is a separate operation.
    if (error == 18 ||
        error == 22 ||
        error == 38 ||
        error == 45 ||
        error == 78 ||
        error == 95) {
      return false;
    }
    throw FileSystemException(
      'Exclusive rename failed',
      source,
      OSError('OS error $error', error),
    );
  } finally {
    calloc.free(from);
    calloc.free(to);
  }
}

String _windowsPath(String path) {
  final absolute = File(path).absolute.path;
  if (absolute.startsWith(r'\\?\')) return absolute;
  if (absolute.startsWith(r'\\')) {
    return r'\\?\UNC\' + absolute.substring(2);
  }
  return r'\\?\' + absolute;
}
