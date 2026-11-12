import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/file_cache_service.dart';
import 'package:crisp_cloud/services/office_document_service.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/widgets/office_editor_dialog.dart';
import 'package:crisp_cloud/widgets/office_editor_ribbon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart'
    hide WordPackagePreservation;
import 'package:quds_office_engine/quds_office_engine.dart'
    show WordPackagePreservation;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart' as xml;

import 'support/workflow_fake_client.dart';
import 'support/workspace_fixture.dart';

class _TemplateCloud extends WorkflowFakeClient {
  int uploadAttempts = 0;

  @override
  Future<void> uploadFile(
    List<int> bytes,
    String name,
    String targetPath, {
    Function(int, int)? onProgress,
  }) async {
    uploadAttempts++;
    await super.uploadFile(bytes, name, targetPath, onProgress: onProgress);
  }
}

class _Cache extends FileCacheService {
  @override
  Future<void> remove(String remotePath, String provider) async {}
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() complete,
  String reason,
) async {
  final elapsed = Stopwatch()..start();
  do {
    await tester.pump(const Duration(milliseconds: 20));
    await Future<void>.delayed(const Duration(milliseconds: 1));
    if (elapsed.elapsed > const Duration(seconds: 15)) {
      throw TimeoutException(reason);
    }
  } while (!complete());
  await tester.pump();
}

OfficeEditorRibbon _ribbon(WidgetTester tester) =>
    tester.widget<OfficeEditorRibbon>(find.byType(OfficeEditorRibbon));

Future<WordEditorController> _openHost(
  WidgetTester tester,
  _TemplateCloud cloud,
  String name,
  Uint8List original,
) async {
  SharedPreferences.setMockInitialValues({});
  cloud.put('/$name', original);
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith((_) => WorkspaceTestAuth(cloud)),
      fileCacheProvider.overrideWithValue(_Cache()),
    ],
  );
  addTearDown(container.dispose);
  final panel = container.read(panelProvider(PanelSide.remote));
  await panel.refresh();
  final file = panel.files!.single;
  expect(panel.originForOperation(file), isNotNull);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: OfficeEditorDialog(file: file, side: PanelSide.remote),
      ),
    ),
  );
  await _pumpUntil(
    tester,
    () => find.byType(QudsWordEditor).evaluate().isNotEmpty,
    'The real Office host did not open $name.',
  );
  return tester.widget<QudsWordEditor>(find.byType(QudsWordEditor)).controller;
}

Future<void> _runHostCase(
  WidgetTester tester,
  Future<void> Function() body,
) async {
  (Object, StackTrace)? failure;
  await tester.runAsync(() async {
    try {
      await body();
    } catch (error, stack) {
      failure = (error, stack);
    }
  });
  if (failure case final error?) {
    Error.throwWithStackTrace(error.$1, error.$2);
  }
}

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
  if (extension == 'docm' || extension == 'dotm')
    contentTypes.rootElement.children.add(macroType);
  parts['[Content_Types].xml'] = Uint8List.fromList(
    utf8.encode(contentTypes.toXmlString()),
  );
  if (extension == 'docm' || extension == 'dotm') {
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

void _assertHostPackage(Uint8List original, Uint8List saved, String extension) {
  final before = _parts(original);
  final after = _parts(saved);
  final types = xml.XmlDocument.parse(
    utf8.decode(after['[Content_Types].xml']!),
  );
  const expectedTypes = {
    'docm': 'application/vnd.ms-word.document.macroEnabled.main+xml',
    'dotx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.template.main+xml',
    'dotm': 'application/vnd.ms-word.template.macroEnabledTemplate.main+xml',
  };
  expect(
    types
        .findAllElements('Override', namespace: '*')
        .singleWhere(
          (node) => node.getAttribute('PartName') == '/word/document.xml',
        )
        .getAttribute('ContentType'),
    expectedTypes[extension],
  );
  final document = xml.XmlDocument.parse(
    utf8.decode(after['word/document.xml']!),
  );
  expect(
    document
        .findAllElements(
          't',
          namespace:
              'http://schemas.openxmlformats.org/wordprocessingml/2006/main',
        )
        .map((node) => node.innerText)
        .join(),
    'Host-saved Template body.',
  );
  if (extension == 'dotx') {
    expect(after.containsKey('word/vbaProject.bin'), isFalse);
    return;
  }
  for (final part in [
    'word/vbaProject.bin',
    'word/vbaProjectSignature.bin',
    'word/vbaData.xml',
  ]) {
    expect(after[part], orderedEquals(before[part]!), reason: part);
  }
  final relationships = xml.XmlDocument.parse(
    utf8.decode(after['word/_rels/document.xml.rels']!),
  );
  final macro = relationships
      .findAllElements('Relationship', namespace: '*')
      .singleWhere((node) => node.getAttribute('Id') == 'rIdVba');
  expect(macro.getAttribute('Target'), 'vbaProject.bin');
  expect(
    macro.getAttribute('Type'),
    'http://schemas.microsoft.com/office/2006/relationships/vbaProject',
  );
  final signature = xml.XmlDocument.parse(
    utf8.decode(after['word/_rels/vbaProject.bin.rels']!),
  ).findAllElements('Relationship', namespace: '*').single;
  expect(signature.getAttribute('Id'), 'signature');
  expect(signature.getAttribute('Target'), 'vbaProjectSignature.bin');
  expect(
    signature.getAttribute('Type'),
    'http://schemas.microsoft.com/office/2006/relationships/vbaProjectSignature',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final extension in ['docm', 'dotm', 'dotx']) {
    test('$extension preview routes through the shared Word format', () async {
      final preview = await parseOfficeDocument(
        _fixture(extension),
        'example.$extension',
      );
      expect(preview.plainText, contains('Template body.'));
    });
    testWidgets(
      'actual host uploads edited $extension with preserved package',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await _runHostCase(tester, () async {
          final cloud = _TemplateCloud();
          final original = _fixture(extension);
          final name = 'template.$extension';
          final controller = await _openHost(tester, cloud, name, original);
          controller.jumpToParagraph(0);
          controller.insertText('Host-saved ');
          await tester.pump();
          expect(_ribbon(tester).dirty, isTrue);
          await tester.tap(find.byTooltip('Save'));
          await _pumpUntil(
            tester,
            () => cloud.writes.length == 1 && !_ribbon(tester).saving,
            'The actual host did not upload the edited $extension.',
          );
          expect(cloud.uploadAttempts, 1);
          expect(cloud.writes.single, '/$name');
          expect(controller.isDirty, isFalse);
          expect(_ribbon(tester).dirty, isFalse);
          final saved = cloud.files['/$name']!;
          _assertHostPackage(original, saved, extension);
          final file = File(
            'build/fidelity-host/word-$extension-save.$extension',
          );
          file.parent.createSync(recursive: true);
          file.writeAsBytesSync(saved);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        });
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('actual host blocks a changed macro part before upload', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _runHostCase(tester, () async {
      final cloud = _TemplateCloud();
      final original = _fixture('dotm');
      final controller = await _openHost(
        tester,
        cloud,
        'template.dotm',
        original,
      );
      controller.insertText('Retain this unsaved edit ');
      // Simulate a serializer/package-preservation regression at its real
      // imported-part boundary; the host must reject these bytes before upload.
      controller.document.package!
          .getPart('/word/vbaProject.bin')!
          .writeBytes(Uint8List.fromList([1, 2, 3]));
      await tester.pump();
      await tester.tap(find.byTooltip('Save'));
      await _pumpUntil(
        tester,
        () =>
            !_ribbon(tester).saving &&
            find
                .textContaining(
                  'Saving would change a preserved Word binary or macro part',
                )
                .evaluate()
                .isNotEmpty,
        'The host did not surface the failed Word preservation check.',
      );
      expect(cloud.uploadAttempts, 0);
      expect(cloud.writes, isEmpty);
      expect(cloud.files['/template.dotm'], orderedEquals(original));
      expect(controller.isDirty, isTrue);
      expect(_ribbon(tester).dirty, isTrue);
      expect(
        controller.document.paragraphs.first.text,
        contains('Retain this unsaved edit '),
      );
      expect(find.byType(QudsWordEditor), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
    expect(tester.takeException(), isNull);
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
      // The shared engine and host load asynchronously; the Word
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

  for (final extension in ['docx', 'dotm']) {
    test('$extension package signatures are rejected before editing', () async {
      final signed = _parts(_fixture(extension));
      signed['_xmlsignatures/sig1.xml'] = Uint8List.fromList(
        utf8.encode('<Signature/>'),
      );
      await expectLater(
        WordPackagePreservation.capture(_package(signed), 'signed.$extension'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('digitally signed'),
          ),
        ),
      );
    });
  }

  test(
    'DOCX embedded object bytes and their relationship remain protected',
    () async {
      final original = _parts(_fixture('docx'));
      original['word/embeddings/object.xlsx'] = Uint8List.fromList([1, 3, 5]);
      final rels = xml.XmlDocument.parse(
        utf8.decode(original['word/_rels/document.xml.rels']!),
      );
      rels.rootElement.children.add(
        xml.XmlElement(xml.XmlName('Relationship'), [
          xml.XmlAttribute(xml.XmlName('Id'), 'object'),
          xml.XmlAttribute(
            xml.XmlName('Type'),
            'http://schemas.openxmlformats.org/officeDocument/2006/relationships/package',
          ),
          xml.XmlAttribute(xml.XmlName('Target'), 'embeddings/object.xlsx'),
        ]),
      );
      original['word/_rels/document.xml.rels'] = Uint8List.fromList(
        utf8.encode(rels.toXmlString()),
      );
      final guard = (await WordPackagePreservation.capture(
        _package(original),
        'copy.docx',
      ))!;
      await guard.validateSaved(_package(original));
      final changed = Map<String, Uint8List>.of(original)
        ..['word/embeddings/object.xlsx'] = Uint8List.fromList([9]);
      await expectLater(
        guard.validateSaved(_package(changed)),
        throwsFormatException,
      );
      final missingRelationship = Map<String, Uint8List>.of(original);
      rels.rootElement.children.removeWhere(
        (node) => node is xml.XmlElement && node.getAttribute('Id') == 'object',
      );
      missingRelationship['word/_rels/document.xml.rels'] = Uint8List.fromList(
        utf8.encode(rels.toXmlString()),
      );
      await expectLater(
        guard.validateSaved(_package(missingRelationship)),
        throwsFormatException,
      );
    },
  );

  test('DOCX signature parts outside the usual folder are rejected by type or relationship', () async {
    final original = _parts(_fixture('docx'));
    final byType = Map<String, Uint8List>.of(original);
    final types = xml.XmlDocument.parse(
      utf8.decode(byType['[Content_Types].xml']!),
    );
    types.rootElement.children.add(
      xml.XmlElement(xml.XmlName('Override'), [
        xml.XmlAttribute(xml.XmlName('PartName'), '/proof/signature.xml'),
        xml.XmlAttribute(
          xml.XmlName('ContentType'),
          'application/vnd.openxmlformats-package.digital-signature-xmlsignature+xml',
        ),
      ]),
    );
    byType['[Content_Types].xml'] = Uint8List.fromList(
      utf8.encode(types.toXmlString()),
    );
    byType['proof/signature.xml'] = Uint8List.fromList(
      utf8.encode('<Signature/>'),
    );
    await expectLater(
      WordPackagePreservation.capture(_package(byType), 'copy.docx'),
      throwsFormatException,
    );
    final byRelationship = Map<String, Uint8List>.of(original);
    final relationships = xml.XmlDocument.parse(
      utf8.decode(byRelationship['_rels/.rels']!),
    );
    relationships.rootElement.children.add(
      xml.XmlElement(xml.XmlName('Relationship'), [
        xml.XmlAttribute(xml.XmlName('Id'), 'origin'),
        xml.XmlAttribute(
          xml.XmlName('Type'),
          'http://schemas.openxmlformats.org/package/2006/relationships/digital-signature/origin',
        ),
        xml.XmlAttribute(xml.XmlName('Target'), 'proof/origin.sigs'),
      ]),
    );
    byRelationship['_rels/.rels'] = Uint8List.fromList(
      utf8.encode(relationships.toXmlString()),
    );
    byRelationship['proof/origin.sigs'] = Uint8List(0);
    await expectLater(
      WordPackagePreservation.capture(_package(byRelationship), 'copy.docx'),
      throwsFormatException,
    );
  });
}
