import 'package:flutter/services.dart';

/// Loads embedded PDF `/FontFile2` faces so paint matches the file.
abstract final class PdfFontFaces {
  static final Map<int, String> _ready = <int, String>{};
  static final Set<int> _loading = <int>{};
  static final Set<int> _failed = <int>{};

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
    return _ready[_key(bytes)] ?? host;
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
      final int key = _key(bytes);
      if (_failed.contains(key)) {
        continue;
      }
      if (!_ready.containsKey(key)) {
        return false;
      }
    }
    return true;
  }

  /// Starts loading [bytes] as a Flutter face. Calls [onReady] once.
  static void ensure(Uint8List bytes, void Function() onReady) {
    if (bytes.length < 16) {
      return;
    }
    final int key = _key(bytes);
    if (_ready.containsKey(key) || !_loading.add(key)) {
      return;
    }
    final String name = 'PdfFace-$key';
    final FontLoader loader = FontLoader(name);
    loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    loader
        .load()
        .then((_) {
          _ready[key] = name;
          _loading.remove(key);
          onReady();
        })
        .catchError((Object _) {
          _loading.remove(key);
          _failed.add(key);
          onReady();
        });
  }

  static int _key(Uint8List bytes) {
    return Object.hash(
      bytes.length,
      bytes[0],
      bytes[bytes.length >> 2],
      bytes[bytes.length >> 1],
      bytes[bytes.length - 1],
    );
  }
}
