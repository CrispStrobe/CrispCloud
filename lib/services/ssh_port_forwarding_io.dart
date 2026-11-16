import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import 'ssh_port_forwarding.dart';

const sshPortForwardingSupported = true;

SshPortForwarding createSshPortForwarding(
  SSHClient client, {
  VoidCallback? onActivity,
  required Duration connectTimeout,
  required Duration handshakeTimeout,
}) => _NativeForwarding(client, onActivity, connectTimeout, handshakeTimeout);

class _NativeForwarding extends SshPortForwarding {
  _NativeForwarding(
    this.client,
    this.onActivity,
    this.connectTimeout,
    this.handshakeTimeout,
  ) : super.base() {
    if (connectTimeout <= Duration.zero || handshakeTimeout <= Duration.zero) {
      throw ArgumentError('Forwarding timeouts must be positive.');
    }
    unawaited(
      client.done.then<void>(
        (_) => close(),
        onError: (Object _, StackTrace __) => close(),
      ),
    );
  }

  final SSHClient client;
  final VoidCallback? onActivity;
  final Duration connectTimeout;
  final Duration handshakeTimeout;
  final _entries = <String, _Forward>{};
  int _nextId = 1;
  bool _closed = false;
  Future<void>? _closing;
  bool _disposed = false;

  @override
  bool get isClosed => _closed;

  @override
  List<SshPortForwardSnapshot> get forwards =>
      List.unmodifiable(_entries.values.map((entry) => entry.snapshot));

  void changed() {
    if (!_disposed) notifyListeners();
  }

  bool current(_Forward entry) =>
      !_closed &&
      !client.isClosed &&
      entry.live &&
      identical(_entries[entry.id], entry);

  @override
  Future<SshPortForwardSnapshot> start(SshPortForwardSpec spec) async {
    if (_closed || client.isClosed) {
      throw const SshPortForwardException('The SSH connection is closed.');
    }
    if (_entries.length >= SshPortForwarding.maximumForwards) {
      throw const SshPortForwardException(
        'The connection has reached its limit of 16 forwards.',
      );
    }
    final entry = _Forward('forward-${_nextId++}', spec);
    _entries[entry.id] = entry;
    changed();
    try {
      if (!current(entry)) {
        throw const SshPortForwardException('Forwarding was cancelled.');
      }
      if (spec.kind == SshPortForwardKind.remote) {
        entry.remoteOpening = true;
        final pending = client.forwardRemote(
          host: spec.bindHost,
          port: spec.bindPort,
          filter: (_, __) =>
              current(entry) &&
              entry.peers.length < SshPortForwarding.maximumConnections,
        );
        // A timeout/cancel does not cancel an SSH request. Its late reply still
        // belongs to this request and must revoke any server-side listener.
        unawaited(
          pending.then<void>((remote) async {
            if (remote != null && !current(entry)) {
              try {
                await cancelRemote(remote, unclaimed: true);
              } catch (_) {}
            }
          }, onError: (Object _, StackTrace __) {}),
        );
        final remote = await pending.timeout(connectTimeout);
        entry.remoteOpening = false;
        if (remote == null) {
          throw const SshPortForwardException(
            'The SSH server refused remote forwarding.',
          );
        }
        if (!current(entry)) {
          await cancelRemote(remote, unclaimed: true);
          throw const SshPortForwardException('Forwarding was cancelled.');
        }
        entry.remote = remote;
        entry.port = remote.port;
        entry.remoteSubscription = remote.connections.listen(
          (channel) => acceptRemote(entry, channel),
          onError: (Object _, StackTrace __) => listenerFailed(entry),
          onDone: () {
            if (current(entry)) listenerFailed(entry);
          },
        );
      } else {
        final pending = ServerSocket.bind(
          spec.bindHost,
          spec.bindPort,
          shared: false,
          v6Only: spec.bindHost == '::1',
        );
        unawaited(
          pending.then<void>((server) async {
            if (!current(entry)) await server.close();
          }, onError: (Object _, StackTrace __) {}),
        );
        final server = await pending.timeout(connectTimeout);
        if (!current(entry)) {
          await server.close();
          throw const SshPortForwardException('Forwarding was cancelled.');
        }
        entry.server = server;
        entry.port = server.port;
        entry.localSubscription = server.listen(
          (socket) => acceptLocal(entry, socket),
          onError: (Object _, StackTrace __) => listenerFailed(entry),
          onDone: () {
            if (current(entry)) listenerFailed(entry);
          },
        );
      }
      if (entry.port < 1 || entry.port > 65535) {
        throw const SshPortForwardException(
          'The server returned an invalid listening port.',
        );
      }
      entry.status = SshPortForwardStatus.active;
      onActivity?.call();
      changed();
      return entry.snapshot;
    } catch (error) {
      entry.live = false;
      var message = error is SshPortForwardException
          ? error.message
          : error is TimeoutException
          ? 'Starting the forward timed out.'
          : 'The forwarding listener could not be started.';
      try {
        await release(entry);
      } on SshPortForwardException catch (cleanup) {
        message = cleanup.message;
      }
      if (identical(_entries[entry.id], entry) && !_closed) {
        entry.status = SshPortForwardStatus.failed;
        entry.error = message;
        changed();
      }
      throw SshPortForwardException(message);
    }
  }

  void acceptLocal(_Forward entry, Socket socket) {
    if (!current(entry) ||
        entry.peers.length >= SshPortForwarding.maximumConnections) {
      socket.destroy();
      return;
    }
    final peer = _Peer(this, entry, socket: socket);
    entry.peers.add(peer);
    changed();
    unawaited(peer.openLocal());
  }

  void acceptRemote(_Forward entry, SSHForwardChannel channel) {
    if (!current(entry) ||
        entry.peers.length >= SshPortForwarding.maximumConnections) {
      _destroyChannel(channel);
      return;
    }
    final peer = _Peer(this, entry, channel: channel);
    entry.peers.add(peer);
    changed();
    unawaited(peer.openRemote());
  }

  void listenerFailed(_Forward entry) {
    if (!current(entry)) return;
    entry.live = false;
    entry.status = SshPortForwardStatus.failed;
    entry.error = 'The forwarding listener stopped unexpectedly.';
    changed();
    unawaited(release(entry).catchError((Object _) {}));
  }

  // dartssh2 removes the listener from its routing table before awaiting the
  // cancel reply. If cancellation fails, retry cannot revoke it. Closing the
  // SSH transport is the only reliable way to stop that remote listener.
  final _remoteCancellations = Expando<Future<void>>();
  Future<void> cancelRemote(
    SSHRemoteForward remote, {
    bool unclaimed = false,
  }) => _remoteCancellations[remote] ??= () async {
    // A late listener has never had a consumer. Drain any channel already
    // queued before cancellation instead of dropping its owned resources.
    final drain = unclaimed
        ? remote.connections.listen(
            _destroyChannel,
            onError: (Object _, StackTrace __) {},
          )
        : null;
    try {
      if (client.isClosed) return;
      if (!await client.cancelForwardRemote(remote).timeout(connectTimeout)) {
        throw StateError('Cancellation rejected');
      }
    } catch (_) {
      await closeClientTransport();
      throw const SshPortForwardException(
        'The server did not confirm stopping the forward; the SSH connection was closed.',
      );
    } finally {
      if (drain != null) {
        await Future<void>.delayed(Duration.zero);
        await drain.cancel();
      }
    }
  }();

  Future<void>? _clientClosing;
  Future<void> closeClientTransport() => _clientClosing ??= () async {
    Future<void>? closing;
    try {
      closing = client.close();
    } catch (_) {}
    try {
      client.socket.destroy();
    } catch (_) {}
    try {
      await closing?.timeout(const Duration(seconds: 2));
    } catch (_) {}
  }();

  Future<void> release(_Forward entry) => entry.releasing ??= () async {
    for (final peer in entry.peers.toList()) {
      peer.close();
    }
    Object? failure;
    if (entry.remoteOpening && entry.remote == null && !client.isClosed) {
      // The server may have created a listener even if its global-request
      // reply never arrives. There is no assigned port to cancel in that case.
      // Stop/timeout must not leave an unowned server listener behind.
      await closeClientTransport();
      failure = const SshPortForwardException(
        'The remote forwarding request could not be confirmed; the SSH connection was closed.',
      );
    }
    try {
      await entry.server?.close();
      final remote = entry.remote;
      if (remote != null) await cancelRemote(remote);
    } catch (error) {
      failure = error;
    }
    // Keep rejecting accepted connections while listener cancellation drains.
    await Future<void>.delayed(Duration.zero);
    await entry.localSubscription?.cancel();
    await entry.remoteSubscription?.cancel();
    if (failure != null) throw failure;
  }();

  @override
  Future<void> stop(String id) async {
    final entry = _entries[id];
    if (entry == null) return;
    entry.live = false;
    entry.status = SshPortForwardStatus.stopping;
    changed();
    try {
      await release(entry);
    } finally {
      _entries.remove(id);
      changed();
    }
  }

  @override
  Future<void> close() => _closing ??= () async {
    _closed = true;
    final entries = _entries.values.toList();
    for (final entry in entries) {
      entry.live = false;
    }
    changed();
    await Future.wait(
      entries.map((entry) => release(entry).catchError((Object _) {})),
    );
    _entries.clear();
    changed();
  }();

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(close());
    super.dispose();
  }
}

class _Forward {
  _Forward(this.id, this.spec) : port = spec.bindPort;
  final String id;
  final SshPortForwardSpec spec;
  int port;
  bool live = true;
  SshPortForwardStatus status = SshPortForwardStatus.starting;
  String? error;
  ServerSocket? server;
  SSHRemoteForward? remote;
  bool remoteOpening = false;
  StreamSubscription<Socket>? localSubscription;
  StreamSubscription<SSHForwardChannel>? remoteSubscription;
  Future<void>? releasing;
  final peers = <_Peer>{};

  SshPortForwardSnapshot get snapshot => SshPortForwardSnapshot(
    id: id,
    spec: spec,
    status: status,
    port: port,
    activeConnections: peers.length,
    error: error,
  );
}

/// Owns even partially established connections, including a SOCKS negotiation
/// or a socket/channel which arrives after its owner was stopped.
class _Peer {
  _Peer(this.owner, this.forward, {this.socket, this.channel}) {
    if (socket != null) _observeDone(socket!.done);
    if (channel != null) _observeDone(channel!.done);
  }
  final _NativeForwarding owner;
  final _Forward forward;
  Socket? socket;
  SSHForwardChannel? channel;
  _SocketReader? reader;
  bool closed = false;
  bool get current => !closed && owner.current(forward);

  Future<void> openLocal() async {
    var socksReady = false;
    try {
      final local = socket!;
      final input = reader = _SocketReader(local);
      final _Target target;
      if (forward.spec.kind == SshPortForwardKind.dynamic) {
        target = await _negotiate(input, local).timeout(owner.handshakeTimeout);
        socksReady = true;
      } else {
        target = _Target(forward.spec.targetHost!, forward.spec.targetPort!);
      }
      if (!current) return;
      final pending = owner.client.forwardLocal(
        target.host,
        target.port,
        localHost: local.remoteAddress.address,
        localPort: local.remotePort,
      );
      unawaited(
        pending.then<void>((late) {
          if (!current) _destroyChannel(late);
        }, onError: (Object _, StackTrace __) {}),
      );
      final remote = await pending.timeout(owner.connectTimeout);
      if (!current) {
        _destroyChannel(remote);
        return;
      }
      channel = remote;
      _observeDone(remote.done);
      if (socksReady) {
        local.add(_socksReply(0));
        await local.flush();
        socksReady = false;
      }
      await pump(input.remaining(), local, remote);
    } catch (error) {
      if (current) {
        if (socksReady) {
          socket?.add(_socksReply(4));
          try {
            await socket?.flush().timeout(const Duration(seconds: 1));
          } catch (_) {}
        }
        if (error is! _SocksRejection) {
          forward.error = error is TimeoutException
              ? 'A forwarded connection timed out.'
              : 'A forwarded connection could not reach its destination.';
          owner.changed();
        }
      }
    } finally {
      close();
    }
  }

  Future<void> openRemote() async {
    try {
      final pending = Socket.connect(
        forward.spec.targetHost!,
        forward.spec.targetPort!,
        timeout: owner.connectTimeout,
      );
      unawaited(
        pending.then<void>((late) {
          if (!current) {
            _observeDone(late.done);
            late.destroy();
          }
        }, onError: (Object _, StackTrace __) {}),
      );
      final local = await pending.timeout(owner.connectTimeout);
      if (!current) {
        local.destroy();
        return;
      }
      socket = local;
      _observeDone(local.done);
      await pump(local, local, channel!);
    } catch (error) {
      if (current) {
        forward.error = error is TimeoutException
            ? 'A forwarded connection timed out.'
            : 'A forwarded connection could not reach its destination.';
        owner.changed();
      }
    } finally {
      close();
    }
  }

  Future<void> pump(
    Stream<List<int>> input,
    Socket local,
    SSHForwardChannel remote,
  ) async {
    owner.onActivity?.call();
    unawaited(
      remote.done.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
    );
    Stream<List<int>> active(Stream<List<int>> stream) => stream.map((data) {
      if (!current) throw const _ForwardCancelled();
      owner.onActivity?.call();
      return data;
    });
    // Each pipe closes only its output direction on EOF. The other direction
    // remains alive for a response after a request half-close. addStream/pipe
    // propagates stream pause/resume instead of accumulating output in a list.
    final upload = active(input).pipe(remote.sink);
    final download = active(remote.stream).pipe(local);
    await Future.wait<void>([
      upload.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          close();
          Error.throwWithStackTrace(error, stack);
        },
      ),
      download.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          close();
          Error.throwWithStackTrace(error, stack);
        },
      ),
    ], eagerError: true);
  }

  void close() {
    if (closed) return;
    closed = true;
    socket?.destroy();
    final remote = channel;
    if (remote != null) _destroyChannel(remote);
    unawaited(reader?.cancel() ?? Future<void>.value());
    forward.peers.remove(this);
    owner.changed();
  }
}

void _destroyChannel(SSHForwardChannel channel) {
  try {
    unawaited(
      channel.done.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
    );
    channel.destroy();
  } catch (_) {}
}

void _observeDone(Future<dynamic> done) {
  unawaited(done.then<void>((_) {}, onError: (Object _, StackTrace __) {}));
}

class _ForwardCancelled implements Exception {
  const _ForwardCancelled();
}

class _SocksRejection implements Exception {}

class _Target {
  const _Target(this.host, this.port);
  final String host;
  final int port;
}

List<int> _socksReply(int code) => [5, code, 0, 1, 0, 0, 0, 0, 0, 0];

Future<_Target> _negotiate(_SocketReader reader, Socket socket) async {
  Future<Never> reject(List<int> reply) async {
    socket.add(reply);
    await socket.flush();
    throw _SocksRejection();
  }

  final greeting = await reader.read(2);
  if (greeting[0] != 5 || greeting[1] == 0) return reject([5, 255]);
  final methods = await reader.read(greeting[1]);
  if (!methods.contains(0)) return reject([5, 255]);
  socket.add([5, 0]);
  await socket.flush();
  final request = await reader.read(4);
  if (request[0] != 5 || request[2] != 0) return reject(_socksReply(1));
  if (request[1] != 1) return reject(_socksReply(7));
  final String host;
  switch (request[3]) {
    case 1:
      host = (await reader.read(4)).join('.');
    case 3:
      final length = (await reader.read(1)).single;
      if (length == 0) return reject(_socksReply(8));
      final bytes = await reader.read(length);
      if (bytes.any((byte) => byte > 127)) return reject(_socksReply(8));
      host = ascii.decode(bytes);
      if (!SshPortForwardSpec.isValidTargetHost(host) || host.contains(':')) {
        return reject(_socksReply(8));
      }
    case 4:
      host = InternetAddress.fromRawAddress(await reader.read(16)).address;
    default:
      return reject(_socksReply(8));
  }
  final bytes = await reader.read(2);
  final port = (bytes[0] << 8) | bytes[1];
  if (port == 0) return reject(_socksReply(1));
  return _Target(host, port);
}

/// One bounded socket chunk plus at most a SOCKS field (255 bytes). The
/// iterator pauses the socket between reads and hands pipelined application
/// bytes to the tunnel exactly once when negotiation finishes.
class _SocketReader {
  _SocketReader(Stream<Uint8List> stream) : _iterator = StreamIterator(stream);
  final StreamIterator<Uint8List> _iterator;
  Uint8List _chunk = Uint8List(0);
  int _offset = 0;
  bool _cancelled = false;

  Future<Uint8List> read(int count) async {
    final result = Uint8List(count);
    var written = 0;
    while (written < count) {
      if (_cancelled) throw const _ForwardCancelled();
      if (_offset == _chunk.length) {
        if (!await _iterator.moveNext()) throw const _ForwardCancelled();
        _chunk = _iterator.current;
        _offset = 0;
      }
      final available = _chunk.length - _offset;
      final remaining = count - written;
      final take = available < remaining ? available : remaining;
      result.setRange(written, written + take, _chunk, _offset);
      written += take;
      _offset += take;
    }
    return result;
  }

  Stream<Uint8List> remaining() async* {
    if (_offset < _chunk.length) yield Uint8List.sublistView(_chunk, _offset);
    _chunk = Uint8List(0);
    while (!_cancelled && await _iterator.moveNext()) {
      yield _iterator.current;
    }
  }

  Future<void> cancel() async {
    if (_cancelled) return;
    _cancelled = true;
    try {
      await _iterator.cancel();
    } catch (_) {}
  }
}
