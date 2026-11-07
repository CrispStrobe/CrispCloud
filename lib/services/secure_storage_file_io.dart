import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/async_lock.dart';
import 'native_system.dart';
import 'secure_storage_service.dart';
import 'secure_storage_web.dart';

/// A transactional file backend for the shared password vault codec.
///
/// Each operation loads fresh committed state under an OS lock. There is no
/// per-instance cache. Cooperating processes and isolates cannot overwrite one
/// another's transactions: competing OS lock attempts fail explicitly and can
/// be retried. The persistent empty .lock file must never be unlinked in normal
/// use, since replacing a locked inode would split the exclusion boundary.
///
/// Writes use a unique private directory on the same filesystem, flush the
/// staged file, then replace the destination without deleting it first. POSIX
/// files are made 0600 before ciphertext is written; Windows inherits the
/// application's data-directory ACL, not POSIX mode bits. The directory must be
/// private to the user: this is not a defense against another process running
/// as that same user and modifying the application's directories or memory.
class FileStorageBackend implements TransactionalWebStorageBackend {
  FileStorageBackend(
    this.file, {
    @visibleForTesting
    Future<void> Function(File staged, File destination)? replaceForTesting,
  }) : _replaceForTesting = replaceForTesting;

  final File file;
  final Future<void> Function(File, File)? _replaceForTesting;
  static final _pathLocks = <String, AsyncLock>{};
  static const _maximumBytes = 16 * 1024 * 1024;

  Future<File> _resolvedFile() async {
    final parent = file.absolute.parent;
    await parent.create(recursive: true);
    // Resolve system aliases (e.g. /var -> /private/var on Apple systems) once
    // per operation, so spelling aliases share the same serialization key.
    final resolved = Directory(await parent.resolveSymbolicLinks());
    if (!Platform.isWindows && ((await resolved.stat()).mode & 0x12) != 0) {
      throw FileSystemException(
        'Credential vault directory must not be writable by other users',
        resolved.path,
      );
    }
    return File(p.join(resolved.path, p.basename(file.path)));
  }

  static Future<FileSystemEntityType> _regularOrAbsent(String path) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type != FileSystemEntityType.file &&
        type != FileSystemEntityType.notFound) {
      throw FileSystemException(
        'Credential vault paths must be regular files, never links',
        path,
      );
    }
    return type;
  }

  static void _privateMode(String path, int mode) {
    if (!Platform.isWindows && !setFileMode(path, mode)) {
      throw FileSystemException('Could not restrict credential vault permissions', path);
    }
  }

  Future<Map<String, String>> _load(File target) async {
    if (await _regularOrAbsent(target.path) == FileSystemEntityType.notFound) {
      return <String, String>{};
    }
    if (await target.length() > _maximumBytes) {
      throw StateError('Credential vault exceeds the supported size');
    }
    final bytes = await target.readAsBytes();
    if (bytes.length > _maximumBytes) {
      throw StateError('Credential vault exceeds the supported size');
    }
    try {
      // An existing empty/truncated file is corruption, not a new vault.
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) {
        throw const FormatException('Credential vault is not a JSON object');
      }
      final data = <String, String>{};
      for (final entry in decoded.entries) {
        if (entry.key is! String || entry.value is! String) {
          throw const FormatException('Credential vault contains a non-string entry');
        }
        data[entry.key as String] = entry.value as String;
      }
      return data;
    } on FormatException {
      // Do not embed raw JSON/credential contents in an error or log message.
      throw StateError('Credential vault is corrupt; preserve it for recovery');
    }
  }

  Future<void> _save(File target, Map<String, String> data) async {
    final encoded = utf8.encode(jsonEncode(data));
    if (encoded.length > _maximumBytes) {
      throw StateError('Credential vault exceeds the supported size');
    }
    final staging = await target.parent.createTemp('.credential-vault-');
    try {
      _privateMode(staging.path, 0x1c0 /* 0700 */);
      final temporary = File(p.join(staging.path, 'vault.json'));
      await temporary.create(exclusive: true);
      _privateMode(temporary.path, 0x180 /* 0600 */);
      await temporary.writeAsBytes(encoded, flush: true);
      await _regularOrAbsent(target.path);
      final replace = _replaceForTesting;
      if (replace != null) {
        await replace(temporary, target);
      } else {
        // Dart uses rename/renameat on POSIX and MoveFileExW with
        // REPLACE_EXISTING | WRITE_THROUGH on Windows. No delete-before-rename.
        await temporary.rename(target.path);
      }
      if (!Platform.isWindows) {
        // Sync the published directory entry as well as the staged contents.
        // If this fails, the replacement already happened; report that state
        // explicitly. Filesystem/device failure can still defeat durability.
        _PosixVaultLock.syncDirectory(target.parent.path);
      }
    } finally {
      // An interrupted process may leave an encrypted private staging directory;
      // it is never treated as committed state or used to overwrite a vault.
      // Cleanup failure must not turn an acknowledged commit into a failed one.
      try {
        await staging.delete(recursive: true);
      } on FileSystemException {
        // The committed vault (or previous vault after a failed rename) remains.
      }
    }
  }

  @override
  Future<T> transaction<T>(Future<T> Function(WebStorageBackend) action) async {
    final target = await _resolvedFile();
    final lockKey = Platform.isWindows ? target.path.toLowerCase() : target.path;
    final local = _pathLocks.putIfAbsent(lockKey, AsyncLock.new);
    return local.synchronized(() async {
      final release = await _acquireLock(target);
      try {
        final staged = _StagedFileBackend(await _load(target));
        try {
          final result = await action(staged);
          staged.active = false;
          if (staged.dirty) await _save(target, staged.data);
          return result;
        } finally {
          staged.active = false;
        }
      } finally {
        await release();
      }
    });
  }

  static Future<Future<void> Function()> _acquireLock(File target) async {
    final lockFile = File('${target.path}.lock');
    // Exclusive creation never follows a pre-existing symlink. The lock file
    // is empty and persistent; secret data is never written through this path.
    try {
      await lockFile.create(exclusive: true);
    } on PathExistsException {
      // Another instance/process may have created the same stable lock file.
    }
    await _regularOrAbsent(lockFile.path);
    if (!Platform.isWindows) {
      // Dart's POSIX RandomAccessFile.lock is process-scoped, so two isolates
      // can both hold it. flock is scoped to the opened file description and
      // supplies the exclusion needed here; O_NOFOLLOW refuses lock symlinks.
      final lock = _PosixVaultLock.acquire(lockFile.path);
      return () async => lock.close();
    }
    final handle = await lockFile.open(mode: FileMode.append);
    try {
      await handle.lock(FileLock.exclusive);
      return () async {
        await handle.close();
      };
    } catch (_) {
      await handle.close();
      throw StateError('Credential vault is in use or could not be locked; retry');
    }
  }

  @override
  Future<String?> getItem(String key) => transaction((staged) => staged.getItem(key));

  @override
  Future<void> setItem(String key, String value) =>
      transaction((staged) => staged.setItem(key, value));

  @override
  Future<void> removeItem(String key) => transaction((staged) => staged.removeItem(key));

  @override
  Future<List<String>> allKeys() => transaction((staged) => staged.allKeys());
}

class _StagedFileBackend implements WebStorageBackend {
  _StagedFileBackend(this.data);
  final Map<String, String> data;
  bool active = true;
  bool dirty = false;

  void _checkActive() {
    if (!active) throw StateError('Credential vault transaction has finished');
  }

  @override
  Future<String?> getItem(String key) async {
    _checkActive();
    return data[key];
  }

  @override
  Future<void> setItem(String key, String value) async {
    _checkActive();
    if (data[key] != value) {
      data[key] = value;
      dirty = true;
    }
  }

  @override
  Future<void> removeItem(String key) async {
    _checkActive();
    if (data.remove(key) != null) dirty = true;
  }

  @override
  Future<List<String>> allKeys() async {
    _checkActive();
    return data.keys.toList();
  }
}

typedef _OpenNative = Int32 Function(Pointer<Utf8>, Int32);
typedef _OpenDart = int Function(Pointer<Utf8>, int);
typedef _IntPairNative = Int32 Function(Int32, Int32);
typedef _IntPairDart = int Function(int, int);
typedef _ChmodNative = Int32 Function(Int32, Uint32);
typedef _ChmodDart = int Function(int, int);
typedef _FdNative = Int32 Function(Int32);
typedef _FdDart = int Function(int);

class _PosixVaultLock {
  _PosixVaultLock(this._fd);
  final int _fd;
  static final _libc = DynamicLibrary.process();
  // open is called without O_CREAT, so its optional mode argument is absent.
  static final _open = _libc.lookupFunction<_OpenNative, _OpenDart>('open');
  static final _flock = _libc.lookupFunction<_IntPairNative, _IntPairDart>('flock');
  static final _fchmod = _libc.lookupFunction<_ChmodNative, _ChmodDart>('fchmod');
  static final _close = _libc.lookupFunction<_FdNative, _FdDart>('close');
  static final _fsync = _libc.lookupFunction<_FdNative, _FdDart>('fsync');
  static bool get _darwin => Platform.isMacOS || Platform.isIOS;
  static int get _noFollow => _darwin ? 0x100 : 0x20000;
  static int get _closeOnExec => _darwin ? 0x1000000 : 0x80000;

  static _PosixVaultLock acquire(String path) {
    final nativePath = path.toNativeUtf8();
    int fd;
    try {
      fd = _open(nativePath, 2 /* O_RDWR */ | _noFollow | _closeOnExec);
    } finally {
      malloc.free(nativePath);
    }
    if (fd < 0) throw FileSystemException('Could not safely open vault lock', path);
    if (_fchmod(fd, 0x180 /* 0600 */) != 0 ||
        _flock(fd, 2 /* LOCK_EX */ | 4 /* LOCK_NB */) != 0) {
      _close(fd);
      throw StateError('Credential vault is in use or could not be locked; retry');
    }
    return _PosixVaultLock(fd);
  }

  static void syncDirectory(String path) {
    final nativePath = path.toNativeUtf8();
    int fd;
    try {
      fd = _open(nativePath, _noFollow | _closeOnExec /* O_RDONLY */);
    } finally {
      malloc.free(nativePath);
    }
    if (fd < 0) {
      throw FileSystemException('Vault replaced, but its directory could not be synced', path);
    }
    try {
      if (_fsync(fd) != 0) {
        throw FileSystemException('Vault replaced, but its directory could not be synced', path);
      }
    } finally {
      _close(fd);
    }
  }

  void close() {
    _close(_fd);
  }
}

/// Native password vault using the same AES-256-GCM format as the web vault.
class EncryptedFileStorage extends WebEncryptedStorage {
  EncryptedFileStorage(File file) : super(FileStorageBackend(file));
}

Future<SecureStorage> createEncryptedFileStorage() async {
  final directory = await getApplicationSupportDirectory();
  return EncryptedFileStorage(
    File(p.join(directory.path, 'credential-vault.json')),
  );
}
