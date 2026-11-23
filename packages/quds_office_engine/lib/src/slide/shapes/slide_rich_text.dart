import '../../xml/namespaces.dart';
import '../../xml/xml_node.dart';
import '../../xml/xml_reader.dart';
import '../model/pml_presentation.dart';

final _containsSymbol = RegExp(r'[\uF000-\uF0FF]');
final _symbolSegments = RegExp(r'[\uF000-\uF0FF]+|[^\uF000-\uF0FF]+');

/// Parses a captured `p:txBody` snapshot into paragraphs and styled runs.
List<PmlTextParagraph> parsePmlRichText(
  String xml,
  Map<String, String> colors,
) {
  final XmlElement root = _readRoot(xml);
  XmlElement? drawing(XmlElement? parent, String tag) =>
      parent?.firstChild(tag, namespaceUri: OfficeNamespaces.a);
  final list = drawing(root, 'lstStyle');
  final List<PmlTextParagraph> paragraphs = <PmlTextParagraph>[];
  for (final XmlElement paragraph in root.childrenNamed(
    'p',
    namespaceUri: OfficeNamespaces.a,
  )) {
    final XmlElement? pPr = paragraph.firstChild(
      'pPr',
      namespaceUri: OfficeNamespaces.a,
    );
    final level = (int.tryParse(pPr?.getAttribute('lvl') ?? '') ?? 0).clamp(
      0,
      8,
    );
    final levelProps = drawing(list, 'lvl${level + 1}pPr');
    final fallbackProps = drawing(levelProps, 'defRPr');
    final paraRun = drawing(pPr, 'defRPr');
    final end = drawing(paragraph, 'endParaRPr');
    String? runAttr(XmlElement? run, String name) =>
        run?.getAttribute(name) ??
        paraRun?.getAttribute(name) ??
        fallbackProps?.getAttribute(name);
    String face(XmlElement? run) =>
        drawing(run, 'latin')?.getAttribute('typeface') ?? '';
    String ink(XmlElement? run) {
      for (final props in [run, paraRun, fallbackProps]) {
        final color = _runColor(props, colors);
        if (color.isNotEmpty) return color;
      }
      return '';
    }

    String? paragraphAttr(String name) =>
        pPr?.getAttribute(name) ?? levelProps?.getAttribute(name);
    XmlElement? paragraphElement(String name) =>
        drawing(pPr, name) ?? drawing(levelProps, name);
    XmlElement? choice(XmlElement? props, Set<String> names) => props
        ?.childElements
        .where(
          (e) =>
              e.namespaceUri == OfficeNamespaces.a &&
              names.contains(e.localName),
        )
        .firstOrNull;
    final bulletNames = {'buNone', 'buChar', 'buAutoNum', 'buBlip'};
    final bullet = choice(pPr, bulletNames) ?? choice(levelProps, bulletNames);
    final bulletFont =
        choice(pPr, {'buFont', 'buFontTx'}) ??
        choice(levelProps, {'buFont', 'buFontTx'});
    final bulletColor =
        choice(pPr, {'buClr', 'buClrTx'}) ??
        choice(levelProps, {'buClr', 'buClrTx'});
    final line = paragraphElement('lnSpc');
    final before = paragraphElement('spcBef');
    final after = paragraphElement('spcAft');
    final pointValue = double.tryParse(
      drawing(line, 'spcPts')?.getAttribute('val') ?? '',
    );
    final out = PmlTextParagraph(
      align: _align(paragraphAttr('algn')),
      level: level,
      marginLeftPt: _emuToPt(paragraphAttr('marL')),
      marginRightPt: _emuToPt(paragraphAttr('marR')),
      indentPt: _emuToPt(paragraphAttr('indent')),
      rightToLeft: paragraphAttr('rtl') == '1',
      defaultTabPt: _emuToPt(paragraphAttr('defTabSz')) == 0
          ? 72
          : _emuToPt(paragraphAttr('defTabSz')),
      lineSpacing: _spacingRatio(line, fallback: 1),
      lineSpacingPt:
          pointValue != null && pointValue.isFinite && pointValue >= 0
          ? pointValue / 100
          : null,
      spaceBeforePt: _spacing(before),
      spaceAfterPt: _spacing(after),
      spaceBeforeLineRatio: _spacingRatio(before),
      spaceAfterLineRatio: _spacingRatio(after),
      defaultFontSizePt: (int.tryParse(runAttr(end, 'sz') ?? '') ?? 0) / 100,
      defaultLetterSpacingPt: _letterSpacing(runAttr(null, 'spc')),
      defaultFontFamily: [
        face(end),
        face(paraRun),
        face(fallbackProps),
      ].firstWhere((name) => name.isNotEmpty, orElse: () => ''),
      defaultColor: ink(end),
      defaultBold: runAttr(end, 'b') == '1',
      defaultItalic: runAttr(end, 'i') == '1',
      bullet: bullet?.getAttribute('char'),
      bulletFont: bulletFont?.getAttribute('typeface'),
      bulletColor: bulletColor?.localName == 'buClr'
          ? _fillColor(bulletColor!, colors)
          : null,
      definedProperties: {
        if (paragraphAttr('algn') != null) PmlParagraphProperty.alignment,
        if (paragraphAttr('rtl') != null) PmlParagraphProperty.direction,
        if (paragraphAttr('marL') != null) PmlParagraphProperty.leftMargin,
        if (paragraphAttr('marR') != null) PmlParagraphProperty.rightMargin,
        if (paragraphAttr('indent') != null) PmlParagraphProperty.indent,
        if (line != null) PmlParagraphProperty.lineSpacing,
        if (before != null) PmlParagraphProperty.spaceBefore,
        if (after != null) PmlParagraphProperty.spaceAfter,
        if (bullet != null) PmlParagraphProperty.bullet,
        if (bulletFont != null) PmlParagraphProperty.bulletFont,
        if (bulletColor != null) PmlParagraphProperty.bulletColor,
      },
    );
    for (final XmlElement child in paragraph.childElements) {
      final isBreak = child.localName == 'br';
      if (child.localName == 'r' || child.localName == 'fld' || isBreak) {
        final XmlElement? rPr = child.firstChild(
          'rPr',
          namespaceUri: OfficeNamespaces.a,
        );
        final String text = isBreak
            ? '\n'
            : child
                  .childrenNamed('t', namespaceUri: OfficeNamespaces.a)
                  .map((XmlElement e) => e.text)
                  .join();
        if (text.isEmpty) continue;
        final run = PmlTextRun(
          text: text,
          fontSizePt: (int.tryParse(runAttr(rPr, 'sz') ?? '') ?? 0) / 100,
          // An omitted attribute can use fallback styling; an explicit
          // zero must continue to disable that style on this run.
          bold: (runAttr(rPr, 'b') ?? end?.getAttribute('b')) == '1',
          boldSpecified: (runAttr(rPr, 'b') ?? end?.getAttribute('b')) != null,
          italic: (runAttr(rPr, 'i') ?? end?.getAttribute('i')) == '1',
          underline: switch (rPr?.getAttribute('u')) {
            null || 'none' => false,
            _ => true,
          },
          strike: switch (rPr?.getAttribute('strike')) {
            null || 'noStrike' => false,
            _ => true,
          },
          baseline:
              (int.tryParse(rPr?.getAttribute('baseline') ?? '') ?? 0) / 100000,
          letterSpacingPt: _letterSpacing(rPr?.getAttribute('spc')),
          color: ink(rPr),
          fontFamily: [
            face(rPr),
            face(paraRun),
            face(fallbackProps),
          ].firstWhere((name) => name.isNotEmpty, orElse: () => ''),
        );
        final symbolFace = drawing(rPr, 'sym')?.getAttribute('typeface');
        if (symbolFace == null ||
            symbolFace.isEmpty ||
            !_containsSymbol.hasMatch(text)) {
          out.runs.add(run);
        } else {
          // The symbol face applies only to encoded symbol characters. A run
          // can also contain ordinary letters or spaces in its Latin face.
          for (final match in _symbolSegments.allMatches(text)) {
            final segment = match.group(0)!;
            out.runs.add(
              run.copy()
                ..text = segment
                ..fontFamily = _containsSymbol.hasMatch(segment)
                    ? symbolFace
                    : run.fontFamily,
            );
          }
        }
      }
    }
    if (end != null) {
      for (final PmlTextRun run in out.runs) {
        if (run.color.isEmpty) run.color = out.defaultColor;
      }
    }
    paragraphs.add(out);
  }
  return paragraphs;
}

/// Projects master text defaults through the same parser as slide text.
Map<int, PmlTextParagraph> parsePmlMasterTextStyle(
  XmlElement style,
  Map<String, String> colors,
) {
  XmlElement drawing(String name) => XmlElement(
    localName: name,
    prefix: 'a',
    namespaceUri: OfficeNamespaces.a,
  );
  final body =
      XmlElement(
          localName: 'txBody',
          prefix: 'p',
          namespaceUri: OfficeNamespaces.p,
        )
        ..setAttribute('a', OfficeNamespaces.a, prefix: 'xmlns')
        ..setAttribute('p', OfficeNamespaces.p, prefix: 'xmlns');
  for (var level = 0; level < 9; level++) {
    final props =
        style.firstChild(
          'lvl${level + 1}pPr',
          namespaceUri: OfficeNamespaces.a,
        ) ??
        style.firstChild('defPPr', namespaceUri: OfficeNamespaces.a);
    if (props == null) continue;
    final pPr = drawing('pPr')
      ..attributes.addAll(props.attributes.map((attribute) => attribute.copy()))
      ..setAttribute('lvl', '$level');
    for (final node in props.children) {
      pPr.addChild(node.copy());
    }
    body.addChild(
      drawing('p')
        ..addChild(pPr)
        ..addChild(drawing('r')..addChild(drawing('t')..addText('x'))),
    );
  }
  return {
    for (final paragraph in parsePmlRichText(
      XmlDocument(root: body).toXmlString(declaration: false),
      colors,
    ))
      paragraph.level: paragraph,
  };
}

PmlTextAlign _align(String? value) => switch (value) {
  'ctr' => PmlTextAlign.center,
  'r' => PmlTextAlign.right,
  'just' => PmlTextAlign.justify,
  _ => PmlTextAlign.left,
};

double _emuToPt(String? value) => (int.tryParse(value ?? '') ?? 0) / 12700;

double? _letterSpacing(String? value) {
  final hundredths = int.tryParse(value ?? '');
  if (hundredths == null || hundredths < -400000 || hundredths > 400000) {
    return null;
  }
  return hundredths / 100;
}

double _spacing(XmlElement? spacing) =>
    (int.tryParse(
          spacing
                  ?.firstChild('spcPts', namespaceUri: OfficeNamespaces.a)
                  ?.getAttribute('val') ??
              '',
        ) ??
        0) /
    100;

double _spacingRatio(XmlElement? spacing, {double fallback = 0}) {
  final value = spacing
      ?.firstChild('spcPct', namespaceUri: OfficeNamespaces.a)
      ?.getAttribute('val')
      ?.trim();
  if (value == null) return fallback;
  final hasUnit = value.endsWith('%');
  final amount = double.tryParse(
    hasUnit ? value.substring(0, value.length - 1) : value,
  );
  if (amount == null || !amount.isFinite || amount < 0) return fallback;
  return amount / (hasUnit ? 100 : 100000);
}

String _runColor(XmlElement? properties, Map<String, String> colors) {
  final fill = properties?.firstChild(
    'solidFill',
    namespaceUri: OfficeNamespaces.a,
  );
  return fill == null ? '' : _fillColor(fill, colors);
}

String _fillColor(XmlElement fill, Map<String, String> colors) {
  for (final XmlElement color in fill.childElements) {
    switch (color.localName) {
      case 'srgbClr':
        return _modifyColor(
          color.getAttribute('val')?.toUpperCase() ?? '',
          color,
        );
      case 'schemeClr':
        return _modifyColor(
          colors[color.getAttribute('val') ?? ''] ?? '',
          color,
        );
      case 'sysClr':
        return _modifyColor(
          (color.getAttribute('lastClr') ?? '').toUpperCase(),
          color,
        );
      case 'prstClr':
        return _modifyColor(switch (color.getAttribute('val')) {
          'white' => 'FFFFFF',
          'black' => '000000',
          'red' => 'FF0000',
          'green' => '008000',
          'blue' => '0000FF',
          'yellow' => 'FFFF00',
          'gray' => '808080',
          _ => '',
        }, color);
    }
  }
  return '';
}

String _modifyColor(String hex, XmlElement color) {
  if (hex.length != 6 || int.tryParse(hex, radix: 16) == null) return hex;
  double lumMod = 1;
  double lumOff = 0;
  for (final XmlElement child in color.childElements) {
    final double amount =
        (int.tryParse(child.getAttribute('val') ?? '') ?? 100000) / 100000;
    switch (child.localName) {
      case 'lumMod':
        lumMod = amount;
      case 'lumOff':
        lumOff = amount;
      case 'shade':
        hex = _mapChannels(hex, (int c) => c * amount);
      case 'tint':
        hex = _mapChannels(hex, (int c) => c + (255 - c) * (1 - amount));
    }
  }
  if (lumMod == 1 && lumOff == 0) return hex;
  return _applyLuminance(hex, lumMod, lumOff);
}

String _mapChannels(String hex, double Function(int channel) map) {
  final int rgb = int.parse(hex, radix: 16);
  final StringBuffer out = StringBuffer();
  for (final int shift in <int>[16, 8, 0]) {
    final int c = map((rgb >> shift) & 0xFF).round().clamp(0, 255);
    out.write(c.toRadixString(16).padLeft(2, '0'));
  }
  return out.toString().toUpperCase();
}

String _applyLuminance(String hex, double lumMod, double lumOff) {
  final int rgb = int.parse(hex, radix: 16);
  final double r = ((rgb >> 16) & 0xFF) / 255;
  final double g = ((rgb >> 8) & 0xFF) / 255;
  final double b = (rgb & 0xFF) / 255;
  final double max = <double>[
    r,
    g,
    b,
  ].reduce((double a, double v) => a > v ? a : v);
  final double min = <double>[
    r,
    g,
    b,
  ].reduce((double a, double v) => a < v ? a : v);
  double h = 0;
  double s = 0;
  final double l = (max + min) / 2;
  if (max != min) {
    final double d = max - min;
    s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    h = max == r
        ? (g - b) / d + (g < b ? 6 : 0)
        : max == g
        ? (b - r) / d + 2
        : (r - g) / d + 4;
    h /= 6;
  }
  final double nl = (l * lumMod + lumOff).clamp(0.0, 1.0);
  double hue2rgb(double p, double q, double t) {
    if (t < 0) t += 1;
    if (t > 1) t -= 1;
    if (t < 1 / 6) return p + (q - p) * 6 * t;
    if (t < 1 / 2) return q;
    if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
    return p;
  }

  final double q = nl < 0.5 ? nl * (1 + s) : nl + s - nl * s;
  final double p = 2 * nl - q;
  int channel(double value) => (value * 255).round().clamp(0, 255);
  final int nr = s == 0 ? channel(nl) : channel(hue2rgb(p, q, h + 1 / 3));
  final int ng = s == 0 ? channel(nl) : channel(hue2rgb(p, q, h));
  final int nb = s == 0 ? channel(nl) : channel(hue2rgb(p, q, h - 1 / 3));
  return ((nr << 16) | (ng << 8) | nb)
      .toRadixString(16)
      .padLeft(6, '0')
      .toUpperCase();
}

XmlElement _readRoot(String xml) {
  final XmlPullReader reader = XmlPullReader(xml);
  while (reader.next()) {
    if (reader.eventType == XmlEventType.startElement) {
      return XmlDocument.readElement(reader);
    }
  }
  throw const FormatException('Imported slide text body is empty');
}
