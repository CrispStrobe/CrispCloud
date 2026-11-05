import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/widgets/file_editor_dialog.dart';
import 'package:crisp_cloud/widgets/image_editor_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _openFile(WidgetTester tester, FileItem file) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  showFileEditorDialog(context, ref, file, PanelSide.local),
              child: const Text('Open file with F4 dispatcher'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open file with F4 dispatcher'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('F4 dispatches supported raster images before loading bytes', (
    tester,
  ) async {
    await _openFile(
      tester,
      FileItem(name: 'large.PNG', isFolder: false, size: 1024 * 1024 * 1024),
    );

    expect(find.byType(ImageEditorDialog), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('F4 dispatches WebP before reading bytes', (tester) async {
    await _openFile(
      tester,
      FileItem(name: 'large.webp', isFolder: false, size: 1024 * 1024 * 1024),
    );
    expect(find.byType(ImageEditorDialog), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('F4 dispatches GIF before reading bytes', (tester) async {
    await _openFile(
      tester,
      FileItem(name: 'large.gif', isFolder: false, size: 1024 * 1024 * 1024),
    );
    expect(find.byType(ImageEditorDialog), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('F4 rejects unsupported image formats instead of editing bytes', (
    tester,
  ) async {
    await _openFile(tester, FileItem(name: 'drawing.svg', isFolder: false));

    expect(find.byType(ImageEditorDialog), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(
      find.text('This file type cannot be edited here. Use F3 to view it.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an image-like folder cannot open an editor', (tester) async {
    await _openFile(tester, FileItem(name: 'photos.png', isFolder: true));
    expect(find.byType(ImageEditorDialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
