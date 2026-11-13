import 'dart:convert';

import 'package:crisp_cloud/widgets/office_html_widget_factory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../support/office_svg_paint.dart';

void main() {
  testWidgets(
    'Office CSS escapes resolve to named fonts without changing other styles',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HtmlWidget(
              r'''<p><span style="font-family:'\41 \72 \69 \61 \6c ';font-size:17pt;font-weight:bold;font-style:italic;color:#123456">ARIAL_PROBE</span></p>'''
              r'''<p><span style="font-family:'\43 \61 \6c \69 \62 \72 \69 '">CALIBRI_PROBE</span></p>'''
              r'''<p><span style="font-family:'X\27 \3b color\3a red';color:#123456">LITERAL_PROBE</span></p>''',
              factoryBuilder: OfficeHtmlWidgetFactory.new,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final styles = <String, TextStyle>{};
      void walk(InlineSpan span, TextStyle inherited) {
        if (span is! TextSpan) return;
        final effective = inherited.merge(span.style);
        if (span.text?.endsWith('_PROBE') == true) {
          styles[span.text!] = effective;
        }
        for (final child in span.children ?? <InlineSpan>[]) {
          walk(child, effective);
        }
      }

      for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
        walk(rich.text, const TextStyle());
      }
      final arial = styles['ARIAL_PROBE']!;
      expect(arial.fontFamily, 'Liberation Sans');
      expect(arial.fontWeight, FontWeight.bold);
      expect(arial.fontStyle, FontStyle.italic);
      expect(arial.fontSize, closeTo(22.6667, .01));
      expect(arial.color, const Color(0xff123456));
      expect(arial.fontFamilyFallback, contains('Noto Naskh Arabic'));
      expect(styles['CALIBRI_PROBE']!.fontFamily, 'Carlito');
      expect(styles['LITERAL_PROBE']!.fontFamily, "X';color:red");
      expect(styles['LITERAL_PROBE']!.color, const Color(0xff123456));
      expect(tester.takeException(), isNull);
    },
  );

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
