import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart' as codecs;
import 'package:koni_archive/koni_archive.dart' as koni;

import '../models/archive_endpoint.dart';
import 'archive_compression_writer.dart';
import 'archive_hfs_writer.dart';
import 'archive_package_writers.dart';
import 'archive_streaming_writer.dart';
import 'archive_types.dart';
import 'archive_write_model.dart';
import 'archive_writer_service.dart';

const supportsArchiveWriterWorker = true;
const _chunkBytes = 256 * 1024;
const _cancelled = ArchiveViewException('Archive writing was cancelled.');

Future<void> writeArchiveEntriesInWorker(
  ArchiveEndpointFormat format,
  List<ArchiveWriteEntry> entries, {
  required Future<void> Function(List<int>) sink,
  required int maxOutputBytes,
  bool streamed = false,
  ArchiveRewriteInspection? source,
  ArchiveCpioFormat cpioFormat = ArchiveCpioFormat.newc,
  ArchiveCompressionKind? compression,
  bool singlePayload = false,
  Uint8List? gzipHeader,
  int xzCheck = 4,
  int level = 6,
  String? password,
  bool encryptNames = false,
  koni.ArchiveCompression? entryCompression,
  bool Function()? isCancelled,
  Future<void> Function()? checkpoint,
  Future<void>? cancellationFuture,
}) => _WriterHost(
  entries,
  _WriterSpec(
    format: format,
    entries: entries.map(_EntryMetadata.new).toList(growable: false),
    maxOutputBytes: maxOutputBytes,
    streamed: streamed,
    source: source,
    cpioFormat: cpioFormat,
    compression: compression,
    singlePayload: singlePayload,
    gzipHeader: gzipHeader == null ? null : Uint8List.fromList(gzipHeader),
    xzCheck: xzCheck,
    level: level,
    password: password,
    encryptNames: encryptNames,
    entryCompression: entryCompression,
  ),
  sink: sink,
  isCancelled: isCancelled,
  checkpoint: checkpoint,
  cancellationFuture: cancellationFuture,
).run();

Future<void> writeHfsArchiveInWorker(
  List<ArchiveWriteEntry> entries, {
  required Future<void> Function(List<int>) sink,
  required int maxOutputBytes,
  ArchiveRewriteInspection? source,
  String volumeName = 'CrispCloud',
  bool Function()? isCancelled,
  Future<void> Function()? checkpoint,
  Future<void>? cancellationFuture,
}) => _WriterHost(
  entries,
  _WriterSpec(
    entries: entries.map(_EntryMetadata.new).toList(growable: false),
    maxOutputBytes: maxOutputBytes,
    source: source,
    volumeName: volumeName,
  ),
  sink: sink,
  isCancelled: isCancelled,
  checkpoint: checkpoint,
  cancellationFuture: cancellationFuture,
).run();

/// Native protocol fault injection, deliberately absent from the public
/// platform facade. The supplied test entry point receives a Map containing
/// `port` (the host SendPort) and `directory` (its private temporary directory).
Future<void> debugRunArchiveWriterWorker(
  void Function(Object?) entryPoint, {
  required Future<void> Function(List<int>) sink,
}) => _WriterHost(
  const [],
  const _WriterSpec(entries: [], maxOutputBytes: 1024),
  sink: sink,
  entryPoint: entryPoint,
).run();

// Only data crosses at startup. Never send ArchiveWriteEntry itself: its
// captured callback can retain a backend, a widget and the entire application.
class _EntryMetadata {
  _EntryMetadata(ArchiveWriteEntry entry)
    : path = entry.path,
      isDirectory = entry.isDirectory,
      size = entry.size,
      modified = entry.modified,
      mode = entry.mode,
      attributes = entry.attributes;
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime? modified;
  final int? mode;
  final Map<String, Object?> attributes;
}

class _WriterSpec {
  const _WriterSpec({
    this.format,
    required this.entries,
    required this.maxOutputBytes,
    this.streamed = false,
    this.source,
    this.cpioFormat = ArchiveCpioFormat.newc,
    this.compression,
    this.singlePayload = false,
    this.gzipHeader,
    this.xzCheck = 4,
    this.level = 6,
    this.password,
    this.encryptNames = false,
    this.entryCompression,
    this.volumeName = 'CrispCloud',
  });
  final ArchiveEndpointFormat? format; // null explicitly selects raw HFSX.
  final List<_EntryMetadata> entries;
  final int maxOutputBytes;
  final bool streamed;
  final ArchiveRewriteInspection? source;
  final ArchiveCpioFormat cpioFormat;
  final ArchiveCompressionKind? compression;
  final bool singlePayload;
  final Uint8List? gzipHeader;
  final int xzCheck, level;
  final String? password;
  final bool encryptNames;
  final koni.ArchiveCompression? entryCompression;
  final String volumeName;
}

enum _RequestKind { checkpoint, open, read, close, output }

class _Request {
  const _Request(this.id, this.kind, [this.value]);
  final int id;
  final _RequestKind kind;
  final Object? value;
}

class _Reply {
  const _Reply(this.id, this.value);
  final int id;
  final Object? value;
}

class _Ready {
  const _Ready(this.port);
  final SendPort port;
}

class _Done {
  const _Done();
}

class _Failure {
  _Failure(Object error, StackTrace stack)
    : message = error.toString(),
      code = error is ArchiveViewException ? error.code : null,
      stack = stack.toString();
  final String message, stack;
  final ArchiveMessageCode? code;
}

class _Outcome {
  const _Outcome([this.error, this.stack]);
  final Object? error;
  final StackTrace? stack;
}

class _Stopped implements Exception {
  const _Stopped();
}

abstract class _PendingWait {
  void stop();
}

class _Wait<T> implements _PendingWait {
  final result = Completer<T>();
  void complete(T value) {
    if (!result.isCompleted) result.complete(value);
  }

  void fail(Object error, StackTrace stack) {
    if (!result.isCompleted) result.completeError(error, stack);
  }

  @override
  void stop() => fail(const _Stopped(), StackTrace.current);
}

class _CancellationRelay {
  _CancellationRelay(this.finish);
  void Function(Object error, StackTrace? stack)? finish;
  void cancel(void _) => finish?.call(_cancelled, null);
  void fail(Object error, StackTrace stack) => finish?.call(error, stack);
}

class _Input {
  _Input(this.id, this.iterator, this.cancellation);
  final int id;
  final StreamIterator<List<int>> iterator;
  final Completer<void> cancellation;
  bool ended = false;
  void cancel() {
    if (!cancellation.isCompleted) cancellation.complete();
  }
}

class _WriterHost {
  _WriterHost(
    List<ArchiveWriteEntry> entries,
    this.spec, {
    required this.sink,
    this.isCancelled,
    this.checkpoint,
    this.cancellationFuture,
    this.entryPoint = _workerMain,
  }) : entries = List.unmodifiable(entries);
  final List<ArchiveWriteEntry> entries;
  final _WriterSpec spec;
  final Future<void> Function(List<int>) sink;
  final bool Function()? isCancelled;
  final Future<void> Function()? checkpoint;
  final Future<void>? cancellationFuture;
  final void Function(Object?) entryPoint;
  final _done = Completer<_Outcome>();
  final _exited = Completer<void>();
  _PendingWait? _waiting;
  Isolate? _worker;
  SendPort? _port;
  _Input? _input;
  bool _ended = false, _servicing = false;
  int _nextRequest = 0, _nextInput = 0, _written = 0;

  Future<void> run() async {
    validateArchiveWriteEntries(entries);
    if (spec.maxOutputBytes <= 0 ||
        spec.maxOutputBytes > kArchiveStreamingLimit) {
      throw ArgumentError.value(spec.maxOutputBytes, 'maxOutputBytes');
    }
    if (spec.level < 0 || spec.level > 9) {
      throw ArgumentError.value(spec.level, 'level');
    }
    final messages = ReceivePort();
    final subscription = messages.listen(_receive);
    Directory? directory;
    Timer? timer;
    Object? cleanupFailure;
    final cancellation = _CancellationRelay(_finish);
    try {
      if (cancellationFuture != null) {
        unawaited(
          cancellationFuture!.then<void>(
            cancellation.cancel,
            onError: cancellation.fail,
          ),
        );
      }
      if (isCancelled != null) {
        timer = Timer.periodic(const Duration(milliseconds: 25), (_) {
          try {
            if (isCancelled!()) _finish(_cancelled);
          } catch (error, stack) {
            _finish(error, stack);
          }
        });
      }
      await _gate();
      // A killed isolate does not run its finally blocks. All worker-owned
      // codec spools are confined here so the host can remove them after exit.
      directory = await Directory.systemTemp.createTemp(
        'crisp-archive-worker-',
      );
      await _gate();
      _worker = await Isolate.spawn<Object?>(
        entryPoint,
        {'port': messages.sendPort, 'directory': directory.path, 'spec': spec},
        onError: messages.sendPort,
        onExit: messages.sendPort,
        errorsAreFatal: true,
        debugName: 'CrispCloud archive writer',
      );
      // Cancellation can arrive while spawn is awaiting its acknowledgement.
      if (_ended) _worker!.kill(priority: Isolate.immediate);
      await _done.future;
    } catch (error, stack) {
      if (error is! _Stopped) _finish(error, stack);
    } finally {
      // A never-completed caller cancellation Future must not retain a finished
      // job's backend closures, passwords or entries through its listener.
      cancellation.finish = null;
      timer?.cancel();
      _cancelInput();
      if (_worker != null) {
        _worker!.kill(priority: Isolate.immediate);
        await _exited.future;
      }
      await subscription.cancel();
      messages.close();
      if (directory != null) {
        try {
          await directory.delete(recursive: true);
        } catch (error) {
          cleanupFailure = error;
        }
      }
    }
    final outcome = await _done.future;
    if (outcome.error != null) {
      Error.throwWithStackTrace(
        outcome.error!,
        outcome.stack ?? StackTrace.current,
      );
    }
    if (cleanupFailure != null) throw cleanupFailure;
  }

  void _finish([Object? error, StackTrace? stack]) {
    if (_ended) return;
    _ended = true;
    _waiting?.stop();
    _cancelInput();
    _worker?.kill(priority: Isolate.immediate);
    _done.complete(_Outcome(error, stack));
  }

  void _cancelInput() {
    final input = _input;
    _input = null;
    if (input == null) return;
    input.cancel();
    // A misbehaving provider's cancellation Future must not keep the codec
    // worker alive forever. No subsequent pull or output is accepted.
    unawaited(
      input.iterator.cancel().then<void>((_) {}, onError: (Object _) {}),
    );
  }

  Future<T> _race<T>(Future<T> action) async {
    if (_waiting != null) throw StateError('Concurrent archive host waits.');
    final waiting = _Wait<T>();
    // Only the small waiter is retained by a stalled provider Future. Unlike
    // repeatedly racing against one cancellation Future, completed chunk reads
    // do not accumulate a listener for the entire lifetime of a large job.
    unawaited(action.then<void>(waiting.complete, onError: waiting.fail));
    _waiting = waiting;
    if (_ended) waiting.stop();
    try {
      return await waiting.result.future;
    } finally {
      if (identical(_waiting, waiting)) _waiting = null;
    }
  }

  Future<void> _gate() async {
    if (_ended) throw const _Stopped();
    if (isCancelled?.call() ?? false) throw _cancelled;
    final callback = checkpoint;
    if (callback != null) await _race(Future<void>.sync(callback));
    if (_ended) throw const _Stopped();
    if (isCancelled?.call() ?? false) throw _cancelled;
  }

  void _receive(Object? message) {
    if (message == null) {
      if (!_exited.isCompleted) _exited.complete();
      if (!_ended) {
        _finish(
          const ArchiveViewException(
            'The archive writer exited before completing.',
          ),
        );
      }
      return;
    }
    if (_ended) return;
    if (message is _Ready && _port == null && !_servicing) {
      _port = message.port;
      return;
    }
    if (message is _Failure) {
      _finish(
        ArchiveViewException(message.message, code: message.code),
        StackTrace.fromString(message.stack),
      );
      return;
    }
    if (message is List && message.length == 2) {
      // Isolate.onError, including failures outside the codec's catch block.
      _finish(
        ArchiveViewException('The archive writer failed: ${message[0]}'),
        StackTrace.fromString('${message[1]}'),
      );
      return;
    }
    if (message is _Done && _port != null && !_servicing && _input == null) {
      _finish();
      return;
    }
    if (message is! _Request ||
        _port == null ||
        _servicing ||
        message.id != _nextRequest++) {
      _finish(
        const ArchiveViewException('Invalid archive writer protocol message.'),
      );
      return;
    }
    _servicing = true;
    unawaited(_handle(message));
  }

  Future<void> _handle(_Request request) async {
    try {
      await _gate();
      Object? reply;
      switch (request.kind) {
        case _RequestKind.checkpoint:
          if (request.value != null) {
            throw const FormatException('Invalid checkpoint.');
          }
        case _RequestKind.open:
          final index = request.value;
          if (_input != null ||
              index is! int ||
              index < 0 ||
              index >= entries.length ||
              entries[index].isDirectory) {
            throw const FormatException('Invalid archive input request.');
          }
          final cancellation = Completer<void>();
          final input = _Input(
            _nextInput++,
            StreamIterator(
              entries[index].openRead(
                chunkSize: _chunkBytes,
                cancellationFuture: cancellation.future,
              ),
            ),
            cancellation,
          );
          _input = input;
          reply = input.id;
        case _RequestKind.read:
          final input = _input;
          if (input == null || input.id != request.value || input.ended) {
            throw const FormatException('Invalid archive input pull.');
          }
          if (await _race(input.iterator.moveNext())) {
            final chunk = input.iterator.current;
            if (chunk.length > _chunkBytes) {
              throw const FormatException('Unbounded archive input message.');
            }
            reply = TransferableTypedData.fromList([Uint8List.fromList(chunk)]);
          } else {
            input.ended = true;
          }
        case _RequestKind.close:
          final input = _input;
          if (input == null || input.id != request.value) {
            throw const FormatException('Invalid archive input close.');
          }
          input.cancel();
          await _race(input.iterator.cancel());
          _input = null;
        case _RequestKind.output:
          final value = request.value;
          if (value is! TransferableTypedData) {
            throw const FormatException('Invalid archive output message.');
          }
          final chunk = value.materialize().asUint8List();
          if (chunk.isEmpty || chunk.length > _chunkBytes) {
            throw const FormatException('Unbounded archive output message.');
          }
          if (chunk.length > spec.maxOutputBytes - _written) {
            throw const ArchiveViewException(
              'The packed archive exceeds its output limit.',
            );
          }
          await _race(Future<void>.sync(() => sink(chunk)));
          _written += chunk.length;
      }
      await _gate();
      _port!.send(_Reply(request.id, reply));
    } catch (error, stack) {
      if (error is! _Stopped) _finish(error, stack);
    } finally {
      _servicing = false;
    }
  }
}

class _WorkerChannel {
  _WorkerChannel(this.host) {
    _subscription = _messages.listen((Object? message) {
      final pending = _pending;
      if (message is! _Reply || pending == null || message.id != _pendingId) {
        throw const FormatException('Invalid archive writer response.');
      }
      _pending = null;
      pending.complete(message.value);
    });
    host.send(_Ready(_messages.sendPort));
  }
  final SendPort host;
  final _messages = ReceivePort();
  late final StreamSubscription<Object?> _subscription;
  Completer<Object?>? _pending;
  int _next = 0, _pendingId = -1;

  Future<Object?> request(_RequestKind kind, [Object? value]) {
    if (_pending != null) {
      throw StateError('Concurrent archive writer requests.');
    }
    final reply = Completer<Object?>();
    _pending = reply;
    _pendingId = _next++;
    host.send(_Request(_pendingId, kind, value));
    return reply.future;
  }

  Future<void> checkpoint() async => request(_RequestKind.checkpoint);

  Stream<List<int>> read(int index) async* {
    final id = await request(_RequestKind.open, index);
    if (id is! int) {
      throw const FormatException('Invalid archive input handle.');
    }
    try {
      while (true) {
        final value = await request(_RequestKind.read, id);
        if (value == null) break;
        if (value is! TransferableTypedData) {
          throw const FormatException('Invalid archive input response.');
        }
        final bytes = value.materialize().asUint8List();
        if (bytes.length > _chunkBytes) {
          throw const FormatException('Unbounded archive input response.');
        }
        yield bytes;
      }
    } finally {
      await request(_RequestKind.close, id);
    }
  }

  Future<void> emit(List<int> bytes) async {
    if (bytes is! Uint8List && bytes.any((byte) => byte < 0 || byte > 255)) {
      throw const ArchiveViewException(
        'The archive writer emitted invalid bytes.',
      );
    }
    for (var offset = 0; offset < bytes.length; offset += _chunkBytes) {
      final end = offset + _chunkBytes < bytes.length
          ? offset + _chunkBytes
          : bytes.length;
      final chunk = bytes is Uint8List
          ? Uint8List.sublistView(bytes, offset, end)
          : Uint8List.fromList(bytes.sublist(offset, end));
      await request(
        _RequestKind.output,
        TransferableTypedData.fromList([chunk]),
      );
    }
  }

  Future<void> close() async {
    await _subscription.cancel();
    _messages.close();
  }
}

void _workerMain(Object? message) async {
  final start = message as Map;
  final host = start['port'] as SendPort;
  final channel = _WorkerChannel(host);
  try {
    await IOOverrides.runZoned(() async {
      final spec = start['spec'] as _WriterSpec;
      await channel.checkpoint();
      final entries = [
        for (var index = 0; index < spec.entries.length; index++)
          _workerEntry(spec.entries[index], index, channel),
      ];
      if (spec.format == null) {
        await writeHfsArchive(
          entries,
          sink: channel.emit,
          source: spec.source,
          maxOutputBytes: spec.maxOutputBytes,
          volumeName: spec.volumeName,
        );
      } else if (spec.entryCompression != null) {
        await _writeCreation(spec, entries, channel);
      } else if (spec.streamed) {
        if (spec.cpioFormat != ArchiveCpioFormat.newc ||
            spec.singlePayload && spec.format != ArchiveEndpointFormat.gzip ||
            spec.compression != null &&
                !(spec.compression == ArchiveCompressionKind.gzip &&
                    (spec.format == ArchiveEndpointFormat.gzip ||
                        spec.format == ArchiveEndpointFormat.tarGzip))) {
          throw const ArchiveViewException(
            'The streamed writer options do not match its format.',
          );
        }
        await writeStreamingArchiveEntries(
          spec.format!,
          entries,
          sink: channel.emit,
          source: spec.source,
          maxOutputBytes: spec.maxOutputBytes,
          gzipHeader: spec.gzipHeader,
          level: spec.level,
          password: spec.password,
          encryptNames: spec.encryptNames,
        );
      } else {
        await writeArchiveEntries(
          spec.format!,
          entries,
          sink: channel.emit,
          source: spec.source,
          maxOutputBytes: spec.maxOutputBytes,
          cpioFormat: spec.cpioFormat,
          compression: spec.compression,
          singlePayload: spec.singlePayload,
          gzipHeader: spec.gzipHeader,
          xzCheck: spec.xzCheck,
          level: spec.level,
          password: spec.password,
          encryptNames: spec.encryptNames,
        );
      }
      await channel.checkpoint();
    }, getSystemTempDirectory: () => Directory(start['directory'] as String));
    host.send(const _Done());
  } catch (error, stack) {
    host.send(_Failure(error, stack));
  } finally {
    await channel.close();
  }
}

ArchiveWriteEntry _workerEntry(
  _EntryMetadata entry,
  int index,
  _WorkerChannel channel,
) => ArchiveWriteEntry(
  path: entry.path,
  isDirectory: entry.isDirectory,
  size: entry.size,
  modified: entry.modified,
  mode: entry.mode,
  attributes: entry.attributes,
  readChunks: entry.isDirectory ? null : () => channel.read(index),
);

// Preserve the existing creation dialog's selected ZIP Store/Deflate and
// 7z Store/Deflate/LZMA2 methods. The generic buffered rewrite dispatcher has
// intentionally different defaults and must not silently replace that choice.
Future<void> _writeCreation(
  _WriterSpec spec,
  List<ArchiveWriteEntry> entries,
  _WorkerChannel channel,
) async {
  final zipFormat = spec.format == ArchiveEndpointFormat.zip;
  if (spec.streamed ||
      spec.source != null ||
      !(zipFormat || spec.format == ArchiveEndpointFormat.sevenZip) ||
      spec.compression != null ||
      spec.singlePayload ||
      spec.cpioFormat != ArchiveCpioFormat.newc ||
      spec.gzipHeader != null ||
      !const [
        koni.ArchiveCompression.stored,
        koni.ArchiveCompression.deflate,
        koni.ArchiveCompression.lzma2,
      ].contains(spec.entryCompression) ||
      zipFormat && spec.entryCompression == koni.ArchiveCompression.lzma2 ||
      spec.encryptNames && (zipFormat || spec.password == null) ||
      spec.maxOutputBytes > 256 * 1024 * 1024) {
    throw const ArchiveViewException(
      'Unsupported buffered archive creation options.',
    );
  }
  validateArchiveWriteEntries(entries);
  final memory = _BoundedMemory(spec.maxOutputBytes);
  final output = _MemorySink(memory);
  final zip = zipFormat
      ? codecs.ZipEncoder(password: spec.password, streamed: true)
      : null;
  final writer = zip == null
      ? koni.Archive.create(
          output,
          format: const koni.SevenZWriteFormat(),
          options: koni.ArchiveWriteOptions(
            compression: spec.entryCompression!,
            password: spec.password,
            encryptHeader: spec.encryptNames,
          ),
        )
      : null;
  zip?.startEncode(memory, level: spec.level);
  var total = 0;
  for (final entry in entries) {
    await channel.checkpoint();
    total += entry.size;
    if (total > 256 * 1024 * 1024) {
      throw const ArchiveViewException('Archive contents exceed 256 MiB.');
    }
    final bytes = entry.isDirectory ? null : await entry.read();
    if (zip != null) {
      final file = bytes == null
          ? codecs.ArchiveFile.directory('${entry.path}/')
          : codecs.ArchiveFile.bytes(entry.path, bytes);
      if (entry.modified != null) {
        file.lastModTime = entry.modified!.millisecondsSinceEpoch ~/ 1000;
      }
      if (entry.mode != null) file.mode = entry.mode!;
      file.compression = spec.entryCompression == koni.ArchiveCompression.stored
          ? codecs.CompressionType.none
          : codecs.CompressionType.deflate;
      final body = zip.addHeader(file);
      if (body != null) {
        try {
          while (body.step()) {
            await channel.checkpoint();
          }
          body.finish();
        } catch (_) {
          body.cancel();
          rethrow;
        }
      }
    } else {
      final metadata = koni.ArchiveEntrySpec(
        path: entry.path,
        type: entry.isDirectory
            ? koni.ArchiveEntryType.directory
            : koni.ArchiveEntryType.file,
        modified: entry.modified,
        posixMode: entry.mode,
      );
      if (bytes == null) {
        await writer!.addEntry(metadata);
      } else {
        await writer!.addBytes(metadata, bytes);
      }
    }
  }
  await channel.checkpoint();
  if (zip != null) {
    zip.endEncode();
  } else {
    await writer!.close();
  }
  await channel.emit(memory.getBytes());
}

class _BoundedMemory extends codecs.OutputMemoryStream {
  _BoundedMemory(this.limit);
  final int limit;
  void _allow(int count) {
    if (count < 0 || count > limit - length) {
      throw const ArchiveViewException(
        'The packed archive exceeds its output limit.',
      );
    }
  }

  @override
  void writeByte(int value) {
    _allow(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _allow(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(codecs.InputStream stream) {
    _allow(stream.length);
    super.writeStream(stream);
  }

  @override
  void reserve(int total) {
    if (total > limit) {
      throw const ArchiveViewException(
        'The packed archive exceeds its output limit.',
      );
    }
    super.reserve(total);
  }
}

class _MemorySink implements koni.ByteSink {
  _MemorySink(this.memory);
  final _BoundedMemory memory;
  @override
  int get length => memory.length;
  @override
  Future<void> add(Uint8List bytes) async => memory.writeBytes(bytes);
  @override
  Future<void> close() async {}
}
