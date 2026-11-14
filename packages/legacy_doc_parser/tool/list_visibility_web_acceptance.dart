// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:xml/xml.dart';

import '../test/support/list_visibility_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

void verifyListVisibilityCase(String name) {
  void check(bool condition, String message) {
    if (!condition) throw StateError('$name: $message');
  }

  final source = listVisibilityFixture(name), before = source.toList();
  final document = parseLegacyWordDocument(source);
  final expected = listVisibilityExpectedLabels(name);
  final bodies = listVisibilityExpectedBodies(name);
  final paragraphs = document.blocks.cast<LegacyWordParagraph>();
  final spansBefore = [for (final p in paragraphs) (p.startCp, p.endCp)];
  check(paragraphs.length == expected.length, 'source paragraph count');
  final html = XmlDocument.parse(document.safeHtml.replaceAll('<br>', '<br/>'));
  final htmlParagraphs = html.findAllElements('p').toList();
  check(htmlParagraphs.length == expected.length, 'HTML paragraph count');
  for (var i = 0; i < expected.length; i++) {
    check(
      htmlParagraphs[i].getAttribute('data-word-numbering') != 'unsupported',
      'intentional label suppression is not unsupported numbering',
    );
    final labels = htmlParagraphs[i]
        .findAllElements('span')
        .where((span) => span.getAttribute('data-word-list-label') == 'true');
    check(
      labels.map((label) => label.innerText).join() == expected[i],
      'HTML exact paragraph $i label (expected ${expected[i]})',
    );
    if (expected[i].isNotEmpty && bodies[i].isEmpty) {
      check(
        htmlParagraphs[i].findAllElements('br').isEmpty,
        'marker-only paragraph $i has no extra placeholder break',
      );
    }
  }
  for (final mode in LegacyWordFieldMode.values) {
    final result = convertLegacyWordDocument(document, fieldMode: mode);
    final archive = ZipDecoder().decodeBytes(result.bytes);
    XmlDocument part(String path) =>
        XmlDocument.parse(utf8.decode(archive.findFile(path)!.content));
    final native = part('word/numbering.xml');
    final xml = part('word/document.xml');
    final output = xml.findAllElements('p', namespace: _w).toList();
    check(output.length == expected.length, '${mode.name} paragraph count');
    final starts = <String, int>{};
    for (final num in native.findAllElements('num', namespace: _w)) {
      starts[num.getAttribute('numId', namespace: _w)!] = int.parse(
        num.findAllElements(
              'startOverride',
              namespace: _w,
            ).firstOrNull?.getAttribute('val', namespace: _w) ??
            '7',
      );
    }
    final counters = <String, int>{};
    final literal = name.startsWith('literal-');
    for (var i = 0; i < expected.length; i++) {
      final p = output[i];
      final numId = p
          .findAllElements('numId', namespace: _w)
          .single
          .getAttribute('val', namespace: _w)!;
      String label = '';
      if (numId != '0') {
        final value = counters[numId] ?? starts[numId]!;
        counters[numId] = value + 1;
        if (!name.endsWith('hidden-marker')) label = '$value.';
      }
      final visible = StringBuffer();
      for (final run in p.findAllElements('r', namespace: _w)) {
        final hidden = run
            .getElement('rPr', namespace: _w)
            ?.getElement('vanish', namespace: _w);
        if (hidden != null &&
            ![
              '0',
              'false',
              'off',
            ].contains(hidden.getAttribute('val', namespace: _w))) {
          continue;
        }
        for (final text in run.findAllElements('t', namespace: _w)) {
          visible.write(text.innerText);
        }
      }
      final expectedText = '${literal ? expected[i] : ''}${bodies[i]}';
      check(
        visible.toString() == expectedText,
        '${mode.name} exact paragraph $i visible runs',
      );
      if (!literal) {
        check(
          label == expected[i],
          '${mode.name} native counter at paragraph $i',
        );
      } else {
        check(
          numId == '0',
          '${mode.name} materialized/native reset at paragraph $i',
        );
      }
    }
    check(
      (result.preservedCounts['suppressedNumberingLabels'] ?? 0) ==
          listVisibilitySuppressedLabels(name),
      '${mode.name} explicit suppressed-label count',
    );
  }
  check(source.length == before.length, 'source byte length');
  for (var i = 0; i < source.length; i++) {
    check(source[i] == before[i], 'source byte $i unchanged');
  }
  for (var i = 0; i < spansBefore.length; i++) {
    check(
      (paragraphs[i].startCp, paragraphs[i].endCp) == spansBefore[i],
      'source CPs unchanged',
    );
  }
}

Map<String, Object> verifyListVisibilityWebAcceptance() {
  for (final name in listVisibilityCases) {
    verifyListVisibilityCase(name);
  }
  return {
    'cases': listVisibilityCases.length,
    'fieldModes': LegacyWordFieldMode.values.length,
    'emptyParagraphLabels': true,
    'fieldBoundaryVisibility': true,
    'hiddenCountersAdvance': true,
    'sourceUnchanged': true,
  };
}

void main() => print(jsonEncode(verifyListVisibilityWebAcceptance()));
