import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crisp_cloud/services/office_document_service.dart';
import 'package:crisp_cloud/services/word_package_preservation.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/widgets/office_editor_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:xml/xml.dart' as xml;

Uint8List _package(Map<String, Uint8List> parts) {
  final archive = Archive();
  for (final part in parts.entries) {
    archive.addFile(ArchiveFile.bytes(part.key, part.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Map<String, Uint8List> _parts(Uint8List bytes) => {
  for (final file in ZipDecoder().decodeBytes(bytes).files)
    if (file.isFile) file.name: Uint8List.fromList(file.content),
};

Uint8List _fixture(String extension) {
  final controller = WordEditorController();
  controller.insertText('Template body.');
  final parts = _parts(controller.saveBytes());
  controller.dispose();
  final contentTypes = xml.XmlDocument.parse(
    utf8.decode(parts['[Content_Types].xml']!),
  );
  contentTypes
      .findAllElements('Override', namespace: '*')
      .firstWhere(
        (part) => part.getAttribute('PartName') == '/word/document.xml',
      )
      .setAttribute(
        'ContentType',
        WordPackagePreservation.contentTypesByExtension[extension]!,
      );
  final macroType = xml.XmlElement(xml.XmlName('Override'), [
    xml.XmlAttribute(xml.XmlName('PartName'), '/word/vbaProject.bin'),
    xml.XmlAttribute(
      xml.XmlName('ContentType'),
      'application/vnd.ms-office.vbaProject',
    ),
  ]);
  if (extension != 'dotx') contentTypes.rootElement.children.add(macroType);
  parts['[Content_Types].xml'] = Uint8List.fromList(
    utf8.encode(contentTypes.toXmlString()),
  );
  if (extension != 'dotx') {
    // Opaque fixture bytes: these must survive untouched, without any VBA execution.
    parts['word/vbaProject.bin'] = Uint8List.fromList([
      0xd0,
      0xcf,
      0x11,
      0xe0,
      0,
      255,
      67,
      7,
    ]);
    parts['word/vbaProjectSignature.bin'] = Uint8List.fromList([9, 8, 7, 6]);
    parts['word/vbaData.xml'] = Uint8List.fromList(
      utf8.encode(
        '<wne:vbaSuppData xmlns:wne="http://schemas.microsoft.com/office/word/2006/wordml"/>',
      ),
    );
    final rels = xml.XmlDocument.parse(
      utf8.decode(parts['word/_rels/document.xml.rels']!),
    );
    rels.rootElement.children.add(
      xml.XmlElement(xml.XmlName('Relationship'), [
        xml.XmlAttribute(xml.XmlName('Id'), 'rIdVba'),
        xml.XmlAttribute(
          xml.XmlName('Type'),
          'http://schemas.microsoft.com/office/2006/relationships/vbaProject',
        ),
        xml.XmlAttribute(xml.XmlName('Target'), 'vbaProject.bin'),
      ]),
    );
    parts['word/_rels/document.xml.rels'] = Uint8List.fromList(
      utf8.encode(rels.toXmlString()),
    );
    parts['word/_rels/vbaProject.bin.rels'] = Uint8List.fromList(
      utf8.encode('''
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="signature" Type="http://schemas.microsoft.com/office/2006/relationships/vbaProjectSignature" Target="vbaProjectSignature.bin"/>
</Relationships>'''),
    );
  }
  return _package(parts);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final extension in ['docm', 'dotm', 'dotx']) {
    test(
      '$extension previews document text and preserves its package type after edits',
      () async {
        final original = _fixture(extension);
        final preview = await parseOfficeDocument(
          original,
          'example.$extension',
        );
        expect(preview.plainText, contains('Template body.'));
        final guard = await WordPackagePreservation.capture(
          original,
          'example.$extension',
        );
        expect(guard, isNotNull);
        final controller = WordEditorController.fromBytes(original);
        addTearDown(controller.dispose);
        controller.insertText('Updated ');
        final saved = await controller.saveBytesAsync();
        await guard!.validateSaved(saved);
        final after = _parts(saved);
        expect(
          utf8.decode(after['[Content_Types].xml']!),
          contains(WordPackagePreservation.contentTypesByExtension[extension]),
        );
        if (extension != 'dotx') {
          for (final path in [
            'word/vbaProject.bin',
            'word/vbaProjectSignature.bin',
            'word/vbaData.xml',
          ]) {
            expect(after[path], orderedEquals(_parts(original)[path]!));
          }
          final rels = xml.XmlDocument.parse(
            utf8.decode(after['word/_rels/document.xml.rels']!),
          );
          expect(
            rels
                .findAllElements('Relationship', namespace: '*')
                .where((rel) => rel.getAttribute('Id') == 'rIdVba')
                .single
                .getAttribute('Target'),
            'vbaProject.bin',
          );
        }
        final reopened = WordEditorController.fromBytes(saved);
        addTearDown(reopened.dispose);
        expect(reopened.document.paragraphs.first.text, contains('Updated '));
        await guard.validateSaved(reopened.saveBytes());
      },
    );
  }

  test('guard rejects changed MIME type, dropped macro, mutation and missing relationship', () async {
    final original = _fixture('dotm');
    final guard = (await WordPackagePreservation.capture(
      original,
      'example.dotm',
    ))!;
    final withoutMacro = _parts(original)..remove('word/vbaProject.bin');
    final changedMacro = _parts(original)
      ..['word/vbaProject.bin'] = Uint8List.fromList([1]);
    final changedType = _parts(original);
    changedType['[Content_Types].xml'] = Uint8List.fromList(
      utf8.encode(
        utf8
            .decode(changedType['[Content_Types].xml']!)
            .replaceAll(
              WordPackagePreservation.contentTypesByExtension['dotm']!,
              'application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml',
            ),
      ),
    );
    final noRelationship = _parts(original);
    final rels = xml.XmlDocument.parse(
      utf8.decode(noRelationship['word/_rels/document.xml.rels']!),
    );
    rels.rootElement.children.removeWhere(
      (node) => node is xml.XmlElement && node.getAttribute('Id') == 'rIdVba',
    );
    noRelationship['word/_rels/document.xml.rels'] = Uint8List.fromList(
      utf8.encode(rels.toXmlString()),
    );
    for (final invalid in [
      withoutMacro,
      changedMacro,
      changedType,
      noRelationship,
    ]) {
      await expectLater(
        guard.validateSaved(_package(invalid)),
        throwsFormatException,
      );
    }
  });

  test(
    'renaming DOCM bytes to DOTM does not enable mismatched editing',
    () async {
      await expectLater(
        WordPackagePreservation.capture(_fixture('docm'), 'template.dotm'),
        throwsFormatException,
      );
    },
  );

  test('package signatures are rejected before editing', () async {
    final signed = _parts(_fixture('dotm'));
    signed['_xmlsignatures/sig1.xml'] = Uint8List.fromList(
      utf8.encode('<Signature/>'),
    );
    await expectLater(
      WordPackagePreservation.capture(_package(signed), 'signed.dotm'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('digitally signed'),
        ),
      ),
    );
  });

  testWidgets('DOTM opens the real Word editor', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: OfficeEditorDialog(
              file: FileItem(
                name: 'template.dotm',
                path: '/template.dotm',
                isFolder: false,
              ),
              side: PanelSide.local,
              bytesOverride: _fixture('dotm'),
            ),
          ),
        ),
      );
      // The bounded archive reader completes real asynchronous work; the Word
      // caret continues animating once loaded. Wait for the editor itself,
      // rather than for all frames to stop or for fake timers to drain.
      final elapsed = Stopwatch()..start();
      while (find.byType(QudsWordEditor).evaluate().isEmpty) {
        await tester.pump(const Duration(milliseconds: 20));
        await Future<void>.delayed(const Duration(milliseconds: 1));
        if (elapsed.elapsed > const Duration(seconds: 15)) {
          throw TimeoutException('DOTM did not open in the Word editor.');
        }
      }
      expect(find.byType(QudsWordEditor), findsOneWidget);
      expect(find.textContaining('cannot be edited safely'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });
}
