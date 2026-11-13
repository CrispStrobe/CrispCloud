import 'dart:typed_data';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/binary_structure_strings.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/services/binary_structure_service.dart';
import 'package:crisp_cloud/widgets/binary_structure_dialog.dart';
import 'package:crisp_cloud/widgets/hex_viewer.dart';
import 'package:crisp_cloud/widgets/internal_viewer_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _wasm() => Uint8List.fromList([0, 0x61, 0x73, 0x6d, 1, 0, 0, 0]);

Future<void> _openViewer(WidgetTester tester, Uint8List bytes) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: InternalViewerDialog(
          file: FileItem(
            name: 'module.wasm',
            isFolder: false,
            size: bytes.length,
          ),
          side: PanelSide.local,
          bytesOverride: bytes,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ChoiceChip, 'Hex'));
  await tester.pumpAndSettle();
}

Future<void> _inspect(WidgetTester tester) async {
  final action = find.byKey(const ValueKey('viewer-binary-structure'));
  await tester.ensureVisible(action);
  await tester.pumpAndSettle();
  await tester.tap(action);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('field selection returns to Hex and highlights its exact bytes', (
    tester,
  ) async {
    final bytes = _wasm();
    final original = bytes.toList();
    await _openViewer(tester, bytes);
    final source = tester.widget<HexViewer>(find.byType(HexViewer)).source;
    await _inspect(tester);
    expect(find.text('Binary structure'), findsOneWidget);
    expect(find.text('WebAssembly'), findsOneWidget);
    expect(find.text('Inspected 8 of 8 bytes'), findsOneWidget);
    final version = find.byKey(const ValueKey('binary-field-4-Version'));
    await tester.ensureVisible(version);
    await tester.tap(version);
    await tester.pumpAndSettle();
    expect(find.byType(BinaryStructureDialog), findsNothing);
    final viewer = tester.widget<HexViewer>(find.byType(HexViewer));
    expect(viewer.source, same(source));
    expect(viewer.selectedByte, 4);
    expect(viewer.highlightRangeStart, 4);
    expect(viewer.highlightRangeEnd, 8);
    expect(bytes, original);

    await tester.tap(find.byTooltip('Search (Ctrl+F)'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<HexViewer>(find.byType(HexViewer)).highlightRangeStart,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing structure preserves current hex selection', (
    tester,
  ) async {
    await _openViewer(tester, _wasm());
    tester.widget<HexViewer>(find.byType(HexViewer)).onByteTapped!(2);
    await tester.pump();
    await _inspect(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
    expect(tester.widget<HexViewer>(find.byType(HexViewer)).selectedByte, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'truncated input discloses missing fields without selectable inventions',
    (tester) async {
      await _openViewer(tester, Uint8List.fromList([0, 0x61, 0x73, 0x6d]));
      await _inspect(tester);
      expect(
        find.text('The file ends before a required header field is complete.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('binary-field-4-Version')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unknown bytes remain accessible in Hex', (tester) async {
    await _openViewer(tester, Uint8List.fromList([1, 2, 3, 4]));
    await _inspect(tester);
    expect(find.text('Unknown format'), findsOneWidget);
    expect(
      find.text(
        'No supported header was recognized. The original bytes remain available in Hex.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
    expect(find.byType(HexViewer), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('all supported locales translate controls and every issue', (
    tester,
  ) async {
    final titles = <String>{};
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
      late BinaryStructureStrings strings;
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(language),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              strings = BinaryStructureStrings(context);
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      titles.add(strings.text('title'));
      for (final issue in BinaryStructureIssue.values) {
        expect(strings.issue(issue), isNotEmpty);
      }
      expect(strings.summary(8, 9), contains('8'));
      expect(strings.summary(8, 9), contains('9'));
      expect(strings.text('inspect'), isNotEmpty);
      expect(strings.text('readError'), isNotEmpty);
    }
    expect(titles, hasLength(9));
    expect(tester.takeException(), isNull);
  });
}
