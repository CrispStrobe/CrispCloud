import 'dart:ui';

import '/core/constants/int_constants.dart';
import '/shared/extensions/num_extension.dart';
import '/shared/utils/parser/double_parser.dart';

/// Represents an erased area with a position ([offset]) and a circular
/// [radius].
///
/// This model is typically used for storing, serializing, and comparing erase
/// operations in a drawing or editing context.
class ErasedOffset {
  /// Creates an [ErasedOffset] with the given [offset] and [radius].
  const ErasedOffset({required this.offset, required this.radius});

  /// Creates an [ErasedOffset] from a [map].
  ///
  /// - For versions before `11.6.0`, the `radius` may be missing and falls
  ///   back to a default value of `8.0`.
  /// - Supports both the new `map['offset'] = {x, y}` structure
  ///   and the legacy `map['x'], map['y']` fields.
  factory ErasedOffset.fromMap(Map<String, dynamic> map) {
    /// Old versions before `11.6.0` fallback to the default value.
    final radius = safeParseDouble(map['radius'], fallback: 8.0);

    final Offset offset = map['offset'] != null
        ? Offset(
            safeParseDouble(map['offset']['x']),
            safeParseDouble(map['offset']['y']),
          )
        : Offset(safeParseDouble(map['x']), safeParseDouble(map['y']));

    return ErasedOffset(offset: offset, radius: radius);
  }

  /// The position of the erased area.
  final Offset offset;

  /// The circular radius of the erased area.
  final double radius;

  /// Converts this [ErasedOffset] into a [Map] representation.
  ///
  /// - [maxDecimalPlaces] controls how many decimal places to keep
  ///   when rounding numbers. Defaults to [kMaxSafeDecimalPlaces].
  /// - [enableMinify] can be used for future optimizations
  ///   (currently not applied).
  Map<String, dynamic> toMap({
    int maxDecimalPlaces = kMaxSafeDecimalPlaces,
    bool enableMinify = false,
  }) {
    return {
      'offset': {
        'x': offset.dx.roundSmart(maxDecimalPlaces),
        'y': offset.dy.roundSmart(maxDecimalPlaces),
      },
      'radius': radius.roundSmart(maxDecimalPlaces),
    };
  }

  @override
  bool operator ==(Object other) {
    return other is ErasedOffset &&
        other.radius == radius &&
        other.offset == offset;
  }

  @override
  int get hashCode => radius.hashCode ^ offset.hashCode;
}
