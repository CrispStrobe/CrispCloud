import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

void main() {
  testWidgets('records font family decoded by the production HTML renderer', (tester) async {
    final cases = <String, String>{
      'plain Arial': "<span style=\"font-family:'Arial';font-size:17pt;font-weight:bold\">FONT_PROBE_PLAIN</span>",
      'hex escaped Arial as emitted by legacy-doc-parser': r'''<span style="font-family:'\41 \72 \69 \61 \6c ';font-size:17pt;font-weight:bold">FONT_PROBE_ESCAPED</span>''',
    };
    for (final entry in cases.entries) {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: HtmlWidget(entry.value))));
      await tester.pumpAndSettle();
      final matches = <Map<String, Object?>>[];
      void walk(InlineSpan span, TextStyle inherited) {
        if (span is! TextSpan) return;
        final effective = inherited.merge(span.style);
        if (span.text?.contains('FONT_PROBE_') == true) {
          matches.add({'text':span.text,'family':effective.fontFamily,'fallbacks':effective.fontFamilyFallback,'weight':effective.fontWeight?.value,'size':effective.fontSize});
        }
        for (final child in span.children ?? <InlineSpan>[]) {
          walk(child, effective);
        }
      }
      for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
        walk(rich.text, const TextStyle());
      }
      print(jsonEncode({'case':entry.key,'matches':matches}));
      expect(matches.length, 1);
      expect(matches.single['weight'], 700);
      expect(matches.single['size'], closeTo(22.6666666667, .01));
      expect(matches.single['family'], entry.key == 'plain Arial' ? 'Arial' : r'\41 \72 \69 \61 \6c ');
    }
  });
}
