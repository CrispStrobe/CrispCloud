/// HTTP transport layer for the Filen API.
///
/// Provides centralized request handling with retry logic, exponential backoff,
/// and bearer token authentication. Accepts an optional [http.Client] for
/// testability via MockClient.
import 'dart:convert';

import 'package:http/http.dart' as http;

class FilenApi {
  static const apiUrl = 'https://gateway.filen.io';

  final http.Client _client;
  String? apiKey;
  bool debugMode = false;

  FilenApi({http.Client? client}) : _client = client ?? http.Client();

  /// The underlying HTTP client (e.g. for direct chunk transfers to
  /// egest/ingest hosts). Exposed so callers reuse the same client —
  /// important for testing with a mock client.
  http.Client get client => _client;

  void log(String msg) {
    if (debugMode) print('🔍 [DEBUG] $msg');
  }

  void logWebDAV(String message) {
    if (debugMode) {
      final timestamp = DateTime.now().toIso8601String();
      print('[$timestamp] WebDAV: $message');
    }
  }

  /// Centralized request with retry logic and exponential backoff.
  Future<http.Response> makeRequest(
    String method,
    Uri url, {
    Map<String, String>? headers,
    dynamic body,
    bool useAuth = true,
    bool isAuthRetry = false,
    int maxRetries = 3,
    int retryCount = 0,
  }) async {
    // Clone so the Authorization injection never mutates the caller's map
    // (it would otherwise leak a stale bearer token across reuses/retries).
    final requestHeaders = headers != null
        ? Map<String, String>.from(headers)
        : <String, String>{'Content-Type': 'application/json'};
    if (useAuth && apiKey != null && apiKey!.isNotEmpty) {
      requestHeaders['Authorization'] = 'Bearer $apiKey';
    }

    http.Response response;
    try {
      switch (method.toUpperCase()) {
        case 'GET':
          response = await _client.get(url, headers: requestHeaders);
          break;
        case 'POST':
          response =
              await _client.post(url, headers: requestHeaders, body: body);
          break;
        case 'PUT':
          response =
              await _client.put(url, headers: requestHeaders, body: body);
          break;
        case 'PATCH':
          response =
              await _client.patch(url, headers: requestHeaders, body: body);
          break;
        case 'DELETE':
          final request = http.Request('DELETE', url)
            ..headers.addAll(requestHeaders)
            ..body = body ?? '';
          final streamedResponse = await _client.send(request);
          response = await http.Response.fromStream(streamedResponse);
          break;
        default:
          throw Exception('Unsupported HTTP method: $method');
      }
    } catch (e) {
      log('Network error: $e');
      if (retryCount < maxRetries) {
        final delay = Duration(seconds: 1 << retryCount);
        log('Retrying in ${delay.inSeconds}s... (${retryCount + 1}/$maxRetries)');
        await Future.delayed(delay);
        return makeRequest(
          method,
          url,
          headers: headers,
          body: body,
          useAuth: useAuth,
          isAuthRetry: isAuthRetry,
          maxRetries: maxRetries,
          retryCount: retryCount + 1,
        );
      }
      throw Exception('Network request failed after $maxRetries attempts: $e');
    }

    // Handle 5xx errors with retry
    if (response.statusCode >= 500 && response.statusCode < 600) {
      if (retryCount < maxRetries) {
        final delay = Duration(seconds: 1 << retryCount);
        log('Server error ${response.statusCode}. Retrying in ${delay.inSeconds}s...');
        await Future.delayed(delay);
        return makeRequest(
          method,
          url,
          headers: headers,
          body: body,
          useAuth: useAuth,
          isAuthRetry: isAuthRetry,
          maxRetries: maxRetries,
          retryCount: retryCount + 1,
        );
      }
    }

    // Handle 401
    if (response.statusCode == 401 && useAuth && !isAuthRetry) {
      log('Auth error (401). API key may be invalid.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      log('API Error ${response.statusCode}: ${response.body}');
      throw Exception('API Error: ${response.statusCode} - ${response.body}');
    }

    return response;
  }

  /// Convenience POST wrapper that parses JSON and checks status.
  Future<Map<String, dynamic>> post(String endpoint, dynamic body,
      {bool auth = true}) async {
    final r = await makeRequest(
      'POST',
      Uri.parse('$apiUrl$endpoint'),
      body: json.encode(body),
      useAuth: auth,
    );

    final d = json.decode(utf8.decode(r.bodyBytes, allowMalformed: true));
    if (d['status'] != true) throw Exception(d['message']);
    return d;
  }

  /// Token refresh stub (Filen uses long-lived API keys).
  Future<void> refreshToken() async {
    log('Token refresh not needed for Filen');
  }
}
