import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  group('Agile encryption data integrity', () {
    late Uint8List locked;
    late Uint8List plaintext;

    setUp(() {
      plaintext = Uint8List.fromList(List.generate(128, (i) => i));
      locked = OfficeCrypto.encrypt(plaintext, 'integrity-test', spinCount: 10);
    });

    Uint8List rewrite({Uint8List? package, Uint8List? info}) {
      final file = CfbfFile.fromBytes(locked);
      final writer = CfbfWriter();
      writer.addStream(
        'EncryptionInfo',
        info ?? file.readStream('EncryptionInfo')!,
      );
      writer.addStream(
        'EncryptedPackage',
        package ?? file.readStream('EncryptedPackage')!,
      );
      return writer.build();
    }

    test('authenticates before returning plaintext', () {
      expect(OfficeCrypto.decrypt(locked, 'integrity-test'), plaintext);
      final pack = CfbfFile.fromBytes(locked).readStream('EncryptedPackage')!;
      // The password verifier is untouched; only file ciphertext changes.
      pack[24] ^= 1;
      expect(
        () => OfficeCrypto.decrypt(rewrite(package: pack), 'integrity-test'),
        throwsA(isA<OfficePasswordException>()),
      );
    });

    test('authenticates StreamSize as well as ciphertext', () {
      final pack = CfbfFile.fromBytes(locked).readStream('EncryptedPackage')!;
      pack[0] ^= 1;
      expect(
        () => OfficeCrypto.decrypt(rewrite(package: pack), 'integrity-test'),
        throwsA(isA<OfficePasswordException>()),
      );
    });

    test(
      'missing integrity metadata cannot downgrade to unauthenticated CBC',
      () {
        final info = CfbfFile.fromBytes(locked).readStream('EncryptionInfo')!;
        final xml = utf8
            .decode(info.sublist(8))
            .replaceFirst(RegExp(r'<dataIntegrity\s[^>]*/>'), '');
        final stripped = Uint8List.fromList([
          ...info.sublist(0, 8),
          ...utf8.encode(xml),
        ]);
        expect(
          () => OfficeCrypto.decrypt(rewrite(info: stripped), 'integrity-test'),
          throwsA(isA<OfficePasswordException>()),
        );
      },
    );
  });

  group('Independent Agile DataIntegrity fixture', () {
    // Generated with Python hashlib/hmac and cryptography AES-CBC, without
    // this library. Plaintext is bytes 128..159; secret is bytes 32..63;
    // KeyData salt is 0..15, password salt is 16..39, verifier is 64..87.
    // Ten SHA-512 password iterations use "independent-integrity-fixture".
    // The 16-byte HMAC key is 606162636465666768696a6b6c6d6e01: its final
    // 0x01 is key material, not padding. DataIntegrity follows MS-OFFCRYPTO
    // 2.3.4.14, including the StreamSize in HMAC-SHA512 and no extra block
    // when encrypting an already aligned HMAC key/value.
    //
    // Password wrapping deliberately reproduces the library's existing
    // block keys, hashed IVs and PKCS#7 padding so this isolated integrity
    // regression does not claim complete Microsoft Office interoperability.
    // In particular, the existing secret block is 146e0be7accad1d6.
    const xml =
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<encryption xmlns="http://schemas.microsoft.com/office/2006/encryption" '
        'xmlns:p="http://schemas.microsoft.com/office/2006/keyEncryptor/password">'
        '<keyData saltSize="16" blockSize="16" keyBits="256" hashSize="64" '
        'cipherAlgorithm="AES" cipherChaining="ChainingModeCBC" '
        'hashAlgorithm="SHA512" saltValue="AAECAwQFBgcICQoLDA0ODw=="/>'
        '<dataIntegrity encryptedHmacKey="AdJImdiEiyt0NVAixdsfdw==" '
        'encryptedHmacValue="t4N/GSW7EwzpYhTtrSXeJRbxDr9sMh68XVaesSDOnPPX+zjaiYqs5OuZBsFuZNn4ny7w7zBd/9SpZVivsc+bnQ=="/>'
        '<keyEncryptors><keyEncryptor '
        'uri="http://schemas.microsoft.com/office/2006/keyEncryptor/password">'
        '<p:encryptedKey spinCount="10" saltSize="24" blockSize="16" '
        'keyBits="256" hashSize="64" cipherAlgorithm="AES" '
        'cipherChaining="ChainingModeCBC" hashAlgorithm="SHA512" '
        'saltValue="EBESExQVFhcYGRobHB0eHyAhIiMkJSYn" '
        'encryptedVerifierHashInput="ixeFej6bQY0s14E1hNj1gl0bsLamQXU6S+8UANv+2Y4=" '
        'encryptedVerifierHashValue="SHuc4rhX0HKID1sfEtzFVxVuWs606TLxLkduxyWKiWIUtvidO+nKnSigrGY0ABoPBx81bgFdj5yQyfxvEzDnq3A4SVXY/7pdMAK90pRpHv0=" '
        'encryptedKeyValue="DDW3DU7GjGOSYoPc7n/ItNmKhgwUcKpR/GMquRNUgQh9OP57YMnP9YyeoMUqAPwh"/>'
        '</keyEncryptor></keyEncryptors></encryption>';

    Uint8List fixture({bool tamperPackage = false, String info = xml}) {
      final pack = base64.decode(
        'IAAAAAAAAACfKqSVyLtDNvmBSIexjZyfZp/nTHkX4pmRugnzpqJC0A==',
      );
      if (tamperPackage) {
        pack[8] ^= 1;
      }
      final writer = CfbfWriter();
      writer.addStream(
        'EncryptionInfo',
        Uint8List.fromList([4, 0, 4, 0, 0x40, 0, 0, 0, ...utf8.encode(info)]),
      );
      writer.addStream('EncryptedPackage', pack);
      return writer.build();
    }

    test('uses KeyData salt size, not password salt size or hash size', () {
      expect(
        OfficeCrypto.decrypt(fixture(), 'independent-integrity-fixture'),
        Uint8List.fromList(List.generate(32, (i) => i + 128)),
      );
    });

    test('short-key compatibility still requires a valid package HMAC', () {
      expect(
        () => OfficeCrypto.decrypt(
          fixture(tamperPackage: true),
          'independent-integrity-fixture',
        ),
        throwsA(isA<OfficePasswordException>()),
      );
    });

    test(
      'rejects a declared KeyData salt size that disagrees with its salt',
      () {
        expect(
          () => OfficeCrypto.decrypt(
            fixture(
              info: xml.replaceFirst(
                '<keyData saltSize="16"',
                '<keyData saltSize="15"',
              ),
            ),
            'independent-integrity-fixture',
          ),
          throwsA(isA<OfficePasswordException>()),
        );
      },
    );
  });

  test('AES-128 ECB matches the FIPS-197 Appendix C.1 vector', () {
    final Uint8List key = Uint8List.fromList(<int>[
      0x00,
      0x01,
      0x02,
      0x03,
      0x04,
      0x05,
      0x06,
      0x07,
      0x08,
      0x09,
      0x0a,
      0x0b,
      0x0c,
      0x0d,
      0x0e,
      0x0f,
    ]);
    final Uint8List plain = Uint8List.fromList(<int>[
      0x00,
      0x11,
      0x22,
      0x33,
      0x44,
      0x55,
      0x66,
      0x77,
      0x88,
      0x99,
      0xaa,
      0xbb,
      0xcc,
      0xdd,
      0xee,
      0xff,
    ]);
    final Uint8List expected = Uint8List.fromList(<int>[
      0x69,
      0xc4,
      0xe0,
      0xd8,
      0x6a,
      0x7b,
      0x04,
      0x30,
      0xd8,
      0xcd,
      0xb7,
      0x80,
      0x70,
      0xb4,
      0xc5,
      0x5a,
    ]);
    final Aes aes = Aes(key);
    final Uint8List cipher = Uint8List(16);
    aes.encryptBlock(plain, 0, cipher, 0);
    expect(cipher, expected);
    final Uint8List back = Uint8List(16);
    aes.decryptBlock(cipher, 0, back, 0);
    expect(back, plain);
  });

  test('password-protects an xlsx and reopens it', () {
    final XlsxWorkbookBuilder book = XlsxWorkbookBuilder();
    book.addSheet('بيانات')
      ..addRow(<Object?>['الاسم', 'قيمة'])
      ..addRow(<Object?>['أ', 7]);
    const String password = 'سرّ123';
    final Uint8List locked = book.build(password: password);
    expect(OfficeCrypto.isEncrypted(locked), isTrue);
    expect(CfbfFile.isCfbf(locked), isTrue);
    expect(
      () => OpcPackage.openBytes(locked),
      throwsA(isA<OfficePasswordRequiredException>()),
    );
    expect(
      () => OpcPackage.openBytes(locked, password: 'wrong'),
      throwsA(isA<OfficePasswordException>()),
    );
    final List<Map<String, String>> rows = XlsxGridReader.readHeaderMaps(
      locked,
      password: password,
    );
    expect(rows.single['الاسم'], 'أ');
    expect(rows.single['قيمة'], '7');
  });

  test('password-protects a docx through OpcPackage.save', () {
    final Uint8List locked = WordSerializer().writeBytes(
      WmlDocument.empty(text: 'محمي'),
      password: 'office',
    );
    expect(OfficeCrypto.isEncrypted(locked), isTrue);
    final WmlDocument opened = WordDeserializer().readBytes(
      locked,
      password: 'office',
    );
    expect(opened.paragraphs.first.text, contains('محمي'));
  });
}
