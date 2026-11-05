@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:pro_image_editor/shared/services/content_recorder/services/image_converter_service.dart';
import 'package:pro_image_editor/shared/services/content_recorder/services/web_worker/web_worker_manager.dart';
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
  final codec = await ui.instantiateImageCodec(bytes!);
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
