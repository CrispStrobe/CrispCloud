import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const String _phrase = 'تقرير ربع سنوي';

void main() {
  final SfntFont? naskh = _tryPath(
    '../quds_office_editor/fonts/NotoNaskhArabic-Regular.ttf',
  );
  final SfntFont? latin = _tryPath(
    '../quds_office_editor/fonts/LiberationSans-Regular.ttf',
  );

  test('WinAnsi showLatin does not UTF-8-encode middle dot', () {
    final PdfCanvas canvas = PdfCanvas(200, 200);
    canvas.showLatin(
      x: 10,
      y: 20,
      fontSize: 11,
      text: 'ISO 32000-1 · Parallel',
      color: '000000',
    );
    final String stream = utf8.decode(canvas.toStream());
    expect(stream, contains(r'\267'));
    expect(stream, isNot(contains('Â')));
    expect(canvas.toStream(), isNot(contains(0xC2)));
  });

  test('Yeh joins when the previous letter is dual, not after Waw', () {
    final List<ShapedChar> taqrir = ArabicShaper.shape('تقرير');
    final ShapedChar yehInTaqrir = taqrir[3];
    expect(yehInTaqrir.codePoint, 0xFEF3);
    expect(yehInTaqrir.form, ArabicJoinForm.initial);
    expect(yehInTaqrir.advanceFactor, 1);

    final List<ShapedChar> bi = ArabicShaper.shape('بي');
    expect(bi.last.codePoint, 0xFEF2);
    expect(bi.last.form, ArabicJoinForm.finalForm);

    // Waw is right-joining, so Yeh in سنوي is isolated. A final form here
    // would glue the joining stub onto Waw.
    final List<ShapedChar> sanawi = ArabicShaper.shape('سنوي');
    expect(sanawi.last.codePoint, 0xFEF1);
    expect(sanawi.last.form, ArabicJoinForm.isolated);
    expect(sanawi.last.advanceFactor, 1);

    final List<ShapedChar> forced = ArabicShaper.shape('ي\u200D');
    expect(forced.first.form, ArabicJoinForm.initial);
    expect(forced.first.advanceFactor, 1);
    expect(forced[1].advanceFactor, 0);
  });

  test('Word PDF embeds Arabic as Identity-H, not WinAnsi mojibake', () {
    if (naskh == null) {
      markTestSkipped('Noto Naskh Arabic is not next to the engine package');
    }
    final Uint8List pdf = OfficePdfExport.word(
      _doc(_phrase),
      fonts: OfficeFontSet(primary: naskh),
      title: 'Arabic',
    );
    final String ascii = latin1.decode(pdf, allowInvalid: true);
    expect(ascii, contains('/Identity-H'));
    expect(_indexOf(pdf, String.fromCharCodes(_utf8(_phrase)), 0), lessThan(0));

    final String inflated = _inflateAll(pdf);
    final Map<int, int> toUnicode = _bfchars(inflated);
    expect(toUnicode.values, contains(0xFEF3));
    expect(toUnicode.values, contains(0xFEF1));

    final int joiningYeh = toUnicode.entries
        .firstWhere((MapEntry<int, int> e) => e.value == 0xFEF3)
        .key;
    final int isolatedYeh = toUnicode.entries
        .firstWhere((MapEntry<int, int> e) => e.value == 0xFEF1)
        .key;
    final List<int> widths = _widths(ascii);
    expect(widths[joiningYeh], greaterThan(0));
    expect(widths[isolatedYeh], greaterThan(0));

    final List<({double x, int gid})> shows = _shows(inflated);
    expect(shows, isNotEmpty);
    final List<double> xs = <double>[for (final s in shows) s.x];
    expect(
      xs.reduce((double a, double b) => a > b ? a : b) -
          xs.reduce((double a, double b) => a < b ? a : b),
      greaterThan(20),
    );
    for (final ({double x, int gid}) show in shows) {
      if (show.gid != joiningYeh && show.gid != isolatedYeh) {
        continue;
      }
      final bool stacked = shows.any(
        (({double x, int gid}) other) =>
            other.gid != show.gid && (other.x - show.x).abs() < 0.4,
      );
      expect(
        stacked,
        isFalse,
        reason: 'Yeh gid ${show.gid} stacked at ${show.x}',
      );
    }

    final String extracted = PdfExtract.pageText(PdfFile.open(pdf), 0);
    final String folded = ArabicShaper.foldPresentation(extracted);
    for (final int cp in _phrase.runes) {
      if (cp == 0x20) {
        continue;
      }
      expect(folded.runes, contains(cp));
    }
  });

  test('Word PDF Arabic comes back as logical letters', () {
    if (naskh == null) {
      markTestSkipped('Noto Naskh Arabic is not next to the engine package');
    }
    final Uint8List pdf = OfficePdfExport.word(
      _doc('$_phrase 2026'),
      fonts: OfficeFontSet(
        primary: naskh,
        fallbacks: <SfntFont>[if (latin != null) latin],
      ),
      title: 'Arabic',
    );
    final String text = PdfToOffice.recover(PdfFile.open(pdf))
        .pages
        .expand((PdfOfficePage page) => page.lines)
        .map((PdfOfficeLine line) => line.text)
        .join('\n');
    expect(text, contains('تقرير ربع سنوي'));
    expect(text, contains('2026'));
    expect(text, isNot(contains('ﺮ')));
  });

  test('Latin-only export does not WinAnsi-mojibake Arabic', () {
    if (latin == null) {
      markTestSkipped('Liberation Sans is not next to the engine package');
    }
    final Uint8List pdf = OfficePdfExport.word(
      _doc(_phrase),
      font: latin,
      title: 'Latin only',
    );
    expect(_indexOf(pdf, String.fromCharCodes(_utf8(_phrase)), 0), lessThan(0));
  });
}

WmlDocument _doc(String text) {
  return WmlDocument(
    sections: <WmlSection>[
      WmlSection(
        blocks: <WmlBlock>[
          WmlParagraph(
            properties: WmlParagraphProps(
              rightToLeft: true,
              justification: WmlJustification.right,
            ),
            inlines: <WmlInline>[WmlRun(text: text)],
          ),
        ],
      ),
    ],
  );
}

SfntFont? _tryPath(String relative) {
  final File file = File(relative);
  if (!file.existsSync()) {
    return null;
  }
  return SfntFont.parse(file.readAsBytesSync());
}

List<int> _utf8(String text) => utf8.encode(text);

String _inflateAll(Uint8List pdf) {
  final StringBuffer out = StringBuffer();
  final List<int> mark = 'stream\n'.codeUnits;
  var i = 0;
  while (i < pdf.length - mark.length) {
    var hit = true;
    for (int k = 0; k < mark.length; k++) {
      if (pdf[i + k] != mark[k]) {
        hit = false;
        break;
      }
    }
    if (!hit) {
      i++;
      continue;
    }
    final int start = i + mark.length;
    final int end = _indexOf(pdf, 'endstream', start);
    if (end < 0) {
      break;
    }
    var payload = Uint8List.sublistView(pdf, start, end);
    if (payload.isNotEmpty && payload.last == 0x0A) {
      payload = Uint8List.sublistView(payload, 0, payload.length - 1);
    }
    if (payload.length >= 2 && payload[0] == 0x78) {
      try {
        out.write(
          utf8.decode(PdfFlate.decompress(payload), allowMalformed: true),
        );
      } catch (_) {}
    } else {
      out.write(latin1.decode(payload, allowInvalid: true));
    }
    i = end + 9;
  }
  return out.toString();
}

Map<int, int> _bfchars(String inflated) {
  final Map<int, int> map = <int, int>{};
  final RegExp pair = RegExp(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>');
  for (final RegExpMatch m in pair.allMatches(inflated)) {
    final int gid = int.parse(m.group(1)!, radix: 16);
    final int uni = int.parse(m.group(2)!, radix: 16);
    if (uni >= 0x0600) {
      map[gid] = uni;
    }
  }
  return map;
}

List<int> _widths(String ascii) {
  final RegExp w = RegExp(r'/W \[ 0 \[([0-9 ]+)\] \]');
  final Match? match = w.firstMatch(ascii);
  expect(match, isNotNull, reason: 'CID /W array');
  return <int>[
    for (final String part in match!.group(1)!.trim().split(RegExp(r'\s+')))
      if (part.isNotEmpty) int.parse(part),
  ];
}

List<({double x, int gid})> _shows(String inflated) {
  final List<({double x, int gid})> out = <({double x, int gid})>[];
  final RegExp tm = RegExp(
    r'1 0 [\d.\-]+ -1 ([\d.\-]+) [\d.\-]+ Tm\s+\[<([0-9A-Fa-f]+)>\] TJ',
  );
  for (final RegExpMatch m in tm.allMatches(inflated)) {
    out.add((
      x: double.parse(m.group(1)!),
      gid: int.parse(m.group(2)!, radix: 16),
    ));
  }
  return out;
}

int _indexOf(Uint8List data, String token, int from) {
  final List<int> needle = token.codeUnits;
  for (int i = from; i <= data.length - needle.length; i++) {
    var ok = true;
    for (int k = 0; k < needle.length; k++) {
      if (data[i + k] != needle[k]) {
        ok = false;
        break;
      }
    }
    if (ok) {
      return i;
    }
  }
  return -1;
}
