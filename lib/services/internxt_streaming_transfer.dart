import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:internxt_client/auth.dart' as sdk_auth;
import 'package:internxt_client/api.dart' as sdk_api;
import 'package:internxt_client/crypto.dart' as sdk_crypto;
import 'package:internxt_client/drive.dart' as sdk_drive;
import 'package:path/path.dart' as p;

import 'bounded_http_transfer.dart';
import 'bounded_transfer_stream.dart';
import 'internxt_transfer_platform.dart';
import 'spooled_http_upload.dart';
import 'transfer_spool.dart';
import 'transfer_stream_request.dart';

class InternxtPathNotFound implements Exception {
  const InternxtPathNotFound();
}

/// Immutable credentials for one operation. Nothing here logs or persists them.
class InternxtTransferSession {
  InternxtTransferSession({
    required this.driveUrl,
    required this.networkUrl,
    required this.token,
    required this.mnemonic,
    required this.bucket,
    required this.rootFolder,
    required this.bridgeUser,
    required String userIdForAuth,
    required this.checkCurrent,
  }) : bridgePassword = sdk_auth.computeBridgePass(userIdForAuth);
  final String driveUrl, networkUrl, token, mnemonic, bucket, rootFolder;
  final String bridgeUser, bridgePassword;
  final void Function() checkCurrent;

  Map<String, String> get driveHeaders => {
    'authorization': 'Bearer $token',
    'accept': 'application/json',
    'content-type': 'application/json',
    'internxt-client': 'cli',
  };
  Map<String, String> get networkHeaders => {
    'authorization':
        'Basic ${base64Encode(utf8.encode('$bridgeUser:$bridgePassword'))}',
    'accept': 'application/json',
    'content-type': 'application/json',
    'internxt-client': 'cli',
    'x-api-version': '2',
  };
}

/// Bounds encrypted transfer memory independently of object or multipart size.
/// Implements the Internxt 0.2.3 start/finish/register protocol with no automatic
/// retries of mutations. SDK crypto is reused; its buffered transfer APIs are not.
class InternxtStreamingTransfer {
  const InternxtStreamingTransfer({
    this.multipartMinimum = 100 * 1024 * 1024,
    this.preferredPartSize = 30 * 1024 * 1024,
  });
  static const chunkSize = 64 * 1024;
  static const maxUploadSize = 20 * 1024 * 1024 * 1024;
  // Adaptive part sizes keep signed-URL metadata bounded as well as file data.
  static const maxParts = 128;
  final int multipartMinimum, preferredPartSize;

  static Uri _endpoint(
    String base,
    List<String> segments, [
    Map<String, String>? query,
  ]) {
    var uri = Uri.parse(base);
    if (!uri.hasScheme) uri = Uri.base.resolveUri(uri);
    if (uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.host.isEmpty ||
        (uri.scheme != 'https' && !(kIsWeb && uri.origin == Uri.base.origin))) {
      throw StateError('Internxt requires a secure API address.');
    }
    return uri.replace(
      pathSegments: [
        ...uri.pathSegments.where((s) => s.isNotEmpty),
        ...segments,
      ],
      queryParameters: query,
    );
  }

  static String _id(Object? value, String field) {
    if (value is! String ||
        value.isEmpty ||
        value.length > 256 ||
        value.contains(RegExp(r'[\x00-\x20/\\]'))) {
      throw FormatException('Internxt returned an invalid $field.');
    }
    return value;
  }

  static int _size(Object? value) {
    final size = value is int
        ? value
        : value is String && RegExp(r'^\d+$').hasMatch(value)
        ? int.tryParse(value)
        : null;
    if (size == null || size < 0 || size > 9007199254740991) {
      throw const FormatException('Internxt returned an invalid file length.');
    }
    return size;
  }

  Future<Map<String, dynamic>> _json(
    InternxtTransferSession session,
    Uri uri, {
    String method = 'GET',
    Map<String, dynamic>? body,
    bool network = false,
    required String operation,
  }) async {
    session.checkCurrent();
    final client = http.Client();
    try {
      final request = http.Request(method, uri)
        ..followRedirects = false
        ..headers.addAll(
          network ? session.networkHeaders : session.driveHeaders,
        );
      if (body != null) request.body = jsonEncode(body);
      final response = await sendTransferRequest(
        client,
        request,
        operation: operation,
      );
      session.checkCurrent();
      if (response.statusCode != 200 &&
          !(method == 'POST' && response.statusCode == 201)) {
        throw StateError('$operation failed (${response.statusCode}).');
      }
      try {
        return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
      } catch (_) {
        throw StateError('$operation returned invalid metadata.');
      }
    } finally {
      client.close();
    }
  }

  /// SDK path functions accept external caches. Fresh request-local maps avoid
  /// the session class's inaccessible one-hour cache after direct uploads.
  Future<Map<String, dynamic>> resolve(
    InternxtTransferSession session,
    String path,
  ) async {
    session.checkCurrent();
    final client = _MetadataClient(session.checkCurrent);
    try {
      final value = await sdk_drive.resolvePath(
        _endpoint(session.driveUrl, []).toString(),
        session.token,
        session.rootFolder,
        {},
        {},
        path,
        client: client,
      );
      session.checkCurrent();
      return value;
    } catch (error) {
      session.checkCurrent();
      if (error.toString().startsWith('Exception: Path not found: ')) {
        throw const InternxtPathNotFound();
      }
      throw StateError('Internxt could not resolve the selected path.');
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> list(
    InternxtTransferSession session,
    String path,
  ) async {
    final folder = await resolve(session, path);
    if (folder['type'] != 'folder') {
      throw StateError('The selected path is not a folder.');
    }
    final id = _id(folder['uuid'], 'folder identity');
    final client = _MetadataClient(session.checkCurrent);
    try {
      final driveUrl = _endpoint(session.driveUrl, []).toString();
      final folders = await sdk_drive.listFolders(
        driveUrl,
        session.token,
        {},
        id,
        detailed: true,
        client: client,
      );
      session.checkCurrent();
      final files = await sdk_drive.listFolderFiles(
        driveUrl,
        session.token,
        {},
        id,
        detailed: true,
        client: client,
      );
      session.checkCurrent();
      return {'folders': folders, 'files': files};
    } catch (_) {
      session.checkCurrent();
      throw StateError('Internxt could not list the selected folder.');
    } finally {
      client.close();
    }
  }

  Stream<List<int>> download(
    InternxtTransferSession session,
    String path, {
    void Function(int, int)? onProgress,
    int? maxBytes,
  }) async* {
    final resolved = await resolve(session, path);
    if (resolved['type'] != 'file') {
      throw StateError('The selected path is not a file.');
    }
    final uuid = _id(resolved['uuid'], 'file identity');
    final meta = await _json(
      session,
      _endpoint(session.driveUrl, ['files', uuid, 'meta']),
      operation: 'Internxt file metadata',
    );
    final size = _size(meta['size']);
    if (maxBytes != null && size > maxBytes) {
      throw StateError('This Internxt file requires a streaming download.');
    }
    if (meta['uuid'] != null && meta['uuid'] != uuid) {
      throw StateError('Internxt returned a different file identity.');
    }
    final bucket = _id(meta['bucket'], 'bucket identity');
    final fileId = _id(meta['fileId'], 'network file identity');
    final links = await _json(
      session,
      _endpoint(session.networkUrl, [
        'buckets',
        bucket,
        'files',
        fileId,
        'info',
      ]),
      network: true,
      operation: 'Internxt download link',
    );
    final index = links['index'];
    final shards = links['shards'];
    if (index is! String ||
        !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(index) ||
        shards is! List ||
        shards.length != 1 ||
        shards.single is! Map) {
      throw const FormatException(
        'Internxt returned an unsupported encrypted download layout.',
      );
    }
    final shard = shards.single as Map;
    if (shard['url'] is! String) {
      throw const FormatException('Internxt returned no download address.');
    }
    final cipher = sdk_crypto.downloadDecryptor(
      session.mnemonic,
      bucket,
      index,
    );
    final digest = _DigestSink();
    final hash = crypto.sha256.startChunkedConversion(digest);
    var received = 0;
    try {
      await for (final bytes in streamHttpDownload(
        Uri.parse(shard['url'] as String),
        operation: 'Internxt encrypted download',
        expectedLength: size,
        followRedirects: false,
        checkCurrent: session.checkCurrent,
      )) {
        for (var offset = 0; offset < bytes.length; offset += chunkSize) {
          session.checkCurrent();
          final chunk = Uint8List.fromList(
            bytes.sublist(offset, math.min(offset + chunkSize, bytes.length)),
          );
          hash.add(chunk);
          final plain = cipher.process(chunk);
          received += plain.length;
          onProgress?.call(received, size);
          yield plain;
        }
      }
    } finally {
      hash.close();
    }
    session.checkCurrent();
    if (received != size) {
      throw StateError('Internxt download ended before its expected length.');
    }
    final expectedHash = shard['hash'];
    if (expectedHash is String &&
        RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(expectedHash) &&
        digest.value.toString() != expectedHash.toLowerCase()) {
      throw StateError('Internxt encrypted content failed its checksum.');
    }
    onProgress?.call(size, size);
  }

  Future<void> upload(
    InternxtTransferSession session,
    Stream<List<int>> source,
    int length,
    String name,
    String targetPath, {
    void Function(int, int)? onProgress,
  }) async {
    if (length < 0 || length > maxUploadSize) {
      throw ArgumentError.value(length, 'length', 'Expected 0–20 GiB.');
    }
    if (multipartMinimum <= 0 || preferredPartSize <= 0) {
      throw StateError('Invalid multipart settings.');
    }
    if (name.isEmpty ||
        name == '.' ||
        name == '..' ||
        name.contains('/') ||
        name.contains(r'\') ||
        name.contains('\u0000')) {
      throw const FormatException('Enter a file name without path separators.');
    }
    session.checkCurrent();
    final target = await resolve(session, targetPath);
    if (target['type'] != 'folder') {
      throw StateError('The upload destination is not a folder.');
    }
    final folder = _id(target['uuid'], 'folder identity');
    final index =
        sdk_crypto.encryptStream(
              Uint8List(0),
              session.mnemonic,
              session.bucket,
            )['index']
            as String;
    final cipher = sdk_crypto.downloadDecryptor(
      session.mnemonic,
      session.bucket,
      index,
    );
    final digest = _DigestSink();
    final hash = crypto.sha256.startChunkedConversion(digest);
    Stream<List<int>> encrypted() async* {
      try {
        await for (final part in validatedTransferParts(
          source,
          length,
          chunkSize,
        )) {
          session.checkCurrent();
          final bytes = cipher.process(part);
          hash.add(bytes);
          yield bytes;
        }
        session.checkCurrent();
      } finally {
        hash.close();
      }
    }

    final spool = await createTransferSpool(
      encrypted(),
      expectedLength: length,
      maxBytes: maxUploadSize,
      checkpoint: () async => session.checkCurrent(),
    );
    try {
      session.checkCurrent();
      final multipart = length >= multipartMinimum;
      final partSize = math.max(
        preferredPartSize,
        (length + maxParts - 1) ~/ maxParts,
      );
      final count = multipart ? (length + partSize - 1) ~/ partSize : 1;
      final started = await _json(
        session,
        _endpoint(
          session.networkUrl,
          ['v2', 'buckets', session.bucket, 'files', 'start'],
          {'multiparts': '$count'},
        ),
        method: 'POST',
        network: true,
        operation: 'Internxt upload initialization',
        body: {
          'uploads': [
            {'index': 0, 'size': length},
          ],
        },
      );
      final uploads = started['uploads'];
      if (uploads is! List || uploads.length != 1 || uploads.single is! Map) {
        throw const FormatException(
          'Internxt returned an invalid upload layout.',
        );
      }
      final upload = uploads.single as Map;
      final shard = <String, dynamic>{
        'hash': digest.value.toString(),
        'uuid': _id(upload['uuid'], 'upload identity'),
      };
      if (multipart) {
        final urls = upload['urls'];
        if (urls is! List ||
            urls.length != count ||
            urls.any((url) => url is! String)) {
          throw const FormatException(
            'Internxt returned an incomplete multipart upload layout.',
          );
        }
        shard['UploadId'] = _id(
          upload['UploadId'] ?? upload['uploadId'],
          'multipart identity',
        );
        final parts = <Map<String, dynamic>>[];
        for (var part = 0; part < count; part++) {
          final start = part * partSize,
              end = math.min((part + 1) * partSize, length);
          final slice = sliceInternxtSpool(spool, start, end);
          final response = await _put(
            session,
            Uri.parse(urls[part] as String),
            slice,
            onProgress: (sent, total) => onProgress?.call(start + sent, length),
          );
          final etag = response.headers['etag']?.replaceAll('"', '');
          if (etag == null ||
              etag.isEmpty ||
              etag.length > 256 ||
              etag.contains(RegExp(r'[\r\n]'))) {
            throw StateError(
              'Internxt multipart response has no usable ETag; browser CORS must expose ETag.',
            );
          }
          parts.add({'PartNumber': part + 1, 'ETag': etag});
        }
        shard['parts'] = parts;
      } else {
        if (upload['url'] is! String) {
          throw const FormatException('Internxt returned no upload address.');
        }
        await _put(
          session,
          Uri.parse(upload['url'] as String),
          spool,
          onProgress: onProgress,
        );
      }
      final finished = await _json(
        session,
        _endpoint(session.networkUrl, [
          'v2',
          'buckets',
          session.bucket,
          'files',
          'finish',
        ]),
        method: 'POST',
        network: true,
        operation: 'Internxt upload finalization',
        body: {
          'index': index,
          'shards': [shard],
        },
      );
      final fileId = _id(finished['id'], 'network file identity');
      final plainName = p.posix.basenameWithoutExtension(name),
          type = p.posix.extension(name).replaceFirst('.', '');
      final created = await _json(
        session,
        _endpoint(session.driveUrl, ['files']),
        method: 'POST',
        operation: 'Internxt file registration',
        body: {
          'folderUuid': folder,
          'plainName': plainName,
          'type': type,
          'size': length,
          'bucket': session.bucket,
          'fileId': fileId,
          'encryptVersion': 'Aes03',
          'name': '',
          'creationTime': null,
          'modificationTime': null,
        },
      );
      final uuid = _id(created['uuid'], 'created file identity');
      final confirmed = await _json(
        session,
        _endpoint(session.driveUrl, ['files', uuid, 'meta']),
        operation: 'Internxt upload verification',
      );
      if (confirmed['fileId'] != fileId ||
          confirmed['bucket'] != session.bucket ||
          _size(confirmed['size']) != length ||
          confirmed['folderUuid'] != folder ||
          (confirmed['plainName'] ?? confirmed['name']) != plainName ||
          (confirmed['type'] ?? confirmed['fileType'] ?? '') != type) {
        throw StateError(
          'Internxt could not confirm the uploaded file identity, name, destination and length.',
        );
      }
      session.checkCurrent();
      onProgress?.call(length, length);
    } finally {
      await spool.dispose();
    }
  }

  Future<http.Response> _put(
    InternxtTransferSession session,
    Uri uri,
    TransferSpool spool, {
    void Function(int, int)? onProgress,
  }) async {
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw StateError('Internxt returned an insecure upload address.');
    }
    session.checkCurrent();
    final http.Response response;
    if (kIsWeb) {
      response = await uploadSpooledHttpBody(
        uri,
        spool,
        operation: 'Internxt encrypted upload',
        checkCurrent: session.checkCurrent,
        onProgress: onProgress,
      );
    } else {
      var sent = 0;
      Stream<List<int>> body() async* {
        await for (final bytes in validatedTransferParts(
          spool.openRead(),
          spool.length,
          chunkSize,
        )) {
          session.checkCurrent();
          sent += bytes.length;
          onProgress?.call(sent, spool.length);
          yield bytes;
        }
        session.checkCurrent();
      }

      final client = http.Client();
      try {
        response = await sendTransferRequest(
          client,
          TransferStreamRequest('PUT', uri, body(), spool.length)
            ..headers['content-type'] = 'application/octet-stream',
          operation: 'Internxt encrypted upload',
        );
        if (sent != spool.length) {
          throw StateError('Internxt did not consume the complete upload.');
        }
      } finally {
        client.close();
      }
    }
    session.checkCurrent();
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw StateError(
        'Internxt encrypted upload failed (${response.statusCode}).',
      );
    }
    return response;
  }
}

class _DigestSink implements Sink<crypto.Digest> {
  crypto.Digest? value;
  @override
  void add(crypto.Digest data) => value = data;
  @override
  void close() {}
}

/// SDK read-only path helpers retain their parsing/pagination behavior while
/// each response is bounded and every request checks its captured account.
class _MetadataClient extends http.BaseClient {
  _MetadataClient(this.checkCurrent);
  final void Function() checkCurrent;
  final _client = http.Client();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    checkCurrent();
    request.followRedirects = false;
    final response = await sendTransferRequest(
      _client,
      request,
      operation: 'Internxt path lookup',
    );
    checkCurrent();
    if (response.statusCode != 200) {
      throw sdk_api.ApiException(
        response.statusCode,
        'Internxt path lookup failed.',
      );
    }
    if (request.url.path.contains('/folders/content/')) {
      try {
        final value = jsonDecode(response.body) as Map;
        final kind = request.url.pathSegments.last;
        final items = value['result'] ?? value[kind];
        if (items is! List || items.any((item) => item is! Map)) {
          throw const FormatException('Invalid directory result.');
        }
      } catch (_) {
        // Never let an incomplete/error response become an empty directory.
        throw sdk_api.ApiException(
          422,
          'Internxt returned invalid directory metadata.',
        );
      }
    }
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      contentLength: response.bodyBytes.length,
    );
  }

  @override
  void close() => _client.close();
}
