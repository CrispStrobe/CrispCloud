import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/lrc_strings.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/services/lrc_parser.dart';
import 'package:crisp_cloud/widgets/hex_viewer.dart';
import 'package:crisp_cloud/widgets/internal_viewer_dialog.dart';
import 'package:crisp_cloud/widgets/internal_viewer_views.dart';
import 'package:crisp_cloud/widgets/lrc_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChannels;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _open(
  WidgetTester tester,
  Uint8List bytes, {
  String filename = 'track.lrc',
  String? displayName,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: InternalViewerDialog(
          file: FileItem(name: filename, isFolder: false, size: bytes.length),
          side: PanelSide.local,
          bytesOverride: bytes,
          displayName: displayName,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Uint8List _bytes(String value) => Uint8List.fromList(utf8.encode(value));

void main() {
  testWidgets(
    'F3 previews metadata, chronological lines and shifted word timing',
    (tester) async {
      await _open(
        tester,
        _bytes(
          '[ti:Example]\n[00:02]Later\n'
          '[00:01.50]M:<00:01.50>Hello <00:01.75>there\n[offset:500]',
        ),
      );
      expect(find.byType(LrcPreview), findsOneWidget);
      expect(find.text('ti: Example'), findsOneWidget);
      expect(find.text('Timed lines: 2'), findsOneWidget);
      expect(find.text('Timing offset: +500 ms'), findsOneWidget);
      expect(find.text('00:01.000'), findsOneWidget);
      expect(find.text('00:01.500'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Hello there')).dy,
        lessThan(tester.getTopLeft(find.text('Later')).dy),
      );
      expect(find.text('M:'), findsWidgets);
      await tester.tap(find.text('Word timing'));
      await tester.pumpAndSettle();
      expect(find.text('00:01.250'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Source and Hex preserve exact file text and bytes', (
    tester,
  ) async {
    const source = '[ti:Example]\r\n[00:01][00:02]Hello  world\r\n';
    final bytes = _bytes(source);
    await _open(tester, bytes);
    String? copied;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy all text'));
    await tester.pumpAndSettle();
    expect(copied, source);
    await tester.tap(find.byKey(const ValueKey('lrc-source')));
    await tester.pumpAndSettle();
    expect(find.byType(LrcPreview), findsNothing);
    final textView = tester.widget<MonoLineListView>(
      find.byType(MonoLineListView),
    );
    expect(textView.lines, ['[ti:Example]', '[00:01][00:02]Hello  world', '']);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Hex'));
    await tester.pumpAndSettle();
    final hex = tester.widget<HexViewer>(find.byType(HexViewer));
    expect(hex.source.readSync(0, bytes.length), orderedEquals(bytes));
    expect(bytes, orderedEquals(_bytes(source)));
    expect(tester.takeException(), isNull);
  });

  testWidgets('UTF-16 BOM and archive display name keep lyrics detection', (
    tester,
  ) async {
    const text = '[00:01]雪😀';
    final bytes = Uint8List.fromList([
      0xff,
      0xfe,
      for (final unit in text.codeUnits) ...[unit & 0xff, unit >> 8],
    ]);
    await _open(
      tester,
      bytes,
      filename: 'archive.zip',
      displayName: 'TRACK.LRC',
    );
    expect(find.byType(LrcPreview), findsOneWidget);
    expect(find.text('雪😀'), findsOneWidget);
    expect(find.text('00:01.000'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('malformed timing and markup stay visible as literal text', (
    tester,
  ) async {
    await _open(
      tester,
      _bytes('[00:61]invalid\n<script>alert(1)</script>\n[broken]text'),
    );
    expect(find.byType(LrcPreview), findsOneWidget);
    expect(find.text('[00:61]invalid'), findsOneWidget);
    expect(find.text('<script>alert(1)</script>'), findsOneWidget);
    expect(find.text('[broken]text'), findsOneWidget);
    expect(
      find.text(
        'No valid line timestamps were found. The text is shown in source order.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'parser limit offers complete source instead of a partial timeline',
    (tester) async {
      final text = List.filled(lrcMaxCues + 1, '[00:01]bounded').join('\n');
      await _open(tester, _bytes(text));
      expect(find.byType(LrcPreviewUnavailable), findsOneWidget);
      expect(find.text('00:01.000'), findsNothing);
      expect(
        find.text(
          'This lyrics file exceeds the preview limit. Open Source to view the complete text.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('lrc-source')));
      await tester.pumpAndSettle();
      final view = tester.widget<MonoLineListView>(
        find.byType(MonoLineListView),
      );
      expect(view.lines.length, lrcMaxCues + 1);
      expect(view.lines.last, '[00:01]bounded');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Lyrics keeps source order while Timeline uses chronological order',
    (tester) async {
      await _open(tester, _bytes('[00:02]Second\n[00:01]First\nUntimed text'));
      expect(
        tester.getTopLeft(find.text('First')).dy,
        lessThan(tester.getTopLeft(find.text('Second')).dy),
      );
      final lyrics = find.descendant(
        of: find.byType(LrcPreview),
        matching: find.widgetWithText(ChoiceChip, 'Lyrics'),
      );
      await tester.tap(lyrics);
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Second')).dy,
        lessThan(tester.getTopLeft(find.text('First')).dy),
      );
      expect(find.text('00:01.000'), findsNothing);
      expect(find.text('Untimed text'), findsOneWidget);
    },
  );

  testWidgets(
    'search returns to complete text and finds original timing tags',
    (tester) async {
      await _open(tester, _bytes('[00:01]Hello\n[00:02]World'));
      await tester.tap(find.byTooltip('Search (Ctrl+F)'));
      await tester.pumpAndSettle();
      expect(find.byType(LrcPreview), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('viewer-search-input')),
        '[00:02]',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('1/1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('small display with large text keeps Source reachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2.5)),
          child: child!,
        ),
        home: Scaffold(
          body: LrcPreview(
            document: parseLrc(
              '[ti:A long title on a small display]\n[00:01]Readable lyrics',
            ),
            onShowSource: () => opened = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final source = find.byKey(const ValueKey('lrc-source'));
    await tester.ensureVisible(source);
    await tester.tap(source);
    expect(opened, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long lines and expanded word detail have bounded rendering', (
    tester,
  ) async {
    final longText = 'x' * 9000;
    final words = List.generate(
      120,
      (i) => '<00:01.${i.toString().padLeft(3, '0')}>word ',
    ).join();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LrcPreview(
            document: parseLrc('[00:01]$longText\n[00:02]$words'),
            onShowSource: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final selected = tester.widgetList<SelectableText>(
      find.byType(SelectableText),
    );
    expect(selected.every((text) => (text.data?.length ?? 0) <= 8193), isTrue);
    expect(
      find.text(
        'This line is shortened for preview. Open Source for the complete text.',
      ),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LrcPreview(
            document: parseLrc('[00:02]$words'),
            onShowSource: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Word timing'));
    await tester.pumpAndSettle();
    expect(find.text('word '), findsNWidgets(100));
    expect(
      find.text(
        'This line is shortened for preview. Open Source for the complete text.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('all supported locales translate controls and error messages', (
    tester,
  ) async {
    for (final language in [
      'en',
      'de',
      'fr',
      'es',
      'pt',
      'zh',
      'ja',
      'ko',
      'ar',
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(language),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Builder(
            builder: (context) {
              final strings = LrcStrings(context);
              for (final key in [
                'lyrics',
                'timeline',
                'source',
                'limit',
                'sourceChanged',
                'readFailed',
                'shortened',
              ]) {
                expect(strings.text(key), isNotEmpty);
                expect(strings.text(key), isNot(key));
              }
              expect(strings.timedLines(3), contains('3'));
              expect(strings.offset(-500), contains('-500'));
              return Scaffold(
                body: LrcPreview(
                  document: parseLrc('[00:01]مرحبا'),
                  onShowSource: () {},
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: language);
      final timestamp = tester.widget<Text>(find.text('00:01.000'));
      expect(timestamp.textDirection, TextDirection.ltr);
    }
  });
}
