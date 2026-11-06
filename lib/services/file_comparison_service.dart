import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../models/file_item.dart';
import 'editor_document.dart';
import 'file_operation_service.dart';
import 'transfer_recovery_service.dart';

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

/// One contiguous run of unequal byte positions, including an unmatched tail.
class BinaryDifferenceRange {
  const BinaryDifferenceRange(this.index, this.start, this.end);
  final int index;
  final int start;
  final int end;
  int get length => end - start;
}

class BinaryComparison {
  const BinaryComparison(
    this.leftBytes,
    this.rightBytes,
    this.differingBytes,
    this.firstDifference, {
    this.rangeCount = 0,
    this.ranges = const [],
  });
  final int leftBytes;
  final int rightBytes;
  final int differingBytes;
  final int? firstDifference;
  final int rangeCount;

  /// A bounded sparse index, including the first and last difference. Missing
  /// ranges are resolved from the nearest preceding checkpoint on demand.
  final List<BinaryDifferenceRange> ranges;
  bool get equal => firstDifference == null;
}

Future<BinaryComparison> compareBinaryFiles(
  FileOperationBackend left,
  FileItem leftFile,
  FileOperationBackend right,
  FileItem rightFile, {
  bool Function()? isCancelled,
  void Function(int bytes)? onProgress,
  int maxIndexedRanges = 4096,
}) async {
  void check() {
    if (isCancelled?.call() ?? false) throw StateError('Comparison cancelled.');
    if (!left.isCurrent || !right.isCurrent) {
      throw StateError('A comparison source changed.');
    }
  }

  check();
  final beforeLeft = await left.stat(leftFile.path!);
  final beforeRight = await right.stat(rightFile.path!);
  if (beforeLeft == null ||
      beforeRight == null ||
      !sameTransferVersion(leftFile, beforeLeft) ||
      !sameTransferVersion(rightFile, beforeRight) ||
      beforeLeft.isFolder ||
      beforeRight.isFolder) {
    throw StateError('A file changed before comparison. Reload both files.');
  }
  final result = await compareBinaryStreams(
    left.readFile(beforeLeft),
    right.readFile(beforeRight),
    isCancelled: () {
      check();
      return false;
    },
    onProgress: onProgress,
    maxIndexedRanges: maxIndexedRanges,
  );
  check();
  final afterLeft = await left.stat(leftFile.path!);
  final afterRight = await right.stat(rightFile.path!);
  if (afterLeft == null ||
      afterRight == null ||
      !sameTransferVersion(beforeLeft, afterLeft) ||
      !sameTransferVersion(beforeRight, afterRight) ||
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
  int maxIndexedRanges = 4096,
}) => _scanBinaryStreams(
  left,
  right,
  isCancelled: isCancelled,
  onProgress: onProgress,
  maxIndexedRanges: maxIndexedRanges,
);

Future<BinaryComparison> _scanBinaryStreams(
  Stream<List<int>> left,
  Stream<List<int>> right, {
  bool Function()? isCancelled,
  void Function(int bytes)? onProgress,
  int maxIndexedRanges = 4096,
  int startOffset = 0,
  int startRangeIndex = 0,
  int? stopAfterRange,
}) async {
  if (maxIndexedRanges < 2) {
    throw ArgumentError.value(maxIndexedRanges, 'maxIndexedRanges');
  }
  final control = FileOperationControl();
  Object? halted;
  void check() {
    if (halted != null) throw halted!;
    if (isCancelled?.call() ?? false) throw StateError('Comparison cancelled.');
  }

  final watcher = isCancelled == null
      ? null
      : Timer.periodic(const Duration(milliseconds: 50), (_) {
          try {
            check();
          } catch (error) {
            halted = error;
            control.cancel();
          }
        });
  final a = StreamIterator(control.bind(left)),
      b = StreamIterator(control.bind(right));
  var chunkA = <int>[], chunkB = <int>[];
  var indexA = 0, indexB = 0, sizeA = 0, sizeB = 0;
  var offset = startOffset, different = 0, rangeCount = 0, stride = 1;
  var lastYield = offset;
  int? first, rangeStart;
  var endedA = false, endedB = false, stop = false;
  final ranges = <BinaryDifferenceRange>[];
  BinaryDifferenceRange? lastRange;
  void finishRange(int end) {
    if (rangeStart == null) return;
    final range = BinaryDifferenceRange(
      startRangeIndex + rangeCount,
      rangeStart!,
      end,
    );
    rangeCount++;
    rangeStart = null;
    lastRange = range;
    if (range.index % stride == 0) ranges.add(range);
    if (ranges.length > maxIndexedRanges) {
      stride *= 2;
      ranges.removeWhere((item) => item.index % stride != 0);
    }
    if (range.index == stopAfterRange) stop = true;
  }

  try {
    while (!stop) {
      check();
      while (indexA == chunkA.length && !endedA) {
        endedA = !await a.moveNext();
        chunkA = endedA ? [] : a.current;
        indexA = 0;
        sizeA += chunkA.length;
        check();
      }
      while (indexB == chunkB.length && !endedB) {
        endedB = !await b.moveNext();
        chunkB = endedB ? [] : b.current;
        indexB = 0;
        sizeB += chunkB.length;
        check();
      }
      if (endedA && endedB) break;
      final available = endedA
          ? chunkB.length - indexB
          : endedB
          ? chunkA.length - indexA
          : (chunkA.length - indexA < chunkB.length - indexB
                ? chunkA.length - indexA
                : chunkB.length - indexB);
      final count = available > 64 * 1024 ? 64 * 1024 : available;
      var processed = 0;
      for (var i = 0; i < count; i++) {
        if (endedA || endedB || chunkA[indexA + i] != chunkB[indexB + i]) {
          first ??= offset + i;
          rangeStart ??= offset + i;
          different++;
        } else {
          finishRange(offset + i);
          if (stop) break;
        }
        processed++;
      }
      if (!endedA) indexA += processed;
      if (!endedB) indexB += processed;
      offset += processed;
      onProgress?.call(offset);
      if (offset - lastYield >= 1024 * 1024) {
        await Future<void>.delayed(Duration.zero);
        lastYield = offset;
      }
    }
    finishRange(offset);
    check();
    if (lastRange != null &&
        (ranges.isEmpty || ranges.last.index != lastRange!.index)) {
      ranges.add(lastRange!);
    }
    return BinaryComparison(
      sizeA,
      sizeB,
      different,
      first,
      rangeCount: rangeCount,
      ranges: List.unmodifiable(ranges),
    );
  } on FileOperationCancelled {
    check();
    throw StateError('Comparison cancelled.');
  } finally {
    watcher?.cancel();
    // Completed cursors already released their subscriptions. For an early
    // stop, drain the bound cursors; FileOperationControl requests upstream
    // cleanup without waiting indefinitely for a stalled provider.
    await Future.wait([
      if (!endedA) a.cancel().catchError((Object _) {}),
      if (!endedB) b.cancel().catchError((Object _) {}),
    ]);
  }
}

class BinaryComparisonWindow {
  const BinaryComparisonWindow(this.offset, this.left, this.right);
  final int offset;
  final Uint8List left;
  final Uint8List right;
  int get length => left.length > right.length ? left.length : right.length;
}

/// Navigates every difference in arbitrarily large files with a bounded index
/// and small hex windows. Non-range providers stream to the requested offset.
class BinaryComparisonSession {
  BinaryComparisonSession._(
    this.left,
    this.leftFile,
    this.right,
    this.rightFile,
    this.result,
  );
  final FileOperationBackend left, right;
  final FileItem leftFile, rightFile;
  final BinaryComparison result;
  final _recent = <int, BinaryDifferenceRange>{};
  int get totalBytes => result.leftBytes > result.rightBytes
      ? result.leftBytes
      : result.rightBytes;

  static Future<BinaryComparisonSession> open(
    FileOperationBackend left,
    FileItem leftFile,
    FileOperationBackend right,
    FileItem rightFile, {
    bool Function()? isCancelled,
    void Function(int bytes)? onProgress,
    int maxIndexedRanges = 4096,
  }) async {
    final a = await left.stat(leftFile.path!);
    final b = await right.stat(rightFile.path!);
    if (a == null ||
        b == null ||
        !sameTransferVersion(leftFile, a) ||
        !sameTransferVersion(rightFile, b)) {
      throw StateError('A file changed before comparison. Reload both files.');
    }
    final result = await compareBinaryFiles(
      left,
      a,
      right,
      b,
      isCancelled: isCancelled,
      onProgress: onProgress,
      maxIndexedRanges: maxIndexedRanges,
    );
    return BinaryComparisonSession._(left, a, right, b, result);
  }

  void _check(bool Function()? cancelled) {
    if (cancelled?.call() ?? false) throw StateError('Comparison cancelled.');
    if (!left.isCurrent || !right.isCurrent) {
      throw StateError('A comparison source changed.');
    }
  }

  Future<void> _validate(bool Function()? cancelled) async {
    _check(cancelled);
    final a = await left.stat(leftFile.path!);
    final b = await right.stat(rightFile.path!);
    if (a == null ||
        b == null ||
        !sameTransferVersion(leftFile, a) ||
        !sameTransferVersion(rightFile, b)) {
      throw StateError(
        'A compared file changed. Compare again before navigating.',
      );
    }
    _check(cancelled);
  }

  Stream<List<int>> _suffix(
    FileOperationBackend backend,
    FileItem file,
    int size,
    int offset,
  ) => offset >= size ? const Stream.empty() : backend.readRange(file, offset);

  Future<BinaryDifferenceRange> difference(
    int index, {
    bool Function()? isCancelled,
  }) async {
    if (index < 0 || index >= result.rangeCount) {
      throw RangeError.index(
        index,
        result.ranges,
        'difference',
        null,
        result.rangeCount,
      );
    }
    await _validate(isCancelled);
    BinaryDifferenceRange? preceding;
    for (final range in [...result.ranges, ..._recent.values]) {
      if (range.index == index) return range;
      if (range.index < index &&
          (preceding == null || range.index > preceding.index)) {
        preceding = range;
      }
    }
    final offset = preceding?.end ?? 0;
    final scan = await _scanBinaryStreams(
      _suffix(left, leftFile, result.leftBytes, offset),
      _suffix(right, rightFile, result.rightBytes, offset),
      startOffset: offset,
      startRangeIndex: (preceding?.index ?? -1) + 1,
      stopAfterRange: index,
      maxIndexedRanges: 2,
      isCancelled: () {
        _check(isCancelled);
        return false;
      },
    );
    await _validate(isCancelled);
    if (scan.ranges.isEmpty || scan.ranges.last.index != index) {
      throw StateError('The compared contents changed. Compare again.');
    }
    final found = scan.ranges.last;
    _recent[index] = found;
    if (_recent.length > 128) _recent.remove(_recent.keys.first);
    return found;
  }

  Future<BinaryComparisonWindow> window(
    int offset, {
    int length = 1024,
    bool Function()? isCancelled,
  }) async {
    if (offset < 0 || offset > totalBytes) {
      throw RangeError.range(offset, 0, totalBytes, 'offset');
    }
    if (length < 1 || length > 64 * 1024) {
      throw RangeError.range(length, 1, 64 * 1024, 'length');
    }
    await _validate(isCancelled);
    final control = FileOperationControl();
    Object? halted;
    final watcher = Timer.periodic(const Duration(milliseconds: 50), (_) {
      try {
        _check(isCancelled);
      } catch (error) {
        halted = error;
        control.cancel();
      }
    });
    Future<Uint8List> read(
      FileOperationBackend backend,
      FileItem file,
      int size,
    ) async {
      final expected = (size - offset).clamp(0, length);
      final bytes = BytesBuilder(copy: false);
      if (expected == 0) return bytes.takeBytes();
      final cursor = StreamIterator(
        control.bind(_suffix(backend, file, size, offset)),
      );
      try {
        while (bytes.length < expected && await cursor.moveNext()) {
          _check(isCancelled);
          final chunk = cursor.current;
          final remaining = expected - bytes.length;
          bytes.add(
            chunk.length > remaining ? chunk.sublist(0, remaining) : chunk,
          );
        }
      } finally {
        unawaited(cursor.cancel().catchError((Object _) {}));
      }
      if (bytes.length != expected) {
        throw StateError('The compared file became shorter.');
      }
      return bytes.takeBytes();
    }

    try {
      final a = await read(left, leftFile, result.leftBytes);
      final b = await read(right, rightFile, result.rightBytes);
      await _validate(isCancelled);
      return BinaryComparisonWindow(offset, a, b);
    } on FileOperationCancelled {
      if (halted != null) throw halted!;
      throw StateError('Comparison cancelled.');
    } finally {
      watcher.cancel();
    }
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
  FileItem file;
  EditorDocument document;
  String _fingerprint;
  static const maxTextBytes = 8 * 1024 * 1024;

  static Future<Uint8List> readTextBytes(
    FileOperationBackend source,
    FileItem file, {
    bool Function()? isCancelled,
  }) async {
    void check() {
      if (!source.isCurrent) throw StateError('The comparison source changed.');
      if (isCancelled?.call() ?? false) {
        throw StateError('Comparison cancelled.');
      }
    }

    check();
    if ((file.size ?? 0) > maxTextBytes) {
      throw StateError('Use binary comparison for files larger than 8 MiB.');
    }
    final before = await source.stat(file.path!);
    if (before == null ||
        !sameTransferVersion(file, before) ||
        before.isFolder) {
      throw StateError(
        'The compared file changed. Reload it before continuing.',
      );
    }
    final bytes = BytesBuilder(copy: false);
    final control = FileOperationControl();
    Object? halted;
    final watcher = Timer.periodic(const Duration(milliseconds: 50), (_) {
      try {
        check();
      } catch (error) {
        halted = error;
        control.cancel();
      }
    });
    try {
      await for (final chunk in control.bind(source.readFile(before))) {
        check();
        if (bytes.length + chunk.length > maxTextBytes) {
          throw StateError('Text merge exceeds 8 MiB. Use binary comparison.');
        }
        bytes.add(chunk);
      }
      check();
      final after = await source.stat(file.path!);
      if (after == null ||
          !sameTransferVersion(before, after) ||
          (before.size != null && bytes.length != before.size)) {
        throw StateError(
          'The compared file changed or could not be read completely.',
        );
      }
      return bytes.takeBytes();
    } on FileOperationCancelled {
      if (halted != null) throw halted!;
      throw StateError('Comparison cancelled.');
    } finally {
      watcher.cancel();
    }
  }

  static Future<MergeDocumentSession> open(
    FileOperationBackend source,
    FileItem file, {
    EditorEncoding? encodingOverride,
    bool Function()? isCancelled,
  }) async {
    final bytes = await readTextBytes(source, file, isCancelled: isCancelled);
    final snapshot = await source.stat(file.path!);
    if (snapshot == null || !sameTransferVersion(file, snapshot)) {
      throw StateError('The compared file changed while opening it.');
    }
    return MergeDocumentSession._(
      source,
      snapshot,
      EditorDocument.decode(bytes, encodingOverride: encodingOverride),
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
    if (source.supportsStagedVerification) {
      await source.writePreparedFile(
        file.path!,
        Stream.value(bytes),
        bytes.length,
        replace: true,
        verifyStaged: (staged) async {
          final prepared = await readTextBytes(source, staged);
          if (sha256.convert(prepared) != sha256.convert(bytes)) {
            throw StateError(
              'The prepared merge could not be verified. The destination was not replaced.',
            );
          }
          final latest = await readTextBytes(source, file);
          if (sha256.convert(latest).toString() != _fingerprint) {
            throw StateError(
              'The destination changed while saving. It was not replaced.',
            );
          }
        },
      );
    } else {
      await source.writeFile(
        file.path!,
        Stream.value(bytes),
        bytes.length,
        replace: true,
      );
    }
    if (!source.isCurrent) throw StateError('Source changed while saving.');
    final written = await source.stat(file.path!);
    if (written == null) throw StateError('The saved file is unavailable.');
    final verified = await readTextBytes(source, written);
    if (sha256.convert(verified).toString() !=
        sha256.convert(bytes).toString()) {
      throw StateError('The saved content could not be verified.');
    }
    _fingerprint = sha256.convert(bytes).toString();
    file = written;
    document = document.copyWith(text: text);
  }
}
