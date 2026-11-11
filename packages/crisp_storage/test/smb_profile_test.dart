import 'package:crisp_storage/crisp_storage.dart';
import 'package:test/test.dart';

void main() {
  RemoteConnection profile({SmbBackend? backend}) => RemoteConnection(
    id: 'id',
    name: 'NAS',
    kind: 'smb',
    url: 'smb://localhost/books/',
    username: 'reader',
    secret: 'private',
    smbBackend: backend,
  );
  for (final backend in SmbBackend.values) {
    test('${backend.name} persists without exposing credentials', () {
      final original = profile(backend: backend);
      expect(original.toJson()['smbBackend'], backend.name);
      expect(original.toJson().containsKey('secret'), isFalse);
      final restored = RemoteConnection.fromJson(
        original.toJson(credentials: true),
      );
      expect(restored.smbBackend, backend);
      final session = SmbSession(restored);
      expect(session.backend, backend);
      session.close();
    });
  }
  test('legacy default, explicit override and invalid profile values', () {
    final legacy = RemoteConnection.fromJson(
      profile().toJson(credentials: true),
    );
    expect(legacy.smbBackend, isNull);
    final defaultSession = SmbSession(legacy);
    expect(defaultSession.backend, SmbBackend.libsmb2);
    defaultSession.close();
    final override = SmbSession(
      profile(backend: SmbBackend.rust),
      backend: SmbBackend.libsmb2,
    );
    expect(override.backend, SmbBackend.libsmb2);
    override.close();
    for (final invalid in ['RUST', '', 'native', false, 42]) {
      expect(
        () => RemoteConnection.fromJson({
          ...profile().toJson(credentials: true),
          'smbBackend': invalid,
        }),
        throwsFormatException,
      );
    }
    expect(legacy.requireEncryption, isTrue);
  });
}
