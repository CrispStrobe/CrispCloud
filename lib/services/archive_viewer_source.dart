import 'dart:async';
import 'dart:typed_data';

import 'package:koni_archive/koni_archive.dart' as koni;

import 'archive_types.dart';
import 'file_bytes_loader.dart';

/// Allows a member's bounded compressed input to include modest codec overhead.
/// Expanded member limits remain the archive reader's responsibility.
const int kArchiveViewerReadLimit = kArchiveReadLimit + 64 * 1024;

/// Borrows an already opened F3 byte source without owning its file handle,
/// access grant, spool, or in-memory storage.
///
/// The viewer must keep [source] alive until this adapter has been closed and
/// pass an [isCurrent] check bound to its captured load/mode generation and
/// source identity. Create a fresh adapter for every archive/password attempt:
/// failed readers close their input, while the viewer continues owning it.
///
/// Positional reads are serialized and each synchronous slice is copied before
/// yielding. A shared ViewBytesSource file cursor therefore cannot interleave
/// between seek/read operations. Native files are validated before and after
/// each request; memory sources follow the same ownership rules on the web.
class ArchiveViewerSource implements koni.ByteSource {
  ArchiveViewerSource(
    ViewBytesSource source, {
    required this._isCurrent,
    this.name,
    this.maxReadBytes = kArchiveViewerReadLimit,
  }) : _source = source,
       length = source.size {
    if (maxReadBytes <= 0) {
      throw ArgumentError.value(maxReadBytes, 'maxReadBytes');
    }
    if (length < 0 || length > 9007199254740991) {
      throw const ArchiveViewException(
        'The archive source size cannot be represented safely.',
      );
    }
  }

  static const _chunkBytes = 256 * 1024;
  final ViewBytesSource _source;
  final bool Function() _isCurrent;
  @override
  final String? name;
  @override
  final int length;
  final int maxReadBytes;
  bool _closed = false;
  Future<void> _tail = Future<void>.value();
  Future<void>? _closing;

  bool get isClosed => _closed;

  @override
  Future<Uint8List> read(int offset, int length) async {
    _checkCurrent();
    if (offset < 0) throw ArgumentError.value(offset, 'offset');
    if (length < 0) throw ArgumentError.value(length, 'length');
    if (offset > this.length || length > this.length - offset) {
      throw _readError('The requested range leaves the captured archive.');
    }
    if (length > maxReadBytes) {
      throw ArchiveViewException(
        'The archive read exceeds its $maxReadBytes-byte input limit.',
        code: ArchiveMessageCode.entryLimit,
        arguments: {'limit': '$maxReadBytes bytes'},
      );
    }
    final result = Completer<Uint8List>();
    _tail = _tail.then((_) async {
      try {
        result.complete(await _read(offset, length));
      } catch (error, stack) {
        result.completeError(
          error is ArchiveViewException
              ? error
              : _readError('The viewed file is unavailable or changed: $error'),
          stack,
        );
      }
    });
    return result.future;
  }

  Future<Uint8List> _read(int offset, int count) async {
    _checkCurrent();
    await _source.validateUnchanged();
    _checkCurrent();
    final result = Uint8List(count);
    var copied = 0;
    while (copied < count) {
      _checkCurrent();
      final remaining = count - copied;
      final take = remaining < _chunkBytes ? remaining : _chunkBytes;
      final bytes = _source.readSync(offset + copied, take);
      if (bytes.length != take) {
        throw _readError(
          'The viewed file returned fewer bytes than requested.',
        );
      }
      result.setRange(copied, copied + take, bytes);
      copied += take;
      if (copied < count) {
        // Let mode changes, cancellation and rendering run between windows.
        await Future<void>.delayed(Duration.zero);
      }
    }
    await _source.validateUnchanged();
    _checkCurrent();
    return result;
  }

  void _checkCurrent() {
    if (_closed) {
      throw const ArchiveViewException(
        'This archive has been closed.',
        code: ArchiveMessageCode.closed,
      );
    }
    if (!_isCurrent() || _source.size != length) {
      throw _readError(
        'The original viewer source is no longer current. Reopen the archive.',
      );
    }
  }

  /// Invalidates borrowing synchronously, then waits for queued reads to stop.
  /// Never disposes the viewer's source or releases its platform access grant.
  @override
  Future<void> close() {
    _closed = true;
    return _closing ??= _tail;
  }
}

ArchiveViewException _readError(String detail) => ArchiveViewException(
  detail,
  code: ArchiveMessageCode.readEntry,
  arguments: {'detail': detail},
);
