import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/services/s3_client_adapter.dart';
import 'package:crisp_cloud/services/s3_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// An HTTP boundary fixture for the actual signed S3 adapter. Listing, HEAD,
/// full downloads and exact conditional ranges share one mutable revision.
class VerifiedS3Fixture {
  VerifiedS3Fixture(this.bytes);

  Uint8List bytes;
  String version = '"revision-1"';
  String? listingVersion;
  bool includeETag = true;
  String? badResponse;
  int heads = 0;
  int fullReads = 0;
  int requestedBytes = 0;
  final ranges = <String>[];
  final validators = <String?>[];
  Future<void> Function()? beforeHead;
  Future<void> Function()? afterRange;
  Stream<List<int>> Function(Uint8List)? responseBody;

  void resetRequests() {
    heads = 0;
    fullReads = 0;
    requestedBytes = 0;
    ranges.clear();
    validators.clear();
  }

  http.Client client() => MockClient.streaming((request, requestBody) async {
    await requestBody.drain<void>();
    if (request.method == 'HEAD') {
      heads++;
      await beforeHead?.call();
      return http.StreamedResponse(
        const Stream.empty(),
        200,
        headers: {'etag': version, 'content-length': '${bytes.length}'},
      );
    }
    if (request.method != 'GET') {
      throw StateError('Unexpected S3 mutation: ${request.method}');
    }
    if (request.url.queryParameters['list-type'] == '2') {
      final xml =
          '''<?xml version="1.0" encoding="UTF-8"?>
<ListBucketResult><IsTruncated>false</IsTruncated><Contents>
<Key>image.bin</Key><Size>${bytes.length}</Size>
<LastModified>2026-11-14T00:00:00Z</LastModified>
${includeETag ? '<ETag>${const HtmlEscape().convert(listingVersion ?? version)}</ETag>' : ''}
</Contents></ListBucketResult>''';
      final body = utf8.encode(xml);
      return http.StreamedResponse(
        Stream.value(body),
        200,
        headers: {
          'content-type': 'application/xml',
          'content-length': '${body.length}',
        },
      );
    }
    final range = request.headers['range'];
    if (range == null) {
      fullReads++;
      requestedBytes += bytes.length;
      return http.StreamedResponse(
        responseBody?.call(Uint8List.fromList(bytes)) ??
            Stream.value(Uint8List.fromList(bytes)),
        200,
        headers: {'etag': version, 'content-length': '${bytes.length}'},
      );
    }
    ranges.add(range);
    validators.add(request.headers['if-match']);
    if (request.headers['if-match'] != version) {
      return http.StreamedResponse(const Stream.empty(), 412);
    }
    final parts = RegExp(r'^bytes=(\d+)-(\d+)$').firstMatch(range);
    if (parts == null) throw StateError('Invalid range request: $range');
    final start = int.parse(parts.group(1)!);
    final end = int.parse(parts.group(2)!);
    var body = Uint8List.fromList(bytes.sublist(start, end + 1));
    final responseVersion = badResponse == 'version'
        ? '"wrong-revision"'
        : version;
    if (badResponse == 'short') body = body.sublist(0, body.length - 1);
    if (badResponse == 'digest' && body.isNotEmpty) body[0] ^= 255;
    requestedBytes += body.length;
    await afterRange?.call();
    return http.StreamedResponse(
      responseBody?.call(body) ?? Stream.value(body),
      badResponse == 'ignored' ? 200 : 206,
      headers: {
        'etag': responseVersion,
        'content-range': 'bytes $start-$end/${bytes.length}',
        'content-length': '${body.length}',
        if (badResponse == 'encoding') 'content-encoding': 'gzip',
      },
    );
  });
}

Future<S3ClientAdapter> verifiedS3Adapter({
  required String cacheDirectory,
  String account = 'verified-copy-access',
  String endpoint = 'https://s3.amazonaws.com',
}) async {
  final config = S3ConfigService(
    configPath: '',
    secureStorage: InMemorySecureStorage(),
  );
  await config.saveCredentials({
    'accessKey': account,
    'secretKey': 'fixture-secret',
    'endpoint': endpoint,
    'bucket': 'bucket',
    'region': 'us-east-1',
  });
  final adapter = S3ClientAdapter(
    config: config,
    deltaCacheDirectory: cacheDirectory,
  );
  if (!await adapter.restoreCredentials()) {
    throw StateError('Fixture credentials could not be restored.');
  }
  // Explicit reviewed selection must not depend on the inactive old toggle.
  if (adapter.deltaSyncEnabled) throw StateError('Legacy delta toggle is on.');
  return adapter;
}
