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
