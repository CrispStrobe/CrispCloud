import 'package:crisp_storage/crisp_storage.dart' as storage;
// lib/adapters/webdav_adapter.dart
//
// Pure-Dart WebDAV adapter for the crisp CLI.
// Uses only package:http (no Flutter, no webdav_client package which has
// a transitive flutter dep). Implements the subset of WebDAV we need:
// PROPFIND, GET, PUT, DELETE, MKCOL, MOVE.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../config/cli_config.dart';
import 'bounded_download.dart';
import 'cli_storage_client.dart';

class WebDavCliAdapter implements CliStorageClient, CliBoundedDownload {
  final String _baseUrl; // e.g. https://dav.example.com (no trailing slash)
  final String _username;
  final String _password;

  late final Map<String, String> _authHeader;

  WebDavCliAdapter({
    required String baseUrl,
    required String username,
    required String password,
  })  : _baseUrl = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl,
        _username = username,
        _password = password {
    final encoded = base64Encode(utf8.encode('$_username:$_password'));
    _authHeader = {'Authorization': 'Basic $encoded'};
  }

  factory WebDavCliAdapter.fromConfig(Map<String, dynamic> cfg) {
    final username = cfg['username'] as String?;
    final password = cfg['password'] as String?;
    final host = cfg['host'] as String?;

    if (username == null || password == null || host == null) {
      throw CliConfigException(
        'WebDAV provider config missing required fields: username, password, host',
      );
    }
    return WebDavCliAdapter(
      baseUrl: host,
      username: username,
      password: password,
    );
  }

  /// Parse the identity string used with `crisp connect`:
  ///   user@https://dav.example.com
  static Map<String, String> parseIdentity(String identity, String password) {
    final splitIndex = identity.lastIndexOf('@http');
    if (splitIndex < 0) {
      throw CliConfigException(
        'Invalid WebDAV identity format. Expected: username@https://host',
      );
    }
    final username = identity.substring(0, splitIndex);
    final host = identity.substring(splitIndex + 1);
    return {
      'username': username,
      'password': password,
      'host': host,
    };
  }

  @override
  String get providerName => 'WebDAV';

  String _url(String remotePath) {
    final base = Uri.parse(_baseUrl);
    final prefix = base.pathSegments.toList();
    while (prefix.isNotEmpty && prefix.last.isEmpty) {
      prefix.removeLast();
    }
    final relative = remotePath.replaceFirst(RegExp(r'^/+'), '');
    // Inputs are decoded provider paths. Encode each segment exactly once so
    // a filename containing #, ?, spaces or % remains a filename, not a URL.
    return base.replace(pathSegments: [...prefix, ...relative.split('/')])
        .removeFragment().toString();
  }

  Map<String, String> get _headers => {
        ..._authHeader,
        'Accept': '*/*',
      };

  // ---------------------------------------------------------------------------
  // PROPFIND helper — parses a basic WebDAV multi-status response
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> _propfind(String remotePath,
      {int depth = 1}) async {
    final client = http.Client();
    try {
      final response = await client.send(
        http.Request('PROPFIND', Uri.parse(_url(remotePath)))
          ..followRedirects = false
          ..headers.addAll({
            ..._headers,
            'Depth': depth.toString(),
            'Content-Type': 'application/xml',
          })
          ..body = '''<?xml version="1.0" encoding="utf-8"?>
<propfind xmlns="DAV:">
  <prop>
    <displayname/>
    <getcontentlength/>
    <getlastmodified/>
    <resourcetype/>
  </prop>
</propfind>''',
      ).timeout(const Duration(seconds: 60));
      if (response.statusCode != 207 && response.statusCode != 200) {
        throw StateError('WebDAV PROPFIND failed (HTTP ${response.statusCode}).');
      }
      final bytes = await readBoundedResponseBytes(response,
          maxBytes: 16 * 1024 * 1024);
      return _parseMultiStatus(utf8.decode(bytes), remotePath, depth: depth);
    } finally {
      client.close();
    }
  }

  List<Map<String, dynamic>> _parseMultiStatus(String xml, String remotePath,
      {required int depth}) {
    try {
      final root = XmlDocument.parse(xml).rootElement;
      if (root.name.local != 'multistatus') {
        throw const FormatException('Expected DAV multistatus.');
      }
      XmlElement? child(XmlElement parent, String name, {bool required = false}) {
        final found = parent.childElements
            .where((element) => element.name.local == name).toList();
        if (found.length > 1 || (required && found.isEmpty)) {
          throw const FormatException('Missing or duplicate DAV property.');
        }
        return found.isEmpty ? null : found.single;
      }
      int status(XmlElement element) {
        final match = RegExp(r'^HTTP/[^ ]+ +([0-9]{3})(?: |$)')
            .firstMatch(element.innerText.trim());
        if (match == null) throw const FormatException('Invalid DAV status.');
        return int.parse(match.group(1)!);
      }
      List<String> segments(Uri uri) {
        final result = uri.pathSegments.toList();
        while (result.isNotEmpty && result.last.isEmpty) {
          result.removeLast();
        }
        if (result.any((part) => part.isEmpty || part.contains('/') ||
            part == '.' || part == '..' || part.contains('\u0000'))) {
          throw const FormatException('Invalid DAV resource path.');
        }
        return result;
      }
      bool samePath(List<String> a, List<String> b) =>
          a.length == b.length &&
          List.generate(a.length, (index) => a[index] == b[index]).every((v) => v);

      final requested = Uri.parse(_url(remotePath));
      final baseSegments = segments(requested);
      final results = <Map<String, dynamic>>[];
      final seenPaths = <String>{};
      var sawSelf = false;
      for (final response in root.childElements
          .where((element) => element.name.local == 'response')) {
        final href = Uri.parse(child(response, 'href', required: true)!.innerText.trim());
        final resolved = requested.resolveUri(href);
        if (resolved.scheme != requested.scheme || resolved.host != requested.host ||
            resolved.port != requested.port || resolved.userInfo.isNotEmpty ||
            resolved.hasQuery || resolved.hasFragment) {
          throw const FormatException('Unexpected DAV resource origin.');
        }
        final parts = segments(resolved);
        final isSelf = samePath(parts, baseSegments);
        if (!isSelf && (depth != 1 || parts.length != baseSegments.length + 1 ||
            !samePath(parts.sublist(0, baseSegments.length), baseSegments))) {
          throw const FormatException('DAV response is outside the requested directory.');
        }
        if (!seenPaths.add(parts.join('/'))) {
          throw const FormatException('Duplicate DAV resource.');
        }
        final responseStatus = child(response, 'status');
        if (responseStatus != null &&
            (status(responseStatus) < 200 || status(responseStatus) >= 300)) {
          throw const FormatException('DAV resource access failed.');
        }
        final properties = <String, XmlElement>{};
        for (final propstat in response.childElements
            .where((element) => element.name.local == 'propstat')) {
          final code = status(child(propstat, 'status', required: true)!);
          if (code < 200 || code >= 300) continue;
          final prop = child(propstat, 'prop', required: true)!;
          for (final property in prop.childElements) {
            if (properties.containsKey(property.name.local)) {
              throw const FormatException('Duplicate DAV property.');
            }
            properties[property.name.local] = property;
          }
        }
        final resourceType = properties['resourcetype'];
        if (resourceType == null) {
          throw const FormatException('DAV resource type was not returned successfully.');
        }
        final isDirectory = resourceType.childElements
            .any((element) => element.name.local == 'collection');
        if (isSelf && depth == 1 && !isDirectory) {
          throw const FormatException('Requested DAV parent is not a directory.');
        }
        final sizeText = properties['getcontentlength']?.innerText.trim();
        final size = sizeText == null || sizeText.isEmpty ? null : int.tryParse(sizeText);
        if (sizeText != null && sizeText.isNotEmpty && (size == null || size < 0)) {
          throw const FormatException('Invalid DAV content length.');
        }
        sawSelf |= isSelf;
        final name = parts.isEmpty ? '' : parts.last;
        results.add({
          // Keep adapter-facing paths relative to its configured base URL.
          // Returning the server's full href would apply that prefix twice.
          'href': isSelf ? remotePath : p.posix.join(remotePath, name),
          'name': name,
          'isDir': isDirectory,
          'isSelf': isSelf,
          'size': size,
          'modified': properties['getlastmodified']?.innerText,
        });
      }
      if (!sawSelf) throw const FormatException('Missing requested DAV resource.');
      return results;
    } catch (_) {
      // A successful HTTP response with unparseable/incomplete XML must never
      // authorize overwriting an apparently absent PDF. Do not log XML source.
      throw StateError('Invalid or incomplete WebDAV directory listing.');
    }
  }

  // ---------------------------------------------------------------------------
  // CliStorageClient implementation
  // ---------------------------------------------------------------------------

  @override
  Future<List<CliFileItem>> list(String remotePath) async {
    final entries = await _propfind(remotePath, depth: 1);
    return [
      for (final entry in entries)
        if (entry['isSelf'] != true)
          CliFileItem(
            name: entry['name'] as String,
            path: entry['href'] as String,
            isDirectory: entry['isDir'] as bool,
            size: entry['size'] as int?,
            modifiedAt: entry['modified'] as String?,
          ),
    ];
  }

  @override
  Future<void> upload(
    List<int> data,
    String fileName,
    String remoteDir, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final remotePath = p.posix.join(remoteDir, fileName);
    final response = await http.put(
      Uri.parse(_url(remotePath)),
      headers: {
        ..._headers,
        'Content-Type': 'application/octet-stream',
        'Content-Length': data.length.toString(),
      },
      body: Uint8List.fromList(data),
    );

    if (response.statusCode != 200 &&
        response.statusCode != 201 &&
        response.statusCode != 204) {
      throw Exception(
        'WebDAV upload failed (HTTP ${response.statusCode}): ${response.body}',
      );
    }
    onProgress?.call(data.length, data.length);
  }

  @override
  Future<List<int>> downloadBytes(String remotePath) async {
    final response = await http.get(
      Uri.parse(_url(remotePath)),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw Exception(
        'WebDAV download failed (HTTP ${response.statusCode}): ${response.body}',
      );
    }
    return response.bodyBytes;
  }

  @override
  Future<Uint8List> downloadBytesBounded(
    String remotePath, {
    required int maxBytes,
  }) => boundedHttpDownload(
    Uri.parse(_url(remotePath)),
    headers: _headers,
    maxBytes: maxBytes,
  );

  @override
  Future<void> download(
    String remotePath,
    String localPath, {
    void Function(int received, int total)? onProgress,
  }) async {
    final client = storage.RemoteClient(storage.RemoteConnection(
        id: 'cli-webdav',
        name: 'WebDAV',
        kind: 'webdav',
        url: _baseUrl,
        username: _username,
        secret: _password,
        allowLocalHttp: true));
    try {
      await client.download(
          Uri(path: remotePath.replaceFirst(RegExp(r'^/+'), '')).toString(),
          File(localPath),
          onBytes: (bytes) => onProgress?.call(bytes, 0));
    } finally {
      client.close();
    }
  }

  @override
  Future<void> createDirectory(String remotePath) async {
    final response = await http.Client().send(
      http.Request('MKCOL', Uri.parse(_url(remotePath)))
        ..headers.addAll(_headers),
    );
    final status = response.statusCode;
    if (status != 201 && status != 405 /* already exists */) {
      throw Exception('WebDAV MKCOL failed (HTTP $status)');
    }
  }

  @override
  Future<void> delete(String remotePath) async {
    final response = await http.delete(
      Uri.parse(_url(remotePath)),
      headers: _headers,
    );
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception(
        'WebDAV delete failed (HTTP ${response.statusCode}): ${response.body}',
      );
    }
  }

  @override
  Future<void> move(String sourcePath, String targetPath) async {
    final destination = _url(targetPath);
    final response = await http.Client().send(
      http.Request('MOVE', Uri.parse(_url(sourcePath)))
        ..headers.addAll({
          ..._headers,
          'Destination': destination,
          'Overwrite': 'T',
        }),
    );
    final status = response.statusCode;
    if (status != 201 && status != 204) {
      throw Exception('WebDAV MOVE failed (HTTP $status)');
    }
  }

  @override
  Future<CliFileItem?> stat(String remotePath) async {
    try {
      final entries = await _propfind(remotePath, depth: 0);
      if (entries.isEmpty) return null;
      final e = entries.first;
      return CliFileItem(
        name: e['name'] as String,
        path: remotePath,
        isDirectory: e['isDir'] as bool,
        size: e['size'] as int?,
        modifiedAt: e['modified'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String> share(String remotePath, {Duration? expires}) {
    throw UnsupportedError(
      'WebDAV does not have a standard share-link API. '
      'If your server supports Nextcloud/ownCloud sharing, use their web UI.',
    );
  }

  @override
  Future<void> dispose() async {}
}
