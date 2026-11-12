import 'dart:convert';

import 'package:crisp_cloud/widgets/office_html_widget_factory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../support/office_svg_paint.dart';

void main() {
  testWidgets('Office SVG data images paint with dimensions and semantics', (
    tester,
  ) async {
    const svg =
        '<svg xmlns="http://www.w3.org/2000/svg" '
        'viewBox="0 0 200 100"><rect x="10" y="10" width="180" '
        'height="80" fill="#99ccdd"/></svg>';
    final uri = 'data:image/svg+xml;base64,${base64Encode(utf8.encode(svg))}';
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          home: Scaffold(
            body: HtmlWidget(
              '<p><img src="$uri" width="100" height="50" '
              'alt="Stored Office vector"/></p>',
              factoryBuilder: OfficeHtmlWidgetFactory.new,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectPaintedOfficeSvg(tester, boundary);
    final image = tester.widget<SvgPicture>(find.byType(SvgPicture));
    expect(image.semanticsLabel, 'Stored Office vector');
    expect(tester.getSize(find.byType(SvgPicture)), const Size(100, 50));
  });

  testWidgets('Office images do not fetch URLs or decode malformed SVG URIs', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HtmlWidget(
            '<img src="https://example.invalid/remote.png"/>'
            '<img src="file:///unrelated/image.png"/>'
            '<img src="asset:unrelated.svg"/>'
            '<img src="data:image/svg+xml;base64,NOT-BASE64!"/>'
            '<img src="data:image/svg+xml,%3Csvg/%3E"/>',
            factoryBuilder: OfficeHtmlWidgetFactory.new,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SvgPicture), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
