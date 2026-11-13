import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/widgets/internal_viewer_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('missing font assets leave formatted Office reading available', (
    tester,
  ) async {
    final bytes = Uint8List.fromList(
      utf8.encode(r'{\rtf1\ansi READABLE_WITHOUT_FONT_ASSETS}'),
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMessageHandler('flutter/assets', (_) async => null);
    addTearDown(() => messenger.setMockMessageHandler('flutter/assets', null));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: InternalViewerDialog(
            file: FileItem(
              name: 'reading.rtf',
              isFolder: false,
              size: bytes.length,
            ),
            side: PanelSide.local,
            bytesOverride: bytes,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('READABLE_WITHOUT_FONT_ASSETS', findRichText: true),
      findsWidgets,
    );
    expect(find.textContaining('Bundled fonts could not load'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
