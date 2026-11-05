import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/services/image_editor_menu.dart';
import 'package:crisp_cloud/widgets/image_editor_menus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<List<PlatformMenu>> _buildMenus(
  WidgetTester tester,
  ImageEditorMenuActions editor, {
  Locale locale = const Locale('en'),
}) async {
  late List<PlatformMenuItem> menus;
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          menus = buildImageEditorPlatformMenus(context, editor);
          return const SizedBox();
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return menus.cast<PlatformMenu>();
}

Map<String, PlatformMenuItem> _items(List<PlatformMenu> menus) =>
    <String, PlatformMenuItem>{
      for (final menu in menus)
        for (final item in menu.menus) item.label: item,
    };

void main() {
  testWidgets('native menus dispatch image commands and expose save shortcuts',
      (tester) async {
    final calls = <ImageEditorAction>[];
    final menus = await _buildMenus(
      tester,
      ImageEditorMenuActions(
        perform: calls.add,
        canSave: true,
        canUndo: true,
        canRedo: true,
      ),
    );
    expect(menus.map((menu) => menu.label), <String>['File', 'Edit', 'Image']);
    final items = _items(menus);

    items['Save']!.onSelected!();
    items['Undo']!.onSelected!();
    items['Redo']!.onSelected!();
    items['Crop and rotate']!.onSelected!();
    items['Draw']!.onSelected!();
    items['Text']!.onSelected!();
    items['Filters']!.onSelected!();
    items['Blur']!.onSelected!();
    items['Adjust']!.onSelected!();
    items['Close editor']!.onSelected!();
    expect(calls, <ImageEditorAction>[
      ImageEditorAction.save,
      ImageEditorAction.undo,
      ImageEditorAction.redo,
      ImageEditorAction.cropRotate,
      ImageEditorAction.paint,
      ImageEditorAction.text,
      ImageEditorAction.filter,
      ImageEditorAction.blur,
      ImageEditorAction.tune,
      ImageEditorAction.close,
    ]);

    final save = items['Save']!.shortcut! as SingleActivator;
    expect(save.trigger, LogicalKeyboardKey.keyS);
    expect(save.meta, isTrue);
    final close = items['Close editor']!.shortcut! as SingleActivator;
    expect(close.trigger, LogicalKeyboardKey.keyW);
    expect(close.meta, isTrue);
    final redo = items['Redo']!.shortcut! as SingleActivator;
    expect(redo.trigger, LogicalKeyboardKey.keyZ);
    expect(redo.meta, isTrue);
    expect(redo.shift, isTrue);
  });

  testWidgets('native disabled commands have no selectable callback',
      (tester) async {
    final menus = await _buildMenus(
      tester,
      ImageEditorMenuActions(
        perform: (_) => fail('A disabled menu must not dispatch'),
        canSave: false,
        canUndo: false,
        canRedo: false,
        busy: true,
      ),
    );
    for (final item in _items(menus).values) {
      expect(item.onSelected, isNull, reason: item.label);
    }
  });

  testWidgets('tool subeditors expose close without main image commands',
      (tester) async {
    final calls = <ImageEditorAction>[];
    final menus = await _buildMenus(
      tester,
      ImageEditorMenuActions(
        perform: calls.add,
        canSave: true,
        canUndo: true,
        canRedo: true,
        canEdit: false,
      ),
    );
    final items = _items(menus);
    for (final item in items.values) {
      if (item.label != 'Close editor') {
        expect(item.onSelected, isNull, reason: item.label);
      }
    }
    items['Close editor']!.onSelected!();
    expect(calls, <ImageEditorAction>[ImageEditorAction.close]);
  });

  testWidgets('native menu chrome follows the active application locale',
      (tester) async {
    final editor = ImageEditorMenuActions(
      perform: (_) {},
      canSave: true,
      canUndo: true,
      canRedo: true,
    );
    final german = await _buildMenus(
      tester,
      editor,
      locale: const Locale('de'),
    );
    expect(
      german.map((menu) => menu.label),
      <String>['Datei', 'Bearbeiten', 'Bild'],
    );
    expect(_items(german), contains('Speichern'));
    expect(_items(german), isNot(contains('Save')));

    final english = await _buildMenus(tester, editor);
    expect(english.map((menu) => menu.label), <String>['File', 'Edit', 'Image']);
    expect(_items(english), contains('Save'));
  });
}
