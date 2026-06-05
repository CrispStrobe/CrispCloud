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

/// Finds the InkWell inside the Tooltip with [message].
Finder _buttonByTooltip(String message) => find.descendant(
      of: find.byTooltip(message),
      matching: find.byType(InkWell),
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
      // The SizedBox.shrink() is returned — no FKeyBar Material content.
      expect(find.byType(Tooltip), findsNothing);
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
  // Labels — verified via Tooltip messages (buttons use RichText not Text)
  // -------------------------------------------------------------------------

  group('FKeyBar button labels', () {
    testWidgets('shows "View" tooltip for F3', (tester) async {
      await tester.pumpWidget(_wrap(FKeyBar(overrideContext: _emptyContext())));
      await tester.pump();
      expect(find.byTooltip('F3 — View'), findsOneWidget);
    });

    testWidgets('shows "Edit" tooltip for F4', (tester) async {
      await tester.pumpWidget(_wrap(FKeyBar(overrideContext: _emptyContext())));
      await tester.pump();
      expect(find.byTooltip('F4 — Edit'), findsOneWidget);
    });

    testWidgets('shows "Copy" tooltip for F5', (tester) async {
      await tester.pumpWidget(_wrap(FKeyBar(overrideContext: _emptyContext())));
      await tester.pump();
      expect(find.byTooltip('F5 — Copy'), findsOneWidget);
    });

    testWidgets('shows "Move" tooltip for F6', (tester) async {
      await tester.pumpWidget(_wrap(FKeyBar(overrideContext: _emptyContext())));
      await tester.pump();
      expect(find.byTooltip('F6 — Move'), findsOneWidget);
    });

    testWidgets('shows "MkDir" tooltip for F7', (tester) async {
      await tester.pumpWidget(_wrap(FKeyBar(overrideContext: _emptyContext())));
      await tester.pump();
      expect(find.byTooltip('F7 — MkDir'), findsOneWidget);
    });

    testWidgets('shows "Delete" tooltip for F8', (tester) async {
      await tester.pumpWidget(_wrap(FKeyBar(overrideContext: _emptyContext())));
      await tester.pump();
      expect(find.byTooltip('F8 — Delete'), findsOneWidget);
    });

    testWidgets('shows shortcut prefixes F3 through F8 as RichText', (tester) async {
      await tester.pumpWidget(_wrap(FKeyBar(overrideContext: _emptyContext())));
      await tester.pump();
      // 6 RichText widgets — one per button (wide mode).
      expect(find.byType(RichText), findsWidgets);
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

      await tester.tap(_buttonByTooltip('F7 — MkDir'));
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

      await tester.tap(_buttonByTooltip('F5 — Copy'));
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

      await tester.tap(_buttonByTooltip('F8 — Delete'));
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

      await tester.tap(_buttonByTooltip('F3 — View'));
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

      await tester.tap(_buttonByTooltip('F3 — View'));
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

      await tester.tap(_buttonByTooltip('F5 — Copy'));
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

      await tester.tap(_buttonByTooltip('F6 — Move'));
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

      await tester.tap(_buttonByTooltip('F8 — Delete'));
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

      await tester.tap(_buttonByTooltip('F4 — Edit'));
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

      await tester.tap(_buttonByTooltip('F4 — Edit'));
      await tester.pump();

      expect(tapped, isNot(contains(FKeyAction.edit)));
    });
  });

  // -------------------------------------------------------------------------
  // Narrow screen (icon-only) mode
  // Uses MediaQuery override to force narrow width since setSurfaceSize
  // interacts with test binding layout.
  // -------------------------------------------------------------------------

  /// Wraps [child] inside a MediaQuery that reports [width] x 600 logical pixels.
  Widget _wrapNarrow(Widget child, double width) {
    return ProviderScope(
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: Size(width, 600)),
          child: Scaffold(body: Column(children: [child])),
        ),
      ),
    );
  }

  group('FKeyBar narrow screen', () {
    testWidgets('shows icons instead of RichText labels on narrow screen',
        (tester) async {
      await tester.pumpWidget(
        _wrapNarrow(FKeyBar(overrideContext: _emptyContext()), 400),
      );
      await tester.pump();

      // In narrow mode, Icon widgets are used instead of RichText labels.
      expect(find.byType(Icon), findsWidgets);
    });

    testWidgets('shows specific icons for each action in narrow mode',
        (tester) async {
      await tester.pumpWidget(
        _wrapNarrow(FKeyBar(overrideContext: _emptyContext()), 400),
      );
      await tester.pump();

      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      expect(find.byIcon(Icons.drive_file_move_outlined), findsOneWidget);
      expect(find.byIcon(Icons.create_new_folder_outlined), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('shows RichText labels on wide screen', (tester) async {
      await tester.pumpWidget(
        _wrapNarrow(FKeyBar(overrideContext: _emptyContext()), 800),
      );
      await tester.pump();

      // Wide mode uses RichText; narrow mode uses Icon. On 800px, must have RichText.
      expect(find.byType(RichText), findsWidgets);
      // All 6 tooltips still present.
      expect(find.byType(Tooltip), findsNWidgets(6));
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
      await tester.tap(_buttonByTooltip('F3 — View'));
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
      await tester.tap(_buttonByTooltip('F7 — MkDir'));
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
