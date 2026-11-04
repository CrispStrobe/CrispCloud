import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/preview_media_strings.dart';
import 'package:crisp_cloud/widgets/preview_media.dart';
import 'package:crisp_cloud/widgets/preview_pane.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('web audio control is localized in German', (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: const Scaffold(
          body: WebMediaPlayer(blobUrl: 'blob:test', isAudio: true)),
    ));
    expect(find.text('Audio abspielen'), findsOneWidget);
  });

  testWidgets('empty office text result follows selected language',
      (tester) async {
    late PreviewMediaStrings strings;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(builder: (context) {
        strings = PreviewMediaStrings(context);
        return const SizedBox();
      }),
    ));
    final archive = Archive()
      ..addFile(ArchiveFile.bytes('placeholder.txt', [1]));
    final zip = Uint8List.fromList(ZipEncoder().encode(archive));
    final text =
        await extractOfficeText(zip, 'document.docx', strings: strings);
    expect(text, '(Kein Textinhalt gefunden)');
  });

  testWidgets('media control labels are available in every locale',
      (tester) async {
    for (final locale in AppLocalizations.supportedLocales) {
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(
            builder: (context) =>
                Text(PreviewMediaStrings(context).text('pause'))),
      ));
      expect(find.byType(Text), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('preview error is translated without reading oversized files',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
      locale: const Locale('de'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
          body: PreviewPane(
        file:
            FileItem(name: 'big.txt', isFolder: false, size: 10 * 1024 * 1024),
        side: PanelSide.local,
      )),
    )));
    expect(
        find.textContaining('Datei für die Vorschau zu groß'), findsOneWidget);
  });
}
