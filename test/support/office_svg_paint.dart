import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

/// Check actual rasterized pixels, not only the presence of an SVG widget.
/// Both the authored metafile controls and the factory control use #99CCDD.
Future<void> expectPaintedOfficeSvg(
  WidgetTester tester,
  GlobalKey boundaryKey,
) async {
  expect(find.byType(SvgPicture), findsOneWidget);
  var painted = 0;
  for (var attempt = 0; attempt < 30 && painted < 100; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    painted =
        await tester.runAsync(() async {
          final boundary =
              boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          try {
            final data = await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            final pixels = data!.buffer.asUint8List();
            var matching = 0;
            for (var index = 0; index < pixels.length; index += 4) {
              if (pixels[index] == 0x99 &&
                  pixels[index + 1] == 0xcc &&
                  pixels[index + 2] == 0xdd &&
                  pixels[index + 3] == 0xff) {
                matching++;
              }
            }
            return matching;
          } finally {
            image.dispose();
          }
        }) ??
        0;
  }
  expect(painted, greaterThanOrEqualTo(100), reason: 'SVG shapes must paint.');
  expect(tester.takeException(), isNull);
}
