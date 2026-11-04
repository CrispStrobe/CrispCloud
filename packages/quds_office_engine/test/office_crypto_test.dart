import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
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
