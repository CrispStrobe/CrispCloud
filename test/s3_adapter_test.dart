import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crisp_cloud/services/s3_client_adapter.dart';
import 'package:crisp_cloud/services/s3_config_service.dart';
import 'package:crisp_cloud/services/delta_sync_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';

void main() {
  late S3ClientAdapter adapter;
  late S3ConfigService configService;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    configService = S3ConfigService(
      configPath: '/tmp/s3_test_config',
      secureStorage: InMemorySecureStorage(),
    );
    adapter = S3ClientAdapter(config: configService);
  });

  group('S3ClientAdapter - basic properties', () {
    test('providerName returns S3', () {
      expect(adapter.providerName, equals('S3'));
    });

    test('rootPath returns /', () {
      expect(adapter.rootPath, equals('/'));
    });

    test('isAuthenticated returns false initially', () {
      expect(adapter.isAuthenticated, isFalse);
    });

    test('userId returns null when not authenticated', () {
      expect(adapter.userId, isNull);
    });

    test('bucketId returns null when not authenticated', () {
      expect(adapter.bucketId, isNull);
    });

    test('is2faNeeded always returns false', () async {
      final result = await adapter.is2faNeeded('test@example.com');
      expect(result, isFalse);
    });
  });

  group('S3ClientAdapter - capability flags', () {
    test('supportsMultipart is true', () {
      expect(adapter.supportsMultipart, isTrue);
    });

    test('supportsStreaming is true', () {
      expect(adapter.supportsStreaming, isTrue);
    });

    test('supportsVersioning is false (default)', () {
      expect(adapter.supportsVersioning, isFalse);
    });

    test('supportsSharing is false (default)', () {
      expect(adapter.supportsSharing, isFalse);
    });

    test('supportsSearch is false (default)', () {
      expect(adapter.supportsSearch, isFalse);
    });
  });

  group('S3ClientAdapter - login identity parsing', () {
    test('parses standard AWS format', () {
      final result = S3ClientAdapter.parseLoginIdentity(
        'AKIAIOSFODNN7@https://s3.amazonaws.com/my-bucket?region=us-east-1',
      );

      expect(result['accessKey'], equals('AKIAIOSFODNN7'));
      expect(result['endpoint'], equals('https://s3.amazonaws.com'));
      expect(result['bucket'], equals('my-bucket'));
      expect(result['region'], equals('us-east-1'));
    });

    test('parses MinIO format', () {
      final result = S3ClientAdapter.parseLoginIdentity(
        'minioadmin@http://localhost:9000/my-bucket?region=us-east-1',
      );

      expect(result['accessKey'], equals('minioadmin'));
      expect(result['endpoint'], equals('http://localhost:9000'));
      expect(result['bucket'], equals('my-bucket'));
      expect(result['region'], equals('us-east-1'));
    });

    test('parses format without region (defaults later)', () {
      final result = S3ClientAdapter.parseLoginIdentity(
        'AKIAKEY@https://s3.amazonaws.com/bucket-name',
      );

      expect(result['accessKey'], equals('AKIAKEY'));
      expect(result['endpoint'], equals('https://s3.amazonaws.com'));
      expect(result['bucket'], equals('bucket-name'));
      expect(result['region'], isNull);
    });

    test('parses Backblaze B2 endpoint', () {
      final result = S3ClientAdapter.parseLoginIdentity(
        'keyId@https://s3.us-west-002.backblazeb2.com/my-b2-bucket?region=us-west-002',
      );

      expect(result['accessKey'], equals('keyId'));
      expect(result['endpoint'], equals('https://s3.us-west-002.backblazeb2.com'));
      expect(result['bucket'], equals('my-b2-bucket'));
      expect(result['region'], equals('us-west-002'));
    });

    test('returns nulls for invalid format (no @)', () {
      final result = S3ClientAdapter.parseLoginIdentity('no-at-sign-here');
      expect(result['accessKey'], isNull);
    });

    test('parses R2 endpoint', () {
      final result = S3ClientAdapter.parseLoginIdentity(
        'access123@https://account.r2.cloudflarestorage.com/my-r2-bucket?region=auto',
      );

      expect(result['accessKey'], equals('access123'));
      expect(result['endpoint'], equals('https://account.r2.cloudflarestorage.com'));
      expect(result['bucket'], equals('my-r2-bucket'));
      expect(result['region'], equals('auto'));
    });
  });

  group('S3ClientAdapter - SigV4 signing', () {
    test('signRequest produces correct Authorization header format', () {
      // Set up adapter with known credentials for deterministic signing
      final testAdapter = S3ClientAdapter(config: configService);
      // We can't call login (needs network), but we can call signRequest directly

      final now = DateTime.utc(2026, 5, 29, 14, 30, 25);
      final uri = Uri.parse('https://my-bucket.s3.us-east-1.amazonaws.com/?list-type=2&max-keys=1');

      final headers = testAdapter.signRequest(
        method: 'GET',
        uri: uri,
        headers: {},
        payloadHash: sha256.convert([]).toString(),
        now: now,
      );

      // Verify the Authorization header has the correct format
      expect(headers['Authorization'], isNotNull);
      expect(headers['Authorization']!.startsWith('AWS4-HMAC-SHA256'), isTrue);
      expect(headers['Authorization']!.contains('Credential='), isTrue);
      expect(headers['Authorization']!.contains('SignedHeaders='), isTrue);
      expect(headers['Authorization']!.contains('Signature='), isTrue);

      // Verify x-amz-date is set correctly
      expect(headers['x-amz-date'], equals('20260529T143025Z'));

      // Verify x-amz-content-sha256 is set
      expect(headers['x-amz-content-sha256'], isNotNull);
      expect(headers['x-amz-content-sha256']!.length, equals(64)); // SHA-256 hex length
    });

    test('signRequest with payload produces different hash', () {
      final testAdapter = S3ClientAdapter(config: configService);
      final now = DateTime.utc(2026, 5, 29, 14, 30, 25);
      final uri = Uri.parse('https://my-bucket.s3.us-east-1.amazonaws.com/test.txt');

      final emptyHash = sha256.convert([]).toString();
      final dataHash = sha256.convert(utf8.encode('Hello World')).toString();

      final headersEmpty = testAdapter.signRequest(
        method: 'PUT',
        uri: uri,
        headers: {'content-type': 'application/octet-stream'},
        payloadHash: emptyHash,
        now: now,
      );

      final headersData = testAdapter.signRequest(
        method: 'PUT',
        uri: uri,
        headers: {'content-type': 'application/octet-stream'},
        payloadHash: dataHash,
        now: now,
      );

      // Different payloads should produce different signatures
      expect(headersEmpty['Authorization'], isNot(equals(headersData['Authorization'])));
      expect(headersEmpty['x-amz-content-sha256'], isNot(equals(headersData['x-amz-content-sha256'])));
    });

    test('date formatting is correct', () {
      final testAdapter = S3ClientAdapter(config: configService);
      final now = DateTime.utc(2026, 1, 5, 3, 7, 9);
      final uri = Uri.parse('https://bucket.s3.amazonaws.com/key');

      final headers = testAdapter.signRequest(
        method: 'GET',
        uri: uri,
        headers: {},
        payloadHash: sha256.convert([]).toString(),
        now: now,
      );

      expect(headers['x-amz-date'], equals('20260105T030709Z'));
    });
  });

  group('S3ClientAdapter - XML parsing via listPath patterns', () {
    // We can't call listPath directly (needs network), but we can verify
    // the regex patterns that the adapter uses by testing them in isolation.

    test('parses CommonPrefixes (folders) from S3 XML', () {
      const xml = '''
      <?xml version="1.0" encoding="UTF-8"?>
      <ListBucketResult>
        <Name>my-bucket</Name>
        <Prefix>photos/</Prefix>
        <IsTruncated>false</IsTruncated>
        <CommonPrefixes><Prefix>photos/vacation/</Prefix></CommonPrefixes>
        <CommonPrefixes><Prefix>photos/work/</Prefix></CommonPrefixes>
      </ListBucketResult>
      ''';

      final matches = RegExp(
        r'<CommonPrefixes>\s*<Prefix>([^<]+)</Prefix>\s*</CommonPrefixes>',
      ).allMatches(xml);

      final prefixes = matches.map((m) => m.group(1)!).toList();
      expect(prefixes, hasLength(2));
      expect(prefixes[0], equals('photos/vacation/'));
      expect(prefixes[1], equals('photos/work/'));
    });

    test('parses Contents (files) from S3 XML', () {
      const xml = '''
      <?xml version="1.0" encoding="UTF-8"?>
      <ListBucketResult>
        <Contents>
          <Key>photos/cat.jpg</Key>
          <LastModified>2026-05-29T10:30:00.000Z</LastModified>
          <ETag>"abc123"</ETag>
          <Size>1048576</Size>
        </Contents>
        <Contents>
          <Key>photos/dog.png</Key>
          <LastModified>2026-05-28T08:15:00.000Z</LastModified>
          <ETag>"def456"</ETag>
          <Size>2097152</Size>
        </Contents>
      </ListBucketResult>
      ''';

      final matches = RegExp(
        r'<Contents>\s*'
        r'<Key>([^<]+)</Key>\s*'
        r'<LastModified>([^<]+)</LastModified>\s*'
        r'(?:<ETag>[^<]*</ETag>\s*)?'
        r'<Size>([^<]+)</Size>',
      ).allMatches(xml);

      final items = matches.toList();
      expect(items, hasLength(2));

      expect(items[0].group(1), equals('photos/cat.jpg'));
      expect(items[0].group(2), equals('2026-05-29T10:30:00.000Z'));
      expect(items[0].group(3), equals('1048576'));

      expect(items[1].group(1), equals('photos/dog.png'));
      expect(items[1].group(3), equals('2097152'));
    });

    test('parses IsTruncated flag', () {
      const xmlTruncated = '<IsTruncated>true</IsTruncated>';
      const xmlNotTruncated = '<IsTruncated>false</IsTruncated>';

      expect(
        RegExp(r'<IsTruncated>true</IsTruncated>').hasMatch(xmlTruncated),
        isTrue,
      );
      expect(
        RegExp(r'<IsTruncated>true</IsTruncated>').hasMatch(xmlNotTruncated),
        isFalse,
      );
    });

    test('parses NextContinuationToken', () {
      const xml = '<NextContinuationToken>abc123token456</NextContinuationToken>';

      final match = RegExp(r'<NextContinuationToken>([^<]+)</NextContinuationToken>').firstMatch(xml);
      expect(match, isNotNull);
      expect(match!.group(1), equals('abc123token456'));
    });
  });

  group('S3ClientAdapter - logout', () {
    test('logout clears authentication state', () async {
      // Manually set state via restoreCredentials after saving
      await configService.saveCredentials({
        'accessKey': 'AKIAIOSFODNN7EXAMPLE',
        'secretKey': 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
        'endpoint': 'https://s3.amazonaws.com',
        'bucket': 'test-bucket',
        'region': 'us-east-1',
      });

      final restored = await adapter.restoreCredentials();
      expect(restored, isTrue);
      expect(adapter.isAuthenticated, isTrue);
      expect(adapter.userId, equals('AKIAIOSFODNN7EXAMPLE'));
      expect(adapter.bucketId, equals('test-bucket'));

      await adapter.logout();
      expect(adapter.isAuthenticated, isFalse);
      expect(adapter.userId, isNull);
      expect(adapter.bucketId, isNull);
    });
  });

  group('S3ClientAdapter - restoreCredentials', () {
    test('returns false when no credentials saved', () async {
      final result = await adapter.restoreCredentials();
      expect(result, isFalse);
      expect(adapter.isAuthenticated, isFalse);
    });

    test('returns true and sets state when credentials exist', () async {
      await configService.saveCredentials({
        'accessKey': 'TEST_ACCESS_KEY',
        'secretKey': 'TEST_SECRET_KEY',
        'endpoint': 'https://minio.example.com',
        'bucket': 'data-bucket',
        'region': 'us-east-1',
      });

      final result = await adapter.restoreCredentials();
      expect(result, isTrue);
      expect(adapter.isAuthenticated, isTrue);
      expect(adapter.userId, equals('TEST_ACCESS_KEY'));
      expect(adapter.bucketId, equals('data-bucket'));
    });
  });

  group('S3ClientAdapter - error handling', () {
    test('throws when calling operations without authentication', () {
      expect(
        () => adapter.listPath('/'),
        throwsA(isA<Exception>()),
      );

      expect(
        () => adapter.uploadFile([1, 2, 3], 'test.txt', '/'),
        throwsA(isA<Exception>()),
      );

      expect(
        () => adapter.downloadFileBytes('/test.txt'),
        throwsA(isA<Exception>()),
      );

      expect(
        () => adapter.deletePath('/test.txt'),
        throwsA(isA<Exception>()),
      );

      expect(
        () => adapter.createFolderPath('/test-folder'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('S3ClientAdapter - presigned URLs', () {
    test('generatePresignedUrl throws when not authenticated', () {
      expect(
        () => adapter.generatePresignedUrl('/test.txt'),
        throwsA(isA<Exception>()),
      );
    });

    test('generatePresignedUrl produces valid URL when authenticated', () async {
      await configService.saveCredentials({
        'accessKey': 'AKIAIOSFODNN7EXAMPLE',
        'secretKey': 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
        'endpoint': 'https://s3.amazonaws.com',
        'bucket': 'test-bucket',
        'region': 'us-east-1',
      });
      await adapter.restoreCredentials();

      final url = adapter.generatePresignedUrl('/photos/cat.jpg');
      final parsed = Uri.parse(url);

      expect(parsed.queryParameters['X-Amz-Algorithm'], equals('AWS4-HMAC-SHA256'));
      expect(parsed.queryParameters['X-Amz-Credential'], contains('AKIAIOSFODNN7EXAMPLE'));
      expect(parsed.queryParameters['X-Amz-Expires'], equals('3600'));
      expect(parsed.queryParameters['X-Amz-Signature'], isNotNull);
      expect(parsed.queryParameters['X-Amz-Signature']!.length, equals(64));
      expect(parsed.queryParameters['X-Amz-SignedHeaders'], equals('host'));
    });

    test('generatePresignedUrl respects custom expiration', () async {
      await configService.saveCredentials({
        'accessKey': 'AKIAIOSFODNN7EXAMPLE',
        'secretKey': 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
        'endpoint': 'https://s3.amazonaws.com',
        'bucket': 'test-bucket',
        'region': 'us-east-1',
      });
      await adapter.restoreCredentials();

      final url = adapter.generatePresignedUrl(
        '/photos/cat.jpg',
        expires: const Duration(minutes: 30),
      );
      final parsed = Uri.parse(url);
      expect(parsed.queryParameters['X-Amz-Expires'], equals('1800'));
    });

    test('generatePresignedUploadUrl produces PUT-signed URL', () async {
      await configService.saveCredentials({
        'accessKey': 'AKIAIOSFODNN7EXAMPLE',
        'secretKey': 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
        'endpoint': 'https://s3.amazonaws.com',
        'bucket': 'test-bucket',
        'region': 'us-east-1',
      });
      await adapter.restoreCredentials();

      final url = adapter.generatePresignedUploadUrl('/uploads/new-file.txt');
      final parsed = Uri.parse(url);

      expect(parsed.queryParameters['X-Amz-Algorithm'], equals('AWS4-HMAC-SHA256'));
      expect(parsed.queryParameters['X-Amz-Signature'], isNotNull);
      // PUT and GET URLs should differ because canonical request includes method
      final getUrl = adapter.generatePresignedUrl('/uploads/new-file.txt');
      expect(url, isNot(equals(getUrl)));
    });

    test('presigned URL uses virtual-hosted style for AWS', () async {
      await configService.saveCredentials({
        'accessKey': 'AKIAIOSFODNN7EXAMPLE',
        'secretKey': 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
        'endpoint': 'https://s3.us-east-1.amazonaws.com',
        'bucket': 'my-bucket',
        'region': 'us-east-1',
      });
      await adapter.restoreCredentials();

      final url = adapter.generatePresignedUrl('/test.txt');
      expect(url, contains('my-bucket.s3.us-east-1.amazonaws.com'));
    });

    test('presigned URL uses path style for non-AWS endpoints', () async {
      await configService.saveCredentials({
        'accessKey': 'minioadmin',
        'secretKey': 'minioadmin',
        'endpoint': 'http://localhost:9000',
        'bucket': 'test',
        'region': 'us-east-1',
      });
      await adapter.restoreCredentials();

      final url = adapter.generatePresignedUrl('/test.txt');
      expect(url, contains('localhost:9000/test/'));
    });
  });

  group('S3ClientAdapter - server-side encryption', () {
    test('default encryption is none', () {
      expect(adapter.encryption, equals(S3Encryption.none));
    });

    test('encryption can be set to SSE-S3', () {
      adapter.encryption = S3Encryption.sseS3;
      expect(adapter.encryption, equals(S3Encryption.sseS3));
    });

    test('encryption can be set to SSE-KMS with key ID', () {
      adapter.encryption = S3Encryption.sseKms;
      adapter.kmsKeyId = 'arn:aws:kms:us-east-1:123456:key/abcdef';
      expect(adapter.encryption, equals(S3Encryption.sseKms));
      expect(adapter.kmsKeyId, isNotNull);
    });

    test('restoreCredentials restores encryption settings', () async {
      await configService.saveCredentials({
        'accessKey': 'TEST_KEY',
        'secretKey': 'TEST_SECRET',
        'endpoint': 'https://s3.amazonaws.com',
        'bucket': 'test',
        'region': 'us-east-1',
        'encryption': 'sseKms',
        'kmsKeyId': 'arn:aws:kms:us-east-1:123:key/abc',
        'storageClass': 'STANDARD_IA',
      });

      final result = await adapter.restoreCredentials();
      expect(result, isTrue);
      expect(adapter.encryption, equals(S3Encryption.sseKms));
      expect(adapter.kmsKeyId, equals('arn:aws:kms:us-east-1:123:key/abc'));
      expect(adapter.storageClass, equals(S3StorageClass.standardIa));
    });
  });

  group('S3ClientAdapter - storage classes', () {
    test('default storage class is standard', () {
      expect(adapter.storageClass, equals(S3StorageClass.standard));
    });

    test('all storage classes have correct header values', () {
      expect(S3StorageClass.standard.headerValue, equals('STANDARD'));
      expect(S3StorageClass.standardIa.headerValue, equals('STANDARD_IA'));
      expect(S3StorageClass.onezoneIa.headerValue, equals('ONEZONE_IA'));
      expect(S3StorageClass.intelligentTiering.headerValue, equals('INTELLIGENT_TIERING'));
      expect(S3StorageClass.glacier.headerValue, equals('GLACIER'));
      expect(S3StorageClass.glacierIr.headerValue, equals('GLACIER_IR'));
      expect(S3StorageClass.deepArchive.headerValue, equals('DEEP_ARCHIVE'));
      expect(S3StorageClass.reducedRedundancy.headerValue, equals('REDUCED_REDUNDANCY'));
    });

    test('storage class display names are human-readable', () {
      expect(S3StorageClass.standard.displayName, equals('Standard'));
      expect(S3StorageClass.standardIa.displayName, equals('Standard-IA'));
      expect(S3StorageClass.glacier.displayName, equals('Glacier Flexible Retrieval'));
      expect(S3StorageClass.deepArchive.displayName, equals('Glacier Deep Archive'));
    });

    test('fromHeaderValue roundtrips all storage classes', () {
      for (final sc in S3StorageClass.values) {
        expect(S3StorageClassX.fromHeaderValue(sc.headerValue), equals(sc));
      }
    });

    test('fromHeaderValue handles unknown values gracefully', () {
      expect(S3StorageClassX.fromHeaderValue('UNKNOWN'), equals(S3StorageClass.standard));
    });

    test('supportsNativeShare is true for S3', () {
      expect(adapter.supportsNativeShare, isTrue);
    });
  });

  // ===========================================================================
  // Delta sync configuration
  // ===========================================================================
  group('S3ClientAdapter - delta sync config', () {
    test('deltaSyncEnabled is false by default', () {
      expect(adapter.deltaSyncEnabled, isFalse);
    });

    test('deltaSyncEnabled can be toggled', () {
      adapter.deltaSyncEnabled = true;
      expect(adapter.deltaSyncEnabled, isTrue);
      adapter.deltaSyncEnabled = false;
      expect(adapter.deltaSyncEnabled, isFalse);
    });
  });

  // ===========================================================================
  // Delta sync guards
  // ===========================================================================
  group('S3ClientAdapter - delta sync guards', () {
    test('deltaDownload returns null when deltaSyncEnabled is false', () async {
      expect(adapter.deltaSyncEnabled, isFalse);
      final result = await adapter.deltaDownload('/remote/file.bin', '/tmp/file.bin');
      expect(result, isNull);
    });

    test('deltaUpload returns null when deltaSyncEnabled is false', () async {
      expect(adapter.deltaSyncEnabled, isFalse);
      final result = await adapter.deltaUpload('/tmp/file.bin', '/remote/file.bin');
      expect(result, isNull);
    });

    test('deltaDownload throws when enabled but not authenticated', () async {
      adapter.deltaSyncEnabled = true;
      // Auth check fires before file existence check
      expect(
        () => adapter.deltaDownload('/remote/file.bin', '/tmp/nonexistent.bin'),
        throwsA(isA<Exception>().having(
          (e) => e.toString(), 'message', contains('authenticate'),
        )),
      );
    });

    test('deltaUpload throws when enabled but not authenticated', () async {
      adapter.deltaSyncEnabled = true;
      expect(
        () => adapter.deltaUpload('/tmp/any.bin', '/remote/any.bin'),
        throwsA(isA<Exception>().having(
          (e) => e.toString(), 'message', contains('authenticate'),
        )),
      );
    });

    test('downloadRange throws when not authenticated', () {
      expect(
        () => adapter.downloadRange('/file.bin', 0, 4096),
        throwsA(isA<Exception>().having(
          (e) => e.toString(), 'message', contains('authenticate'),
        )),
      );
    });

    test('getObjectETag throws when not authenticated', () {
      expect(
        () => adapter.getObjectETag('/file.bin'),
        throwsA(isA<Exception>().having(
          (e) => e.toString(), 'message', contains('authenticate'),
        )),
      );
    });
  });

  // ===========================================================================
  // Delta sync with DeltaSyncService
  // ===========================================================================
  group('S3ClientAdapter - delta sync with DeltaSyncService', () {
    late DeltaSyncService deltaSvc;
    const bs = 64 * 1024; // 64 KB for fast tests

    setUp(() {
      deltaSvc = DeltaSyncService();
    });

    test('block map format matches S3 Range GET expectations', () async {
      final dir = await Directory.systemTemp.createTemp('s3_delta_bm_');
      final file = File('${dir.path}/test.bin');
      final data = List<int>.generate(4 * bs, (i) => (i * 7) & 0xFF);
      await file.writeAsBytes(data);

      try {
        final map = await deltaSvc.computeBlockMap(file.path, blockSize: bs);
        expect(map.blockCount, equals(4));
        expect(map.blockSize, equals(bs));

        // Verify offsets align with Range GET byte ranges
        for (int i = 0; i < map.blockCount; i++) {
          final sig = map.signatures[i];
          expect(sig.offset, equals(i * bs));
          final rangeStart = sig.offset;
          final rangeEnd = sig.offset + sig.size - 1;
          // Range: bytes=rangeStart-rangeEnd is what S3 downloadRange would use
          expect(rangeEnd, greaterThan(rangeStart));
          expect(rangeEnd - rangeStart + 1, equals(sig.size));
        }
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('DeltaResult correctly identifies changed blocks for Range GET download', () async {
      final dir = await Directory.systemTemp.createTemp('s3_delta_cmp_');
      try {
        // "Remote" file (what S3 has)
        final remote = File('${dir.path}/remote.bin');
        await remote.writeAsBytes([
          ...List.filled(bs, 0x11),
          ...List.filled(bs, 0x22),
          ...List.filled(bs, 0x33),
        ]);

        // "Local" file (what we have, block 1 outdated)
        final local = File('${dir.path}/local.bin');
        await local.writeAsBytes([
          ...List.filled(bs, 0x11),
          ...List.filled(bs, 0xBB), // stale
          ...List.filled(bs, 0x33),
        ]);

        final remoteMap = await deltaSvc.computeBlockMap(remote.path, blockSize: bs);
        final localMap = await deltaSvc.computeBlockMap(local.path, blockSize: bs);

        // Compare remote vs local to find what to download
        final delta = deltaSvc.compareBlockMaps(remoteMap, localMap);
        expect(delta.changedBlocks, equals([1]));
        expect(delta.savingsPercent, closeTo(66.7, 0.1));
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('download plan produces correct Range GET parameters', () async {
      final dir = await Directory.systemTemp.createTemp('s3_delta_plan_');
      try {
        final remote = File('${dir.path}/remote.bin');
        await remote.writeAsBytes([
          ...List.filled(bs, 0xAA),
          ...List.filled(bs, 0xBB),
          ...List.filled(bs, 0xCC),
          ...List.filled(bs, 0xDD),
        ]);

        final local = File('${dir.path}/local.bin');
        await local.writeAsBytes([
          ...List.filled(bs, 0xAA),
          ...List.filled(bs, 0xFF), // stale
          ...List.filled(bs, 0xCC),
          ...List.filled(bs, 0xFE), // stale
        ]);

        final remoteMap = await deltaSvc.computeBlockMap(remote.path, blockSize: bs);
        final localMap = await deltaSvc.computeBlockMap(local.path, blockSize: bs);
        final delta = deltaSvc.compareBlockMaps(remoteMap, localMap);
        final plan = deltaSvc.createTransferPlan(
            delta, TransferDirection.download, remoteMap);

        // Verify download operations match expected Range GET offsets
        final downloadOps = plan.operations
            .where((op) => op.type == BlockOperationType.download)
            .toList();
        expect(downloadOps.length, equals(2));
        expect(downloadOps[0].blockIndex, equals(1));
        expect(downloadOps[0].offset, equals(1 * bs));
        expect(downloadOps[0].size, equals(bs));
        expect(downloadOps[1].blockIndex, equals(3));
        expect(downloadOps[1].offset, equals(3 * bs));
        expect(downloadOps[1].size, equals(bs));
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('applyDelta download simulates Range GET → local file patch', () async {
      final dir = await Directory.systemTemp.createTemp('s3_delta_apply_');
      try {
        // Simulate the remote file data on S3
        final remoteData = Uint8List.fromList([
          ...List.filled(bs, 0x11),
          ...List.filled(bs, 0x22),
          ...List.filled(bs, 0x33),
        ]);

        // Local file with stale block 1
        final localFile = File('${dir.path}/local.bin');
        await localFile.writeAsBytes([
          ...List.filled(bs, 0x11),
          ...List.filled(bs, 0xBB), // stale
          ...List.filled(bs, 0x33),
        ]);

        final remoteMap = await deltaSvc.computeBlockMap(
          (await (() async {
            final f = File('${dir.path}/remote.bin');
            await f.writeAsBytes(remoteData);
            return f.path;
          })()),
          blockSize: bs,
        );
        final localMap = await deltaSvc.computeBlockMap(localFile.path, blockSize: bs);

        final delta = deltaSvc.compareBlockMaps(remoteMap, localMap);
        final plan = deltaSvc.createTransferPlan(
            delta, TransferDirection.download, remoteMap);

        // Simulate S3 Range GET
        await deltaSvc.applyDelta(
          plan,
          localFile.path,
          remoteReadBlock: (blockIndex, offset, size) async {
            return remoteData.sublist(offset, offset + size);
          },
        );

        // Verify local file is now identical to remote
        final result = await localFile.readAsBytes();
        expect(result.sublist(0, bs), equals(List.filled(bs, 0x11)));
        expect(result.sublist(bs, 2 * bs), equals(List.filled(bs, 0x22)));
        expect(result.sublist(2 * bs, 3 * bs), equals(List.filled(bs, 0x33)));
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('S3 upload fallback: when blocks changed, full file upload is needed', () async {
      final dir = await Directory.systemTemp.createTemp('s3_delta_upload_');
      try {
        final orig = File('${dir.path}/orig.bin');
        await orig.writeAsBytes(List.filled(3 * bs, 0xAA));

        final mod = File('${dir.path}/mod.bin');
        await mod.writeAsBytes([
          ...List.filled(bs, 0xAA),
          ...List.filled(bs, 0xFF),
          ...List.filled(bs, 0xAA),
        ]);

        final origMap = await deltaSvc.computeBlockMap(orig.path, blockSize: bs);
        final modMap = await deltaSvc.computeBlockMap(mod.path, blockSize: bs);
        final delta = deltaSvc.compareBlockMaps(modMap, origMap);

        // S3 can detect changes but must upload entire file (no partial write)
        expect(delta.changedBlocks, equals([1]));
        expect(delta.changedBlocks.isNotEmpty, isTrue);
        // The S3 adapter would do a full uploadFile here, not block-level write
        // The savings come from *skipping* the upload when no changes detected
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('S3 upload skip: identical file produces empty changed list', () async {
      final dir = await Directory.systemTemp.createTemp('s3_delta_skip_');
      try {
        final file = File('${dir.path}/test.bin');
        await file.writeAsBytes(List.filled(4 * bs, 0x42));

        final map1 = await deltaSvc.computeBlockMap(file.path, blockSize: bs);
        final map2 = await deltaSvc.computeBlockMap(file.path, blockSize: bs);

        final delta = deltaSvc.compareBlockMaps(map1, map2);
        expect(delta.changedBlocks, isEmpty);
        // S3 adapter would skip the upload entirely in this case
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('block map cache path uses s3 provider namespace', () {
      final path1 = deltaSvc.blockMapCachePath('/cache', '/file.bin', 's3');
      final path2 = deltaSvc.blockMapCachePath('/cache', '/file.bin', 'pcloud');
      expect(path1, isNot(equals(path2)));
    });

    test('deltaDownload returns null when disabled, regardless of cache', () async {
      expect(adapter.deltaSyncEnabled, isFalse);
      // When disabled, returns null without hitting auth or cache
      final dir = await Directory.systemTemp.createTemp('s3_delta_nocache_');
      final file = File('${dir.path}/large.bin');
      await file.writeAsBytes(List.filled(11 * 1024 * 1024, 0x42)); // 11 MB
      try {
        final result = await adapter.deltaDownload('/remote/large.bin', file.path);
        expect(result, isNull);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('deltaUpload returns null when disabled, regardless of cache', () async {
      expect(adapter.deltaSyncEnabled, isFalse);
      final dir = await Directory.systemTemp.createTemp('s3_delta_nocache_up_');
      final file = File('${dir.path}/large.bin');
      await file.writeAsBytes(List.filled(11 * 1024 * 1024, 0x42)); // 11 MB
      try {
        final result = await adapter.deltaUpload(file.path, '/remote/large.bin');
        expect(result, isNull);
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });
}
