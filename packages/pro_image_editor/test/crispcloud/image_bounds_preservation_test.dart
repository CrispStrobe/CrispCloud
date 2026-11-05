import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pro_image_editor/core/models/multi_threading/thread_request_model.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:pro_image_editor/shared/services/content_recorder/services/image_converter_service.dart';
import 'package:pro_image_editor/shared/services/content_recorder/services/thread_fallback_manager.dart';
import 'package:pro_image_editor/shared/services/content_recorder/services/thread_manager.dart';

Future<ui.Image> _transparentBorderImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  // A rotated 24x16 image with one transparent row must remain 16x24.
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 1, 16, 23),
    ui.Paint()..color = const ui.Color(0xffff0000),
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(16, 24);
  } finally {
    picture.dispose();
  }
}

class _RecordingThreadManager extends ThreadManager {
  _RecordingThreadManager()
    : super(const ImageGenerationConfigs(enableIsolateGeneration: false));

  final requests = <ThreadRequest>[];

  @override
  void initialize() {}

  @override
  Future<Uint8List?> send(ThreadRequest data) async {
    requests.add(data);
    return Uint8List.fromList([1]);
  }
}

void main() {
  for (final scenario in <({String name, bool imageBounds, bool? override, int height})>[
    (name: 'image bounds preserve transparent source pixels', imageBounds: true, override: null, height: 24),
    (name: 'drawing-only bounds still trim surrounding transparency', imageBounds: false, override: null, height: 23),
    (name: 'explicit capture preservation overrides drawing-only trim', imageBounds: false, override: false, height: 24),
    (name: 'explicit layer trim remains supported', imageBounds: true, override: true, height: 23),
  ]) {
    testWidgets(scenario.name, (tester) async {
      await tester.runAsync(() async {
        final configs = ImageGenerationConfigs(
          outputFormat: OutputFormat.png,
          captureImageByteFormat: ui.ImageByteFormat.rawStraightRgba,
          cropToImageBounds: scenario.imageBounds,
          cropToDrawingBounds: true,
          enableIsolateGeneration: false,
        );
        final manager = ThreadFallbackManager(configs);
        final pixels = await _transparentBorderImage();
        try {
          final output = await ImageConverterService(configs: configs, threadManager: manager).convert(
            image: pixels,
            id: 'transparent-border',
            cropToDrawingBounds: scenario.override,
          );
          final codec = await ui.instantiateImageCodec(output!);
          try {
            final decoded = (await codec.getNextFrame()).image;
            try {
              expect((decoded.width, decoded.height), (16, scenario.height));
              final rgba = (await decoded.toByteData(format: ui.ImageByteFormat.rawRgba))!;
              expect(rgba.getUint8(3), scenario.height == 24 ? 0 : 255);
              expect(rgba.getUint8((decoded.height - 1) * decoded.width * 4 + 3), 255);
            } finally {
              decoded.dispose();
            }
          } finally {
            codec.dispose();
          }
        } finally {
          pixels.dispose();
          manager.destroy();
        }
      });
    });
  }

  testWidgets('worker request preserves image bounds before entering bundled code', (tester) async {
    await tester.runAsync(() async {
      final manager = _RecordingThreadManager();
      final pixels = await _transparentBorderImage();
      try {
        await ImageConverterService(
          configs: const ImageGenerationConfigs(
            outputFormat: OutputFormat.png,
            captureImageByteFormat: ui.ImageByteFormat.rawStraightRgba,
            enableIsolateGeneration: true,
          ),
          threadManager: manager,
        ).convert(image: pixels, id: 'worker-border');
        expect(manager.requests, hasLength(1));
        expect(manager.requests.single.generateOnlyImageBounds, isFalse);
        expect((manager.requests.single.image.width, manager.requests.single.image.height), (16, 24));
      } finally {
        pixels.dispose();
        manager.destroy();
      }
    });
  });
}
