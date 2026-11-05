import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hashes;
import 'package:filen_client/filen_client.dart';
import 'package:http/http.dart' as http;

import 'bounded_http_transfer.dart';
import 'bounded_transfer_stream.dart';

const _chunkBytes = 1024 * 1024;

class _DigestSink implements Sink<hashes.Digest> {
  hashes.Digest? value;
  @override
  void add(hashes.Digest data) => value = data;
  @override
  void close() {}
}

Future<Map<String, dynamic>> _post(
  FilenClient client,
  String token,
  String endpoint,
  Map<String, dynamic> body,
  void Function() check,
) async {
  check();
  final request = http.Request('POST', Uri.parse('${FilenApi.apiUrl}$endpoint'))
    ..followRedirects = false
    ..headers.addAll({
      'authorization': 'Bearer $token',
      'content-type': 'application/json',
    })
    ..body = jsonEncode(body);
  final response = await sendTransferRequest(
    client.api.client,
    request,
    operation: 'Filen transfer',
  );
  check();
  if (response.statusCode != 200) {
    throw StateError('Filen transfer failed (HTTP ${response.statusCode}).');
  }
  final data = jsonDecode(response.body);
  if (data is! Map<String, dynamic> || data['status'] != true) {
    throw StateError('Filen did not confirm the transfer request.');
  }
  return data;
}

/// Captures the encrypted metadata once and processes one 1 MiB chunk at a time.
/// The caller supplies a credential snapshot guard; each network step checks it.
Stream<List<int>> readFilenStream(
  FilenClient client,
  String uuid, {
  required String token,
  required List<String> masterKeys,
  required void Function() checkCurrent,
  void Function(int, int)? onProgress,
}) async* {
  final result = await _post(client, token, '/v3/file', {
    'uuid': uuid,
  }, checkCurrent);
  final data = result['data'];
  if (data is! Map || data['metadata'] is! String) {
    throw StateError('Filen file metadata is unavailable.');
  }
  final decoded = await client.crypto.tryDecrypt(
    data['metadata'] as String,
    masterKeys,
  );
  checkCurrent();
  final metadata = jsonDecode(decoded) as Map;
  final size = int.tryParse(metadata['size'].toString());
  final chunks = int.tryParse(data['chunks'].toString());
  if (size == null ||
      size < 0 ||
      chunks == null ||
      chunks != (size + _chunkBytes - 1) ~/ _chunkBytes ||
      (data['uuid'] != null && data['uuid'] != uuid)) {
    throw StateError('Filen file size or chunk identity is invalid.');
  }
  final key = client.crypto.decodeUniversalKey(metadata['key'] as String);
  final digest = _DigestSink();
  final hasher = hashes.sha512.startChunkedConversion(digest);
  var received = 0;
  try {
    for (var index = 0; index < chunks; index++) {
      checkCurrent();
      final uri = Uri(
        scheme: 'https',
        host: 'egest.filen.io',
        pathSegments: [
          data['region'] as String,
          data['bucket'] as String,
          uuid,
          '$index',
        ],
      );
      final response = await client.api.client.send(
        http.Request('GET', uri)..followRedirects = false,
      );
      try {
        checkCurrent();
      } catch (_) {
        await response.stream.listen((_) {}).cancel();
        rethrow;
      }
      if (response.statusCode != 200) {
        await response.stream.listen((_) {}).cancel();
        throw StateError(
          'Filen chunk download failed (HTTP ${response.statusCode}).',
        );
      }
      final encrypted = BytesBuilder(copy: false);
      await for (final chunk in response.stream) {
        checkCurrent();
        if (encrypted.length + chunk.length > _chunkBytes + 1024) {
          throw StateError('Filen returned an oversized encrypted chunk.');
        }
        encrypted.add(chunk);
      }
      final plain = await client.crypto.decryptData(encrypted.takeBytes(), key);
      checkCurrent();
      final expected = (size - received).clamp(0, _chunkBytes);
      if (plain.length != expected) {
        throw StateError(
          'Filen chunk length does not match the original file.',
        );
      }
      received += plain.length;
      hasher.add(plain);
      onProgress?.call(received, size);
      yield plain;
    }
  } finally {
    hasher.close();
  }
  checkCurrent();
  final expectedHash = metadata['hash']?.toString() ?? '';
  if (received != size ||
      (expectedHash.isNotEmpty &&
          digest.value.toString() != expectedHash.toLowerCase())) {
    throw StateError('Filen file verification failed.');
  }
}

Future<void> writeFilenStream(
  FilenClient client,
  Stream<List<int>> source,
  int length,
  String name,
  String parent, {
  required String token,
  required List<String> masterKeys,
  required String email,
  required void Function() checkCurrent,
  void Function(int, int)? onProgress,
}) async {
  if (length < 0) throw ArgumentError.value(length, 'length');
  final crypto = client.crypto;
  final uuid = crypto.uuid();
  final key = crypto.randomString(32);
  final keyBytes = Uint8List.fromList(utf8.encode(key));
  final uploadKey = crypto.randomString(32);
  final removeKey = crypto.randomString(32);
  final digest = _DigestSink();
  final hasher = hashes.sha512.startChunkedConversion(digest);
  var index = 0, sent = 0;
  try {
    await for (final plain in validatedTransferParts(
      source,
      length,
      _chunkBytes,
    )) {
      checkCurrent();
      hasher.add(plain);
      final encrypted = await crypto.encryptData(plain, keyBytes);
      checkCurrent();
      final uri = Uri.https('ingest.filen.io', '/v3/upload', {
        'uuid': uuid,
        'index': '${index++}',
        'parent': parent,
        'uploadKey': uploadKey,
        'hash': hashes.sha512.convert(encrypted).toString(),
      });
      final request = http.Request('POST', uri)
        ..followRedirects = false
        ..headers['authorization'] = 'Bearer $token'
        ..bodyBytes = encrypted;
      final response = await sendTransferRequest(
        client.api.client,
        request,
        operation: 'Filen chunk upload',
      );
      checkCurrent();
      if (response.statusCode != 200) {
        throw StateError(
          'Filen chunk upload failed (HTTP ${response.statusCode}).',
        );
      }
      if (response.body.isNotEmpty) {
        final acknowledgement = jsonDecode(response.body);
        if (acknowledgement is Map && acknowledgement['status'] == false) {
          throw StateError('Filen rejected an uploaded chunk.');
        }
      }
      sent += plain.length;
      onProgress?.call(sent, length);
    }
  } finally {
    hasher.close();
  }
  checkCurrent();
  final metadata = jsonEncode({
    'name': name,
    'size': length,
    'mime': 'application/octet-stream',
    'key': key,
    'hash': length == 0 ? '' : digest.value.toString(),
    'lastModified': DateTime.now().millisecondsSinceEpoch,
  });
  final fields = <String, dynamic>{
    'uuid': uuid,
    'name': await crypto.encryptMetadata002(name, key),
    'nameHashed': await crypto.hashFileName(name, masterKeys, email),
    'size': await crypto.encryptMetadata002('$length', key),
    'mime': await crypto.encryptMetadata002('application/octet-stream', key),
    'metadata': await crypto.encryptMetadata002(metadata, masterKeys.last),
    'version': 2,
    if (length == 0) 'parent': parent,
    if (length > 0) ...{
      'chunks': index,
      'rm': removeKey,
      'uploadKey': uploadKey,
    },
  };
  await _post(
    client,
    token,
    length == 0 ? '/v3/upload/empty' : '/v3/upload/done',
    fields,
    checkCurrent,
  );
  client.cache.invalidate(parent);
  onProgress?.call(length, length);
}
