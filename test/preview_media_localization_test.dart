import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/preview_media_strings.dart';
import 'package:crisp_cloud/widgets/preview_media.dart';
import 'package:crisp_cloud/widgets/preview_pane.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/workflow_fake_client.dart';
import 'support/workspace_fixture.dart';

class _OversizedPreviewClient extends WorkflowFakeClient {
  int reads = 0;

  @override
  Future<Map<String, dynamic>> listPath(String path) async => {
    'folders': <Map<String, dynamic>>[],
    'files': [
      {'name': 'big.txt', 'path': '/big.txt', 'size': 10 * 1024 * 1024},
    ],
  };

  @override
  Future<Uint8List> downloadFileBytes(
    String path, {
    Function(int, int)? onProgress,
  }) async {
    reads++;
    throw StateError('An oversized preview must not read file contents.');
  }
}

void main() {
  test('Word side previews follow the package main-part relationship', () async {
    final archive = Archive()
      ..addFile(ArchiveFile.bytes('_rels/.rels', utf8.encode('''
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="main"
    Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"
    Target="/office/text/main.xml"/>
</Relationships>
''')))
      ..addFile(ArchiveFile.bytes('office/text/main.xml', utf8.encode('''
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body><w:p><w:r><w:t>Relocated Word body</w:t></w:r></w:p></w:body>
</w:document>
''')))
      ..addFile(ArchiveFile.bytes('word/document.xml', utf8.encode('''
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body><w:p><w:r><w:t>Unused fallback body</w:t></w:r></w:p></w:body>
</w:document>
''')));
    final zip = Uint8List.fromList(ZipEncoder().encode(archive));

    for (final extension in ['docx', 'docm', 'dotx', 'dotm']) {
      final text = await extractOfficeText(zip, 'document.$extension');
      expect(text.trim(), 'Relocated Word body', reason: extension);
    }
  });

  test('Word side previews retain the conventional-part fallback', () async {
    final archive = Archive()
      ..addFile(ArchiveFile.bytes('word/document.xml', utf8.encode('''
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body><w:p><w:r><w:t>Conventional Word body</w:t></w:r></w:p></w:body>
</w:document>
''')));
    final zip = Uint8List.fromList(ZipEncoder().encode(archive));

    expect(
      (await extractOfficeText(zip, 'document.docx')).trim(),
      'Conventional Word body',
    );
  });


  testWidgets('web audio control is localized in German', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const Scaffold(
          body: WebMediaPlayer(blobUrl: 'blob:test', isAudio: true),
        ),
      ),
    );
    expect(find.text('Audio abspielen'), findsOneWidget);
  });

  testWidgets('empty office text result follows selected language', (
    tester,
  ) async {
    late PreviewMediaStrings strings;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(
          builder: (context) {
            strings = PreviewMediaStrings(context);
            return const SizedBox();
          },
        ),
      ),
    );
    final archive = Archive()
      ..addFile(ArchiveFile.bytes('placeholder.txt', [1]));
    final zip = Uint8List.fromList(ZipEncoder().encode(archive));
    final text = await extractOfficeText(
      zip,
      'document.docx',
      strings: strings,
    );
    expect(text, '(Kein Textinhalt gefunden)');
  });

  testWidgets('media control labels are available in every locale', (
    tester,
  ) async {
    for (final locale in AppLocalizations.supportedLocales) {
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Builder(
            builder: (context) =>
                Text(PreviewMediaStrings(context).text('pause')),
          ),
        ),
      );
      expect(find.byType(Text), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('preview error is translated without reading oversized files', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final cloud = _OversizedPreviewClient();
    final container = ProviderContainer(
      overrides: [authProvider.overrideWith((_) => WorkspaceTestAuth(cloud))],
    );
    addTearDown(container.dispose);
    final panel = container.read(panelProvider(PanelSide.remote));
    await panel.refresh();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('de'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: PreviewPane(
              file: panel.files!.single,
              side: PanelSide.remote,
            ),
          ),
        ),
      ),
    );
    expect(
      find.textContaining('Datei für die Vorschau zu groß'),
      findsOneWidget,
    );
    expect(cloud.reads, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
