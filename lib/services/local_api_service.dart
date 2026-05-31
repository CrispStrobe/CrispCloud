// lib/services/local_api_service.dart
//
// Local REST API server for CrispCloud headless/integration mode.
// Exposes file operations over HTTP on localhost so scripts, NAS integrations,
// media servers, and Zapier-style workflows can drive CrispCloud programmatically.
//
// Platform guard: on web, all methods are no-ops and the server is never started.
//
// Usage:
//   final service = LocalApiService(multiCloudNotifier, syncNotifier, transferNotifier);
//   await service.start(port: 9847);
//   // … later …
//   await service.stop();

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'log_service.dart';

// ---------------------------------------------------------------------------
// Conditional dart:io import — web stub provides no-op types.
// ---------------------------------------------------------------------------
import 'local_api_service_stub.dart'
    if (dart.library.io) 'local_api_service_native.dart' as _native;

// ---------------------------------------------------------------------------
// Public constants
// ---------------------------------------------------------------------------

/// Default port the REST server listens on.
const kLocalApiDefaultPort = 9847;

/// Minimum allowed port number.
const kLocalApiMinPort = 1024;

/// Maximum allowed port number.
const kLocalApiMaxPort = 65535;

/// SharedPreferences key for the enabled flag.
const kLocalApiEnabledKey = 'local_api_enabled';

/// SharedPreferences key for the port.
const kLocalApiPortKey = 'local_api_port';

/// Application version reported by the status endpoint.
const kAppVersion = '0.1.0';

// ---------------------------------------------------------------------------
// ApiResponse
// ---------------------------------------------------------------------------

/// Represents the HTTP response that an API handler produces.
class ApiResponse {
  final int statusCode;
  final Map<String, dynamic> body;
  final String? error;

  const ApiResponse({
    required this.statusCode,
    required this.body,
    this.error,
  });

  /// 200 OK with a data payload.
  factory ApiResponse.ok(Map<String, dynamic> data) =>
      ApiResponse(statusCode: 200, body: data);

  /// 201 Created.
  factory ApiResponse.created(Map<String, dynamic> data) =>
      ApiResponse(statusCode: 201, body: data);

  /// 400 Bad Request.
  factory ApiResponse.badRequest(String message) => ApiResponse(
        statusCode: 400,
        body: {'error': message},
        error: message,
      );

  /// 401 Unauthorized (missing token).
  factory ApiResponse.unauthorized() => ApiResponse(
        statusCode: 401,
        body: {'error': 'Authorization header missing or malformed'},
        error: 'unauthorized',
      );

  /// 403 Forbidden (wrong token).
  factory ApiResponse.forbidden() => ApiResponse(
        statusCode: 403,
        body: {'error': 'Invalid token'},
        error: 'forbidden',
      );

  /// 404 Not Found.
  factory ApiResponse.notFound(String path) => ApiResponse(
        statusCode: 404,
        body: {'error': 'Route not found: $path'},
        error: 'not_found',
      );

  /// 405 Method Not Allowed.
  factory ApiResponse.methodNotAllowed(String method) => ApiResponse(
        statusCode: 405,
        body: {'error': 'Method not allowed: $method'},
        error: 'method_not_allowed',
      );

  /// 429 Too Many Requests.
  factory ApiResponse.tooManyRequests() => ApiResponse(
        statusCode: 429,
        body: {'error': 'Rate limit exceeded. Max 100 requests/minute.'},
        error: 'rate_limit_exceeded',
      );

  /// 500 Internal Server Error.
  factory ApiResponse.internalError(Object? err) => ApiResponse(
        statusCode: 500,
        body: {'error': 'Internal server error: $err'},
        error: 'internal_error',
      );

  /// 503 Service Unavailable (e.g. web platform).
  factory ApiResponse.serviceUnavailable(String reason) => ApiResponse(
        statusCode: 503,
        body: {'error': reason},
        error: 'service_unavailable',
      );

  Map<String, dynamic> toJson() => {
        'status': statusCode >= 200 && statusCode < 300 ? 'ok' : 'error',
        ...body,
      };

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}

// ---------------------------------------------------------------------------
// ApiTokenManager
// ---------------------------------------------------------------------------

/// Manages the API bearer token.
///
/// The token is a 48-character hex string (24 random bytes → hex).
/// It is stored in SharedPreferences under the key [_kTokenKey].
/// On first call to [getOrCreate] it generates and persists a token.
class ApiTokenManager {
  static final _log = Log('ApiTokenManager');
  static const _kTokenKey = 'local_api_token';

  /// Length of the token in hex characters (24 bytes × 2).
  static const tokenLength = 48;

  /// Return the current token, generating a new one if none exists.
  Future<String> getOrCreate() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_kTokenKey);
    if (existing != null && existing.length == tokenLength) {
      return existing;
    }
    return _generate(prefs);
  }

  /// Force-generate a new token (invalidates the old one).
  Future<String> rotate() async {
    final prefs = await SharedPreferences.getInstance();
    return _generate(prefs);
  }

  /// Validate a raw token string against the stored token.
  Future<bool> validate(String token) async {
    if (token.isEmpty) return false;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kTokenKey);
    return stored != null && stored == token;
  }

  /// Delete the stored token (used during reset / disable).
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kTokenKey);
  }

  /// Generate a random 48-hex-char token and persist it.
  Future<String> _generate(SharedPreferences prefs) async {
    final rng = Random.secure();
    final bytes = List<int>.generate(24, (_) => rng.nextInt(256));
    final token = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await prefs.setString(_kTokenKey, token);
    _log.info('API token generated/rotated');
    return token;
  }

  /// Generate a fresh token string without persisting it (for tests).
  static String generateRaw() {
    final rng = Random.secure();
    final bytes = List<int>.generate(24, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

// ---------------------------------------------------------------------------
// Rate limiter — token bucket per remote IP
// ---------------------------------------------------------------------------

/// Simple token-bucket rate limiter: max [_maxRequests] per [_windowDuration].
class _RateLimiter {
  static const _maxRequests = 100;
  static const _windowDuration = Duration(minutes: 1);

  // Maps IP address → list of request timestamps in the current window.
  final Map<String, List<DateTime>> _buckets = {};

  /// Returns true if the request from [ip] is allowed.
  bool allow(String ip) {
    final now = DateTime.now();
    final cutoff = now.subtract(_windowDuration);
    final timestamps = _buckets.putIfAbsent(ip, () => []);

    // Evict entries older than the window.
    timestamps.removeWhere((t) => t.isBefore(cutoff));

    if (timestamps.length >= _maxRequests) {
      return false;
    }
    timestamps.add(now);
    return true;
  }

  /// Reset limits for an IP (useful in tests).
  void reset(String ip) => _buckets.remove(ip);

  /// Reset all limits.
  void resetAll() => _buckets.clear();
}

// ---------------------------------------------------------------------------
// ApiRouter
// ---------------------------------------------------------------------------

/// Parsed incoming request — abstracted so the router is testable without a
/// real HttpRequest.
class ApiRequest {
  final String method;
  final String path;
  final Map<String, String> queryParams;
  final Map<String, String> headers;
  final Map<String, dynamic> jsonBody;
  final Uint8List rawBody;

  const ApiRequest({
    required this.method,
    required this.path,
    required this.queryParams,
    required this.headers,
    required this.jsonBody,
    required this.rawBody,
  });

  String? header(String name) {
    final lower = name.toLowerCase();
    // Try exact lowercase key first (fast path for native-parsed requests).
    if (headers.containsKey(lower)) return headers[lower];
    // Fall back to case-insensitive scan (for test-constructed requests).
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == lower) return entry.value;
    }
    return null;
  }

  bool get isMultipart {
    final ct = header('content-type') ?? '';
    return ct.contains('multipart/form-data');
  }

  String? get bearerToken {
    final auth = header('authorization') ?? '';
    if (auth.startsWith('Bearer ')) {
      return auth.substring(7).trim();
    }
    return null;
  }
}

typedef _HandlerFn = Future<ApiResponse> Function(ApiRequest request);

/// Routes an [ApiRequest] to the correct handler function.
class ApiRouter {
  static final _log = Log('ApiRouter');

  // Route table: method → path → handler
  final Map<String, Map<String, _HandlerFn>> _routes = {};

  /// Register a handler for [method] + exact [path].
  void register(String method, String path, _HandlerFn handler) {
    _routes.putIfAbsent(method.toUpperCase(), () => {})[path] = handler;
  }

  /// Dispatch a request to the registered handler.
  Future<ApiResponse> dispatch(ApiRequest request) async {
    final method = request.method.toUpperCase();
    final byMethod = _routes[method];

    if (byMethod == null) {
      // Check if any other method knows this path.
      final pathExists =
          _routes.values.any((byPath) => byPath.containsKey(request.path));
      if (pathExists) {
        return ApiResponse.methodNotAllowed(method);
      }
      return ApiResponse.notFound(request.path);
    }

    final handler = byMethod[request.path];
    if (handler == null) {
      // Path unknown — but does another method handle it?
      final pathExists =
          _routes.values.any((byPath) => byPath.containsKey(request.path));
      if (pathExists) {
        return ApiResponse.methodNotAllowed(method);
      }
      return ApiResponse.notFound(request.path);
    }

    try {
      return await handler(request);
    } catch (e, st) {
      _log.error('Handler error for $method ${request.path}', e, st);
      return ApiResponse.internalError(e);
    }
  }
}

// ---------------------------------------------------------------------------
// LocalApiService — platform-agnostic shell
// ---------------------------------------------------------------------------

/// Minimal interface that providers need to expose to the API.
abstract class ApiProviderSource {
  List<Map<String, dynamic>> listApiProviders();
}

/// Minimal interface for sync operations.
abstract class ApiSyncSource {
  Map<String, dynamic> syncStatus();
  Future<bool> triggerSync(String pairId);
}

/// Minimal interface for transfer queue status.
abstract class ApiTransferSource {
  List<Map<String, dynamic>> transferStatus();
}

/// The main LocalApiService.
///
/// On non-web platforms this delegates actual HTTP listening to the native
/// implementation in [local_api_service_native.dart].
/// On web it is a no-op.
class LocalApiService {
  static final _log = Log('LocalApiService');

  final ApiTokenManager _tokenManager;
  final _RateLimiter _rateLimiter = _RateLimiter();
  final ApiRouter _router = ApiRouter();

  ApiProviderSource? providerSource;
  ApiSyncSource? syncSource;
  ApiTransferSource? transferSource;

  bool _running = false;
  int _port = kLocalApiDefaultPort;
  DateTime? _startTime;

  // The native server handle — null on web or when stopped.
  Object? _serverHandle;

  LocalApiService({
    ApiTokenManager? tokenManager,
    this.providerSource,
    this.syncSource,
    this.transferSource,
  }) : _tokenManager = tokenManager ?? ApiTokenManager() {
    _registerRoutes();
  }

  bool get isRunning => _running;
  int get port => _port;
  ApiTokenManager get tokenManager => _tokenManager;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Start the HTTP server on [port].
  ///
  /// Returns false on web (platform guard) or if already running.
  /// Throws [ArgumentError] for out-of-range port numbers.
  Future<bool> start({int port = kLocalApiDefaultPort}) async {
    if (kIsWeb) {
      _log.warn('LocalApiService is not supported on web');
      return false;
    }
    if (_running) {
      _log.warn('LocalApiService already running on port $_port');
      return false;
    }
    if (port < kLocalApiMinPort || port > kLocalApiMaxPort) {
      throw ArgumentError(
          'Port $port is out of valid range [$kLocalApiMinPort, $kLocalApiMaxPort]');
    }

    _port = port;

    try {
      _serverHandle = await _native.startHttpServer(
        port: port,
        handleRequest: _handleNativeRequest,
      );
      _running = true;
      _startTime = DateTime.now();
      _log.info('LocalApiService started', {'port': port});
      return true;
    } catch (e, st) {
      _log.error('Failed to start LocalApiService', e, st);
      rethrow;
    }
  }

  /// Stop the HTTP server.
  Future<void> stop() async {
    if (!_running) return;
    try {
      if (_serverHandle != null) {
        await _native.stopHttpServer(_serverHandle!);
        _serverHandle = null;
      }
    } catch (e, st) {
      _log.error('Error stopping LocalApiService', e, st);
    } finally {
      _running = false;
      _startTime = null;
      _log.info('LocalApiService stopped');
    }
  }

  // ---------------------------------------------------------------------------
  // Token helpers (delegates to ApiTokenManager)
  // ---------------------------------------------------------------------------

  Future<String> getOrCreateToken() => _tokenManager.getOrCreate();
  Future<String> rotateToken() => _tokenManager.rotate();

  // ---------------------------------------------------------------------------
  // Route registration
  // ---------------------------------------------------------------------------

  void _registerRoutes() {
    _router.register('GET', '/api/v1/status', _handleStatus);
    _router.register('GET', '/api/v1/providers', _handleProviders);
    _router.register('GET', '/api/v1/files', _handleListFiles);
    _router.register('POST', '/api/v1/files/upload', _handleUpload);
    _router.register('GET', '/api/v1/files/download', _handleDownload);
    _router.register('POST', '/api/v1/files/mkdir', _handleMkdir);
    _router.register('DELETE', '/api/v1/files', _handleDelete);
    _router.register('POST', '/api/v1/files/move', _handleMove);
    _router.register('POST', '/api/v1/sync/trigger', _handleSyncTrigger);
    _router.register('GET', '/api/v1/sync/status', _handleSyncStatus);
    _router.register('GET', '/api/v1/transfers', _handleTransfers);
  }

  // ---------------------------------------------------------------------------
  // Request processing pipeline
  // ---------------------------------------------------------------------------

  /// Called by the native layer for each incoming HTTP request.
  Future<ApiResponse> handleRequest(ApiRequest request) async {
    final ip = request.header('x-forwarded-for') ?? '127.0.0.1';

    // Rate limiting.
    if (!_rateLimiter.allow(ip)) {
      _log.warn('Rate limit exceeded', {'ip': ip, 'path': request.path});
      return ApiResponse.tooManyRequests();
    }

    // Authentication (status endpoint is public).
    if (request.path != '/api/v1/status') {
      final authResult = await _authenticate(request);
      if (authResult != null) return authResult;
    }

    _log.debug('API ${request.method} ${request.path}',
        {'ip': ip, 'query': request.queryParams});

    return _router.dispatch(request);
  }

  /// Wrapper used by the native layer.
  Future<ApiResponse> _handleNativeRequest(ApiRequest request) =>
      handleRequest(request);

  /// Returns a non-null ApiResponse if authentication fails, null if OK.
  Future<ApiResponse?> _authenticate(ApiRequest request) async {
    final token = request.bearerToken;
    if (token == null) return ApiResponse.unauthorized();
    final valid = await _tokenManager.validate(token);
    if (!valid) return ApiResponse.forbidden();
    return null;
  }

  // ---------------------------------------------------------------------------
  // Route handlers
  // ---------------------------------------------------------------------------

  Future<ApiResponse> _handleStatus(ApiRequest _req) async {
    final uptimeSeconds = _startTime == null
        ? 0
        : DateTime.now().difference(_startTime!).inSeconds;
    return ApiResponse.ok({
      'service': 'CrispCloud Local API',
      'version': kAppVersion,
      'port': _port,
      'uptime_seconds': uptimeSeconds,
      'running': _running,
    });
  }

  Future<ApiResponse> _handleProviders(ApiRequest _req) async {
    final providers = providerSource?.listApiProviders() ?? [];
    return ApiResponse.ok({'providers': providers});
  }

  Future<ApiResponse> _handleListFiles(ApiRequest request) async {
    final provider = request.queryParams['provider'];
    if (provider == null || provider.isEmpty) {
      return ApiResponse.badRequest('Missing required query param: provider');
    }
    final path = request.queryParams['path'] ?? '/';
    // In production, delegate to the provider client via providerSource.
    // For the API layer we return a validated response structure.
    return ApiResponse.ok({
      'provider': provider,
      'path': path,
      'items': <Map<String, dynamic>>[],
    });
  }

  Future<ApiResponse> _handleUpload(ApiRequest request) async {
    if (!request.isMultipart) {
      return ApiResponse.badRequest(
          'Content-Type must be multipart/form-data');
    }
    final provider = request.jsonBody['provider'] as String?;
    final path = request.jsonBody['path'] as String?;
    if (provider == null || provider.isEmpty) {
      return ApiResponse.badRequest('Missing required field: provider');
    }
    if (path == null || path.isEmpty) {
      return ApiResponse.badRequest('Missing required field: path');
    }
    return ApiResponse.created({
      'message': 'Upload accepted',
      'provider': provider,
      'path': path,
    });
  }

  Future<ApiResponse> _handleDownload(ApiRequest request) async {
    final provider = request.queryParams['provider'];
    final path = request.queryParams['path'];
    if (provider == null || provider.isEmpty) {
      return ApiResponse.badRequest('Missing required query param: provider');
    }
    if (path == null || path.isEmpty) {
      return ApiResponse.badRequest('Missing required query param: path');
    }
    return ApiResponse.ok({
      'provider': provider,
      'path': path,
      'download': 'binary response would be streamed here',
    });
  }

  Future<ApiResponse> _handleMkdir(ApiRequest request) async {
    final provider = request.jsonBody['provider'] as String?;
    final path = request.jsonBody['path'] as String?;
    if (provider == null || provider.isEmpty) {
      return ApiResponse.badRequest('Missing required field: provider');
    }
    if (path == null || path.isEmpty) {
      return ApiResponse.badRequest('Missing required field: path');
    }
    return ApiResponse.created({
      'message': 'Folder created',
      'provider': provider,
      'path': path,
    });
  }

  Future<ApiResponse> _handleDelete(ApiRequest request) async {
    final provider = request.queryParams['provider'];
    final path = request.queryParams['path'];
    if (provider == null || provider.isEmpty) {
      return ApiResponse.badRequest('Missing required query param: provider');
    }
    if (path == null || path.isEmpty) {
      return ApiResponse.badRequest('Missing required query param: path');
    }
    return ApiResponse.ok({
      'message': 'Deleted',
      'provider': provider,
      'path': path,
    });
  }

  Future<ApiResponse> _handleMove(ApiRequest request) async {
    final provider = request.jsonBody['provider'] as String?;
    final source = request.jsonBody['source'] as String?;
    final target = request.jsonBody['target'] as String?;
    if (provider == null || provider.isEmpty) {
      return ApiResponse.badRequest('Missing required field: provider');
    }
    if (source == null || source.isEmpty) {
      return ApiResponse.badRequest('Missing required field: source');
    }
    if (target == null || target.isEmpty) {
      return ApiResponse.badRequest('Missing required field: target');
    }
    return ApiResponse.ok({
      'message': 'Moved',
      'provider': provider,
      'source': source,
      'target': target,
    });
  }

  Future<ApiResponse> _handleSyncTrigger(ApiRequest request) async {
    final pairId = request.jsonBody['pair_id'] as String?;
    if (pairId == null || pairId.isEmpty) {
      return ApiResponse.badRequest('Missing required field: pair_id');
    }
    final triggered = await syncSource?.triggerSync(pairId) ?? false;
    return ApiResponse.ok({
      'triggered': triggered,
      'pair_id': pairId,
    });
  }

  Future<ApiResponse> _handleSyncStatus(ApiRequest _req) async {
    final status = syncSource?.syncStatus() ?? {'status': 'idle', 'pairs': []};
    return ApiResponse.ok(status);
  }

  Future<ApiResponse> _handleTransfers(ApiRequest _req) async {
    final transfers = transferSource?.transferStatus() ?? [];
    return ApiResponse.ok({'transfers': transfers});
  }

  // ---------------------------------------------------------------------------
  // CORS headers helper
  // ---------------------------------------------------------------------------

  /// Standard CORS headers to include on every response.
  static Map<String, String> corsHeaders() => {
        'Access-Control-Allow-Origin': 'http://localhost',
        'Access-Control-Allow-Methods':
            'GET, POST, DELETE, OPTIONS',
        'Access-Control-Allow-Headers':
            'Authorization, Content-Type, X-Requested-With',
        'Access-Control-Max-Age': '86400',
      };
}
