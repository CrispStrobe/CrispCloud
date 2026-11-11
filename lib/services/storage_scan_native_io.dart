import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import '../models/storage_analysis.dart';

/// A directory-sized unit of work keeps synchronous metadata calls away from
/// the UI isolate. The caller holds its security scope until this completes.
/// Using a worker avoids a round trip through Dart's async I/O scheduler for
/// every type/stat check. No file contents or provider credentials are passed.
Future<StorageScanDirectory> readNativeStorageScanDirectory(String path) =>
    Isolate.run(() => _readDirectory(path));

/// One metadata worker for one scan. Only paths and metadata cross the isolate
/// boundary; the caller keeps platform access scopes on the originating isolate.
/// Closing drains submitted reads before stopping the worker, so an access scope
/// is never released while its filesystem operation is still running.
class NativeStorageScanWorker {
  NativeStorageScanWorker._() {
    _events.listen(_onEvent);
  }

  final ReceivePort _events = ReceivePort();
  final Completer<SendPort?> _ready = Completer<SendPort?>();
  final Completer<void> _exited = Completer<void>();
  final Map<int, Completer<StorageScanDirectory>> _pending = {};
  Isolate? _isolate;
  SendPort? _commands;
  Object? _failure;
  StackTrace? _failureStack;
  int _nextRequest = 0;
  bool _closing = false;
  Future<void>? _closeFuture;

  static Future<NativeStorageScanWorker> start() async {
    final worker = NativeStorageScanWorker._();
    try {
      worker._isolate = await Isolate.spawn<SendPort>(
        _runStorageScanWorker,
        worker._events.sendPort,
        onError: worker._events.sendPort,
        onExit: worker._events.sendPort,
        errorsAreFatal: true,
        debugName: 'Storage metadata scan',
      );
      // A failed startup completes with null instead of an unhandled error
      // while Isolate.spawn itself is still being awaited.
      if (await worker._ready.future == null) {
        Error.throwWithStackTrace(
          worker._failure ?? StateError('The metadata worker could not start.'),
          worker._failureStack ?? StackTrace.current,
        );
      }
      return worker;
    } catch (_) {
      worker._isolate?.kill(priority: Isolate.immediate);
      worker._events.close();
      rethrow;
    }
  }

  Future<StorageScanDirectory> readDirectory(String path) {
    if (_closing || _exited.isCompleted || _failure != null) {
      return Future.error(StateError('The metadata worker is closed.'));
    }
    final id = _nextRequest++;
    final result = Completer<StorageScanDirectory>();
    _pending[id] = result;
    _commands!.send((id, path));
    return result.future;
  }

  Future<void> close() => _closeFuture ??= _shutdown();

  Future<void> _shutdown() async {
    _closing = true;
    // Retain any caller's original read error while still finishing cleanup.
    await Future.wait(
      _pending.values.map(
        (pending) => pending.future.then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {},
        ),
      ),
    );
    if (_exited.isCompleted) return;
    _commands!.send(null);
    await _exited.future;
  }

  void _onEvent(dynamic message) {
    if (message is SendPort) {
      _commands = message;
      if (!_ready.isCompleted) _ready.complete(message);
    } else if (message case (
      final int id,
      final StorageScanDirectory? result,
      final String? error,
      final String? stack,
    )) {
      final pending = _pending.remove(id);
      if (pending == null) return;
      if (result != null) {
        pending.complete(result);
      } else {
        pending.completeError(
          RemoteError(error ?? 'Could not read the directory.', stack ?? ''),
        );
      }
    } else if (message is List && message.length == 2) {
      _fail(
        RemoteError(message[0].toString(), message[1].toString()),
        StackTrace.fromString(message[1].toString()),
      );
    } else if (message == null) {
      if (!_closing || _pending.isNotEmpty || !_ready.isCompleted) {
        _fail(StateError('The metadata worker exited unexpectedly.'));
      }
      if (!_ready.isCompleted) _ready.complete(null);
      if (!_exited.isCompleted) _exited.complete();
      _events.close();
    }
  }

  void _fail(Object error, [StackTrace? stack]) {
    _failure ??= error;
    _failureStack ??= stack ?? StackTrace.current;
    if (!_ready.isCompleted) _ready.complete(null);
    for (final pending in _pending.values) {
      pending.completeError(_failure!, _failureStack);
    }
    _pending.clear();
  }
}

void _runStorageScanWorker(SendPort events) {
  final commands = ReceivePort();
  events.send(commands.sendPort);
  commands.listen((dynamic command) {
    if (command == null) {
      commands.close();
      return;
    }
    final (int id, String path) = command as (int, String);
    try {
      events.send((id, _readDirectory(path), null, null));
    } catch (error, stack) {
      // A failed directory must not discard healthy siblings or end the scan.
      events.send((id, null, error.toString(), stack.toString()));
    }
  });
}

StorageScanDirectory _readDirectory(String path) {
  final entries = <FileItem>[];
  final issues = <StorageScanIssue>[];
  var complete = true;
  // Keep per-directory errors bounded even before the global diagnostic limit
  // is applied. The summary preserves the fact that more entries failed.
  var suppressed = 0;
  void failed(String entryPath, Object error) {
    complete = false;
    if (issues.length < 20) {
      issues.add(
        StorageScanIssue(
          path: entryPath,
          code: StorageScanIssueCode.invalidEntry,
          message: 'Could not inspect an entry: $error',
        ),
      );
    } else {
      suppressed++;
    }
  }

  // Do not follow a root that was replaced by a link after the caller's stat.
  if (FileSystemEntity.typeSync(path, followLinks: false) !=
      FileSystemEntityType.directory) {
    throw FileSystemException('The directory is no longer available.', path);
  }
  // Ordinary POSIX enumeration preserves this already-normalized parent. A
  // direct child component therefore needs no second full-path normalization.
  // Windows aliases, roots, leading double slashes, trailing separators and
  // noncanonical parents keep the original path-library behavior.
  final directChildPrefix =
      !Platform.isWindows &&
          p.context.style == p.Style.posix &&
          p.isAbsolute(path) &&
          path != '/' &&
          !path.startsWith('//') &&
          !path.endsWith('/') &&
          p.normalize(path) == path
      ? '$path/'
      : null;
  for (final entity in Directory(path).listSync(followLinks: false)) {
    var entryPath = entity.path;
    String? name;
    if (directChildPrefix != null && entryPath.startsWith(directChildPrefix)) {
      final component = entryPath.substring(directChildPrefix.length);
      if (component.isNotEmpty &&
          component != '.' &&
          component != '..' &&
          !component.contains('/') &&
          !component.contains(r'\') &&
          !component.contains(':') &&
          !component.contains('\u0000')) {
        name = component;
      }
    }
    if (name == null) {
      entryPath = p.normalize(entryPath);
      name = p.basename(entryPath);
    }
    if (entity is Link) {
      // A disk-usage scan needs to identify links, not resolve their targets.
      entries.add(
        FileItem(name: name, path: entryPath, isFolder: false, isSymlink: true),
      );
      continue;
    }
    final listedType = entity is Directory
        ? FileSystemEntityType.directory
        : FileSystemEntityType.file;
    try {
      final info = FileStat.statSync(entryPath);
      // Directory enumeration already supplied the initial no-follow type.
      // Check again after stat so a new link cannot contribute target bytes.
      if (info.type != listedType ||
          FileSystemEntity.typeSync(entryPath, followLinks: false) !=
              listedType) {
        throw FileSystemException(
          'The entry changed while its metadata was read.',
          entryPath,
        );
      }
      entries.add(
        FileItem(
          name: name,
          path: entryPath,
          isFolder: listedType == FileSystemEntityType.directory,
          isSymlink: false,
          size: listedType == FileSystemEntityType.file ? info.size : null,
          updatedAt: info.modified,
        ),
      );
    } catch (error) {
      failed(entryPath, error);
      // Keep known names visible, but never invent a size for failed metadata.
      // Unknown folders are rechecked by the reader before descent.
      entries.add(
        FileItem(
          name: name,
          path: entryPath,
          isFolder: listedType == FileSystemEntityType.directory,
        ),
      );
    }
  }
  if (suppressed > 0) {
    issues.add(
      StorageScanIssue(
        path: path,
        code: StorageScanIssueCode.incompleteListing,
        message: '$suppressed additional entries could not be inspected.',
      ),
    );
  }
  if (FileSystemEntity.typeSync(path, followLinks: false) !=
      FileSystemEntityType.directory) {
    // A changed root invalidates the entire listing: its apparent children
    // could have come from a replacement link target under the same names.
    throw FileSystemException(
      'The directory changed during enumeration.',
      path,
    );
  }
  return StorageScanDirectory(
    entries: entries,
    issues: issues,
    isComplete: complete,
  );
}
