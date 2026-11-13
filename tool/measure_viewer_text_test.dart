import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/widgets/internal_viewer_dialog.dart';
import 'package:crisp_cloud/widgets/internal_viewer_views.dart';

void main() {
  testWidgets(
    'local long-line text opens, wraps and scrolls with bounded paragraphs',
    (tester) async {
      final bytes = File(
        Platform.environment['CRISPCLOUD_VIEWER_PERF_FILE'] ??
            (throw StateError(
              'Set CRISPCLOUD_VIEWER_PERF_FILE to a local long-line text file',
            )),
      ).readAsBytesSync();
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final clock = Stopwatch()..start();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: InternalViewerDialog(
              file: FileItem(
                name: 'project.bcad',
                isFolder: false,
                size: bytes.length,
              ),
              side: PanelSide.local,
              bytesOverride: bytes,
            ),
          ),
        ),
      );
      await tester.pump();
      final firstContentMs = clock.elapsedMilliseconds;
      await tester.pumpAndSettle();
      final openedMs = clock.elapsedMilliseconds;
      final view = find.byType(StreamingSafeView);
      expect(view, findsOneWidget);
      int maxParagraph() => tester
          .widgetList<Text>(
            find.descendant(of: view, matching: find.byType(Text)),
          )
          .map((w) => w.textSpan?.toPlainText().length ?? 0)
          .fold(0, (a, b) => a > b ? a : b);
      expect(maxParagraph(), lessThanOrEqualTo(2052));
      clock.reset();
      await tester.tap(find.byKey(const ValueKey('viewer-word-wrap')));
      await tester.pumpAndSettle();
      final wrappedMs = clock.elapsedMilliseconds;
      expect(maxParagraph(), lessThanOrEqualTo(1028));
      clock.reset();
      await tester.drag(
        find.descendant(of: view, matching: find.byType(ListView)),
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      final scrolledMs = clock.elapsedMilliseconds;
      await tester.tap(find.byKey(const ValueKey('viewer-word-wrap')));
      await tester.pumpAndSettle();
      expect(
        find.text('00000000'),
        findsNothing,
        reason: 'Toggling wrap must retain the scrolled source location',
      );
      expect(tester.takeException(), isNull);
      // The benchmark deliberately emits metrics, never source text or its path.
      // ignore: avoid_print
      print(
        jsonEncode({
          'fileBytes': bytes.length,
          'firstContentMs': firstContentMs,
          'indexedMs': openedMs,
          'wrapMs': wrappedMs,
          'scrollMs': scrolledMs,
          'maxUnwrappedParagraphCodeUnits': maxParagraph(),
        }),
      );
    },
  );
}
