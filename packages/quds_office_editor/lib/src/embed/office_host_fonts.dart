import 'package:flutter/services.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import 'office_system_font_validation.dart';

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
  static int _revision = 0;
  static final Map<String, List<OfficeFontFace>> _metricFaces = {};
  static final _paintMetrics =
      <(String, double, int, int, bool), FontMetrics?>{};
  static final Map<String, List<InstalledFontData>> _installedFaces = {};
  static final Map<String, Future<void>> _installedLoads = {};
  static final Set<String> _installedNames = {};
  static int _installedSequence = 0;

  static const _replaceableBundledAliases = <String, String>{
    'arial': 'liberation sans',
    'times new roman': 'liberation serif',
    'courier new': 'liberation mono',
  };

  /// Vertical metrics of the same registered face used for painting. Font
  /// bytes stay in memory; documents retain their authored family names.
  static FontMetrics? wordMetrics(
    int codePoint,
    double sizePoints,
    WmlRunProps props, {
    String? themeFamily,
  }) {
    if (!sizePoints.isFinite || sizePoints <= 0) return null;
    final requested = OfficeTypeface.paintFamily(
      text: String.fromCharCode(codePoint),
      runFamily: OfficeTypeface.familyForRun(props, codePoint),
      themeFamily: themeFamily,
    );
    return paintMetrics(
      registeredFamily(requested) ??
          (OfficeTypeface.isRtlCodePoint(codePoint)
              ? 'Noto Naskh Arabic'
              : OfficeTypeface.isSerifFamily(requested)
              ? 'Liberation Serif'
              : 'Liberation Sans'),
      sizePoints,
      codePoint: codePoint < 32 ? 0x20 : codePoint,
      weight: props.bold ? 700 : 400,
      italic: props.italic,
    );
  }

  /// Metrics for a font family already selected by the canvas painter.
  static FontMetrics? paintMetrics(
    String family,
    double sizePoints, {
    required int codePoint,
    required int weight,
    required bool italic,
  }) {
    final registered = registeredFamily(family) ?? family;
    final normalized = registered.toLowerCase();
    final faces = _metricFaces[normalized];
    if (faces == null) return null;
    final key = (normalized, sizePoints, codePoint, weight, italic);
    if (_paintMetrics.containsKey(key)) return _paintMetrics[key];
    final face = OfficeFontSet(faces: faces).resolve(
      codePoint,
      family: registered,
      weight: weight,
      italic: italic,
      allowPostScriptOutlines: true,
    );
    final metrics = face == null
        ? null
        : FontMetrics(font: face.font, fontSizePoints: sizePoints);
    if (_paintMetrics.length >= 4096) {
      _paintMetrics.remove(_paintMetrics.keys.first);
    }
    _paintMetrics[key] = metrics;
    return metrics;
  }

  /// Changes after a name or alias successfully gains real font bytes.
  /// Measurement caches can use this to discard widths obtained from a
  /// fallback before an asynchronous registration completed.
  static int get registrationRevision => _revision;

  /// The loaded paint family behind a successfully registered name or alias.
  /// Installed replacements use an internal name so old aliases cannot win.
  /// Unknown/unloaded names and unavailable italic faces stay unresolved;
  /// callers must not silently measure a platform fallback as that font.
  static String? registeredFamily(String family, {bool italic = false}) {
    final face = _registeredFaces[family.trim().toLowerCase()];
    if (face == null || (italic && !face.$2)) return null;
    return face.$1;
  }

  /// The loaded paint name for an installed face; other names stay unchanged.
  /// A separate Flutter family prevents an earlier bundled alias from winning
  /// selection after the real installed face becomes available.
  static String paintFamily(String family) {
    final key = family.trim().toLowerCase();
    return _installedFaces.containsKey(key)
        ? _registeredFaces[key]!.$1
        : family;
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
      if (_installedNames.contains(normalized)) {
        throw StateError('An installed font already owns this family name.');
      }
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

  /// Registers verified local TrueType bytes, replacing only a bundled Office
  /// compatibility alias. Custom host families and aliases keep their owners.
  ///
  /// Font family and style come from the bytes. Invalid inputs leave fallback
  /// paint/metrics intact. Repeated identical registrations are idempotent;
  /// changing an already accepted installed face is deliberately unsupported.
  static Future<void> registerInstalledFamily({
    required String family,
    required List<ByteData> faces,
  }) async {
    if (!validInstalledFontFamily(family) ||
        faces.isEmpty ||
        faces.length > 16 ||
        faces.any((face) => face.lengthInBytes > maxInstalledFontBytes) ||
        faces.fold<int>(0, (sum, face) => sum + face.lengthInBytes) >
            maxInstalledFamilyBytes) {
      throw ArgumentError('Invalid installed font family or face collection.');
    }
    final canonical = family.trim();
    final key = canonical.toLowerCase();
    final parsed = <InstalledFontData>[];
    final styles = <(int, bool)>{};
    for (final face in faces) {
      final bytes = Uint8List.fromList(
        face.buffer.asUint8List(face.offsetInBytes, face.lengthInBytes),
      );
      final data = parseInstalledFont(canonical, bytes);
      if (data == null || !styles.add((data.weight, data.italic))) {
        throw ArgumentError('Installed font bytes or style do not match.');
      }
      parsed.add(data);
    }
    await ensureRegistered();
    final pending = _installedLoads[key];
    if (pending != null) await pending;
    final previous = _installedFaces[key];
    if (previous != null) {
      if (!_sameInstalledFaces(previous, parsed)) {
        throw StateError('An installed family cannot be replaced again.');
      }
      return;
    }
    final existing = _registeredFaces[key]?.$1.toLowerCase();
    if (_extensionOwners.containsKey(key) ||
        _installedNames.contains(key) ||
        (existing != null && existing != _replaceableBundledAliases[key])) {
      throw StateError('Another font already owns this family name.');
    }
    _installedNames.add(key);
    final load = _installFamily(key, parsed);
    _installedLoads[key] = load;
    try {
      await load;
    } on Object {
      _installedNames.remove(key);
      rethrow;
    } finally {
      if (identical(_installedLoads[key], load)) _installedLoads.remove(key);
    }
  }

  static Future<void> _installFamily(
    String key,
    List<InstalledFontData> faces,
  ) async {
    String paintName;
    do {
      paintName = 'Quds Installed ${++_installedSequence}';
    } while (_registeredFaces.containsKey(paintName.toLowerCase()) ||
        _extensionOwners.containsKey(paintName.toLowerCase()) ||
        _installedNames.contains(paintName.toLowerCase()));
    final paintKey = paintName.toLowerCase();
    _installedNames.add(paintKey);
    final loader = FontLoader(paintName);
    for (final face in faces) {
      loader.addFont(Future.value(ByteData.sublistView(face.font.bytes)));
    }
    try {
      await loader.load();
    } on Object {
      _installedNames.remove(paintKey);
      rethrow;
    }
    final hasItalic = faces.any((face) => face.italic);
    _metricFaces[paintKey] = [
      for (final face in faces)
        OfficeFontFace(
          font: face.font,
          family: paintName,
          weight: face.weight,
          italic: face.italic,
        ),
    ];
    _registeredFaces[paintKey] = (paintName, hasItalic);
    _registeredFaces[key] = (paintName, hasItalic);
    _installedFaces[key] = faces;
    _paintMetrics.clear();
    _revision++;
  }

  static bool _sameInstalledFaces(
    List<InstalledFontData> first,
    List<InstalledFontData> second,
  ) {
    if (first.length != second.length) return false;
    for (var i = 0; i < first.length; i++) {
      final a = first[i].font.bytes;
      final b = second[i].font.bytes;
      if (a.length != b.length) return false;
      for (var j = 0; j < a.length; j++) {
        if (a[j] != b[j]) return false;
      }
    }
    return true;
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
    _metricFaces.putIfAbsent(resolvedFamily.toLowerCase(), () {
      final parsed = <OfficeFontFace>[];
      for (final data in faces) {
        try {
          final font = SfntFont.parse(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          );
          final table = font.tables['OS/2'];
          final bytes = ByteData.sublistView(font.bytes);
          final weight = table != null && table.length >= 6
              ? bytes.getUint16(table.offset + 4)
              : 400;
          final flags = table != null && table.length >= 64
              ? bytes.getUint16(table.offset + 62)
              : 0;
          parsed.add(
            OfficeFontFace(
              font: font,
              family: resolvedFamily,
              weight: weight.clamp(1, 1000),
              italic: flags & 1 != 0,
            ),
          );
        } on FormatException {
          // Flutter can register formats the pure-Dart parser cannot read.
          // Keep painting available and explicitly fall back for metrics.
        }
      }
      return parsed;
    });
    _registeredFaces[family.trim().toLowerCase()] = (resolvedFamily, hasItalic);
    _paintMetrics.clear();
    _revision++;
  }
}
