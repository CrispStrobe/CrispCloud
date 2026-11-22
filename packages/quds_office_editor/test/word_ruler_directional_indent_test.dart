import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _margins = WmlPageMargins(left: 72, right: 36);
const _indent = WmlIndent(left: 12, right: 45, firstLine: 9);
const _pageWidth = 612.0;
const _contentLeft = 100.0;
const _contentRight = 460.0;

({double first, double body, double trailing}) _markers(
  WmlIndent indent, {
  required bool rtl,
}) => (
  first: WordRuler.firstLinePageX(
    margins: _margins,
    indent: indent,
    pageWidth: _pageWidth,
    rtl: rtl,
    contentLeft: _contentLeft,
    contentRight: _contentRight,
  ),
  body: WordRuler.hangingPageX(
    margins: _margins,
    indent: indent,
    pageWidth: _pageWidth,
    rtl: rtl,
    contentLeft: _contentLeft,
    contentRight: _contentRight,
  ),
  trailing: WordRuler.rightIndentPageX(
    margins: _margins,
    indent: indent,
    pageWidth: _pageWidth,
    rtl: rtl,
    contentLeft: _contentLeft,
    contentRight: _contentRight,
  ),
);

WmlIndent _drag(
  WmlIndent indent,
  RulerHitKind kind,
  double pageX, {
  bool rtl = true,
}) => WordRuler.applyIndentDrag(
  indent: indent,
  kind: kind,
  pageX: pageX,
  margins: _margins,
  pageWidth: _pageWidth,
  rtl: rtl,
  contentLeft: _contentLeft,
  contentRight: _contentRight,
);

void _expectIndent(
  WmlIndent indent, {
  required double left,
  required double right,
  double firstLine = 0,
  double hanging = 0,
}) {
  expect(indent.left, left);
  expect(indent.right, right);
  expect(indent.firstLine, firstLine);
  expect(indent.hanging, hanging);
}

void main() {
  test('asymmetric physical margins locate LTR and RTL marker families', () {
    expect(_markers(_indent, rtl: false), (
      first: 121.0,
      body: 112.0,
      trailing: 415.0,
    ));
    expect(_markers(_indent, rtl: true), (
      first: 406.0,
      body: 415.0,
      trailing: 112.0,
    ));
    const hanging = WmlIndent(left: 12, right: 45, hanging: 18);
    expect(_markers(hanging, rtl: true), (
      first: 433.0,
      body: 415.0,
      trailing: 112.0,
    ));
  });

  test('page-margin fallback also uses physical sides in RTL', () {
    expect(
      WordRuler.hangingPageX(
        margins: _margins,
        indent: _indent,
        pageWidth: _pageWidth,
        rtl: true,
      ),
      531,
    );
    expect(
      WordRuler.rightIndentPageX(
        margins: _margins,
        indent: _indent,
        pageWidth: _pageWidth,
        rtl: true,
      ),
      84,
    );
  });

  for (final rtl in [false, true]) {
    test(
      '$rtl hit targets and drag guides match physical marker positions',
      () {
        final expected = rtl
            ? <(RulerHitKind, double, double)>[
                (RulerHitKind.firstLine, 406, 5),
                (RulerHitKind.hanging, 415, 10),
                (RulerHitKind.leftIndent, 415, 17),
                (RulerHitKind.rightIndent, 112, 11),
              ]
            : <(RulerHitKind, double, double)>[
                (RulerHitKind.firstLine, 121, 5),
                (RulerHitKind.hanging, 112, 10),
                (RulerHitKind.leftIndent, 112, 17),
                (RulerHitKind.rightIndent, 415, 11),
              ];
        for (final (kind, pageX, y) in expected) {
          final localX = 24 + pageX * 2;
          final hit = WordRuler.hit(
            local: Offset(localX, y),
            view: const Size(1300, 900),
            pageLeft: 24,
            pageTop: 30,
            scale: 2,
            pageWidth: _pageWidth,
            pageHeight: 792,
            margins: _margins,
            indent: _indent,
            tabs: const [],
            rtl: rtl,
            contentLeft: _contentLeft,
            contentRight: _contentRight,
          );
          expect(hit?.kind, kind);
          expect(
            WordRuler.guideLocal(
              active: hit,
              pageLeft: 24,
              pageTop: 30,
              scale: 2,
              pageWidth: _pageWidth,
              pageHeight: 792,
              margins: _margins,
              indent: _indent,
              tabs: const [],
              rtl: rtl,
              contentLeft: _contentLeft,
              contentRight: _contentRight,
            ),
            (localX, null),
          );
        }
      },
    );
  }

  test('RTL leading drag changes physical right and preserves left', () {
    final result = _drag(_indent, RulerHitKind.leftIndent, 400);
    _expectIndent(result, left: 12, right: 60, firstLine: 9);
    expect(_markers(result, rtl: true).body, 400);
    expect(_markers(result, rtl: true).trailing, 112);
  });

  test('RTL trailing drag changes physical left and preserves right', () {
    final result = _drag(_indent, RulerHitKind.rightIndent, 124);
    _expectIndent(result, left: 24, right: 45, firstLine: 9);
    expect(_markers(result, rtl: true).trailing, 124);
    expect(_markers(result, rtl: true).body, 415);
  });

  test('LTR leading and trailing drags retain their physical ownership', () {
    _expectIndent(
      _drag(_indent, RulerHitKind.leftIndent, 130, rtl: false),
      left: 30,
      right: 45,
      firstLine: 9,
    );
    _expectIndent(
      _drag(_indent, RulerHitKind.rightIndent, 400, rtl: false),
      left: 12,
      right: 60,
      firstLine: 9,
    );
  });

  test('RTL first-line drag switches between inward and hanging offsets', () {
    final inward = _drag(_indent, RulerHitKind.firstLine, 400);
    _expectIndent(inward, left: 12, right: 45, firstLine: 15);
    expect(_markers(inward, rtl: true).first, 400);
    final outward = _drag(inward, RulerHitKind.firstLine, 433);
    _expectIndent(outward, left: 12, right: 45, hanging: 18);
    expect(_markers(outward, rtl: true).first, 433);
  });

  test('RTL hanging drag keeps first-line position while body edge moves', () {
    final inward = _drag(_indent, RulerHitKind.hanging, 400);
    _expectIndent(inward, left: 12, right: 60, hanging: 6);
    expect(_markers(inward, rtl: true), (
      first: 406.0,
      body: 400.0,
      trailing: 112.0,
    ));
    final outward = _drag(inward, RulerHitKind.hanging, 430);
    _expectIndent(outward, left: 12, right: 30, firstLine: 24);
    expect(_markers(outward, rtl: true), (
      first: 406.0,
      body: 430.0,
      trailing: 112.0,
    ));
  });

  test('ruler-edited native RTL indents survive repeated DOCX reopening', () {
    final package = OpcPackage.openBytes(
      (DocxDocumentBuilder()..paragraph('RTL ruler')).build(),
    );
    package
        .getPart('/word/document.xml')!
        .writeText(
          '<w:document xmlns:w="${OfficeNamespaces.w}"><w:body><w:p>'
          '<w:pPr><w:ind w:left="900" w:right="240" w:firstLine="180"/>'
          '<w:jc w:val="left"/><w:bidi/></w:pPr>'
          '<w:r><w:t>RTL ruler</w:t></w:r></w:p><w:sectPr/>'
          '</w:body></w:document>',
        );
    var document = WordDeserializer().read(package);
    final properties = document.paragraphs.single.properties;
    _expectIndent(properties.indent, left: 12, right: 45, firstLine: 9);
    properties.indent = _drag(
      _drag(properties.indent, RulerHitKind.hanging, 400),
      RulerHitKind.rightIndent,
      124,
    );
    for (var cycle = 0; cycle < 3; cycle++) {
      document = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );
      final paragraph = document.paragraphs.single;
      expect(paragraph.properties.rightToLeft, isTrue);
      expect(paragraph.properties.justification, WmlJustification.right);
      _expectIndent(
        paragraph.properties.indent,
        left: 24,
        right: 60,
        hanging: 6,
      );
      expect(_markers(paragraph.properties.indent, rtl: true), (
        first: 406.0,
        body: 400.0,
        trailing: 124.0,
      ));
    }
  });
}
