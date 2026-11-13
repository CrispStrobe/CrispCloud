import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/widgets/hex_viewer.dart';
import 'package:crisp_cloud/widgets/internal_viewer_dialog.dart';
import 'package:crisp_cloud/widgets/internal_viewer_views.dart';
import 'package:crisp_cloud/widgets/mbox_message_view.dart';
import 'package:file_viewer_documents/file_viewer_documents.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _open(WidgetTester tester, String name, Uint8List bytes) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: InternalViewerDialog(
          file: FileItem(name: name, isFolder: false, size: bytes.length),
          side: PanelSide.local,
          bytesOverride: bytes,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

String _message(String name, String date, String subject, String body) =>
    'From $name@example.test $date\n'
    'Subject: $subject\nFrom: $name@example.test\n'
    'Content-Type: text/plain; charset=utf-8\n'
    'Content-Transfer-Encoding: base64\n\n'
    '${base64Encode(utf8.encode(body))}\n';

Uint8List _mailbox() => _bytes(
  _message(
        'one',
        'Mon Jan  1 00:00:00 2024',
        'First',
        'only-first needle needle',
      ) +
      _message(
        'two',
        'Tue Jan  2 00:00:00 2024',
        'Second',
        'only-second needle',
      ),
);

Future<void> _copyAll(WidgetTester tester) async {
  await tester.tap(find.byTooltip('More'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Copy all text'));
  await tester.pumpAndSettle();
}

void _recordClipboard(ValueChanged<String> changed) {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') {
      changed((call.arguments as Map)['text'] as String);
    }
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
}

void main() {
  testWidgets('MBOX Copy all follows decoded selected message only', (
    tester,
  ) async {
    await _open(tester, 'mail.mbox', _mailbox());
    String? copied;
    _recordClipboard((text) => copied = text);
    await _copyAll(tester);
    expect(copied, contains('only-first needle needle'));
    expect(copied, isNot(contains('only-second')));
    expect(copied, isNot(contains('Content-Transfer-Encoding')));
    await tester.tap(find.byKey(const ValueKey('mbox-next')));
    await tester.pumpAndSettle();
    await _copyAll(tester);
    expect(copied, contains('only-second needle'));
    expect(copied, isNot(contains('only-first')));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'MBOX navigation retains query and searches the newly selected message',
    (tester) async {
      await _open(tester, 'mail.mbox', _mailbox());
      await tester.tap(find.byTooltip('Search (Ctrl+F)'));
      await tester.pumpAndSettle();
      final search = find.byKey(const ValueKey('viewer-search-input'));
      await tester.enterText(search, 'needle');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('1/2'), findsOneWidget);
      expect(find.byType(MboxMessageView), findsOneWidget);
      expect(find.byKey(const ValueKey('mbox-next')), findsOneWidget);
      expect(find.byKey(const ValueKey('mbox-choose')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mbox-next')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(search).controller!.text, 'needle');
      expect(find.text('1/1'), findsOneWidget);
      final body = tester.widget<MonoLineListView>(
        find.byType(MonoLineListView),
      );
      expect(body.lines.join('\n'), contains('only-second needle'));
      expect(body.lines.join('\n'), isNot(contains('only-first')));
      await tester.tap(find.byKey(const ValueKey('mbox-previous')));
      await tester.pumpAndSettle();
      expect(find.text('1/2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('one malformed MBOX message leaves later messages reachable', (
    tester,
  ) async {
    final input = _bytes(
      [
        'From broken@example.test Mon Jan  1 00:00:00 2024\n'
            'This is not a MIME header\n',
        _message('two', 'Tue Jan  2 00:00:00 2024', 'Valid', 'reachable-body'),
      ].join(),
    );
    await _open(tester, 'mail.mbox', input);
    var view = tester.widget<MboxMessageView>(find.byType(MboxMessageView));
    expect(view.selectedIndex, 0);
    expect(view.message, isNull);
    expect(view.messageError, isNotNull);
    await tester.tap(find.byKey(const ValueKey('mbox-next')));
    await tester.pumpAndSettle();
    view = tester.widget<MboxMessageView>(find.byType(MboxMessageView));
    expect(view.selectedIndex, 1);
    expect(view.message!.searchText, contains('reachable-body'));
    expect(view.messageError, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'compressed BOM mailbox uses inner format and preserves expanded Source/Hex bytes',
    (tester) async {
      final source = Uint8List.fromList([0xef, 0xbb, 0xbf, ..._mailbox()]);
      await _open(
        tester,
        'MAIL.MBOX.gz',
        Uint8List.fromList(const GZipEncoder().encode(source)),
      );
      final view = tester.widget<MboxMessageView>(find.byType(MboxMessageView));
      expect(view.document.sourceBytes, orderedEquals(source));
      await tester.tap(find.byKey(const ValueKey('mbox-source')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Hex'));
      await tester.pumpAndSettle();
      final hex = tester.widget<HexViewer>(find.byType(HexViewer));
      expect(hex.source.readSync(0, source.length), orderedEquals(source));
    },
  );

  testWidgets(
    'compressed binary PPT keeps inner name, copies native text, and protects visual Copy all',
    (tester) async {
      final compressed = File(
        'test/fixtures/legacy_powerpoint/current-slides.ppt.gz',
      ).readAsBytesSync();
      final expanded = Uint8List.fromList(
        const GZipDecoder().decodeBytes(compressed),
      );
      await _open(tester, 'presentation.ppt.gz', compressed);
      var preview = tester.widget<DocumentPreview>(
        find.byType(DocumentPreview),
      );
      expect(preview.filename, 'presentation.ppt');
      expect(preview.kind, DocumentPreviewKind.ppt);
      expect(preview.bytes, orderedEquals(expanded));
      await tester.ensureVisible(find.text('Text fallback'));
      await tester.tap(find.text('Text fallback'));
      await tester.pumpAndSettle();
      expect(find.byType(DocumentPreview), findsNothing);
      String? copied;
      _recordClipboard((text) => copied = text);
      await _copyAll(tester);
      expect(copied, contains('Current title 世界'));
      expect(copied, contains('Independent shape café'));
      expect(copied, contains('Second current slide'));
      expect(copied, isNot(contains('SPEAKER')));
      await tester.ensureVisible(find.text('Preview'));
      await tester.tap(find.text('Preview'));
      await tester.pumpAndSettle();
      preview = tester.widget<DocumentPreview>(find.byType(DocumentPreview));
      expect(preview.bytes, orderedEquals(expanded));
      copied = null;
      await _copyAll(tester);
      expect(copied, isNull);
      // The preceding successful-copy snackbar is still queued in this real
      // host; let it finish so the next explanation is actually displayed.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Select text inside the document'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'XML tools receive original UTF-16 bytes and Source/Hex remain exact',
    (tester) async {
      const xml = '<?xml version="1.0" encoding="UTF-16"?><root>café</root>';
      final data = ByteData(2 + xml.length * 2)
        ..setUint16(0, 0xfeff, Endian.little);
      for (var i = 0; i < xml.length; i++) {
        data.setUint16(2 + i * 2, xml.codeUnitAt(i), Endian.little);
      }
      final source = data.buffer.asUint8List();
      await _open(tester, 'schema.xsd', source);
      await tester.ensureVisible(find.text('XSD / XSLT'));
      await tester.tap(find.text('XSD / XSLT'));
      await tester.pumpAndSettle();
      final preview = tester.widget<DocumentPreview>(
        find.byType(DocumentPreview),
      );
      expect(preview.filename, 'schema.xsd');
      expect(preview.bytes, orderedEquals(source));
      await tester.tap(
        find.descendant(
          of: find.byType(SegmentedButton<String>),
          matching: find.text('Source'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DocumentPreview), findsNothing);
      String? copied;
      _recordClipboard((text) => copied = text);
      await _copyAll(tester);
      expect(copied, xml);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Hex'));
      await tester.pumpAndSettle();
      final hex = tester.widget<HexViewer>(find.byType(HexViewer));
      expect(hex.source.readSync(0, source.length), orderedEquals(source));
      expect(tester.takeException(), isNull);
    },
  );
}
