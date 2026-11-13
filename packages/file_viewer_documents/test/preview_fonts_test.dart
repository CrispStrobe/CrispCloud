// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:file_viewer_documents/file_viewer_documents.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('invalid shared-font configuration never opens a browser host', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DocumentPreview(
          bytes: Uint8List.fromList([1]),
          filename: 'example.xls',
          kind: DocumentPreviewKind.spreadsheet,
          fonts: const [
            DocumentPreviewFont(
              asset: 'https://untrusted.invalid/font.ttf',
              family: 'Unexpected',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('The document font configuration is invalid.'),
      findsOneWidget,
    );
    expect(find.byType(Texture), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
