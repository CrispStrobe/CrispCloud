@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:pro_image_editor/core/models/multi_threading/thread_request_model.dart';
import 'package:pro_image_editor/shared/services/content_recorder/services/image_converter_service.dart';
import 'package:pro_image_editor/shared/services/content_recorder/services/web_worker/web_worker_manager.dart';
import 'package:pro_image_editor/shared/services/content_recorder/utils/web_worker_utils.dart' as worker_interop;
import 'package:web/web.dart' as web;

const _configs = ImageGenerationConfigs(
  outputFormat: OutputFormat.png,
  captureImageByteFormat: ui.ImageByteFormat.rawStraightRgba,
  enableIsolateGeneration: true,
  enableBackgroundGeneration: false,
  processorConfigs: ProcessorConfigs(processorMode: ProcessorMode.minimum),
);

class _InspectableManager extends WebWorkerManager {
  _InspectableManager(String url) : super(_configs, workerScriptUrl: url);

  int get pendingTasks => tasks.length;
  int dispatches = 0;

  @override
  Future<Uint8List?> send(ThreadRequest data) {
    dispatches++;
    return super.send(data);
  }
}

Future<ui.Image> _sourcePixels() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    const ui.Rect.fromLTWH(0, 1, 2, 1),
    ui.Paint()..color = const ui.Color(0xffff0000),
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(2, 2);
  } finally {
    picture.dispose();
  }
}

Future<void> _expectValidPng(Uint8List? bytes) async {
  expect(bytes, isNotNull);
  final encoded = bytes!;
  // Decoders often tolerate trailing bytes; the original-file writer correctly
  // requires the encoded image itself, not an encoder's entire capacity buffer.
  expect(encoded.sublist(encoded.length - 12), orderedEquals([
    0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
  ]), reason: 'The PNG must end exactly after its IEND chunk.');
  final codec = await ui.instantiateImageCodec(encoded);
  try {
    final decoded = (await codec.getNextFrame()).image;
    try {
      expect((decoded.width, decoded.height), (2, 2));
      final rgba = (await decoded.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      expect(rgba.getUint8(3), 0);
      expect(rgba.getUint8(11), 255);
    } finally {
      decoded.dispose();
    }
  } finally {
    codec.dispose();
  }
}

Future<void> _exerciseFailure(String scriptUrl) async {
  final pixels = await _sourcePixels();
  final manager = _InspectableManager(scriptUrl);
  final converter = ImageConverterService(configs: _configs, threadManager: manager);
  try {
    // The timeout belongs to this regression test. Production reacts directly
    // to browser error events and imposes no arbitrary encoding time limit.
    await _expectValidPng(await converter.convert(
      image: pixels,
      id: 'first',
    ).timeout(const Duration(seconds: 10)));
    expect(manager.pendingTasks, 0);
    expect(manager.threads.single.activeTasks, 0);
    expect(manager.isSupported, isFalse);

    // A failed worker stays unavailable; a later save takes the existing
    // fallback path instead of waiting on the same broken worker again.
    await _expectValidPng(await converter.convert(
      image: pixels,
      id: 'retry',
    ).timeout(const Duration(seconds: 10)));
    expect(manager.pendingTasks, 0);
    expect(manager.threads, hasLength(1));
  } finally {
    manager.destroy();
    pixels.dispose();
  }
}

void main() {
  test('worker byte transfer preserves a subview offset and length', () {
    final backing = Uint8List.fromList([99, 1, 2, 3, 88, 77]);
    final view = Uint8List.sublistView(backing, 1, 4);
    final transferred = worker_interop.jsify(view) as JSArrayBuffer;
    expect(transferred.toDart.asUint8List(), orderedEquals([1, 2, 3]));
  });

  test('worker byte transfer omits unused encoder buffer capacity', () {
    final backing = Uint8List(8192)..setRange(0, 3, [1, 2, 3]);
    final view = Uint8List.sublistView(backing, 0, 3);
    final transferred = worker_interop.jsify(view) as JSArrayBuffer;
    expect(transferred.toDart.asUint8List(), orderedEquals([1, 2, 3]));
  });


  testWidgets('bundled production worker encodes PNG twice and JPEG without fallback or task leaks', (tester) async {
    await tester.runAsync(() async {
      // Flutter's test server exposes package files at this URL. It serves the
      // exact production JavaScript, without requiring a built asset tree.
      final pixels = await _sourcePixels();
      final manager = _InspectableManager('/packages/pro_image_editor/web/web_worker.dart.js');
      final converter = ImageConverterService(configs: _configs, threadManager: manager);
      try {
        for (final id in ['first', 'second']) {
          await _expectValidPng(await converter.convert(
            image: pixels,
            id: id,
          ).timeout(const Duration(seconds: 10)));
          expect(manager.isSupported, isTrue);
          expect(manager.pendingTasks, 0);
          expect(manager.threads.single.activeTasks, 0);
        }
        final jpeg = (await converter.convert(
          image: pixels,
          id: 'jpeg',
          format: OutputFormat.jpg,
        ).timeout(const Duration(seconds: 10)))!;
        expect(jpeg.take(2), orderedEquals([0xff, 0xd8]));
        expect(jpeg.sublist(jpeg.length - 2), orderedEquals([0xff, 0xd9]),
          reason: 'The JPEG must end at its EOI marker.');
        final codec = await ui.instantiateImageCodec(jpeg);
        try {
          final decoded = (await codec.getNextFrame()).image;
          expect((decoded.width, decoded.height), (2, 2));
          decoded.dispose();
        } finally {
          codec.dispose();
        }
        expect(manager.dispatches, 3);
        expect(manager.isSupported, isTrue);
        expect(manager.pendingTasks, 0);
        expect(manager.threads.single.activeTasks, 0);
      } finally {
        manager.destroy();
        pixels.dispose();
      }
    });
  });


  for (final scenario in <({String name, String script})>[
    (
      name: 'worker execution error completes pending capture and retries through fallback',
      script: 'self.onmessage = function () { throw new Error("intentional worker failure"); };',
    ),
    (
      name: 'malformed worker response completes pending capture through fallback',
      script: 'self.onmessage = function () { self.postMessage({unexpected: true}); };',
    ),
  ]) {
    testWidgets(scenario.name, (tester) async {
      await tester.runAsync(() async {
        final url = web.URL.createObjectURL(web.Blob(
          <JSAny>[scenario.script.toJS].toJS,
          web.BlobPropertyBag(type: 'application/javascript'),
        ));
        try {
          await _exerciseFailure(url);
        } finally {
          web.URL.revokeObjectURL(url);
        }
      });
    });
  }

  testWidgets('missing worker asset falls back instead of leaving Save pending', (tester) async {
    await tester.runAsync(() async {
      // Same-origin 404 from the test server; no external network dependency.
      await _exerciseFailure(Uri.base.resolve('missing-image-worker-regression.js').toString());
    });
  });
}
