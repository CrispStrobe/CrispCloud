import 'dart:typed_data';

/// Host-owned lookup for a macro asset. Keys do not imply filesystem access.
typedef OfficeMacroAssetResolver = Uint8List Function(String key);

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

/// Resolves an explicitly supplied host asset and verifies its image signature.
Uint8List readPicture(StepInput step, OfficeMacroAssetResolver? resolveAsset) {
  final path = step.string('file');
  if (resolveAsset == null) {
    throw UnsupportedError('Picture operations require a host asset resolver');
  }
  final bytes = Uint8List.fromList(resolveAsset(path));
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
