import 'package:crisp_storage/src/smb_backend.dart';
import 'package:test/test.dart';

void main() {
  test('default does not load Rust', () async {
    expect(configuredSmbBackend(), SmbBackend.libsmb2);
    expect(
      await selectSmbBackend(
        SmbBackend.libsmb2,
        () async => fail('must not load'),
      ),
      SmbBackend.libsmb2,
    );
  });
  test('auto falls back only when the native library is unavailable', () async {
    expect(
      await selectSmbBackend(
        SmbBackend.auto,
        () async => throw const RustSmbUnavailable(),
      ),
      SmbBackend.libsmb2,
    );
    expect(
      await selectSmbBackend(SmbBackend.auto, () async {}),
      SmbBackend.rust,
    );
    await expectLater(
      selectSmbBackend(
        SmbBackend.auto,
        () async => throw StateError('security failure'),
      ),
      throwsStateError,
    );
  });
  test('strict Rust never falls back', () async {
    await expectLater(
      selectSmbBackend(
        SmbBackend.rust,
        () async => throw const RustSmbUnavailable(),
      ),
      throwsA(isA<RustSmbUnavailable>()),
    );
  });
}
