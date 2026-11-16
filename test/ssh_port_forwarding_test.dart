@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/services/ssh_port_forwarding.dart';
import 'package:crisp_cloud/services/ssh_terminal_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _Client client;
  late SshPortForwarding manager;
  final sockets = <Socket>[];
  final echoes = <_Echo>[];
  var activity = 0;

  setUp(() {
    client = _Client();
    activity = 0;
    manager = SshPortForwarding(client, onActivity: () => activity++);
  });

  tearDown(() async {
    await manager.close();
    manager.dispose();
    await client.close();
    for (final socket in sockets) {
      socket.destroy();
    }
    sockets.clear();
    for (final echo in echoes) {
      await echo.close();
    }
    echoes.clear();
  });

  Future<_Echo> echo({bool afterEof = false}) async {
    final result = await _Echo.create(afterEof: afterEof);
    echoes.add(result);
    return result;
  }

  Future<Socket> connect(int port) async {
    final socket = await Socket.connect('127.0.0.1', port);
    sockets.add(socket);
    return socket;
  }

  SshPortForwardSpec local(int port) => SshPortForwardSpec(
    kind: SshPortForwardKind.local,
    targetHost: '127.0.0.1',
    targetPort: port,
  );
  SshPortForwardSpec remote(int port) => SshPortForwardSpec(
    kind: SshPortForwardKind.remote,
    targetHost: '127.0.0.1',
    targetPort: port,
  );

  test('local forwarding allocates a loopback port and carries binary/Unicode traffic', () async {
    final target = await echo();
    final forward = await manager.start(local(target.port));
    expect(forward.port, greaterThan(0));
    expect(forward.status, SshPortForwardStatus.active);
    final socket = await connect(forward.port);
    final reader = _Read(socket);
    addTearDown(reader.cancel);
    final bytes = [0, 255, ...utf8.encode('route-✓-日本語')];
    socket.add(bytes);
    expect(await reader.read(bytes.length), bytes);
    expect(client.requests.single.$1, '127.0.0.1');
    expect(client.requests.single.$2, target.port);
    expect(manager.forwards.single.activeConnections, 1);
    expect(activity, greaterThanOrEqualTo(3));
    await manager.stop(forward.id);
    expect(manager.forwards, isEmpty);
    await expectLater(
      Socket.connect('127.0.0.1', forward.port),
      throwsA(isA<SocketException>()),
    );
    expect(client.isClosed, isFalse);
  });

  test('local request half-close preserves the final response', () async {
    final target = await echo(afterEof: true);
    final forward = await manager.start(local(target.port));
    final socket = await connect(forward.port);
    final response = socket.fold<List<int>>(
      [],
      (all, chunk) => all..addAll(chunk),
    );
    socket.add(utf8.encode('half-close-✓'));
    await socket.close();
    expect(
      utf8.decode(await response.timeout(const Duration(seconds: 3))),
      'reply:half-close-✓',
    );
    await until(() => manager.forwards.single.activeConnections == 0);
  });

  test(
    'remote forwarding allocates a port and drains a response after EOF',
    () async {
      final target = await echo(afterEof: true);
      final forward = await manager.start(remote(target.port));
      expect(client.remotes.single.host, '127.0.0.1');
      final socket = await connect(forward.port);
      final response = socket.fold<List<int>>(
        [],
        (all, chunk) => all..addAll(chunk),
      );
      socket.add(utf8.encode('remote-✓'));
      await socket.close();
      expect(
        utf8.decode(await response.timeout(const Duration(seconds: 3))),
        'reply:remote-✓',
      );
      await manager.stop(forward.id);
      expect(client.cancellations, 1);
      expect(client.isClosed, isFalse);
      await expectLater(
        Socket.connect('127.0.0.1', forward.port),
        throwsA(isA<SocketException>()),
      );
    },
  );

  test('stopping closes an already accepted remote connection', () async {
    final target = await echo();
    final forward = await manager.start(remote(target.port));
    final socket = await connect(forward.port);
    final done = socket.drain<void>();
    await until(() => manager.forwards.single.activeConnections == 1);
    await manager.stop(forward.id);
    await done.timeout(const Duration(seconds: 3));
    expect(manager.forwards, isEmpty);
  });

  test(
    'remote refusal leaves an inspectable error and the SSH session alive',
    () async {
      client.refuseRemote = true;
      await expectLater(
        manager.start(remote(80)),
        throwsA(isA<SshPortForwardException>()),
      );
      expect(manager.forwards.single.status, SshPortForwardStatus.failed);
      expect(manager.forwards.single.error, contains('refused'));
      expect(client.isClosed, isFalse);
      await manager.stop(manager.forwards.single.id);
      expect(manager.forwards, isEmpty);
    },
  );

  test('unconfirmed remote cancellation closes SSH so the listener cannot remain active', () async {
    final forward = await manager.start(remote(80));
    client.refuseCancellation = true;
    await expectLater(
      manager.stop(forward.id),
      throwsA(isA<SshPortForwardException>()),
    );
    expect(client.isClosed, isTrue);
    await until(() => manager.isClosed);
    await expectLater(
      Socket.connect('127.0.0.1', forward.port),
      throwsA(isA<SocketException>()),
    );
  });

  test('occupied port failure does not disturb an existing forward', () async {
    final target = await echo();
    final running = await manager.start(local(target.port));
    await expectLater(
      manager.start(
        SshPortForwardSpec(
          kind: SshPortForwardKind.local,
          bindPort: running.port,
          targetHost: 'localhost',
          targetPort: 80,
        ),
      ),
      throwsA(isA<SshPortForwardException>()),
    );
    expect(manager.forwards.first.status, SshPortForwardStatus.active);
    expect(manager.forwards.last.status, SshPortForwardStatus.failed);
    expect(client.isClosed, isFalse);
  });

  test('forward limit includes pending requests and failed records', () async {
    client.refuseRemote = true;
    for (var i = 0; i < SshPortForwarding.maximumForwards; i++) {
      await expectLater(
        manager.start(remote(80)),
        throwsA(isA<SshPortForwardException>()),
      );
    }
    await expectLater(
      manager.start(local(80)),
      throwsA(isA<SshPortForwardException>()),
    );
    expect(manager.forwards, hasLength(16));
    await manager.stop(manager.forwards.first.id);
    expect(
      (await manager.start(local(80))).status,
      SshPortForwardStatus.active,
    );
  });

  test(
    'late local channel is destroyed after the listener is stopped',
    () async {
      final pending = client.pendingLocal = Completer<SSHForwardChannel>();
      final forward = await manager.start(local(80));
      final socket = await connect(forward.port);
      final done = socket.drain<void>();
      await until(() => client.requests.isNotEmpty);
      await manager.stop(forward.id);
      final late = _UnconnectedChannel();
      pending.complete(late);
      await until(() => late.destroyed);
      await done.timeout(const Duration(seconds: 3));
      expect(manager.forwards, isEmpty);
    },
  );

  test('late local channel is destroyed after dial timeout', () async {
    await manager.close();
    manager = SshPortForwarding(
      client,
      connectTimeout: const Duration(milliseconds: 30),
    );
    final pending = client.pendingLocal = Completer<SSHForwardChannel>();
    final forward = await manager.start(local(80));
    final socket = await connect(forward.port);
    final done = socket.drain<void>();
    await done.timeout(const Duration(seconds: 3));
    final late = _UnconnectedChannel();
    pending.complete(late);
    await until(() => late.destroyed);
    expect(manager.forwards.single.activeConnections, 0);
    expect(manager.forwards.single.error, contains('timed out'));
  });

  test(
    'stopping an unacknowledged remote listener closes the SSH route',
    () async {
      final pending = client.pendingRemote = Completer<SSHRemoteForward?>();
      final starting = manager.start(remote(80));
      final failure = expectLater(
        starting,
        throwsA(isA<SshPortForwardException>()),
      );
      final late = await client.makeRemote('127.0.0.1', 0);
      final accepted = await connect(late.port);
      final acceptedDone = accepted.drain<void>();
      await until(() => late.clients.isNotEmpty);
      await expectLater(
        manager.stop(manager.forwards.single.id),
        throwsA(isA<SshPortForwardException>()),
      );
      pending.complete(late);
      await failure;
      await manager.close();
      await acceptedDone.timeout(const Duration(seconds: 3));
      expect(late.clients.single.destroyed, isTrue);
      expect(client.isClosed, isTrue);
      expect(manager.forwards, isEmpty);
    },
  );

  test(
    'unacknowledged remote timeout closes the transport before a late reply',
    () async {
      await manager.close();
      manager = SshPortForwarding(
        client,
        connectTimeout: const Duration(milliseconds: 30),
      );
      final pending = client.pendingRemote = Completer<SSHRemoteForward?>();
      final late = await client.makeRemote('127.0.0.1', 0);
      await expectLater(
        manager.start(remote(80)),
        throwsA(isA<SshPortForwardException>()),
      );
      expect(client.isClosed, isTrue);
      pending.complete(late);
      await manager.close();
      expect(manager.forwards, isEmpty);
      await expectLater(
        Socket.connect('127.0.0.1', late.port),
        throwsA(isA<SocketException>()),
      );
    },
  );

  test('a remote create that never replies cannot keep the connection alive after timeout', () async {
    await manager.close();
    manager = SshPortForwarding(
      client,
      connectTimeout: const Duration(milliseconds: 30),
    );
    client.pendingRemote = Completer<SSHRemoteForward?>();
    await expectLater(
      manager.start(remote(80)),
      throwsA(isA<SshPortForwardException>()),
    );
    expect(client.isClosed, isTrue);
    await manager.close();
    expect(manager.forwards, isEmpty);
  });

  test(
    'Stop closes SSH even when a pending remote create never replies',
    () async {
      await manager.close();
      manager = SshPortForwarding(
        client,
        connectTimeout: const Duration(milliseconds: 30),
      );
      client.pendingRemote = Completer<SSHRemoteForward?>();
      final starting = manager.start(remote(80));
      final failure = expectLater(
        starting,
        throwsA(isA<SshPortForwardException>()),
      );
      await expectLater(
        manager.stop(manager.forwards.single.id),
        throwsA(isA<SshPortForwardException>()),
      );
      expect(client.isClosed, isTrue);
      await failure;
      await manager.close();
      expect(manager.forwards, isEmpty);
    },
  );

  test('32-client limit applies before a SOCKS handshake completes', () async {
    final forward = await manager.start(
      SshPortForwardSpec(kind: SshPortForwardKind.dynamic),
    );
    for (var i = 0; i < SshPortForwarding.maximumConnections; i++) {
      await connect(forward.port);
    }
    await until(() => manager.forwards.single.activeConnections == 32);
    final excess = await connect(forward.port);
    await excess.drain<void>().timeout(const Duration(seconds: 3));
    expect(manager.forwards.single.activeConnections, 32);
    expect(client.requests, isEmpty);
    await manager.stop(forward.id);
    expect(manager.forwards, isEmpty);
  });

  test('SOCKS fragmented greeting and request preserve pipelined application bytes', () async {
    final target = await echo();
    final forward = await manager.start(
      SshPortForwardSpec(kind: SshPortForwardKind.dynamic),
    );
    final socket = await connect(forward.port);
    final reader = _Read(socket);
    addTearDown(reader.cancel);
    for (final byte in [5, 1, 0]) {
      socket.add([byte]);
      await socket.flush();
    }
    expect(await reader.read(2), [5, 0]);
    final payload = utf8.encode('socks-✓');
    final request = [
      5,
      1,
      0,
      1,
      127,
      0,
      0,
      1,
      target.port >> 8,
      target.port & 255,
    ];
    for (final byte in request.take(9)) {
      socket.add([byte]);
      await socket.flush();
    }
    socket.add([request.last, ...payload]);
    final reply = await reader.read(10);
    expect(reply.take(2), [5, 0]);
    expect(await reader.read(payload.length), payload);
  });

  test(
    'SOCKS domain names are sent to the SSH server without local resolution',
    () async {
      final target = await echo();
      client.targetOverride = ('127.0.0.1', target.port);
      final forward = await manager.start(
        SshPortForwardSpec(kind: SshPortForwardKind.dynamic),
      );
      final socket = await connect(forward.port);
      final reader = _Read(socket);
      addTearDown(reader.cancel);
      final host = ascii.encode('only.on.remote.invalid');
      socket.add([5, 1, 0, 5, 1, 0, 3, host.length, ...host, 1, 187, 65]);
      expect(await reader.read(2), [5, 0]);
      expect((await reader.read(10))[1], 0);
      expect(await reader.read(1), [65]);
      expect(client.requests.single, ('only.on.remote.invalid', 443));
    },
  );

  test(
    'SOCKS IPv6 target is decoded without requiring a local IPv6 server',
    () async {
      final target = await echo();
      client.targetOverride = ('127.0.0.1', target.port);
      final forward = await manager.start(
        SshPortForwardSpec(kind: SshPortForwardKind.dynamic),
      );
      final socket = await connect(forward.port);
      final reader = _Read(socket);
      addTearDown(reader.cancel);
      socket.add([5, 1, 0, 5, 1, 0, 4, ...List.filled(15, 0), 1, 0, 80]);
      expect(await reader.read(2), [5, 0]);
      expect((await reader.read(10))[1], 0);
      expect(client.requests.single, ('::1', 80));
    },
  );

  test(
    'SOCKS no-auth negotiation rejects unsupported authentication',
    () async {
      final forward = await manager.start(
        SshPortForwardSpec(kind: SshPortForwardKind.dynamic),
      );
      final socket = await connect(forward.port);
      final response = socket.fold<List<int>>(
        [],
        (all, chunk) => all..addAll(chunk),
      );
      socket.add([5, 1, 2]);
      expect(await response.timeout(const Duration(seconds: 3)), [5, 255]);
      expect(client.requests, isEmpty);
    },
  );

  for (final example in <(String, List<int>, int)>[
    ('BIND', [5, 2, 0, 1], 7),
    ('UDP', [5, 3, 0, 1], 7),
    ('reserved byte', [5, 1, 1, 1], 1),
    ('address type', [5, 1, 0, 9], 8),
    ('empty domain', [5, 1, 0, 3, 0], 8),
    ('control in domain', [5, 1, 0, 3, 1, 0], 8),
    ('zero port', [5, 1, 0, 1, 127, 0, 0, 1, 0, 0], 1),
  ]) {
    test('SOCKS rejects ${example.$1} before opening a channel', () async {
      final forward = await manager.start(
        SshPortForwardSpec(kind: SshPortForwardKind.dynamic),
      );
      final socket = await connect(forward.port);
      final response = socket.fold<List<int>>(
        [],
        (all, chunk) => all..addAll(chunk),
      );
      socket.add([5, 1, 0, ...example.$2]);
      final bytes = await response.timeout(const Duration(seconds: 3));
      expect(bytes.take(2), [5, 0]);
      expect(bytes[3], example.$3);
      expect(client.requests, isEmpty);
    });
  }

  test(
    'stalled SOCKS handshake expires and frees its connection slot',
    () async {
      await manager.close();
      manager = SshPortForwarding(
        client,
        handshakeTimeout: const Duration(milliseconds: 30),
      );
      final forward = await manager.start(
        SshPortForwardSpec(kind: SshPortForwardKind.dynamic),
      );
      final socket = await connect(forward.port);
      socket.add([5]);
      await socket.drain<void>().timeout(const Duration(seconds: 3));
      await until(() => manager.forwards.single.activeConnections == 0);
      expect(client.requests, isEmpty);
    },
  );

  test(
    'SSH client closure stops every listener and rejects new requests',
    () async {
      final forward = await manager.start(local(80));
      await client.close();
      await manager.close();
      expect(manager.isClosed, isTrue);
      expect(manager.forwards, isEmpty);
      await expectLater(
        Socket.connect('127.0.0.1', forward.port),
        throwsA(isA<SocketException>()),
      );
      await expectLater(
        manager.start(local(80)),
        throwsA(isA<SshPortForwardException>()),
      );
    },
  );

  test(
    'service owns a manager per connection and closes it on disconnect',
    () async {
      final service = SshTerminalService(
        secureStorage: InMemorySecureStorage(),
        clientConnector: (
          host,
          port, {
          required username,
          password,
          identities,
          gateway,
        }) async => client,
      );
      addTearDown(service.dispose);
      final session = await service.connect(
        'test.invalid',
        22,
        'test',
        'password',
      );
      final owned = service.forwarding(session.id);
      expect(identical(owned, service.forwarding(session.id)), isTrue);
      final forward = await owned.start(local(80));
      await service.disconnect(session.id);
      expect(owned.isClosed, isTrue);
      expect(owned.forwards, isEmpty);
      await expectLater(
        Socket.connect('127.0.0.1', forward.port),
        throwsA(isA<SocketException>()),
      );
    },
  );
}

Future<void> until(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) fail('Condition did not become true');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class _Client implements SSHClient {
  final completed = Completer<void>();
  final requests = <(String, int)>[];
  final remotes = <_Remote>[];
  final channels = <_Channel>[];
  Completer<SSHForwardChannel>? pendingLocal;
  Completer<SSHRemoteForward?>? pendingRemote;
  (String, int)? targetOverride;
  bool refuseRemote = false;
  bool refuseCancellation = false;
  int cancellations = 0;
  @override
  bool isClosed = false;
  @override
  Future<void> get authenticated => Future<void>.value();
  @override
  Future<void> get done => completed.future;
  @override
  Future<SSHForwardChannel> forwardLocal(
    String remoteHost,
    int remotePort, {
    String localHost = 'localhost',
    int localPort = 0,
  }) async {
    requests.add((remoteHost, remotePort));
    if (pendingLocal != null) return pendingLocal!.future;
    final target = targetOverride ?? (remoteHost, remotePort);
    final channel = _Channel(await Socket.connect(target.$1, target.$2));
    channels.add(channel);
    return channel;
  }

  Future<_Remote> makeRemote(String host, int port) async {
    final remote = _Remote(await ServerSocket.bind(host, port));
    remotes.add(remote);
    return remote;
  }

  @override
  Future<SSHRemoteForward?> forwardRemote({
    String? host,
    int? port,
    SSHRemoteConnectionFilter? filter,
  }) async {
    if (pendingRemote != null) return pendingRemote!.future;
    if (refuseRemote) return null;
    return makeRemote(host!, port!);
  }

  @override
  Future<bool> cancelForwardRemote(SSHRemoteForward forward) async {
    cancellations++;
    if (refuseCancellation) return false;
    await (forward as _Remote).stopListening();
    return true;
  }

  @override
  Future<void> close() async {
    if (isClosed) return;
    isClosed = true;
    completed.complete();
    for (final remote in remotes) {
      await remote.shutdown();
    }
    for (final channel in channels) {
      channel.destroy();
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Remote implements SSHRemoteForward {
  _Remote(this.server) : host = server.address.address, port = server.port {
    subscription = server.listen((socket) {
      final channel = _Channel(socket);
      clients.add(channel);
      controller.add(channel);
    });
  }
  final ServerSocket server;
  final controller = StreamController<SSHForwardChannel>();
  final clients = <_Channel>[];
  late final StreamSubscription<Socket> subscription;
  Future<void>? closing;
  @override
  final String host;
  @override
  final int port;
  @override
  Stream<SSHForwardChannel> get connections => controller.stream;
  Future<void> stopListening() => closing ??= () async {
    await server.close();
    await subscription.cancel();
    unawaited(controller.close());
  }();
  Future<void> shutdown() async {
    for (final channel in clients) {
      channel.destroy();
    }
    await stopListening();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Channel implements SSHForwardChannel {
  _Channel(this.socket);
  final Socket socket;
  bool destroyed = false;
  @override
  Stream<Uint8List> get stream => socket;
  @override
  StreamSink<List<int>> get sink => socket;
  @override
  Future<void> get done => socket.done;
  @override
  Future<void> close() async => socket.close();
  @override
  void destroy() {
    destroyed = true;
    socket.destroy();
  }

  @override
  Future<void> flush() => socket.flush();
}

class _UnconnectedChannel implements SSHForwardChannel {
  bool destroyed = false;
  final complete = Completer<void>();
  @override
  Future<void> get done => complete.future;
  @override
  void destroy() {
    destroyed = true;
    if (!complete.isCompleted) complete.complete();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Echo {
  _Echo(this.server, this.afterEof) {
    subscription = server.listen((socket) {
      clients.add(socket);
      final bytes = <int>[];
      socket.listen(
        (chunk) {
          if (afterEof) {
            bytes.addAll(chunk);
          } else {
            socket.add(chunk);
          }
        },
        onDone: () async {
          if (afterEof) socket.add([...utf8.encode('reply:'), ...bytes]);
          await socket.close();
        },
        onError: (Object _) => socket.destroy(),
      );
    });
  }
  static Future<_Echo> create({required bool afterEof}) async =>
      _Echo(await ServerSocket.bind('127.0.0.1', 0), afterEof);
  final ServerSocket server;
  final bool afterEof;
  final clients = <Socket>[];
  late final StreamSubscription<Socket> subscription;
  int get port => server.port;
  Future<void> close() async {
    await server.close();
    await subscription.cancel();
    for (final socket in clients) {
      socket.destroy();
    }
  }
}

class _Read {
  _Read(Socket socket) : iterator = StreamIterator(socket);
  final StreamIterator<Uint8List> iterator;
  Uint8List chunk = Uint8List(0);
  int offset = 0;
  Future<List<int>> read(int count) =>
      _read(count).timeout(const Duration(seconds: 3));
  Future<List<int>> _read(int count) async {
    final result = <int>[];
    while (result.length < count) {
      if (offset >= chunk.length) {
        if (!await iterator.moveNext()) fail('Unexpected EOF');
        chunk = iterator.current;
        offset = 0;
      }
      result.add(chunk[offset++]);
    }
    return result;
  }

  Future<void> cancel() => iterator.cancel();
}
