// test/mock_server/mock_webdav_server.dart
//
// In-process WebDAV mock HTTP server for offline CI testing.
// Uses dart:io HttpServer on localhost with port 0 (dynamic allocation).
// Supports PROPFIND, GET, PUT, DELETE, MKCOL, MOVE, COPY.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Represents a single node in the in-memory filesystem.
class _FsNode {
  final bool isDirectory;
  Uint8List data;
  DateTime lastModified;

  _FsNode.file(this.data) : isDirectory = false, lastModified = DateTime.now().toUtc();
  _FsNode.directory() : isDirectory = true, data = Uint8List(0), lastModified = DateTime.now().toUtc();
}

/// In-process mock WebDAV server.
///
/// The filesystem is represented as a flat map from canonical path → `_FsNode`.
/// Canonical paths always start with `/` and directories never have a trailing
/// slash (except the root `/`).
class MockWebDavServer {
  HttpServer? _server;

  /// path → node
  final Map<String, _FsNode> _fs = {};

  int get port => _server?.port ?? 0;

  String get baseUrl => 'http://127.0.0.1:$port';

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  Future<void> start([int port = 0]) async {
    // Seed root
    _fs['/'] = _FsNode.directory();
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _server!.listen(_handleRequest);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  // ---------------------------------------------------------------------------
  // Data helpers
  // ---------------------------------------------------------------------------

  void seedFile(String path, Uint8List data) {
    final canonical = _canonicalize(path);
    _ensureParents(canonical);
    _fs[canonical] = _FsNode.file(data);
  }

  void seedFolder(String path) {
    final canonical = _canonicalize(path);
    _ensureParents(canonical);
    _fs[canonical] = _FsNode.directory();
  }

  void reset() {
    _fs.clear();
    _fs['/'] = _FsNode.directory();
  }

  // ---------------------------------------------------------------------------
  // Path helpers
  // ---------------------------------------------------------------------------

  String _canonicalize(String path) {
    var p = path;
    if (!p.startsWith('/')) p = '/$p';
    // Remove trailing slash unless root
    if (p.length > 1 && p.endsWith('/')) p = p.substring(0, p.length - 1);
    return p;
  }

  String _parent(String path) {
    if (path == '/') return '/';
    final idx = path.lastIndexOf('/');
    if (idx == 0) return '/';
    return path.substring(0, idx);
  }

  String _name(String path) {
    if (path == '/') return '';
    return path.substring(path.lastIndexOf('/') + 1);
  }

  void _ensureParents(String path) {
    var current = path;
    while (current != '/') {
      current = _parent(current);
      if (!_fs.containsKey(current)) {
        _fs[current] = _FsNode.directory();
      }
    }
  }

  /// List direct children of [dirPath].
  List<String> _children(String dirPath) {
    final prefix = dirPath == '/' ? '/' : '$dirPath/';
    return _fs.keys.where((k) {
      if (k == dirPath) return false;
      if (!k.startsWith(prefix)) return false;
      // Direct child: no further slashes after the prefix
      final rest = k.substring(prefix.length);
      return !rest.contains('/');
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // Request dispatch
  // ---------------------------------------------------------------------------

  Future<void> _handleRequest(HttpRequest req) async {
    try {
      final method = req.method.toUpperCase();
      final path = _canonicalize(Uri.decodeComponent(req.uri.path));

      switch (method) {
        case 'PROPFIND':
          await _propfind(req, path);
          break;
        case 'GET':
          await _get(req, path);
          break;
        case 'PUT':
          await _put(req, path);
          break;
        case 'DELETE':
          await _delete(req, path);
          break;
        case 'MKCOL':
          await _mkcol(req, path);
          break;
        case 'MOVE':
          await _move(req, path);
          break;
        case 'COPY':
          await _copy(req, path);
          break;
        case 'HEAD':
          await _head(req, path);
          break;
        case 'OPTIONS':
          req.response.statusCode = 200;
          req.response.headers.set(
            'DAV',
            '1, 2',
          );
          req.response.headers.set(
            'Allow',
            'OPTIONS, GET, HEAD, PUT, DELETE, MKCOL, PROPFIND, MOVE, COPY',
          );
          await req.response.close();
          break;
        default:
          req.response.statusCode = 405;
          await req.response.close();
      }
    } catch (_) {
      try {
        req.response.statusCode = 500;
        await req.response.close();
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------------------
  // Operation handlers
  // ---------------------------------------------------------------------------

  Future<void> _propfind(HttpRequest req, String path) async {
    await req.drain<void>(); // consume body (we don't parse the XML query)

    final node = _fs[path];
    if (node == null) {
      req.response.statusCode = 404;
      await req.response.close();
      return;
    }

    final depthHeader = req.headers.value('Depth') ?? '1';
    final depth = depthHeader == 'infinity' ? 1 : (int.tryParse(depthHeader) ?? 1);

    final responses = <String>[];
    responses.add(_propfindEntry(path, node));

    if (depth >= 1 && node.isDirectory) {
      for (final childPath in _children(path)) {
        final child = _fs[childPath];
        if (child != null) {
          responses.add(_propfindEntry(childPath, child));
        }
      }
    }

    final body = '''<?xml version="1.0" encoding="UTF-8"?>
<D:multistatus xmlns:D="DAV:">
${responses.join('\n')}
</D:multistatus>''';

    final bytes = utf8.encode(body);
    req.response.statusCode = 207; // Multi-Status
    req.response.headers
      ..set('Content-Type', 'application/xml; charset=utf-8')
      ..set('Content-Length', bytes.length.toString());
    req.response.add(bytes);
    await req.response.close();
  }

  String _propfindEntry(String path, _FsNode node) {
    final href = _xmlEscape(path == '/' ? '/' : path);
    final displayName = _xmlEscape(_name(path));
    final lm = HttpDate.format(node.lastModified);
    final resourcetype = node.isDirectory
        ? '<D:resourcetype><D:collection/></D:resourcetype>'
        : '<D:resourcetype/>';
    final contentLength = node.isDirectory ? '' : '<D:getcontentlength>${node.data.length}</D:getcontentlength>';

    return '''  <D:response>
    <D:href>$href</D:href>
    <D:propstat>
      <D:prop>
        <D:displayname>$displayName</D:displayname>
        <D:getlastmodified>$lm</D:getlastmodified>
        $resourcetype
        $contentLength
      </D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>''';
  }

  Future<void> _get(HttpRequest req, String path) async {
    final node = _fs[path];
    if (node == null || node.isDirectory) {
      req.response.statusCode = node == null ? 404 : 405;
      await req.response.close();
      return;
    }
    req.response.statusCode = 200;
    req.response.headers
      ..set('Content-Length', node.data.length.toString())
      ..set('Content-Type', 'application/octet-stream')
      ..set('Last-Modified', HttpDate.format(node.lastModified));
    req.response.add(node.data);
    await req.response.close();
  }

  Future<void> _head(HttpRequest req, String path) async {
    await req.drain<void>();
    final node = _fs[path];
    if (node == null || node.isDirectory) {
      req.response.statusCode = node == null ? 404 : 405;
      await req.response.close();
      return;
    }
    req.response.statusCode = 200;
    req.response.headers
      ..set('Content-Length', node.data.length.toString())
      ..set('Content-Type', 'application/octet-stream')
      ..set('Last-Modified', HttpDate.format(node.lastModified));
    await req.response.close();
  }

  Future<void> _put(HttpRequest req, String path) async {
    final bytes = await _readBody(req);
    final data = Uint8List.fromList(bytes);
    _ensureParents(path);
    _fs[path] = _FsNode.file(data);
    req.response.statusCode = 201; // created / replaced
    await req.response.close();
  }

  Future<void> _delete(HttpRequest req, String path) async {
    await req.drain<void>();
    if (!_fs.containsKey(path)) {
      req.response.statusCode = 404;
      await req.response.close();
      return;
    }
    // Remove node and all descendants
    final toRemove = _fs.keys.where((k) => k == path || k.startsWith('$path/')).toList();
    for (final k in toRemove) {
      _fs.remove(k);
    }
    req.response.statusCode = 204;
    await req.response.close();
  }

  Future<void> _mkcol(HttpRequest req, String path) async {
    await req.drain<void>();
    if (_fs.containsKey(path)) {
      req.response.statusCode = 405; // already exists
      await req.response.close();
      return;
    }
    final parent = _parent(path);
    if (parent != path && !_fs.containsKey(parent)) {
      req.response.statusCode = 409; // parent not found
      await req.response.close();
      return;
    }
    _fs[path] = _FsNode.directory();
    req.response.statusCode = 201;
    await req.response.close();
  }

  Future<void> _move(HttpRequest req, String path) async {
    await req.drain<void>();
    final destHeader = req.headers.value('Destination');
    if (destHeader == null) {
      req.response.statusCode = 400;
      await req.response.close();
      return;
    }

    final dest = _canonicalize(Uri.decodeComponent(Uri.parse(destHeader).path));

    if (!_fs.containsKey(path)) {
      req.response.statusCode = 404;
      await req.response.close();
      return;
    }

    // Move all entries under the source path
    final toMove = _fs.keys.where((k) => k == path || k.startsWith('$path/')).toList();
    for (final k in toMove) {
      final newKey = k == path ? dest : '$dest${k.substring(path.length)}';
      _ensureParents(newKey);
      _fs[newKey] = _fs.remove(k)!;
    }

    req.response.statusCode = 201;
    await req.response.close();
  }

  Future<void> _copy(HttpRequest req, String path) async {
    await req.drain<void>();
    final destHeader = req.headers.value('Destination');
    if (destHeader == null) {
      req.response.statusCode = 400;
      await req.response.close();
      return;
    }

    final dest = _canonicalize(Uri.decodeComponent(Uri.parse(destHeader).path));

    if (!_fs.containsKey(path)) {
      req.response.statusCode = 404;
      await req.response.close();
      return;
    }

    final toCopy = _fs.keys.where((k) => k == path || k.startsWith('$path/')).toList();
    for (final k in toCopy) {
      final newKey = k == path ? dest : '$dest${k.substring(path.length)}';
      _ensureParents(newKey);
      final src = _fs[k]!;
      if (src.isDirectory) {
        _fs[newKey] = _FsNode.directory();
      } else {
        _fs[newKey] = _FsNode.file(Uint8List.fromList(src.data));
      }
    }

    req.response.statusCode = 201;
    await req.response.close();
  }

  // ---------------------------------------------------------------------------
  // Utility helpers
  // ---------------------------------------------------------------------------

  Future<List<int>> _readBody(HttpRequest req) async {
    final chunks = <List<int>>[];
    await for (final chunk in req) {
      chunks.add(chunk);
    }
    return chunks.expand((c) => c).toList();
  }

  String _xmlEscape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
