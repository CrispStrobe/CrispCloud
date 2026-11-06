import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madedit2_hex/madedit2_hex.dart';

class SyntheticSource implements HexByteSource {
  SyntheticSource(this.length);
  @override final int length;
  int reads = 0, maximumRead = 0;
  @override Future<Uint8List> read(int offset, int length) async {
    reads++; maximumRead = max(maximumRead, length);
    return Uint8List.fromList(List.generate(length, (i) => (offset + i) % 251));
  }
}
class ShortSource implements HexByteSource {
  @override int get length => 10;
  @override Future<Uint8List> read(int offset, int count) async => Uint8List(count - 1);
}

void main() {
  test('persistent rope matches a reference model over random edits and history', () async {
    final random = Random(836);
    final doc = HexDocument(MemoryHexByteSource(List.generate(512, (i) => i % 256)), maxUndoSteps: 1500);
    var expected = List.generate(512, (i) => i % 256);
    final undo = <List<int>>[], redo = <List<int>>[];
    for (var step = 0; step < 1200; step++) {
      final action = random.nextInt(8);
      if (action == 0 && undo.isNotEmpty) {
        redo.add(List.of(expected)); expected = undo.removeLast(); expect(doc.undo(), isTrue);
      } else if (action == 1 && redo.isNotEmpty) {
        undo.add(List.of(expected)); expected = redo.removeLast(); expect(doc.redo(), isTrue);
      } else {
        final at = random.nextInt(expected.length + 1);
        final remove = random.nextInt(min(12, expected.length - at) + 1);
        final add = List.generate(random.nextInt(12) + 1, (_) => random.nextInt(256));
        final old = doc.snapshot, previous = List.of(expected);
        undo.add(previous); redo.clear();
        expected.replaceRange(at, at + remove, add);
        doc.replace(at, remove, add);
        expect(await old.read(0, old.length), previous, reason: 'old snapshot at $step');
      }
      expect(doc.length, expected.length);
      expect(await doc.read(0, doc.length), expected, reason: 'edit $step');
      expect(doc.debugTreeHeight, lessThan(30));
    }
  });
  test('huge file edits do not scan original bytes and offsets exceed 32 bits', () async {
    final source = SyntheticSource(6 * 1024 * 1024 * 1024);
    final doc = HexDocument(source);
    final offset = 5 * 1024 * 1024 * 1024;
    doc.insert(offset, [255, 254]);
    expect(source.reads, 0);
    expect(await doc.read(offset, 3), [255, 254, offset % 251]);
    expect(source.maximumRead, 1);
    expect(hexOffsetDigits(doc.length), 9);
  });
  test('short original reads are errors, never silent zero padding', () async {
    final doc = HexDocument(ShortSource());
    await expectLater(doc.read(0, 10), throwsStateError);
  });
  test('branching after undo never reuses a saved revision', () {
    final doc = HexDocument(MemoryHexByteSource([1, 2]));
    doc.overwrite(0, [3]); final saved = doc.snapshot; doc.markSaved(saved);
    doc.undo(); doc.overwrite(0, [4]);
    expect(doc.isDirty, isTrue); expect(doc.revision, greaterThan(saved.revision));
    expect(() => doc.markSaved(HexDocument(MemoryHexByteSource([])).snapshot), throwsArgumentError);
  });
  test('input buffers cannot mutate document or snapshots', () async {
    final bytes = Uint8List.fromList([1, 2]);
    final doc = HexDocument(MemoryHexByteSource(bytes)); bytes[0] = 99;
    final add = [3, 4]; doc.insert(1, add); add[0] = 88;
    final read = await doc.read(0, 4); read[0] = 55;
    expect(await doc.read(0, 4), [1, 3, 4, 2]);
  });
  test('search crosses chunk and piece boundaries, supports cancellation', () async {
    final doc = HexDocument(MemoryHexByteSource(List.filled(65540, 0)));
    doc.overwrite(65535, [1, 2, 3]);
    expect(await doc.snapshot.find([1, 2, 3]), 65535);
    expect(await doc.snapshot.find([2, 3, 4]), isNull);
    await expectLater(doc.snapshot.find([9], cancelled: () => true), throwsA(isA<HexSearchCancelled>()));
    final chunks = await doc.snapshot.chunks(chunkSize: 1000, start: 65534, count: 5).toList();
    expect(chunks.single, [0, 1, 2, 3, 0]);
  });
  test('strict hex parser rejects malformed clipboard text', () {
    expect(parseHexBytes('0xAA 00 ff\n10'), [170, 0, 255, 16]);
    expect(() => parseHexBytes('abc'), throwsFormatException);
    expect(() => parseHexBytes('Hello FF'), throwsFormatException);
  });
  testWidgets('two nibble keystrokes are one undo step; raw deletion ignores display codec', (tester) async {
    final doc = HexDocument(MemoryHexByteSource([0x12, 0x34, 0x56]));
    final c = HexEditorController(doc); addTearDown(c.dispose);
    await c.typeDigit(0xa); await c.typeDigit(0xb);
    expect(await doc.read(0, 3), [0xab, 0x34, 0x56]);
    await c.undo(); expect(await doc.read(0, 3), [0x12, 0x34, 0x56]);
    await c.redo(); expect(await doc.read(0, 3), [0xab, 0x34, 0x56]);
    await c.setLatin1(true); await c.select(1); await c.delete();
    expect(await doc.read(0, 2), [0xab, 0x56]);
  });
  testWidgets('queued input appends at EOF and readonly commands do not mutate', (tester) async {
    final doc = HexDocument(MemoryHexByteSource([])); final c = HexEditorController(doc);
    addTearDown(c.dispose);
    final first = c.typeDigit(15), second = c.typeDigit(10); await Future.wait([first, second]);
    expect(await doc.read(0, 1), [250]);
    c.readOnly = true; expect(await c.typeDigit(0), isFalse);
    expect(doc.length, 1); expect(c.error, contains('read-only'));
  });
  testWidgets('native surface handles keys, undo and a narrow screen', (tester) async {
    final c = HexEditorController(HexDocument(MemoryHexByteSource([0x12, 0x34])));
    addTearDown(c.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(width: 320, height: 500,
      child: HexEditor(controller: c, showKeypad: true)))));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pumpAndSettle();
    expect(await c.document.read(0, 2), [0xab, 0x34]);
    await tester.tap(find.byTooltip('Undo')); await tester.pumpAndSettle();
    expect(await c.document.read(0, 2), [0x12, 0x34]);
    expect(tester.takeException(), isNull);
  });
}
