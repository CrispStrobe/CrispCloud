import 'dart:async';
import 'dart:typed_data';

import 'bounded_transfer_stream.dart';

/// Reads sequential provider parts while retaining only one validated 64 KiB
/// source chunk. Parts can be hashed, discarded or spooled without buffering
/// their full size. The final source chunk is withheld until EOF is validated.
class TransferPartReader {
  TransferPartReader(Stream<List<int>> source, int length)
    : _chunks = StreamIterator(
        validatedTransferParts(source, length, 64 * 1024),
      );

  final StreamIterator<Uint8List> _chunks;
  Uint8List? _current;
  int _offset = 0;
  bool _reading = false;
  bool _closed = false;
  bool _failed = false;
  bool _exhausted = false;

  void _checkReady() {
    if (_closed || _failed || _reading || _exhausted) {
      throw StateError('The transfer part reader is not ready for more data.');
    }
  }

  Stream<List<int>> takeBytes(int length) async* {
    if (length < 0) throw ArgumentError.value(length, 'length');
    _checkReady();
    _reading = true;
    var completed = false;
    try {
      var remaining = length;
      while (remaining > 0) {
        if (_current == null || _offset == _current!.length) {
          if (!await _chunks.moveNext()) {
            throw StateError('Upload source ended before its declared length.');
          }
          _current = _chunks.current;
          _offset = 0;
        }
        final count = remaining < _current!.length - _offset
            ? remaining
            : _current!.length - _offset;
        final chunk = Uint8List.sublistView(
          _current!,
          _offset,
          _offset + count,
        );
        _offset += count;
        remaining -= count;
        yield chunk;
      }
      completed = true;
    } finally {
      _reading = false;
      // A cancelled part cannot later masquerade as a completely consumed one.
      if (!completed) _failed = true;
    }
  }

  Future<void> verifyEnd() async {
    _checkReady();
    _reading = true;
    try {
      if ((_current != null && _offset != _current!.length) ||
          await _chunks.moveNext()) {
        throw StateError('Upload source exceeded its declared length.');
      }
      _exhausted = true;
    } catch (_) {
      _failed = true;
      rethrow;
    } finally {
      _reading = false;
    }
  }

  Future<void> cancel() {
    _closed = true;
    return _chunks.cancel();
  }
}
