import 'dart:collection';
import 'dart:math' as math;

import 'package:quds_office_engine/quds_office_engine.dart';

/// An immutable proofing publication that can skip groups of findings
/// outside a line without changing the provider's drawing order.
final class WordProofingFindings
    extends UnmodifiableListView<OfficeProofingFinding> {
  WordProofingFindings(Iterable<OfficeProofingFinding> findings)
    : super(List<OfficeProofingFinding>.unmodifiable(findings));

  static const _batchSize = 16;
  // The line painter can recognize this publication without retaining it.
  final Object publication = Object();
  late final _bounds = _indexBatches();

  static List<OfficeProofingFinding> freeze(
    List<OfficeProofingFinding> findings,
  ) => findings.length <= _batchSize
      ? List<OfficeProofingFinding>.unmodifiable(findings)
      : WordProofingFindings(findings);

  static bool mayAffect(OfficeProofingFinding finding, int min, int max) {
    final start = finding.start;
    final end = finding.end;
    // Keep both boundaries for discretionary hyphens. Zero-length marks
    // are resolved by the painter against the exact source positions.
    return start == end || (start <= max && end >= min);
  }

  List<({int min, int max})?> _indexBatches() => [
    for (var start = 0; start < length; start += _batchSize)
      _batchBounds(start, math.min(start + _batchSize, length)),
  ];

  ({int min, int max})? _batchBounds(int start, int end) {
    final first = this[start];
    var min = first.start;
    var max = first.end;
    for (var index = start; index < end; index++) {
      final finding = this[index];
      if (finding.start == finding.end) return null;
      min = math.min(min, finding.start);
      max = math.max(max, finding.end);
    }
    return (min: min, max: max);
  }

  Iterable<OfficeProofingFinding> affecting(int min, int max) sync* {
    for (final (batch, bounds) in _bounds.indexed) {
      if (bounds != null && (bounds.min > max || bounds.max < min)) continue;
      final start = batch * _batchSize;
      final end = math.min(start + _batchSize, length);
      for (var index = start; index < end; index++) {
        final finding = this[index];
        if (mayAffect(finding, min, max)) yield finding;
      }
    }
  }
}
