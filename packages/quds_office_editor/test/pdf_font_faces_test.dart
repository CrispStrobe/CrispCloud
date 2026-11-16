import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show RenderProxyBox;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_editor/src/editor_pdf/pdf_font_faces.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(PdfFontFaces.debugReset);
  tearDown(PdfFontFaces.debugReset);

  test(
    'all pending consumers finish once and identical copies share a face',
    () async {
      final completion = Completer<void>();
      var loads = 0;
      PdfFontFaces.debugLoadFont = (family, bytes) {
        loads++;
        return completion.future;
      };
      final bytes = _bytes(1);
      final copy = Uint8List.fromList(bytes);
      var first = 0;
      var second = 0;
      void onFirst() => first++;
      void onSecond() => second++;
      PdfFontFaces.ensure(bytes, onFirst);
      PdfFontFaces.ensure(bytes, onFirst);
      PdfFontFaces.ensure(copy, onSecond);
      expect(loads, 1);
      expect(_ready(bytes), isFalse);
      expect(PdfFontFaces.familyFor(copy, 'Helvetica'), 'Liberation Sans');
      completion.complete();
      await _flush();
      expect((first, second), (1, 1));
      expect(_ready(bytes), isTrue);
      final family = PdfFontFaces.familyFor(bytes, 'Helvetica');
      expect(PdfFontFaces.isEmbedded(family), isTrue);
      expect(PdfFontFaces.familyFor(copy, 'Helvetica'), family);
      expect(
        PdfFontFaces.familyFor(Uint8List.fromList(copy), 'Helvetica'),
        family,
      );
      PdfFontFaces.ensure(copy, onSecond);
      expect((loads, first, second), (1, 1, 1));
    },
  );

  test('failed loading notifies all waiters and remains terminal', () async {
    final completion = Completer<void>();
    var loads = 0;
    PdfFontFaces.debugLoadFont = (family, bytes) {
      loads++;
      return completion.future;
    };
    final bytes = _bytes(2);
    var first = 0;
    var second = 0;
    PdfFontFaces.ensure(bytes, () => first++);
    PdfFontFaces.ensure(Uint8List.fromList(bytes), () => second++);
    completion.completeError(StateError('Font is not loadable'));
    await _flush();
    expect((loads, first, second), (1, 1, 1));
    expect(_ready(bytes), isTrue, reason: 'Fallback can now be rasterized');
    expect(PdfFontFaces.familyFor(bytes, 'Times-Roman'), 'Times New Roman');
    PdfFontFaces.ensure(bytes, () => first++);
    PdfFontFaces.ensure(Uint8List.fromList(bytes), () => second++);
    await _flush();
    expect((loads, first, second), (1, 1, 1));
  });

  test(
    'registration owns a read-only snapshot while caller bytes change',
    () async {
      final completion = Completer<void>();
      final loaded = <Uint8List>[];
      PdfFontFaces.debugLoadFont = (family, bytes) {
        loaded.add(bytes);
        return completion.future;
      };
      final bytes = _bytes(3);
      final original = Uint8List.fromList(bytes);
      PdfFontFaces.ensure(bytes, () {});
      bytes[8] ^= 0xff;
      expect(loaded.single, orderedEquals(original));
      expect(() => loaded.single[8] = 0, throwsUnsupportedError);
      completion.complete();
      await _flush();
      final family = PdfFontFaces.familyFor(bytes, 'Helvetica');
      // The original buffer keeps its first registered snapshot. A fresh buffer
      // is how a caller explicitly supplies a changed font.
      PdfFontFaces.ensure(Uint8List.fromList(bytes), () {});
      await _flush();
      expect(loaded, hasLength(2));
      expect(loaded.last, orderedEquals(bytes));
      expect(PdfFontFaces.familyFor(original, 'Helvetica'), family);
      expect(
        PdfFontFaces.familyFor(Uint8List.fromList(bytes), 'Helvetica'),
        isNot(family),
      );
    },
  );

  test(
    'removing a consumer leaves the other pending consumers intact',
    () async {
      final completion = Completer<void>();
      PdfFontFaces.debugLoadFont = (family, bytes) => completion.future;
      var removed = 0;
      var retained = 0;
      void onRemoved() => removed++;
      void onRetained() => retained++;
      final bytes = _bytes(4);
      PdfFontFaces.ensure(bytes, onRemoved);
      PdfFontFaces.ensure(bytes, onRetained);
      PdfFontFaces.removeListener(onRemoved);
      completion.complete();
      await _flush();
      expect((removed, retained), (0, 1));
    },
  );

  test(
    'one consumer error does not corrupt a loaded face or stop fanout',
    () async {
      final completion = Completer<void>();
      PdfFontFaces.debugLoadFont = (family, bytes) => completion.future;
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = errors.add;
      try {
        var notified = false;
        final bytes = _bytes(5);
        PdfFontFaces.ensure(bytes, () => throw StateError('consumer failed'));
        PdfFontFaces.ensure(bytes, () => notified = true);
        completion.complete();
        await _flush();
        expect(notified, isTrue);
        expect(errors, hasLength(1));
        expect(
          PdfFontFaces.isEmbedded(PdfFontFaces.familyFor(bytes, 'Helvetica')),
          isTrue,
        );
      } finally {
        FlutterError.onError = previous;
      }
    },
  );

  test(
    'evicting content snapshots preserves active font buffer bindings',
    () async {
      var loads = 0;
      PdfFontFaces.debugLoadFont = (family, bytes) async {
        loads++;
      };
      final first = _bytes(6);
      PdfFontFaces.ensure(first, () {});
      await _flush();
      final family = PdfFontFaces.familyFor(first, 'Helvetica');
      for (var i = 0; i < 140; i++) {
        PdfFontFaces.ensure(_bytes(1000 + i), () {});
        await _flush();
      }
      expect(loads, 141);
      expect(PdfFontFaces.familyFor(first, 'Helvetica'), family);
      expect(_ready(first), isTrue);
      PdfFontFaces.ensure(first, () => fail('Already loaded'));
      expect(loads, 141);
    },
  );

  test(
    'valid fonts colliding under the old sampled key render separately',
    () async {
      final sans = _font('LiberationSans-Regular');
      final serif = _font('LiberationSerif-Regular');
      final rawSans = FontSubsetter(sans).subset('AMW'.runes).bytes;
      final rawSerif = FontSubsetter(serif).subset('AMW'.runes).bytes;
      // SFNT tables carry their own lengths. Trailing zero padding is legal and
      // keeps the checksum valid. All old sample positions are now zero in both
      // otherwise different real fonts; their outlines and advances are intact.
      final length = 4 * math.max(rawSans.length, rawSerif.length).toInt() + 4;
      final bytesSans = Uint8List(length)..setAll(0, rawSans);
      final bytesSerif = Uint8List(length)..setAll(0, rawSerif);
      expect(_oldKey(bytesSans), _oldKey(bytesSerif));
      expect(listEquals(bytesSans, bytesSerif), isFalse);
      expect(SfntFont.parse(bytesSans).glyphIdFor(0x41), greaterThan(0));
      expect(SfntFont.parse(bytesSerif).glyphIdFor(0x41), greaterThan(0));
      await Future.wait([_ensure(bytesSans), _ensure(bytesSerif)]);
      final familySans = PdfFontFaces.familyFor(bytesSans, 'Helvetica');
      final familySerif = PdfFontFaces.familyFor(bytesSerif, 'Times-Roman');
      expect(PdfFontFaces.isEmbedded(familySans), isTrue);
      expect(PdfFontFaces.isEmbedded(familySerif), isTrue);
      expect(familySans, isNot(familySerif));
      final painterSans = _painter(familySans);
      final painterSerif = _painter(familySerif);
      try {
        expect(
          painterSans.width,
          closeTo(
            FontMetrics(font: sans, fontSizePoints: 32).characterWidth(0x41),
            0.001,
          ),
        );
        expect(
          painterSerif.width,
          closeTo(
            FontMetrics(font: serif, fontSizePoints: 32).characterWidth(0x41),
            0.001,
          ),
        );
        expect(painterSans.width, isNot(painterSerif.width));
        expect(
          listEquals(await _pixels(painterSans), await _pixels(painterSerif)),
          isFalse,
          reason: 'Both actual Flutter font loads paint their own outlines',
        );
      } finally {
        painterSans.dispose();
        painterSerif.dispose();
      }
    },
  );

  testWidgets('independent canvases repaint after one shared load completes', (
    tester,
  ) async {
    final completion = Completer<void>();
    PdfFontFaces.debugLoadFont = (family, bytes) => completion.future;
    final bytes = _bytes(7);
    final list = _displayList(bytes);
    final draws = [0, 0];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: [
            for (var i = 0; i < 2; i++)
              SizedBox(
                width: 200,
                height: 240,
                child: RepaintBoundary(
                  child: PdfCanvasView(
                    lists: [list],
                    viewport: VirtualViewport(),
                    scale: 1,
                    config: const OfficeSurfaceConfig(),
                    onDraw: (canvas, size, page) => draws[i]++,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    expect(draws.every((value) => value > 0), isTrue);
    final before = List<int>.of(draws);
    completion.complete();
    await tester.pump();
    await tester.pump();
    for (var i = 0; i < 2; i++) {
      expect(draws[i], greaterThan(before[i]), reason: 'Canvas $i repaint');
    }
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing a canvas and thumbnail removes pending listeners', (
    tester,
  ) async {
    final completion = Completer<void>();
    PdfFontFaces.debugLoadFont = (family, bytes) => completion.future;
    final list = _displayList(_bytes(8));
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: [
            SizedBox(
              width: 200,
              height: 240,
              child: PdfCanvasView(
                lists: [list],
                viewport: VirtualViewport(),
                scale: 1,
                config: const OfficeSurfaceConfig(),
              ),
            ),
            SizedBox(width: 100, child: PdfPageThumb(list: list)),
          ],
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    completion.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  for (final thumbnail in [false, true]) {
    final surface = thumbnail ? 'thumbnail' : 'canvas';
    testWidgets(
      'reparented retained $surface observes pending font completion',
      (tester) async {
        final completion = Completer<void>();
        PdfFontFaces.debugLoadFont = (family, bytes) => completion.future;
        final list = _displayList(_bytes(thumbnail ? 9 : 10));
        var draws = 0;
        final page = _countedSurface(list, thumbnail, () => draws++);
        final retained = RepaintBoundary(
          key: GlobalKey(),
          child: SizedBox(width: 200, height: 240, child: page),
        );
        Widget tree(bool moved) => Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            children: [
              Padding(
                key: const ValueKey('first'),
                padding: EdgeInsets.zero,
                child: moved
                    ? const SizedBox(width: 200, height: 240)
                    : retained,
              ),
              Padding(
                key: const ValueKey('second'),
                padding: EdgeInsets.zero,
                child: moved
                    ? retained
                    : const SizedBox(width: 200, height: 240),
              ),
            ],
          ),
        );
        await tester.pumpWidget(tree(false));
        final beforeMove = draws;
        // The same widget and repaint boundary move without updating the leaf's
        // properties. A retained layer must not suppress listener reattachment.
        await tester.pumpWidget(tree(true));
        final afterMove = draws;
        completion.complete();
        await tester.pump();
        await tester.pump();
        final afterFont = draws;
        await tester.pumpWidget(const SizedBox.shrink());
        expect(afterMove, greaterThan(beforeMove));
        expect(afterFont, greaterThan(afterMove));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('reattached retained $surface refreshes a completed font', (
      tester,
    ) async {
      final completion = Completer<void>();
      PdfFontFaces.debugLoadFont = (family, bytes) => completion.future;
      final bytes = _bytes(thumbnail ? 11 : 12);
      final list = _displayList(bytes);
      var draws = 0;
      final page = _countedSurface(list, thumbnail, () => draws++);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RepaintBoundary(
            child: SizedBox(width: 200, height: 240, child: page),
          ),
        ),
      );
      final render = tester.renderObject<RenderObject>(find.byWidget(page));
      final parent = render.parent! as RenderProxyBox;
      final before = draws;
      // Remove and re-adopt through the real parent's child contract: directly
      // detaching a leaf whose parent is still attached is invalid in Flutter.
      // The font completes while the same render object is legally detached;
      // no frame is rendered during that interval.
      var completedWhileDetached = false;
      try {
        parent.child = null;
        completion.complete();
        await Future<void>.value();
        completedWhileDetached = _ready(bytes);
      } finally {
        if (!completion.isCompleted) completion.complete();
        parent.child = render as RenderBox;
      }
      await tester.pump();
      await tester.pump();
      final after = draws;
      await tester.pumpWidget(const SizedBox.shrink());
      expect(completedWhileDetached, isTrue);
      expect(after, greaterThan(before));
      expect(tester.takeException(), isNull);
    });
  }
}

Widget _countedSurface(
  PdfDisplayList list,
  bool thumbnail,
  VoidCallback onPaint,
) => thumbnail
    ? _CountingThumb(list: list, onPaint: onPaint)
    : PdfCanvasView(
        lists: [list],
        viewport: VirtualViewport(),
        scale: 1,
        config: const OfficeSurfaceConfig(),
        onDraw: (canvas, size, page) => onPaint(),
      );

class _CountingThumb extends PdfPageThumb {
  const _CountingThumb({required super.list, required this.onPaint});
  final VoidCallback onPaint;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _CountingRenderThumb(list, onPaint);
}

class _CountingRenderThumb extends RenderPdfPageThumb {
  _CountingRenderThumb(PdfDisplayList list, this.onPaint)
    : super(list: list, selected: false, annots: const []);
  final VoidCallback onPaint;

  @override
  void paint(PaintingContext context, Offset offset) {
    onPaint();
    super.paint(context, offset);
  }
}

Uint8List _bytes(int marker) => Uint8List(32)
  ..[8] = marker & 0xff
  ..[9] = marker >> 8;

bool _ready(Uint8List bytes) =>
    PdfFontFaces.readyFor([bytes], (value) => value as Uint8List);

Future<void> _flush() => Future<void>.delayed(Duration.zero);

Future<void> _ensure(Uint8List bytes) {
  final completion = Completer<void>();
  PdfFontFaces.ensure(bytes, completion.complete);
  return completion.future.timeout(const Duration(seconds: 10));
}

SfntFont _font(String name) {
  final local = File('fonts/$name.ttf');
  final font = local.existsSync()
      ? local
      : File('packages/quds_office_editor/fonts/$name.ttf');
  return SfntFont.parse(font.readAsBytesSync());
}

int _oldKey(Uint8List bytes) => Object.hash(
  bytes.length,
  bytes[0],
  bytes[bytes.length >> 2],
  bytes[bytes.length >> 1],
  bytes[bytes.length - 1],
);

TextPainter _painter(String family) => TextPainter(
  text: TextSpan(
    text: 'A',
    style: TextStyle(
      fontFamily: family,
      fontSize: 32,
      color: const Color(0xff000000),
      height: 1,
    ),
  ),
  textDirection: TextDirection.ltr,
  maxLines: 1,
)..layout();

Future<Uint8List> _pixels(TextPainter painter) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(const Color(0xffffffff), BlendMode.src);
  painter.paint(canvas, const Offset(8, 8));
  final picture = recorder.endRecording();
  final image = await picture.toImage(64, 64);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return Uint8List.fromList(bytes!.buffer.asUint8List());
  } finally {
    image.dispose();
    picture.dispose();
  }
}

PdfDisplayList _displayList(Uint8List bytes) => PdfDisplayList(
  page: const PdfPageInfo(
    index: 0,
    mediaBox: PdfBox(llx: 0, lly: 0, urx: 160, ury: 200),
    cropBox: PdfBox(llx: 0, lly: 0, urx: 160, ury: 200),
  ),
  ops: [
    for (var i = 0; i < 20; i++)
      PdfDrawText(
        x: 10 + (i % 10) * 12,
        y: 20 + (i ~/ 10) * 20,
        size: 12,
        color: 0xff000000,
        text: 'A',
        fontBytes: bytes,
      ),
  ],
);
