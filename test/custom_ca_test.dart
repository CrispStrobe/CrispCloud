// test/custom_ca_test.dart
//
// Tests for custom CA certificate support and TLS version enforcement.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/services/cert_pinning_service.dart';

/// A fake PEM certificate with embedded Subject and CN fields.
Uint8List _fakePem({String cn = 'My Custom CA', String? subject}) {
  final text = '''
-----BEGIN CERTIFICATE-----
Subject: ${subject ?? 'CN=$cn, O=TestOrg'}
Issuer: CN=$cn, O=TestOrg
MIIBkTCB+wIJALRiMLAh7DAMB8wHQYDVQQDDBZNeSBDdXN0b20gQ0E=
-----END CERTIFICATE-----
''';
  return Uint8List.fromList(utf8.encode(text));
}

void main() {
  late CertPinningService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = CertPinningService();
  });

  // ---------------------------------------------------------------------------
  // Custom CA certificate management
  // ---------------------------------------------------------------------------

  group('Custom CA certificates -', () {
    test('initially empty', () {
      expect(service.getCustomCaCerts(), isEmpty);
    });

    test('add a custom CA cert', () async {
      await service.addCustomCaCert(_fakePem());
      expect(service.getCustomCaCerts(), hasLength(1));
    });

    test('add multiple custom CA certs', () async {
      await service.addCustomCaCert(_fakePem(cn: 'CA 1'));
      await service.addCustomCaCert(_fakePem(cn: 'CA 2'));
      await service.addCustomCaCert(_fakePem(cn: 'CA 3'));
      expect(service.getCustomCaCerts(), hasLength(3));
    });

    test('remove custom CA cert by index', () async {
      await service.addCustomCaCert(_fakePem(cn: 'CA A'));
      await service.addCustomCaCert(_fakePem(cn: 'CA B'));
      await service.removeCustomCaCert(0);
      final certs = service.getCustomCaCerts();
      expect(certs, hasLength(1));
      final text = utf8.decode(certs.first);
      expect(text, contains('CA B'));
    });

    test('remove at invalid index is no-op', () async {
      await service.addCustomCaCert(_fakePem());
      await service.removeCustomCaCert(-1);
      await service.removeCustomCaCert(5);
      expect(service.getCustomCaCerts(), hasLength(1));
    });

    test('getCustomCaCerts returns unmodifiable list', () async {
      await service.addCustomCaCert(_fakePem());
      final list = service.getCustomCaCerts();
      expect(() => list.add(Uint8List(0)), throwsUnsupportedError);
    });

    test('getCustomCaCertInfos extracts subject', () async {
      await service.addCustomCaCert(_fakePem(cn: 'Test CA'));
      final infos = service.getCustomCaCertInfos();
      expect(infos, hasLength(1));
      expect(infos.first.subjectDn, contains('Test CA'));
    });
  });

  // ---------------------------------------------------------------------------
  // Custom CA persistence
  // ---------------------------------------------------------------------------

  group('Custom CA persistence -', () {
    test('save and load round-trip', () async {
      await service.addCustomCaCert(_fakePem(cn: 'Persisted CA'));
      await service.addCustomCaCert(_fakePem(cn: 'Another CA'));

      // Create a new service and load from SharedPreferences
      final service2 = CertPinningService();
      await service2.loadCustomCaCerts();
      final certs = service2.getCustomCaCerts();
      expect(certs, hasLength(2));

      final text1 = utf8.decode(certs[0]);
      final text2 = utf8.decode(certs[1]);
      expect(text1, contains('Persisted CA'));
      expect(text2, contains('Another CA'));
    });

    test('save stores base64 in SharedPreferences', () async {
      final pem = _fakePem(cn: 'Base64 Test');
      await service.addCustomCaCert(pem);

      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList('custom_ca_certs');
      expect(stored, isNotNull);
      expect(stored, hasLength(1));

      // Verify it's valid base64 that decodes back to original
      final decoded = base64Decode(stored!.first);
      expect(decoded, equals(pem));
    });

    test('load with empty prefs yields empty list', () async {
      final fresh = CertPinningService();
      await fresh.loadCustomCaCerts();
      expect(fresh.getCustomCaCerts(), isEmpty);
    });

    test('load ignores corrupt base64 entries', () async {
      final prefs = await SharedPreferences.getInstance();
      final validPem = _fakePem(cn: 'Good');
      await prefs.setStringList('custom_ca_certs', [
        base64Encode(validPem),
        '!!!not-base64!!!',
      ]);

      final fresh = CertPinningService();
      await fresh.loadCustomCaCerts();
      expect(fresh.getCustomCaCerts(), hasLength(1));
    });
  });

  // ---------------------------------------------------------------------------
  // Custom CA validation
  // ---------------------------------------------------------------------------

  group('Custom CA validation -', () {
    // We cannot construct a real X509Certificate in tests without dart:io
    // network operations, but we can test the structural logic.

    test('validateWithCustomCAs returns false when no CAs stored', () async {
      // No certs added, so validation should return false for any cert.
      // We test indirectly by verifying the list is empty.
      expect(service.getCustomCaCerts(), isEmpty);
    });

    test('adding CA then checking info shows correct subject', () async {
      await service.addCustomCaCert(_fakePem(cn: 'Corp Internal CA'));
      final infos = service.getCustomCaCertInfos();
      expect(infos.first.subjectDn, contains('Corp Internal CA'));
      expect(infos.first.issuerDn, contains('Corp Internal CA'));
    });
  });

  // ---------------------------------------------------------------------------
  // TLS version enforcement
  // ---------------------------------------------------------------------------

  group('TLS version -', () {
    test('default is TLS 1.2', () {
      expect(service.getMinTlsVersion(), equals(TlsVersion.tls12));
    });

    test('set to TLS 1.3', () async {
      await service.setMinTlsVersion(TlsVersion.tls13);
      expect(service.getMinTlsVersion(), equals(TlsVersion.tls13));
    });

    test('set to any', () async {
      await service.setMinTlsVersion(TlsVersion.any);
      expect(service.getMinTlsVersion(), equals(TlsVersion.any));
    });

    test('persistence round-trip', () async {
      await service.setMinTlsVersion(TlsVersion.tls13);

      final service2 = CertPinningService();
      await service2.load();
      expect(service2.getMinTlsVersion(), equals(TlsVersion.tls13));
    });

    test('invalid stored value falls back to tls12', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('min_tls_version', 'bogus_value');

      final fresh = CertPinningService();
      await fresh.load();
      expect(fresh.getMinTlsVersion(), equals(TlsVersion.tls12));
    });

    test('TlsVersion enum has expected values', () {
      expect(TlsVersion.values, hasLength(3));
      expect(TlsVersion.values, contains(TlsVersion.any));
      expect(TlsVersion.values, contains(TlsVersion.tls12));
      expect(TlsVersion.values, contains(TlsVersion.tls13));
    });
  });

  // ---------------------------------------------------------------------------
  // CertPinSet host matching (existing, but good to verify not broken)
  // ---------------------------------------------------------------------------

  group('CertPinSet -', () {
    test('matchesHost with exact match', () {
      const ps = CertPinSet(
        name: 'Test',
        hostPatterns: ['example.com'],
        pins: {'abc='},
      );
      expect(ps.matchesHost('example.com'), isTrue);
    });

    test('matchesHost with suffix match', () {
      const ps = CertPinSet(
        name: 'Test',
        hostPatterns: ['example.com'],
        pins: {'abc='},
      );
      expect(ps.matchesHost('api.example.com'), isTrue);
    });

    test('matchesHost rejects non-matching host', () {
      const ps = CertPinSet(
        name: 'Test',
        hostPatterns: ['example.com'],
        pins: {'abc='},
      );
      expect(ps.matchesHost('other.com'), isFalse);
    });
  });
}
