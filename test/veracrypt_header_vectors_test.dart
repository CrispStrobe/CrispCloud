import 'dart:convert';

import 'package:crisp_cloud/services/veracrypt_service.dart';
import 'package:flutter_test/flutter_test.dart';

// Independent fixtures generated with Python hashlib.pbkdf2_hmac (10
// iterations), cryptography AES-XTS (data unit 0) and zlib.crc32. These do not
// use the Dart production encryptor/KDF or its mirrored legacy test helper.
// Layout: https://veracrypt.io/en/VeraCrypt%20Volume%20Format%20Specification.html
// Header version 5; salt=bytes(range(64)); password='audit-vector-password';
// plaintext[0:4]='VERA', uint16BE[4]=5, uint16BE[6]=0x010b;
// uint64BE[36]=10MiB, [44]=131072, [52]=10MiB, uint32BE[64]=512 (or 1000);
// plaintext[192:448]=bytes(range(256)); uint32BE[8]=crc32(plaintext[192:448]);
// uint32BE[188]=crc32(plaintext[0:188]); all other plaintext bytes are zero.
// raw=salt || AES-XTS(PBKDF2-HMAC(password,salt,10,64), zero_tweak, plaintext).

const _sha512 =
    'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4vMDEyMzQ1Njc4'
    'OTo7PD0+PxXvFvoGzohY9myQ5EYxOTw8NnpP2ZfIvXWVhnrUX47WlO6/+J6fZ4gXBYLewM76FFcm'
    '5qwNhNZ2vtRoPedbSywORGR1wRN9azhdn7D5OqEJH7p3NTt1enEG2gP4e9rp7acJOeHnhRUeMea+'
    'VAs+JSxxDjJsGmw7N8ZPFumv3tV1VuJccUD0suhRJr8fFYZDAHd4wcoFn9OggUGoG5nBuMOEVqJp'
    '7tavyaeZZ5Qba6cXLKnviKakXpTfK8Q3/oVAXDRG1J3QmtuEaxvG+WQ5GWdsQQx30SCuISNOZiC1'
    'UJruMC2+uualssv/Y4pjCQh/WLsqf6xcaSl6f4o1gEQLiZFpvNfNDED66gPDhAPpq/VL/Fkkwlcz'
    'Fft2AC2dnisIhUZ1YGsJTlAX22+sVZg1sVTABiAWXJjpliq4gTZnsnAdU78wUAh6praog3UF79ZO'
    'CkVHTOaUBgbw4IjuQBoS0nqFQfpnhPiuD3Xx2kmak5RW6cNUzhIVC4S+mrx6Qv9wzbGZ+SILnr1s'
    'dFZPBZrHx4g1HmOJnXhtfSD0eJemS//ZIycS1gqDwNpLTMTZjsfRv6pqd1pk23FApQgJW1/hiUM=';

const _sha256 =
    'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4vMDEyMzQ1Njc4'
    'OTo7PD0+P+Oil/MWaCqJ3KCjMLlIy+6xIn4NJc1CzOqowmhF0AT0atCb+tfZAYqyMtbRVOTJd595'
    'i/c0AMHu/ax3oZNiuYXlQoOI9nVHWE7dDN53SFQWREnMh2djRs06eAlZRBKbPgL93UG4/qHfa5vp'
    '8ucopJQOFXAKWZ0hfIQ0R5S2XquzAX4kMcUo03FDUEWfzPzrGz9kxP5r1Zeeb9c8g25jOeTPtgW9'
    'ZRRdtH+2DKBBNJ+hPoui5lj9x4RXvUg1oGaGN/WBDxxm1KjS9uKzSJnChQKP6WS+ess/WhLIcKWm'
    'LNsHuldGkswVntPV8akZ97zAnLnrGDm7TRJp2A5QYugXmBk0C7l27SIv+JzD5bAJoY3lGj4+BgG8'
    'XGMbf7/HvAXDmH9phl8stwULmdWtGF7Py6HeIH2mJPDvz5T4rUeHOyh85hha0Vw0AwUsSfNer2iO'
    'yl0kTTCGZnqdvNmYbXLppVopSbXmcDdAv5fgrkufmozmtrveNdJSBMXH2YfsDJtObU8/B15JM20h'
    'bbizv93xMwU89AZcbzl7hcXPzBZlaW+D+E6rl221qvvkws5n7CLqNdd3H7ZfGGXHTYoebavwWko=';

const _invalidSector =
    'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4vMDEyMzQ1Njc4'
    'OTo7PD0+PxXvFvoGzohY9myQ5EYxOTw8NnpP2ZfIvXWVhnrUX47WlO6/+J6fZ4gXBYLewM76FFcm'
    '5qwNhNZ2vtRoPedbSyzd66PVfUpyQDE9UBdi11C2H7p3NTt1enEG2gP4e9rp7acJOeHnhRUeMea+'
    'VAs+JSxxDjJsGmw7N8ZPFumv3tV1VuJccUD0suhRJr8fFYZDAHd4wcoFn9OggUGoG5nBuMOEVqJp'
    '7tavyaeZZ5Qba6cXK4iGzB5ybrHMigcjc71TfjRG1J3QmtuEaxvG+WQ5GWdsQQx30SCuISNOZiC1'
    'UJruMC2+uualssv/Y4pjCQh/WLsqf6xcaSl6f4o1gEQLiZFpvNfNDED66gPDhAPpq/VL/Fkkwlcz'
    'Fft2AC2dnisIhUZ1YGsJTlAX22+sVZg1sVTABiAWXJjpliq4gTZnsnAdU78wUAh6praog3UF79ZO'
    'CkVHTOaUBgbw4IjuQBoS0nqFQfpnhPiuD3Xx2kmak5RW6cNUzhIVC4S+mrx6Qv9wzbGZ+SILnr1s'
    'dFZPBZrHx4g1HmOJnXhtfSD0eJemS//ZIycS1gqDwNpLTMTZjsfRv6pqd1pk23FApQgJW1/hiUM=';

void main() {
  test('reads independent AES-XTS headers at the official offsets', () {
    for (final fixture in [(_sha512, 1), (_sha256, 3)]) {
      final parsed = VeraCryptService.tryDecryptHeader(
        base64.decode(fixture.$1),
        'audit-vector-password',
        testIterations: 10,
      );
      expect(parsed, isNotNull);
      expect(parsed!.version, 5);
      expect(parsed.sectorSize, 512);
      expect(parsed.volumeSize, 10 * 1024 * 1024);
      expect(parsed.encryptedAreaOffset, 131072);
      expect(parsed.encryptedAreaSize, 10 * 1024 * 1024);
      expect(parsed.encryptionAlgorithmId, 1);
      expect(parsed.hashAlgorithmId, fixture.$2);
      expect(parsed.salt, List.generate(64, (i) => i));
    }
  });

  test('rejects corruption even when the VERA magic block is unchanged', () {
    // XTS corrupts only the affected 16-byte plaintext block. These mutations
    // preserve VERA, while separately breaking the header-field and key CRCs.
    for (final offset in [144, 300, 500]) {
      final tampered = base64.decode(_sha512)..[offset] ^= 1;
      expect(
        VeraCryptService.tryDecryptHeader(
          tampered,
          'audit-vector-password',
          testIterations: 10,
        ),
        isNull,
        reason: 'Corruption at complete-header offset $offset',
      );
    }
  });

  test(
    'rejects impossible sector geometry even when both CRCs are correct',
    () {
      expect(
        VeraCryptService.tryDecryptHeader(
          base64.decode(_invalidSector),
          'audit-vector-password',
          testIterations: 10,
        ),
        isNull,
      );
    },
  );

  test('wrong password cannot unlock an independent header', () {
    expect(
      VeraCryptService.tryDecryptHeader(
        base64.decode(_sha512),
        'wrong',
        testIterations: 10,
      ),
      isNull,
    );
  });
}
