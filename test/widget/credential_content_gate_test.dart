import 'package:crisp_cloud/widgets/credential_content_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('never mounts protected content before initial authorization', (
    tester,
  ) async {
    var builds = 0;
    final barrier = ValueNotifier<Widget?>(const Text('Locked'));
    addTearDown(barrier.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<Widget?>(
          valueListenable: barrier,
          builder: (_, cover, child) =>
              CredentialContentGate(barrier: cover, child: child!),
          child: Builder(
            builder: (_) {
              builds++;
              return const Text('Private workspace');
            },
          ),
        ),
      ),
    );
    expect(builds, 0);
    expect(find.text('Private workspace', skipOffstage: false), findsNothing);
    barrier.value = null;
    await tester.pumpAndSettle();
    expect(builds, 1);
    expect(find.text('Private workspace'), findsOneWidget);
  });

  testWidgets(
    'text, caret and focus survive secure covers without accepting hidden input',
    (tester) async {
      final barrier = ValueNotifier<Widget?>(null);
      addTearDown(barrier.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<Widget?>(
            valueListenable: barrier,
            builder: (_, cover, child) =>
                CredentialContentGate(barrier: cover, child: child!),
            child: const Scaffold(body: TextField(autofocus: true)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Retained private text');
      final editor = tester.widget<EditableText>(find.byType(EditableText));
      editor.controller.selection = const TextSelection.collapsed(offset: 9);
      final element = find.byType(EditableText).evaluate().single;
      for (var i = 0; i < 3; i++) {
        barrier.value = const ColoredBox(
          color: Colors.white,
          child: Text('Checking credentials'),
        );
        await tester.pumpAndSettle();
        expect(
          find.byType(EditableText, skipOffstage: false).evaluate().single,
          same(element),
        );
        expect(editor.focusNode.hasFocus, isFalse);
        expect(find.byType(TextField).hitTestable(), findsNothing);
        expect(find.text('Retained private text'), findsNothing);
        barrier.value = null;
        await tester.pumpAndSettle();
        expect(find.byType(EditableText).evaluate().single, same(element));
        expect(editor.controller.text, 'Retained private text');
        expect(editor.controller.selection.baseOffset, 9);
        expect(editor.focusNode.hasFocus, isTrue);
      }
    },
  );
}
