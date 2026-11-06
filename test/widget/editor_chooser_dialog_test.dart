import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/widgets/editor_chooser_dialog.dart';

void main() {
  testWidgets('a plist offers text, hex and system editors', (tester) async {
    final file = FileItem(
      name: 'Info.plist',
      path: '/tmp/Info.plist',
      isFolder: false,
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => ElevatedButton(
                onPressed: () =>
                    showEditorChooser(context, ref, file, PanelSide.local),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Open with…'), findsOneWidget);
    expect(find.text('Text / Code Editor'), findsOneWidget);
    expect(find.text('Hex Editor'), findsOneWidget);
    expect(find.text('System Editor'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
