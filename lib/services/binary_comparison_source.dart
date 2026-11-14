import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:madedit2_hex/hex_document.dart';

import '../models/file_item.dart';
import 'file_operation_service.dart';
import 'hex_file_source.dart';
import 'transfer_recovery_service.dart';
import 'transfer_spool.dart';

const kBinaryComparisonNativeInputLimit = 8 * 1024 * 1024 * 1024;
const kBinaryComparisonWebInputLimit = 32 * 1024 * 1024;

/// Per-input allowances. A comparison owns at most two captured inputs.
/// These ceilings do not enlarge archive, editor, or transfer allowances.
class BinaryComparisonLimits {
  const BinaryComparisonLimits({
    this.maxBytes = kIsWeb
        ? kBinaryComparisonWebInputLimit
        : kBinaryComparisonNativeInputLimit,
    this.maxChunks = 1024 * 1024,
    this.maxEmptyChunks = 1024,
    this.overallTimeout = const Duration(minutes: 30),
    this.inactivityTimeout = const Duration(seconds: 30),
  });

  final int maxBytes, maxChunks, maxEmptyChunks;
  final Duration overallTimeout, inactivityTimeout;

  void validate() {
    final ceiling = kIsWeb
        ? kBinaryComparisonWebInputLimit
        : kBinaryComparisonNativeInputLimit;
    if (maxBytes < 1 || maxBytes > ceiling) {
      throw RangeError.range(maxBytes, 1, ceiling, 'maxBytes');
    }
    if (maxChunks < 1 || maxEmptyChunks < 0) {
      throw ArgumentError(
        'Comparison chunk allowances must be finite and valid.',
      );
    }
    if (overallTimeout <= Duration.zero || inactivityTimeout <= Duration.zero) {
      throw ArgumentError('Comparison time limits must be positive.');
    }
  }
}

class BinaryComparisonLimitExceeded extends StateError {
  BinaryComparisonLimitExceeded(super.message);
}

class BinaryComparisonSourceChanged extends StateError {
  BinaryComparisonSourceChanged(super.message);
}

class BinaryComparisonCancelled extends StateError {
  BinaryComparisonCancelled() : super('Comparison cancelled.');
}

/// An owned read-only copy whose length and SHA-256 matched two complete reads.
///
/// Native captures use private temporary disk storage; browser captures use a
/// bounded memory copy. Navigation never reads live source bytes. Source/account
/// metadata is checked separately and is never treated as a content hash.
/// Matching reads do not establish an atomic source snapshot on an unversioned
/// provider, or a simultaneous snapshot of the two comparison inputs.
class BinaryComparisonSnapshot {
  BinaryComparisonSnapshot._(
    this.backend,
    this._identity,
    this.file,
    this._source,
    this._spool,
    this.sha256Digest,
    this.limits,
  );

  final FileOperationBackend backend;
  final Object _identity;
  final FileItem file;
  final HexByteSource _source;
  final TransferSpool? _spool;
  final String sha256Digest;
  final BinaryComparisonLimits limits;
  bool _closed = false;
  Future<void>? _closing;

  int get length => _source.length;
  bool get isClosed => _closed;

  static Future<BinaryComparisonSnapshot> capture(
    FileOperationBackend backend,
    FileItem file, {
    BinaryComparisonLimits limits = const BinaryComparisonLimits(),
    bool Function()? isCancelled,
    void Function(int bytes)? onProgress,
  }) async {
    limits.validate();
    final path = file.path;
    if (path == null ||
        path.isEmpty ||
        file.isFolder ||
        file.isSymlink == true) {
      throw ArgumentError(
        'Binary comparison requires a regular file with a path.',
      );
    }
    final identity = backend.identity;
    void checkSource() {
      if (!backend.isCurrent || backend.identity != identity) {
        throw BinaryComparisonSourceChanged('A comparison source changed.');
      }
      if (isCancelled?.call() ?? false) throw BinaryComparisonCancelled();
    }

    final guard = _ComparisonGuard(limits, checkSource);
    TransferSpool? spool;
    HexByteSource? source;
    try {
      // Copy identity metadata: providers are allowed to reuse their FileItem
      // maps. Mutating such a map must not mutate the captured version token.
      final selected = _freeze(file);
      final before = _requireVersion(
        selected,
        await guard.wait(() => backend.stat(path)),
        path,
      );
      if (before.size != null &&
          (before.size! < 0 || before.size! > limits.maxBytes)) {
        throw BinaryComparisonLimitExceeded(
          'File exceeds the ${limits.maxBytes} byte comparison input limit.',
        );
      }
      final firstDigest = _DigestSink();
      final digest = sha256.startChunkedConversion(firstDigest);
      var received = 0;
      Stream<List<int>> input() async* {
        try {
          await for (final part in _boundedInput(
            backend.readFile(before),
            guard,
            limits,
            expectedLength: before.size,
          )) {
            digest.add(part);
            received += part.length;
            onProgress?.call(received);
            guard.check();
            yield part;
          }
        } finally {
          digest.close();
        }
      }

      if (kIsWeb) {
        final bytes = BytesBuilder(copy: false);
        await for (final part in input()) {
          bytes.add(part);
        }
        source = MemoryHexByteSource(bytes.takeBytes());
      } else {
        // Await storage ownership before cancelling/cleaning it: racing this
        // allocation against cancellation could orphan a late-created spool.
        spool = await createTransferSpool(
          input(),
          expectedLength: before.size,
          maxBytes: limits.maxBytes,
          checkpoint: () async => guard.check(),
        );
        guard.check();
        source = await openHexFileSource(spool.localPath!);
      }
      guard.check();
      if (source.length != received) {
        throw BinaryComparisonSourceChanged(
          'The captured file length changed.',
        );
      }
      final afterCopy = _requireVersion(
        before,
        await guard.wait(() => backend.stat(path)),
        path,
      );
      _requireLength(afterCopy, received);
      final secondDigest = _DigestSink();
      final verifier = sha256.startChunkedConversion(secondDigest);
      try {
        await for (final part in _boundedInput(
          backend.readFile(afterCopy),
          guard,
          limits,
          expectedLength: received,
        )) {
          verifier.add(part);
        }
      } finally {
        verifier.close();
      }
      final afterVerify = _requireVersion(
        afterCopy,
        await guard.wait(() => backend.stat(path)),
        path,
      );
      _requireLength(afterVerify, received);
      guard.check();
      if (firstDigest.value == null ||
          firstDigest.value != secondDigest.value) {
        throw BinaryComparisonSourceChanged(
          'The source bytes changed while capturing the comparison. Compare again.',
        );
      }
      return BinaryComparisonSnapshot._(
        backend,
        identity,
        afterVerify,
        source,
        spool,
        firstDigest.value!,
        limits,
      );
    } catch (_) {
      try {
        if (source != null) await closeHexFileSource(source);
      } finally {
        await spool?.dispose();
      }
      rethrow;
    } finally {
      guard.dispose();
    }
  }

  void _check(bool Function()? isCancelled) {
    if (_closed) throw StateError('The comparison snapshot is closed.');
    if (!backend.isCurrent || backend.identity != _identity) {
      throw BinaryComparisonSourceChanged('A comparison source changed.');
    }
    if (isCancelled?.call() ?? false) throw BinaryComparisonCancelled();
  }

  /// Detects available metadata/account changes without rereading live bytes.
  Future<void> validate({bool Function()? isCancelled}) async {
    final guard = _ComparisonGuard(limits, () => _check(isCancelled));
    try {
      final current = _requireVersion(
        file,
        await guard.wait(() => backend.stat(file.path!)),
        file.path!,
      );
      _requireLength(current, length);
      guard.check();
    } finally {
      guard.dispose();
    }
  }

  /// The stream is bounded by the captured length and uses owned 64 KiB parts.
  Stream<List<int>> readRange(
    int offset, {
    bool Function()? isCancelled,
  }) async* {
    if (offset < 0 || offset > length) {
      throw RangeError.range(offset, 0, length, 'offset');
    }
    final guard = _ComparisonGuard(limits, () => _check(isCancelled));
    var position = offset;
    var sinceYield = 0;
    try {
      while (position < length) {
        final count = (length - position).clamp(0, 64 * 1024);
        final part = await guard.wait(() => _source.read(position, count));
        if (part.length != count) {
          throw BinaryComparisonSourceChanged(
            'The captured file became shorter.',
          );
        }
        guard.progress();
        position += count;
        sinceYield += count;
        yield Uint8List.fromList(part);
        if (sinceYield >= 1024 * 1024) {
          await Future<void>.delayed(Duration.zero);
          sinceYield = 0;
        }
        guard.check();
      }
    } finally {
      guard.dispose();
    }
  }

  Future<Uint8List> read(
    int offset,
    int count, {
    bool Function()? isCancelled,
  }) async {
    if (offset < 0 || count < 0 || offset > length || count > length - offset) {
      throw RangeError('Invalid comparison snapshot byte range.');
    }
    if (count > 64 * 1024) {
      throw BinaryComparisonLimitExceeded(
        'A comparison window exceeds 64 KiB.',
      );
    }
    final guard = _ComparisonGuard(limits, () => _check(isCancelled));
    try {
      final bytes = await guard.wait(() => _source.read(offset, count));
      if (bytes.length != count) {
        throw BinaryComparisonSourceChanged(
          'The captured file became shorter.',
        );
      }
      guard.check();
      // MemoryHexByteSource may return a view. Never expose mutable snapshot
      // storage to a caller that can subsequently change the comparison.
      return Uint8List.fromList(bytes);
    } finally {
      guard.dispose();
    }
  }

  /// Idempotent; queued native positional reads complete before file removal.
  Future<void> close() {
    if (_closing != null) return _closing!;
    _closed = true;
    return _closing = () async {
      try {
        await closeHexFileSource(_source);
      } finally {
        await _spool?.dispose();
      }
    }();
  }
}

FileItem _freeze(FileItem item) {
  if (item.metadata == null) return item;
  final metadata = Map<String, dynamic>.of(item.metadata!);
  // These are the tokens consumed by sameTransferVersion. Normalize just
  // their observed values; unrelated provider metadata can contain opaque
  // handles or cyclic objects and must not be recursively traversed.
  for (final key in ['version', 'versionId', 'eTag', 'etag', 'rev', 'cTag']) {
    if (metadata[key] != null) metadata[key] = metadata[key].toString();
  }
  return item.copyWith(metadata: Map<String, dynamic>.unmodifiable(metadata));
}

void _requireLength(FileItem file, int expected) {
  if (file.size != null && file.size != expected) {
    throw BinaryComparisonSourceChanged(
      'The comparison source length changed.',
    );
  }
}

FileItem _requireVersion(FileItem before, FileItem? after, String path) {
  if (after == null ||
      after.isFolder ||
      after.isSymlink == true ||
      (after.path != null && after.path != path) ||
      (before.storageId != null && before.storageId != after.storageId) ||
      !sameTransferVersion(before, after)) {
    throw BinaryComparisonSourceChanged(
      'A compared file changed. Compare again before navigating.',
    );
  }
  return _freeze(after.copyWith(path: path));
}

Stream<List<int>> _boundedInput(
  Stream<List<int>> stream,
  _ComparisonGuard guard,
  BinaryComparisonLimits limits, {
  required int? expectedLength,
}) async* {
  var bytes = 0, chunks = 0, emptyChunks = 0, sinceYield = 0;
  final cursor = StreamIterator(guard.control.bind(stream));
  try {
    while (await guard.wait(cursor.moveNext)) {
      guard.check();
      final chunk = cursor.current;
      if (++chunks > limits.maxChunks) {
        throw BinaryComparisonLimitExceeded(
          'Comparison input has too many chunks.',
        );
      }
      if (chunk.isEmpty && ++emptyChunks > limits.maxEmptyChunks) {
        throw BinaryComparisonLimitExceeded(
          'Comparison input has too many empty chunks.',
        );
      }
      if (chunk.length > limits.maxBytes - bytes) {
        throw BinaryComparisonLimitExceeded(
          'Comparison input exceeds its byte limit.',
        );
      }
      if (expectedLength != null && chunk.length > expectedLength - bytes) {
        throw BinaryComparisonSourceChanged(
          'The comparison source exceeded its declared length.',
        );
      }
      // Copy before retaining provider buffers, and never hand a giant chunk to
      // the hash/spool loop without cancellation and elapsed-work checkpoints.
      for (var offset = 0; offset < chunk.length;) {
        final count = (chunk.length - offset).clamp(0, 64 * 1024);
        final part = Uint8List(count);
        for (var i = 0; i < count; i++) {
          final byte = chunk[offset + i];
          if (byte < 0 || byte > 255) {
            throw RangeError.range(byte, 0, 255, 'source byte');
          }
          part[i] = byte;
        }
        bytes += count;
        offset += count;
        sinceYield += count;
        guard.progress();
        yield part;
        if (sinceYield >= 1024 * 1024) {
          await Future<void>.delayed(Duration.zero);
          sinceYield = 0;
        }
        guard.check();
      }
      // Empty or tiny synchronous chunks must not starve cancellation timers.
      if (chunks % 64 == 0) await Future<void>.delayed(Duration.zero);
    }
    guard.check();
    if (expectedLength != null && bytes != expectedLength) {
      throw BinaryComparisonSourceChanged(
        'The comparison source ended before its declared length.',
      );
    }
  } on FileOperationCancelled {
    guard.check();
    throw BinaryComparisonCancelled();
  } finally {
    // FileOperationControl detaches stalled upstream cancellation, so a
    // provider's pending cleanup cannot retain this operation or its spool.
    await cursor.cancel().catchError((Object _) {});
  }
}

class _DigestSink implements Sink<Digest> {
  String? value;
  @override
  void add(Digest data) => value = data.toString();
  @override
  void close() {}
}

/// Guards metadata futures as well as byte streams. Late provider completion
/// is observed and discarded; it never reacquires ownership after cancellation.
class _ComparisonGuard {
  _ComparisonGuard(this.limits, this.checkSource) {
    check();
    _timer = Timer.periodic(const Duration(milliseconds: 25), (_) {
      try {
        check();
      } catch (_) {
        // check() already failed all waiters and detached the input stream.
      }
    });
  }

  final BinaryComparisonLimits limits;
  final void Function() checkSource;
  final control = FileOperationControl();
  final _watch = Stopwatch()..start();
  final _waiters = <void Function()>{};
  Duration _lastProgress = Duration.zero;
  Timer? _timer;
  Object? _failure;
  StackTrace? _failureStack;

  void check() {
    if (_failure != null) Error.throwWithStackTrace(_failure!, _failureStack!);
    try {
      checkSource();
      if (_watch.elapsed >= limits.overallTimeout) {
        throw TimeoutException(
          'Comparison exceeded its elapsed-work limit.',
          limits.overallTimeout,
        );
      }
      if (_watch.elapsed - _lastProgress >= limits.inactivityTimeout) {
        throw TimeoutException(
          'Comparison source stopped making progress.',
          limits.inactivityTimeout,
        );
      }
    } catch (error, stack) {
      _failure = error;
      _failureStack = stack;
      _timer?.cancel();
      control.cancel();
      for (final waiter in _waiters.toList()) {
        waiter();
      }
      rethrow;
    }
  }

  void progress() {
    check();
    _lastProgress = _watch.elapsed;
  }

  Future<T> wait<T>(Future<T> Function() action) {
    check();
    final completed = Completer<T>();
    void stopped() {
      _waiters.remove(stopped);
      if (!completed.isCompleted) {
        completed.completeError(_failure!, _failureStack!);
      }
    }

    _waiters.add(stopped);
    unawaited(
      Future<T>.sync(action).then<void>(
        (value) {
          _waiters.remove(stopped);
          if (completed.isCompleted) return;
          try {
            check();
            completed.complete(value);
          } catch (error, stack) {
            if (!completed.isCompleted) completed.completeError(error, stack);
          }
        },
        onError: (Object error, StackTrace stack) {
          _waiters.remove(stopped);
          if (completed.isCompleted) return;
          try {
            check();
            completed.completeError(error, stack);
          } catch (halted, haltedStack) {
            if (!completed.isCompleted)
              completed.completeError(halted, haltedStack);
          }
        },
      ),
    );
    return completed.future;
  }

  void dispose() {
    _timer?.cancel();
    _watch.stop();
  }
}
