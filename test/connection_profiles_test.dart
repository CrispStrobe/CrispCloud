// test/connection_profiles_test.dart
//
// Unit tests for ConnectionProfile model and ConnectionProfileService.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/services/connection_profiles.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';

void main() {
  // ---------------------------------------------------------------------------
  // ConnectionProfile model
  // ---------------------------------------------------------------------------
  group('ConnectionProfile model', () {
    test('toJson includes all fields', () {
      const profile = ConnectionProfile(
        name: 'work-s3',
        provider: 's3',
        fields: {'bucket': 'my-bucket', 'region': 'us-east-1', 'accessKey': 'AKIA...'},
      );
      final json = profile.toJson();
      expect(json['name'], 'work-s3');
      expect(json['provider'], 's3');
      expect(json['fields'], {'bucket': 'my-bucket', 'region': 'us-east-1', 'accessKey': 'AKIA...'});
    });

    test('fromJson round-trip', () {
      const original = ConnectionProfile(
        name: 'personal-gdrive',
        provider: 'gdrive',
        fields: {'clientId': 'cid', 'clientSecret': 'cs'},
      );
      final json = original.toJson();
      final restored = ConnectionProfile.fromJson(json);
      expect(restored.name, 'personal-gdrive');
      expect(restored.provider, 'gdrive');
      expect(restored.fields['clientId'], 'cid');
      expect(restored.fields['clientSecret'], 'cs');
    });

    test('fromJson with empty fields map', () {
      final profile = ConnectionProfile.fromJson({
        'name': 'empty',
        'provider': 'local',
        'fields': <String, dynamic>{},
      });
      expect(profile.fields, isEmpty);
    });

    test('fields map is a String-String map', () {
      const profile = ConnectionProfile(
        name: 'test',
        provider: 'sftp',
        fields: {'host': '10.0.0.1', 'port': '22'},
      );
      expect(profile.fields, isA<Map<String, String>>());
      expect(profile.fields['port'], '22');
    });
  });

  // ---------------------------------------------------------------------------
  // ConnectionProfileService
  // ---------------------------------------------------------------------------
  group('ConnectionProfileService', () {
    late InMemorySecureStorage storage;
    late ConnectionProfileService service;

    setUp(() {
      storage = InMemorySecureStorage();
      service = ConnectionProfileService(storage);
    });

    test('getAll returns empty list when no profiles saved', () async {
      final all = await service.getAll();
      expect(all, isEmpty);
    });

    test('save and getAll round-trip', () async {
      const profile = ConnectionProfile(
        name: 'home-nas',
        provider: 'sftp',
        fields: {'host': '192.168.1.100', 'port': '22', 'user': 'admin'},
      );
      await service.save(profile);

      final all = await service.getAll();
      expect(all.length, 1);
      expect(all.first.name, 'home-nas');
      expect(all.first.provider, 'sftp');
      expect(all.first.fields['host'], '192.168.1.100');
    });

    test('save multiple profiles for different providers', () async {
      await service.save(const ConnectionProfile(
        name: 'work', provider: 's3', fields: {'bucket': 'b1'},
      ));
      await service.save(const ConnectionProfile(
        name: 'personal', provider: 'gdrive', fields: {'clientId': 'c1'},
      ));
      await service.save(const ConnectionProfile(
        name: 'backup', provider: 'sftp', fields: {'host': 'backup.local'},
      ));

      final all = await service.getAll();
      expect(all.length, 3);
    });

    test('save upserts by name+provider', () async {
      await service.save(const ConnectionProfile(
        name: 'server', provider: 'sftp', fields: {'host': 'old.example.com'},
      ));
      await service.save(const ConnectionProfile(
        name: 'server', provider: 'sftp', fields: {'host': 'new.example.com'},
      ));

      final all = await service.getAll();
      expect(all.length, 1);
      expect(all.first.fields['host'], 'new.example.com');
    });

    test('save does not conflict across providers with same name', () async {
      await service.save(const ConnectionProfile(
        name: 'production', provider: 's3', fields: {'bucket': 'prod-bucket'},
      ));
      await service.save(const ConnectionProfile(
        name: 'production', provider: 'sftp', fields: {'host': 'prod.sftp.com'},
      ));

      final all = await service.getAll();
      expect(all.length, 2);
    });

    test('getForProvider filters by provider', () async {
      await service.save(const ConnectionProfile(
        name: 'a', provider: 's3', fields: {'x': '1'},
      ));
      await service.save(const ConnectionProfile(
        name: 'b', provider: 'sftp', fields: {'x': '2'},
      ));
      await service.save(const ConnectionProfile(
        name: 'c', provider: 's3', fields: {'x': '3'},
      ));

      final s3Profiles = await service.getForProvider('s3');
      expect(s3Profiles.length, 2);
      expect(s3Profiles.every((p) => p.provider == 's3'), true);

      final sftpProfiles = await service.getForProvider('sftp');
      expect(sftpProfiles.length, 1);
    });

    test('getForProvider returns empty for unknown provider', () async {
      await service.save(const ConnectionProfile(
        name: 'x', provider: 's3', fields: {'a': 'b'},
      ));

      final result = await service.getForProvider('dropbox');
      expect(result, isEmpty);
    });

    test('delete removes by name+provider', () async {
      await service.save(const ConnectionProfile(
        name: 'toDelete', provider: 'ftp', fields: {'host': 'ftp.example.com'},
      ));
      await service.save(const ConnectionProfile(
        name: 'toKeep', provider: 'sftp', fields: {'host': 'sftp.example.com'},
      ));

      await service.delete('toDelete', 'ftp');

      final all = await service.getAll();
      expect(all.length, 1);
      expect(all.first.name, 'toKeep');
    });

    test('delete non-existent profile is a no-op', () async {
      await service.save(const ConnectionProfile(
        name: 'existing', provider: 's3', fields: {'b': 'v'},
      ));

      await service.delete('nonexistent', 's3');

      final all = await service.getAll();
      expect(all.length, 1);
    });

    test('delete only removes matching name+provider pair', () async {
      await service.save(const ConnectionProfile(
        name: 'shared-name', provider: 's3', fields: {'x': '1'},
      ));
      await service.save(const ConnectionProfile(
        name: 'shared-name', provider: 'sftp', fields: {'x': '2'},
      ));

      await service.delete('shared-name', 's3');

      final all = await service.getAll();
      expect(all.length, 1);
      expect(all.first.provider, 'sftp');
    });

    test('persists across service instances', () async {
      await service.save(const ConnectionProfile(
        name: 'durable', provider: 'gdrive', fields: {'id': '123'},
      ));

      // Create new service with same storage
      final service2 = ConnectionProfileService(storage);
      final all = await service2.getAll();
      expect(all.length, 1);
      expect(all.first.name, 'durable');
    });

    test('getAll handles corrupted storage gracefully', () async {
      await storage.write('connection_profiles', 'invalid json data');

      final all = await service.getAll();
      expect(all, isEmpty);
    });

    test('getAll handles empty string in storage', () async {
      await storage.write('connection_profiles', '');

      final all = await service.getAll();
      expect(all, isEmpty);
    });

    test('save preserves credential fields securely', () async {
      await service.save(const ConnectionProfile(
        name: 'secure-server',
        provider: 'sftp',
        fields: {
          'host': 'secure.example.com',
          'port': '22',
          'username': 'admin',
          'privateKey': '-----BEGIN RSA PRIVATE KEY-----\nMIIE...',
        },
      ));

      final all = await service.getAll();
      expect(all.first.fields['privateKey'], startsWith('-----BEGIN RSA'));
    });
  });
}
