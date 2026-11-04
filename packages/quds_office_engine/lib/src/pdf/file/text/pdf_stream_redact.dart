/// Removes text-showing operators whose origin lies inside a redaction rect.
library;

import '../model/pdf_annot.dart';

/// Rewrites a content stream so `Tj` / `TJ` strings inside [rect] become empty.
abstract final class PdfStreamRedactor {
  /// strip API.
  static String strip(String source, PdfRect rect) {
    final StringBuffer out = StringBuffer();
    var x = 0.0;
    var y = 0.0;
    var written = 0;
    var i = 0;
    while (i < source.length) {
      if (source.startsWith('Tm', i) && _boundary(source, i, 2)) {
        final List<double>? nums = _numbersBefore(source, i, 6);
        if (nums != null) {
          x = nums[4];
          y = nums[5];
        }
      } else if (source.startsWith('Td', i) && _boundary(source, i, 2)) {
        final List<double>? nums = _numbersBefore(source, i, 2);
        if (nums != null) {
          x += nums[0];
          y += nums[1];
        }
      } else if (source.startsWith('Tj', i) && _boundary(source, i, 2)) {
        final int literal = _literalStart(source, i);
        if (literal >= written && rect.contains(x, y)) {
          out.write(source.substring(written, literal));
          out.write(source[literal] == '(' ? '()' : '<>');
          written = i;
        }
      }
      i++;
    }
    out.write(source.substring(written));
    return out.toString();
  }

  static bool _boundary(String source, int i, int length) {
    final bool before = i == 0 || !_token(source.codeUnitAt(i - 1));
    final int after = i + length;
    return before && (after >= source.length || !_token(source.codeUnitAt(after)));
  }

  static bool _token(int unit) =>
      (unit >= 0x30 && unit <= 0x39) ||
      (unit >= 0x41 && unit <= 0x5A) ||
      (unit >= 0x61 && unit <= 0x7A);

  static List<double>? _numbersBefore(String source, int at, int count) {
    final List<double> nums = <double>[];
    var i = at - 1;
    while (i >= 0 && nums.length < count) {
      while (i >= 0 && source.codeUnitAt(i) <= 32) {
        i--;
      }
      if (i < 0) {
        break;
      }
      var start = i;
      while (start >= 0 && _numberChar(source.codeUnitAt(start))) {
        start--;
      }
      start++;
      if (start > i) {
        break;
      }
      final double? value = double.tryParse(source.substring(start, i + 1));
      if (value == null) {
        break;
      }
      nums.add(value);
      i = start - 1;
    }
    if (nums.length < count) {
      return null;
    }
    return nums.reversed.toList();
  }

  static bool _numberChar(int unit) =>
      (unit >= 0x30 && unit <= 0x39) || unit == 0x2E || unit == 0x2D || unit == 0x2B;

  static int _literalStart(String source, int tj) {
    var i = tj - 1;
    while (i >= 0 && source.codeUnitAt(i) <= 32) {
      i--;
    }
    if (i < 0) {
      return -1;
    }
    if (source[i] == ')') {
      var depth = 0;
      for (int k = i; k >= 0; k--) {
        if (source[k] == ')' && (k == 0 || source[k - 1] != '\\')) {
          depth++;
        } else if (source[k] == '(' && (k == 0 || source[k - 1] != '\\')) {
          depth--;
          if (depth == 0) {
            return k;
          }
        }
      }
      return -1;
    }
    if (source[i] == '>') {
      final int open = source.lastIndexOf('<', i);
      return open;
    }
    return -1;
  }

}
