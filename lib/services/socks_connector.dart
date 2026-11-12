import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

part 'socks5_socket.dart';

/// Shared TCP ownership, cancellation and verified HTTPS for SOCKS CONNECT.
/// HttpClient.connectionFactory expects a secure socket for HTTPS targets.
sealed class SocksConnector {
  const SocksConnector({required this.host, required this.port});

  final String host;
  final int port;
  String get _protocol;

  void validate() {
    if (host.trim().isEmpty || port < 1 || port > 65535) {
      throw FormatException(
        '$_protocol needs a host and port from 1 to 65535.',
      );
    }
  }

  FutureOr<List<int>> _prepareRequest(Uri target);
  Future<void> _handshake(
    Socket socket,
    _SocksReplyReader reader,
    List<int> request,
  );

  Future<ConnectionTask<Socket>> connect(
    Uri target, {
    SecurityContext? securityContext,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    validate();
    if (target.scheme != 'http' && target.scheme != 'https') {
      throw SocketException('$_protocol HTTP routing requires HTTP or HTTPS.');
    }
    if (timeout <= Duration.zero) throw ArgumentError.value(timeout, 'timeout');
    if (target.port < 1 || target.port > 65535) {
      throw SocketException('$_protocol destination port is invalid.');
    }
    final prepared = _prepareRequest(target);
    final result = Completer<Socket>();
    ConnectionTask<RawSocket>? connecting;
    RawSocket? transport;
    Socket? active;
    _SocksReplyReader? reader;
    var stopped = false;
    Timer? timer;

    void fail(Object error, [StackTrace? trace]) {
      if (stopped || result.isCompleted) return;
      stopped = true;
      timer?.cancel();
      connecting?.cancel();
      active?.destroy();
      if (transport != null) _ignoreCleanup(transport!.close());
      if (reader != null) _ignoreCleanup(reader!.cancel());
      result.completeError(error, trace);
    }

    Future<void> negotiate() async {
      try {
        // SOCKS4 may resolve IPv4 locally. Its lookup shares the deadline; a
        // late lookup cannot open a socket after cancellation or timeout.
        final request = await prepared;
        if (stopped) return;
        final pending = await RawSocket.startConnect(host, port);
        if (stopped) {
          // startConnect itself is asynchronous. Observe a task returned after
          // cancellation and close any late transport instead of adopting it.
          _ignoreCleanup(
            pending.socket.then<void>((socket) {
              _ignoreCleanup(socket.close());
            }),
          );
          pending.cancel();
          return;
        }
        connecting = pending;
        final connected = await pending.socket;
        connecting = null;
        if (stopped) {
          _ignoreCleanup(connected.close());
          return;
        }
        transport = connected;
        active = _SocksRawSocket(connected);
        reader = _SocksReplyReader(active!, _protocol);
        await _handshake(active!, reader!, request);
        if (stopped) return;
        Socket ready;
        if (target.scheme == 'https') {
          // TLS peers cannot send application records before ClientHello.
          // Keep ownership of the raw socket throughout the pending upgrade.
          if (reader!.bufferedBytes != 0) {
            throw SocketException(
              '$_protocol proxy sent unexpected bytes before TLS.',
            );
          }
          final secure = await RawSecureSocket.secure(
            transport!,
            subscription: (active! as _SocksRawSocket).detachForTls(),
            host: target.host,
            context: securityContext,
          );
          if (stopped) {
            _ignoreCleanup(secure.close());
            return;
          }
          transport = secure;
          ready = _SocksSecureSocket(secure);
          active = ready;
          await reader!.cancel();
        } else {
          // Preserve coalesced payload bytes and the existing subscription.
          ready = _SocksHttpSocket(active!, reader!);
        }
        if (stopped) {
          ready.destroy();
          return;
        }
        timer?.cancel();
        result.complete(ready);
      } catch (error, trace) {
        fail(error, trace);
      }
    }

    timer = Timer(
      timeout,
      () => fail(SocketException('$_protocol connection timed out.')),
    );
    unawaited(negotiate());
    return ConnectionTask.fromSocket(
      result.future,
      () => fail(SocketException('$_protocol connection cancelled.')),
    );
  }
}

/// SOCKS5 CONNECT with remote DNS and optional RFC 1929 password authentication.
class Socks5Connector extends SocksConnector {
  const Socks5Connector({
    required super.host,
    required super.port,
    this.username,
    this.password,
  });

  final String? username;
  final String? password;
  @override
  String get _protocol => 'SOCKS5';

  @override
  void validate() {
    super.validate();
    if (username != null || password != null) {
      final userBytes = utf8.encode(username ?? '');
      final passwordBytes = utf8.encode(password ?? '');
      if (userBytes.isEmpty ||
          userBytes.length > 255 ||
          passwordBytes.isEmpty ||
          passwordBytes.length > 255) {
        throw const FormatException(
          'SOCKS5 username and password must each contain 1 to 255 UTF-8 bytes.',
        );
      }
    }
  }

  @override
  List<int> _prepareRequest(Uri target) {
    final address = InternetAddress.tryParse(target.host);
    final bytes = <int>[];
    if (address != null) {
      bytes.add(address.type == InternetAddressType.IPv4 ? 1 : 4);
      bytes.addAll(address.rawAddress);
    } else {
      final name = utf8.encode(target.host);
      if (name.isEmpty || name.length > 255 || name.contains(0)) {
        throw const SocketException('SOCKS5 destination hostname is invalid.');
      }
      bytes.addAll([3, name.length, ...name]);
    }
    return [...bytes, target.port >> 8, target.port & 255];
  }

  @override
  Future<void> _handshake(
    Socket socket,
    _SocksReplyReader reader,
    List<int> request,
  ) async {
    final method = username == null ? 0 : 2;
    socket.add([5, 1, method]);
    await socket.flush();
    final selection = await reader.read(2);
    if (selection[0] != 5 || selection[1] != method) {
      throw const SocketException(
        'SOCKS5 proxy refused the requested authentication method.',
      );
    }
    if (method == 2) {
      final user = utf8.encode(username!);
      final secret = utf8.encode(password!);
      socket.add([1, user.length, ...user, secret.length, ...secret]);
      await socket.flush();
      final authenticated = await reader.read(2);
      if (authenticated[0] != 1 || authenticated[1] != 0) {
        throw const SocketException('SOCKS5 authentication failed.');
      }
    }
    socket.add([5, 1, 0, ...request]);
    await socket.flush();
    final reply = await reader.read(4);
    if (reply[0] != 5 || reply[2] != 0) {
      throw const SocketException('SOCKS5 proxy returned a malformed reply.');
    }
    if (reply[1] != 0) {
      throw SocketException('SOCKS5 connection refused (reply ${reply[1]}).');
    }
    final addressLength = switch (reply[3]) {
      1 => 4,
      4 => 16,
      3 => (await reader.read(1)).single,
      _ => throw const SocketException(
        'SOCKS5 proxy returned an invalid address type.',
      ),
    };
    if (addressLength == 0) {
      throw const SocketException('SOCKS5 proxy returned an empty address.');
    }
    await reader.read(addressLength + 2);
  }
}

/// Local IPv4 lookup used only by SOCKS4. SOCKS4a never calls this resolver.
typedef SocksAddressLookup = Future<List<InternetAddress>> Function(
  String host,
);

/// SOCKS4 CONNECT, with an explicit opt-in to the SOCKS4a remote DNS extension.
/// USERID is an identifier, not a password; this implementation accepts an
/// optional printable ASCII identifier up to 255 bytes. IPv6 is unsupported.
class Socks4Connector extends SocksConnector {
  const Socks4Connector({
    required super.host,
    required super.port,
    this.userId = '',
    this.remoteDns = false,
    this.lookup,
  });

  final String userId;
  final bool remoteDns;
  final SocksAddressLookup? lookup;
  @override
  String get _protocol => remoteDns ? 'SOCKS4a' : 'SOCKS4';

  @override
  void validate() {
    super.validate();
    if (userId.length > 255 ||
        userId.codeUnits.any((byte) => byte < 32 || byte > 126)) {
      throw const FormatException(
        'SOCKS4 user ID must contain at most 255 printable ASCII characters.',
      );
    }
  }

  @override
  FutureOr<List<int>> _prepareRequest(Uri target) {
    final address = InternetAddress.tryParse(target.host);
    if (address != null) return _request(target.port, address);
    final name = target.host.codeUnits;
    // The wire format has NUL-terminated ASCII names. Require the IDNA ASCII
    // form for international names rather than forwarding percent escapes.
    if (name.isEmpty ||
        name.length > 255 ||
        name.any((byte) => byte < 33 || byte > 126 || byte == 37)) {
      throw SocketException(
        '$_protocol destination hostname must be ASCII and at most 255 bytes.',
      );
    }
    if (remoteDns) {
      return [
        4,
        1,
        target.port >> 8,
        target.port & 255,
        0,
        0,
        0,
        1,
        ...userId.codeUnits,
        0,
        ...name,
        0,
      ];
    }
    final resolve = lookup ?? _lookupIpv4;
    return resolve(target.host).then((addresses) {
      for (final resolved in addresses) {
        if (resolved.type == InternetAddressType.IPv4) {
          return _request(target.port, resolved);
        }
      }
      throw const SocketException('SOCKS4 destination has no IPv4 address.');
    });
  }

  static Future<List<InternetAddress>> _lookupIpv4(String host) =>
      InternetAddress.lookup(host, type: InternetAddressType.IPv4);

  List<int> _request(int destinationPort, InternetAddress address) {
    if (address.type != InternetAddressType.IPv4) {
      throw SocketException('$_protocol does not support IPv6 destinations.');
    }
    final bytes = address.rawAddress;
    if (bytes[0] == 0 && bytes[1] == 0 && bytes[2] == 0 && bytes[3] != 0) {
      throw SocketException(
        '$_protocol destination uses the reserved SOCKS4a marker.',
      );
    }
    return [
      4,
      1,
      destinationPort >> 8,
      destinationPort & 255,
      ...bytes,
      ...userId.codeUnits,
      0,
    ];
  }

  @override
  Future<void> _handshake(
    Socket socket,
    _SocksReplyReader reader,
    List<int> request,
  ) async {
    socket.add(request);
    await socket.flush();
    final reply = await reader.read(8);
    if (reply[0] != 0) {
      throw SocketException('$_protocol proxy returned a malformed reply.');
    }
    if (reply[1] != 90) {
      throw SocketException(
        '$_protocol connection refused (reply ${reply[1]}).',
      );
    }
  }
}

void _ignoreCleanup(Future<dynamic> cleanup) {
  unawaited(cleanup.then<void>((_) {}, onError: (Object _) {}));
}

class _SocksReplyReader {
  _SocksReplyReader(Socket socket, this.protocol)
    : _input = StreamIterator(socket);
  final String protocol;
  final StreamIterator<Uint8List> _input;
  Uint8List _chunk = Uint8List(0);
  int _offset = 0;
  int _readBytes = 0;
  int get bufferedBytes => _chunk.length - _offset;

  Future<List<int>> read(int count) async {
    _readBytes += count;
    if (count < 0 || _readBytes > 1024) {
      throw SocketException('$protocol reply exceeded its size limit.');
    }
    final result = <int>[];
    while (result.length < count) {
      if (_offset == _chunk.length) {
        if (!await _input.moveNext()) {
          throw SocketException('$protocol proxy closed during negotiation.');
        }
        _chunk = _input.current;
        _offset = 0;
      }
      final remaining = count - result.length;
      final available = _chunk.length - _offset;
      final length = remaining < available ? remaining : available;
      result.addAll(_chunk.sublist(_offset, _offset + length));
      _offset += length;
    }
    return result;
  }

  Stream<Uint8List> remaining() async* {
    try {
      if (bufferedBytes > 0) yield Uint8List.sublistView(_chunk, _offset);
      _chunk = Uint8List(0);
      while (await _input.moveNext()) {
        yield _input.current;
      }
    } finally {
      await _input.cancel();
    }
  }

  Future<void> cancel() => _input.cancel();
}

/// Retains the already-open SOCKS subscription for unencrypted HTTP. HTTPS uses
/// the original raw transport upgraded by RawSecureSocket.secure instead.
class _SocksHttpSocket extends Stream<Uint8List> implements Socket {
  _SocksHttpSocket(this._socket, this._reader)
    : _incoming = _reader.remaining();
  final Socket _socket;
  final _SocksReplyReader _reader;
  final Stream<Uint8List> _incoming;
  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _incoming.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  void destroy() {
    _socket.destroy();
    _ignoreCleanup(_reader.cancel());
  }

  @override
  Encoding get encoding => _socket.encoding;
  @override
  set encoding(Encoding value) => _socket.encoding = value;
  @override
  void add(List<int> data) => _socket.add(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _socket.addError(error, stackTrace);
  @override
  Future<void> addStream(Stream<List<int>> stream) => _socket.addStream(stream);
  @override
  Future<void> flush() => _socket.flush();
  @override
  Future<void> close() async {
    await _socket.close();
  }

  @override
  Future<void> get done async {
    await _socket.done;
  }

  @override
  void write(Object? object) => _socket.write(object);
  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) =>
      _socket.writeAll(objects, separator);
  @override
  void writeCharCode(int charCode) => _socket.writeCharCode(charCode);
  @override
  void writeln([Object? object = '']) => _socket.writeln(object);
  @override
  bool setOption(SocketOption option, bool enabled) =>
      _socket.setOption(option, enabled);
  @override
  Uint8List getRawOption(RawSocketOption option) =>
      _socket.getRawOption(option);
  @override
  void setRawOption(RawSocketOption option) => _socket.setRawOption(option);
  @override
  int get port => _socket.port;
  @override
  int get remotePort => _socket.remotePort;
  @override
  InternetAddress get address => _socket.address;
  @override
  InternetAddress get remoteAddress => _socket.remoteAddress;
}
