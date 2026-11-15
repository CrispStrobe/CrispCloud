import 'package:crisp_cloud/widgets/new_document_dialog.dart';
import 'package:crisp_cloud/services/new_document.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'chooser starts requested editor format and keeps a collision open for retry',
    (tester) async {
      var attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NewDocumentDialog(
              directory: '/tmp',
              onCreate: (kind, name) async {
                attempts++;
                expect(kind, NewDocumentKind.spreadsheet);
                expect(name, 'Untitled.xlsx');
                throw StateError('A file already exists');
              },
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('new-document-kind')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Spreadsheet (.xlsx)').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('new-document-create')));
      await tester.pumpAndSettle();
      expect(attempts, 1);
      expect(find.textContaining('A file already exists'), findsOneWidget);
      expect(find.byKey(const ValueKey('new-document-dialog')), findsOneWidget);
    },
  );
  testWidgets('converter entry is reachable without creating a document', (
    tester,
  ) async {
    var converted = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NewDocumentDialog(
            directory: '/tmp',
            onCreate: (_, __) async => throw StateError('must not create'),
            onConvert: () => converted = true,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('new-document-convert')));
    expect(converted, isTrue);
  });
}
