// test/placeholder_service_test.dart
//
// Tests for PlaceholderService and PlaceholderMeta.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/services/placeholder_service.dart';
import 'package:crisp_cloud/services/sync_database.dart';

void main() {
  // --- PlaceholderMeta Tests ---
  group('PlaceholderMeta', () {
    test('toJson/fromJson round-trip', () {
      final meta = PlaceholderMeta(
        remotePath: '/docs/report.pdf',
        provider: 'gdrive',
        sizeBytes: 1048576,
        remoteModified: DateTime.utc(2026, 5, 30, 12, 0),
        contentHash: 'abc123',
      );
      final json = meta.toJson();
      final restored = PlaceholderMeta.fromJson(json);
      expect(restored.remotePath, '/docs/report.pdf');
      expect(restored.provider, 'gdrive');
      expect(restored.sizeBytes, 1048576);
      expect(restored.remoteModified, DateTime.utc(2026, 5, 30, 12, 0));
      expect(restored.contentHash, 'abc123');
    });

    test('encode/decode round-trip', () {
      final meta = PlaceholderMeta(
        remotePath: '/photos/sunset.jpg',
        provider: 's3',
        sizeBytes: 5242880,
      );
      final encoded = meta.encode();
      final decoded = PlaceholderMeta.decode(encoded);
      expect(decoded, isNotNull);
      expect(decoded!.remotePath, '/photos/sunset.jpg');
      expect(decoded.provider, 's3');
      expect(decoded.sizeBytes, 5242880);
      expect(decoded.remoteModified, isNull);
      expect(decoded.contentHash, isNull);
    });

    test('decode returns null for invalid content', () {
      expect(PlaceholderMeta.decode('not json'), isNull);
      expect(PlaceholderMeta.decode(''), isNull);
    });

    test('toJson includes version field', () {
      final meta = PlaceholderMeta(
        remotePath: '/test',
        provider: 'sftp',
        sizeBytes: 100,
      );
      final json = meta.toJson();
      expect(json['version'], 1);
    });

    test('fromJson handles missing optional fields', () {
      final meta = PlaceholderMeta.fromJson({
        'remotePath': '/test',
        'provider': 'ftp',
      });
      expect(meta.sizeBytes, 0);
      expect(meta.remoteModified, isNull);
      expect(meta.contentHash, isNull);
    });
  });

  // --- PlaceholderService Static Methods ---
  group('PlaceholderService static', () {
    test('isPlaceholder detects .crispcloud extension', () {
      expect(PlaceholderService.isPlaceholder('file.txt.crispcloud'), true);
      expect(PlaceholderService.isPlaceholder('photo.jpg.crispcloud'), true);
      expect(PlaceholderService.isPlaceholder('file.txt'), false);
      expect(PlaceholderService.isPlaceholder('crispcloud'), false);
      expect(PlaceholderService.isPlaceholder('.crispcloud'), true);
    });

    test('realName strips .crispcloud extension', () {
      expect(PlaceholderService.realName('file.txt.crispcloud'), 'file.txt');
      expect(PlaceholderService.realName('photo.jpg.crispcloud'), 'photo.jpg');
      expect(PlaceholderService.realName('a.crispcloud'), 'a');
    });

    test('placeholderName adds .crispcloud extension', () {
      expect(PlaceholderService.placeholderName('file.txt'), 'file.txt.crispcloud');
      expect(PlaceholderService.placeholderName('/path/to/photo.jpg'), '/path/to/photo.jpg.crispcloud');
    });

    test('round-trip: placeholderName → realName', () {
      const original = 'document.pdf';
      final placeholder = PlaceholderService.placeholderName(original);
      final restored = PlaceholderService.realName(placeholder);
      expect(restored, original);
    });
  });

  // --- SyncStatus enum includes placeholder ---
  group('SyncStatus', () {
    test('has placeholder value', () {
      expect(SyncStatus.values.map((s) => s.name), contains('placeholder'));
    });

    test('placeholder is distinct from synced', () {
      expect(SyncStatus.placeholder, isNot(SyncStatus.synced));
    });
  });

  // --- placeholderExtension ---
  group('Constants', () {
    test('placeholderExtension is .crispcloud', () {
      expect(placeholderExtension, '.crispcloud');
    });
  });
}
