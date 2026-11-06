import 'dart:async';

import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/services/hex_edit_session.dart';
import 'package:crisp_cloud/widgets/hex_editor_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madedit2_hex/madedit2_hex.dart';

import '../support/hex_memory_backend.dart';

void main() {
  Future<HexEditSession> open(HexMemoryBackend backend) async =>
      HexEditSession.open(
        backend: backend,
        file: (await backend.stat('/sample.bin'))!,
        inMemory: true,
      );

  Future<void> showEditor(WidgetTester tester, HexEditSession session) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('Open binary'),
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => HexEditorDialog(
                      file: session.file,
                      side: PanelSide.local,
                      sessionOverride: session,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open binary'));
    await tester.pumpAndSettle();
  }

  test('parses exact byte pairs and decimal or explicit hex offsets', () {
    expect(parseHexEditorBytes('00 ff 7A\n10'), [0, 255, 122, 16]);
    expect(parseHexEditorBytes('aabb'), [170, 187]);
    expect(() => parseHexEditorBytes('abc'), throwsFormatException);
    expect(() => parseHexEditorBytes('gg'), throwsFormatException);
    expect(parseHexEditorOffset('10', 30), 10);
    expect(parseHexEditorOffset('0x10', 30), 16);
    expect(parseHexEditorOffset('0X1E', 30), 30);
    expect(parseHexEditorOffset('31', 30), isNull);
    expect(parseHexEditorOffset('-1', 30), isNull);
    expect(parseHexEditorOffset('1e1', 30), isNull);
  });

  testWidgets('failed save retains byte edits and can be retried', (
    tester,
  ) async {
    final backend = HexMemoryBackend([1, 2, 3])..failWrite = true;
    final session = await open(backend);
    addTearDown(session.close);
    await showEditor(tester, session);
    final controller = tester
        .widget<HexEditor>(find.byType(HexEditor))
        .controller;
    session.document.overwrite(1, [9]);
    controller.refresh();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('hex-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Save failed'), findsOneWidget);
    expect(session.isDirty, isTrue);
    expect(backend.bytes, [1, 2, 3]);
    expect(await session.document.read(0, 3), [1, 9, 3]);
    backend.failWrite = false;
    await tester.tap(find.byKey(const ValueKey('hex-save')));
    await tester.pumpAndSettle();
    expect(backend.bytes, [1, 9, 3]);
    expect(session.isDirty, isFalse);
    expect(find.textContaining('Save failed'), findsNothing);
  });

  testWidgets('unsaved close allows cancel or explicit discard', (
    tester,
  ) async {
    final session = await open(HexMemoryBackend([1, 2, 3]));
    addTearDown(session.close);
    await showEditor(tester, session);
    final controller = tester
        .widget<HexEditor>(find.byType(HexEditor))
        .controller;
    session.document.insert(3, [4]);
    controller.refresh();
    await tester.pump();
    await tester.tap(find.byTooltip('Close').first);
    await tester.pumpAndSettle();
    expect(find.text('Save changes to this binary file?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(HexEditor), findsOneWidget);
    expect(session.isDirty, isTrue);
    await tester.tap(find.byTooltip('Close').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(HexEditor), findsNothing);
    expect(find.text('Open binary'), findsOneWidget);
  });

  testWidgets('host reports newer edits after an in-flight save', (
    tester,
  ) async {
    final backend = HexMemoryBackend([1, 2, 3]);
    final session = await open(backend);
    addTearDown(session.close);
    await showEditor(tester, session);
    final controller = tester
        .widget<HexEditor>(find.byType(HexEditor))
        .controller;
    final stage = Completer<void>();
    final resume = Completer<void>();
    backend.afterStage = () async {
      stage.complete();
      await resume.future;
    };
    session.document.overwrite(0, [8]);
    controller.refresh();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('hex-save')));
    await tester.pump();
    expect(stage.isCompleted, isTrue);
    session.document.overwrite(1, [9]);
    controller.refresh();
    resume.complete();
    await tester.pumpAndSettle();
    expect(backend.bytes, [8, 2, 3]);
    expect(session.isDirty, isTrue);
    expect(find.text('Saved; newer edits remain unsaved.'), findsOneWidget);
  });
}
