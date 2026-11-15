import 'package:crisp_cloud/widgets/active_pane_frame.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'active pane remains obvious without keyboard focus ($brightness)',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final theme = ThemeData(brightness: brightness);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: theme,
              home: Scaffold(
                body: Row(
                  children: [
                    Expanded(
                      child: ActivePaneFrame(
                        side: PanelSide.local,
                        child: TextButton(
                          onPressed: () =>
                              container
                                      .read(activePanelProvider.notifier)
                                      .state =
                                  PanelSide.local,
                          child: const Text('Left'),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ActivePaneFrame(
                        side: PanelSide.remote,
                        child: TextButton(
                          onPressed: () =>
                              container
                                      .read(activePanelProvider.notifier)
                                      .state =
                                  PanelSide.remote,
                          child: const Text('Right'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        Border border(PanelSide side) =>
            (tester
                            .widget<DecoratedBox>(
                              find.byKey(
                                ValueKey('active-pane-frame-${side.name}'),
                              ),
                            )
                            .decoration
                        as BoxDecoration)
                    .border!
                as Border;
        final leftSize = tester.getSize(find.text('Left'));
        expect(border(PanelSide.local).top.color, theme.colorScheme.primary);
        expect(border(PanelSide.local).top.width, 1);
        await tester.tap(find.text('Right'));
        await tester.pump();
        expect(border(PanelSide.remote).top.color, theme.colorScheme.primary);
        expect(
          border(PanelSide.local).top.color,
          theme.colorScheme.outlineVariant,
        );
        expect(
          border(PanelSide.local).top.width,
          border(PanelSide.remote).top.width,
        );
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        expect(border(PanelSide.remote).top.color, theme.colorScheme.primary);
        expect(tester.getSize(find.text('Left')), leftSize);
      },
    );
  }
}
