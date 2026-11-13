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
  static final Map<String, Future<void>> _extensionLoads = {};
  static final Map<String, String> _extensionOwners = {};

  /// The actual bundled family behind a successfully loaded name or alias.
  /// Unknown/unloaded names and unavailable italic faces stay unresolved;
  /// callers must not silently measure a platform fallback as that font.
  static String? registeredFamily(String family, {bool italic = false}) {
    final face = _registeredFaces[family.trim().toLowerCase()];
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

  /// Adds a host-owned family without copying its assets into this package.
  ///
  /// The host supplies real face bytes (regular/bold/italic/bold-italic when
  /// available) and only verified aliases. For example, Carlito may be supplied
  /// with a Calibri alias. Registration is idempotent per name; additional
  /// aliases may be registered later. Replacing a previously registered face
  /// with different bytes or styles is not supported.
  static Future<void> registerFamily({
    required String family,
    required List<ByteData> faces,
    List<String> aliases = const <String>[],
    bool hasItalic = false,
  }) async {
    bool valid(String name) =>
        name.trim().isNotEmpty &&
        name.length <= 256 &&
        !name.contains(RegExp(r'[\x00-\x1f\x7f]'));
    if (!valid(family) ||
        aliases.any((name) => !valid(name)) ||
        aliases.length > 64 ||
        faces.isEmpty ||
        faces.length > 16) {
      throw ArgumentError('Invalid host font family or face collection.');
    }
    await ensureRegistered();
    final canonical = family.trim();
    final key = canonical.toLowerCase();
    final names = <String>{canonical, ...aliases.map((name) => name.trim())};
    for (final name in names) {
      final normalized = name.toLowerCase();
      final existing =
          _registeredFaces[normalized]?.$1.toLowerCase() ??
          _extensionOwners[normalized];
      if (existing != null && existing != key) {
        throw StateError('Font alias is already registered to another family.');
      }
    }
    // Reserve every alias before the first font-loader await, so simultaneous
    // extension calls cannot claim the same name for unrelated faces.
    for (final name in names) {
      _extensionOwners[name.toLowerCase()] = key;
    }
    for (final name in names) {
      final normalized = name.toLowerCase();
      final pending = _extensionLoads.putIfAbsent(
        normalized,
        () =>
            _face(name, faces, resolvedFamily: canonical, hasItalic: hasItalic),
      );
      try {
        await pending;
      } on Object {
        if (identical(_extensionLoads[normalized], pending)) {
          _extensionLoads.remove(normalized);
        }
        rethrow;
      }
    }
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
    _registeredFaces[family.trim().toLowerCase()] = (resolvedFamily, hasItalic);
  }
}
