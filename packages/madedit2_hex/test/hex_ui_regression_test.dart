import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madedit2_hex/madedit2_hex.dart';

class _DeferredSource implements HexByteSource {
  _DeferredSource(this.bytes);

  final Uint8List bytes;
  final pending = Completer<Uint8List>();
  final started = Completer<void>();
  int? _offset;
  int? _count;

  @override
  int get length => bytes.length;

  @override
  Future<Uint8List> read(int offset, int count) {
    if (!started.isCompleted) {
      _offset = offset;
      _count = count;
      started.complete();
      return pending.future;
    }
    return Future.value(
      Uint8List.fromList(bytes.sublist(offset, offset + count)),
    );
  }

  void complete() => pending.complete(
    Uint8List.fromList(bytes.sublist(_offset!, _offset! + _count!)),
  );
}

Future<void> _mountNarrowEditor(
  WidgetTester tester,
  HexEditorController controller,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 320,
          height: 500,
          child: HexEditor(controller: controller),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ScrollController _horizontalController(WidgetTester tester) => tester
    .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
    .singleWhere((view) => view.controller != null)
    .controller!;

void main() {
  test(
    'navigation keeps its selection when an older search finishes',
    () async {
      final source = _DeferredSource(Uint8List.fromList([0xab, 0, 0, 0]));
      final controller = HexEditorController(HexDocument(source));
      addTearDown(controller.dispose);

      final search = controller.findNext(
        Uint8List.fromList([0xab]),
        wrap: false,
      );
      await source.started.future;
      await controller.select(3);
      source.complete();

      expect(await search, isNull);
      expect(controller.caret, 3);
      expect(controller.anchor, 3);
      expect(controller.searching, isFalse);
      expect(controller.error, isNull);
    },
  );

  testWidgets('queued navigation takes priority over an older search result', (
    tester,
  ) async {
    final source = _DeferredSource(Uint8List.fromList([0xab, 0, 0, 0]));
    final controller = HexEditorController(HexDocument(source));
    addTearDown(controller.dispose);
    final clipboardStarted = Completer<void>();
    final clipboard = Completer<Map<String, dynamic>?>();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        clipboardStarted.complete();
        return clipboard.future;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    final search = controller.findNext(Uint8List.fromList([0xab]), wrap: false);
    await source.started.future;
    final paste = controller.paste();
    await clipboardStarted.future;
    final navigation = controller.select(3);
    source.complete();
    // Let the search finish reading while the command queue waits for the
    // clipboard. Its result must remain behind the user's queued navigation.
    await tester.pump();
    clipboard.complete(null);
    await Future.wait([paste, navigation]);

    expect(await search, isNull);
    expect(controller.caret, 3);
    expect(controller.anchor, 3);
    expect(controller.searching, isFalse);
  });

  testWidgets('keyboard navigation reveals hex bytes on narrow screens', (
    tester,
  ) async {
    final controller = HexEditorController(
      HexDocument(MemoryHexByteSource(List.filled(32, 0))),
    );
    addTearDown(controller.dispose);
    await _mountNarrowEditor(tester, controller);
    final horizontal = _horizontalController(tester);
    expect(horizontal.offset, 0);

    await controller.select(15);
    await tester.pumpAndSettle();
    expect(horizontal.offset, greaterThan(0));

    await controller.select(0);
    await tester.pumpAndSettle();
    expect(horizontal.offset, lessThanOrEqualTo(150));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('switching input columns reveals the text caret', (tester) async {
    final controller = HexEditorController(
      HexDocument(MemoryHexByteSource([0x41, 0x42])),
    );
    addTearDown(controller.dispose);
    await _mountNarrowEditor(tester, controller);
    final horizontal = _horizontalController(tester);
    expect(horizontal.offset, 0);

    await controller.setArea(HexArea.ascii);
    await tester.pumpAndSettle();
    expect(horizontal.offset, greaterThan(0));
    expect(controller.caret, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
