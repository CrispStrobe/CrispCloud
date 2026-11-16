import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'ssh_agent_stub.dart'
    if (dart.library.io) 'ssh_agent_io.dart'
    as platform;

/// A single local agent transaction. Implementations own the underlying socket;
/// [destroy] must synchronously revoke further writes and release its handle.
abstract interface class SshAgentTransport {
  Stream<List<int>> get input;
  void add(Uint8List bytes);
  void destroy();
}

typedef SshAgentTransportConnector = Future<SshAgentTransport> Function();
typedef SshAgentFactory = SshAgentConnection Function({
  required bool Function() isCurrent,
});

class SshAgentException implements Exception {
  const SshAgentException(this.message);
  final String message;
  @override
  String toString() => message;

  static const unsupported =
      'SSH agent access requires the Linux or macOS native app.';
  static const unavailable =
      'No SSH agent is available. Start an agent and set SSH_AUTH_SOCK before opening CrispCloud.';
  static const connection = 'Could not connect to the local SSH agent.';
  static const empty = 'The SSH agent has no supported keys.';
  static const refused = 'The SSH agent refused the signature request.';
  static const invalid = 'The SSH agent returned an invalid response.';
  static const timeout = 'The SSH agent did not respond in time.';
  static const closed = 'SSH agent access has ended.';
  static const busy = 'The SSH agent request limit was reached.';
}

/// The agent authority for one SSH route. Only public keys enter the application;
/// signing stays in the local agent. Every transaction owns a separate socket,
/// a deadline, bounded framing, and cancellation. Close revokes active and late
/// sockets before the SSH route can be replaced.
class SshAgentConnection implements SSHAgentHandler {
  SshAgentConnection({
    required this._connect,
    required this._isCurrent,
    this.requestTimeout = const Duration(seconds: 10),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  factory SshAgentConnection.system({required bool Function() isCurrent}) =>
      platform.createSystemSshAgent(isCurrent: isCurrent);

  static bool get supported => platform.sshAgentSupported;
  static bool get available => platform.sshAgentAvailable;
  static const maximumFrameLength = 256 * 1024;
  static const maximumKeys = 64;
  static const maximumKeyLength = 16 * 1024;
  static const maximumCommentLength = 1024;
  static const maximumSigningDataLength = 240 * 1024;
  static const maximumConcurrentRequests = 4;
  static const maximumForwardRequestsPerSecond = 32;

  final SshAgentTransportConnector _connect;
  final bool Function() _isCurrent;
  final DateTime Function() _clock;
  final Duration requestTimeout;
  final _requests = <_AgentTransaction>{};
  final _keys = <String, _AgentKey>{};
  List<SSHIdentity>? _identities;
  Future<List<SSHIdentity>>? _loading;
  bool _closed = false;
  DateTime? _forwardWindow;
  int _forwardRequests = 0;

  bool get isClosed => _closed || !_isCurrent();

  void _ensureCurrent() {
    if (isClosed) throw const SshAgentException(SshAgentException.closed);
  }

  /// Snapshot an allowlist once. Newly added agent keys never appear through an
  /// already forwarded connection. Unknown key families are skipped, and an
  /// empty supported set fails instead of falling back to password auth.
  Future<List<SSHIdentity>> loadIdentities() {
    _ensureCurrent();
    return _loading ??= _loadIdentities();
  }

  Future<List<SSHIdentity>> _loadIdentities() async {
    final response = await _request(Uint8List.fromList([11]));
    _ensureCurrent();
    try {
      final reader = _Reader(response);
      if (reader.byte() != 12) _invalid();
      final count = reader.uint32();
      if (count > maximumKeys) _invalid();
      final accepted = <String, _AgentKey>{};
      for (var i = 0; i < count; i++) {
        final blob = reader.string(maximumKeyLength);
        final commentBytes = reader.string(maximumCommentLength);
        final comment = utf8.decode(commentBytes);
        final key = _AgentKey.parse(blob, comment);
        if (key != null) accepted.putIfAbsent(base64Encode(blob), () => key);
      }
      reader.end();
      if (accepted.isEmpty) {
        throw const SshAgentException(SshAgentException.empty);
      }
      _ensureCurrent();
      _keys.addAll(accepted);
      final identities = <SSHIdentity>[];
      for (final key in _keys.values) {
        for (final algorithm in key.algorithms) {
          identities.add(
            SSHIdentity.custom(
              type: algorithm,
              publicKey: SSHRawHostKey(Uint8List.fromList(key.blob)),
              comment: key.comment,
              shouldProbe: true,
              signer: (data) async {
                _ensureCurrent();
                return SSHRawSignature(await _sign(key, algorithm, data));
              },
            ),
          );
        }
      }
      return _identities = List.unmodifiable(identities);
    } on SshAgentException {
      rethrow;
    } catch (_) {
      throw const SshAgentException(SshAgentException.invalid);
    }
  }

  Future<Uint8List> _sign(
    _AgentKey key,
    String algorithm,
    Uint8List data,
  ) async {
    _ensureCurrent();
    if (data.isEmpty || data.length > maximumSigningDataLength) _invalid();
    final flags = switch (algorithm) {
      'rsa-sha2-512' => 4,
      'rsa-sha2-256' => 2,
      _ => 0,
    };
    final request = _Writer()
      ..byte(13)
      ..string(key.blob)
      ..string(data)
      ..uint32(flags);
    final response = await _request(request.take());
    _ensureCurrent();
    try {
      final reader = _Reader(response);
      final type = reader.byte();
      if (type == 5) {
        reader.end();
        throw const SshAgentException(SshAgentException.refused);
      }
      if (type != 14) _invalid();
      final signature = reader.string(maximumKeyLength);
      reader.end();
      final fields = _Reader(signature);
      if (utf8.decode(fields.string(128)) != algorithm) _invalid();
      final bytes = fields.string(maximumKeyLength);
      fields.end();
      if (bytes.isEmpty) _invalid();
      if (algorithm == 'ssh-ed25519' && bytes.length != 64) _invalid();
      if (algorithm.startsWith('rsa-') && bytes.length > 1024) _invalid();
      if (algorithm.startsWith('ecdsa-')) {
        final integers = _Reader(bytes);
        for (var i = 0; i < 2; i++) {
          final integer = integers.string(67);
          if (integer.isEmpty || integer.first & 0x80 != 0) _invalid();
        }
        integers.end();
      }
      return signature;
    } on SshAgentException {
      rethrow;
    } catch (_) {
      throw const SshAgentException(SshAgentException.invalid);
    }
  }

  /// Restricted forwarding: list and sign only, limited to this connection's
  /// original key snapshot. Agent mutation, locking and extensions are refused.
  /// All failures use the protocol's generic failure response and reveal no
  /// local socket paths, key comments from new keys, or backend errors.
  @override
  Future<Uint8List> handleRequest(Uint8List request) async {
    final failure = Uint8List.fromList([5]);
    if (isClosed ||
        _identities == null ||
        request.length > maximumFrameLength) {
      return failure;
    }
    final now = _clock();
    if (_forwardWindow == null ||
        now.difference(_forwardWindow!) >= const Duration(seconds: 1) ||
        now.isBefore(_forwardWindow!)) {
      _forwardWindow = now;
      _forwardRequests = 0;
    }
    if (++_forwardRequests > maximumForwardRequestsPerSecond) return failure;
    try {
      final reader = _Reader(request);
      switch (reader.byte()) {
        case 11:
          reader.end();
          final response = _Writer()
            ..byte(12)
            ..uint32(_keys.length);
          for (final key in _keys.values) {
            response
              ..string(key.blob)
              ..string(utf8.encode(key.comment));
          }
          return response.take();
        case 13:
          final blob = reader.string(maximumKeyLength);
          final data = reader.string(maximumSigningDataLength);
          final flags = reader.uint32();
          reader.end();
          final key = _keys[base64Encode(blob)];
          if (key == null) return failure;
          final algorithm = key.type == 'ssh-rsa'
              ? switch (flags) {
                  4 => 'rsa-sha2-512',
                  2 => 'rsa-sha2-256',
                  _ => null,
                }
              : flags == 0
              ? key.type
              : null;
          if (algorithm == null) return failure;
          final signature = await _sign(key, algorithm, data);
          if (isClosed) return failure;
          return (_Writer()
                ..byte(14)
                ..string(signature))
              .take();
        default:
          return failure;
      }
    } catch (_) {
      return failure;
    }
  }

  Future<Uint8List> _request(Uint8List bytes) async {
    _ensureCurrent();
    if (bytes.isEmpty || bytes.length > maximumFrameLength) _invalid();
    if (_requests.length >= maximumConcurrentRequests) {
      throw const SshAgentException(SshAgentException.busy);
    }
    final transaction = _AgentTransaction();
    _requests.add(transaction);
    try {
      final result = await transaction.run(
        _connect,
        bytes,
        timeout: requestTimeout,
        current: () => !isClosed,
      );
      _ensureCurrent();
      return result;
    } finally {
      transaction.close();
      _requests.remove(transaction);
    }
  }

  /// Revoke before awaiting any SSH client cleanup. Late agent socket opens
  /// are disposed by their already-canceled transaction, never reused.
  void close() {
    if (_closed) return;
    _closed = true;
    for (final request in _requests.toList()) {
      request.cancel();
    }
    _keys.clear();
    _identities = null;
  }
}

Never _invalid() => throw const SshAgentException(SshAgentException.invalid);

class _AgentKey {
  _AgentKey(this.blob, this.type, this.comment);
  final Uint8List blob;
  final String type;
  final String comment;

  List<String> get algorithms =>
      type == 'ssh-rsa' ? const ['rsa-sha2-512', 'rsa-sha2-256'] : [type];

  static _AgentKey? parse(Uint8List blob, String comment) {
    final reader = _Reader(blob);
    final type = utf8.decode(reader.string(128));
    switch (type) {
      case 'ssh-ed25519':
        if (reader.string(32).length != 32) _invalid();
      case 'ssh-rsa':
        final exponent = reader.string(8);
        final modulus = reader.string(1025);
        if (exponent.isEmpty ||
            exponent.first & 0x80 != 0 ||
            modulus.length < 128 ||
            modulus.first & 0x80 != 0) {
          _invalid();
        }
      case 'ecdsa-sha2-nistp256':
      case 'ecdsa-sha2-nistp384':
      case 'ecdsa-sha2-nistp521':
        final curve = utf8.decode(reader.string(32));
        final expected = type.substring('ecdsa-sha2-'.length);
        final length = switch (expected) {
          'nistp256' => 65,
          'nistp384' => 97,
          _ => 133,
        };
        final point = reader.string(length);
        if (curve != expected || point.length != length || point.first != 4) {
          _invalid();
        }
      default:
        return null;
    }
    reader.end();
    return _AgentKey(
      Uint8List.fromList(blob),
      type,
      comment.replaceAll(RegExp(r'[\x00-\x1f\x7f-\x9f]'), ''),
    );
  }
}

class _AgentTransaction {
  final _result = Completer<Uint8List>();
  SshAgentTransport? _socket;
  StreamSubscription<List<int>>? _subscription;
  Timer? _timer;
  bool _closed = false;
  final _header = Uint8List(4);
  int _headerLength = 0;
  Uint8List? _body;
  int _bodyLength = 0;

  Future<Uint8List> run(
    SshAgentTransportConnector connect,
    Uint8List bytes, {
    required Duration timeout,
    required bool Function() current,
  }) {
    _timer = Timer(timeout, () => _fail(SshAgentException.timeout));
    unawaited(() async {
      try {
        final socket = await connect();
        if (_closed || !current()) {
          socket.destroy();
          _fail(SshAgentException.closed);
          return;
        }
        _socket = socket;
        _subscription = socket.input.listen(
          (bytes) => _read(bytes, current),
          onError: (Object _, StackTrace __) =>
              _fail(SshAgentException.connection),
          onDone: () {
            if (!_result.isCompleted) _fail(SshAgentException.invalid);
          },
        );
        if (_closed || !current()) {
          _fail(SshAgentException.closed);
          return;
        }
        socket.add(
          (_Writer()
                ..uint32(bytes.length)
                ..bytes(bytes))
              .take(),
        );
      } on SshAgentException catch (error) {
        _fail(error.message);
      } catch (_) {
        _fail(SshAgentException.connection);
      }
    }());
    return _result.future;
  }

  void _read(List<int> chunk, bool Function() current) {
    if (_closed) return;
    if (!current()) {
      _fail(SshAgentException.closed);
      return;
    }
    var offset = 0;
    while (offset < chunk.length && _headerLength < 4) {
      _header[_headerLength++] = chunk[offset++];
    }
    if (_headerLength < 4) return;
    if (_body == null) {
      final length = ByteData.sublistView(_header).getUint32(0);
      if (length == 0 || length > SshAgentConnection.maximumFrameLength) {
        _fail(SshAgentException.invalid);
        return;
      }
      _body = Uint8List(length);
    }
    final body = _body!;
    final count = chunk.length - offset;
    if (count > body.length - _bodyLength) {
      _fail(SshAgentException.invalid);
      return;
    }
    body.setRange(_bodyLength, _bodyLength + count, chunk, offset);
    _bodyLength += count;
    if (_bodyLength == body.length) {
      _result.complete(body);
      close();
    }
  }

  void _fail(String message) {
    if (!_result.isCompleted) {
      _result.completeError(SshAgentException(message));
    }
    close();
  }

  void cancel() => _fail(SshAgentException.closed);

  void close() {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    _timer = null;
    _socket?.destroy();
    _socket = null;
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel().catchError((Object _) {}));
    }
  }
}

class _Reader {
  _Reader(this.bytes);
  final Uint8List bytes;
  int offset = 0;
  int byte() {
    if (offset >= bytes.length) _invalid();
    return bytes[offset++];
  }

  int uint32() {
    if (bytes.length - offset < 4) _invalid();
    final value = ByteData.sublistView(bytes, offset, offset + 4).getUint32(0);
    offset += 4;
    return value;
  }

  Uint8List string(int maximum) {
    final length = uint32();
    if (length > maximum || length > bytes.length - offset) _invalid();
    final value = Uint8List.sublistView(bytes, offset, offset + length);
    offset += length;
    return value;
  }

  void end() {
    if (offset != bytes.length) _invalid();
  }
}

class _Writer {
  final _bytes = BytesBuilder(copy: false);
  void byte(int value) => _bytes.addByte(value);
  void uint32(int value) {
    final data = ByteData(4)..setUint32(0, value);
    _bytes.add(data.buffer.asUint8List());
  }

  void bytes(List<int> value) => _bytes.add(value);
  void string(List<int> value) {
    uint32(value.length);
    bytes(value);
  }

  Uint8List take() => _bytes.takeBytes();
}
