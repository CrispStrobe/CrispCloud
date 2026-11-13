import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import 'archive_external_packer_types.dart';

final class _Timespec extends Struct {
  @Long()
  external int seconds;
  @Long()
  external int nanoseconds;
}

typedef _UtimensatNative = Int32 Function(
  Int32,
  Pointer<Utf8>,
  Pointer<_Timespec>,
  Int32,
);
typedef _UtimensatDart = int Function(
  int,
  Pointer<Utf8>,
  Pointer<_Timespec>,
  int,
);
typedef _CreateFileNative = IntPtr Function(
  Pointer<Utf16>,
  Uint32,
  Uint32,
  Pointer<Void>,
  Uint32,
  Uint32,
  IntPtr,
);
typedef _CreateFileDart = int Function(
  Pointer<Utf16>,
  int,
  int,
  Pointer<Void>,
  int,
  int,
  int,
);
typedef _SetFileTimeNative = Int32 Function(
  IntPtr,
  Pointer<Uint64>,
  Pointer<Uint64>,
  Pointer<Uint64>,
);
typedef _SetFileTimeDart = int Function(
  int,
  Pointer<Uint64>,
  Pointer<Uint64>,
  Pointer<Uint64>,
);
typedef _CloseHandleNative = Int32 Function(IntPtr);
typedef _CloseHandleDart = int Function(int);

/// Sets only owned private staging metadata. Dart's File.setLastModified
/// refuses directory paths on POSIX, so directories require the native API.
/// Every caller-visible pathname is checked before and after the native call.
Future<void> setArchiveExternalPackerModified(
  String path,
  DateTime modified, {
  required bool isDirectory,
}) async {
  const changed = ArchiveExternalPackerException(
    ArchiveExternalPackerFailure.changed,
  );
  const unsupported = ArchiveExternalPackerException(
    ArchiveExternalPackerFailure.unsupportedEntry,
  );
  final expected = isDirectory
      ? FileSystemEntityType.directory
      : FileSystemEntityType.file;
  if (!p.isAbsolute(path) ||
      path.contains('\x00') ||
      await FileSystemEntity.type(path, followLinks: false) != expected ||
      p.normalize(await File(path).resolveSymbolicLinks()) != path) {
    throw changed;
  }
  if (modified.year < 1601 || modified.year > 9999) throw unsupported;
  final ok = Platform.isWindows
      ? _windows(path, modified)
      : _posix(path, modified);
  if (!ok) throw unsupported;
  if (await FileSystemEntity.type(path, followLinks: false) != expected ||
      p.normalize(await File(path).resolveSymbolicLinks()) != path ||
      !(await FileStat.stat(path)).modified.isAtSameMomentAs(modified)) {
    throw changed;
  }
}

bool _posix(String path, DateTime time) {
  if (!(Platform.isLinux || Platform.isMacOS) || sizeOf<Long>() != 8)
    return false;
  final nativePath = path.toNativeUtf8();
  final times = calloc<_Timespec>(2);
  try {
    final microseconds = time.microsecondsSinceEpoch;
    var seconds = microseconds ~/ Duration.microsecondsPerSecond;
    final remainder = microseconds % Duration.microsecondsPerSecond;
    if (microseconds < 0 && remainder != 0) seconds--;
    for (var i = 0; i < 2; i++) {
      times[i].seconds = seconds;
      times[i].nanoseconds = remainder * 1000;
    }
    final call = DynamicLibrary.process()
        .lookupFunction<_UtimensatNative, _UtimensatDart>('utimensat');
    // Absolute paths ignore dirfd. AT_SYMLINK_NOFOLLOW also prevents changing
    // a substituted final symlink target between the two namespace checks.
    return call(0, nativePath, times, Platform.isMacOS ? 0x20 : 0x100) == 0;
  } catch (_) {
    return false;
  } finally {
    calloc.free(nativePath);
    calloc.free(times);
  }
}

bool _windows(String path, DateTime time) {
  final nativePath = path.toNativeUtf16();
  final filetime = calloc<Uint64>();
  var handle = -1;
  _CloseHandleDart? close;
  try {
    final library = DynamicLibrary.open('kernel32.dll');
    final create = library.lookupFunction<_CreateFileNative, _CreateFileDart>(
      'CreateFileW',
    );
    close = library.lookupFunction<_CloseHandleNative, _CloseHandleDart>(
      'CloseHandle',
    );
    final set = library.lookupFunction<_SetFileTimeNative, _SetFileTimeDart>(
      'SetFileTime',
    );
    // FILE_WRITE_ATTRIBUTES; share read/write/delete; OPEN_EXISTING;
    // FILE_FLAG_BACKUP_SEMANTICS permits directories and OPEN_REPARSE_POINT
    // prevents following a substituted final symlink/reparse point.
    handle = create(nativePath, 0x100, 7, nullptr, 3, 0x02200000, 0);
    if (handle == -1) return false;
    filetime.value = (time.microsecondsSinceEpoch + 11644473600000000) * 10;
    return set(handle, nullptr, nullptr, filetime) != 0;
  } catch (_) {
    return false;
  } finally {
    if (handle != -1) close?.call(handle);
    calloc.free(nativePath);
    calloc.free(filetime);
  }
}
