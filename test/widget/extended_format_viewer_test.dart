import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/services/editor_document.dart';
import 'package:crisp_cloud/widgets/email_message_view.dart';
import 'package:crisp_cloud/widgets/internal_viewer_dialog.dart';
import 'package:crisp_cloud/widgets/internal_viewer_views.dart';
import 'package:crisp_cloud/widgets/xml_tree_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import '../support/structured_word_fixture.dart';

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

Future<void> _open(
  WidgetTester tester,
  String name,
  Uint8List bytes, {
  Locale? locale,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
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

Future<void> _tapMode(WidgetTester tester, String label) async {
  final chip = find.widgetWithText(ChoiceChip, label);
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

Uint8List _eml() => _bytes(
  'Subject: =?UTF-8?B?${base64.encode(utf8.encode('Saved café'))}?=\r\n'
  'From: sender@example.test\r\n'
  'To: recipient@example.test\r\n'
  'MIME-Version: 1.0\r\n'
  'Content-Type: multipart/mixed; boundary="parts"\r\n\r\n'
  '--parts\r\nContent-Type: text/plain; charset=utf-8\r\n'
  'Content-Transfer-Encoding: base64\r\n\r\n'
  '${base64.encode(utf8.encode('Decoded café content'))}\r\n'
  '--parts\r\nContent-Type: text/plain\r\n'
  'Content-Disposition: attachment; filename="note.txt"\r\n'
  'Content-Transfer-Encoding: base64\r\n\r\n'
  '${base64.encode(utf8.encode('Original attachment bytes'))}\r\n'
  '--parts--\r\n',
);

Uint8List _unicode(String text) {
  final bytes = ByteData((text.length + 1) * 2);
  for (var index = 0; index < text.length; index++) {
    bytes.setUint16(index * 2, text.codeUnitAt(index), Endian.little);
  }
  return bytes.buffer.asUint8List();
}

Uint8List _formattedWord() {
  const text = 'Bold Added Removed HIDDEN\r';
  const offset = 8192;
  return StructuredWordFixture(
    pieces: const [WordFixturePiece(text, offset: offset)],
    characterRuns: [
      WordFixtureFkpRun(
        offset,
        offset + 4,
        properties: wordSprm(0x0835, [1]), // Bold.
      ),
      WordFixtureFkpRun(
        offset + 5,
        offset + 10,
        properties: wordSprm(0x0801, [1]), // Inserted revision.
      ),
      WordFixtureFkpRun(
        offset + 11,
        offset + 18,
        properties: wordSprm(0x0800, [1]), // Deleted revision.
      ),
      WordFixtureFkpRun(
        offset + 19,
        offset + 25,
        properties: wordSprm(0x083c, [1]), // Hidden text.
      ),
      const WordFixtureFkpRun(offset + 25, offset + text.length),
    ],
  ).build();
}

Iterable<(String, TextStyle)> _styledText(
  InlineSpan span, [
  TextStyle inherited = const TextStyle(),
]) sync* {
  if (span is! TextSpan) return;
  final style = inherited.merge(span.style);
  if (span.text case final text?) yield (text, style);
  for (final child in span.children ?? const <InlineSpan>[]) {
    yield* _styledText(child, style);
  }
}

void main() {
  for (final scenario in [
    ('doc', const Locale('en'), 'Partial preview of a binary Word document.'),
    (
      'dot',
      const Locale('de'),
      'Teilweise Vorschau eines binären Word-Dokuments.',
    ),
  ]) {
    testWidgets(
      '${scenario.$1.toUpperCase()} F3 shows supported formatting and revisions with a localized notice and explicit text view',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1100, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await _open(
          tester,
          'formatted.${scenario.$1}',
          _formattedWord(),
          locale: scenario.$2,
        );
        final html = tester.widget<HtmlWidget>(find.byType(HtmlWidget)).html;
        expect(html, contains('<ins'));
        expect(html, contains('<del'));
        expect(html, isNot(contains('HIDDEN')));
        expect(html, isNot(contains('UNREFERENCED PRIVATE BYTES')));
        expect(find.textContaining('Added', findRichText: true), findsWidgets);
        expect(
          find.textContaining('Removed', findRichText: true),
          findsWidgets,
        );
        final rendered = tester
            .widgetList<RichText>(find.byType(RichText))
            .expand((widget) => _styledText(widget.text));
        expect(
          rendered.any(
            (span) =>
                span.$1.contains('Bold') &&
                span.$2.fontWeight == FontWeight.bold,
          ),
          isTrue,
        );
        expect(find.textContaining(scenario.$3), findsOneWidget);
        expect(find.text('Pages'), findsNothing);
        expect(find.text('Seiten'), findsNothing);

        final textView = find.descendant(
          of: find.byWidgetPredicate((widget) => widget is SegmentedButton),
          matching: find.text('Text'),
        );
        await tester.ensureVisible(textView);
        await tester.tap(textView);
        await tester.pumpAndSettle();
        expect(find.byType(HtmlWidget), findsNothing);
        final text = tester.widgetList<SelectableText>(
          find.byType(SelectableText),
        );
        expect(
          text.any(
            (widget) => widget.data?.contains('Bold Added Removed') ?? false,
          ),
          isTrue,
        );
        expect(
          text.every(
            (widget) =>
                !(widget.data?.contains('UNREFERENCED PRIVATE BYTES') ?? false),
          ),
          isTrue,
        );
        expect(
          text.every((widget) => !(widget.data?.contains('HIDDEN') ?? false)),
          isTrue,
        );
        expect(find.textContaining(scenario.$3), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'RTF opens a formatted safe preview without unsupported page layout',
    (tester) async {
      await _open(
        tester,
        'formatted.rtf',
        _bytes(r'{\rtf1\ansi Plain \b bold\b0  body\par Second paragraph}'),
      );
      expect(find.byType(HtmlWidget), findsOneWidget);
      expect(find.textContaining('bold', findRichText: true), findsWidgets);
      expect(
        find.textContaining('Second paragraph', findRichText: true),
        findsWidgets,
      );
      expect(find.text('Pages'), findsNothing);
      expect(find.byTooltip('Edit (F4)'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('F3 decodes MIME text and searches decoded message content', (
    tester,
  ) async {
    final bytes = _eml();
    expect(utf8.decode(bytes), isNot(contains('Decoded café content')));
    await _open(tester, 'message.eml', bytes);
    expect(find.byType(EmailMessageView), findsOneWidget);
    expect(find.text('Saved café'), findsOneWidget);
    expect(find.text('Decoded café content'), findsOneWidget);

    await tester.tap(find.byTooltip('Search (Ctrl+F)'));
    await tester.pumpAndSettle();
    expect(find.byType(EmailMessageView), findsOneWidget);
    expect(find.byType(MonoLineListView), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('viewer-search-input')),
      'café content',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('1/1'), findsOneWidget);
    final emailMode = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Email'),
    );
    expect(emailMode.selected, isTrue);

    await _tapMode(tester, 'Text');
    await _tapMode(tester, 'Email');
    expect(find.text('1/1'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('viewer-search-input')),
      'CAFÉ CONTENT',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('1/1'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('viewer-match-case')));
    await tester.pumpAndSettle();
    expect(find.text('0/0'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('viewer-match-case')));
    await tester.pumpAndSettle();
    expect(find.text('1/1'), findsOneWidget);

    await tester.tap(find.byTooltip('Close search (Esc)'));
    await tester.pumpAndSettle();
    expect(find.byType(EmailMessageView), findsOneWidget);
    expect(find.text('Decoded café content'), findsOneWidget);
  });

  testWidgets(
    'decoded search bounds newline-dense messages and keeps preview',
    (tester) async {
      await _open(
        tester,
        'many-lines.eml',
        _bytes(
          'Subject: Newline-dense message\r\n'
          'Content-Type: multipart/alternative; boundary="parts"\r\n\r\n'
          '--parts\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n'
          'Readable prefix\n${'\n' * 200010}\r\n'
          '--parts\r\nContent-Type: text/html; charset=utf-8\r\n\r\n'
          '<p>Readable message</p>\r\n'
          '--parts--\r\n',
        ),
      );
      expect(find.byType(EmailMessageView), findsOneWidget);
      expect(find.text('Readable message', findRichText: true), findsOneWidget);
      await tester.tap(find.byTooltip('Search (Ctrl+F)'));
      await tester.pumpAndSettle();
      expect(find.byType(EmailMessageView), findsOneWidget);
      expect(find.byType(MonoLineListView), findsNothing);

      await tester.enterText(
        find.byKey(const ValueKey('viewer-search-input')),
        'message',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.byType(EmailMessageView), findsOneWidget);
      expect(find.byType(MonoLineListView), findsNothing);
      expect(find.text('Readable message', findRichText: true), findsOneWidget);
      expect(
        find.textContaining('200,000 lines or 8 MiB of decoded UTF-8 text'),
        findsWidgets,
      );
    },
  );

  testWidgets(
    'email attachments use the existing viewer without an edit target',
    (tester) async {
      await _open(tester, 'message.eml', _eml());
      await tester.tap(find.byTooltip('Open attachment'));
      await tester.pumpAndSettle();
      final viewer = tester.widget<InternalViewerDialog>(
        find.byType(InternalViewerDialog).last,
      );
      expect(viewer.displayName, 'note.txt');
      expect(utf8.decode(viewer.bytesOverride!), 'Original attachment bytes');
      expect(find.byTooltip('Edit (F4)'), findsNothing);
    },
  );

  testWidgets('F3 opens Outlook compound messages in the email view', (
    tester,
  ) async {
    final writer = CfbfWriter()
      ..addStream('__properties_version1.0', Uint8List(32))
      ..addStream('__substg1.0_0037001F', _unicode('Outlook subject'))
      ..addStream('__substg1.0_1000001F', _unicode('Readable Outlook body'));
    await _open(tester, 'message.MSG', writer.build());
    expect(find.byType(EmailMessageView), findsOneWidget);
    expect(find.text('Outlook subject'), findsOneWidget);
    expect(find.text('Readable Outlook body'), findsOneWidget);
  });

  testWidgets('gzip-expanded Outlook messages use the inner MSG filename', (
    tester,
  ) async {
    final writer = CfbfWriter()
      ..addStream('__properties_version1.0', Uint8List(32))
      ..addStream(
        '__substg1.0_0037001F',
        _unicode('Compressed Outlook subject'),
      )
      ..addStream('__substg1.0_1000001F', _unicode('Expanded Outlook body'));
    await _open(
      tester,
      'message.msg.gz',
      Uint8List.fromList(const GZipEncoder().encode(writer.build())),
    );
    expect(find.byType(EmailMessageView), findsOneWidget);
    expect(find.text('Compressed Outlook subject'), findsOneWidget);
    expect(find.text('Expanded Outlook body'), findsOneWidget);
  });

  testWidgets('Autodesk keyboard profiles open as an XML tree', (tester) async {
    await _open(
      tester,
      'shortcuts.kbdx',
      _bytes(
        '<?xml version="1.0"?><ADSK_KBD><shortcut fVirt="3" '
        'accleleratorKey="65" actionID="SelectAll" actionTableID="0"/></ADSK_KBD>',
      ),
    );
    expect(find.byType(XmlTreeView), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'XML'), findsOneWidget);
    expect(find.text('Source'), findsOneWidget);
  });

  test('MIME source edits retain CRLF and untouched attachment encoding', () {
    final original = _eml();
    final document = EditorDocument.decode(original);
    expect(document.encode(), orderedEquals(original));
    final from = document.text.indexOf('sender@example.test');
    final changed = document.replace(
      from,
      from + 'sender@example.test'.length,
      'other@example.test',
    );
    final expected = utf8
        .decode(original)
        .replaceFirst('sender@example.test', 'other@example.test');
    expect(changed.encode(), orderedEquals(utf8.encode(expected)));
  });

  test('keyboard profile source editing retains UTF-16 and line endings', () {
    const source =
        '<ADSK_KBD>\r\n<shortcut actionID="Old"/>\r\n</ADSK_KBD>\r\n';
    final utf16 = _unicode(source);
    final bytes = Uint8List.fromList([
      0xff,
      0xfe,
      ...utf16.sublist(0, utf16.length - 2),
    ]);
    final document = EditorDocument.decode(bytes);
    expect(document.encode(), orderedEquals(bytes));
    final from = document.text.indexOf('Old');
    final changed = document.replace(from, from + 3, 'New');
    expect(changed.encoding, EditorEncoding.utf16le);
    expect(
      EditorDocument.decode(changed.encode()).text,
      document.text.replaceFirst('Old', 'New'),
    );
    expect(changed.lineEndings, everyElement(EditorLineEnding.crlf));
  });
}
