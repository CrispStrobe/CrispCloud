import 'package:characters/characters.dart';

/// UAX #29 grapheme-cluster segmentation used for caret hit-testing.
class GraphemeCluster {
  /// GraphemeCluster API.
  const GraphemeCluster({
    required this.start,
    required this.end,
    required this.text,
  });

  /// start API.
  final int start;

  /// end API.
  final int end;

  /// text API.
  final String text;

  /// length API.
  int get length => end - start;
}

/// Class GraphemeClusters.
abstract final class GraphemeClusters {
  /// Segment Unicode extended grapheme clusters without changing source text.
  /// Offsets remain UTF-16 code-unit indexes, matching Dart strings and Word
  /// ranges. Unicode boundary rules come from the pure-Dart characters package.
  static List<GraphemeCluster> segment(String text) {
    if (text.isEmpty) {
      return const <GraphemeCluster>[];
    }
    final out = <GraphemeCluster>[];
    var start = 0;
    for (final cluster in text.characters) {
      final end = start + cluster.length;
      out.add(GraphemeCluster(start: start, end: end, text: cluster));
      start = end;
    }
    return out;
  }

  /// UTF-16 end offsets without allocating a substring for each grapheme.
  static Iterable<int> endOffsets(String text) sync* {
    final range = CharacterRange(text);
    while (range.moveNext()) {
      yield text.length - range.stringAfterLength;
    }
  }

  /// UTF-16 offsets at which a grapheme starts.
  static Set<int> startOffsets(String text) {
    final range = CharacterRange(text);
    final starts = <int>{};
    while (range.moveNext()) {
      starts.add(range.stringBeforeLength);
    }
    return starts;
  }

  /// Returns the cluster index containing logical UTF-16 [offset].
  static int indexAt(List<GraphemeCluster> clusters, int offset) {
    for (int i = 0; i < clusters.length; i++) {
      if (offset < clusters[i].end) {
        return i;
      }
    }
    return clusters.length;
  }
}
