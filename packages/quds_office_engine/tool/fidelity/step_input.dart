import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Strict JSON input for repeatable scenarios. A misspelled field is an error.
class StepInput {
  StepInput(this.values);
  final Map<String, Object?> values;
  bool has(String key) => values.containsKey(key);

  void fields(Iterable<String> allowed) {
    final unknown = values.keys.toSet().difference(<String>{'op', ...allowed});
    if (unknown.isNotEmpty) {
      throw ArgumentError(
        'Unknown fields for ${string('op')}: ${unknown.join(', ')}',
      );
    }
  }

  String string(String key, {String? fallback}) {
    final value = values[key];
    if (!has(key) && fallback != null) return fallback;
    if (value is! String) throw ArgumentError('$key must be a string');
    return value;
  }

  int integer(String key, {int? fallback, int min = 0, int? max}) {
    final value = !has(key) ? fallback : values[key];
    if (value is! int || value < min || (max != null && value > max)) {
      throw ArgumentError(
        '$key must be an integer in $min..${max ?? 'unbounded'}',
      );
    }
    return value;
  }

  double number(String key, {double? fallback, double? min, double? max}) {
    final value = !has(key) ? fallback : values[key];
    if (value is! num ||
        !value.isFinite ||
        (min != null && value < min) ||
        (max != null && value > max)) {
      throw ArgumentError(
        '$key must be a finite number in ${min ?? '-infinity'}..${max ?? 'infinity'}',
      );
    }
    return value.toDouble();
  }

  bool boolean(String key, {bool? fallback}) {
    final value = !has(key) ? fallback : values[key];
    if (value is! bool) throw ArgumentError('$key must be a boolean');
    return value;
  }

  String color(String key) {
    final value = string(key);
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(value)) {
      throw ArgumentError('$key must be a six-digit RGB hex color');
    }
    return value.toUpperCase();
  }

  T item<T>(String key, Iterable<T> items, {int? fallback}) {
    final list = items.toList(growable: false);
    return list[integer(key, fallback: fallback, max: list.length - 1)];
  }

  Map<String, Object?> object(String key) {
    final value = values[key];
    if (value is! Map<String, Object?>) {
      throw ArgumentError('$key must be an object');
    }
    return value;
  }
}

List<Map<String, Object?>> readSteps(String path) {
  final Object? input = jsonDecode(File(path).readAsStringSync());
  if (input is! List<Object?>) {
    throw const FormatException('Steps must be a JSON array');
  }
  return <Map<String, Object?>>[
    for (final value in input)
      if (value is Map<String, Object?>)
        value
      else
        throw const FormatException('Every step must be a JSON object'),
  ];
}

/// Relative assets belong to the scenario file, so a script is cwd-independent.
Uint8List readPicture(StepInput step, String? assetDirectory) {
  final path = step.string('file');
  final file = File(path).isAbsolute || assetDirectory == null
      ? File(path)
      : File('$assetDirectory/$path');
  final bytes = file.readAsBytesSync();
  final png =
      bytes.length >= 24 &&
      bytes.take(8).join(',') == '137,80,78,71,13,10,26,10';
  final jpeg =
      bytes.length >= 4 &&
      bytes[0] == 255 &&
      bytes[1] == 216 &&
      bytes[bytes.length - 2] == 255 &&
      bytes.last == 217;
  if (!png && !jpeg) throw ArgumentError('Picture must be PNG or JPEG: $path');
  return bytes;
}

/// Write only after all edits and serialization succeed, then atomically rename.
void writeOutput(String path, Uint8List bytes) {
  final target = File(path);
  target.parent.createSync(recursive: true);
  final temporary = File(
    '$path.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
  );
  try {
    temporary.writeAsBytesSync(bytes, flush: true);
    temporary.renameSync(path);
  } finally {
    if (temporary.existsSync()) temporary.deleteSync();
  }
}
