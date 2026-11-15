import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

SheetEditorController _controller() => SheetEditorController(
  workbook: SmlWorkbook(
    sheets: [
      SmlWorksheet(name: 'Budget', sheetId: 1)
        ..cellA1('A1').value = 5
        ..cellA1('B2').value = 'Find first',
      SmlWorksheet(name: 'Summary', sheetId: 2)
        ..cellA1('B2').value = 'Find second',
    ],
  ),
  config: const OfficeSurfaceConfig(autofocus: false),
);

Widget _host({
  required SheetEditorController controller,
  Widget Function(BuildContext, SheetEditorController)? navigation,
  FocusNode? focus,
  Widget Function(BuildContext, SheetEditorController)? status,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: QudsSheetEditor(
    controller: controller,
    focusNode: focus,
    navigationBuilder: navigation,
    statusBarBuilder: status,
  ),
);

void main() {
  testWidgets('navigation renders below the grid and above status chrome', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(
        controller: controller,
        navigation: (_, current) => SizedBox(
          key: const ValueKey('navigation'),
          height: 42,
          child: Text(current.sheet.name),
        ),
        status: (_, _) => const SizedBox(key: ValueKey('status'), height: 20),
      ),
    );
    final grid = tester.getRect(find.byType(SheetGrid));
    final navigation = tester.getRect(find.byKey(const ValueKey('navigation')));
    final status = tester.getRect(find.byKey(const ValueKey('status')));
    expect(navigation.top, grid.bottom);
    expect(navigation.height, 42);
    expect(status.top, navigation.bottom);
    expect(find.text('Budget'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('navigation follows sheet changes, rename, undo and redo', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(
        controller: controller,
        navigation: (_, current) => SizedBox(
          height: 42,
          child: Text('${current.activeSheetIndex}: ${current.sheet.name}'),
        ),
      ),
    );
    expect(find.text('0: Budget'), findsOneWidget);
    controller.setActiveSheet(1);
    await tester.pump();
    expect(find.text('1: Summary'), findsOneWidget);
    controller.renameSheet('Totals');
    await tester.pump();
    expect(find.text('1: Totals'), findsOneWidget);
    controller.undo();
    await tester.pump();
    expect(find.text('1: Summary'), findsOneWidget);
    controller.redo();
    await tester.pump();
    expect(find.text('1: Totals'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('absent navigation retains the full default grid layout', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller: controller));
    final defaultGrid = tester.getRect(find.byType(SheetGrid));
    await tester.pumpWidget(
      _host(
        controller: controller,
        navigation: (_, _) => const SizedBox(height: 42),
      ),
    );
    final withNavigation = tester.getRect(find.byType(SheetGrid));
    expect(withNavigation.topLeft, defaultGrid.topLeft);
    expect(withNavigation.width, defaultGrid.width);
    expect(withNavigation.height, defaultGrid.height - 42);
    await tester.pumpWidget(_host(controller: controller));
    expect(tester.getRect(find.byType(SheetGrid)), defaultGrid);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('replacement controller owns subsequent navigation rebuilds', (
    tester,
  ) async {
    final original = _controller();
    final replacement = _controller();
    addTearDown(original.dispose);
    addTearDown(replacement.dispose);
    var builds = 0;
    Widget navigation(BuildContext context, SheetEditorController current) {
      builds++;
      return SizedBox(height: 42, child: Text(current.sheet.name));
    }

    await tester.pumpWidget(
      _host(controller: original, navigation: navigation),
    );
    await tester.pumpWidget(
      _host(controller: replacement, navigation: navigation),
    );
    replacement.setActiveSheet(1);
    await tester.pump();
    expect(find.text('Summary'), findsOneWidget);
    final afterReplacement = builds;
    original.refresh();
    await tester.pump();
    expect(builds, afterReplacement);
    await tester.pumpWidget(const SizedBox.shrink());
    replacement.refresh();
    original.refresh();
    expect(tester.takeException(), isNull);
  });

  for (final forward in [true, false]) {
    testWidgets(
      'F3 ${forward ? 'next' : 'previous'} retains a rejected draft',
      (tester) async {
        final controller = _controller();
        final focus = FocusNode();
        addTearDown(controller.dispose);
        addTearDown(focus.dispose);
        controller.find(const OfficeFindOptions(query: 'Find'));
        controller.selection.selectCell(const SmlCellRef(0, 0));
        controller.sheet.validations.add(
          SmlDataValidation(
            range: SmlRange.parse('A1:A1'),
            kind: SmlValidationKind.whole,
            formula1: '1',
            formula2: '10',
            error: 'Enter a whole number.',
          ),
        );
        await tester.pumpWidget(_host(controller: controller, focus: focus));
        focus.requestFocus();
        await tester.pump();
        controller.beginCellEdit();
        controller.cellEditor.bridge.updateEditingValue(
          const TextEditingValue(
            text: 'invalid',
            selection: TextSelection.collapsed(offset: 7),
          ),
        );
        final before = controller.contentRevision;
        if (!forward) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.f3);
        if (!forward) {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        }
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(controller.lastValidationError, isNotNull);
        expect(controller.activeSheetIndex, 0);
        expect(controller.selection.focus, const SmlCellRef(0, 0));
        expect(controller.findSession.index, 0);
        expect(controller.cellEditor.editing, isTrue);
        expect(controller.formulaBarText, 'invalid');
        expect(controller.contentRevision, before);
        expect(controller.commands.canUndo, isFalse);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
