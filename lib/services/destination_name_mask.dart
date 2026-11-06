/// Commander-style destination masks and explicit name tokens.
///
/// `*.*` keeps the name, `*.bak` changes its extension, `*.*.bak` appends one,
/// and `?` copies one source character. Tokens `[N]`, `[E]`, `[C]`, `[C:000]`
/// mean stem, extension, and a one-based counter. Literal names are supported.
class DestinationNameMask {
  DestinationNameMask(this.mask) {
    if (mask.isEmpty ||
        mask.length > 1024 ||
        mask.contains('/') ||
        mask.contains('\\') ||
        mask.contains('\u0000')) {
      throw const FormatException(
        'Enter a destination name mask, without directories.',
      );
    }
    if (mask.contains('[') &&
        RegExp(r'\[(?!N\]|E\]|C\]|C:0{1,12}\])').hasMatch(mask)) {
      throw const FormatException('Name tokens: [N], [E], [C] or [C:000].');
    }
  }
  final String mask;

  String apply(String original, {int index = 1}) {
    final dot = original.lastIndexOf('.');
    final stem = dot > 0 ? original.substring(0, dot) : original;
    final extension = dot > 0 ? original.substring(dot + 1) : '';
    String result;
    if (mask == '*' || mask == '*.*') {
      result = original;
    } else if (mask.contains('[')) {
      result = mask
          .replaceAll('[N]', stem)
          .replaceAll('[E]', extension)
          .replaceAllMapped(
            RegExp(r'\[C(?::(0{1,12}))?\]'),
            (match) =>
                index.toString().padLeft(match.group(1)?.length ?? 1, '0'),
          );
    } else if (mask.startsWith('*.*.')) {
      result = original + mask.substring(3);
    } else {
      final split = mask.lastIndexOf('.');
      if (split >= 0) {
        final name = _part(mask.substring(0, split), stem);
        final ext = _part(mask.substring(split + 1), extension);
        result = ext.isEmpty ? name : '$name.$ext';
      } else {
        result = _part(mask, original);
      }
    }
    validateName(result);
    return result;
  }

  static String _part(String mask, String source) {
    final runes = source.runes.toList();
    final out = StringBuffer();
    var position = 0;
    for (final char in mask.runes) {
      if (char == 42) {
        out.write(String.fromCharCodes(runes.skip(position)));
        position = runes.length;
      } else if (char == 63) {
        if (position < runes.length) out.writeCharCode(runes[position++]);
      } else {
        out.writeCharCode(char);
      }
    }
    return out.toString();
  }

  static void validateName(String name) {
    if (name.isEmpty ||
        name == '.' ||
        name == '..' ||
        name.contains('/') ||
        name.contains('\\') ||
        name.contains('\u0000') ||
        RegExp(r'[\x01-\x1f]').hasMatch(name)) {
      throw const FormatException(
        'Destination names must be nonempty filenames.',
      );
    }
  }
}
