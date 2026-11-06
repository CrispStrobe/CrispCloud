import 'dart:async';

import 'package:dartssh2/dartssh2.dart' show SSHSocket;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'web_ssh_socket.dart';

/// Returns a localizable validation message, or null when the URL is usable.
///
/// The SSH host and port are deliberately separate from this URL: they identify
/// the server whose SSH key is verified. No gateway is discovered or supplied
/// by CrispCloud. The chosen gateway must already route to that SSH endpoint.
/// [rawUrl] lets forms reject an explicit `:0`, which Dart otherwise removes
/// while parsing a wss URI because that scheme has no registered default port.
String? sshGatewayValidationMessage(
  Uri? gateway, {
  bool required = false,
  String? rawUrl,
}) {
  const invalid = 'Use a complete wss:// URL with a valid host and port.';
  if (gateway == null) {
    if (rawUrl?.trim().isNotEmpty == true) return invalid;
    return required
        ? 'A secure WebSocket gateway is required in the browser.'
        : null;
  }
  if (gateway.scheme != 'wss' ||
      gateway.host.isEmpty ||
      (gateway.hasPort && (gateway.port < 1 || gateway.port > 65535))) {
    return invalid;
  }
  if (rawUrl != null) {
    // https has a registered default of 443, so this parsing-only substitution
    // retains explicit port zero for validation. It never opens a connection.
    final portUri = Uri.tryParse(
      rawUrl.trim().replaceFirst(
        RegExp(r'^wss:', caseSensitive: false),
        'https:',
      ),
    );
    if (portUri == null ||
        portUri.scheme != 'https' ||
        (portUri.hasPort && (portUri.port < 1 || portUri.port > 65535))) {
      return invalid;
    }
  }
  if (gateway.userInfo.isNotEmpty || gateway.hasQuery || gateway.hasFragment) {
    return 'The gateway URL must not contain credentials, query parameters, or a fragment.';
  }
  return null;
}

/// Contains no URL or underlying platform error, which could disclose gateway
/// access details. SSH authentication/host-key errors remain unchanged.
class SshGatewayException implements Exception {
  const SshGatewayException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Opens an explicitly selected secure WebSocket gateway before starting SSH.
///
/// [connectChannel] is the I/O boundary for deterministic, browser-compatible
/// tests. Normal application calls use the existing web_socket_channel library.
Future<SSHSocket> openSshGateway(
  Uri gateway, {
  Duration timeout = const Duration(seconds: 15),
  WebSocketChannel Function(Uri)? connectChannel,
}) async {
  final validation = sshGatewayValidationMessage(gateway);
  if (validation != null) throw ArgumentError(validation);

  WebSocketChannel? channel;
  try {
    channel = (connectChannel ?? WebSocketChannel.connect)(gateway);
    // Observe early sink failures before the SSH client has attached. The SSH
    // socket still exposes its original done future after a successful open.
    unawaited(
      channel.sink.done.then<void>(
        (_) {},
        onError: (Object _, StackTrace __) {},
      ),
    );
    await channel.ready.timeout(timeout);
    return WebSSHSocket(channel);
  } catch (error) {
    if (channel != null) {
      // A failed handshake can leave an error buffered on the receive stream.
      // Consume it and request closure without waiting on another handshake.
      // If the underlying connect finishes late, the queued sink close also
      // closes that socket instead of leaving a detached connection alive.
      try {
        unawaited(channel.stream.drain<void>().catchError((Object _) {}));
      } catch (_) {}
      try {
        unawaited(
          channel.sink.close().then<void>(
            (_) {},
            onError: (Object _, StackTrace __) {},
          ),
        );
      } catch (_) {}
    }
    if (error is TimeoutException) {
      throw const SshGatewayException(
        'The WebSocket gateway connection timed out.',
      );
    }
    throw const SshGatewayException(
      'The WebSocket gateway connection failed. Check the gateway URL and access.',
    );
  }
}
