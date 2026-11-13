// test/widget/internal_viewer_widget_test.dart
//
// Widget tests for the F3 internal viewer dialog.
// Uses [InternalViewerDialog.bytesOverride] so no real files/providers are
// needed, covering auto-detection, mode switching, search, archives and the
// single-file gzip expansion path.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/services/file_bytes_loader.dart';
import 'package:crisp_cloud/services/viewer_search_service.dart';
import 'package:crisp_cloud/widgets/hex_viewer.dart';
import 'package:crisp_cloud/widgets/internal_viewer_dialog.dart';
import 'package:crisp_cloud/widgets/internal_viewer_views.dart';
import 'package:crisp_cloud/widgets/pptx_slide_viewer.dart';
import 'package:crisp_cloud/widgets/preview_media.dart';
import 'package:crisp_cloud/widgets/xml_tree_view.dart';

Widget _wrap(Widget child) {
  return ProviderScope(child: MaterialApp(home: child));
}

Future<void> _pumpViewer(
  WidgetTester tester,
  Uint8List bytes, {
  String name = 'sample.xyz',
}) async {
  await tester.pumpWidget(
    _wrap(
      InternalViewerDialog(
        file: FileItem(name: name, isFolder: false, size: bytes.length),
        side: PanelSide.local,
        bytesOverride: bytes,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapChip(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(ChoiceChip, label));
  await tester.pumpAndSettle();
}

void main() {
  group('text mode', () {
    testWidgets(
      'literal whitespace and 0x text, case toggle and edited-query reset agree',
      (tester) async {
        await _pumpViewer(
          tester,
          Uint8List.fromList(utf8.encode('Needle needle\n0x41 A\n x \nx\n')),
        );
        await tester.tap(find.byTooltip('Search (Ctrl+F)'));
        await tester.pumpAndSettle();
        final input = find.byKey(const ValueKey('viewer-search-input'));
        Future<void> search(String query) async {
          await tester.enterText(input, query);
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pumpAndSettle();
        }

        await search('needle');
        expect(find.text('1/2'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('viewer-match-case')));
        await tester.pumpAndSettle();
        expect(find.text('1/1'), findsOneWidget);
        await search('0x41');
        expect(find.text('1/1'), findsOneWidget);
        await search(' x ');
        expect(find.text('1/1'), findsOneWidget);
        await tester.enterText(input, 'missing');
        await tester.pump();
        expect(find.text('0/0'), findsOneWidget);
        final next = tester.widget<IconButton>(
          find.byWidgetPredicate(
            (widget) =>
                widget is IconButton && widget.tooltip == 'Next match (F3)',
          ),
        );
        expect(next.onPressed, isNull);
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        expect(find.text('0/0'), findsOneWidget);
      },
    );

    testWidgets(
      'every match remains reachable past the bounded result page in both directions',
      (tester) async {
        await _pumpViewer(
          tester,
          Uint8List.fromList(
            utf8.encode(List.filled(2002, 'needle').join('\n')),
          ),
        );
        await tester.tap(find.byTooltip('Search (Ctrl+F)'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('viewer-search-input')),
          'needle',
        );
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        expect(find.text('1/2002'), findsOneWidget);
        Future<void> previous() async {
          await tester.tap(find.byTooltip('Previous match (Shift+F3)'));
          await tester.pumpAndSettle();
        }

        await previous();
        expect(find.text('2002/2002'), findsOneWidget);
        await previous();
        expect(find.text('2001/2002'), findsOneWidget);
        await previous();
        expect(find.text('2000/2002'), findsOneWidget);
        await tester.tap(find.byTooltip('Next match (F3)'));
        await tester.pumpAndSettle();
        expect(find.text('2001/2002'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'reload cancels an active scan and any pending query debounce',
      (tester) async {
        final data = Uint8List(4 * 1024 * 1024);
        data.setAll(0, utf8.encode('needle\n'));
        await _pumpViewer(tester, data, name: 'sample.txt');
        await tester.tap(find.byTooltip('Search (Ctrl+F)'));
        await tester.pumpAndSettle();
        final input = find.byKey(const ValueKey('viewer-search-input'));
        await tester.enterText(input, 'needle');
        tester.widget<TextField>(input).onSubmitted!('needle');
        await tester.pump();
        expect(find.byTooltip('Stop search'), findsOneWidget);
        await tester.tap(find.byTooltip('Reload (F5)'));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Stop search'), findsNothing);
        expect(tester.widget<TextField>(input).controller!.text, isEmpty);
        expect(find.text('0/0'), findsOneWidget);
        expect(find.textContaining('disposed'), findsNothing);

        await tester.enterText(input, 'needle');
        await tester.tap(find.byTooltip('Reload (F5)'));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        expect(find.text('0/0'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('renders decoded lines for a text file', (tester) async {
      await _pumpViewer(
        tester,
        Uint8List.fromList(utf8.encode('hello\nworld\n')),
      );

      expect(find.text('hello'), findsOneWidget);
      expect(find.text('world'), findsOneWidget);
      expect(find.textContaining('Text'), findsWidgets);
    });

    testWidgets('search finds and counts text matches', (tester) async {
      await _pumpViewer(
        tester,
        Uint8List.fromList(utf8.encode('alpha beta\nbeta gamma\n')),
      );

      await tester.tap(find.byTooltip('Search (Ctrl+F)'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'beta');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.textContaining('1/2'), findsWidgets);
    });
  });

  group('byte modes', () {
    final bytes = Uint8List.fromList(<int>[0x41, 0x00, 0x42, 0x0A, 0x43]);

    testWidgets('ASCII mode keeps control bytes visible as dots', (
      tester,
    ) async {
      await _pumpViewer(tester, bytes);
      await _tapChip(tester, 'ASCII');

      expect(find.text('A·B'), findsOneWidget);
    });

    testWidgets('Binary mode keeps only printable ASCII', (tester) async {
      await _pumpViewer(tester, bytes);
      await _tapChip(tester, 'Binary');

      expect(find.text('A.B'), findsOneWidget);
    });

    testWidgets('Hex mode renders the dump for any file type', (tester) async {
      await _pumpViewer(
        tester,
        Uint8List.fromList(List<int>.generate(32, (i) => i)),
      );
      await _tapChip(tester, 'Hex');

      expect(find.byType(HexViewer), findsOneWidget);
      expect(
        find.textContaining('00000000', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('hex mode is available for binary data', (tester) async {
      await _pumpViewer(
        tester,
        Uint8List.fromList(List<int>.generate(16, (i) => 0x80 + i)),
        name: 'blob.bin',
      );
      // .bin auto-detects Binary; switch to hex on demand.
      await _tapChip(tester, 'Hex');
      expect(find.byType(HexViewer), findsOneWidget);
    });

    testWidgets(
      'hex goto uses decimal numbers and explicit hexadecimal offsets',
      (tester) async {
        await _pumpViewer(tester, Uint8List(8192), name: 'sample.bin');
        await _tapChip(tester, 'Hex');
        Future<double> go(String offset) async {
          await tester.tap(find.byTooltip('Go to line / offset (Ctrl+G)'));
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField), offset);
          await tester.tap(find.widgetWithText(TextButton, 'Go'));
          await tester.pumpAndSettle();
          return tester
              .widget<HexViewer>(find.byType(HexViewer))
              .controller!
              .offset;
        }

        final decimal = await go('160');
        final hexadecimal = await go('0x160');
        expect(decimal, closeTo(4 + 10 * hexRowExtent(1), 0.01));
        expect(hexadecimal, closeTo(4 + 22 * hexRowExtent(1), 0.01));
        expect(await go('0xA0'), decimal);
      },
    );
  });

  group('rich modes', () {
    testWidgets('CSV renders as a table', (tester) async {
      await _pumpViewer(
        tester,
        Uint8List.fromList(utf8.encode('a,b\n1,2\n')),
        name: 'table.csv',
      );

      expect(find.byType(CsvTableView), findsOneWidget);
    });

    testWidgets('ZIP shows a member list and opens members', (tester) async {
      final archive = Archive();
      archive.addFile(
        ArchiveFile('a.txt', 5, Uint8List.fromList(utf8.encode('hello'))),
      );
      final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive));

      await _pumpViewer(tester, zipBytes, name: 'bundle.zip');

      expect(find.text('a.txt'), findsOneWidget);

      await tester.tap(find.text('a.txt'));
      await tester.pumpAndSettle();

      // The member opens in a nested viewer; .txt uses the highlighted
      // (RichText) renderer, so search inside rich text.
      expect(find.textContaining('hello', findRichText: true), findsOneWidget);
    });

    testWidgets('7z lists members and opens them', (tester) async {
      final bytes = File('test/fixtures/archives/sample.7z').readAsBytesSync();
      await _pumpViewer(tester, bytes, name: 'sample.7z');

      expect(find.text('nested/deep/data.bin'), findsOneWidget);
      await tester.tap(find.text('nested/deep/data.bin'));
      await tester.pumpAndSettle();
      expect(find.byType(InternalViewerDialog), findsNWidgets(2));
    });

    testWidgets('RAR lists real members', (tester) async {
      final bytes = File('test/fixtures/archives/sample.rar').readAsBytesSync();
      await _pumpViewer(tester, bytes, name: 'sample.rar');

      expect(find.text('grad.bmp'), findsOneWidget);
    });

    testWidgets('encrypted 7z asks for a password and opens members', (
      tester,
    ) async {
      final bytes = File('test/fixtures/archives/header_encrypted.7z')
          .readAsBytesSync();
      await _pumpViewer(tester, bytes, name: 'locked.7z');

      expect(find.text('Password required'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'secret');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('hello.txt'), findsOneWidget);

      await tester.tap(find.text('hello.txt'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('hello, 7z!', findRichText: true),
        findsWidgets,
      );
    });

    testWidgets('single-file .gz opens decompressed content', (tester) async {
      final gzBytes = Uint8List.fromList(
        const GZipEncoder().encode(utf8.encode('hello gzip')),
      );

      await _pumpViewer(tester, gzBytes, name: 'notes.xyz.gz');

      expect(find.text('hello gzip'), findsOneWidget);
    });

    testWidgets('markdown renders as a document', (tester) async {
      await _pumpViewer(
        tester,
        Uint8List.fromList(utf8.encode('# Title\n\nBody text\n')),
        name: 'readme.md',
      );

      expect(find.byType(Markdown), findsOneWidget);
      expect(find.textContaining('Title', findRichText: true), findsWidgets);
    });

    testWidgets('office documents render formatted text and plain text', (
      tester,
    ) async {
      const xml =
          '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
          '<w:body>'
          '<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr>'
          '<w:r><w:t>Hello office</w:t></w:r></w:p>'
          '</w:body></w:document>';
      final archive = Archive()
        ..addFile(ArchiveFile.bytes('word/document.xml', utf8.encode(xml)));
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive));

      await _pumpViewer(tester, bytes, name: 'report.docx');

      // Default view: Markdown (formatted).
      expect(find.byType(Markdown), findsOneWidget);
      expect(
        find.textContaining('Hello office', findRichText: true),
        findsWidgets,
      );

      // Text tab shows the plain-text rendering.
      await tester.ensureVisible(find.text('Text').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Text').last);
      await tester.pumpAndSettle();
      final selectable = tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .map((widget) => widget.data)
          .whereType<String>()
          .join('\n');
      expect(selectable, contains('Hello office'));

      // XML tab is available for inspection.
      expect(find.text('XML'), findsWidgets);
    });

    testWidgets('HTML renders and can switch to source', (tester) async {
      await _pumpViewer(
        tester,
        Uint8List.fromList(
          utf8.encode(
            '<html><body><h1>Hello HTML</h1><p>Body text</p></body></html>',
          ),
        ),
        name: 'page.html',
      );

      expect(find.byType(HtmlWidget), findsOneWidget);
      expect(
        find.textContaining('Hello HTML', findRichText: true),
        findsWidgets,
      );

      await tester.ensureVisible(find.text('Source'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Source'));
      await tester.pumpAndSettle();

      expect(find.byType(HtmlWidget), findsNothing);
      expect(find.textContaining('<h1>', findRichText: true), findsWidgets);
    });

    testWidgets('XML renders as a tree and can switch to source', (
      tester,
    ) async {
      const xml = '<root><item id="1">Value</item></root>';
      await _pumpViewer(
        tester,
        Uint8List.fromList(utf8.encode(xml)),
        name: 'data.xml',
      );

      expect(find.byType(XmlTreeView), findsOneWidget);
      expect(find.textContaining('Value', findRichText: true), findsWidgets);

      await tester.ensureVisible(find.text('Source'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Source'));
      await tester.pumpAndSettle();

      expect(find.byType(XmlTreeView), findsNothing);
      expect(find.textContaining('<root>', findRichText: true), findsWidgets);
    });

    testWidgets('PPTX opens the slide viewer by default', (tester) async {
      const presentation =
          '<p:presentation '
          'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
          '<p:sldSz cx="12192000" cy="6858000"/></p:presentation>';
      const slide =
          '<p:sld '
          'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" '
          'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
          '<p:cSld><p:spTree><p:sp><p:spPr><a:xfrm>'
          '<a:off x="914400" y="914400"/><a:ext cx="9144000" cy="1828800"/>'
          '</a:xfrm></p:spPr><p:txBody><a:p><a:r><a:rPr sz="3200"/>'
          '<a:t>Hello slide</a:t></a:r></a:p></p:txBody></p:sp>'
          '</p:spTree></p:cSld></p:sld>';
      final archive = Archive()
        ..addFile(
          ArchiveFile.bytes('ppt/presentation.xml', utf8.encode(presentation)),
        )
        ..addFile(
          ArchiveFile.bytes('ppt/slides/slide1.xml', utf8.encode(slide)),
        );
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive));

      await _pumpViewer(tester, bytes, name: 'deck.pptx');

      expect(find.byType(PptxSlideViewer), findsOneWidget);
      expect(find.textContaining('Hello slide'), findsWidgets);
    });

    testWidgets('truncated legacy PPT shows its localized extraction reason', (
      tester,
    ) async {
      await _pumpViewer(
        tester,
        Uint8List.fromList(<int>[0xD0, 0xCF, 0x11, 0xE0]),
        name: 'legacy.ppt',
      );

      // Visual PPT is primary; the prior native text reader remains explicit.
      await tester.ensureVisible(find.text('Text fallback'));
      await tester.tap(find.text('Text fallback'));
      await tester.pumpAndSettle();

      final text = tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .map((widget) => widget.data)
          .whereType<String>()
          .join('\n');
      expect(text, contains('Could not extract text from this document'));
      expect(
        find.textContaining('invalid or incomplete slide references'),
        findsOneWidget,
      );
    });

    testWidgets('PNG auto-detects image mode', (tester) async {
      final png = Uint8List.fromList(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQ'
          'DwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
        ),
      );

      await _pumpViewer(tester, png, name: 'pixel.png');

      expect(find.byType(Image), findsOneWidget);
    });
  });

  group('streaming view', () {
    testWidgets(
      'UTF-8 page boundaries preserve the whole character and paging survives a parent rebuild',
      (tester) async {
        final bytes = Uint8List.fromList(
          utf8.encode('${'x' * (kMaxIndexedBytes - 1)}🙂next'),
        );
        final source = ViewBytesSource.memory(bytes);
        await source.open();
        final controller = ScrollController();
        addTearDown(controller.dispose);
        addTearDown(source.dispose);
        Widget view(double zoom, int request) => _wrap(
          Scaffold(
            body: StreamingSafeView(
              source: source,
              rawText: true,
              fontScale: zoom,
              controller: controller,
              scrollToByte: 0,
              scrollRequest: request,
            ),
          ),
        );
        await tester.pumpWidget(view(1, 0));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Next text window'));
        await tester.pumpAndSettle();
        expect(find.text('🙂next', findRichText: true), findsOneWidget);
        await tester.pumpWidget(view(1.2, 0));
        await tester.pumpAndSettle();
        expect(find.text('🙂next', findRichText: true), findsOneWidget);
        await tester.pumpWidget(view(1.2, 1));
        await tester.pumpAndSettle();
        expect(find.text('🙂next', findRichText: true), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'long rows keep UTF-16 surrogate pairs and UTF-8 chunk-edge scalars together',
      (tester) async {
        for (final encoding in ['utf16le', 'utf8']) {
          final count = encoding == 'utf16le' ? 4095 : 128 * 1024 - 1;
          final source = ViewBytesSource.memory(
            encodeViewerSearchText('${'x' * count}🙂end', encoding),
          );
          await source.open();
          await tester.pumpWidget(
            _wrap(
              Scaffold(
                body: StreamingSafeView(
                  source: source,
                  rawText: true,
                  encoding: encoding,
                  fontScale: 1,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.textContaining('🙂', findRichText: true),
            findsOneWidget,
            reason: encoding,
          );
          expect(
            find.text('end', findRichText: true),
            findsOneWidget,
            reason: encoding,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          source.dispose();
        }
      },
    );

    testWidgets('indexes lines and shows byte offsets', (tester) async {
      final data = Uint8List.fromList(utf8.encode('one\ntwo\nthree\n'));
      final source = ViewBytesSource.memory(data);
      await source.open();
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _wrap(
          Scaffold(
            body: StreamingSafeView(
              source: source,
              rawText: true,
              fontScale: 1.0,
              controller: controller,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('one'), findsOneWidget);
      expect(find.text('two'), findsOneWidget);
      expect(find.text('three'), findsOneWidget);
      // One row per line, prefixed with the absolute byte offset.
      expect(find.text('00000000'), findsOneWidget);
      expect(find.text('00000004'), findsOneWidget);
      expect(find.text('00000008'), findsOneWidget);
    });
  });

  testWidgets(
    'text goto reaches a match beyond 64 MiB without indexing the prefix',
    (tester) async {
      const offset = 65 * 1024 * 1024;
      final data = Uint8List(offset + 64);
      final marker = utf8.encode('\nfar away text match\n');
      data.setRange(offset - 1, offset - 1 + marker.length, marker);
      final source = ViewBytesSource.memory(data);
      await source.open();
      final controller = ScrollController();
      addTearDown(controller.dispose);
      addTearDown(source.dispose);
      await tester.pumpWidget(
        _wrap(
          Scaffold(
            body: StreamingSafeView(
              source: source,
              rawText: true,
              fontScale: 1,
              controller: controller,
              scrollToByte: offset,
              matchStart: offset,
              matchEnd: offset + 18,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('far away text match', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('Previous text window'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('streamed UTF-16 text retains encoding and newline alignment', (
    tester,
  ) async {
    final bytes = Uint8List.fromList([
      for (final c in 'one\ntwo café\n'.codeUnits) ...[c & 255, c >> 8],
    ]);
    final source = ViewBytesSource.memory(bytes);
    await source.open();
    await tester.pumpWidget(
      _wrap(
        Scaffold(
          body: StreamingSafeView(
            source: source,
            rawText: true,
            encoding: 'utf16le',
            fontScale: 1,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('one'), findsOneWidget);
    expect(find.text('two café'), findsOneWidget);
    expect(find.text('00000008'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('mode bar', () {
    testWidgets('offers the core viewer modes', (tester) async {
      await _pumpViewer(tester, Uint8List.fromList(utf8.encode('x')));

      for (final label in ['Auto', 'Text', 'ASCII', 'Binary', 'Hex', 'Image']) {
        expect(find.widgetWithText(ChoiceChip, label), findsOneWidget);
      }
    });
  });
}
