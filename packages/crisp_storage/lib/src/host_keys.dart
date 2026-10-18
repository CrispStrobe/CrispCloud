import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import 'remote_client.dart';

typedef HostKeyPrompt = Future<bool> Function(
    String endpoint, String fingerprint);

class SftpHostKeyException extends RemoteException {
  final String fingerprint;
  final String? expected, endpoint;
  SftpHostKeyException(this.fingerprint, {this.expected, this.endpoint})
      : super(expected == null
            ? 'Verify this server’s SSH host key before connecting: $fingerprint'
            : 'SSH host key changed for ${endpoint ?? "this server"}. Expected $expected; received $fingerprint.');
}

/// Endpoint-scoped SSH trust, independent of account passwords and Flutter.
class SshKnownHosts {
  final Future<String?> Function() read;
  final Future<void> Function(String) write;
  static Future<void> _writes = Future.value();
  SshKnownHosts({required this.read, required this.write});
  static String endpoint(String host, int port) =>
      '${host.toLowerCase()}:$port';
  Future<Map<String, String>> _load() async {
    final raw = await read();
    if (raw == null) return {};
    return Map<String, String>.from(jsonDecode(raw) as Map);
  }

  Future<bool> verify(String endpoint, String fingerprint,
      {HostKeyPrompt? prompt}) async {
    if (!RegExp(r'^SHA256:[A-Za-z0-9+/]{43}$').hasMatch(fingerprint)) {
      throw const FormatException('Invalid SSH SHA256 fingerprint');
    }
    final known = (await _load())[endpoint];
    if (known == fingerprint) return true;
    if (known != null) {
      throw SftpHostKeyException(fingerprint,
          expected: known, endpoint: endpoint);
    }
    if (prompt == null || !await prompt(endpoint, fingerprint)) {
      throw SftpHostKeyException(fingerprint, endpoint: endpoint);
    }
    final result = _writes.then((_) async {
      final latest = await _load();
      final old = latest[endpoint];
      if (old != null && old != fingerprint) {
        throw SftpHostKeyException(fingerprint,
            expected: old, endpoint: endpoint);
      }
      latest[endpoint] = fingerprint;
      await write(jsonEncode(latest));
    });
    _writes = result.catchError((Object _) {});
    await result;
    return true;
  }
}

/// Authentication starts only after the caller has accepted the server key.
Future<SSHClient> openVerifiedSsh(
  SSHSocket socket, {
  required String username,
  String? password,
  List<SSHIdentity>? identities,
  required FutureOr<bool> Function(String, Uint8List) verify,
  void Function(SSHClient)? onCreated,
}) async {
  Object? verificationError;
  final client = SSHClient(socket,
      username: username,
      identities: identities,
      handshakeTimeout: const Duration(seconds: 15),
      authTimeout: const Duration(seconds: 15),
      onPasswordRequest: password == null ? null : () => password,
      onVerifyHostKey: (type, key) async {
    try {
      return await verify(type, key);
    } catch (error) {
      verificationError = error;
      return false;
    }
  });
  unawaited(client.done.catchError((Object _) {}));
  onCreated?.call(client);
  try {
    await client.authenticated;
    return client;
  } catch (error, stack) {
    try {
      await client.close();
    } catch (_) {}
    Error.throwWithStackTrace(verificationError ?? error, stack);
  }
}
