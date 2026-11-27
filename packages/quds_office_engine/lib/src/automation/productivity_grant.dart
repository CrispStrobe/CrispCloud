import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'productivity_snapshot.dart';

const _grantPath = '/productivity-grant';
const _maxRequestBytes = 32 * 1024;
const _maxResponseBytes = 2 * 1024 * 1024;
const _wireTimeout = Duration(seconds: 3);
const _operationTimeout = Duration(seconds: 20);

/// One ephemeral credential for the local relay. The ticket never contains a
/// provider credential. Keep it out of arguments, logs, and tool results.
final class ProductivityGrantTicket {
  const ProductivityGrantTicket._(this._port, this._secret);

  static const environmentKey = 'CRISPOFFICE_MCP_GRANT';
  final int _port;
  final String _secret;

  factory ProductivityGrantTicket.parse(String value) {
    final match = RegExp(
      r'^([1-9][0-9]{0,4})\.([A-Za-z0-9_-]{43})$',
    ).firstMatch(value);
    if (match == null || match.end != value.length) {
      throw const FormatException('Invalid grant');
    }
    final port = int.parse(match[1]!);
    if (port > 65535) throw const FormatException('Invalid grant');
    return ProductivityGrantTicket._(port, match[2]!);
  }

  String get relayCredential => '$_port.$_secret';

  @override
  String toString() => 'ProductivityGrantTicket(redacted)';
}

/// The host alone selects the callback and the scope. One ticket authorizes
/// one short-lived MCP session. This endpoint is a private stdio relay protocol.
final class ProductivityGrant {
  ProductivityGrant._(this._server, this._session, this._isCurrent, this._ttl)
    : ticket = ProductivityGrantTicket._(_server.port, _secret()) {
    _expiry = Timer(_ttl, () => unawaited(revoke()));
    _server.idleTimeout = _wireTimeout;
    _server.listen(
      (request) => unawaited(_serve(request)),
      onError: (Object _) => unawaited(revoke()),
    );
  }

  static Future<ProductivityGrant> open({
    required ProductivityMcp session,
    required bool Function() isCurrent,
    Duration lifetime = const Duration(minutes: 10),
  }) async {
    if (lifetime <= Duration.zero || lifetime > const Duration(minutes: 30)) {
      throw ArgumentError.value(lifetime, 'lifetime');
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return ProductivityGrant._(server, session, isCurrent, lifetime);
  }

  final ProductivityGrantTicket ticket;
  final HttpServer _server;
  final ProductivityMcp _session;
  final bool Function() _isCurrent;
  final Duration _ttl;
  final _age = Stopwatch()..start();
  late final Timer _expiry;
  bool _closed = false;
  bool _busy = false;
  int _window = -1;
  int _requests = 0;
  int _successfulReads = 0;

  int get successfulReads => _successfulReads;

  bool get isActive {
    if (_closed) return false;
    if (_age.elapsed >= _ttl || !_isCurrent()) {
      unawaited(revoke());
      return false;
    }
    return true;
  }

  Future<void> revoke() async {
    if (_closed) return;
    _closed = true;
    _expiry.cancel();
    await _server.close(force: true);
  }

  static String _secret() {
    final random = Random.secure();
    return base64Url
        .encode(List.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
  }

  bool _authorized(HttpRequest request) {
    if (request.method != 'POST' ||
        request.uri.toString() != _grantPath ||
        request.connectionInfo?.remoteAddress.isLoopback != true ||
        request.headers.value(HttpHeaders.hostHeader) !=
            '127.0.0.1:${_server.port}' ||
        request.headers['origin'] != null ||
        request.headers.contentType?.mimeType != 'application/json') {
      return false;
    }
    final match = request.headers[HttpHeaders.authorizationHeader];
    return match?.length == 1 &&
        _equal(match!.single, 'Bearer ${ticket._secret}');
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    response.persistentConnection = false;
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    var ownsSlot = false;
    try {
      if (!_authorized(request) || !isActive) {
        response.statusCode = HttpStatus.forbidden;
        return;
      }
      if (_busy) {
        response.statusCode = HttpStatus.tooManyRequests;
        return;
      }
      final window = _age.elapsed.inMinutes;
      if (window != _window) {
        _window = window;
        _requests = 0;
      }
      if (++_requests > 60) {
        response.statusCode = HttpStatus.tooManyRequests;
        return;
      }
      if (request.contentLength > _maxRequestBytes) {
        response.statusCode = HttpStatus.requestEntityTooLarge;
        return;
      }
      ownsSlot = _busy = true;
      final input = await _readBytes(request, _maxRequestBytes);
      if (!isActive) {
        response.statusCode = HttpStatus.forbidden;
        return;
      }
      final requestData = jsonDecode(utf8.decode(input));
      final reply = await _session
          .handleMessage(requestData)
          .timeout(_operationTimeout);
      if (!isActive) {
        response.statusCode = HttpStatus.forbidden;
        return;
      }
      if (reply == null) {
        response.statusCode = HttpStatus.noContent;
        return;
      }
      final output = utf8.encode(jsonEncode(reply));
      if (output.length > _maxResponseBytes) {
        response.statusCode = HttpStatus.internalServerError;
        return;
      }
      response.headers.contentType = ContentType.json;
      response.add(output);
      final result = reply['result'];
      final params = requestData is Map<String, Object?>
          ? requestData['params']
          : null;
      if (requestData is Map<String, Object?> &&
          requestData['method'] == 'tools/call' &&
          params is Map<String, Object?> &&
          _session.isReadTool(params['name']) &&
          result is Map<String, Object?> &&
          result['isError'] == false) {
        _successfulReads++;
      }
    } on Object {
      if (isActive) response.statusCode = HttpStatus.badRequest;
    } finally {
      if (ownsSlot) _busy = false;
      try {
        await response.close();
      } on Object {
        // The relay or revoked grant already closed the socket.
      }
    }
  }
}

bool _equal(String supplied, String expected) {
  if (supplied.length != expected.length) return false;
  var difference = 0;
  for (var i = 0; i < expected.length; i++) {
    difference |= supplied.codeUnitAt(i) ^ expected.codeUnitAt(i);
  }
  return difference == 0;
}

Future<List<int>> _readBytes(Stream<List<int>> stream, int limit) async {
  final bytes = <int>[];
  final input = StreamIterator(stream);
  final watch = Stopwatch()..start();
  try {
    while (await input.moveNext().timeout(_wireTimeout - watch.elapsed)) {
      final chunk = input.current;
      if (chunk.length > limit - bytes.length) {
        throw const FormatException('Message exceeds transport limit');
      }
      bytes.addAll(chunk);
    }
    return bytes;
  } finally {
    await input.cancel();
  }
}

/// Passes JSON-RPC frames to the loopback grant using native Dart.
final class ProductivityGrantRelay {
  ProductivityGrantRelay(this._ticket)
    : _client = (HttpClient()
        ..connectionTimeout = _wireTimeout
        ..findProxy = ((_) => 'DIRECT'));

  final ProductivityGrantTicket _ticket;
  final HttpClient _client;

  void close() => _client.close(force: true);

  Future<Map<String, Object?>?> forward(Object? request) async {
    final body = utf8.encode(jsonEncode(request));
    if (body.length > _maxRequestBytes) {
      return _error(request, -32600, 'Request is too large');
    }
    final path = Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: _ticket._port,
      path: _grantPath,
    );
    try {
      final connection = await _client.postUrl(path).timeout(_wireTimeout);
      connection.followRedirects = false;
      connection.persistentConnection = false;
      connection.headers.contentType = ContentType.json;
      connection.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${_ticket._secret}',
      );
      connection.contentLength = body.length;
      connection.add(body);
      final response = await connection.close().timeout(
        _operationTimeout + _wireTimeout,
      );
      final output = await _readBytes(response, _maxResponseBytes);
      return switch (response.statusCode) {
        HttpStatus.noContent => null,
        HttpStatus.ok =>
          jsonDecode(utf8.decode(output)) as Map<String, Object?>,
        HttpStatus.tooManyRequests => _error(
          request,
          -32003,
          'Live grant is busy or rate limited',
        ),
        _ => _error(request, -32003, 'Live grant is unavailable'),
      };
    } on Object {
      return _error(request, -32003, 'Live grant is unavailable');
    }
  }

  Map<String, Object?>? _error(Object? request, int code, String message) {
    if (request is Map<String, Object?> && !request.containsKey('id')) {
      return null;
    }
    final id = request is Map<String, Object?> ? request['id'] : null;
    return {
      'jsonrpc': '2.0',
      'id': id is num || (id is String && id.length <= 256) ? id : null,
      'error': {'code': code, 'message': message},
    };
  }
}
