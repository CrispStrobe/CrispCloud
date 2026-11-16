import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/src/hostkey/hostkey_rsa.dart';
import 'package:dartssh2/src/ssh_channel.dart';
import 'package:dartssh2/src/ssh_hostkey.dart';
import 'package:dartssh2/src/ssh_key_pair.dart';
import 'package:dartssh2/src/ssh_message.dart';
import 'package:dartssh2/src/ssh_transport.dart';
import 'package:pointycastle/api.dart' hide Signature;
import 'package:pointycastle/asymmetric/api.dart' as asymmetric;
import 'package:pointycastle/digests/sha1.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/digests/sha512.dart';
import 'package:pointycastle/signers/rsa_signer.dart';

abstract class SSHAgentHandler {
  Future<Uint8List> handleRequest(Uint8List request);
}

class SSHKeyPairAgent implements SSHAgentHandler {
  SSHKeyPairAgent(this._identities, {this.comment});

  final List<SSHKeyPair> _identities;
  final String? comment;

  @override
  Future<Uint8List> handleRequest(Uint8List request) async {
    if (request.isEmpty) {
      return _failure();
    }
    final reader = SSHMessageReader(request);
    final messageType = reader.readUint8();
    switch (messageType) {
      case SSHAgentProtocol.requestIdentities:
        return _handleRequestIdentities();
      case SSHAgentProtocol.signRequest:
        return _handleSignRequest(reader);
      default:
        return _failure();
    }
  }

  Uint8List _handleRequestIdentities() {
    final writer = SSHMessageWriter();
    writer.writeUint8(SSHAgentProtocol.identitiesAnswer);
    writer.writeUint32(_identities.length);
    for (final identity in _identities) {
      final publicKey = identity.toPublicKey().encode();
      writer.writeString(publicKey);
      writer.writeUtf8(comment ?? '');
    }
    return writer.takeBytes();
  }

  Uint8List _handleSignRequest(SSHMessageReader reader) {
    final keyBlob = reader.readString();
    final data = reader.readString();
    final flags = reader.readUint32();

    final identity = _findIdentity(keyBlob);
    if (identity == null) {
      return _failure();
    }

    final signature = _sign(identity, data, flags);
    final writer = SSHMessageWriter();
    writer.writeUint8(SSHAgentProtocol.signResponse);
    writer.writeString(signature.encode());
    return writer.takeBytes();
  }

  SSHSignature _sign(SSHKeyPair identity, Uint8List data, int flags) {
    if (identity is OpenSSHRsaKeyPair || identity is RsaPrivateKey) {
      final signatureType = _rsaSignatureTypeForFlags(flags);
      return _signRsa(identity, data, signatureType);
    }
    return identity.sign(data);
  }

  String _rsaSignatureTypeForFlags(int flags) {
    if (flags & SSHAgentProtocol.rsaSha2_512 != 0) {
      return SSHRsaSignatureType.sha512;
    }
    if (flags & SSHAgentProtocol.rsaSha2_256 != 0) {
      return SSHRsaSignatureType.sha256;
    }
    return SSHRsaSignatureType.sha1;
  }

  SSHRsaSignature _signRsa(
    SSHKeyPair identity,
    Uint8List data,
    String signatureType,
  ) {
    final key = _rsaKeyFrom(identity);
    if (key == null) {
      final signature = identity.sign(data);
      if (signature is SSHRsaSignature) {
        if (signature.type != signatureType) {
          throw StateError(
            'RSA signature type mismatch: requested $signatureType but identity produced ${signature.type}',
          );
        }
        return signature;
      }
      throw StateError(
        'RSA signing requested but identity produced non-RSA signature: ${signature.runtimeType}',
      );
    }

    final signer = _rsaSignerFor(signatureType);
    signer.init(true, PrivateKeyParameter<asymmetric.RSAPrivateKey>(key));
    return SSHRsaSignature(signatureType, signer.generateSignature(data).bytes);
  }

  asymmetric.RSAPrivateKey? _rsaKeyFrom(SSHKeyPair identity) {
    if (identity is OpenSSHRsaKeyPair) {
      return asymmetric.RSAPrivateKey(
        identity.n,
        identity.d,
        identity.p,
        identity.q,
      );
    }
    if (identity is RsaPrivateKey) {
      return asymmetric.RSAPrivateKey(
        identity.n,
        identity.d,
        identity.p,
        identity.q,
      );
    }
    return null;
  }

  RSASigner _rsaSignerFor(String signatureType) {
    switch (signatureType) {
      case SSHRsaSignatureType.sha1:
        return RSASigner(SHA1Digest(), '06052b0e03021a');
      case SSHRsaSignatureType.sha256:
        return RSASigner(SHA256Digest(), '0609608648016503040201');
      case SSHRsaSignatureType.sha512:
        return RSASigner(SHA512Digest(), '0609608648016503040203');
      default:
        return RSASigner(SHA256Digest(), '0609608648016503040201');
    }
  }

  SSHKeyPair? _findIdentity(Uint8List keyBlob) {
    for (final identity in _identities) {
      final publicKey = identity.toPublicKey().encode();
      if (_bytesEqual(publicKey, keyBlob)) {
        return identity;
      }
    }
    return null;
  }

  Uint8List _failure() {
    final writer = SSHMessageWriter();
    writer.writeUint8(SSHAgentProtocol.failure);
    return writer.takeBytes();
  }

  bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class SSHAgentChannel {
  static const maxFrameSize = 256 * 1024;
  static const maxBufferedBytes = maxFrameSize * 2 + 8;

  SSHAgentChannel(
    this._channel,
    this._handler, {
    this.printDebug,
    this.requestTimeout = const Duration(seconds: 30),
    this.idleTimeout = const Duration(seconds: 30),
  }) {
    if (requestTimeout <= Duration.zero || idleTimeout <= Duration.zero) {
      throw ArgumentError('SSH agent timeouts must be positive');
    }
    _subscription = _channel.stream.listen(
      _handleData,
      onDone: _handleDone,
      onError: (_, __) => _close(),
    );
    // CHANNEL_CLOSE and transport shutdown must revoke a pending handler even
    // while the receive subscription is paused for signing or output pressure.
    _channel.done.then((_) => _finish(), onError: (_, __) => _finish());
    _armIdleDeadline();
  }

  final SSHChannel _channel;
  final SSHAgentHandler _handler;
  final SSHPrintHandler? printDebug;
  final Duration requestTimeout;
  final Duration idleTimeout;

  StreamSubscription<SSHChannelData>? _subscription;
  Uint8List _buffer = Uint8List(0);
  bool _processing = false;
  bool _inputEnded = false;
  bool _closed = false;
  Timer? _idleTimer;
  void Function()? _cancelPending;

  void _handleDone() {
    _inputEnded = true;
    _drainRequests();
  }

  void _handleData(SSHChannelData data) {
    if (_closed) return;
    if (data.type != null ||
        data.bytes.length > maxBufferedBytes - _buffer.length) {
      _close();
      return;
    }
    _buffer = _appendBytes(_buffer, data.bytes);
    _drainRequests();
  }

  void _drainRequests() {
    if (_processing || _closed) return;
    _processing = true;
    // Pausing also stops the channel's receive-window replenishment. Already
    // admitted stream events are bounded by the advertised SSH receive window.
    // Keep input paused through the response flush, so a peer with no output
    // window cannot build an unbounded queue of replies.
    _subscription?.pause();
    _processQueue().catchError((Object _) => _close()).whenComplete(() {
      _processing = false;
      if (_closed) return;
      if (_inputEnded) {
        // Complete requests have drained; a remaining partial frame is invalid.
        _close();
      } else {
        _subscription?.resume();
      }
    });
  }

  Future<void> _processQueue() async {
    while (!_closed && _buffer.length >= 4) {
      final length = ByteData.sublistView(_buffer, 0, 4).getUint32(0);
      if (length == 0 || length > maxFrameSize) {
        printDebug?.call(
          'SSH agent: invalid frame length $length, closing channel',
        );
        _close();
        return;
      }
      if (_buffer.length < 4 + length) return;
      final payload = _buffer.sublist(4, 4 + length);
      _buffer = _buffer.sublist(4 + length);
      _idleTimer?.cancel();
      Uint8List response;
      try {
        response = await _untilClosed(
          Future<Uint8List>.sync(() => _handler.handleRequest(payload)),
        ).timeout(requestTimeout);
      } on TimeoutException {
        _close();
        return;
      } catch (_) {
        if (_closed) return;
        // Handler exceptions can contain local socket paths or key comments.
        printDebug?.call('SSH agent handler failed');
        response = _failureResponse();
      }
      if (_closed) return;
      if (response.isEmpty || response.length > maxFrameSize) {
        _close();
        return;
      }
      await _untilClosed(_sendResponse(response)).timeout(requestTimeout);
      if (!_closed) _armIdleDeadline();
    }
  }

  Future<T> _untilClosed<T>(Future<T> operation) {
    final result = Completer<T>();
    void cancel() {
      if (!result.isCompleted) {
        result.completeError(StateError('SSH agent closed'));
      }
    }

    _cancelPending = cancel;
    operation.then(
      (value) {
        if (!result.isCompleted) result.complete(value);
      },
      onError: (Object error, StackTrace stack) {
        if (!result.isCompleted) result.completeError(error, stack);
      },
    );
    if (_closed) cancel();
    return result.future.whenComplete(() {
      if (identical(_cancelPending, cancel)) _cancelPending = null;
    });
  }

  void _armIdleDeadline() {
    _idleTimer?.cancel();
    if (!_closed) _idleTimer = Timer(idleTimeout, _close);
  }

  void _finish() {
    if (_closed) return;
    _closed = true;
    _idleTimer?.cancel();
    _buffer = Uint8List(0);
    _subscription?.cancel();
    _cancelPending?.call();
    _cancelPending = null;
  }

  void _close() {
    if (_closed) return;
    _finish();
    _channel.destroy();
  }

  Uint8List _failureResponse() {
    final writer = SSHMessageWriter();
    writer.writeUint8(SSHAgentProtocol.failure);
    return writer.takeBytes();
  }

  Future<void> _sendResponse(Uint8List payload) async {
    final writer = SSHMessageWriter();
    writer.writeUint32(payload.length);
    writer.writeBytes(payload);
    await _channel.sendDataAndWait(writer.takeBytes());
  }

  Uint8List _appendBytes(Uint8List a, Uint8List b) {
    if (a.isEmpty) return b;
    if (b.isEmpty) return a;
    final combined = Uint8List(a.length + b.length);
    combined.setAll(0, a);
    combined.setAll(a.length, b);
    return combined;
  }
}

abstract class SSHAgentProtocol {
  static const int failure = 5;
  static const int requestIdentities = 11;
  static const int identitiesAnswer = 12;
  static const int signRequest = 13;
  static const int signResponse = 14;
  static const int rsaSha2_256 = 2;
  static const int rsaSha2_512 = 4;
}
