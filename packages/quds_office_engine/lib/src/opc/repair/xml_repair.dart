import 'dart:convert';

/// Recovers well-formed-enough XML from broken Office part markup.
abstract final class XmlRepair {
  /// looksLikeXml API.
  static bool looksLikeXml(List<int> bytes) {
    for (int i = 0; i < bytes.length && i < 256; i++) {
      final int b = bytes[i];
      if (b == 0x3C) {
        return true;
      }
      if (b > 0x20) {
        return false;
      }
    }
    return false;
  }

  /// decode API.
  static String decode(List<int> bytes) {
    final List<int> cleaned = <int>[
      for (final int b in bytes)
        if (b != 0) b,
    ];
    return utf8.decode(cleaned, allowMalformed: true);
  }

  /// Strips illegal control characters, recovers tag nesting, and closes
  /// leftover open elements so Word/Excel can parse the part.
  static String sanitize(String raw) {
    final StringBuffer out = StringBuffer();
    final List<String> stack = <String>[];
    var i = 0;
    var changed = false;
    while (i < raw.length) {
      final int ch = raw.codeUnitAt(i);
      if (ch == 0x3C) {
        if (i + 1 < raw.length && raw.codeUnitAt(i + 1) == 0x21) {
          final int end = _skipSpecial(raw, i);
          out.write(raw.substring(i, end));
          i = end;
          continue;
        }
        if (i + 1 < raw.length && raw.codeUnitAt(i + 1) == 0x3F) {
          final int end = raw.indexOf('?>', i + 2);
          if (end < 0) {
            break;
          }
          out.write(raw.substring(i, end + 2));
          i = end + 2;
          continue;
        }
        if (i + 1 < raw.length && raw.codeUnitAt(i + 1) == 0x2F) {
          final ({String name, int next}) tag = _readEnd(raw, i);
          i = tag.next;
          if (tag.name.isEmpty) {
            changed = true;
            continue;
          }
          final int match = stack.lastIndexOf(tag.name);
          if (match < 0) {
            changed = true;
            continue;
          }
          while (stack.length - 1 > match) {
            out.write('</${stack.removeLast()}>');
            changed = true;
          }
          stack.removeLast();
          out.write('</${tag.name}>');
          continue;
        }
        final ({String name, bool empty, int next}) start = _readStart(raw, i);
        if (start.name.isEmpty) {
          out.write('&lt;');
          i++;
          changed = true;
          continue;
        }
        out.write(raw.substring(i, start.next));
        i = start.next;
        if (!start.empty) {
          stack.add(start.name);
        }
        continue;
      }
      if (_illegal(ch)) {
        changed = true;
        i++;
        continue;
      }
      if (ch == 0x26) {
        final int semi = raw.indexOf(';', i + 1);
        if (semi < 0 || semi - i > 12 || !_entityBody(raw, i + 1, semi)) {
          out.write('&amp;');
          i++;
          changed = true;
          continue;
        }
        out.write(raw.substring(i, semi + 1));
        i = semi + 1;
        continue;
      }
      out.writeCharCode(ch);
      i++;
    }
    while (stack.isNotEmpty) {
      out.write('</${stack.removeLast()}>');
      changed = true;
    }
    return changed ? out.toString() : raw;
  }

  /// needsSanitize API.
  static bool needsSanitize(String raw) {
    return sanitize(raw) != raw;
  }

  static bool _illegal(int ch) {
    return ch < 0x09 ||
        ch == 0x0B ||
        ch == 0x0C ||
        (ch > 0x0D && ch < 0x20) ||
        ch == 0x7F;
  }

  static bool _entityBody(String raw, int start, int end) {
    if (end <= start) {
      return false;
    }
    if (raw.codeUnitAt(start) == 0x23) {
      if (start + 1 < end &&
          (raw.codeUnitAt(start + 1) == 0x78 ||
              raw.codeUnitAt(start + 1) == 0x58)) {
        for (int i = start + 2; i < end; i++) {
          final int c = raw.codeUnitAt(i);
          final bool hex =
              (c >= 48 && c <= 57) ||
              (c >= 65 && c <= 70) ||
              (c >= 97 && c <= 102);
          if (!hex) {
            return false;
          }
        }
        return end > start + 2;
      }
      for (int i = start + 1; i < end; i++) {
        final int c = raw.codeUnitAt(i);
        if (c < 48 || c > 57) {
          return false;
        }
      }
      return end > start + 1;
    }
    for (int i = start; i < end; i++) {
      final int c = raw.codeUnitAt(i);
      if (!((c >= 65 && c <= 90) || (c >= 97 && c <= 122))) {
        return false;
      }
    }
    return true;
  }

  static int _skipSpecial(String raw, int i) {
    if (raw.startsWith('<!--', i)) {
      final int end = raw.indexOf('-->', i + 4);
      return end < 0 ? raw.length : end + 3;
    }
    if (raw.startsWith('<![CDATA[', i)) {
      final int end = raw.indexOf(']]>', i + 9);
      return end < 0 ? raw.length : end + 3;
    }
    final int end = raw.indexOf('>', i + 2);
    return end < 0 ? raw.length : end + 1;
  }

  static ({String name, int next}) _readEnd(String raw, int i) {
    var p = i + 2;
    while (p < raw.length && _isSpace(raw.codeUnitAt(p))) {
      p++;
    }
    final int start = p;
    while (p < raw.length && _isName(raw.codeUnitAt(p))) {
      p++;
    }
    final String name = raw.substring(start, p);
    final int gt = raw.indexOf('>', p);
    return (name: name, next: gt < 0 ? raw.length : gt + 1);
  }

  static ({String name, bool empty, int next}) _readStart(String raw, int i) {
    var p = i + 1;
    if (p >= raw.length || !_isNameStart(raw.codeUnitAt(p))) {
      return (name: '', empty: true, next: i + 1);
    }
    final int start = p;
    while (p < raw.length && _isName(raw.codeUnitAt(p))) {
      p++;
    }
    final String name = raw.substring(start, p);
    final int gt = raw.indexOf('>', p);
    if (gt < 0) {
      return (name: name, empty: true, next: raw.length);
    }
    final bool empty = gt > p && raw.codeUnitAt(gt - 1) == 0x2F;
    return (name: name, empty: empty, next: gt + 1);
  }

  static bool _isSpace(int c) =>
      c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;

  static bool _isNameStart(int c) =>
      (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 0x5F || c == 0x3A;

  static bool _isName(int c) =>
      _isNameStart(c) || (c >= 48 && c <= 57) || c == 0x2D || c == 0x2E;
}
