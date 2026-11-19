import '../../xml/namespaces.dart';
import '../../xml/xml_node.dart';
import '../../xml/xml_reader.dart';
import '../model/pml_presentation.dart';

/// Parses a captured `p:txBody` snapshot into paragraphs and styled runs.
List<PmlTextParagraph> parsePmlRichText(
  String xml,
  Map<String, String> colors,
) {
  final XmlElement root = _readRoot(xml);
  final List<PmlTextParagraph> paragraphs = <PmlTextParagraph>[];
  for (final XmlElement paragraph in root.childrenNamed(
    'p',
    namespaceUri: OfficeNamespaces.a,
  )) {
    final XmlElement? pPr = paragraph.firstChild(
      'pPr',
      namespaceUri: OfficeNamespaces.a,
    );
    final PmlTextParagraph out = PmlTextParagraph(
      align: _align(pPr?.getAttribute('algn')),
      level: int.tryParse(pPr?.getAttribute('lvl') ?? '') ?? 0,
      marginLeftPt: _emuToPt(pPr?.getAttribute('marL')),
      indentPt: _emuToPt(pPr?.getAttribute('indent')),
      rightToLeft: pPr?.getAttribute('rtl') == '1',
      defaultTabPt: _emuToPt(pPr?.getAttribute('defTabSz') ?? '') == 0
          ? 72
          : _emuToPt(pPr?.getAttribute('defTabSz')),
    );
    if (pPr != null) {
      final XmlElement? line = pPr.firstChild(
        'lnSpc',
        namespaceUri: OfficeNamespaces.a,
      );
      final XmlElement? pct = line?.firstChild(
        'spcPct',
        namespaceUri: OfficeNamespaces.a,
      );
      final int? pctVal = int.tryParse(pct?.getAttribute('val') ?? '');
      if (pctVal != null && pctVal > 0) {
        out.lineSpacing = pctVal / 100000;
      }
      out.spaceBeforePt = _spacing(pPr, 'spcBef');
      out.spaceAfterPt = _spacing(pPr, 'spcAft');
    }
    for (final XmlElement child in paragraph.childElements) {
      if (child.localName == 'r' || child.localName == 'fld') {
        final XmlElement? rPr = child.firstChild(
          'rPr',
          namespaceUri: OfficeNamespaces.a,
        );
        final String text = child
            .childrenNamed('t', namespaceUri: OfficeNamespaces.a)
            .map((XmlElement e) => e.text)
            .join();
        if (text.isEmpty) continue;
        out.runs.add(
          PmlTextRun(
            text: text,
            fontSizePt:
                (int.tryParse(rPr?.getAttribute('sz') ?? '') ?? 0) / 100,
            bold: rPr?.getAttribute('b') == '1',
            italic: rPr?.getAttribute('i') == '1',
            underline: switch (rPr?.getAttribute('u')) {
              null || 'none' => false,
              _ => true,
            },
            strike: switch (rPr?.getAttribute('strike')) {
              null || 'noStrike' => false,
              _ => true,
            },
            baseline:
                (int.tryParse(rPr?.getAttribute('baseline') ?? '') ?? 0) /
                100000,
            color: _runColor(rPr, colors),
            fontFamily:
                rPr
                    ?.firstChild('latin', namespaceUri: OfficeNamespaces.a)
                    ?.getAttribute('typeface') ??
                '',
          ),
        );
      } else if (child.localName == 'br') {
        out.runs.add(PmlTextRun(text: '\n'));
      }
    }
    final XmlElement? end = paragraph.firstChild(
      'endParaRPr',
      namespaceUri: OfficeNamespaces.a,
    );
    if (end != null) {
      out.defaultFontSizePt =
          (int.tryParse(end.getAttribute('sz') ?? '') ?? 0) / 100;
      out.defaultColor = _runColor(end, colors);
      out.defaultBold = end.getAttribute('b') == '1';
      out.defaultItalic = end.getAttribute('i') == '1';
      for (final PmlTextRun run in out.runs) {
        if (run.color.isEmpty) run.color = out.defaultColor;
        if (out.defaultBold) run.bold = true;
        if (out.defaultItalic) run.italic = true;
      }
    }
    paragraphs.add(out);
  }
  return paragraphs;
}

PmlTextAlign _align(String? value) => switch (value) {
  'ctr' => PmlTextAlign.center,
  'r' => PmlTextAlign.right,
  'just' => PmlTextAlign.justify,
  _ => PmlTextAlign.left,
};

double _emuToPt(String? value) => (int.tryParse(value ?? '') ?? 0) / 12700;

double _spacing(XmlElement pPr, String name) {
  final XmlElement? spacing = pPr.firstChild(
    name,
    namespaceUri: OfficeNamespaces.a,
  );
  if (spacing == null) return 0;
  final XmlElement? pts = spacing.firstChild(
    'spcPts',
    namespaceUri: OfficeNamespaces.a,
  );
  return (int.tryParse(pts?.getAttribute('val') ?? '') ?? 0) / 100;
}

String _runColor(XmlElement? rPr, Map<String, String> colors) {
  if (rPr == null) return '';
  final XmlElement? fill = rPr.firstChild(
    'solidFill',
    namespaceUri: OfficeNamespaces.a,
  );
  if (fill == null) return '';
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
