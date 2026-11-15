import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:quds_office_editor/quds_office_editor.dart'
    show WordEditorController;
import 'package:quds_office_engine/quds_office_engine.dart';

import 'secure_storage_service.dart';

/// Captures the intended insertion target before asynchronous credential I/O.
/// Layout-only notifications preserve this value; document, content, story or
/// selection changes invalidate it even when the controller is still mounted.
Object officeZoteroEditTarget(WordEditorController controller) => (
  document: controller.document,
  revision: controller.contentRevision,
  caret: controller.caret,
  paragraph: controller.caret.paragraphIndex,
  offset: controller.caret.logicalIndex,
  anchorParagraph: controller.caret.selectionAnchorParagraph,
  anchorOffset: controller.caret.selectionAnchor,
  headerFooter: controller.isEditingHeaderFooter,
  footer: controller.isEditingFooter,
  section: controller.isEditingHeaderFooter
      ? controller.editingSectionIndex
      : null,
  comment: controller.isEditingComment ? controller.selectedComment : null,
  frame: controller.selectedFrame,
  editingFrame: controller.editingFrame,
  table: controller.selectedTable,
  tableBand: controller.selectedTableBand,
  visual: controller.selectedVisual,
  equation: controller.selectedEquation,
);

/// Host-owned HTTP boundary for the shared, read-only Zotero client.
///
/// Each request owns its client so a timeout can close the connection without
/// cancelling another request. The factory should use CrispCloud's selected
/// proxy and TLS policy. No request or response content is logged here.
class OfficeZoteroTransport {
  OfficeZoteroTransport({
    required this.createClient,
    this.requestTimeout = const Duration(seconds: 20),
    this.maxResponseBytes = 8 * 1024 * 1024,
  }) {
    if (requestTimeout <= Duration.zero || maxResponseBytes <= 0) {
      throw ArgumentError('Zotero transport limits must be positive.');
    }
  }

  final http.Client Function() createClient;
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
    if (uri.scheme != 'https' ||
        uri.host != 'api.zotero.org' ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        request.method != 'GET') {
      throw const OfficeZoteroException('The Zotero request is not supported.');
    }

    http.Client? client;
    try {
      client = createClient();
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

/// Optional persistence uses the credential store selected at app startup.
/// Session-only storage never pretends to remember a key across restarts.
class OfficeZoteroCredentials {
  OfficeZoteroCredentials(this._storage);

  static const storageKey = 'zotero_api_key';
  final SecureStorage _storage;

  bool get canPersist => _storage.isPersistent;

  Future<String?> load() async {
    if (!canPersist) return null;
    try {
      final key = await _storage.read(storageKey);
      if (key == null || key.trim().isEmpty) return null;
      return _validated(key);
    } catch (_) {
      throw const OfficeZoteroException(
        'Could not read the saved Zotero API key.',
      );
    }
  }

  Future<void> save(String? apiKey) async {
    if (!canPersist) {
      throw const OfficeZoteroException(
        'The current credential store cannot remember Zotero API keys.',
      );
    }
    final key = apiKey == null || apiKey.trim().isEmpty
        ? null
        : _validated(apiKey);
    try {
      if (key == null) {
        await _storage.delete(storageKey);
      } else {
        await _storage.write(storageKey, key);
      }
      if (await _storage.read(storageKey) != key) {
        throw const OfficeZoteroException(
          'The Zotero API key could not be saved in the credential store.',
        );
      }
    } catch (_) {
      throw const OfficeZoteroException(
        'The Zotero API key could not be saved in the credential store.',
      );
    }
  }

  String _validated(String key) {
    if (RegExp(r'[\x00-\x1f\x7f]').hasMatch(key)) {
      throw const OfficeZoteroException('The Zotero API key is invalid.');
    }
    return key.trim();
  }
}

class OfficeZoteroException implements Exception {
  const OfficeZoteroException(this.message);

  final String message;

  @override
  String toString() => message;
}
