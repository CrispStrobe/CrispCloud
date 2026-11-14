import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../models/file_item.dart';
import 'binary_comparison_source.dart';
import 'editor_document.dart';
import 'file_operation_service.dart';
import 'transfer_recovery_service.dart';

export 'binary_comparison_source.dart'
    show
        BinaryComparisonLimits,
        BinaryComparisonLimitExceeded,
        BinaryComparisonSourceChanged,
        BinaryComparisonCancelled;

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
  BinaryComparisonLimits limits = const BinaryComparisonLimits(),
}) async {
  final session = await BinaryComparisonSession.open(
    left,
    leftFile,
    right,
    rightFile,
    isCancelled: isCancelled,
    onProgress: onProgress,
    maxIndexedRanges: maxIndexedRanges,
    limits: limits,
  );
  try {
    return session.result;
  } finally {
    await session.close();
  }
}

/// Compare same-offset bytes with bounded input, index, chunk work and time.
///
/// Optional expected lengths are enforced exactly, including extra bytes after
/// the declared end. This stream-only API does not establish source identity;
/// file comparisons use [BinaryComparisonSession]'s verified snapshots.
Future<BinaryComparison> compareBinaryStreams(
  Stream<List<int>> left,
  Stream<List<int>> right, {
  bool Function()? isCancelled,
  void Function(int bytes)? onProgress,
  int maxIndexedRanges = 4096,
  BinaryComparisonLimits limits = const BinaryComparisonLimits(),
  int? expectedLeftBytes,
  int? expectedRightBytes,
}) => _scanBinaryStreams(
  left,
  right,
  isCancelled: isCancelled,
  onProgress: onProgress,
  maxIndexedRanges: maxIndexedRanges,
  limits: limits,
  expectedLeftBytes: expectedLeftBytes,
  expectedRightBytes: expectedRightBytes,
);

void _validateBinaryIndexLimit(int value) {
  if (value < 2 || value > 4096) {
    throw RangeError.range(value, 2, 4096, 'maxIndexedRanges');
  }
}

/// A cursor retains only the provider's current chunk and validates each input
/// independently. Empty chunks consume work but never reset inactivity time.
class _BinaryScanInput {
  _BinaryScanInput(
    Stream<List<int>> stream,
    FileOperationControl control, {
    required this.name,
    required this.limits,
    required this.byteLimit,
    required this.expectedBytes,
    required this.check,
    required this.activity,
    required this.yieldAfterChunk,
  }) : _stream = stream,
       _control = control;

  final Stream<List<int>> _stream;
  final FileOperationControl _control;
  StreamIterator<List<int>>? _cursor;
  StreamIterator<List<int>> get cursor =>
      _cursor ??= StreamIterator(_control.bind(_stream));
  final String name;
  final BinaryComparisonLimits limits;
  final int byteLimit;
  final int? expectedBytes;
  final void Function() check;
  final void Function() activity;
  final Future<void> Function() yieldAfterChunk;
  List<int> chunk = const [];
  int index = 0, size = 0, chunks = 0, emptyChunks = 0;
  bool ended = false;

  Future<void> fill() async {
    while (index == chunk.length && !ended) {
      check();
      final available = await cursor.moveNext();
      check();
      if (!available) {
        ended = true;
        chunk = const [];
        index = 0;
        if (expectedBytes != null && size != expectedBytes) {
          throw BinaryComparisonSourceChanged(
            'The $name comparison input ended before its declared length.',
          );
        }
        return;
      }
      final next = cursor.current;
      if (++chunks > limits.maxChunks) {
        throw BinaryComparisonLimitExceeded(
          'The $name comparison input exceeded the chunk limit.',
        );
      }
      if (next.isEmpty && ++emptyChunks > limits.maxEmptyChunks) {
        throw BinaryComparisonLimitExceeded(
          'The $name comparison input exceeded the empty-chunk limit.',
        );
      }
      if (next.length > byteLimit - size) {
        throw BinaryComparisonLimitExceeded(
          'The $name comparison input exceeded the byte limit.',
        );
      }
      if (expectedBytes != null && next.length > expectedBytes! - size) {
        throw BinaryComparisonSourceChanged(
          'The $name comparison input exceeded its declared length.',
        );
      }
      size += next.length;
      chunk = next;
      index = 0;
      if (next.isNotEmpty) activity();
      await yieldAfterChunk();
    }
  }

  Future<void> close() async {
    if (!ended && _cursor != null) {
      await _cursor!.cancel().catchError((Object _) {});
    }
  }
}

Future<BinaryComparison> _scanBinaryStreams(
  Stream<List<int>> left,
  Stream<List<int>> right, {
  bool Function()? isCancelled,
  void Function(int bytes)? onProgress,
  int maxIndexedRanges = 4096,
  BinaryComparisonLimits limits = const BinaryComparisonLimits(),
  int? expectedLeftBytes,
  int? expectedRightBytes,
  int startOffset = 0,
  int startRangeIndex = 0,
  int? stopAfterRange,
}) async {
  limits.validate();
  _validateBinaryIndexLimit(maxIndexedRanges);
  if (startOffset < 0 || startOffset > limits.maxBytes) {
    throw RangeError.range(startOffset, 0, limits.maxBytes, 'startOffset');
  }
  if (startRangeIndex < 0 ||
      (stopAfterRange != null && stopAfterRange < startRangeIndex)) {
    throw ArgumentError('Invalid binary comparison range indices.');
  }
  final byteLimit = limits.maxBytes - startOffset;
  for (final expected in [expectedLeftBytes, expectedRightBytes]) {
    if (expected != null && (expected < 0 || expected > byteLimit)) {
      throw RangeError.range(expected, 0, byteLimit, 'expectedBytes');
    }
  }
  final control = FileOperationControl();
  final clock = Stopwatch()..start();
  var lastActivity = 0, chunksSinceYield = 0;
  Object? halted;
  void activity() => lastActivity = clock.elapsedMicroseconds;
  void check() {
    if (halted != null) throw halted!;
    if (isCancelled?.call() ?? false) throw BinaryComparisonCancelled();
    if (clock.elapsedMicroseconds >= limits.overallTimeout.inMicroseconds) {
      throw TimeoutException(
        'Binary comparison exceeded the overall time limit.',
        limits.overallTimeout,
      );
    }
    if (clock.elapsedMicroseconds - lastActivity >=
        limits.inactivityTimeout.inMicroseconds) {
      throw TimeoutException(
        'Binary comparison input stopped making progress.',
        limits.inactivityTimeout,
      );
    }
  }

  Future<void> yieldAfterChunk() async {
    if (++chunksSinceYield >= 64) {
      await Future<void>.delayed(Duration.zero);
      chunksSinceYield = 0;
      check();
    }
  }

  check();
  final watcher = Timer.periodic(const Duration(milliseconds: 50), (_) {
    try {
      check();
    } catch (error) {
      halted = error;
      control.cancel();
    }
  });
  final a = _BinaryScanInput(
    left,
    control,
    name: 'left',
    limits: limits,
    byteLimit: byteLimit,
    expectedBytes: expectedLeftBytes,
    check: check,
    activity: activity,
    yieldAfterChunk: yieldAfterChunk,
  );
  final b = _BinaryScanInput(
    right,
    control,
    name: 'right',
    limits: limits,
    byteLimit: byteLimit,
    expectedBytes: expectedRightBytes,
    check: check,
    activity: activity,
    yieldAfterChunk: yieldAfterChunk,
  );
  var offset = startOffset, different = 0, rangeCount = 0, stride = 1;
  var lastYield = offset;
  int? first, rangeStart;
  var stop = false;
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
      await a.fill();
      await b.fill();
      if (a.ended && b.ended) break;
      final available = a.ended
          ? b.chunk.length - b.index
          : b.ended
          ? a.chunk.length - a.index
          : (a.chunk.length - a.index < b.chunk.length - b.index
                ? a.chunk.length - a.index
                : b.chunk.length - b.index);
      final count = available > 64 * 1024 ? 64 * 1024 : available;
      var processed = 0;
      for (var i = 0; i < count; i++) {
        final leftByte = a.ended ? null : a.chunk[a.index + i];
        final rightByte = b.ended ? null : b.chunk[b.index + i];
        if ((leftByte != null && (leftByte < 0 || leftByte > 255)) ||
            (rightByte != null && (rightByte < 0 || rightByte > 255))) {
          throw const FormatException(
            'Binary comparison input contains a non-byte value.',
          );
        }
        if (a.ended || b.ended || leftByte != rightByte) {
          first ??= offset + i;
          rangeStart ??= offset + i;
          different++;
        } else {
          finishRange(offset + i);
          if (stop) break;
        }
        processed++;
      }
      if (!a.ended) a.index += processed;
      if (!b.ended) b.index += processed;
      offset += processed;
      if (processed > 0) activity();
      onProgress?.call(offset);
      if (offset - lastYield >= 1024 * 1024) {
        await Future<void>.delayed(Duration.zero);
        lastYield = offset;
        chunksSinceYield = 0;
      }
    }
    finishRange(offset);
    check();
    if (lastRange != null &&
        (ranges.isEmpty || ranges.last.index != lastRange!.index)) {
      ranges.add(lastRange!);
    }
    return BinaryComparison(
      a.size,
      b.size,
      different,
      first,
      rangeCount: rangeCount,
      ranges: List.unmodifiable(ranges),
    );
  } on FileOperationCancelled {
    check();
    throw BinaryComparisonCancelled();
  } finally {
    watcher.cancel();
    clock.stop();
    // The bound cursors request upstream cleanup without waiting indefinitely
    // for a stalled provider's cancellation acknowledgement.
    await Future.wait([a.close(), b.close()]);
  }
}

class BinaryComparisonWindow {
  const BinaryComparisonWindow(this.offset, this.left, this.right);
  final int offset;
  final Uint8List left;
  final Uint8List right;
  int get length => left.length > right.length ? left.length : right.length;
}

/// A bounded comparison of two verified, owned snapshots. Every range and hex
/// window refers to those same captured bytes, including on unversioned storage.
/// Original source/account metadata remains validated before and after reads.
class BinaryComparisonSession {
  BinaryComparisonSession._(
    this._leftSnapshot,
    this._rightSnapshot,
    this.result,
    this.limits,
    this._leftIdentity,
    this._rightIdentity,
  );
  final BinaryComparisonSnapshot _leftSnapshot, _rightSnapshot;
  FileOperationBackend get left => _leftSnapshot.backend;
  FileOperationBackend get right => _rightSnapshot.backend;
  FileItem get leftFile => _leftSnapshot.file;
  FileItem get rightFile => _rightSnapshot.file;
  String get leftSha256 => _leftSnapshot.sha256Digest;
  String get rightSha256 => _rightSnapshot.sha256Digest;
  final BinaryComparisonLimits limits;
  final Object _leftIdentity, _rightIdentity;
  final BinaryComparison result;
  final _recent = <int, BinaryDifferenceRange>{};
  bool _closed = false;
  Future<void>? _closing;
  bool get isClosed => _closed;
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
    void Function(int side, int bytes)? onCaptureProgress,
    int maxIndexedRanges = 4096,
    BinaryComparisonLimits limits = const BinaryComparisonLimits(),
  }) async {
    limits.validate();
    _validateBinaryIndexLimit(maxIndexedRanges);
    final leftIdentity = left.identity, rightIdentity = right.identity;
    final opening = Stopwatch()..start();
    bool unavailable() {
      if (!left.isCurrent ||
          !right.isCurrent ||
          left.identity != leftIdentity ||
          right.identity != rightIdentity) {
        throw BinaryComparisonSourceChanged('A comparison source changed.');
      }
      if (isCancelled?.call() ?? false) return true;
      if (opening.elapsed >= limits.overallTimeout) {
        throw TimeoutException(
          'Capturing and comparing the inputs exceeded the overall time limit.',
          limits.overallTimeout,
        );
      }
      return false;
    }

    BinaryComparisonSnapshot? a, b;
    try {
      a = await BinaryComparisonSnapshot.capture(
        left,
        leftFile,
        limits: limits,
        isCancelled: unavailable,
        onProgress: onCaptureProgress == null
            ? null
            : (bytes) => onCaptureProgress(0, bytes),
      );
      b = await BinaryComparisonSnapshot.capture(
        right,
        rightFile,
        limits: limits,
        isCancelled: unavailable,
        onProgress: onCaptureProgress == null
            ? null
            : (bytes) => onCaptureProgress(1, bytes),
      );
      await a.validate(isCancelled: unavailable);
      final result = await compareBinaryStreams(
        a.readRange(0, isCancelled: unavailable),
        b.readRange(0, isCancelled: unavailable),
        isCancelled: unavailable,
        onProgress: onProgress,
        maxIndexedRanges: maxIndexedRanges,
        limits: limits,
        expectedLeftBytes: a.length,
        expectedRightBytes: b.length,
      );
      await a.validate(isCancelled: unavailable);
      await b.validate(isCancelled: unavailable);
      return BinaryComparisonSession._(
        a,
        b,
        result,
        limits,
        leftIdentity,
        rightIdentity,
      );
    } catch (_) {
      await Future.wait([
        if (a != null) a.close().catchError((Object _) {}),
        if (b != null) b.close().catchError((Object _) {}),
      ]);
      rethrow;
    } finally {
      opening.stop();
    }
  }

  void _check(bool Function()? cancelled) {
    if (_closed) throw StateError('The binary comparison is closed.');
    if (cancelled?.call() ?? false) throw BinaryComparisonCancelled();
    if (!left.isCurrent ||
        !right.isCurrent ||
        left.identity != _leftIdentity ||
        right.identity != _rightIdentity) {
      throw BinaryComparisonSourceChanged('A comparison source changed.');
    }
  }

  bool _cancelled(bool Function()? cancelled) {
    _check(cancelled);
    return false;
  }

  Future<void> _validate(bool Function()? cancelled) async {
    _check(cancelled);
    await _leftSnapshot.validate(isCancelled: () => _cancelled(cancelled));
    await _rightSnapshot.validate(isCancelled: () => _cancelled(cancelled));
    _check(cancelled);
  }

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
    try {
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
        _leftSnapshot.readRange(
          offset.clamp(0, result.leftBytes),
          isCancelled: () => _cancelled(isCancelled),
        ),
        _rightSnapshot.readRange(
          offset.clamp(0, result.rightBytes),
          isCancelled: () => _cancelled(isCancelled),
        ),
        startOffset: offset,
        startRangeIndex: (preceding?.index ?? -1) + 1,
        stopAfterRange: index,
        maxIndexedRanges: 2,
        limits: limits,
        expectedLeftBytes: (result.leftBytes - offset).clamp(
          0,
          result.leftBytes,
        ),
        expectedRightBytes: (result.rightBytes - offset).clamp(
          0,
          result.rightBytes,
        ),
        isCancelled: () => _cancelled(isCancelled),
      );
      await _validate(isCancelled);
      if (scan.ranges.isEmpty || scan.ranges.last.index != index) {
        throw BinaryComparisonSourceChanged(
          'The compared snapshot could not be read completely.',
        );
      }
      final found = scan.ranges.last;
      _recent[index] = found;
      if (_recent.length > 128) _recent.remove(_recent.keys.first);
      return found;
    } catch (_) {
      await close().catchError((Object _) {});
      rethrow;
    }
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
    try {
      await _validate(isCancelled);
      final a = await _leftSnapshot.read(
        offset.clamp(0, result.leftBytes),
        (result.leftBytes - offset).clamp(0, length),
        isCancelled: () => _cancelled(isCancelled),
      );
      final b = await _rightSnapshot.read(
        offset.clamp(0, result.rightBytes),
        (result.rightBytes - offset).clamp(0, length),
        isCancelled: () => _cancelled(isCancelled),
      );
      await _validate(isCancelled);
      return BinaryComparisonWindow(offset, a, b);
    } catch (_) {
      await close().catchError((Object _) {});
      rethrow;
    }
  }

  /// Invalidate in-flight operations immediately and release both owned inputs.
  Future<void> close() {
    if (_closing != null) return _closing!;
    _closed = true;
    _recent.clear();
    return _closing = Future.wait([
      _leftSnapshot.close(),
      _rightSnapshot.close(),
    ]).then((_) {});
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
