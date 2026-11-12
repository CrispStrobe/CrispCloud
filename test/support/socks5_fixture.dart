import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class Socks5Request {
  const Socks5Request(this.addressType, this.host, this.port);
  final int addressType;
  final String host;
  final int port;
}

/// Real loopback SOCKS server. Named destinations are mapped to loopback by the
/// server, allowing tests to prove that the client sends remote DNS names.
class Socks5Fixture {
  Socks5Fixture._(
    this._server, {
    this.requireAuthentication = false,
    this.selectedMethod,
    this.acceptAuthentication = true,
    this.connectReply = 0,
    this.fragmentReplies = false,
    this.stallGreeting = false,
    this.stallAfterConnect = false,
    this.malformedReply = false,
    this.inlinePayload,
  });

  final ServerSocket _server;
  final bool requireAuthentication;
  final int? selectedMethod;
  final bool acceptAuthentication;
  final int connectReply;
  final bool fragmentReplies;
  final bool stallGreeting;
  final bool stallAfterConnect;
  final bool malformedReply;
  final List<int>? inlinePayload;
  final requests = <Socks5Request>[];
  final offeredMethods = <List<int>>[];
  final errors = <Object>[];
  final _sockets = <Socket>{};
  final _tasks = <Future<void>>{};
  final firstClosed = Completer<void>();
  final connected = Completer<void>();
  final tunnelData = Completer<void>();
  String? username;
  String? password;
  int originsOpened = 0;
  int get port => _server.port;

  static Future<Socks5Fixture> start({
    bool requireAuthentication = false,
    int? selectedMethod,
    bool acceptAuthentication = true,
    int connectReply = 0,
    bool fragmentReplies = false,
    bool stallGreeting = false,
    bool stallAfterConnect = false,
    bool malformedReply = false,
    List<int>? inlinePayload,
  }) async {
    final fixture = Socks5Fixture._(
      await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
      requireAuthentication: requireAuthentication,
      selectedMethod: selectedMethod,
      acceptAuthentication: acceptAuthentication,
      connectReply: connectReply,
      fragmentReplies: fragmentReplies,
      stallGreeting: stallGreeting,
      stallAfterConnect: stallAfterConnect,
      malformedReply: malformedReply,
      inlinePayload: inlinePayload,
    );
    fixture._server.listen((socket) {
      final task = fixture._handle(socket);
      fixture._tasks.add(task);
      unawaited(task.whenComplete(() => fixture._tasks.remove(task)));
    });
    return fixture;
  }

  Future<void> _send(Socket socket, List<int> bytes) async {
    if (!fragmentReplies) {
      socket.add(bytes);
      await socket.flush();
      return;
    }
    for (final byte in bytes) {
      socket.add([byte]);
      await socket.flush();
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  Future<void> _handle(Socket socket) async {
    _sockets.add(socket);
    socket.setOption(SocketOption.tcpNoDelay, true);
    final input = _FixtureReader(socket);
    Socket? target;
    try {
      final greeting = await input.read(2);
      if (greeting[0] != 5) throw StateError('Expected SOCKS version 5.');
      offeredMethods.add(await input.read(greeting[1]));
      if (!connected.isCompleted) connected.complete();
      if (stallGreeting) {
        await input.remaining().drain<void>();
        return;
      }
      final method = selectedMethod ?? (requireAuthentication ? 2 : 0);
      await _send(socket, [5, method]);
      if (method == 2) {
        final auth = await input.read(2);
        if (auth[0] != 1) throw StateError('Expected password auth version 1.');
        username = utf8.decode(await input.read(auth[1]));
        final passwordLength = (await input.read(1)).single;
        password = utf8.decode(await input.read(passwordLength));
        await _send(socket, [1, acceptAuthentication ? 0 : 1]);
        if (!acceptAuthentication) {
          await input.remaining().drain<void>();
          return;
        }
      }
      final header = await input.read(4);
      if (header[0] != 5 || header[1] != 1 || header[2] != 0) {
        throw StateError('Expected SOCKS CONNECT.');
      }
      final addressType = header[3];
      final length = switch (addressType) {
        1 => 4,
        4 => 16,
        3 => (await input.read(1)).single,
        _ => throw StateError('Unexpected address type.'),
      };
      final bytes = await input.read(length);
      final host = addressType == 3
          ? utf8.decode(bytes)
          : InternetAddress.fromRawAddress(Uint8List.fromList(bytes)).address;
      final portBytes = await input.read(2);
      final requestedPort = (portBytes[0] << 8) | portBytes[1];
      requests.add(Socks5Request(addressType, host, requestedPort));
      final response = [
        malformedReply ? 4 : 5,
        connectReply,
        0,
        1,
        127,
        0,
        0,
        1,
        0,
        0,
      ];
      if (connectReply != 0 || malformedReply) {
        await _send(socket, response);
        await input.remaining().drain<void>();
        return;
      }
      if (inlinePayload != null || stallAfterConnect) {
        await _send(socket, [...response, ...?inlinePayload]);
        await for (final bytes in input.remaining()) {
          if (bytes.isNotEmpty && !tunnelData.isCompleted) {
            tunnelData.complete();
          }
        }
        return;
      }
      target = await Socket.connect(
        InternetAddress.loopbackIPv4,
        requestedPort,
      );
      _sockets.add(target);
      originsOpened++;
      await _send(socket, response);
      final remote = target;
      await Future.wait([
        socket.addStream(remote).then((_) => socket.close()),
        remote.addStream(input.remaining()).then((_) => remote.close()),
      ]);
    } on SocketException {
      // Clients deliberately reject handshakes and certificates in these tests.
    } on _FixtureClosed {
      // Authentication/connection rejection closes without another command.
    } catch (error) {
      errors.add(error);
    } finally {
      socket.destroy();
      target?.destroy();
      _sockets.remove(socket);
      _sockets.remove(target);
      await input.cancel();
      if (!firstClosed.isCompleted) firstClosed.complete();
    }
  }

  Future<void> close() async {
    await _server.close();
    for (final socket in _sockets.toList()) {
      socket.destroy();
    }
    await Future.wait(_tasks.toList());
  }
}

class _FixtureClosed implements Exception {}

class _FixtureReader {
  _FixtureReader(Socket socket) : _input = StreamIterator(socket);
  final StreamIterator<Uint8List> _input;
  Uint8List _chunk = Uint8List(0);
  int _offset = 0;
  Future<List<int>> read(int count) async {
    final bytes = <int>[];
    while (bytes.length < count) {
      if (_offset == _chunk.length) {
        if (!await _input.moveNext()) throw _FixtureClosed();
        _chunk = _input.current;
        _offset = 0;
      }
      final countRemaining = count - bytes.length;
      final available = _chunk.length - _offset;
      final length = countRemaining < available ? countRemaining : available;
      bytes.addAll(_chunk.sublist(_offset, _offset + length));
      _offset += length;
    }
    return bytes;
  }

  Stream<Uint8List> remaining() async* {
    if (_offset < _chunk.length) yield Uint8List.sublistView(_chunk, _offset);
    while (await _input.moveNext()) {
      yield _input.current;
    }
  }

  Future<void> cancel() => _input.cancel();
}
