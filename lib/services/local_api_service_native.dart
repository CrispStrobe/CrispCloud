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
  required Future<ApiResponse> Function(ApiRequest) handleRequest,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  final sub = server.listen((HttpRequest nativeRequest) async {
    await _handleNativeRequest(nativeRequest, handleRequest);
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
  Future<ApiResponse> Function(ApiRequest) handler,
) async {
  // Handle CORS preflight.
  if (nativeRequest.method.toUpperCase() == 'OPTIONS') {
    _writeOptionsResponse(nativeRequest.response);
    return;
  }

  final apiRequest = await _parseRequest(nativeRequest);
  final apiResponse = await handler(apiRequest);
  _writeResponse(nativeRequest.response, apiResponse);
}

Future<ApiRequest> _parseRequest(HttpRequest req) async {
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
  headers['x-forwarded-for'] = req.connectionInfo?.remoteAddress.address ?? '127.0.0.1';

  // Read body bytes.
  Uint8List rawBody = Uint8List(0);
  Map<String, dynamic> jsonBody = {};

  try {
    final bodyBytes = await _readBytes(req);
    rawBody = Uint8List.fromList(bodyBytes);

    final ct = headers['content-type'] ?? '';
    if (ct.contains('application/json') && rawBody.isNotEmpty) {
      final decoded = json.decode(utf8.decode(rawBody));
      if (decoded is Map<String, dynamic>) {
        jsonBody = decoded;
      }
    }
  } catch (_) {
    // Body parsing failure — continue with empty body.
  }

  return ApiRequest(
    method: req.method,
    path: path,
    queryParams: queryParams,
    headers: headers,
    jsonBody: jsonBody,
    rawBody: rawBody,
  );
}

Future<List<int>> _readBytes(HttpRequest req) async {
  final bytes = <int>[];
  await for (final chunk in req) {
    bytes.addAll(chunk);
    // Guard against huge uploads exhausting memory (~100 MB limit).
    if (bytes.length > 100 * 1024 * 1024) break;
  }
  return bytes;
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
