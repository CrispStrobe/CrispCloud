import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/file_view_configuration.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/models/sort.dart';
import 'package:crisp_cloud/providers/panel_provider.dart';
import 'package:crisp_cloud/providers/toolbar_provider.dart';
import 'package:crisp_cloud/widgets/file_column_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Panel extends Fake implements PanelNotifier {
  int sorts = 0;
  @override
  String? get sortColumnId => null;
  @override
  String? get secondarySortColumnId => null;
  @override
  SortBy get sortBy => SortBy.name;
  @override
  SortOrder get sortOrder => SortOrder.ascending;
  @override
  SortBy? get secondarySortBy => null;
  @override
  bool get showingSearchResults => false;
  @override
  void setSortBy(SortBy value) => sorts++;
}

void main() {
  Future<ProviderContainer> open(
    WidgetTester tester,
    _Panel panel, {
    double width = 800,
    double scale = 1,
  }) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: FileColumnHeader(side: PanelSide.local, panel: panel),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets(
    'left edge enlarges Size and retains all drag deltas across rebuilds',
    (tester) async {
      final panel = _Panel();
      final container = await open(tester, panel);
      final handle = find.byKey(const ValueKey('resize-column-size'));
      final drag = await tester.startGesture(
        tester.getCenter(handle),
        kind: PointerDeviceKind.mouse,
      );
      await drag.moveBy(const Offset(-25, 0));
      await tester.pump();
      final before = tester.getSize(find.text('Size')).width;
      for (var i = 0; i < 4; i++) {
        await drag.moveBy(const Offset(-16, 0));
      }
      expect(
        container.read(columnWidthsProvider(PanelSide.local))['size'],
        closeTo(before + 64, .01),
      );
      await tester.pump();
      await drag.moveBy(const Offset(20, 0));
      await tester.pump();
      expect(
        container.read(columnWidthsProvider(PanelSide.local))['size'],
        closeTo(before + 44, .01),
      );
      expect(
        tester.getSize(find.text('Size')).width,
        closeTo(before + 44, .01),
      );
      await drag.up();
      await drag.removePointer();
      await tester.pumpAndSettle();
      expect(panel.sorts, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a wide drag stops at the panel budget instead of hiding Size', (
    tester,
  ) async {
    final container = await open(tester, _Panel(), width: 450);
    final handle = find.byKey(const ValueKey('resize-column-size'));
    await tester.drag(
      handle,
      const Offset(-500, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(handle, findsOneWidget);
    expect(find.text('Size'), findsOneWidget);
    expect(
      container.read(columnWidthsProvider(PanelSide.local))['size'],
      greaterThanOrEqualTo(96),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('old accidentally narrowed widths still display normal sizes', (
    tester,
  ) async {
    final container = await open(tester, _Panel());
    container.read(columnWidthsProvider(PanelSide.local).notifier).applyWidths({
      'size': 24,
      'date': 78,
      'ext': 40,
    });
    await tester.pump();
    expect(tester.getSize(find.text('Size')).width, greaterThanOrEqualTo(80));
    container.read(columnWidthsProvider(PanelSide.local).notifier).applyWidths({
      'size': -24,
      'date': 78,
      'ext': 40,
    });
    await tester.pump();
    expect(find.text('Size'), findsNothing);
  });

  testWidgets('default Size width grows with accessible list text', (
    tester,
  ) async {
    await open(tester, _Panel(), scale: 2.5);
    expect(tester.getSize(find.text('Size')).width, greaterThan(120));
    expect(tester.takeException(), isNull);
  });

  test('default Size column reserves readable numeric space', () {
    final view = FileViewConfiguration();
    expect(view.widthFor(FileColumnDefinition.defaults.first), 96);
  });
}
