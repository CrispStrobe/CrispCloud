import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crisp_cloud/services/s3_client_adapter.dart';
import 'package:crisp_cloud/services/s3_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';

void main() {
  late S3ClientAdapter adapter;
  late S3ConfigService configService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    configService = S3ConfigService(
      configPath: '/tmp/s3_resume_test_config',
      secureStorage: InMemorySecureStorage(),
    );
    adapter = S3ClientAdapter(config: configService);

    // Restore credentials so adapter is authenticated for method calls
    await configService.saveCredentials({
      'accessKey': 'TEST_ACCESS_KEY',
      'secretKey': 'TEST_SECRET_KEY',
      'endpoint': 'https://s3.example.com',
      'bucket': 'test-bucket',
      'region': 'us-east-1',
    });
    await adapter.restoreCredentials();
  });

  group('S3 Multipart Resume - SharedPreferences tracking', () {
    test('getInterruptedUploads returns empty list when no uploads tracked', () async {
      final uploads = await adapter.getInterruptedUploads();
      expect(uploads, isEmpty);
    });

    test('getInterruptedUploads returns tracked uploads from SharedPreferences', () async {
      // Simulate a previously persisted interrupted upload
      final prefs = await SharedPreferences.getInstance();
      final trackingData = jsonEncode({
        'uploadId': 'test-upload-id-123',
        'bucket': 'test-bucket',
        'key': 'photos/large-file.zip',
        'parts': [
          {'partNumber': 1, 'etag': '"etag1"'},
          {'partNumber': 2, 'etag': '"etag2"'},
        ],
      });
      await prefs.setString('crisp_s3_multipart_test-upload-id-123', trackingData);

      final uploads = await adapter.getInterruptedUploads();
      expect(uploads, hasLength(1));
      expect(uploads[0]['uploadId'], equals('test-upload-id-123'));
      expect(uploads[0]['key'], equals('photos/large-file.zip'));
      expect(uploads[0]['parts'], hasLength(2));
    });

    test('getInterruptedUploads returns multiple tracked uploads', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('crisp_s3_multipart_upload-1', jsonEncode({
        'uploadId': 'upload-1',
        'bucket': 'b1',
        'key': 'file1.zip',
        'parts': [{'partNumber': 1, 'etag': '"e1"'}],
      }));
      await prefs.setString('crisp_s3_multipart_upload-2', jsonEncode({
        'uploadId': 'upload-2',
        'bucket': 'b2',
        'key': 'file2.zip',
        'parts': [],
      }));

      final uploads = await adapter.getInterruptedUploads();
      expect(uploads, hasLength(2));
      final ids = uploads.map((u) => u['uploadId']).toSet();
      expect(ids, containsAll(['upload-1', 'upload-2']));
    });

    test('getInterruptedUploads ignores non-multipart SharedPrefs keys', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('some_other_key', 'some_value');
      await prefs.setString('crisp_s3_multipart_upload-x', jsonEncode({
        'uploadId': 'upload-x',
        'bucket': 'b',
        'key': 'f.zip',
        'parts': [],
      }));

      final uploads = await adapter.getInterruptedUploads();
      expect(uploads, hasLength(1));
      expect(uploads[0]['uploadId'], equals('upload-x'));
    });

    test('getInterruptedUploads skips malformed JSON entries', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('crisp_s3_multipart_bad', 'not valid json {{{');
      await prefs.setString('crisp_s3_multipart_good', jsonEncode({
        'uploadId': 'good-id',
        'bucket': 'b',
        'key': 'ok.zip',
        'parts': [],
      }));

      final uploads = await adapter.getInterruptedUploads();
      expect(uploads, hasLength(1));
      expect(uploads[0]['uploadId'], equals('good-id'));
    });
  });

  group('S3 Multipart Resume - resumeMultipartUpload error handling', () {
    test('resumeMultipartUpload throws when no interrupted upload found', () async {
      expect(
        () => adapter.resumeMultipartUpload('/nonexistent/file.zip', [1, 2, 3]),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('No interrupted upload found'),
        )),
      );
    });
  });

  group('S3 Multipart Resume - ListParts XML parsing', () {
    test('ListParts XML pattern parses part elements correctly', () {
      const xml = '''
      <ListPartsResult>
        <Bucket>test-bucket</Bucket>
        <Key>photos/large.zip</Key>
        <UploadId>upload-abc</UploadId>
        <IsTruncated>false</IsTruncated>
        <Part>
          <PartNumber>1</PartNumber>
          <LastModified>2026-05-30T10:00:00.000Z</LastModified>
          <ETag>"abc111"</ETag>
          <Size>8388608</Size>
        </Part>
        <Part>
          <PartNumber>2</PartNumber>
          <LastModified>2026-05-30T10:01:00.000Z</LastModified>
          <ETag>"abc222"</ETag>
          <Size>8388608</Size>
        </Part>
        <Part>
          <PartNumber>3</PartNumber>
          <LastModified>2026-05-30T10:02:00.000Z</LastModified>
          <ETag>"abc333"</ETag>
          <Size>5242880</Size>
        </Part>
      </ListPartsResult>
      ''';

      final partMatches = RegExp(
        r'<Part>\s*'
        r'<PartNumber>(\d+)</PartNumber>\s*'
        r'(?:<LastModified>[^<]*</LastModified>\s*)?'
        r'<ETag>([^<]+)</ETag>\s*'
        r'(?:<Size>[^<]*</Size>\s*)?'
        r'</Part>',
      ).allMatches(xml);

      final parts = partMatches.toList();
      expect(parts, hasLength(3));
      expect(parts[0].group(1), equals('1'));
      expect(parts[0].group(2), equals('"abc111"'));
      expect(parts[1].group(1), equals('2'));
      expect(parts[1].group(2), equals('"abc222"'));
      expect(parts[2].group(1), equals('3'));
      expect(parts[2].group(2), equals('"abc333"'));
    });

    test('ListParts XML pattern handles truncated response', () {
      const xml = '''
      <ListPartsResult>
        <IsTruncated>true</IsTruncated>
        <NextPartNumberMarker>5</NextPartNumberMarker>
        <Part>
          <PartNumber>1</PartNumber>
          <ETag>"e1"</ETag>
        </Part>
      </ListPartsResult>
      ''';

      final isTruncated =
          RegExp(r'<IsTruncated>true</IsTruncated>').hasMatch(xml);
      expect(isTruncated, isTrue);

      final markerMatch = RegExp(
        r'<NextPartNumberMarker>(\d+)</NextPartNumberMarker>',
      ).firstMatch(xml);
      expect(markerMatch, isNotNull);
      expect(markerMatch!.group(1), equals('5'));
    });

    test('ListParts XML pattern handles non-truncated response', () {
      const xml = '''
      <ListPartsResult>
        <IsTruncated>false</IsTruncated>
      </ListPartsResult>
      ''';

      final isTruncated =
          RegExp(r'<IsTruncated>true</IsTruncated>').hasMatch(xml);
      expect(isTruncated, isFalse);
    });
  });

  group('S3 Multipart Resume - capability flags', () {
    test('supportsMultipart is true', () {
      expect(adapter.supportsMultipart, isTrue);
    });

    test('supportsStreaming is true', () {
      expect(adapter.supportsStreaming, isTrue);
    });
  });

  group('S3 Multipart Resume - persistInterruptedUploads', () {
    test('persistInterruptedUploads does not throw when no active uploads', () async {
      // Should be a no-op, not throw
      await adapter.persistInterruptedUploads();
    });
  });

  group('S3 Multipart Resume - multipart threshold constants', () {
    test('multipart threshold is 5MB', () {
      expect(S3ClientAdapter.multipartThreshold, equals(5 * 1024 * 1024));
    });

    test('default part size is 8MB', () {
      expect(S3ClientAdapter.defaultPartSize, equals(8 * 1024 * 1024));
    });
  });
}
