import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/widgets/mesh_preview.dart';

import '../mesh_preview_test.dart' show binaryStl, threeMf;

Future<void> ready(WidgetTester tester) async {
  for (
    var i = 0;
    i < 100 && find.byKey(const ValueKey('mesh-surface')).evaluate().isEmpty;
    i++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
  }
  expect(find.byKey(const ValueKey('mesh-surface')), findsOneWidget);
}

void main() {
  testWidgets(
    'STL renders pixels and supports rotation, zoom, wireframe and fit',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MeshPreview(bytes: binaryStl(), filename: 'x.stl'),
          ),
        ),
      );
      await ready(tester);
      final surface = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('mesh-surface')),
      );
      await tester.runAsync(() async {
        final image = await surface.toImage();
        final pixels = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        expect(pixels, isNotNull);
        var painted = 0;
        for (var i = 3; i < pixels!.lengthInBytes; i += 4) {
          if (pixels.getUint8(i) > 0) painted++;
        }
        expect(painted, greaterThan(100));
        image.dispose();
      });
      for (final label in [
        'Zoom in',
        'Rotate right',
        'Wireframe',
        'Fit model',
      ]) {
        await tester.tap(find.byTooltip(label));
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
      await tester.drag(
        find.byKey(const ValueKey('mesh-surface')),
        const Offset(100, 40),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('3MF preview remains usable on narrow, enlarged-text screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 480),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: MeshPreview(bytes: threeMf(), filename: 'x.3mf'),
          ),
        ),
      ),
    );
    await ready(tester);
    expect(tester.takeException(), isNull);
  });
}
