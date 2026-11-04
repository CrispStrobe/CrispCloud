import 'dart:typed_data';

/// Parses a ToUnicode CMap stream (ISO 32000-1 §9.10.3).
class PdfToUnicode {
  /// PdfToUnicode API.
  PdfToUnicode(this._map);

  final Map<int, String> _map;

  /// parse API.
  factory PdfToUnicode.parse(Uint8List bytes) {
    final String text = String.fromCharCodes(bytes);
    final Map<int, String> map = <int, String>{};
    final RegExp hex = RegExp(r'<([0-9A-Fa-f]+)>');
    final Iterable<RegExpMatch> bfchar = RegExp(
      r'beginbfchar([\s\S]*?)endbfchar',
    ).allMatches(text);
    for (final RegExpMatch block in bfchar) {
      final List<RegExpMatch> pairs = hex.allMatches(block.group(1)!).toList();
      for (int i = 0; i + 1 < pairs.length; i += 2) {
        map[_cid(pairs[i].group(1)!)] = _ucs(pairs[i + 1].group(1)!);
      }
    }
    final Iterable<RegExpMatch> bfrange = RegExp(
      r'beginbfrange([\s\S]*?)endbfrange',
    ).allMatches(text);
    for (final RegExpMatch block in bfrange) {
      final String body = block.group(1)!;
      final List<String> lines = body.split(RegExp(r'[\r\n]+'));
      for (final String line in lines) {
        final List<RegExpMatch> xs = hex.allMatches(line).toList();
        if (xs.length >= 3) {
          final int from = _cid(xs[0].group(1)!);
          final int to = _cid(xs[1].group(1)!);
          final int dest = _cid(xs[2].group(1)!);
          for (int c = from; c <= to; c++) {
            map[c] = String.fromCharCode(dest + (c - from));
          }
        }
      }
    }
    return PdfToUnicode(map);
  }

  /// mapCid API.
  String mapCid(int cid) => _map[cid] ?? '';

  /// First CID for each Unicode code unit (copy / CFF cmap invert).
  Map<int, int> invertCodeUnits() {
    final Map<int, int> out = <int, int>{};
    _map.forEach((int cid, String text) {
      if (text.isNotEmpty) {
        out.putIfAbsent(text.codeUnitAt(0), () => cid);
      }
    });
    return out;
  }

  static int _cid(String hex) => int.parse(hex, radix: 16);

  static String _ucs(String hex) {
    if (hex.isEmpty) {
      return '';
    }
    if (hex.length <= 4) {
      return String.fromCharCode(int.parse(hex, radix: 16));
    }
    // UTF-32BE padded BMP (`00000041`) used by some writers.
    if (hex.length == 8 && hex.startsWith('0000')) {
      return String.fromCharCode(int.parse(hex.substring(4), radix: 16));
    }
    final StringBuffer buf = StringBuffer();
    for (int i = 0; i + 3 < hex.length; i += 4) {
      final int cu = int.parse(hex.substring(i, i + 4), radix: 16);
      if (cu == 0) {
        continue;
      }
      buf.writeCharCode(cu);
    }
    return buf.toString();
  }
}
