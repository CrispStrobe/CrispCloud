import 'package:flutter/services.dart';

/// Ships metric-compatible core faces with the editor package so paint does
/// not depend on the host OS font directory.
///
/// - Liberation Sans / Serif / Mono → PDF Standard 14 + Arial/Times/Courier
/// - Noto Naskh Arabic → RTL / Arabic theme
///
/// Call [ensureRegistered] once before the first paint (e.g. in `main`).
/// Embedded PDF `/FontFile*` bytes still win over these host faces.
abstract final class OfficeHostFonts {
  static var _done = false;
  static Future<void>? _inflight;
  static final Map<String, (String, bool)> _registeredFaces = {};

  /// The actual bundled family behind a successfully loaded name or alias.
  /// Unknown/unloaded names and unavailable italic faces stay unresolved;
  /// callers must not silently measure a platform fallback as that font.
  static String? registeredFamily(String family, {bool italic = false}) {
    final face = _registeredFaces[family.toLowerCase()];
    if (face == null || (italic && !face.$2)) return null;
    return face.$1;
  }

  /// Registers bundled faces and common Office/PDF aliases.
  static Future<void> ensureRegistered() {
    if (_done) {
      return Future<void>.value();
    }
    return _inflight ??= _register().whenComplete(() {
      _inflight = null;
    });
  }

  static Future<void> _register() async {
    final ByteData sansR = await _asset('LiberationSans-Regular.ttf');
    final ByteData sansB = await _asset('LiberationSans-Bold.ttf');
    final ByteData sansI = await _asset('LiberationSans-Italic.ttf');
    final ByteData sansBI = await _asset('LiberationSans-BoldItalic.ttf');
    final ByteData serifR = await _asset('LiberationSerif-Regular.ttf');
    final ByteData serifB = await _asset('LiberationSerif-Bold.ttf');
    final ByteData serifI = await _asset('LiberationSerif-Italic.ttf');
    final ByteData serifBI = await _asset('LiberationSerif-BoldItalic.ttf');
    final ByteData monoR = await _asset('LiberationMono-Regular.ttf');
    final ByteData monoB = await _asset('LiberationMono-Bold.ttf');
    final ByteData monoI = await _asset('LiberationMono-Italic.ttf');
    final ByteData monoBI = await _asset('LiberationMono-BoldItalic.ttf');
    final ByteData naskhR = await _asset('NotoNaskhArabic-Regular.ttf');
    final ByteData naskhB = await _asset('NotoNaskhArabic-Bold.ttf');

    const List<String> sansAliases = <String>[
      'Liberation Sans',
      'Helvetica',
      'Arial',
      'Calibri',
      'Carlito',
      'Roboto',
      'SansSerif',
    ];
    for (final String name in sansAliases) {
      await _face(
        name,
        <ByteData>[sansR, sansB, sansI, sansBI],
        resolvedFamily: 'Liberation Sans',
        hasItalic: true,
      );
    }

    const List<String> serifAliases = <String>[
      'Liberation Serif',
      'Times New Roman',
      'Times',
      'Times-Roman',
      'Georgia',
      'Serif',
    ];
    for (final String name in serifAliases) {
      await _face(
        name,
        <ByteData>[serifR, serifB, serifI, serifBI],
        resolvedFamily: 'Liberation Serif',
        hasItalic: true,
      );
    }

    const List<String> monoAliases = <String>[
      'Liberation Mono',
      'Courier New',
      'Courier',
      'Monospace',
    ];
    for (final String name in monoAliases) {
      await _face(
        name,
        <ByteData>[monoR, monoB, monoI, monoBI],
        resolvedFamily: 'Liberation Mono',
        hasItalic: true,
      );
    }

    for (final String name in <String>[
      'Noto Naskh Arabic',
      'NotoNaskhArabic',
    ]) {
      await _face(
        name,
        <ByteData>[naskhR, naskhB],
        resolvedFamily: 'Noto Naskh Arabic',
        hasItalic: false,
      );
    }

    _done = true;
  }

  static Future<ByteData> _asset(String file) {
    return rootBundle.load('packages/quds_office_editor/fonts/$file');
  }

  static Future<void> _face(
    String family,
    List<ByteData> faces, {
    required String resolvedFamily,
    required bool hasItalic,
  }) async {
    final FontLoader loader = FontLoader(family);
    for (final ByteData data in faces) {
      loader.addFont(Future<ByteData>.value(data));
    }
    await loader.load();
    _registeredFaces[family.toLowerCase()] = (resolvedFamily, hasItalic);
  }
}
