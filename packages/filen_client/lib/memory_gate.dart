/// Memory-gated concurrency for upload operations.
///
/// Limits the total bytes held in-flight during concurrent uploads
/// by checking available system memory and reserving slots.
/// Modeled after internxt-dart's MemoryGate.
import 'dart:async';
import 'dart:io';

/// File-level (batch) concurrency (Step 2). W = whole FILES transferred at once
/// in a batch directory upload/download — the bigger real-world win when syncing
/// many files. Each file ALSO runs Step 1 chunk concurrency internally, so the
/// dangerous quantity is the PRODUCT (W files × N chunks each). One shared
/// [ChunkSemaphore] caps that product across the whole batch: every chunk
/// transfer (sequential OR concurrent path) takes one permit before the network
/// call and releases it after, so total in-flight is bounded regardless of how
/// W and the per-file degree combine. (The per-chunk [MemoryGate] still bounds
/// bytes; this bounds the cross-file count.)
const int kDefaultFileConcurrency = 4;

/// Total chunks allowed in flight across ALL files × their chunks. At ~2 MB live
/// per chunk this is a ~16 MB ceiling — matters on mobile (CrispCloud).
const int kGlobalMaxInflightChunks = 8;

class MemoryGate {
  /// Maximum bytes allowed in-flight at once.
  final int maxBytes;

  /// Safety margin: keep at least this many bytes free.
  final int safetyMarginBytes;

  int _currentBytes = 0;
  final _waiters = <_MemoryWaiter>[];

  MemoryGate({
    this.maxBytes = 256 * 1024 * 1024, // 256 MB default
    this.safetyMarginBytes = 1024 * 1024 * 1024, // 1 GB safety margin
  });

  /// Current bytes reserved.
  int get currentBytes => _currentBytes;

  /// Whether there's capacity for [bytes] more.
  bool get hasCapacity => _currentBytes < maxBytes;

  /// Acquire [bytes] worth of memory. Waits if capacity is exceeded.
  Future<void> acquire(int bytes) async {
    // System-memory probing is opt-in: with [safetyMarginBytes] == 0 the gate
    // is a pure fixed byte budget. That matters for PER-CHUNK gating (Step 1),
    // where polling system memory on every chunk would spawn a `vm_stat`
    // subprocess per 1 MB and serialise dispatch — defeating the concurrency.
    if (safetyMarginBytes > 0) {
      final availableMemory = await _getAvailableMemory();
      if (availableMemory != null &&
          availableMemory < safetyMarginBytes + bytes) {
        // Wait for memory to free up
        final completer = Completer<void>();
        _waiters.add(_MemoryWaiter(bytes: bytes, completer: completer));
        return completer.future;
      }
    }

    if (_currentBytes + bytes > maxBytes) {
      final completer = Completer<void>();
      _waiters.add(_MemoryWaiter(bytes: bytes, completer: completer));
      return completer.future;
    }

    _currentBytes += bytes;
  }

  /// Release [bytes] of previously acquired memory.
  void release(int bytes) {
    _currentBytes -= bytes;
    if (_currentBytes < 0) _currentBytes = 0;
    _processWaiters();
  }

  void _processWaiters() {
    while (_waiters.isNotEmpty) {
      final waiter = _waiters.first;
      if (_currentBytes + waiter.bytes <= maxBytes) {
        _waiters.removeAt(0);
        _currentBytes += waiter.bytes;
        waiter.completer.complete();
      } else {
        break;
      }
    }
  }

  /// Get available system memory in bytes.
  /// Returns null if detection fails.
  static Future<int?> _getAvailableMemory() async {
    try {
      if (Platform.isLinux) {
        return _getLinuxAvailableMemory();
      } else if (Platform.isMacOS) {
        return _getMacOSAvailableMemory();
      }
    } catch (_) {}
    return null;
  }

  static int? _getLinuxAvailableMemory() {
    try {
      final meminfo = File('/proc/meminfo').readAsStringSync();
      // Look for MemAvailable line
      for (final line in meminfo.split('\n')) {
        if (line.startsWith('MemAvailable:')) {
          final parts = line.split(RegExp(r'\s+'));
          if (parts.length >= 2) {
            final kb = int.tryParse(parts[1]);
            if (kb != null) return kb * 1024;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<int?> _getMacOSAvailableMemory() async {
    try {
      final result = await Process.run('vm_stat', []);
      if (result.exitCode != 0) return null;

      final output = result.stdout.toString();
      int freePages = 0;

      for (final line in output.split('\n')) {
        if (line.contains('Pages free:') ||
            line.contains('Pages inactive:') ||
            line.contains('Pages purgeable:')) {
          final match =
              RegExp(r'(\d+)').firstMatch(line.substring(line.indexOf(':')));
          if (match != null) {
            freePages += int.tryParse(match.group(1)!) ?? 0;
          }
        }
      }

      // macOS page size is typically 16384 on ARM, 4096 on Intel
      final pageSize = Platform.version.contains('arm') ? 16384 : 4096;
      return freePages * pageSize;
    } catch (_) {}
    return null;
  }
}

class _MemoryWaiter {
  final int bytes;
  final Completer<void> completer;

  _MemoryWaiter({required this.bytes, required this.completer});
}

/// Run [action] over [items] with at most [concurrency] in flight at once.
/// Mirrors internxt-dart's runWithConcurrency: a [ChunkSemaphore] gates how
/// many item futures are active; the rest queue. This is the file-level (Step 2)
/// batch primitive — each whole-file transfer is one item, and the per-file
/// chunk concurrency (Step 1) composes underneath. Completes once every item
/// has finished. If [action] throws for an item, that error propagates out of
/// the returned future (callers that must not abort the batch should catch
/// inside [action] and return a sentinel instead).
Future<void> runWithConcurrency<T>(
  Iterable<T> items,
  int concurrency,
  Future<void> Function(T item) action,
) async {
  final sem = ChunkSemaphore(concurrency < 1 ? 1 : concurrency);
  final inflight = <Future<void>>[];
  for (final item in items) {
    await sem.acquire();
    inflight.add(() async {
      try {
        await action(item);
      } finally {
        sem.release();
      }
    }());
  }
  await Future.wait(inflight);
}

/// A counting semaphore that bounds the *number* of concurrent in-flight chunk
/// transfers. Paired with [MemoryGate] (which bounds the bytes in flight),
/// it caps chunk concurrency by both count and memory — the Step 1 model.
class ChunkSemaphore {
  int _permits;
  final _queue = <Completer<void>>[];

  ChunkSemaphore(this._permits) {
    if (_permits < 1) _permits = 1;
  }

  /// Permits currently available (for tests/diagnostics).
  int get availablePermits => _permits;

  /// Acquire one permit, waiting in FIFO order if none are free.
  Future<void> acquire() {
    if (_permits > 0) {
      _permits--;
      return Future.value();
    }
    final c = Completer<void>();
    _queue.add(c);
    return c.future;
  }

  /// Release one permit, handing it to the next waiter if any.
  void release() {
    if (_queue.isNotEmpty) {
      _queue.removeAt(0).complete();
    } else {
      _permits++;
    }
  }
}
