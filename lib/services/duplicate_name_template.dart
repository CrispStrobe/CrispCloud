import 'destination_name_mask.dart';

/// A filename-only template used whenever Keep both needs another free name.
/// `{ext}` includes its leading dot, so extensionless names never gain one.
/// Counters can be padded with zeroes, for example `{counter:000}`.
class DuplicateNameTemplate {
  DuplicateNameTemplate(this.template) : _parts = _parse(template) {
    if (!_parts.any((part) => part.token == 'counter')) {
      throw const FormatException(
        'Duplicate names require {counter} or a padded counter such as {counter:000}.',
      );
    }
    // Validate literals before a preview can inspect or mutate any target.
    apply('example.txt', index: 1);
  }

  static const defaultTemplate = '{name} ({counter}){ext}';
  final String template;
  final List<_NamePart> _parts;

  String apply(String original, {required int index}) {
    if (index < 1) throw ArgumentError.value(index, 'index');
    DestinationNameMask.validateName(original);
    final dot = original.lastIndexOf('.');
    final name = dot > 0 ? original.substring(0, dot) : original;
    final extension = dot > 0 ? original.substring(dot) : '';
    final result = StringBuffer();
    for (final part in _parts) {
      result.write(switch (part.token) {
        'name' => name,
        'ext' => extension,
        'counter' => index.toString().padLeft(part.width, '0'),
        _ => part.literal,
      });
    }
    final generated = result.toString();
    DestinationNameMask.validateName(generated);
    return generated;
  }

  static List<_NamePart> _parse(String value) {
    if (value.isEmpty || value.length > 1024) {
      throw const FormatException(
        'Enter a duplicate-name template between 1 and 1024 characters.',
      );
    }
    final parts = <_NamePart>[];
    final literal = StringBuffer();
    void flush() {
      if (literal.isEmpty) return;
      parts.add(_NamePart(literal: literal.toString()));
      literal.clear();
    }

    for (var position = 0; position < value.length;) {
      final character = value[position];
      if ((character == '{' || character == '}') &&
          position + 1 < value.length &&
          value[position + 1] == character) {
        literal.write(character);
        position += 2;
        continue;
      }
      if (character == '}') {
        throw const FormatException('Use }} for a literal closing brace.');
      }
      if (character != '{') {
        literal.write(character);
        position++;
        continue;
      }
      flush();
      final end = value.indexOf('}', position + 1);
      if (end < 0) {
        throw const FormatException('A duplicate-name token is not closed.');
      }
      final token = value.substring(position + 1, end);
      if (token == 'name' || token == 'ext' || token == 'counter') {
        parts.add(_NamePart(token: token));
      } else {
        final padded = RegExp(r'^counter:(0{1,12})$').firstMatch(token);
        if (padded == null) {
          throw const FormatException(
            'Duplicate-name tokens are {name}, {ext}, {counter} and {counter:000}.',
          );
        }
        parts.add(_NamePart(token: 'counter', width: padded.group(1)!.length));
      }
      position = end + 1;
    }
    flush();
    return parts;
  }
}

class _NamePart {
  const _NamePart({this.token, this.literal = '', this.width = 1});
  final String? token;
  final String literal;
  final int width;
}
