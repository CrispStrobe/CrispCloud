// test/local_api_test.dart
//
// Unit tests for LocalApiService, ApiTokenManager, ApiRouter, and ApiResponse.
// Tests are written to run on the host (non-web) platform using the Dart test runner.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/services/local_api_service.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ApiRequest _makeRequest({
  String method = 'GET',
  String path = '/api/v1/status',
  Map<String, String>? query,
  Map<String, String>? headers,
  Map<String, dynamic>? body,
  String? token,
}) {
  final h = <String, String>{};
  if (headers != null) h.addAll(headers);
  if (token != null) h['authorization'] = 'Bearer $token';
  return ApiRequest(
    method: method,
    path: path,
    queryParams: query ?? {},
    headers: h,
    jsonBody: body ?? {},
    rawBody: Uint8List(0),
  );
}

/// A LocalApiService subclass with a pre-configured token for testing.
class _TestApiService extends LocalApiService {
  final String fixedToken;

  _TestApiService(this.fixedToken)
      : super(tokenManager: _FixedTokenManager(fixedToken));
}

class _FixedTokenManager extends ApiTokenManager {
  final String _token;
  _FixedTokenManager(this._token);

  @override
  Future<String> getOrCreate() async => _token;

  @override
  Future<bool> validate(String token) async => token == _token;
}

// ---------------------------------------------------------------------------
// ApiTokenManager tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ApiTokenManager — token generation', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('generates a token of length 48', () async {
      final mgr = ApiTokenManager();
      final token = await mgr.getOrCreate();
      expect(token.length, 48);
    });

    test('generated token is a valid hex string', () async {
      final mgr = ApiTokenManager();
      final token = await mgr.getOrCreate();
      expect(RegExp(r'^[0-9a-f]+$').hasMatch(token), isTrue);
    });

    test('two separate managers generate different tokens', () async {
      SharedPreferences.setMockInitialValues({});
      final t1 = await ApiTokenManager().getOrCreate();
      SharedPreferences.setMockInitialValues({});
      final t2 = await ApiTokenManager().getOrCreate();
      expect(t1, isNot(equals(t2)));
    });

    test('generateRaw produces 48 hex chars', () {
      final token = ApiTokenManager.generateRaw();
      expect(token.length, 48);
      expect(RegExp(r'^[0-9a-f]+$').hasMatch(token), isTrue);
    });

    test('generateRaw called twice produces different tokens', () {
      final t1 = ApiTokenManager.generateRaw();
      final t2 = ApiTokenManager.generateRaw();
      expect(t1, isNot(equals(t2)));
    });

    test('getOrCreate returns the same token on repeated calls', () async {
      final mgr = ApiTokenManager();
      final t1 = await mgr.getOrCreate();
      final t2 = await mgr.getOrCreate();
      expect(t1, equals(t2));
    });

    test('rotate produces a new token different from the previous', () async {
      final mgr = ApiTokenManager();
      final original = await mgr.getOrCreate();
      // Rotate until different (overwhelmingly likely on first attempt).
      String rotated;
      do {
        rotated = await mgr.rotate();
      } while (rotated == original);
      expect(rotated, isNot(equals(original)));
    });

    test('rotate still returns a 48-char hex token', () async {
      final mgr = ApiTokenManager();
      await mgr.getOrCreate();
      final rotated = await mgr.rotate();
      expect(rotated.length, 48);
      expect(RegExp(r'^[0-9a-f]+$').hasMatch(rotated), isTrue);
    });
  });

  group('ApiTokenManager — token validation', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('validate returns true for the correct token', () async {
      final mgr = ApiTokenManager();
      final token = await mgr.getOrCreate();
      expect(await mgr.validate(token), isTrue);
    });

    test('validate returns false for an empty string', () async {
      final mgr = ApiTokenManager();
      await mgr.getOrCreate();
      expect(await mgr.validate(''), isFalse);
    });

    test('validate returns false for a wrong token', () async {
      final mgr = ApiTokenManager();
      await mgr.getOrCreate();
      expect(await mgr.validate('deadbeef0000000000000000000000000000000000000000'), isFalse);
    });

    test('validate returns false when no token has been generated', () async {
      final mgr = ApiTokenManager();
      expect(await mgr.validate('some-token'), isFalse);
    });

    test('validate returns false after clear()', () async {
      final mgr = ApiTokenManager();
      final token = await mgr.getOrCreate();
      await mgr.clear();
      expect(await mgr.validate(token), isFalse);
    });

    test('validate returns false for malformed bearer (partial hex)', () async {
      final mgr = ApiTokenManager();
      await mgr.getOrCreate();
      expect(await mgr.validate('gg' * 24), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // ApiResponse tests
  // ---------------------------------------------------------------------------

  group('ApiResponse — construction and serialization', () {
    test('ok() sets statusCode 200 and isSuccess true', () {
      final r = ApiResponse.ok({'key': 'value'});
      expect(r.statusCode, 200);
      expect(r.isSuccess, isTrue);
    });

    test('created() sets statusCode 201', () {
      final r = ApiResponse.created({'id': '1'});
      expect(r.statusCode, 201);
      expect(r.isSuccess, isTrue);
    });

    test('badRequest() sets statusCode 400 and isSuccess false', () {
      final r = ApiResponse.badRequest('missing field');
      expect(r.statusCode, 400);
      expect(r.isSuccess, isFalse);
      expect(r.error, isNotNull);
    });

    test('unauthorized() sets statusCode 401', () {
      final r = ApiResponse.unauthorized();
      expect(r.statusCode, 401);
      expect(r.isSuccess, isFalse);
    });

    test('forbidden() sets statusCode 403', () {
      final r = ApiResponse.forbidden();
      expect(r.statusCode, 403);
      expect(r.isSuccess, isFalse);
    });

    test('notFound() sets statusCode 404', () {
      final r = ApiResponse.notFound('/bogus');
      expect(r.statusCode, 404);
      expect(r.isSuccess, isFalse);
    });

    test('methodNotAllowed() sets statusCode 405', () {
      final r = ApiResponse.methodNotAllowed('PATCH');
      expect(r.statusCode, 405);
    });

    test('tooManyRequests() sets statusCode 429', () {
      final r = ApiResponse.tooManyRequests();
      expect(r.statusCode, 429);
    });

    test('internalError() sets statusCode 500', () {
      final r = ApiResponse.internalError('boom');
      expect(r.statusCode, 500);
    });

    test('serviceUnavailable() sets statusCode 503', () {
      final r = ApiResponse.serviceUnavailable('not available');
      expect(r.statusCode, 503);
    });

    test('toJson includes status:ok for 2xx', () {
      final j = ApiResponse.ok({'foo': 'bar'}).toJson();
      expect(j['status'], 'ok');
      expect(j['foo'], 'bar');
    });

    test('toJson includes status:error for 4xx', () {
      final j = ApiResponse.badRequest('oops').toJson();
      expect(j['status'], 'error');
    });
  });

  // ---------------------------------------------------------------------------
  // ApiRouter — route matching
  // ---------------------------------------------------------------------------

  group('ApiRouter — route matching', () {
    late ApiRouter router;

    setUp(() {
      router = ApiRouter();
      router.register('GET', '/api/v1/status',
          (_) async => ApiResponse.ok({'test': true}));
      router.register('GET', '/api/v1/files',
          (_) async => ApiResponse.ok({'files': []}));
      router.register('POST', '/api/v1/files/upload',
          (_) async => ApiResponse.created({'uploaded': true}));
      router.register('DELETE', '/api/v1/files',
          (_) async => ApiResponse.ok({'deleted': true}));
    });

    test('exact GET match returns 200', () async {
      final r = await router.dispatch(_makeRequest(path: '/api/v1/status'));
      expect(r.statusCode, 200);
    });

    test('exact POST match returns 201', () async {
      final r = await router.dispatch(_makeRequest(
        method: 'POST',
        path: '/api/v1/files/upload',
        headers: {'content-type': 'multipart/form-data; boundary=xxx'},
      ));
      expect(r.statusCode, 201);
    });

    test('unknown path returns 404', () async {
      final r = await router.dispatch(_makeRequest(path: '/api/v1/bogus'));
      expect(r.statusCode, 404);
    });

    test('wrong method on known path returns 405', () async {
      final r = await router.dispatch(
          _makeRequest(method: 'PATCH', path: '/api/v1/status'));
      expect(r.statusCode, 405);
    });

    test('DELETE on /api/v1/files works', () async {
      final r = await router.dispatch(
          _makeRequest(method: 'DELETE', path: '/api/v1/files',
              query: {'provider': 'gdrive', 'path': '/x'}));
      expect(r.statusCode, 200);
    });

    test('query params are ignored for routing', () async {
      final r = await router.dispatch(_makeRequest(
          path: '/api/v1/files', query: {'provider': 'gdrive', 'path': '/'}));
      expect(r.statusCode, 200);
    });

    test('completely unknown path and method still returns 404', () async {
      final r = await router.dispatch(
          _makeRequest(method: 'CONNECT', path: '/hack'));
      expect(r.statusCode, 404);
    });
  });

  // ---------------------------------------------------------------------------
  // ApiRequest — parsing helpers
  // ---------------------------------------------------------------------------

  group('ApiRequest — parsing helpers', () {
    test('bearerToken extracted from Authorization header', () {
      final req = _makeRequest(token: 'abc123');
      expect(req.bearerToken, 'abc123');
    });

    test('bearerToken is null when header is absent', () {
      final req = _makeRequest();
      expect(req.bearerToken, isNull);
    });

    test('bearerToken is null for malformed header', () {
      final req = _makeRequest(headers: {'authorization': 'Basic dXNlcjpwYXNz'});
      expect(req.bearerToken, isNull);
    });

    test('isMultipart true when content-type is multipart/form-data', () {
      final req = _makeRequest(
          headers: {'content-type': 'multipart/form-data; boundary=---xyz'});
      expect(req.isMultipart, isTrue);
    });

    test('isMultipart false for application/json', () {
      final req = _makeRequest(
          headers: {'content-type': 'application/json'});
      expect(req.isMultipart, isFalse);
    });

    test('header() is case-insensitive', () {
      final req = _makeRequest(headers: {'Content-Type': 'application/json'});
      expect(req.header('content-type'), 'application/json');
    });
  });

  // ---------------------------------------------------------------------------
  // LocalApiService — auth middleware
  // ---------------------------------------------------------------------------

  group('LocalApiService — auth middleware', () {
    late _TestApiService svc;
    final validToken = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

    setUp(() {
      svc = _TestApiService(validToken);
    });

    test('missing Authorization header → 401', () async {
      final req = _makeRequest(path: '/api/v1/providers');
      final resp = await svc.handleRequest(req);
      expect(resp.statusCode, 401);
    });

    test('wrong token → 403', () async {
      final req = _makeRequest(path: '/api/v1/providers', token: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb');
      final resp = await svc.handleRequest(req);
      expect(resp.statusCode, 403);
    });

    test('valid token → handler runs (200)', () async {
      final req = _makeRequest(path: '/api/v1/providers', token: validToken);
      final resp = await svc.handleRequest(req);
      expect(resp.statusCode, 200);
    });

    test('/api/v1/status is accessible without a token', () async {
      final req = _makeRequest(path: '/api/v1/status');
      final resp = await svc.handleRequest(req);
      expect(resp.statusCode, 200);
    });
  });

  // ---------------------------------------------------------------------------
  // LocalApiService — status endpoint
  // ---------------------------------------------------------------------------

  group('LocalApiService — status endpoint', () {
    late _TestApiService svc;
    final validToken = 'cccccccccccccccccccccccccccccccccccccccccccccccc';

    setUp(() {
      svc = _TestApiService(validToken);
    });

    test('status response contains required fields', () async {
      final req = _makeRequest(path: '/api/v1/status');
      final resp = await svc.handleRequest(req);
      final body = resp.body;
      expect(body.containsKey('service'), isTrue);
      expect(body.containsKey('version'), isTrue);
      expect(body.containsKey('port'), isTrue);
      expect(body.containsKey('uptime_seconds'), isTrue);
      expect(body.containsKey('running'), isTrue);
    });

    test('status running field reflects service state', () async {
      final req = _makeRequest(path: '/api/v1/status');
      final resp = await svc.handleRequest(req);
      expect(resp.body['running'], isFalse);
    });

    test('status version matches kAppVersion', () async {
      final req = _makeRequest(path: '/api/v1/status');
      final resp = await svc.handleRequest(req);
      expect(resp.body['version'], kAppVersion);
    });
  });

  // ---------------------------------------------------------------------------
  // LocalApiService — providers endpoint
  // ---------------------------------------------------------------------------

  group('LocalApiService — providers endpoint', () {
    late _TestApiService svc;
    final validToken = 'dddddddddddddddddddddddddddddddddddddddddddddddd';

    setUp(() {
      svc = _TestApiService(validToken);
    });

    test('providers response contains providers list', () async {
      final req = _makeRequest(path: '/api/v1/providers', token: validToken);
      final resp = await svc.handleRequest(req);
      expect(resp.statusCode, 200);
      expect(resp.body.containsKey('providers'), isTrue);
      expect(resp.body['providers'], isList);
    });

    test('providers list is empty when no providerSource is set', () async {
      final req = _makeRequest(path: '/api/v1/providers', token: validToken);
      final resp = await svc.handleRequest(req);
      expect((resp.body['providers'] as List).isEmpty, isTrue);
    });

    test('providers list contains source data when providerSource is set',
        () async {
      svc.providerSource = _MockProviderSource();
      final req = _makeRequest(path: '/api/v1/providers', token: validToken);
      final resp = await svc.handleRequest(req);
      final list = resp.body['providers'] as List;
      expect(list.length, 1);
      expect(list.first['name'], 'TestProvider');
    });
  });

  // ---------------------------------------------------------------------------
  // LocalApiService — file listing validation
  // ---------------------------------------------------------------------------

  group('LocalApiService — file listing', () {
    late _TestApiService svc;
    final validToken = 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';

    setUp(() {
      svc = _TestApiService(validToken);
    });

    test('missing provider param → 400', () async {
      final req = _makeRequest(
          path: '/api/v1/files', token: validToken, query: {'path': '/'});
      final resp = await svc.handleRequest(req);
      expect(resp.statusCode, 400);
    });

    test('empty provider param → 400', () async {
      final req = _makeRequest(
          path: '/api/v1/files',
          token: validToken,
          query: {'provider': '', 'path': '/'});
      final resp = await svc.handleRequest(req);
      expect(resp.statusCode, 400);
    });

    test('valid provider param → 200 with items list', () async {
      final req = _makeRequest(
          path: '/api/v1/files',
          token: validToken,
          query: {'provider': 'gdrive', 'path': '/'});
      final resp = await svc.handleRequest(req);
      expect(resp.statusCode, 200);
      expect(resp.body.containsKey('items'), isTrue);
      expect(resp.body['provider'], 'gdrive');
    });

    test('default path is / when not supplied', () async {
      final req = _makeRequest(
          path: '/api/v1/files',
          token: validToken,
          query: {'provider': 'gdrive'});
      final resp = await svc.handleRequest(req);
      expect(resp.body['path'], '/');
    });
  });

  // ---------------------------------------------------------------------------
  // LocalApiService — upload validation
  // ---------------------------------------------------------------------------

  group('LocalApiService — upload', () {
    late _TestApiService svc;
    final validToken = 'ffffffffffffffffffffffffffffffffffffffffffffffff';

    setUp(() {
      svc = _TestApiService(validToken);
    });

    test('non-multipart content-type → 400', () async {
      final req = _makeRequest(
        method: 'POST',
        path: '/api/v1/files/upload',
        token: validToken,
        headers: {'content-type': 'application/json'},
      );
      final resp = await svc.handleRequest(req);
      expect(resp.statusCode, 400);
    });

    test('multipart but missing provider → 400', () async {
      final req = ApiRequest(
        method: 'POST',
        path: '/api/v1/files/upload',
        queryParams: {},
        headers: {
          'authorization': 'Bearer $validToken',
          'content-type': 'multipart/form-data; boundary=xxx',
        },
        jsonBody: {'path': '/'},
        rawBody: Uint8List(0),
      );
      final resp = await svc.handleRequest(req);
      expect(resp.statusCode, 400);
    });

    test('multipart with provider and path → 201', () async {
      final req = ApiRequest(
        method: 'POST',
        path: '/api/v1/files/upload',
        queryParams: {},
        headers: {
          'authorization': 'Bearer $validToken',
          'content-type': 'multipart/form-data; boundary=xxx',
        },
        jsonBody: {'provider': 'gdrive', 'path': '/docs/'},
        rawBody: Uint8List(0),
      );
      final resp = await svc.handleRequest(req);
      expect(resp.statusCode, 201);
    });
  });

  // ---------------------------------------------------------------------------
  // LocalApiService — CORS headers
  // ---------------------------------------------------------------------------

  group('LocalApiService — CORS headers', () {
    test('corsHeaders() contains required keys', () {
      final cors = LocalApiService.corsHeaders();
      expect(cors.containsKey('Access-Control-Allow-Origin'), isTrue);
      expect(cors.containsKey('Access-Control-Allow-Methods'), isTrue);
      expect(cors.containsKey('Access-Control-Allow-Headers'), isTrue);
    });

    test('corsHeaders() allows Authorization header', () {
      final cors = LocalApiService.corsHeaders();
      expect(cors['Access-Control-Allow-Headers'], contains('Authorization'));
    });

    test('corsHeaders() allows GET, POST, DELETE', () {
      final cors = LocalApiService.corsHeaders();
      final methods = cors['Access-Control-Allow-Methods'] ?? '';
      expect(methods, contains('GET'));
      expect(methods, contains('POST'));
      expect(methods, contains('DELETE'));
    });
  });

  // ---------------------------------------------------------------------------
  // Rate limiter
  // ---------------------------------------------------------------------------

  group('Rate limiter', () {
    test('101st request from same IP is blocked', () async {
      final svc = _TestApiService('000000000000000000000000000000000000000000000000');
      // First 100 requests to /api/v1/status should succeed.
      for (var i = 0; i < 100; i++) {
        final req = ApiRequest(
          method: 'GET',
          path: '/api/v1/status',
          queryParams: {},
          headers: {'x-forwarded-for': '10.0.0.1'},
          jsonBody: {},
          rawBody: Uint8List(0),
        );
        final resp = await svc.handleRequest(req);
        expect(resp.statusCode, isNot(429),
            reason: 'Request $i should not be rate-limited');
      }
      // 101st request should be rate-limited.
      final last = ApiRequest(
        method: 'GET',
        path: '/api/v1/status',
        queryParams: {},
        headers: {'x-forwarded-for': '10.0.0.1'},
        jsonBody: {},
        rawBody: Uint8List(0),
      );
      final resp = await svc.handleRequest(last);
      expect(resp.statusCode, 429);
    });

    test('different IPs have independent buckets', () async {
      final svc = _TestApiService('111111111111111111111111111111111111111111111111');
      // Exhaust quota for 10.0.0.2
      for (var i = 0; i < 100; i++) {
        await svc.handleRequest(ApiRequest(
          method: 'GET',
          path: '/api/v1/status',
          queryParams: {},
          headers: {'x-forwarded-for': '10.0.0.2'},
          jsonBody: {},
          rawBody: Uint8List(0),
        ));
      }
      // IP 10.0.0.3 is unaffected.
      final resp = await svc.handleRequest(ApiRequest(
        method: 'GET',
        path: '/api/v1/status',
        queryParams: {},
        headers: {'x-forwarded-for': '10.0.0.3'},
        jsonBody: {},
        rawBody: Uint8List(0),
      ));
      expect(resp.statusCode, isNot(429));
    });
  });

  // ---------------------------------------------------------------------------
  // Port validation
  // ---------------------------------------------------------------------------

  group('LocalApiService — port validation', () {
    test('start() throws ArgumentError for port < 1024', () async {
      final svc = _TestApiService('222222222222222222222222222222222222222222222222');
      expect(() => svc.start(port: 80), throwsArgumentError);
    });

    test('start() throws ArgumentError for port > 65535', () async {
      final svc = _TestApiService('222222222222222222222222222222222222222222222222');
      expect(() => svc.start(port: 70000), throwsArgumentError);
    });

    test('default port constant is 9847', () {
      expect(kLocalApiDefaultPort, 9847);
    });

    test('min port constant is 1024', () {
      expect(kLocalApiMinPort, 1024);
    });

    test('max port constant is 65535', () {
      expect(kLocalApiMaxPort, 65535);
    });
  });

  // ---------------------------------------------------------------------------
  // Platform guard
  // ---------------------------------------------------------------------------

  group('LocalApiService — platform guard', () {
    test('corsHeaders() always returns a non-empty map (safe on all platforms)',
        () {
      final cors = LocalApiService.corsHeaders();
      expect(cors, isNotEmpty);
    });

    test('ApiResponse.serviceUnavailable has status 503', () {
      final r = ApiResponse.serviceUnavailable('web not supported');
      expect(r.statusCode, 503);
      expect(r.error, 'service_unavailable');
    });
  });

  // ---------------------------------------------------------------------------
  // Server lifecycle (non-web only — skipped on web)
  // ---------------------------------------------------------------------------

  group('LocalApiService — server lifecycle', () {
    test('isRunning is false before start()', () {
      final svc = LocalApiService();
      expect(svc.isRunning, isFalse);
    });

    test('stop() when already stopped does not throw', () async {
      final svc = LocalApiService();
      await expectLater(svc.stop(), completes);
    });

    test('multiple sequential stop() calls are safe', () async {
      final svc = LocalApiService();
      await svc.stop();
      await svc.stop();
      expect(svc.isRunning, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Sync and transfer endpoints
  // ---------------------------------------------------------------------------

  group('LocalApiService — sync endpoints', () {
    late _TestApiService svc;
    final validToken = '333333333333333333333333333333333333333333333333';

    setUp(() {
      svc = _TestApiService(validToken);
    });

    test('POST /api/v1/sync/trigger with missing pair_id → 400', () async {
      final req = ApiRequest(
        method: 'POST',
        path: '/api/v1/sync/trigger',
        queryParams: {},
        headers: {'authorization': 'Bearer $validToken'},
        jsonBody: {},
        rawBody: Uint8List(0),
      );
      final resp = await svc.handleRequest(req);
      expect(resp.statusCode, 400);
    });

    test('POST /api/v1/sync/trigger with pair_id → 200', () async {
      svc.syncSource = _MockSyncSource();
      final req = ApiRequest(
        method: 'POST',
        path: '/api/v1/sync/trigger',
        queryParams: {},
        headers: {'authorization': 'Bearer $validToken'},
        jsonBody: {'pair_id': 'pair-1'},
        rawBody: Uint8List(0),
      );
      final resp = await svc.handleRequest(req);
      expect(resp.statusCode, 200);
      expect(resp.body['triggered'], isTrue);
    });

    test('GET /api/v1/sync/status → 200 with status field', () async {
      final req = _makeRequest(
          path: '/api/v1/sync/status', token: validToken);
      final resp = await svc.handleRequest(req);
      expect(resp.statusCode, 200);
      expect(resp.body.containsKey('status'), isTrue);
    });

    test('GET /api/v1/transfers → 200 with transfers list', () async {
      final req = _makeRequest(
          path: '/api/v1/transfers', token: validToken);
      final resp = await svc.handleRequest(req);
      expect(resp.statusCode, 200);
      expect(resp.body.containsKey('transfers'), isTrue);
      expect(resp.body['transfers'], isList);
    });
  });

  // ---------------------------------------------------------------------------
  // Move and mkdir
  // ---------------------------------------------------------------------------

  group('LocalApiService — move and mkdir', () {
    late _TestApiService svc;
    final validToken = '444444444444444444444444444444444444444444444444';

    setUp(() {
      svc = _TestApiService(validToken);
    });

    test('POST /api/v1/files/move missing source → 400', () async {
      final req = ApiRequest(
        method: 'POST',
        path: '/api/v1/files/move',
        queryParams: {},
        headers: {'authorization': 'Bearer $validToken'},
        jsonBody: {'provider': 'gdrive', 'target': '/b/file.txt'},
        rawBody: Uint8List(0),
      );
      final resp = await svc.handleRequest(req);
      expect(resp.statusCode, 400);
    });

    test('POST /api/v1/files/move with all fields → 200', () async {
      final req = ApiRequest(
        method: 'POST',
        path: '/api/v1/files/move',
        queryParams: {},
        headers: {'authorization': 'Bearer $validToken'},
        jsonBody: {
          'provider': 'gdrive',
          'source': '/a/file.txt',
          'target': '/b/file.txt',
        },
        rawBody: Uint8List(0),
      );
      final resp = await svc.handleRequest(req);
      expect(resp.statusCode, 200);
      expect(resp.body['source'], '/a/file.txt');
      expect(resp.body['target'], '/b/file.txt');
    });

    test('POST /api/v1/files/mkdir with all fields → 201', () async {
      final req = ApiRequest(
        method: 'POST',
        path: '/api/v1/files/mkdir',
        queryParams: {},
        headers: {'authorization': 'Bearer $validToken'},
        jsonBody: {'provider': 'gdrive', 'path': '/new-folder'},
        rawBody: Uint8List(0),
      );
      final resp = await svc.handleRequest(req);
      expect(resp.statusCode, 201);
    });

    test('POST /api/v1/files/mkdir missing path → 400', () async {
      final req = ApiRequest(
        method: 'POST',
        path: '/api/v1/files/mkdir',
        queryParams: {},
        headers: {'authorization': 'Bearer $validToken'},
        jsonBody: {'provider': 'gdrive'},
        rawBody: Uint8List(0),
      );
      final resp = await svc.handleRequest(req);
      expect(resp.statusCode, 400);
    });
  });

  // ---------------------------------------------------------------------------
  // Delete endpoint
  // ---------------------------------------------------------------------------

  group('LocalApiService — delete', () {
    late _TestApiService svc;
    final validToken = '555555555555555555555555555555555555555555555555';

    setUp(() {
      svc = _TestApiService(validToken);
    });

    test('DELETE /api/v1/files missing provider → 400', () async {
      final req = _makeRequest(
        method: 'DELETE',
        path: '/api/v1/files',
        token: validToken,
        query: {'path': '/file.txt'},
      );
      final resp = await svc.handleRequest(req);
      expect(resp.statusCode, 400);
    });

    test('DELETE /api/v1/files missing path → 400', () async {
      final req = _makeRequest(
        method: 'DELETE',
        path: '/api/v1/files',
        token: validToken,
        query: {'provider': 'gdrive'},
      );
      final resp = await svc.handleRequest(req);
      expect(resp.statusCode, 400);
    });

    test('DELETE /api/v1/files with all params → 200', () async {
      final req = _makeRequest(
        method: 'DELETE',
        path: '/api/v1/files',
        token: validToken,
        query: {'provider': 'gdrive', 'path': '/file.txt'},
      );
      final resp = await svc.handleRequest(req);
      expect(resp.statusCode, 200);
      expect(resp.body['path'], '/file.txt');
    });
  });
}

// ---------------------------------------------------------------------------
// Mock sources
// ---------------------------------------------------------------------------

class _MockProviderSource implements ApiProviderSource {
  @override
  List<Map<String, dynamic>> listApiProviders() => [
        {'name': 'TestProvider', 'capabilities': []},
      ];
}

class _MockSyncSource implements ApiSyncSource {
  @override
  Map<String, dynamic> syncStatus() => {'status': 'idle', 'pairs': []};

  @override
  Future<bool> triggerSync(String pairId) async => true;
}
