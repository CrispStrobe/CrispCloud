import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../transfer_bandwidth.dart';
import 'transfer_bandwidth_http.dart';

/// Upload responses contain metadata, never file contents. Bound that metadata
/// too, and keep authenticated session URLs out of user-facing error records.
Future<http.Response> sendTransferRequest(
  http.Client client,
  http.BaseRequest request, {
  required String operation,
}) async {
  final context = TransferBandwidthContext.current;
  try {
    final response = await client.send(
      bindHttpTransferBandwidth(request, context),
    );
    final bytes = BytesBuilder(copy: false);
    var received = 0;
    // Reject an oversized raw chunk before waiting for quota; a small limit
    // must not turn the metadata bound into a long-running download.
    final bounded = response.stream.map((chunk) {
      received += chunk.length;
      if (received > 256 * 1024) {
        throw StateError('$operation returned oversized metadata.');
      }
      return chunk;
    });
    final input = context == null
        ? bounded
        : context.bind(bounded, direction: TransferBandwidthDirection.download);
    await for (final chunk in input) {
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
  bool followRedirects = true,
  bool allowHttp = false,
  void Function()? checkCurrent,
  int? Function(Map<String, String>)? responseLength,
  void Function(int, int)? onProgress,
}) {
  // This outer method is deliberately synchronous: an async* body first runs
  // in the subscribing zone, which may belong to a different operation.
  final context = TransferBandwidthContext.current;
  return _streamHttpDownload(
    uri,
    operation: operation,
    headers: Map<String, String>.unmodifiable(headers),
    expectedLength: expectedLength,
    followRedirects: followRedirects,
    allowHttp: allowHttp,
    checkCurrent: checkCurrent,
    responseLength: responseLength,
    onProgress: onProgress,
    context: context,
  );
}

Stream<List<int>> _streamHttpDownload(
  Uri uri, {
  required String operation,
  required Map<String, String> headers,
  required int? expectedLength,
  required bool followRedirects,
  required bool allowHttp,
  required void Function()? checkCurrent,
  required int? Function(Map<String, String>)? responseLength,
  required void Function(int, int)? onProgress,
  required TransferBandwidthContext? context,
}) async* {
  if ((uri.scheme != 'https' && !(allowHttp && uri.scheme == 'http')) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    throw StateError('$operation returned an invalid download address.');
  }
  final client = http.Client();
  try {
    checkCurrent?.call();
    final request = http.Request('GET', uri)
      ..headers.addAll(headers)
      ..followRedirects = followRedirects;
    final response = await client.send(
      bindHttpTransferBandwidth(request, context),
    );
    checkCurrent?.call();
    if (response.statusCode != 200) {
      throw StateError('$operation failed (${response.statusCode}).');
    }
    final length =
        expectedLength ??
        responseLength?.call(response.headers) ??
        response.contentLength;
    var received = 0;
    final measured = response.stream.map((chunk) {
      checkCurrent?.call();
      received += chunk.length;
      if (length != null && received > length) {
        throw StateError('$operation exceeded its expected length.');
      }
      return chunk;
    });
    final input = context == null
        ? measured
        : context.bind(
            measured,
            direction: TransferBandwidthDirection.download,
          );
    var delivered = 0;
    await for (final chunk in input) {
      checkCurrent?.call();
      delivered += chunk.length;
      onProgress?.call(delivered, length ?? delivered);
      yield chunk;
    }
    checkCurrent?.call();
    if (length != null && received != length) {
      throw StateError('$operation ended before its expected length.');
    }
  } on http.ClientException {
    throw StateError('$operation connection was interrupted.');
  } finally {
    client.close();
  }
}
