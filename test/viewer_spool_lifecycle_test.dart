import 'dart:async';
import 'dart:io';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/log_service.dart';
import 'package:crisp_cloud/services/viewer_spool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late _Clock clock;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('viewer-spool-lifecycle-');
    clock = _Clock();
    LogConfig.clear();
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<ViewerSpool> prepare(
    _Backend source, {
    bool Function()? cancelled,
    void Function(int, int?)? progress,
    int maxBytes = 2 * 1024 * 1024 * 1024,
    Duration overall = const Duration(hours: 6),
    Duration idle = const Duration(minutes: 2),
  }) => createViewerSpool(
    source,
    source.item,
    maxBytes: maxBytes,
    isCancelled: cancelled,
    onProgress: progress,
    overallTimeout: overall,
    inactivityTimeout: idle,
    clock: () => clock.elapsed,
    createTimer: clock.timer,
    temporaryRoot: root.path,
  );

  Future<void> empty() async {
    expect(await root.list().toList(), isEmpty);
    expect(clock.activeTimers, 0);
  }

  test(
    'completed bytes retain their owned copy until explicit close',
    () async {
      final source = _Backend();
      final counts = <int>[];
      source.read = (_) => Stream.fromIterable([
        [1],
        [],
        [2, 3],
      ]);
      final spool = await prepare(
        source,
        progress: (count, total) {
          counts.add(count);
          expect(total, 3);
        },
      );
      expect(await File(spool.path).readAsBytes(), [1, 2, 3]);
      expect(spool.path, endsWith('.txt'));
      expect(counts, [1, 3]);
      expect(source.stats, 2);
      expect(clock.activeTimers, 0);
      expect(await root.exists(), isTrue);
      await spool.close();
      await spool.close();
      await empty();
      expect(await root.exists(), isTrue);
    },
  );

  test(
    'input waits for each written chunk before requesting another',
    () async {
      final source = _Backend();
      final written = <int>[];
      source.read = (_) async* {
        yield [1];
        expect(written, [1]);
        yield [2, 3];
        expect(written, [1, 3]);
      };
      final spool = await prepare(
        source,
        progress: (count, _) => written.add(count),
      );
      expect(await File(spool.path).readAsBytes(), [1, 2, 3]);
      await spool.close();
      await empty();
    },
  );

  test('cancellation interrupts an initial metadata future and observes its late error', () async {
    final metadata = Completer<FileItem?>();
    final source = _Backend()..statResult = (_) => metadata.future;
    var cancelled = false;
    final pending = prepare(source, cancelled: () => cancelled);
    final failed = expectLater(pending, throwsStateError);
    expect(source.stats, 1);
    cancelled = true;
    clock.advance(const Duration(milliseconds: 49));
    expect(clock.activeTimers, 3);
    clock.advance(const Duration(milliseconds: 1));
    await failed;
    expect(source.reads, 0);
    await empty();
    metadata.completeError(StateError('late metadata failure'));
    await _turn();
    expect(source.reads, 0);
    await empty();
  });

  test(
    'observed account loss stays latched after an apparent reconnect',
    () async {
      final metadata = Completer<FileItem?>();
      final source = _Backend()..statResult = (_) => metadata.future;
      final pending = prepare(source);
      final failed = expectLater(
        pending,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'cause',
            contains('source changed'),
          ),
        ),
      );
      source.current = false;
      clock.advance(const Duration(milliseconds: 50));
      source.current = true;
      metadata.complete(source.item);
      await failed;
      expect(source.reads, 0);
      await empty();
    },
  );

  test('default inactivity deadline bounds a hung initial stat', () async {
    final metadata = Completer<FileItem?>();
    final source = _Backend()..statResult = (_) => metadata.future;
    final pending = prepare(source);
    final failed = expectLater(
      pending,
      throwsA(
        isA<TimeoutException>().having(
          (error) => error.duration,
          'inactivity deadline',
          const Duration(minutes: 2),
        ),
      ),
    );
    clock.advance(const Duration(minutes: 2));
    await failed;
    await empty();
    metadata.complete(source.item);
    await _turn();
    expect(source.reads, 0);
  });

  test(
    'a final metadata timeout removes the completed temporary file',
    () async {
      final finalStat = Completer<FileItem?>();
      final reached = Completer<void>();
      final source = _Backend()
        ..statResult = (call) {
          if (call == 1) return Future.value(_file());
          reached.complete();
          return finalStat.future;
        };
      final pending = prepare(source);
      final failed = expectLater(pending, throwsA(isA<TimeoutException>()));
      await reached.future;
      final child = (await root.list().toList()).single as Directory;
      expect(await File('${child.path}/content.txt').readAsBytes(), [1, 2, 3]);
      clock.advance(const Duration(minutes: 2));
      await failed;
      await empty();
      finalStat.complete(source.item);
      await _turn();
      await empty();
    },
  );

  test(
    'cancellation during final stat cannot hand a late spool to its caller',
    () async {
      final finalStat = Completer<FileItem?>();
      final reached = Completer<void>();
      final source = _Backend()
        ..statResult = (call) {
          if (call == 1) return Future.value(_file());
          reached.complete();
          return finalStat.future;
        };
      var cancelled = false;
      final pending = prepare(source, cancelled: () => cancelled);
      final failed = expectLater(pending, throwsStateError);
      await reached.future;
      cancelled = true;
      clock.advance(const Duration(milliseconds: 50));
      await failed;
      finalStat.complete(source.item);
      await _turn();
      await empty();
    },
  );

  test('a stalled first chunk is cancelled without awaiting the provider acknowledgement', () async {
    final listening = Completer<void>(), acknowledgement = Completer<void>();
    var cancellations = 0;
    final stream = StreamController<List<int>>(
      onListen: listening.complete,
      onCancel: () {
        cancellations++;
        return acknowledgement.future;
      },
    );
    final source = _Backend()..read = (_) => stream.stream;
    var cancelled = false;
    final pending = prepare(source, cancelled: () => cancelled);
    final failed = expectLater(pending, throwsStateError);
    await listening.future;
    cancelled = true;
    clock.advance(const Duration(milliseconds: 50));
    await failed;
    expect(cancellations, 1);
    expect(acknowledgement.isCompleted, isFalse);
    await empty();
    stream.add([9, 9, 9]);
    acknowledgement.complete();
    await stream.close();
    await empty();
  });

  test(
    'account loss cancels a stalled stream before another byte arrives',
    () async {
      final listening = Completer<void>();
      var cancellations = 0;
      final stream = StreamController<List<int>>(
        onListen: listening.complete,
        onCancel: () => cancellations++,
      );
      final source = _Backend()..read = (_) => stream.stream;
      final pending = prepare(source);
      final failed = expectLater(pending, throwsStateError);
      await listening.future;
      source.current = false;
      clock.advance(const Duration(milliseconds: 50));
      source.current = true;
      await failed;
      expect(cancellations, 1);
      await stream.close();
      await empty();
    },
  );

  test('inactivity after a written prefix removes the partial file', () async {
    final first = Completer<void>(), listening = Completer<void>();
    var cancellations = 0;
    final stream = StreamController<List<int>>(
      onListen: listening.complete,
      onCancel: () => cancellations++,
    );
    final source = _Backend()..read = (_) => stream.stream;
    final pending = prepare(source, progress: (_, _) => first.complete());
    final failed = expectLater(pending, throwsA(isA<TimeoutException>()));
    await listening.future;
    stream.add([1]);
    await first.future;
    clock.advance(const Duration(minutes: 2));
    await failed;
    expect(cancellations, 1);
    await stream.close();
    await empty();
  });

  test('small continuing writes cannot extend the overall deadline', () async {
    final listening = Completer<void>();
    final written = List.generate(3, (_) => Completer<void>());
    final stream = StreamController<List<int>>(onListen: listening.complete);
    final source = _Backend(item: _file(size: null))
      ..read = (_) => stream.stream;
    final pending = prepare(
      source,
      overall: const Duration(milliseconds: 200),
      idle: const Duration(milliseconds: 100),
      progress: (count, _) => written[count - 1].complete(),
    );
    final failed = expectLater(
      pending,
      throwsA(
        isA<TimeoutException>().having(
          (error) => error.message,
          'deadline type',
          contains('overall'),
        ),
      ),
    );
    await listening.future;
    for (var index = 0; index < written.length; index++) {
      if (index > 0) clock.advance(const Duration(milliseconds: 80));
      stream.add([index]);
      await written[index].future;
    }
    clock.advance(const Duration(milliseconds: 40));
    await failed;
    await stream.close();
    await empty();
  });

  test('empty chunks do not reset inactivity', () async {
    final listening = Completer<void>();
    final stream = StreamController<List<int>>(onListen: listening.complete);
    final source = _Backend()..read = (_) => stream.stream;
    var progress = 0;
    final pending = prepare(
      source,
      idle: const Duration(milliseconds: 100),
      progress: (_, _) => progress++,
    );
    final failed = expectLater(pending, throwsA(isA<TimeoutException>()));
    await listening.future;
    clock.advance(const Duration(milliseconds: 50));
    stream.add([]);
    await _turn();
    clock.advance(const Duration(milliseconds: 50));
    await failed;
    expect(progress, 0);
    await stream.close();
    await empty();
  });

  test(
    'a source error remains primary when cancellation acknowledgement hangs',
    () async {
      final listening = Completer<void>(), acknowledgement = Completer<void>();
      final primary = StateError('source read failed');
      var cancellations = 0;
      final stream = StreamController<List<int>>(
        onListen: listening.complete,
        onCancel: () {
          cancellations++;
          return acknowledgement.future;
        },
      );
      final source = _Backend()..read = (_) => stream.stream;
      final pending = prepare(source);
      final failed = expectLater(pending, throwsA(same(primary)));
      await listening.future;
      stream.addError(primary);
      await failed;
      expect(cancellations, 1);
      expect(acknowledgement.isCompleted, isFalse);
      expect(clock.elapsed, Duration.zero);
      await empty();
      acknowledgement.complete();
      await stream.close();
    },
  );

  test('secondary provider cleanup errors do not replace cancellation or leak raw details', () async {
    final listening = Completer<void>();
    final stream = StreamController<List<int>>(
      onListen: listening.complete,
      onCancel: () => Future<void>.error(
        StateError('https://private.example/?access_token=do-not-log'),
      ),
    );
    final source = _Backend()..read = (_) => stream.stream;
    var cancelled = false;
    final pending = prepare(source, cancelled: () => cancelled);
    final failed = expectLater(
      pending,
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'primary cause',
          'Viewer download cancelled.',
        ),
      ),
    );
    await listening.future;
    cancelled = true;
    clock.advance(const Duration(milliseconds: 50));
    await failed;
    await _turn();
    final entries = LogConfig.entries
        .where((entry) => entry.logger == 'ViewerSpool')
        .toList();
    expect(entries, isNotEmpty);
    expect(entries.every((entry) => entry.error == null), isTrue);
    expect(
      entries.map((entry) => entry.message).join(),
      isNot(contains('do-not-log')),
    );
    await stream.close();
    await empty();
  });

  for (final key in [
    'etag',
    'eTag',
    'version',
    'versionId',
    'revision',
    'rev',
    'cTag',
  ]) {
    test(
      'a provider-owned $key map cannot mutate the captured baseline',
      () async {
        final metadata = <String, dynamic>{key: 'before'};
        final item = _file(metadata: metadata);
        final source = _Backend(item: item);
        source.read = (captured) {
          expect(identical(captured, item), isFalse);
          expect(identical(captured.metadata, metadata), isFalse);
          expect(
            () => captured.metadata![key] = 'retargeted',
            throwsUnsupportedError,
          );
          return Stream.multi((controller) {
            metadata[key] = 'after';
            expect(captured.metadata![key], 'before');
            controller.add([1, 2, 3]);
            controller.close();
          });
        };
        await expectLater(prepare(source), throwsStateError);
        expect(source.stats, 2);
        await empty();
      },
    );
  }

  test(
    'mutable revision values fail before subscribing or creating files',
    () async {
      final source = _Backend(
        item: _file(
          metadata: {
            'rev': ['mutable'],
          },
        ),
      );
      await expectLater(prepare(source), throwsStateError);
      expect(source.reads, 0);
      await empty();
    },
  );

  test(
    'overflow and truncated streams remove their incomplete copies',
    () async {
      for (final input in [
        [1, 2],
        [1, 2, 3, 4],
      ]) {
        final source = _Backend()..read = (_) => Stream.value(input);
        await expectLater(prepare(source, maxBytes: 3), throwsStateError);
        await empty();
      }
    },
  );

  test(
    'unknown source length is bounded while a genuinely empty file succeeds',
    () async {
      final unknown = _Backend(item: _file(size: null))
        ..read = (_) => Stream.value([1, 2, 3, 4]);
      await expectLater(prepare(unknown, maxBytes: 3), throwsStateError);
      await empty();
      final zero = _Backend(item: _file(size: 0))
        ..read = (_) => const Stream.empty();
      final spool = await prepare(zero);
      expect(await File(spool.path).length(), 0);
      await spool.close();
      await empty();
    },
  );

  test(
    'changed file identity, type and storage scope refuse handoff',
    () async {
      for (final after in [
        _file().copyWith(uuid: 'other'),
        _file().copyWith(isFolder: true),
        _file().copyWith(isSymlink: true),
        _file().copyWith(storageId: 'other-account'),
      ]) {
        final source = _Backend()
          ..statResult = (call) => Future.value(call == 1 ? _file() : after);
        await expectLater(prepare(source), throwsStateError);
        await empty();
      }
    },
  );

  test('invalid time and byte bounds do not start source work', () async {
    final source = _Backend();
    await expectLater(prepare(source, maxBytes: 0), throwsArgumentError);
    await expectLater(
      prepare(source, overall: Duration.zero),
      throwsArgumentError,
    );
    await expectLater(
      prepare(source, idle: const Duration(seconds: -1)),
      throwsArgumentError,
    );
    expect(source.stats, 0);
    await empty();
  });

  test('concurrent close callers await the same directory deletion', () async {
    final deleting = Completer<void>(), release = Completer<void>();
    final directories = _Directories(root)
      ..beforeDelete = () async {
        deleting.complete();
        await release.future;
      };
    final spool = await IOOverrides.runZoned(
      () => prepare(_Backend()),
      createDirectory: directories.create,
    );
    final first = spool.close();
    final second = spool.close();
    expect(identical(first, second), isTrue);
    await deleting.future;
    expect(directories.child!.deletions, 1);
    expect(await File(spool.path).exists(), isTrue);
    release.complete();
    await Future.wait([first, second]);
    await empty();
  });

  test('an explicit close failure remains retryable', () async {
    final directories = _Directories(root)..failDeletes = 1;
    final spool = await IOOverrides.runZoned(
      () => prepare(_Backend()),
      createDirectory: directories.create,
    );
    await expectLater(spool.close(), throwsA(isA<FileSystemException>()));
    expect(await File(spool.path).readAsBytes(), [1, 2, 3]);
    await spool.close();
    expect(directories.child!.deletions, 2);
    await empty();
  });

  test('partial cleanup failure preserves the read failure and reports only the owned location', () async {
    final directories = _Directories(root)..failDeletes = 1;
    final primary = StateError('source failed');
    final source = _Backend()
      ..read = (_) async* {
        yield [1];
        throw primary;
      };
    await expectLater(
      IOOverrides.runZoned(
        () => prepare(source),
        createDirectory: directories.create,
      ),
      throwsA(same(primary)),
    );
    final child = directories.child!;
    expect(await child.actual.exists(), isTrue);
    expect(clock.activeTimers, 0);
    final entries = LogConfig.entries
        .where((entry) => entry.logger == 'ViewerSpool')
        .toList();
    expect(entries.any((entry) => entry.message.contains(child.path)), isTrue);
    expect(entries.every((entry) => entry.error == null), isTrue);
    expect(
      entries.map((entry) => entry.message).join(),
      isNot(contains('private-cleanup-detail')),
    );
    await child.actual.delete(recursive: true);
    await empty();
  });
}

FileItem _file({int? size = 3, Map<String, dynamic>? metadata}) => FileItem(
  name: 'note.txt',
  path: '/source/note.txt',
  uuid: 'file-a',
  storageId: 'account-a',
  isFolder: false,
  size: size,
  updatedAt: DateTime.utc(2026, 11, 12),
  metadata: metadata,
);

class _Backend extends Fake implements FileOperationBackend {
  _Backend({FileItem? item}) : item = item ?? _file();
  final FileItem item;
  bool current = true;
  int stats = 0, reads = 0;
  Future<FileItem?> Function(int)? statResult;
  Stream<List<int>> Function(FileItem)? read;
  @override
  bool get isCurrent => current;
  @override
  Future<FileItem?> stat(String path) {
    expect(path, item.path);
    stats++;
    return statResult?.call(stats) ?? Future.value(item);
  }

  @override
  Stream<List<int>> readFile(FileItem file) {
    reads++;
    return read?.call(file) ?? Stream.value([1, 2, 3]);
  }
}

Future<void> _turn() => Future<void>.delayed(Duration.zero);

class _Clock {
  Duration elapsed = Duration.zero;
  final timers = <_ManualTimer>[];
  int get activeTimers => timers.where((timer) => timer.isActive).length;
  Timer timer(Duration duration, void Function() callback) {
    final timer = _ManualTimer(elapsed + duration, callback);
    timers.add(timer);
    return timer;
  }

  void advance(Duration duration) {
    elapsed += duration;
    final due =
        timers.where((timer) => timer.isActive && timer.due <= elapsed).toList()
          ..sort((left, right) => left.due.compareTo(right.due));
    for (final timer in due) {
      timer.fire();
    }
    timers.removeWhere((timer) => !timer.isActive);
  }
}

class _ManualTimer implements Timer {
  _ManualTimer(this.due, this.callback);
  final Duration due;
  final void Function() callback;
  @override
  bool isActive = true;
  @override
  int tick = 0;
  @override
  void cancel() => isActive = false;
  void fire() {
    if (!isActive) return;
    isActive = false;
    tick++;
    callback();
  }
}

class _Directories {
  _Directories(this.root) : _outside = Zone.current;
  final Directory root;
  final Zone _outside;
  _OwnedDirectory? child;
  int failDeletes = 0;
  Future<void> Function()? beforeDelete;

  Directory create(String path) {
    if (path == root.path) return _ParentDirectory(this);
    final prefix = '${root.path}${Platform.pathSeparator}';
    expect(path, startsWith(prefix));
    final name = path.substring(prefix.length);
    expect(name, startsWith('crisp-viewer-'));
    expect(name, isNot(contains(Platform.pathSeparator)));
    // createTemp constructs its result through IOOverrides as well. Make only
    // that owned direct child outside the override, without recursive lookup.
    return _outside.run(() => Directory(path));
  }
}

class _ParentDirectory extends Fake implements Directory {
  _ParentDirectory(this.plan);
  final _Directories plan;
  @override
  String get path => plan.root.path;
  @override
  Future<Directory> createTemp([String? prefix]) async {
    final actual = await plan.root.createTemp(prefix);
    return plan.child = _OwnedDirectory(actual, plan);
  }
}

class _OwnedDirectory extends Fake implements Directory {
  _OwnedDirectory(this.actual, this.plan);
  final Directory actual;
  final _Directories plan;
  int deletions = 0;
  @override
  String get path => actual.path;
  @override
  Future<bool> exists() => actual.exists();
  @override
  Future<Directory> delete({bool recursive = false}) async {
    deletions++;
    await plan.beforeDelete?.call();
    if (plan.failDeletes > 0) {
      plan.failDeletes--;
      throw const FileSystemException('private-cleanup-detail');
    }
    await actual.delete(recursive: recursive);
    return this;
  }
}
