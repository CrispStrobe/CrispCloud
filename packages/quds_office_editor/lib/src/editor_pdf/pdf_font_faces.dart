import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Loads embedded PDF `/FontFile2` faces so paint matches the file.
///
/// Once a byte buffer resolves to a font, it identifies that immutable
/// snapshot. Pass a new buffer to register changed contents. This ownership rule
/// keeps painting/readiness checks constant-time without repeatedly hashing an
/// entire font for every glyph. Independent buffers with identical contents
/// share a registration while their content entry remains cached.
abstract final class PdfFontFaces {
  static const int _maxContentEntries = 128;
  static const int _maxContentBytes = 16 * 1024 * 1024;
  static final Map<_FontContent, _FontRecord> _contents = {};
  static final Set<_FontLoad> _pending = {};
  static Expando<_FontLoad> _buffers = Expando<_FontLoad>('PDF font buffers');
  static int _retainedBytes = 0;
  static int _nextFamily = 0;

  /// Test-only replacement for the native loader; snapshots are read-only.
  @visibleForTesting
  static Future<void> Function(String family, Uint8List bytes)? debugLoadFont;

  /// Clears Dart bookkeeping between tests, never reusing native family names.
  @visibleForTesting
  static void debugReset() {
    assert(_pending.isEmpty, 'Complete pending font loads before resetting.');
    _contents.clear();
    _buffers = Expando<_FontLoad>('PDF font buffers');
    _retainedBytes = 0;
    debugLoadFont = null;
  }

  /// Host family for a PDF BaseFont when no glyf file is present.
  static String hostFamily(String baseFont) {
    final String n = baseFont.toLowerCase().replaceAll(RegExp(r'[\s\-_]'), '');
    if (n.contains('cairo')) {
      return 'Cairo';
    }
    if (n.contains('tajawal')) {
      return 'Tajawal';
    }
    if (n.contains('naskh') ||
        n.contains('notoarabic') ||
        n.contains('notosansarabic')) {
      return 'Noto Naskh Arabic';
    }
    if (n.contains('times') ||
        n.contains('georgia') ||
        n.contains('garamond') ||
        n.contains('liberationserif')) {
      return 'Times New Roman';
    }
    if (n.contains('courier') ||
        n.contains('mono') ||
        n.contains('liberationmono')) {
      return 'Courier New';
    }
    if (n.contains('helvetica') ||
        n.contains('arial') ||
        n.contains('liberationsans') ||
        n.contains('calibri') ||
        n.contains('carlito') ||
        n.contains('roboto') ||
        n.contains('myriad') ||
        n.contains('centurygothic') ||
        n.contains('gothic') ||
        n.contains('verdana') ||
        n.contains('tahoma') ||
        n.contains('segoe')) {
      return 'Liberation Sans';
    }
    return 'Liberation Sans';
  }

  /// Registered family for [bytes], or the host fallback while loading.
  ///
  /// Prefer the embedded face whenever possible: PDF glyph advances are
  /// measured for that file, so a host substitute (e.g. Liberation for Roboto)
  /// overlaps or gaps at the recorded positions.
  static String familyFor(Uint8List? bytes, String baseFont) {
    final String host = hostFamily(baseFont);
    if (bytes == null || bytes.length < 16) {
      return host;
    }
    final load = _find(bytes);
    return load?.state == _FontState.ready ? load!.family : host;
  }

  /// Whether [family] is a loaded embedded PDF face (already the right weight).
  static bool isEmbedded(String family) => family.startsWith('PdfFace-');

  /// True when every embedded face in [ops] has finished [FontLoader.load].
  ///
  /// Raster tiles captured before that freeze the host fallback. Zoom rebuilt
  /// them later, which is why the correct face only appeared after zoom.
  static bool readyFor(
    Iterable<Object> ops,
    Uint8List? Function(Object op) bytesOf,
  ) {
    for (final Object op in ops) {
      final Uint8List? bytes = bytesOf(op);
      if (bytes == null || bytes.length < 16) {
        continue;
      }
      final load = _find(bytes);
      if (load == null || load.state == _FontState.loading) {
        return false;
      }
    }
    return true;
  }

  /// Starts loading an owned snapshot of [bytes] as a Flutter face.
  ///
  /// Every distinct callback registered while loading is notified once, on
  /// success or failure. Already completed loads do not notify again; failed
  /// loads are terminal for this buffer. [readyFor] permits host fallback after
  /// failure. A callback can be removed with [removeListener] on disposal.
  static void ensure(Uint8List bytes, void Function() onReady) {
    if (bytes.length < 16) {
      return;
    }
    final existing = _find(bytes);
    if (existing != null) {
      if (existing.state == _FontState.loading) {
        existing.listeners.add(onReady);
      }
      return;
    }
    final snapshot = Uint8List.fromList(bytes).asUnmodifiableView();
    final content = _FontContent(snapshot);
    final load = _FontLoad('PdfFace-${_nextFamily++}')..listeners.add(onReady);
    _buffers[bytes] = load;
    _contents[content] = _FontRecord(content, load);
    _retainedBytes += snapshot.length;
    _trimContents();
    _pending.add(load);
    unawaited(_load(load, snapshot));
  }

  /// Stops retaining a consumer that no longer needs a pending load.
  static void removeListener(void Function() onReady) {
    for (final load in _pending) {
      load.listeners.remove(onReady);
    }
  }

  static _FontLoad? _find(Uint8List bytes) {
    final bound = _buffers[bytes];
    if (bound != null) return bound;
    final record = _contents.remove(_FontContent(bytes));
    if (record == null) return null;
    // Keep the owned snapshot as the retained key, never a caller's mutable
    // lookup buffer. Full byte equality disambiguates even hash collisions.
    _contents[record.content] = record;
    _buffers[bytes] = record.load;
    return record.load;
  }

  static void _trimContents() {
    while (_contents.length > _maxContentEntries ||
        _retainedBytes > _maxContentBytes) {
      final oldest = _contents.keys.first;
      _retainedBytes -= oldest.bytes.length;
      _contents.remove(oldest);
    }
    // Eviction only removes content deduplication snapshots. Weak per-buffer
    // bindings keep active displays correct without retaining the source
    // buffers. Flutter currently provides no API to unload native font faces.
  }

  static Future<void> _load(_FontLoad load, Uint8List snapshot) async {
    try {
      final custom = debugLoadFont;
      if (custom != null) {
        await custom(load.family, snapshot);
      } else {
        final loader = FontLoader(load.family);
        loader.addFont(Future<ByteData>.value(ByteData.sublistView(snapshot)));
        await loader.load();
      }
      load.state = _FontState.ready;
    } on Object {
      load.state = _FontState.failed;
    }
    _pending.remove(load);
    final listeners = load.listeners.toList(growable: false);
    load.listeners.clear();
    for (final listener in listeners) {
      try {
        listener();
      } on Object catch (error, stack) {
        // A consumer error must not mark a successfully loaded font as failed
        // or prevent the other canvases waiting for it from being notified.
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'Quds PDF font loading',
            context: ErrorDescription('while notifying a font consumer'),
          ),
        );
      }
    }
  }
}

enum _FontState { loading, ready, failed }

class _FontLoad {
  _FontLoad(this.family);
  final String family;
  _FontState state = _FontState.loading;
  final Set<void Function()> listeners = {};
}

class _FontRecord {
  _FontRecord(this.content, this.load);
  final _FontContent content;
  final _FontLoad load;
}

class _FontContent {
  _FontContent(this.bytes) : _hash = Object.hashAll(bytes);
  final Uint8List bytes;
  final int _hash;

  @override
  int get hashCode => _hash;

  @override
  bool operator ==(Object other) =>
      other is _FontContent &&
      _hash == other._hash &&
      listEquals(bytes, other.bytes);
}
