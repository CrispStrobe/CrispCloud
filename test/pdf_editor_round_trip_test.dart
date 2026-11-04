import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';

/// Engine-level regression checks. The independent Python verifier reads the
/// emitted PDFs with pypdf. Redaction remains disabled in the product: the
/// partial Form XObject test records a known upstream limitation.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fixtureDirectory = Directory('test/fixtures/pdf_editor');
  final outputDirectory = Directory(
    Platform.environment['PDF_EDITOR_VERIFY_DIR'] ??
        'build/pdf_editor_verification',
  );
  late final Map<String, dynamic> manifest;

  String value(String key) => manifest[key] as String;

  Uint8List fixture(String key) =>
      File('${fixtureDirectory.path}/${value(key)}').readAsBytesSync();

  void writeOutput(String name, Uint8List bytes) {
    File('${outputDirectory.path}/$name').writeAsBytesSync(bytes, flush: true);
  }

  PdfEditingController open(Uint8List bytes, {String password = ''}) {
    final controller = PdfEditingController(
      bytes,
      password: password,
      formSecretStore: InMemoryFormSecretStore(),
    );
    addTearDown(controller.dispose);
    return controller;
  }

  void editDocument(PdfEditingController controller) {
    expect(controller.document.pageCount, 2);
    expect(controller.document.page(1).rotation, 90);
    expect(
      controller.setFormFieldText(
        value('field_name'),
        value('edited_field_value'),
      ),
      isTrue,
    );
    controller.addNote(0, 450, 500, value('annotation_text'));
    controller.movePage(0, 1);
    expect(controller.document.page(0).rotation, 90);
    expect(controller.isModified, isTrue);
  }

  PdfRect redactionRectangle() {
    final coordinates = (manifest['redaction_rect'] as List)
        .cast<num>()
        .map((value) => value.toDouble())
        .toList();
    return PdfRect(
      coordinates[0],
      coordinates[1],
      coordinates[2],
      coordinates[3],
    );
  }

  setUpAll(() {
    manifest = jsonDecode(
      File('${fixtureDirectory.path}/manifest.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    outputDirectory.createSync(recursive: true);
    // A rerun must never let the independent verifier accept stale output.
    for (final filename in [
      'round_trip.pdf',
      'encrypted_edited.pdf',
      'redacted.pdf',
      'partial_form_redaction.pdf',
      'verification.json',
    ]) {
      final file = File('${outputDirectory.path}/$filename');
      if (file.existsSync()) file.deleteSync();
    }
  });

  test(
    'form edits, annotation, rotation and page reorder survive reopening',
    () async {
      final controller = open(fixture('plain_fixture'));
      await controller.formSecretsLoaded;
      editDocument(controller);

      final reopened = open(controller.bytes);
      expect(reopened.document.pageCount, 2);
      expect(reopened.document.page(0).rotation, 90);
      expect(
        reopened.acroForm!.fieldNamed(value('field_name'))!.value,
        value('edited_field_value'),
      );
      expect(
        reopened.document
            .page(1)
            .annotations
            .any(
              (annotation) =>
                  annotation.subtype == 'Text' &&
                  annotation.contents == value('annotation_text'),
            ),
        isTrue,
      );
      writeOutput('round_trip.pdf', controller.bytes);
    },
  );

  test(
    'saving an edited AES-256 document preserves its password protection',
    () async {
      final original = fixture('encrypted_fixture');
      expect(
        () => PdfDocument.open(original),
        throwsA(isA<CosPasswordException>()),
      );
      final controller = open(original, password: value('password'));
      await controller.formSecretsLoaded;
      editDocument(controller);

      expect(controller.document.cos.isEncrypted, isTrue);
      expect(
        () => PdfDocument.open(controller.bytes, password: 'incorrect'),
        throwsA(isA<CosPasswordException>()),
      );
      final reopened = open(controller.bytes, password: value('password'));
      expect(reopened.document.cos.isEncrypted, isTrue);
      expect(
        reopened.acroForm!.fieldNamed(value('field_name'))!.value,
        value('edited_field_value'),
      );
      writeOutput('encrypted_edited.pdf', controller.bytes);
    },
  );

  test(
    'text-only redaction removes the covered stream text and undo history',
    () {
      final controller = open(fixture('redaction_fixture'));
      controller.addRedaction(0, redactionRectangle());
      expect(controller.hasRedactionMarks, isTrue);
      expect(controller.applyRedactions(), isTrue);
      expect(controller.canUndo, isFalse);
      expect(controller.revisionCount, 1);

      final saved = PdfDocument.open(controller.bytes);
      final content = latin1.decode(saved.page(0).contentBytes());
      expect(content, isNot(contains(value('redaction_secret'))));
      expect(content, contains(value('redaction_public')));
      expect(
        saved
            .page(0)
            .annotations
            .where((annotation) => annotation.subtype == 'Redact'),
        isEmpty,
      );
      writeOutput('redacted.pdf', controller.bytes);
    },
  );

  test('known limitation: partial Form XObject redaction retains its text', () {
    final controller = open(fixture('partial_form_fixture'));
    controller.addRedaction(0, redactionRectangle());
    expect(controller.applyRedactions(), isTrue);
    final saved = PdfDocument.open(controller.bytes);
    final xobjects = saved.cos.resolve(saved.page(0).resources['XObject']);
    expect(xobjects, isA<CosDictionary>());
    final retained = (xobjects as CosDictionary).entries.values.any((
      reference,
    ) {
      final object = saved.cos.resolve(reference);
      return object is CosStream &&
          latin1
              .decode(saved.cos.decodeStreamData(object))
              .contains(value('partial_form_secret'));
    });
    expect(
      retained,
      isTrue,
      reason:
          'An overlay does not remove text from a partly covered Form; '
          'production redaction must remain disabled.',
    );
    writeOutput('partial_form_redaction.pdf', controller.bytes);
  });
}
