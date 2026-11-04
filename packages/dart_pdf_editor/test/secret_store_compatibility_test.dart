import 'dart:convert';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';

import 'support/test_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('in-memory secrets remain isolated by document and store lifetime',
      () async {
    final store = InMemoryFormSecretStore();
    await store.write('first', 'password', 'session-only');
    await store.write('second', 'password', 'other-document');

    final copy = await store.readAll('first');
    copy['password'] = 'modified outside store';
    expect(await store.read('first', 'password'), 'session-only');
    expect(await InMemoryFormSecretStore().readAll('first'), isEmpty);

    await store.clearDocument('first');
    expect(await store.readAll('first'), isEmpty);
    expect(await store.read('second', 'password'), 'other-document');
  });

  test('the editor keeps password-field values out of serialized PDF bytes',
      () async {
    final store = InMemoryFormSecretStore();
    final controller = PdfEditingController(
      buildTestPdf(passwordField: true),
      formSecretStore: store,
    );
    addTearDown(controller.dispose);
    await controller.formSecretsLoaded;

    const secret = 'must-stay-out-of-the-saved-pdf';
    expect(controller.setFormFieldText('password', secret), isTrue);
    await controller.formSecretsSettled;
    expect(controller.acroForm!.fieldNamed('password')!.value, isNull);
    expect(latin1.decode(controller.bytes).contains(secret), isFalse);
    expect(await store.read(controller.formSecretDocumentId!, 'password'),
        secret);

    final reopened = PdfEditingController(
      controller.bytes,
      formSecretStore: store,
    );
    addTearDown(reopened.dispose);
    await reopened.formSecretsLoaded;
    expect(
      reopened.formFieldTextValue(reopened.acroForm!.fieldNamed('password')!),
      secret,
    );
    expect(reopened.isModified, isFalse);

    final newSession = PdfEditingController(
      controller.bytes,
      formSecretStore: InMemoryFormSecretStore(),
    );
    addTearDown(newSession.dispose);
    await newSession.formSecretsLoaded;
    expect(
      newSession.formFieldTextValue(newSession.acroForm!.fieldNamed('password')!),
      isNull,
    );
  });

  test('signing identities work without a platform storage plugin', () async {
    final store = InMemoryIdentityStore();
    final identity = PdfSigningIdentity.generate(name: 'Local test identity');
    await store.save('test', identity);

    final loaded = await store.load('test');
    expect(loaded, isNotNull);
    expect(loaded!.certificate, identity.certificate);
    expect(loaded.privateKey.d, identity.privateKey.d);
    expect(await InMemoryIdentityStore().ids(), isEmpty);

    await store.delete('test');
    expect(await store.ids(), isEmpty);
    expect(await store.load('test'), isNull);
  });
}
