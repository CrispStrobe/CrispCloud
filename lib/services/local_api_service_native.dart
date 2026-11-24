// lib/services/local_api_service_native.dart
//
// Native (dart:io) implementation of the LocalApiService HTTP layer.
// Imported only on non-web platforms via conditional import in
// local_api_service.dart.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'local_api_service.dart';

// ---------------------------------------------------------------------------
// Server handle
// ---------------------------------------------------------------------------

class _ServerHandle {
  final HttpServer server;
  final StreamSubscription<HttpRequest> subscription;

  _ServerHandle(this.server, this.subscription);
}

// ---------------------------------------------------------------------------
// Public API called by LocalApiService
// ---------------------------------------------------------------------------

/// Bind an HttpServer to localhost:[port] and register the request handler.
Future<Object> startHttpServer({
  required int port,
  required Future<ApiResponse?> Function(ApiRequest) authorizeRequest,
  required Future<ApiResponse> Function(ApiRequest) handleRequest,
  int maxBodyBytes = 100 * 1024 * 1024,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  final sub = server.listen((HttpRequest nativeRequest) async {
    await _handleNativeRequest(
      nativeRequest,
      authorizeRequest,
      handleRequest,
      maxBodyBytes,
    );
  });
  return _ServerHandle(server, sub);
}

/// Close the server and cancel the subscription.
Future<void> stopHttpServer(Object handle) async {
  if (handle is _ServerHandle) {
    await handle.subscription.cancel();
    await handle.server.close(force: true);
  }
}

// ---------------------------------------------------------------------------
// Request parsing
// ---------------------------------------------------------------------------

Future<void> _handleNativeRequest(
  HttpRequest nativeRequest,
  Future<ApiResponse?> Function(ApiRequest) authorize,
  Future<ApiResponse> Function(ApiRequest) handler,
  int maxBodyBytes,
) async {
  // Handle CORS preflight.
  if (nativeRequest.method.toUpperCase() == 'OPTIONS') {
    _writeOptionsResponse(nativeRequest.response);
    return;
  }

  final head = _parseHead(nativeRequest);
  final denied = await authorize(head);
  if (denied != null) {
    nativeRequest.response.persistentConnection = false;
    _writeResponse(nativeRequest.response, denied);
    return;
  }
  final Uint8List body;
  try {
    body = await _readBytes(nativeRequest, maxBodyBytes);
  } on _BodyLimitExceeded {
    nativeRequest.response.persistentConnection = false;
    _writeResponse(
      nativeRequest.response,
      const ApiResponse(
        statusCode: 413,
        body: {'error': 'Request body is too large'},
      ),
    );
    return;
  } on TimeoutException {
    nativeRequest.response.persistentConnection = false;
    _writeResponse(
      nativeRequest.response,
      const ApiResponse(
        statusCode: 408,
        body: {'error': 'Request body timed out'},
      ),
    );
    return;
  } on HttpException {
    return;
  }
  final apiRequest = ApiRequest(
    method: head.method,
    path: head.path,
    queryParams: head.queryParams,
    headers: head.headers,
    jsonBody: _parseJson(head.headers, body),
    rawBody: body,
  );
  _writeResponse(nativeRequest.response, await handler(apiRequest));
}

ApiRequest _parseHead(HttpRequest req) {
  final uri = req.uri;
  final path = uri.path;
  final queryParams = Map<String, String>.fromEntries(
    uri.queryParameters.entries,
  );

  // Collect headers (lower-cased).
  final headers = <String, String>{};
  req.headers.forEach((name, values) {
    if (values.isNotEmpty) headers[name.toLowerCase()] = values.first;
  });

  // Add remote address as pseudo-header for rate limiting.
  headers['x-forwarded-for'] =
      req.connectionInfo?.remoteAddress.address ?? '127.0.0.1';

  return ApiRequest(
    method: req.method,
    path: path,
    queryParams: queryParams,
    headers: headers,
    jsonBody: const {},
    rawBody: Uint8List(0),
  );
}

Map<String, dynamic> _parseJson(Map<String, String> headers, Uint8List bytes) {
  if (bytes.isNotEmpty &&
      (headers['content-type'] ?? '').contains('application/json')) {
    try {
      final decoded = json.decode(utf8.decode(bytes));
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      return {};
    }
  }
  return {};
}

class _BodyLimitExceeded implements Exception {}

Future<Uint8List> _readBytes(HttpRequest req, int limit) {
  if (req.contentLength > limit) throw _BodyLimitExceeded();
  final bytes = BytesBuilder(copy: false);
  final result = Completer<Uint8List>();
  req
      .timeout(const Duration(seconds: 30))
      .listen(
        (chunk) {
          // Keep draining after a rejected chunk. Cancelling the request stream
          // here can close the socket before the HTTP 413 reaches the client.
          if (result.isCompleted) return;
          if (chunk.length > limit - bytes.length) {
            bytes.clear();
            result.completeError(_BodyLimitExceeded());
            return;
          }
          bytes.add(chunk);
        },
        onError: (Object error, StackTrace trace) {
          if (!result.isCompleted) result.completeError(error, trace);
        },
        onDone: () {
          if (!result.isCompleted) result.complete(bytes.takeBytes());
        },
      );
  return result.future;
}

// ---------------------------------------------------------------------------
// Response writing
// ---------------------------------------------------------------------------

void _writeResponse(HttpResponse res, ApiResponse apiResponse) {
  res.statusCode = apiResponse.statusCode;
  _setCorsHeaders(res);
  res.headers.contentType = ContentType.json;
  res.write(json.encode(apiResponse.toJson()));
  res.close();
}

void _writeOptionsResponse(HttpResponse res) {
  res.statusCode = HttpStatus.noContent;
  _setCorsHeaders(res);
  res.close();
}

void _setCorsHeaders(HttpResponse res) {
  final cors = LocalApiService.corsHeaders();
  cors.forEach((key, value) => res.headers.set(key, value));
}
