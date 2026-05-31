// lib/services/local_api_service_stub.dart
//
// Web/unsupported-platform stub for the LocalApiService native layer.
// All functions are no-ops — the HTTP server cannot run on web.

import 'local_api_service.dart';

/// Start an HTTP server. On web this always throws [UnsupportedError].
Future<Object> startHttpServer({
  required int port,
  required Future<ApiResponse> Function(ApiRequest) handleRequest,
}) {
  throw UnsupportedError('HTTP server is not supported on this platform');
}

/// Stop an HTTP server. On web this is a no-op.
Future<void> stopHttpServer(Object handle) async {}
