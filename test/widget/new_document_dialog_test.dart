import 'package:crisp_cloud/widgets/new_document_dialog.dart';
import 'package:crisp_cloud/services/new_document.dart';
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
      await tester.tap(
        find.byKey(const ValueKey('new-document-kind-spreadsheet')),
      );
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
  testWidgets(
    'format tiles stay reachable on a narrow screen with large text',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Scaffold(
            body: NewDocumentDialog(
              directory: '/tmp',
              onCreate: (_, __) async => throw StateError('not creating'),
            ),
          ),
        ),
      );
      for (final kind in NewDocumentKind.values) {
        final tile = find.byKey(ValueKey('new-document-kind-${kind.name}'));
        await tester.ensureVisible(tile);
        await tester.tap(tile);
        await tester.pump();
        final input = tester.widget<TextField>(
          find.byKey(const ValueKey('new-document-name')),
        );
        expect(input.controller!.text, endsWith('.${kind.extension}'));
        expect(tester.takeException(), isNull);
      }
    },
  );
}
