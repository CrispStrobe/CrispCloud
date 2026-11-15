import 'package:crisp_storage/src/smb_backend.dart';
import 'package:test/test.dart';

void main() {
  test('default and legacy saved profiles select Rust', () {
    expect(configuredSmbBackend(), SmbBackend.rust);
    for (final value in ['libsmb2', 'rust', 'auto']) {
      expect(parseSmbBackend(value), SmbBackend.rust);
    }
    expect(() => parseSmbBackend('typo'), throwsFormatException);
  });
  test('all selections load Rust without an LGPL fallback', () async {
    for (final value in SmbBackend.values) {
      var loads = 0;
      expect(
        await selectSmbBackend(value, () async {
          loads++;
        }),
        SmbBackend.rust,
      );
      expect(loads, 1);
      await expectLater(
        selectSmbBackend(value, () async {
          throw const RustSmbUnavailable();
        }),
        throwsA(isA<RustSmbUnavailable>()),
      );
      await expectLater(
        selectSmbBackend(value, () async {
          throw StateError('security failure');
        }),
        throwsStateError,
      );
    }
  });
}
