// lib/services/search_replace.dart
//
// Regex replacement helpers for the code editor.
//
// Re-Editor 0.10.0 passes the replacement template straight to
// String.replaceAllMapped, which treats `$1` as literal text. The editor's
// find panel uses these helpers to expand capture groups instead.
//
// The editor document is LF-normalized internally, so search and replace both
// operate on the same line separators. This also removes the CRLF mismatch
// where a multiline expression was found but not replaced.

/// Expand `$1`, `$2`, `${name}`, `$&` and `$$` in a replacement template.
///
/// Unrecognised `$` sequences are preserved literally, matching the behavior
/// users expect when replacing text that contains dollar signs.
String expandReplacementTemplate(String template, Match match) {
  final buffer = StringBuffer();
  var i = 0;
  while (i < template.length) {
    final char = template[i];
    if (char != r'$' || i + 1 >= template.length) {
      buffer.write(char);
      i++;
      continue;
    }
    final next = template[i + 1];
    if (next == r'$') {
      buffer.write(r'$');
      i += 2;
      continue;
    }
    if (next == '&') {
      buffer.write(match.group(0) ?? '');
      i += 2;
      continue;
    }
    if (next == '{') {
      final end = template.indexOf('}', i + 2);
      if (end < 0) {
        buffer.write(char);
        i++;
        continue;
      }
      final name = template.substring(i + 2, end);
      buffer.write(_groupValue(match, name));
      i = end + 1;
      continue;
    }
    if (next.codeUnitAt(0) >= 0x30 && next.codeUnitAt(0) <= 0x39) {
      var end = i + 1;
      while (end < template.length) {
        final code = template.codeUnitAt(end);
        if (code < 0x30 || code > 0x39) break;
        end++;
      }
      // Match the longest group number that exists. `$12` therefore means
      // group 12, or group 1 followed by a literal "2" when there is no 12th
      // group. Unknown numbers stay literal instead of deleting text.
      var groupEnd = end;
      int? index;
      while (groupEnd > i + 1) {
        final candidate = int.tryParse(template.substring(i + 1, groupEnd));
        if (candidate != null && candidate <= match.groupCount) {
          index = candidate;
          break;
        }
        groupEnd--;
      }
      if (index == null) {
        buffer.write(char);
        i++;
        continue;
      }
      buffer.write(match.group(index) ?? '');
      i = groupEnd;
      continue;
    }
    buffer.write(char);
    i++;
  }
  return buffer.toString();
}

String _groupValue(Match match, String group) {
  try {
    final intIndex = int.tryParse(group);
    if (intIndex != null) {
      if (intIndex > match.groupCount) return '';
      return match.group(intIndex) ?? '';
    }
    if (match is RegExpMatch) return match.namedGroup(group) ?? '';
    return '';
  } on ArgumentError {
    return '';
  }
}

/// Replace every [pattern] match in [source], expanding [template].
String replaceAllWithExpansion(String source, RegExp pattern, String template) {
  return source.replaceAllMapped(
    pattern,
    (match) => expandReplacementTemplate(template, match),
  );
}
