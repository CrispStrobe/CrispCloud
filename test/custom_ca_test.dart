// Tests use real X.509 certificates. PEM labels and issuer-name matching are
// never an alternative to native certificate parsing and TLS chain validation.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/services/cert_pinning_service.dart';

Uint8List _fixture(String name) =>
    File('test/fixtures/tls/$name').readAsBytesSync();

Uint8List _der(Uint8List pem) => base64Decode(
  utf8
      .decode(pem)
      .replaceAll('-----BEGIN CERTIFICATE-----', '')
      .replaceAll('-----END CERTIFICATE-----', '')
      .replaceAll(RegExp(r'\s'), ''),
);

void main() {
  late CertPinningService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = CertPinningService();
  });

  group('Custom CA certificates', () {
    test('valid PEM and DER certificates can be imported', () async {
      await service.addCustomCaCert(_fixture('ca.pem'));
      await service.addCustomCaCert(_der(_fixture('other-ca.pem')));
      expect(service.getCustomCaCerts(), hasLength(2));
      expect(
        service.getCustomCaCertInfos().first.subjectDn,
        startsWith('SHA-256: '),
      );
    });

    test('PEM bundle creates separate removable trust anchors', () async {
      final bundle = Uint8List.fromList([
        ..._fixture('ca.pem'),
        ..._fixture('other-ca.pem'),
      ]);
      await service.addCustomCaCert(bundle);
      expect(service.getCustomCaCerts(), hasLength(2));
      await service.removeCustomCaCert(0);
      expect(
        _der(service.getCustomCaCerts().single),
        equals(_der(_fixture('other-ca.pem'))),
      );
      await service.removeCustomCaCert(-1);
      await service.removeCustomCaCert(99);
      expect(service.getCustomCaCerts(), hasLength(1));
    });

    test(
      'malformed PEM with fake Subject text is rejected before persistence',
      () async {
        final fake = Uint8List.fromList(
          utf8.encode('''
-----BEGIN CERTIFICATE-----
Subject: CN=My Custom CA
Issuer: CN=My Custom CA
MIIBkTCB+wIJALRiMLAh7DAMB8wHQYDVQQDDBZNeSBDdXN0b20gQ0E=
-----END CERTIFICATE-----
'''),
        );
        await expectLater(service.addCustomCaCert(fake), throwsFormatException);
        expect(service.getCustomCaCerts(), isEmpty);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getStringList('custom_ca_certs'), isNull);
      },
    );

    test(
      'an invalid certificate prevents partial import of a bundle',
      () async {
        final mixed = Uint8List.fromList([
          ..._fixture('ca.pem'),
          ...utf8.encode(
            '-----BEGIN CERTIFICATE-----\nAA==\n'
            '-----END CERTIFICATE-----\n',
          ),
        ]);
        await expectLater(
          service.addCustomCaCert(mixed),
          throwsFormatException,
        );
        expect(service.getCustomCaCerts(), isEmpty);
      },
    );

    test('unsigned PEM metadata cannot spoof the display identifier', () async {
      await service.addCustomCaCert(
        Uint8List.fromList([
          ...utf8.encode('Subject: CN=Untrusted display name\n'),
          ..._fixture('ca.pem'),
        ]),
      );
      final info = service.getCustomCaCertInfos().single;
      expect(info.subjectDn, startsWith('SHA-256: '));
      expect(info.subjectDn, isNot(contains('Untrusted display name')));
      expect(utf8.decode(info.pemBytes), isNot(contains('Subject:')));
    });

    test('callers cannot mutate a previously validated certificate', () async {
      await service.addCustomCaCert(_fixture('ca.pem'));
      final snapshot = service.getCustomCaCerts();
      expect(() => snapshot.add(Uint8List(0)), throwsUnsupportedError);
      snapshot.single.fillRange(0, snapshot.single.length, 0);
      expect(
        _der(service.getCustomCaCerts().single),
        equals(_der(_fixture('ca.pem'))),
      );
    });

    test(
      'valid certificates persist; corrupt and invalid old entries do not load',
      () async {
        await service.addCustomCaCert(_fixture('ca.pem'));
        final prefs = await SharedPreferences.getInstance();
        final stored = prefs.getStringList('custom_ca_certs')!;
        await prefs.setStringList('custom_ca_certs', [
          ...stored,
          '!!!not-base64!!!',
          base64Encode(utf8.encode('Subject: CN=Fake CA')),
        ]);
        final restored = CertPinningService();
        await restored.load();
        expect(restored.getCustomCaCerts(), hasLength(1));
        expect(
          _der(restored.getCustomCaCerts().single),
          equals(_der(_fixture('ca.pem'))),
        );
      },
    );
  });

  group('TLS policy', () {
    test(
      'default config requires TLS 1.2 and rejects unsafe renegotiation',
      () {
        final context = service.configureSecurityContext(null);
        expect(context.minimumTlsProtocolVersion, TlsProtocolVersion.tls1_2);
        expect(context.allowLegacyUnsafeRenegotiation, isFalse);
      },
    );

    test(
      'TLS 1.3 selection reaches the native context and survives reload',
      () async {
        await service.setMinTlsVersion(TlsVersion.tls13);
        final restored = CertPinningService();
        await restored.load();
        expect(restored.getMinTlsVersion(), TlsVersion.tls13);
        expect(
          restored.configureSecurityContext(null).minimumTlsProtocolVersion,
          TlsProtocolVersion.tls1_3,
        );
      },
    );

    test('caller TLS 1.3 policy is not weakened by TLS 1.2 preference', () {
      final context = SecurityContext()
        ..minimumTlsProtocolVersion = TlsProtocolVersion.tls1_3;
      expect(
        service.configureSecurityContext(context).minimumTlsProtocolVersion,
        TlsProtocolVersion.tls1_3,
      );
    });

    test('legacy any selection uses the supported platform default', () async {
      await service.setMinTlsVersion(TlsVersion.any);
      expect(
        service.configureSecurityContext(null).minimumTlsProtocolVersion,
        TlsProtocolVersion.tls1_2,
      );
    });

    test('invalid stored TLS value falls back to TLS 1.2', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('min_tls_version', 'bogus');
      await service.load();
      expect(service.getMinTlsVersion(), TlsVersion.tls12);
    });
  });
}
