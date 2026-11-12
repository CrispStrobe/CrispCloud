import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/services/editor_document.dart';
import 'package:crisp_cloud/services/legacy_text_encoding.dart';
import 'package:crisp_cloud/widgets/code_editor_status_bar.dart';
import 'package:crisp_cloud/widgets/internal_viewer_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final encoding in [EditorEncoding.cp437, EditorEncoding.windows1252]) {
    testWidgets(
      'F3 ${encoding.label} selection renders and searches original bytes',
      (tester) async {
        final text = encoding == EditorEncoding.cp437 ? 'café ┌─┐' : 'café “€”';
        final bytes = encodeLegacyText(text, encoding.name);
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: InternalViewerDialog(
                file: FileItem(
                  name: 'text.txt',
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
        await tester.tap(find.byTooltip('Encoding'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(encoding.label));
        await tester.pumpAndSettle();
        expect(find.text(text, findRichText: true), findsOneWidget);
        await tester.tap(find.byTooltip('Search (Ctrl+F)'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('viewer-search-input')),
          text,
        );
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        expect(find.text('1/1'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('F4 picker exposes ${encoding.label} without a BOM action', (
      tester,
    ) async {
      EditorEncoding? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: CodeEditorStatusBar(
                cursorLine: 1,
                cursorColumn: 1,
                lineCount: 1,
                language: null,
                lineEnding: EditorLineEnding.crlf,
                encoding: encoding,
                isModified: false,
                isSaving: false,
                hadMixedLineEndings: false,
                onLineEndingSelected: (_) {},
                onEncodingSelected: (value) => selected = value,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('File encoding'));
      await tester.pumpAndSettle();
      expect(find.text('Write byte-order mark (BOM)'), findsNothing);
      await tester.tap(find.text('✓ ${encoding.label}'));
      await tester.pumpAndSettle();
      expect(selected, encoding);
      expect(tester.takeException(), isNull);
    });
  }
}
