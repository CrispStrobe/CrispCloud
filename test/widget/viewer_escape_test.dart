import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/widgets/internal_viewer_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<FocusNode> openViewer(WidgetTester tester) async {
    final folderFocus = FocusNode();
    addTearDown(folderFocus.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                focusNode: folderFocus,
                autofocus: true,
                onPressed: () => showInternalViewer(
                  context,
                  file: FileItem(
                    name: 'preview.txt',
                    isFolder: false,
                    size: 12,
                  ),
                  side: PanelSide.local,
                  bytesOverride: Uint8List.fromList(
                    utf8.encode('alpha\nbeta\n'),
                  ),
                ),
                child: const Text('Folders view'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Folders view'));
    await tester.pumpAndSettle();
    expect(find.byType(InternalViewerDialog), findsOneWidget);
    return folderFocus;
  }

  testWidgets('Escape closes viewer and restores the folder view focus', (
    tester,
  ) async {
    final folders = await openViewer(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(InternalViewerDialog), findsNothing);
    expect(folders.hasFocus, isTrue);
  });

  testWidgets(
    'Escape from focused search dismisses find, then returns to folders',
    (tester) async {
      final folders = await openViewer(tester);
      await tester.tap(find.byTooltip('Search (Ctrl+F)'));
      await tester.pumpAndSettle();
      final input = find.byKey(const ValueKey('viewer-search-input'));
      await tester.tap(input);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(input, findsNothing);
      expect(find.byType(InternalViewerDialog), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(InternalViewerDialog), findsNothing);
      expect(folders.hasFocus, isTrue);
    },
  );

  testWidgets('Escape dismisses a nested dialog before closing its viewer', (
    tester,
  ) async {
    await openViewer(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(InternalViewerDialog), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(InternalViewerDialog), findsNothing);
  });
}
