// test/widget/fkey_bar_widget_test.dart
//
// Widget tests for the FKeyBar widget.
// Tests rendering, provider toggling, button labels, disabled states,
// tap callbacks, and narrow-screen icon-only mode.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/providers/panel_source_provider.dart';
import 'package:crisp_cloud/services/fkey_action_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/widgets/fkey_bar.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Wraps [child] in a minimal testable tree.
Widget _wrap(
  Widget child, {
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      home: Scaffold(body: Column(children: [child])),
    ),
  );
}

/// A [FKeyContext] that has no files selected.
FKeyContext _emptyContext() => FKeyContext(
      activePanel: const LocalPanelSource('/'),
      oppositePanel: const LocalPanelSource('/tmp'),
      selectedFiles: [],
    );

/// A [FKeyContext] with one non-folder file selected.
FKeyContext _singleFileContext() => FKeyContext(
      activePanel: const LocalPanelSource('/'),
      oppositePanel: const LocalPanelSource('/tmp'),
      selectedFiles: [
        FileItem(name: 'file.txt', path: '/file.txt', isFolder: false),
      ],
    );

/// A [FKeyContext] with multiple files selected.
FKeyContext _multiFileContext() => FKeyContext(
      activePanel: const LocalPanelSource('/'),
      oppositePanel: const LocalPanelSource('/tmp'),
      selectedFiles: [
        FileItem(name: 'a.txt', path: '/a.txt', isFolder: false),
        FileItem(name: 'b.txt', path: '/b.txt', isFolder: false),
      ],
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // -------------------------------------------------------------------------
  // Visibility
  // -------------------------------------------------------------------------

  group('FKeyBar visibility', () {
    testWidgets('renders 6 buttons when fkeyBarVisibleProvider is true',
        (tester) async {
      // Default SharedPreferences empty → defaults to true.
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(_wrap(FKeyBar(overrideContext: _emptyContext())));
      await tester.pump();

      // 6 InkWell (one per action)
      expect(find.byType(InkWell), findsNWidgets(6));
    });

    testWidgets('renders nothing (SizedBox.shrink) when fkeyBarVisibleProvider is false',
        (tester) async {
      // Pre-set fkey_bar_visible to false in SharedPreferences.
      SharedPreferences.setMockInitialValues({'fkey_bar_visible': false});
      await tester.pumpWidget(_wrap(FKeyBar(overrideContext: _emptyContext())));
      // Give the async _load() in the notifier time to complete.
      await tester.pumpAndSettle();

      expect(find.byType(InkWell), findsNothing);
      expect(find.byType(Material), findsNothing);
    });

    testWidgets('bar is visible by default when SharedPreferences is empty',
        (tester) async {
      await tester.pumpWidget(_wrap(FKeyBar(overrideContext: _emptyContext())));
      await tester.pump();

      // Default state is true; buttons should be present.
      expect(find.byType(InkWell), findsWidgets);
    });
  });

  // -------------------------------------------------------------------------
  // Labels
  // -------------------------------------------------------------------------

  group('FKeyBar button labels', () {
    testWidgets('shows "View" label for F3', (tester) async {
      await tester.pumpWidget(_wrap(FKeyBar(overrideContext: _emptyContext())));
      await tester.pump();
      expect(find.textContaining('View'), findsOneWidget);
    });

    testWidgets('shows "Edit" label for F4', (tester) async {
      await tester.pumpWidget(_wrap(FKeyBar(overrideContext: _emptyContext())));
      await tester.pump();
      expect(find.textContaining('Edit'), findsOneWidget);
    });

    testWidgets('shows "Copy" label for F5', (tester) async {
      await tester.pumpWidget(_wrap(FKeyBar(overrideContext: _emptyContext())));
      await tester.pump();
      expect(find.textContaining('Copy'), findsOneWidget);
    });

    testWidgets('shows "Move" label for F6', (tester) async {
      await tester.pumpWidget(_wrap(FKeyBar(overrideContext: _emptyContext())));
      await tester.pump();
      expect(find.textContaining('Move'), findsOneWidget);
    });

    testWidgets('shows "MkDir" label for F7', (tester) async {
      await tester.pumpWidget(_wrap(FKeyBar(overrideContext: _emptyContext())));
      await tester.pump();
      expect(find.textContaining('MkDir'), findsOneWidget);
    });

    testWidgets('shows "Delete" label for F8', (tester) async {
      await tester.pumpWidget(_wrap(FKeyBar(overrideContext: _emptyContext())));
      await tester.pump();
      expect(find.textContaining('Delete'), findsOneWidget);
    });

    testWidgets('shows shortcut prefixes F3 through F8', (tester) async {
      await tester.pumpWidget(_wrap(FKeyBar(overrideContext: _emptyContext())));
      await tester.pump();
      for (final shortcut in ['F3', 'F4', 'F5', 'F6', 'F7', 'F8']) {
        expect(find.textContaining(shortcut), findsOneWidget,
            reason: '$shortcut shortcut prefix missing');
      }
    });
  });

  // -------------------------------------------------------------------------
  // Availability / enabled states
  // -------------------------------------------------------------------------

  group('FKeyBar button availability', () {
    testWidgets('F7 MkDir is always enabled (even with no selection)',
        (tester) async {
      final tapped = <FKeyAction>[];
      await tester.pumpWidget(
        _wrap(FKeyBar(
          overrideContext: _emptyContext(),
          onAction: tapped.add,
        )),
      );
      await tester.pump();

      // F7 button should be tappable — tap the MkDir area
      final mkdirButton = find.ancestor(
        of: find.textContaining('MkDir'),
        matching: find.byType(InkWell),
      );
      expect(mkdirButton, findsOneWidget);
      await tester.tap(mkdirButton);
      await tester.pump();

      expect(tapped, contains(FKeyAction.mkdir));
    });

    testWidgets('F5 Copy is disabled (no onTap) when selection is empty',
        (tester) async {
      final tapped = <FKeyAction>[];
      await tester.pumpWidget(
        _wrap(FKeyBar(
          overrideContext: _emptyContext(),
          onAction: tapped.add,
        )),
      );
      await tester.pump();

      final copyButton = find.ancestor(
        of: find.textContaining('Copy'),
        matching: find.byType(InkWell),
      );
      await tester.tap(copyButton);
      await tester.pump();

      expect(tapped, isNot(contains(FKeyAction.copy)));
    });

    testWidgets('F8 Delete is disabled when selection is empty',
        (tester) async {
      final tapped = <FKeyAction>[];
      await tester.pumpWidget(
        _wrap(FKeyBar(
          overrideContext: _emptyContext(),
          onAction: tapped.add,
        )),
      );
      await tester.pump();

      final deleteButton = find.ancestor(
        of: find.textContaining('Delete'),
        matching: find.byType(InkWell),
      );
      await tester.tap(deleteButton);
      await tester.pump();

      expect(tapped, isNot(contains(FKeyAction.delete)));
    });

    testWidgets('F3 View is disabled when selection is empty', (tester) async {
      final tapped = <FKeyAction>[];
      await tester.pumpWidget(
        _wrap(FKeyBar(
          overrideContext: _emptyContext(),
          onAction: tapped.add,
        )),
      );
      await tester.pump();

      final viewButton = find.ancestor(
        of: find.textContaining('View'),
        matching: find.byType(InkWell),
      );
      await tester.tap(viewButton);
      await tester.pump();

      expect(tapped, isNot(contains(FKeyAction.view)));
    });

    testWidgets('F3 View fires when a single file is selected', (tester) async {
      final tapped = <FKeyAction>[];
      await tester.pumpWidget(
        _wrap(FKeyBar(
          overrideContext: _singleFileContext(),
          onAction: tapped.add,
        )),
      );
      await tester.pump();

      final viewButton = find.ancestor(
        of: find.textContaining('View'),
        matching: find.byType(InkWell),
      );
      await tester.tap(viewButton);
      await tester.pump();

      expect(tapped, contains(FKeyAction.view));
    });

    testWidgets('F5 Copy fires when files are selected', (tester) async {
      final tapped = <FKeyAction>[];
      await tester.pumpWidget(
        _wrap(FKeyBar(
          overrideContext: _multiFileContext(),
          onAction: tapped.add,
        )),
      );
      await tester.pump();

      final copyButton = find.ancestor(
        of: find.textContaining('Copy'),
        matching: find.byType(InkWell),
      );
      await tester.tap(copyButton);
      await tester.pump();

      expect(tapped, contains(FKeyAction.copy));
    });

    testWidgets('F6 Move fires when files are selected', (tester) async {
      final tapped = <FKeyAction>[];
      await tester.pumpWidget(
        _wrap(FKeyBar(
          overrideContext: _multiFileContext(),
          onAction: tapped.add,
        )),
      );
      await tester.pump();

      final moveButton = find.ancestor(
        of: find.textContaining('Move'),
        matching: find.byType(InkWell),
      );
      await tester.tap(moveButton);
      await tester.pump();

      expect(tapped, contains(FKeyAction.move));
    });

    testWidgets('F8 Delete fires when files are selected', (tester) async {
      final tapped = <FKeyAction>[];
      await tester.pumpWidget(
        _wrap(FKeyBar(
          overrideContext: _multiFileContext(),
          onAction: tapped.add,
        )),
      );
      await tester.pump();

      final deleteButton = find.ancestor(
        of: find.textContaining('Delete'),
        matching: find.byType(InkWell),
      );
      await tester.tap(deleteButton);
      await tester.pump();

      expect(tapped, contains(FKeyAction.delete));
    });

    testWidgets('F4 Edit fires when a single file is selected', (tester) async {
      final tapped = <FKeyAction>[];
      await tester.pumpWidget(
        _wrap(FKeyBar(
          overrideContext: _singleFileContext(),
          onAction: tapped.add,
        )),
      );
      await tester.pump();

      final editButton = find.ancestor(
        of: find.textContaining('Edit'),
        matching: find.byType(InkWell),
      );
      await tester.tap(editButton);
      await tester.pump();

      expect(tapped, contains(FKeyAction.edit));
    });

    testWidgets('F4 Edit is disabled when a folder is selected',
        (tester) async {
      final folderContext = FKeyContext(
        activePanel: const LocalPanelSource('/'),
        oppositePanel: const LocalPanelSource('/tmp'),
        selectedFiles: [
          FileItem(name: 'docs', path: '/docs', isFolder: true),
        ],
      );
      final tapped = <FKeyAction>[];
      await tester.pumpWidget(
        _wrap(FKeyBar(overrideContext: folderContext, onAction: tapped.add)),
      );
      await tester.pump();

      final editButton = find.ancestor(
        of: find.textContaining('Edit'),
        matching: find.byType(InkWell),
      );
      await tester.tap(editButton);
      await tester.pump();

      expect(tapped, isNot(contains(FKeyAction.edit)));
    });
  });

  // -------------------------------------------------------------------------
  // Narrow screen (icon-only) mode
  // -------------------------------------------------------------------------

  group('FKeyBar narrow screen', () {
    testWidgets('shows icons instead of text labels on narrow screen',
        (tester) async {
      // Set a narrow screen size (< 480px wide)
      await tester.binding.setSurfaceSize(const Size(400, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _wrap(FKeyBar(overrideContext: _emptyContext())),
      );
      await tester.pump();

      // In narrow mode, icon widgets are used instead of RichText labels.
      expect(find.byType(Icon), findsWidgets);
      // Specific action text labels should not appear on narrow screen.
      expect(find.textContaining('View'), findsNothing);
      expect(find.textContaining('Copy'), findsNothing);
      expect(find.textContaining('MkDir'), findsNothing);
    });

    testWidgets('shows specific icons for each action in narrow mode',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _wrap(FKeyBar(overrideContext: _emptyContext())),
      );
      await tester.pump();

      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      expect(find.byIcon(Icons.copy_outlined), findsOneWidget);
      expect(find.byIcon(Icons.drive_file_move_outlined), findsOneWidget);
      expect(find.byIcon(Icons.create_new_folder_outlined), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('shows text labels on wide screen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _wrap(FKeyBar(overrideContext: _emptyContext())),
      );
      await tester.pump();

      expect(find.textContaining('View'), findsOneWidget);
      expect(find.textContaining('MkDir'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // onAction callback
  // -------------------------------------------------------------------------

  group('FKeyBar onAction callback', () {
    testWidgets('does not throw when onAction is null and button is tapped',
        (tester) async {
      await tester.pumpWidget(
        _wrap(FKeyBar(overrideContext: _singleFileContext(), onAction: null)),
      );
      await tester.pump();

      // Tapping with onAction == null should not throw.
      final viewButton = find.ancestor(
        of: find.textContaining('View'),
        matching: find.byType(InkWell),
      );
      await tester.tap(viewButton);
      await tester.pump();
      // No assertion needed — just verifying no exception is thrown.
    });

    testWidgets('fires onAction for each enabled button once', (tester) async {
      final tapped = <FKeyAction>[];
      await tester.pumpWidget(
        _wrap(FKeyBar(
          overrideContext: _singleFileContext(),
          onAction: tapped.add,
        )),
      );
      await tester.pump();

      // Tap F7 MkDir (always enabled)
      await tester.tap(find.ancestor(
        of: find.textContaining('MkDir'),
        matching: find.byType(InkWell),
      ));
      await tester.pump();

      expect(tapped.length, equals(1));
      expect(tapped.first, equals(FKeyAction.mkdir));
    });
  });

  // -------------------------------------------------------------------------
  // Tooltip smoke-test
  // -------------------------------------------------------------------------

  group('FKeyBar tooltips', () {
    testWidgets('each button is wrapped in a Tooltip', (tester) async {
      await tester.pumpWidget(
        _wrap(FKeyBar(overrideContext: _emptyContext())),
      );
      await tester.pump();

      // 6 Tooltips, one per action
      expect(find.byType(Tooltip), findsNWidgets(6));
    });
  });
}

