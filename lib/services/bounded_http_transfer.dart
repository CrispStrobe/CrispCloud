import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Upload responses contain metadata, never file contents. Bound that metadata
/// too, and keep authenticated session URLs out of user-facing error records.
Future<http.Response> sendTransferRequest(
  http.Client client,
  http.BaseRequest request, {
  required String operation,
}) async {
  try {
    final response = await client.send(request);
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > 256 * 1024) {
        throw StateError('$operation returned oversized metadata.');
      }
      bytes.add(chunk);
    }
    return http.Response.bytes(
      bytes.takeBytes(),
      response.statusCode,
      headers: response.headers,
    );
  } on http.ClientException {
    throw StateError('$operation connection failed; completion is unknown.');
  }
}

/// Yields download chunks without collecting a whole object in memory. Closing
/// or cancelling the consumer also closes the HTTP client and response stream.
Stream<List<int>> streamHttpDownload(
  Uri uri, {
  required String operation,
  Map<String, String> headers = const {},
  int? expectedLength,
  void Function(int, int)? onProgress,
}) async* {
  if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
    throw StateError('$operation returned an invalid download address.');
  }
  final client = http.Client();
  try {
    final request = http.Request('GET', uri)..headers.addAll(headers);
    final response = await client.send(request);
    if (response.statusCode != 200) {
      throw StateError('$operation failed (${response.statusCode}).');
    }
    final length = expectedLength ?? response.contentLength;
    var received = 0;
    await for (final chunk in response.stream) {
      received += chunk.length;
      if (length != null && received > length) {
        throw StateError('$operation exceeded its expected length.');
      }
      onProgress?.call(received, length ?? received);
      yield chunk;
    }
    if (length != null && received != length) {
      throw StateError('$operation ended before its expected length.');
    }
  } on http.ClientException {
    throw StateError('$operation connection was interrupted.');
  } finally {
    client.close();
  }
}
