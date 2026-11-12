import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

part 'socks5_socket.dart';

/// A SOCKS5 CONNECT tunnel for native HTTP clients. The protocol is implemented
/// directly from RFC 1928/1929; it does not resolve destination DNS locally.
/// HTTPS is upgraded and verified here because HttpClient.connectionFactory
/// expects its custom factory to supply an already-secure socket for HTTPS.
class Socks5Connector {
  const Socks5Connector({
    required this.host,
    required this.port,
    this.username,
    this.password,
  });

  final String host;
  final int port;
  final String? username;
  final String? password;

  void validate() {
    if (host.trim().isEmpty || port < 1 || port > 65535) {
      throw const FormatException(
        'SOCKS5 needs a host and port from 1 to 65535.',
      );
    }
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

  Future<ConnectionTask<Socket>> connect(
    Uri target, {
    SecurityContext? securityContext,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    validate();
    if (target.scheme != 'http' && target.scheme != 'https') {
      throw const SocketException(
        'SOCKS5 HTTP routing requires HTTP or HTTPS.',
      );
    }
    if (timeout <= Duration.zero) throw ArgumentError.value(timeout, 'timeout');
    final destination = _destination(target.host, target.port);
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
      unawaited(transport?.close());
      unawaited(reader?.cancel());
      result.completeError(error, trace);
    }

    Future<void> negotiate() async {
      try {
        connecting = await RawSocket.startConnect(host, port);
        if (stopped) {
          connecting!.cancel();
          return;
        }
        transport = await connecting!.socket;
        active = _SocksRawSocket(transport!);
        if (stopped) {
          active!.destroy();
          return;
        }
        reader = _SocksReplyReader(active!);
        final method = username == null ? 0 : 2;
        active!.add([5, 1, method]);
        await active!.flush();
        final selection = await reader!.read(2);
        if (selection[0] != 5 || selection[1] != method) {
          throw const SocketException(
            'SOCKS5 proxy refused the requested authentication method.',
          );
        }
        if (method == 2) {
          final user = utf8.encode(username!);
          final secret = utf8.encode(password!);
          active!.add([1, user.length, ...user, secret.length, ...secret]);
          await active!.flush();
          final authenticated = await reader!.read(2);
          if (authenticated[0] != 1 || authenticated[1] != 0) {
            throw const SocketException('SOCKS5 authentication failed.');
          }
        }
        active!.add([5, 1, 0, ...destination]);
        await active!.flush();
        final reply = await reader!.read(4);
        if (reply[0] != 5 || reply[2] != 0) {
          throw const SocketException(
            'SOCKS5 proxy returned a malformed reply.',
          );
        }
        if (reply[1] != 0) {
          throw SocketException(
            'SOCKS5 connection refused (reply ${reply[1]}).',
          );
        }
        final addressLength = switch (reply[3]) {
          1 => 4,
          4 => 16,
          3 => (await reader!.read(1)).single,
          _ => throw const SocketException(
            'SOCKS5 proxy returned an invalid address type.',
          ),
        };
        if (addressLength == 0) {
          throw const SocketException(
            'SOCKS5 proxy returned an empty address.',
          );
        }
        await reader!.read(addressLength + 2);
        Socket ready;
        if (target.scheme == 'https') {
          // HTTPS peers cannot legitimately send TLS records before ClientHello.
          // Reject surplus handshake bytes rather than silently discarding them.
          if (reader!.bufferedBytes != 0) {
            throw const SocketException(
              'SOCKS5 proxy sent unexpected bytes before TLS.',
            );
          }
          final secure = await RawSecureSocket.secure(
            transport!,
            subscription: (active! as _SocksRawSocket).detachForTls(),
            host: target.host,
            context: securityContext,
          );
          transport = secure;
          ready = _SocksSecureSocket(secure);
          active = ready;
          await reader!.cancel();
        } else {
          // The socket already has its handshake subscription. Preserve any
          // coalesced payload bytes and forward that subscription to HttpClient.
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
      () => fail(const SocketException('SOCKS5 connection timed out.')),
    );
    unawaited(negotiate());
    return ConnectionTask.fromSocket(
      result.future,
      () => fail(const SocketException('SOCKS5 connection cancelled.')),
    );
  }

  List<int> _destination(String destinationHost, int destinationPort) {
    if (destinationPort < 1 || destinationPort > 65535) {
      throw const SocketException('SOCKS5 destination port is invalid.');
    }
    final address = InternetAddress.tryParse(destinationHost);
    final bytes = <int>[];
    if (address != null) {
      bytes.add(address.type == InternetAddressType.IPv4 ? 1 : 4);
      bytes.addAll(address.rawAddress);
    } else {
      // Uri supplies the hostname; sending it to the proxy retains remote DNS.
      final name = utf8.encode(destinationHost);
      if (name.isEmpty || name.length > 255 || name.contains(0)) {
        throw const SocketException('SOCKS5 destination hostname is invalid.');
      }
      bytes.addAll([3, name.length, ...name]);
    }
    return [...bytes, destinationPort >> 8, destinationPort & 255];
  }
}

class _SocksReplyReader {
  _SocksReplyReader(Socket socket) : _input = StreamIterator(socket);
  final StreamIterator<Uint8List> _input;
  Uint8List _chunk = Uint8List(0);
  int _offset = 0;
  int _readBytes = 0;
  int get bufferedBytes => _chunk.length - _offset;

  Future<List<int>> read(int count) async {
    _readBytes += count;
    if (count < 0 || _readBytes > 1024) {
      throw const SocketException('SOCKS5 reply exceeded its size limit.');
    }
    final result = <int>[];
    while (result.length < count) {
      if (_offset == _chunk.length) {
        if (!await _input.moveNext()) {
          throw const SocketException(
            'SOCKS5 proxy closed during negotiation.',
          );
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
/// the original native socket upgraded by SecureSocket.secure instead.
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
    unawaited(_reader.cancel());
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
