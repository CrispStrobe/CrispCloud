part of 'socks5_connector.dart';

/// Converts raw socket readiness into the byte stream/sink expected by
/// HttpClient. Keeping the raw transport lets cancellation close a pending TLS
/// upgrade, which has detached its original high-level Socket.
class _SocksRawSocket extends Stream<Uint8List> implements Socket {
  _SocksRawSocket(this.raw) {
    raw.readEventsEnabled = false;
    raw.writeEventsEnabled = false;
    _input = StreamController<Uint8List>(
      sync: true,
      onListen: _resume,
      onPause: _pause,
      onResume: _resume,
      onCancel: () {
        if (!_detached) destroy();
      },
    );
    _consumer = _RawSocketConsumer(this);
    _sink = IOSink(_consumer);
    _events = raw.listen(_event, onError: _failed, onDone: _closedEvent);
  }

  final RawSocket raw;
  late final StreamController<Uint8List> _input;
  late final StreamSubscription<RawSocketEvent> _events;
  late final _RawSocketConsumer _consumer;
  late final IOSink _sink;
  Completer<void>? _writable;
  bool _destroyed = false;
  bool _detached = false;
  bool _sendClosed = false;

  void _pause() {
    if (!_destroyed && !_detached) raw.readEventsEnabled = false;
  }

  void _resume() {
    if (!_destroyed && !_detached) raw.readEventsEnabled = true;
  }

  void _event(RawSocketEvent event) {
    if (event == RawSocketEvent.read) {
      final bytes = raw.read(64 * 1024);
      if (bytes != null && !_input.isClosed) _input.add(bytes);
    } else if (event == RawSocketEvent.write) {
      final waiting = _writable;
      _writable = null;
      waiting?.complete();
    } else if (event == RawSocketEvent.readClosed) {
      if (!_input.isClosed) unawaited(_input.close());
    } else if (event == RawSocketEvent.closed) {
      _closedEvent();
    }
  }

  void _failed(Object error, StackTrace trace) {
    if (!_input.isClosed) _input.addError(error, trace);
    _finish(error, trace);
  }

  void _closedEvent() =>
      _finish(const SocketException('SOCKS5 socket closed.'));

  void _finish(Object error, [StackTrace? trace]) {
    if (_destroyed || _detached) return;
    _destroyed = true;
    final waiting = _writable;
    _writable = null;
    waiting?.completeError(error, trace);
    _consumer.abort(error, trace);
    unawaited(raw.close());
    if (!_input.isClosed) unawaited(_input.close());
    // Finish the IOSink even if it was idle at the moment of cancellation.
    unawaited(_sink.close().then<void>((_) {}, onError: (Object _) {}));
  }

  Future<void> _write(List<int> bytes) async {
    var offset = 0;
    while (offset < bytes.length) {
      if (_destroyed || _detached || _sendClosed) {
        throw const SocketException('SOCKS5 socket is closed for writing.');
      }
      final written = raw.write(bytes, offset, bytes.length - offset);
      offset += written;
      if (written == 0) {
        final waiting = Completer<void>();
        _writable = waiting;
        raw.writeEventsEnabled = true;
        await waiting.future;
      }
    }
  }

  Future<void> _closeSend() async {
    if (_destroyed || _detached || _sendClosed) return;
    _sendClosed = true;
    raw.shutdown(SocketDirection.send);
  }

  StreamSubscription<RawSocketEvent> detachForTls() {
    _detached = true;
    raw.readEventsEnabled = false;
    raw.writeEventsEnabled = false;
    if (!_input.isClosed) unawaited(_input.close());
    return _events;
  }

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _input.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  void destroy() => _finish(const SocketException('SOCKS5 socket destroyed.'));
  @override
  Encoding get encoding => _sink.encoding;
  @override
  set encoding(Encoding value) => _sink.encoding = value;
  @override
  void add(List<int> data) => _sink.add(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      throw UnsupportedError('Cannot send errors on a socket.');
  @override
  Future<void> addStream(Stream<List<int>> stream) => _sink.addStream(stream);
  @override
  Future<void> flush() => _sink.flush();
  @override
  Future<void> close() async {
    await _sink.close();
  }

  @override
  Future<void> get done async {
    await _sink.done;
  }

  @override
  void write(Object? object) => _sink.write(object);
  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) =>
      _sink.writeAll(objects, separator);
  @override
  void writeCharCode(int charCode) => _sink.writeCharCode(charCode);
  @override
  void writeln([Object? object = '']) => _sink.writeln(object);
  @override
  bool setOption(SocketOption option, bool enabled) =>
      raw.setOption(option, enabled);
  @override
  Uint8List getRawOption(RawSocketOption option) => raw.getRawOption(option);
  @override
  void setRawOption(RawSocketOption option) => raw.setRawOption(option);
  @override
  int get port => raw.port;
  @override
  int get remotePort => raw.remotePort;
  @override
  InternetAddress get address => raw.address;
  @override
  InternetAddress get remoteAddress => raw.remoteAddress;
}

class _SocksSecureSocket extends _SocksRawSocket implements SecureSocket {
  _SocksSecureSocket(super.raw);
  RawSecureSocket get _secure => raw as RawSecureSocket;
  @override
  X509Certificate? get peerCertificate => _secure.peerCertificate;
  @override
  String? get selectedProtocol => _secure.selectedProtocol;
  @override
  void renegotiate({
    bool useSessionCache = true,
    bool requestClientCertificate = false,
    bool requireClientCertificate = false,
  }) =>
      // Required by SecureSocket; the SDK retains this deprecated no-op.
      // ignore: deprecated_member_use
      _secure.renegotiate(
        useSessionCache: useSessionCache,
        requestClientCertificate: requestClientCertificate,
        requireClientCertificate: requireClientCertificate,
      );
}

/// IOSink serializes input streams. Pause each source until its chunk has been
/// accepted by the socket, retaining backpressure for large cloud transfers.
class _RawSocketConsumer implements StreamConsumer<List<int>> {
  _RawSocketConsumer(this.socket);
  final _SocksRawSocket socket;
  StreamSubscription<List<int>>? _source;
  Completer<void>? _completion;

  @override
  Future<void> addStream(Stream<List<int>> stream) {
    final completed = Completer<void>();
    _completion = completed;
    _source = stream.listen(
      (bytes) {
        _source!.pause();
        socket
            ._write(bytes)
            .then(
              (_) {
                _source?.resume();
              },
              onError: (Object error, StackTrace trace) {
                abort(error, trace);
              },
            );
      },
      onError: (Object error, StackTrace trace) {
        abort(error, trace);
      },
      onDone: () {
        _source = null;
        _completion = null;
        if (!completed.isCompleted) completed.complete();
      },
    );
    return completed.future;
  }

  void abort(Object error, [StackTrace? trace]) {
    final completed = _completion;
    _completion = null;
    final source = _source;
    _source = null;
    if (source != null) unawaited(source.cancel());
    if (completed != null && !completed.isCompleted) {
      completed.completeError(error, trace);
    }
  }

  @override
  Future<void> close() => socket._closeSend();
}
