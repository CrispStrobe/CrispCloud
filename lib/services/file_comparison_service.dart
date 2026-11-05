import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../models/file_item.dart';
import 'editor_document.dart';
import 'file_operation_service.dart';

enum DiffType { equal, added, removed }

class DiffLine {
  const DiffLine({
    required this.type,
    this.leftLine,
    this.rightLine,
    required this.text,
    this.rightText,
  });
  final DiffType type;
  final int? leftLine;
  final int? rightLine;
  final String text;
  final String? rightText;
}

class DiffHunk {
  const DiffHunk(
    this.firstRow,
    this.lastRow,
    this.leftStart,
    this.leftEnd,
    this.rightStart,
    this.rightEnd,
  );
  final int firstRow;
  final int lastRow;
  final int leftStart;
  final int leftEnd;
  final int rightStart;
  final int rightEnd;
}

/// Patience anchors avoid a whole-document quadratic LCS matrix. Small
/// unmatched regions get exact LCS; large unanchored regions are replacement
/// blocks. Every output still reconstructs both original sequences exactly.
List<DiffLine> compareTextLines(
  List<String> left,
  List<String> right, {
  bool ignoreWhitespace = false,
  bool ignoreCase = false,
}) {
  String key(String value) {
    if (ignoreWhitespace) value = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return ignoreCase ? value.toLowerCase() : value;
  }

  final a = left.map(key).toList();
  final b = right.map(key).toList();
  final rows = <DiffLine>[];
  void equal(int i, int j) => rows.add(
    DiffLine(
      type: DiffType.equal,
      leftLine: i + 1,
      rightLine: j + 1,
      text: left[i],
      rightText: right[j],
    ),
  );
  void removed(int i) => rows.add(
    DiffLine(type: DiffType.removed, leftLine: i + 1, text: left[i]),
  );
  void added(int j) => rows.add(
    DiffLine(type: DiffType.added, rightLine: j + 1, text: right[j]),
  );

  void region(int startA, int endA, int startB, int endB, int depth) {
    while (startA < endA && startB < endB && a[startA] == b[startB]) {
      equal(startA++, startB++);
    }
    var suffix = 0;
    while (startA < endA - suffix &&
        startB < endB - suffix &&
        a[endA - suffix - 1] == b[endB - suffix - 1]) {
      suffix++;
    }
    final stopA = endA - suffix;
    final stopB = endB - suffix;
    if (startA == stopA || startB == stopB) {
      for (var i = startA; i < stopA; i++) {
        removed(i);
      }
      for (var j = startB; j < stopB; j++) {
        added(j);
      }
    } else {
      final positionsA = <String, int>{};
      final positionsB = <String, int>{};
      for (var i = startA; i < stopA; i++) {
        positionsA[a[i]] = positionsA.containsKey(a[i]) ? -1 : i;
      }
      for (var j = startB; j < stopB; j++) {
        positionsB[b[j]] = positionsB.containsKey(b[j]) ? -1 : j;
      }
      final candidates = <(int, int)>[];
      for (var i = startA; i < stopA; i++) {
        final j = positionsB[a[i]];
        if (positionsA[a[i]] == i && j != null && j >= 0) {
          candidates.add((i, j));
        }
      }
      final tails = <int>[];
      final previous = List<int>.filled(candidates.length, -1);
      for (var i = 0; i < candidates.length; i++) {
        var low = 0, high = tails.length;
        while (low < high) {
          final middle = (low + high) ~/ 2;
          if (candidates[tails[middle]].$2 < candidates[i].$2) {
            low = middle + 1;
          } else {
            high = middle;
          }
        }
        if (low > 0) previous[i] = tails[low - 1];
        if (low == tails.length) {
          tails.add(i);
        } else {
          tails[low] = i;
        }
      }
      if (tails.isNotEmpty && depth < 100) {
        final anchors = <(int, int)>[];
        for (var i = tails.last; i >= 0; i = previous[i]) {
          anchors.add(candidates[i]);
        }
        var x = startA, y = startB;
        for (final anchor in anchors.reversed) {
          region(x, anchor.$1, y, anchor.$2, depth + 1);
          equal(anchor.$1, anchor.$2);
          x = anchor.$1 + 1;
          y = anchor.$2 + 1;
        }
        region(x, stopA, y, stopB, depth + 1);
      } else if ((stopA - startA) * (stopB - startB) <= 250000) {
        final height = stopA - startA, width = stopB - startB;
        final table = List.generate(height + 1, (_) => Uint32List(width + 1));
        for (var i = height - 1; i >= 0; i--) {
          for (var j = width - 1; j >= 0; j--) {
            table[i][j] = a[startA + i] == b[startB + j]
                ? table[i + 1][j + 1] + 1
                : table[i + 1][j] > table[i][j + 1]
                ? table[i + 1][j]
                : table[i][j + 1];
          }
        }
        var i = 0, j = 0;
        while (i < height || j < width) {
          if (i < height && j < width && a[startA + i] == b[startB + j]) {
            equal(startA + i++, startB + j++);
          } else if (i < height &&
              (j == width || table[i + 1][j] >= table[i][j + 1])) {
            removed(startA + i++);
          } else {
            added(startB + j++);
          }
        }
      } else {
        for (var i = startA; i < stopA; i++) {
          removed(i);
        }
        for (var j = startB; j < stopB; j++) {
          added(j);
        }
      }
    }
    for (var offset = suffix; offset > 0; offset--) {
      equal(endA - offset, endB - offset);
    }
  }

  region(0, left.length, 0, right.length, 0);
  return rows;
}

List<DiffHunk> differenceHunks(List<DiffLine> rows) {
  final hunks = <DiffHunk>[];
  var left = 0, right = 0, row = 0;
  while (row < rows.length) {
    if (rows[row].type == DiffType.equal) {
      left++;
      right++;
      row++;
      continue;
    }
    final start = row, startLeft = left, startRight = right;
    while (row < rows.length && rows[row].type != DiffType.equal) {
      if (rows[row].type == DiffType.removed) left++;
      if (rows[row].type == DiffType.added) right++;
      row++;
    }
    hunks.add(DiffHunk(start, row, startLeft, left, startRight, right));
  }
  return hunks;
}

String mergeHunk(String left, String right, DiffHunk hunk) {
  final output = right.split('\n');
  output.replaceRange(
    hunk.rightStart,
    hunk.rightEnd,
    left.split('\n').sublist(hunk.leftStart, hunk.leftEnd),
  );
  return output.join('\n');
}

class BinaryComparison {
  const BinaryComparison(
    this.leftBytes,
    this.rightBytes,
    this.differingBytes,
    this.firstDifference,
  );
  final int leftBytes;
  final int rightBytes;
  final int differingBytes;
  final int? firstDifference;
  bool get equal => firstDifference == null;
}

Future<BinaryComparison> compareBinaryFiles(
  FileOperationBackend left,
  FileItem leftFile,
  FileOperationBackend right,
  FileItem rightFile, {
  bool Function()? isCancelled,
  void Function(int bytes)? onProgress,
}) async {
  void check() {
    if (isCancelled?.call() ?? false) {
      throw StateError('Comparison cancelled.');
    }
    if (!left.isCurrent || !right.isCurrent) {
      throw StateError('A comparison source changed.');
    }
  }

  bool same(FileItem? before, FileItem? after) =>
      before != null &&
      after != null &&
      !before.isFolder &&
      !after.isFolder &&
      before.uuid == after.uuid &&
      before.size == after.size &&
      before.updatedAt == after.updatedAt &&
      (before.metadata?['etag'] ?? before.metadata?['versionId']) ==
          (after.metadata?['etag'] ?? after.metadata?['versionId']);

  check();
  final beforeLeft = await left.stat(leftFile.path!);
  final beforeRight = await right.stat(rightFile.path!);
  if (!same(leftFile, beforeLeft) || !same(rightFile, beforeRight)) {
    throw StateError('A file changed before comparison. Reload both files.');
  }
  final result = await compareBinaryStreams(
    left.readFile(beforeLeft!),
    right.readFile(beforeRight!),
    isCancelled: () {
      check();
      return false;
    },
    onProgress: onProgress,
  );
  check();
  if (!same(beforeLeft, await left.stat(leftFile.path!)) ||
      !same(beforeRight, await right.stat(rightFile.path!)) ||
      (beforeLeft.size != null && result.leftBytes != beforeLeft.size) ||
      (beforeRight.size != null && result.rightBytes != beforeRight.size)) {
    throw StateError('A file changed during comparison. Compare again.');
  }
  return result;
}

Future<BinaryComparison> compareBinaryStreams(
  Stream<List<int>> left,
  Stream<List<int>> right, {
  bool Function()? isCancelled,
  void Function(int bytes)? onProgress,
}) async {
  final a = StreamIterator(left), b = StreamIterator(right);
  var chunkA = <int>[], chunkB = <int>[];
  var indexA = 0, indexB = 0, sizeA = 0, sizeB = 0, offset = 0, different = 0;
  int? first;
  var endedA = false, endedB = false;
  try {
    while (true) {
      if (isCancelled?.call() ?? false) {
        throw StateError('Comparison cancelled.');
      }
      while (indexA == chunkA.length && !endedA) {
        endedA = !await a.moveNext();
        chunkA = endedA ? [] : a.current;
        indexA = 0;
        sizeA += chunkA.length;
      }
      while (indexB == chunkB.length && !endedB) {
        endedB = !await b.moveNext();
        chunkB = endedB ? [] : b.current;
        indexB = 0;
        sizeB += chunkB.length;
      }
      if (endedA && endedB) break;
      final count = endedA
          ? chunkB.length - indexB
          : endedB
          ? chunkA.length - indexA
          : (chunkA.length - indexA < chunkB.length - indexB
                ? chunkA.length - indexA
                : chunkB.length - indexB);
      for (var i = 0; i < count; i++) {
        if (endedA || endedB || chunkA[indexA + i] != chunkB[indexB + i]) {
          first ??= offset + i;
          different++;
        }
      }
      if (!endedA) indexA += count;
      if (!endedB) indexB += count;
      offset += count;
      onProgress?.call(offset);
    }
    return BinaryComparison(sizeA, sizeB, different, first);
  } finally {
    await a.cancel();
    await b.cancel();
  }
}

/// The editable side carries the original encoding/newline format and a byte
/// fingerprint. Save refuses external modifications and uses staged backend IO.
class MergeDocumentSession {
  MergeDocumentSession._(
    this.source,
    this.file,
    this.document,
    this._fingerprint,
  );
  final FileOperationBackend source;
  final FileItem file;
  EditorDocument document;
  String _fingerprint;
  static const maxTextBytes = 8 * 1024 * 1024;

  static Future<Uint8List> readTextBytes(
    FileOperationBackend source,
    FileItem file,
  ) async {
    if (!source.isCurrent) throw StateError('The comparison source changed.');
    if ((file.size ?? 0) > maxTextBytes) {
      throw StateError('Use binary comparison for files larger than 8 MiB.');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in source.readFile(file)) {
      if (!source.isCurrent) throw StateError('The comparison source changed.');
      if (bytes.length + chunk.length > maxTextBytes) {
        throw StateError('Text merge exceeds 8 MiB. Use binary comparison.');
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  static Future<MergeDocumentSession> open(
    FileOperationBackend source,
    FileItem file,
  ) async {
    final bytes = await readTextBytes(source, file);
    return MergeDocumentSession._(
      source,
      file,
      EditorDocument.decode(bytes),
      sha256.convert(bytes).toString(),
    );
  }

  Future<void> save(String text) async {
    if (!source.isCurrent) throw StateError('The save source changed.');
    final current = await readTextBytes(source, file);
    if (sha256.convert(current).toString() != _fingerprint) {
      throw StateError(
        'The destination changed outside this comparison. Reload before saving.',
      );
    }
    final bytes = document.encode(text);
    if (bytes.length > maxTextBytes) {
      throw StateError('Merged text exceeds 8 MiB.');
    }
    await source.writeFile(
      file.path!,
      Stream.value(bytes),
      bytes.length,
      replace: true,
    );
    if (!source.isCurrent) throw StateError('Source changed while saving.');
    final verified = await readTextBytes(
      source,
      file.copyWith(size: bytes.length),
    );
    if (sha256.convert(verified).toString() !=
        sha256.convert(bytes).toString()) {
      throw StateError('The saved content could not be verified.');
    }
    _fingerprint = sha256.convert(bytes).toString();
    document = document.copyWith(text: text);
  }
}
