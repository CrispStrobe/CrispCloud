import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madedit2_hex/src/core/hex_byte_source.dart';
import 'package:madedit2_hex/src/core/hex_document.dart';
import 'package:madedit2_hex/src/ui/hex_editor.dart';
import 'package:madedit2_hex/src/ui/hex_editor_controller.dart';
import 'package:madedit2_hex/src/ui/hex_viewport.dart';

HexEditorController memoryController(List<int> bytes) => HexEditorController(
  HexDocument(MemoryHexByteSource(Uint8List.fromList(bytes))),
);

Future<void> disposeController(HexEditorController controller) async {
  await controller.settled;
  controller.dispose();
  await controller.document.close();
}

Future<void> mountEditor(
  WidgetTester tester,
  HexEditorController controller, {
  bool readOnly = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 720,
          height: 250,
          child: HexEditor(controller: controller, readOnly: readOnly),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

HexViewportPainter viewport(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(find.byKey(const ValueKey('hex-bytes-paint')))
            .painter!
        as HexViewportPainter;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'serialized nibble edits preserve the other nibble and undo exactly',
    () async {
      final controller = memoryController([0x12, 0x34]);
      addTearDown(() => disposeController(controller));

      final high = controller.typeHexDigit(0xa);
      final low = controller.typeHexDigit(0xb);
      await Future.wait([high, low]);
      expect(await controller.document.read(0, 2), [0xab, 0x34]);
      expect(controller.caretOffset, 1);
      expect(controller.caretNibble, 0);

      await controller.undo();
      expect(await controller.document.read(0, 2), [0xa2, 0x34]);
      await controller.undo();
      expect(await controller.document.read(0, 2), [0x12, 0x34]);
      expect(controller.isDirty, isFalse);
      await controller.redo();
      await controller.redo();
      expect(await controller.document.read(0, 2), [0xab, 0x34]);

      controller.insertMode = true;
      await controller.typeHexDigit(0);
      await controller.typeHexDigit(0xc);
      expect(await controller.document.read(0, 3), [0xab, 0x0c, 0x34]);
      controller.setSelection(1, 2);
      await controller.deleteSelection();
      expect(await controller.document.read(0, 2), [0xab, 0x34]);
    },
  );

  test(
    'selection replacement uses exact bytes with no encoding alignment',
    () async {
      // Looks like UTF-16 LE, but deleting byte 1 must delete only that byte.
      final controller = memoryController([0xff, 0xfe, 0x41, 0x00, 0x42, 0x00]);
      addTearDown(() => disposeController(controller));
      controller.setSelection(1, 2);
      await controller.deleteSelection();
      expect(await controller.document.read(0, 99), [
        0xff,
        0x41,
        0x00,
        0x42,
        0x00,
      ]);
      await controller.undo();
      expect(controller.selectionStart, 1);
      expect(controller.selectionEnd, 2);
      await controller.pasteText('00 7F 80');
      expect(await controller.document.read(0, 99), [
        0xff,
        0x00,
        0x7f,
        0x80,
        0x41,
        0x00,
        0x42,
        0x00,
      ]);
    },
  );

  test(
    'text paste writes one Latin-1 byte and invalid hex leaves data intact',
    () async {
      final controller = memoryController([0, 1, 2, 3]);
      addTearDown(() => disposeController(controller));
      controller.setSelection(1, 3, area: HexEditorArea.ascii);
      await controller.pasteText('é');
      expect(await controller.document.read(0, 99), [0, 0xe9, 3]);
      final revision = controller.document.revision;
      await expectLater(
        controller.pasteText('FF Z0', area: HexEditorArea.hex),
        throwsFormatException,
      );
      expect(controller.document.revision, revision);
      expect(await controller.document.read(0, 99), [0, 0xe9, 3]);
      await controller.undo();
      expect(await controller.document.read(0, 99), [0, 1, 2, 3]);
    },
  );

  test(
    'navigation cancels a delayed nibble read without editing new location',
    () async {
      final read = Completer<Uint8List>();
      var delayed = false;
      final controller = HexEditorController(
        HexDocument(
          CallbackHexByteSource(
            length: 2,
            read: (offset, count) {
              if (!delayed) {
                delayed = true;
                return read.future;
              }
              return Future.value(
                Uint8List.fromList(
                  [0x12, 0x34].sublist(offset, offset + count),
                ),
              );
            },
          ),
        ),
      );
      addTearDown(() => disposeController(controller));
      final edit = controller.typeHexDigit(0xa);
      await Future<void>.delayed(Duration.zero);
      controller.goToOffset(1);
      read.complete(Uint8List.fromList([0x12]));
      await edit;
      expect(controller.document.revision, 0);
      expect(controller.caretOffset, 1);
      expect(await controller.document.read(0, 2), [0x12, 0x34]);
    },
  );

  test(
    'search finds a pattern across read boundaries and searches backward',
    () async {
      final bytes = Uint8List(150000);
      bytes.setRange(65535, 65539, [0xa1, 0xb2, 0xc3, 0xd4]);
      bytes.setRange(140001, 140005, [0xa1, 0xb2, 0xc3, 0xd4]);
      final controller = memoryController(bytes);
      addTearDown(() => disposeController(controller));
      final pattern = Uint8List.fromList([0xa1, 0xb2, 0xc3, 0xd4]);
      expect(await controller.find(pattern, wrap: false), 65535);
      expect(controller.selectionLength, 4);
      expect(await controller.findNext(), 140001);
      expect(await controller.findPrevious(), 65535);
      controller.goToOffset(0);
      expect(await controller.find(pattern, forward: false), 140001);
    },
  );

  test('save-state refresh preserves input waiting for source bytes', () async {
    final pendingRead = Completer<Uint8List>();
    final controller = HexEditorController(
      HexDocument(
        CallbackHexByteSource(length: 1, read: (_, _) => pendingRead.future),
      ),
    );
    addTearDown(() => disposeController(controller));

    final edit = controller.typeHexDigit(0xa);
    await Future<void>.delayed(Duration.zero);
    controller.document.markSaved();
    controller.refresh();
    pendingRead.complete(Uint8List.fromList([0x12]));
    await edit;

    expect(await controller.document.read(0, 1), [0xa2]);
    expect(controller.isDirty, isTrue);
    expect(controller.caretNibble, 1);
  });

  test('canceling a search never moves the current selection', () async {
    final firstRead = Completer<Uint8List>();
    final controller = HexEditorController(
      HexDocument(
        CallbackHexByteSource(
          length: 4,
          read: (offset, length) => firstRead.future,
        ),
      ),
    );
    addTearDown(() => disposeController(controller));
    final search = controller.find(Uint8List.fromList([0xab]));
    await Future<void>.delayed(Duration.zero);
    controller.setSelection(2, 3);
    controller.cancelSearch();
    firstRead.complete(Uint8List.fromList([0xab, 0, 0, 0]));
    expect(await search, isNull);
    expect(controller.selectionStart, 2);
    expect(controller.selectionEnd, 3);
  });

  testWidgets(
    'keyboard nibble input, shift selection, and paste edit real bytes',
    (tester) async {
      final controller = memoryController([0x12, 0x34, 0x56, 0x78]);
      addTearDown(() {
        if (!controller.document.isClosed) {
          controller.dispose();
          unawaited(controller.document.close());
        }
      });
      await mountEditor(tester, controller);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyA, character: 'a');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB, character: 'b');
      await controller.settled;
      await tester.pump();
      expect(await controller.document.read(0, 4), [0xab, 0x34, 0x56, 0x78]);

      controller.goToOffset(1);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(controller.selectionStart, 1);
      expect(controller.selectionEnd, 3);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.getData') return {'text': '00 FF'};
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      await controller.settled;
      expect(await controller.document.read(0, 4), [0xab, 0x00, 0xff, 0x78]);
      await controller.undo();
      expect(await controller.document.read(0, 4), [0xab, 0x34, 0x56, 0x78]);
      await tester.pumpWidget(const SizedBox());
      await disposeController(controller);
    },
  );

  testWidgets('read-only widget allows navigation but blocks editing', (
    tester,
  ) async {
    final controller = memoryController([0x12, 0x34]);
    addTearDown(() {
      if (!controller.document.isClosed) {
        controller.dispose();
        unawaited(controller.document.close());
      }
    });
    await mountEditor(tester, controller, readOnly: true);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF, character: 'f');
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await controller.settled;
    expect(controller.document.revision, 0);
    expect(controller.caretNibble, 1);
    expect(await controller.document.read(0, 2), [0x12, 0x34]);
    await tester.pumpWidget(const SizedBox());
    await disposeController(controller);
  });

  testWidgets(
    'pointer hit testing edits a low nibble and drags byte selections',
    (tester) async {
      final controller = memoryController([0x12, 0x34, 0x56, 0x78]);
      addTearDown(() {
        if (!controller.document.isClosed) {
          controller.dispose();
          unawaited(controller.document.close());
        }
      });
      await mountEditor(tester, controller);
      final geometry = viewport(tester).geometry;
      final origin = tester.getTopLeft(
        find.byKey(const ValueKey('hex-bytes-paint')),
      );
      Offset point(int byte, int nibble) =>
          origin +
          Offset(
            geometry.x(geometry.hexColumn(byte) + nibble) +
                geometry.characterWidth / 2,
            geometry.headerHeight + geometry.rowHeight / 2,
          );
      await tester.tapAt(point(1, 1));
      expect(controller.caretOffset, 1);
      expect(controller.caretNibble, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF, character: 'f');
      await controller.settled;
      expect(await controller.document.read(0, 4), [0x12, 0x3f, 0x56, 0x78]);

      final drag = await tester.startGesture(point(0, 0));
      await drag.moveTo(point(2, 1));
      await tester.pump();
      await drag.up();
      expect(controller.selectionStart, 0);
      expect(controller.selectionEnd, 3);
      await tester.pumpWidget(const SizedBox());
      await disposeController(controller);
    },
  );

  testWidgets('long-press byte entry works with a touch keyboard dialog', (
    tester,
  ) async {
    final controller = memoryController([0x12, 0x34]);
    addTearDown(() {
      if (!controller.document.isClosed) {
        controller.dispose();
        unawaited(controller.document.close());
      }
    });
    await mountEditor(tester, controller);
    final geometry = viewport(tester).geometry;
    final origin = tester.getTopLeft(
      find.byKey(const ValueKey('hex-bytes-paint')),
    );
    await tester.longPressAt(
      origin +
          Offset(
            geometry.x(geometry.hexColumn(0)) + 2,
            geometry.headerHeight + geometry.rowHeight / 2,
          ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enter bytes…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'AA FF');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    await controller.settled;
    expect(await controller.document.read(0, 3), [0xaa, 0xff, 0x34]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await disposeController(controller);
  });

  testWidgets('only the newest async window paints at large offsets', (
    tester,
  ) async {
    final pending = <({int offset, int count, Completer<Uint8List> done})>[];
    final controller = HexEditorController(
      HexDocument(
        CallbackHexByteSource(
          length: 1 << 40,
          read: (offset, count) {
            final done = Completer<Uint8List>();
            pending.add((offset: offset, count: count, done: done));
            return done.future;
          },
        ),
      ),
    );
    addTearDown(() {
      if (!controller.document.isClosed) {
        controller.dispose();
        unawaited(controller.document.close());
      }
    });
    controller.goToOffset(1 << 35);
    await mountEditor(tester, controller);
    expect(pending.length, 1);
    expect(pending.first.offset, greaterThan(1 << 31));
    expect(pending.first.count, lessThan(512));
    final stale = pending.first;

    // Source reads are serialized. A new document revision whose window is
    // entirely edited memory can nevertheless finish before an old source read.
    // This models a late network response racing a more recent local edit.
    controller.document.replace(
      stale.offset,
      stale.count,
      Uint8List.fromList(List.filled(stale.count, 0xbb)),
    );
    controller.refresh();
    await tester.pump();
    await tester.pump();
    expect(pending.length, 1);
    expect(viewport(tester).base, stale.offset);
    expect(viewport(tester).bytes, everyElement(0xbb));

    stale.done.complete(Uint8List.fromList(List.filled(stale.count, 0xaa)));
    await tester.pump();
    await tester.pump();
    expect(viewport(tester).base, stale.offset);
    expect(viewport(tester).bytes, everyElement(0xbb));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await disposeController(controller);
  });

  testWidgets('failed range loads retry explicitly instead of looping', (
    tester,
  ) async {
    var calls = 0;
    final controller = HexEditorController(
      HexDocument(
        CallbackHexByteSource(
          length: 2,
          read: (_, _) async {
            if (++calls == 1) throw StateError('Temporary read failure');
            return Uint8List.fromList([0xab, 0xcd]);
          },
        ),
      ),
    );
    addTearDown(() {
      if (!controller.document.isClosed) {
        controller.dispose();
        unawaited(controller.document.close());
      }
    });
    await mountEditor(tester, controller);
    await tester.pump();
    expect(calls, 1);
    expect(find.text('Retry'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 1);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    expect(calls, 2);
    expect(viewport(tester).bytes, [0xab, 0xcd]);
    await tester.pumpWidget(const SizedBox());
    await disposeController(controller);
  });

  testWidgets('visible byte rows expose actionable screen-reader semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final controller = memoryController([0x41, 0x42, 0x00, 0xff]);
    addTearDown(() {
      if (!controller.document.isClosed) {
        controller.dispose();
        unawaited(controller.document.close());
      }
    });
    await mountEditor(tester, controller);
    await tester.pump();
    expect(find.semantics.byLabel('Offset 0x0: 41 42 00 FF'), findsOne);
    expect(find.semantics.byLabel('Scroll bytes'), findsOne);
    await tester.pumpWidget(const SizedBox());
    await disposeController(controller);
    semantics.dispose();
  });
}
