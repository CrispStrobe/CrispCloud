// Copied into an isolated app by tool/prepare_native_host_smoke.py. Run on a
// real Android/iOS/desktop Flutter target, never on flutter_tester.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crisp_ebook/crisp_ebook.dart';
import 'package:crisp_ebook_conversion/crisp_ebook_conversion.dart';
import 'package:crisp_ebook_reader/crisp_ebook_reader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

String chapter(String body) =>
    '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Shelf</title>'
    '</head><body>$body</body></html>';

EpubDocument publication() {
  final document = EpubDocument.create(
    title: 'Cross-platform library',
    authors: ['CrispCloud tests'],
  );
  document.updateText(
    document.chapters.first.path,
    chapter('<h1 id="first">First shelf</h1><p>Local café 日本語 Ελληνικά.</p>'
        '${List.generate(100, (index) => '<p>Library paragraph $index. '
            'A thousand stories stay on these local shelves.</p>').join()}'),
  );
  document.addChapter(
    title: 'Second shelf',
    xhtml: chapter('<h1 id="second">Second shelf</h1>'
        '<p>Cross-platform needle café 日本語.</p>'),
  );
  return document;
}

Uint8List fictionBook() => Uint8List.fromList(utf8.encode('''
<?xml version="1.0" encoding="utf-8"?>
<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0"
 xmlns:l="http://www.w3.org/1999/xlink">
<description><title-info><genre>prose_contemporary</genre>
<author><nickname>CrispCloud tests</nickname></author>
<book-title>Cross-platform library</book-title><lang>en</lang></title-info>
<document-info><author><nickname>CrispCloud tests</nickname></author>
<date value="2026-01-01">2026-01-01</date><id>crisp-native-smoke</id>
<version>1.0</version></document-info></description>
<body><section id="first"><title><p>First shelf</p></title>
<p>Local café 日本語 Ελληνικά.</p>
${List.generate(100, (index) => '<p>Library paragraph $index. '
        'A thousand stories stay on these local shelves.</p>').join()}
</section><section id="second"><title><p>Second shelf</p></title>
<p>Cross-platform needle café 日本語.</p></section></body></FictionBook>
'''
    .trim()));

Future<void> until(WidgetTester tester, bool Function() condition,
    List<String> errors, String reason) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  do {
    await tester.pump(const Duration(milliseconds: 100));
    if (errors.isNotEmpty) fail(errors.join('\n'));
    if (condition()) return;
  } while (DateTime.now().isBefore(deadline));
  fail(reason);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'real platform reading, conversion, editing and offline isolation',
      (tester) async {
    expect(
        Platform.isAndroid ||
            Platform.isIOS ||
            Platform.isMacOS ||
            Platform.isWindows ||
            Platform.isLinux,
        isTrue);
    debugPrint('ebook host: ${Platform.operatingSystem} '
        '${Platform.operatingSystemVersion}');

    final document = publication();
    final input = document.toBytes();
    final baseline = Uint8List.fromList(input);
    final converter = KindlingConverter();
    final capability = await converter.capabilities();
    expect(capability.available, isTrue, reason: capability.reason);
    expect(capability.runtime, EbookConversionRuntime.native);
    expect(capability.canExportAzw3 && capability.canExportLegacyMobi, isTrue);

    final publications = <String, Uint8List>{'library.epub': input};
    for (final format in KindleExportFormat.values) {
      final converted = await converter.exportKindle(input, format: format);
      expect(ascii.decode(converted.bytes.sublist(60, 68)), 'BOOKMOBI');
      publications['library.${format.extension}'] = converted.bytes;
    }
    final fb2 = fictionBook();
    publications['library.fb2'] = fb2;
    publications['library.fbz'] = ZipEncoder().encodeBytes(
      Archive()..addFile(ArchiveFile.bytes('library.fb2', fb2)),
    );
    expect(input, baseline);

    final controller = CrispEbookController();
    final errors = <String>[];
    final navigator = GlobalKey<NavigatorState>();
    var revision = 0;
    Future<void> open(Uint8List bytes, String name, {String? location}) async {
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        home: Scaffold(
          body: SafeArea(
            child: CrispEbookReader(
              key: ValueKey(++revision),
              bytes: bytes,
              filename: name,
              controller: controller,
              initialLocation: location,
              onError: errors.add,
            ),
          ),
        ),
      ));
      await until(
          tester,
          () => controller.isReady && controller.location != null,
          errors,
          'The actual platform host did not open $name.');
    }

    Future<void> close() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 200));
      expect(controller.isReady, isFalse);
    }

    for (final entry in publications.entries) {
      debugPrint('ebook host: opening ${entry.key}');
      final unchanged = Uint8List.fromList(entry.value);
      await open(entry.value, entry.key);
      expect(controller.bookInfo!.title, 'Cross-platform library');
      expect(controller.bookInfo!.authors, contains('CrispCloud tests'));
      expect(controller.bookInfo!.sectionCount, greaterThanOrEqualTo(2));
      final oldLocation = controller.location!.cfi;
      await controller.next();
      await until(tester, () => controller.location!.cfi != oldLocation, errors,
          'Native page navigation did not change location.');
      await controller.previous();

      final hits = await controller.search('Cross-platform needle');
      expect(hits, isNotEmpty, reason: entry.key);
      expect(hits.first.sectionIndex, greaterThan(0));
      expect(hits.first.cfi, startsWith('epubcfi('));
      await controller.goTo(hits.first.cfi);
      await until(
          tester,
          () => controller.location!.sectionIndex == hits.first.sectionIndex,
          errors,
          'Search did not navigate to its actual chapter.');
      await controller.clearSearch();
      final savedLocation = controller.location!.cfi;
      await controller.addHighlight(EbookHighlight(
        id: 'native-check',
        cfi: hits.first.cfi,
        note: 'Native note café',
      ));
      await controller.setAppearance(const EbookAppearance(
        fontSize: 21,
        theme: 'sepia',
        maxColumnCount: 1,
        usePublisherStyles: false,
      ));
      await controller.removeHighlight('native-check');

      final normalized = await controller.exportPublication();
      final imported = EpubDocument.fromPublication(normalized.toJson());
      expect(imported.title, 'Cross-platform library');
      expect(imported.validate().where((issue) => issue.isError), isEmpty);
      expect(
          imported.chapters.map((item) => imported.readText(item.path)).join(),
          contains('日本語'));

      // Confirm Flutter dialogs retain text input and obscure the platform view
      // on the actual target, including systems that use native composition.
      final modal = showDialog<void>(
        context: navigator.currentContext!,
        builder: (context) => AlertDialog(
          title: const Text('Reader note'),
          content: const TextField(autofocus: true),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'))
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Note café 日本語');
      expect(find.text('Note café 日本語'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await modal;
      await close();
      expect(entry.value, unchanged);

      await open(entry.value, entry.key, location: savedLocation);
      await until(
          tester,
          () => controller.location!.sectionIndex == hits.first.sectionIndex,
          errors,
          'The native host did not restore the saved content anchor.');
      await close();
      debugPrint('ebook host: passed ${entry.key}');
    }

    document.updateMetadata(title: 'Edited native library');
    final last = document.chapters.last.path;
    document.updateText(
        last,
        document
            .readText(last)
            .replaceFirst('Cross-platform needle', 'Edited native passage'));
    final edited = document.toBytes();
    final reopened = EpubDocument.open(edited);
    expect(reopened.title, 'Edited native library');
    expect(input, baseline);
    // The native export must contain edited body text, not only new metadata.
    final editedKindle = await converter.exportKindle(edited);
    await open(editedKindle.bytes, 'edited.azw3');
    expect(controller.bookInfo!.title, 'Edited native library');
    expect(await controller.search('Edited native passage'), isNotEmpty);
    expect(await controller.search('Cross-platform needle'), isEmpty);
    await close();

    final requests = <Uri>[];
    final probe = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => probe.close(force: true));
    probe.listen((request) {
      requests.add(request.uri);
      request.response.statusCode = HttpStatus.forbidden;
      request.response.close();
    });
    final remote = 'http://127.0.0.1:${probe.port}';
    final hostile = publication();
    final path = hostile.chapters.first.path;
    hostile.updateText(
        path,
        chapter('<h1>Offline isolation</h1>'
            '<script>fetch("$remote/script");top.location="$remote/top"</script>'
            '<img src="$remote/image" alt="remote"/>'
            '<iframe src="$remote/frame"></iframe>'
            '<style>body { background-image: url("$remote/style"); }</style>'
            '<p>Harmless local text.</p>'));
    await open(hostile.toBytes(), 'hostile.epub');
    expect(await controller.search('Harmless local text'), isNotEmpty);
    await tester.pump(const Duration(milliseconds: 700));
    expect(requests, isEmpty,
        reason: 'A publication escaped the native offline resource boundary.');
    await close();
    controller.dispose();
    expect(errors, isEmpty);
    debugPrint('ebook host: all runtime contracts passed');
  }, timeout: const Timeout(Duration(minutes: 12)));
}
