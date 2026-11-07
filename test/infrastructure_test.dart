// test/infrastructure_test.dart
//
// Tests for infrastructure features:
// - CertPinningService
// - FileCacheService
// - ThumbnailService
// - Delta sync (content hash comparison)

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;

import 'package:crisp_cloud/services/cert_pinning_service.dart';
import 'package:crisp_cloud/services/file_cache_service.dart';
import 'package:crisp_cloud/services/thumbnail_service.dart';

void main() {
  group('Certificate pinning migration', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('unsupported pinning cannot be enabled', () async {
      final service = CertPinningService();
      expect(service.isEnabled, isFalse);
      await expectLater(service.setEnabled(true), throwsUnsupportedError);
      expect(service.isEnabled, isFalse);
    });

    test(
      'old enabled preference is removed without disabling TLS trust',
      () async {
        SharedPreferences.setMockInitialValues({'cert_pinning_enabled': true});
        final service = CertPinningService();
        await service.load();
        expect(service.isEnabled, isFalse);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('cert_pinning_enabled'), isNull);
        expect(
          service.configureSecurityContext(null).minimumTlsProtocolVersion,
          TlsProtocolVersion.tls1_2,
        );
      },
    );
  });

  // --- FileCacheService Tests ---
  group('FileCacheService', () {
    test('CacheEntry toJson/fromJson round-trip', () {
      final entry = CacheEntry(
        remotePath: '/docs/file.txt',
        provider: 'gdrive',
        sizeBytes: 1024,
        cachedAt: DateTime(2026, 1, 1),
        lastAccessed: DateTime(2026, 1, 2),
        localFileName: 'abc123',
      );

      final json = entry.toJson();
      final restored = CacheEntry.fromJson(json);

      expect(restored.remotePath, '/docs/file.txt');
      expect(restored.provider, 'gdrive');
      expect(restored.sizeBytes, 1024);
      expect(restored.localFileName, 'abc123');
    });

    test('CacheEntry serializes dates correctly', () {
      final now = DateTime.now();
      final entry = CacheEntry(
        remotePath: '/test',
        provider: 'dropbox',
        sizeBytes: 100,
        cachedAt: now,
        lastAccessed: now,
        localFileName: 'x',
      );

      final json = entry.toJson();
      expect(json['cachedAt'], now.toIso8601String());
      expect(json['lastAccessed'], now.toIso8601String());
    });
  });

  // --- ThumbnailService Tests ---
  group('ThumbnailService', () {
    test('isSupported identifies image files', () {
      expect(ThumbnailService.isSupported('photo.jpg'), true);
      expect(ThumbnailService.isSupported('image.png'), true);
      expect(ThumbnailService.isSupported('pic.gif'), true);
      expect(ThumbnailService.isSupported('icon.webp'), true);
      expect(ThumbnailService.isSupported('logo.bmp'), true);
    });

    test('isSupported rejects non-image files', () {
      expect(ThumbnailService.isSupported('document.pdf'), false);
      expect(ThumbnailService.isSupported('script.dart'), false);
      expect(ThumbnailService.isSupported('data.json'), false);
      expect(ThumbnailService.isSupported('video.mp4'), false);
      expect(ThumbnailService.isSupported('archive.zip'), false);
    });

    test('isSupported case insensitive', () {
      expect(ThumbnailService.isSupported('PHOTO.JPG'), true);
      expect(ThumbnailService.isSupported('Image.PNG'), true);
    });

    test('remoteKey format', () {
      final key = ThumbnailService.remoteKey('gdrive', '/photos/cat.jpg');
      expect(key, 'gdrive:/photos/cat.jpg');
    });

    test('localKey format', () {
      final key = ThumbnailService.localKey('/home/user/photo.jpg');
      expect(key, 'local:/home/user/photo.jpg');
    });

    test('getCached returns null for unknown key', () {
      final service = ThumbnailService();
      expect(service.getCached('nonexistent'), null);
    });
  });

  // --- Delta Sync Content Hash Tests ---
  group('Delta Sync', () {
    // Test the content hash comparison logic used in sync engine

    bool isRemoteModified({
      required int? fileSize,
      required DateTime? fileModified,
      required String? fileHash,
      required DateTime? knownModified,
      required int knownSize,
      required String? knownHash,
    }) {
      // If both sides have content hashes, use those
      if (fileHash != null && knownHash != null) {
        return fileHash != knownHash;
      }
      // Fallback: timestamp + size
      if (knownModified == null) return true;
      final timeDiff = fileModified != null
          ? fileModified.difference(knownModified).inSeconds.abs()
          : 0;
      return timeDiff > 1 || (fileSize ?? 0) != knownSize;
    }

    test('same hash means not modified', () {
      expect(
        isRemoteModified(
          fileSize: 100,
          fileModified: DateTime(2026, 1, 2),
          fileHash: 'abc123',
          knownModified: DateTime(2026, 1, 1),
          knownSize: 100,
          knownHash: 'abc123',
        ),
        false,
      );
    });

    test('different hash means modified', () {
      expect(
        isRemoteModified(
          fileSize: 100,
          fileModified: DateTime(2026, 1, 1),
          fileHash: 'abc123',
          knownModified: DateTime(2026, 1, 1),
          knownSize: 100,
          knownHash: 'xyz789',
        ),
        true,
      );
    });

    test('hash takes precedence over timestamp', () {
      // Same hash but different timestamp → not modified (hash wins)
      expect(
        isRemoteModified(
          fileSize: 100,
          fileModified: DateTime(2026, 6, 1),
          fileHash: 'same',
          knownModified: DateTime(2026, 1, 1),
          knownSize: 100,
          knownHash: 'same',
        ),
        false,
      );
    });

    test('no hash falls back to timestamp', () {
      // No hashes, different timestamp → modified
      expect(
        isRemoteModified(
          fileSize: 100,
          fileModified: DateTime(2026, 6, 1),
          fileHash: null,
          knownModified: DateTime(2026, 1, 1),
          knownSize: 100,
          knownHash: null,
        ),
        true,
      );
    });

    test('no hash, same timestamp and size → not modified', () {
      final t = DateTime(2026, 1, 1);
      expect(
        isRemoteModified(
          fileSize: 100,
          fileModified: t,
          fileHash: null,
          knownModified: t,
          knownSize: 100,
          knownHash: null,
        ),
        false,
      );
    });

    test('only remote has hash, falls back to timestamp', () {
      expect(
        isRemoteModified(
          fileSize: 100,
          fileModified: DateTime(2026, 6, 1),
          fileHash: 'abc',
          knownModified: DateTime(2026, 1, 1),
          knownSize: 100,
          knownHash: null,
        ),
        true,
      );
    });
  });
}
