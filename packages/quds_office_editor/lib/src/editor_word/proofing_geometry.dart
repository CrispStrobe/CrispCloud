import 'package:flutter/services.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

/// Maps source findings to painted text while excluding generated note labels
/// and field values. Ordinary shaped lines use source coordinates directly.
abstract final class WordProofingGeometry {
  static List<TextRange> displayRanges(LaidOutLine line, int start, int end) {
    final offsets = line.proofingOffsets;
    if (offsets == null) return [TextRange(start: start, end: end)];
    if (start == end) {
      final index = offsets.indexOf(start);
      return index < 0 ? [] : [TextRange(start: index, end: index)];
    }
    final result = <TextRange>[];
    int? from;
    final length = (line.overlayText?.length ?? offsets.length - 1).clamp(
      0,
      offsets.length - 1,
    );
    for (var i = 0; i < length; i++) {
      final source = offsets[i];
      if (source != null && source >= start && source < end) {
        from ??= i;
      } else if (from != null) {
        result.add(TextRange(start: from, end: i));
        from = null;
      }
    }
    if (from != null) result.add(TextRange(start: from, end: length));
    return result;
  }
}
