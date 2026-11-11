import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/widgets/editor_chooser_dialog.dart';

void main() {
  for (final name in <String>['Info.plist', 'server.crt', 'blob.bin']) {
    testWidgets('$name offers text, hex and system editors', (tester) async {
      await _expectAllEditors(tester, name);
    });
  }
}

Future<void> _expectAllEditors(WidgetTester tester, String name) async {
  {
    final file = FileItem(name: name, path: '/tmp/$name', isFolder: false);
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
  }
}
