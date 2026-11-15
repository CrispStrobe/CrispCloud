import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:quds_office_engine/quds_office_engine.dart'
    show ZoteroHttpRequest, ZoteroHttpResponse;

/// Host-owned HTTP boundary for the shared, read-only Zotero client.
///
/// Each request owns its client so a timeout can close the connection without
/// cancelling another request. The cloud factory uses CrispCloud's selected
/// proxy and TLS policy. A host may separately opt into desktop Zotero by
/// supplying a direct loopback client factory. Local requests never use the
/// cloud factory or forward account credentials. No content is logged here.
class OfficeZoteroTransport {
  OfficeZoteroTransport({
    required this.createClient,
    this.createLocalClient,
    this.requestTimeout = const Duration(seconds: 20),
    this.maxResponseBytes = 8 * 1024 * 1024,
  }) {
    if (requestTimeout <= Duration.zero || maxResponseBytes <= 0) {
      throw ArgumentError('Zotero transport limits must be positive.');
    }
  }

  final http.Client Function() createClient;
  final http.Client Function()? createLocalClient;
  bool get supportsLocal => createLocalClient != null;
  final Duration requestTimeout;
  final int maxResponseBytes;
  final Set<http.Client> _clients = <http.Client>{};
  final Map<http.Client, StreamIterator<List<int>>> _bodies = {};
  bool _disposed = false;

  Future<ZoteroHttpResponse> send(ZoteroHttpRequest request) async {
    final uri = request.uri;
    if (_disposed) {
      throw const OfficeZoteroException('The Zotero connection is closed.');
    }
    final cloud =
        uri.scheme == 'https' &&
        uri.host == 'api.zotero.org' &&
        uri.port == 443;
    final local =
        supportsLocal &&
        uri.scheme == 'http' &&
        uri.host == 'localhost' &&
        uri.port == 23119 &&
        uri.path.startsWith('/api/');
    if ((!cloud && !local) ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        request.method != 'GET') {
      throw const OfficeZoteroException('The Zotero request is not supported.');
    }
    if (local) _validateLocalRequest(request);

    http.Client? client;
    try {
      client = local ? createLocalClient!() : createClient();
      _clients.add(client);
      final outbound = http.Request('GET', uri)
        ..followRedirects = false
        ..maxRedirects = 0
        ..headers.addAll(request.headers);
      return await _read(client, outbound).timeout(requestTimeout);
    } on OfficeZoteroException {
      rethrow;
    } on TimeoutException {
      throw const OfficeZoteroException(
        'Zotero did not respond in time. Please try again.',
      );
    } catch (_) {
      // Exceptions from HTTP clients can include headers, URLs or a response
      // body. Only a fixed diagnostic crosses into the user interface.
      throw const OfficeZoteroException(
        'Could not contact Zotero. Check the connection and try again.',
      );
    } finally {
      if (client != null && _clients.remove(client)) _close(client);
    }
  }

  static void _validateLocalRequest(ZoteroHttpRequest request) {
    final uri = request.uri;
    if (uri.pathSegments.any(
          (segment) =>
              segment == '.' ||
              segment == '..' ||
              segment.contains('/') ||
              segment.contains('\\') ||
              segment.contains('%'),
        ) ||
        uri.queryParameters.keys.any((key) => key.toLowerCase() == 'key')) {
      throw const OfficeZoteroException('The Zotero request is not supported.');
    }
    final headers = <String, String>{};
    for (final entry in request.headers.entries) {
      final name = entry.key.toLowerCase();
      if (headers.containsKey(name)) {
        throw const OfficeZoteroException(
          'The Zotero request is not supported.',
        );
      }
      final allowed = switch (name) {
        'zotero-api-version' => entry.value == '3',
        'zotero-allowed-request' => entry.value == '1',
        'zotero-server-id' => RegExp(
          r'^[A-Za-z0-9_-]{1,128}$',
        ).hasMatch(entry.value),
        _ => false,
      };
      if (!allowed) {
        throw const OfficeZoteroException(
          'The Zotero request is not supported.',
        );
      }
      headers[name] = entry.value;
    }
    if (headers['zotero-api-version'] != '3' ||
        headers['zotero-allowed-request'] != '1') {
      throw const OfficeZoteroException('The Zotero request is not supported.');
    }
  }

  Future<ZoteroHttpResponse> _read(
    http.Client client,
    http.Request request,
  ) async {
    final response = await client.send(request);
    final body = StreamIterator<List<int>>(response.stream);
    if (_disposed || !_clients.contains(client)) {
      await body.cancel();
      throw const OfficeZoteroException('The Zotero connection is closed.');
    }
    _bodies[client] = body;
    try {
      if ((response.contentLength ?? 0) > maxResponseBytes) {
        throw const OfficeZoteroException('The Zotero response is too large.');
      }
      final bytes = BytesBuilder(copy: false);
      while (await body.moveNext()) {
        final chunk = body.current;
        if (bytes.length + chunk.length > maxResponseBytes) {
          throw const OfficeZoteroException(
            'The Zotero response is too large.',
          );
        }
        bytes.add(chunk);
      }
      if (_disposed || !_clients.contains(client)) {
        throw const OfficeZoteroException('The Zotero connection is closed.');
      }
      return ZoteroHttpResponse(
        statusCode: response.statusCode,
        headers: response.headers,
        body: utf8.decode(bytes.takeBytes()),
      );
    } finally {
      _bodies.remove(client);
      await body.cancel();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final client in _clients) {
      _close(client);
    }
    _clients.clear();
  }

  void _close(http.Client client) {
    final body = _bodies.remove(client);
    if (body != null) unawaited(body.cancel().catchError((Object _) {}));
    try {
      client.close();
    } catch (_) {
      // Cleanup must not replace a sanitized network error with a backend
      // exception that could contain request headers.
    }
  }
}

class OfficeZoteroException implements Exception {
  const OfficeZoteroException(this.message);

  final String message;

  @override
  String toString() => message;
}
