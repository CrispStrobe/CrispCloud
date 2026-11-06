import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:madedit2_hex/hex_document.dart';

Future<HexByteSource> openHexFileSource(String path) async {
  final file = await File(path).open();
  try { return _FileSource(file, await file.length()); }
  catch (_) { await file.close(); rethrow; }
}
Future<void> closeHexFileSource(HexByteSource source) async {
  if (source is _FileSource) await source.close();
}
class _FileSource implements HexByteSource {
  _FileSource(this._file, this.length);
  final RandomAccessFile _file;
  @override
  final int length;
  Future<void> _tail = Future<void>.value();
  bool _closed = false;
  @override
  Future<Uint8List> read(int offset, int count) {
    if (offset < 0 || count < 0 || offset > length || count > length - offset) {
      return Future.error(RangeError('Invalid byte range.'));
    }
    if (_closed) return Future.error(StateError('The byte source is closed.'));
    final result = Completer<Uint8List>();
    _tail = _tail.then((_) async {
      try {
        await _file.setPosition(offset);
        final bytes = Uint8List(count);
        var received = 0;
        while (received < count) {
          final n = await _file.readInto(bytes, received, count);
          if (n == 0) throw StateError('The private byte snapshot was truncated.');
          received += n;
        }
        result.complete(bytes);
      } catch (error, stack) { result.completeError(error, stack); }
    });
    return result.future;
  }
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _tail;
    await _file.close();
  }
}
