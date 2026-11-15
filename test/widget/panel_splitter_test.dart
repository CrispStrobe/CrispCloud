import 'package:crisp_cloud/widgets/panel_splitter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final axis in Axis.values) {
    testWidgets('slim divider retains dragging and reset ($axis)', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PanelSplitter(
              axis: axis,
              first: const ColoredBox(
                key: ValueKey('first-pane'),
                color: Colors.black,
              ),
              second: const ColoredBox(color: Colors.white),
            ),
          ),
        ),
      );
      final handle = find.byKey(const ValueKey('panel-splitter-handle'));
      final first = find.byKey(const ValueKey('first-pane'));
      double extent() => axis == Axis.horizontal
          ? tester.getSize(first).width
          : tester.getSize(first).height;
      final initial = extent();
      expect(
        axis == Axis.horizontal
            ? tester.getSize(handle).width
            : tester.getSize(handle).height,
        6,
      );
      await tester.drag(
        handle,
        axis == Axis.horizontal ? const Offset(100, 0) : const Offset(0, 100),
      );
      await tester.pumpAndSettle();
      expect(extent(), greaterThan(initial));
      await tester.tap(handle);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(handle);
      await tester.pumpAndSettle();
      expect(extent(), closeTo(initial, 0.01));
    });
  }
}
