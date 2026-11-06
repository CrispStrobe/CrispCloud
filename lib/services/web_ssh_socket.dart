import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Shared binary WebSocket transport for SFTP and interactive SSH.
///
/// The gateway forwards an existing SSH connection; it does not interpret
/// terminal text or receive plaintext SSH credentials from this adapter.
class WebSSHSocket implements SSHSocket {
  final WebSocketChannel _ws;

  WebSSHSocket(this._ws);

  @override
  Stream<Uint8List> get stream => _ws.stream.map((event) {
    if (event is Uint8List) return event;
    if (event is List<int>) return Uint8List.fromList(event);
    throw FormatException(
      'Invalid payload from WebSocket: ${event.runtimeType}',
    );
  });

  @override
  StreamSink<List<int>> get sink => _WebSSHSink(_ws.sink);

  @override
  Future<void> close() => _ws.sink.close();

  @override
  Future<void> flush() async {
    // WebSocket sends are enqueued immediately.
  }

  @override
  Future<void> get done => _ws.sink.done;

  @override
  void destroy() {
    _ws.sink.close();
  }
}

class _WebSSHSink implements StreamSink<List<int>> {
  final StreamSink<dynamic> _sink;
  _WebSSHSink(this._sink);

  @override
  void add(List<int> event) => _sink.add(_bytes(event));

  static Uint8List _bytes(List<int> event) =>
      event is Uint8List ? event : Uint8List.fromList(event);

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _sink.addError(error, stackTrace);

  @override
  Future<void> addStream(Stream<List<int>> stream) =>
      _sink.addStream(stream.map(_bytes));

  @override
  Future<void> close() => _sink.close();

  @override
  Future<void> get done => _sink.done;
}
