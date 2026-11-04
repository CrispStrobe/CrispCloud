import 'package:dart_pdf_editor_secure_storage/dart_pdf_editor_secure_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'host-token': 'leave-intact'});
  });

  test('form storage round-trips and clears only its own namespace', () async {
    const storage = FlutterSecureStorage();
    final store = SecureFormSecretStore(storage: storage);
    await store.write('doc-a', 'pin', '1234');
    await store.write('doc-a', 'password', 'example');
    await store.write('doc-b', 'password', 'other');
    expect(await store.readAll('doc-a'),
        {'pin': '1234', 'password': 'example'});
    await store.remove('doc-a', 'pin');
    expect(await store.read('doc-a', 'pin'), isNull);
    await store.clearDocument('doc-a');
    expect(await store.readAll('doc-a'), isEmpty);
    expect(await store.read('doc-b', 'password'), 'other');
    await store.clearAll();
    expect(await store.readAll('doc-b'), isEmpty);
    expect(await storage.read(key: 'host-token'), 'leave-intact');
  });

  test('identity adapter preserves keys across instances and namespaced delete',
      () async {
    const storage = FlutterSecureStorage();
    final identity = PdfSigningIdentity.generate(name: 'Adapter test');
    final store = SecureIdentityStore(storage: storage);
    await store.save('test', identity);

    final reopened = SecureIdentityStore(storage: storage);
    expect(await reopened.ids(), ['test']);
    final loaded = await reopened.load('test');
    expect(loaded!.certificate, identity.certificate);
    expect(loaded.privateKey.d, identity.privateKey.d);

    await reopened.delete('test');
    expect(await reopened.ids(), isEmpty);
    expect(await store.load('test'), isNull);
    expect(await storage.read(key: 'host-token'), 'leave-intact');
  });
}
