import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data' show Endian;

import 'package:flutter/services.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart'
    show LegacyWordImageFormat, parseLegacyWordMetafile;
import 'package:quds_office_editor/quds_office_editor.dart'
    show
        OfficeHostFonts,
        OfficeSystemFonts,
        OfficeSystemFontFace,
        VisualImageCache;

import 'document_font_catalog.dart';
import 'office_font_packs.dart';

/// Loads existing app assets on first document use, without increasing the
/// font bundle or registering all document faces during app startup.
abstract final class DocumentFonts {
  static Future<void>? _registration;
  static bool _registered = false;
  static final _bytes = <String, ByteData>{};
  static final _loading = <String, Future<ByteData>>{};

  static Future<ByteData> _load(String asset) {
    if (_bytes[asset] case final cached?) return Future.value(cached);
    return _loading.putIfAbsent(asset, () {
      // Asset bundles may return SynchronousFuture. Normalize it with await;
      // attaching catchError directly can leave that future pending forever.
      Future<ByteData> read() async {
        final data = await rootBundle.load(asset);
        _bytes[asset] = data;
        return data;
      }

      return read().whenComplete(() {
        _loading.remove(asset);
      });
    });
  }

  static Future<void> ensureRegistered() {
    // Do not retain completed futures in their first caller's zone.
    if (_registered) return Future.value();
    return _registration ??= _register()
        .then((_) {
          _registered = true;
        })
        .whenComplete(() => _registration = null);
  }

  static FutureOr<Uint8List?> _metafilePreview(Uint8List bytes) {
    if (bytes.length < 18) return null;
    final data = ByteData.sublistView(bytes);
    final signature = data.getUint32(0, Endian.little);
    final format = switch (signature) {
      1
          when bytes.length >= 44 &&
              data.getUint32(40, Endian.little) == 0x464d4520 =>
        LegacyWordImageFormat.emf,
      0x9ac6cdd7 || 0x00090001 || 0x00090002 => LegacyWordImageFormat.wmf,
      _ => null,
    };
    if (format == null) return null;
    Uint8List? render() {
      final svg = parseLegacyWordMetafile(bytes, format: format).previewSvg;
      return svg == null ? null : Uint8List.fromList(utf8.encode(svg));
    }

    return const bool.fromEnvironment('dart.library.io')
        ? Isolate.run(render)
        : render();
  }

  static Future<void> _register() async {
    VisualImageCache.metafileAsSvg = _metafilePreview;
    await OfficeHostFonts.ensureRegistered();
    // The editor owns Liberation and Noto. These two additional families reuse
    // bytes already bundled by CrispCloud and the PDF editor asset package.
    for (final family in const [
      'Carlito',
      'Roboto',
      'DejaVu Sans',
      'Noto Emoji',
    ]) {
      final faces = documentFontAssets.where((face) => face.family == family);
      await OfficeHostFonts.registerFamily(
        family: family,
        faces: await Future.wait(faces.map((face) => _load(face.asset))),
        aliases: faces.expand((face) => face.aliases).toSet().toList(),
        hasItalic: faces.any((face) => face.italic),
      );
    }
    // Exact local Office faces are read from the host at runtime, not bundled.
    // Existing compatibility aliases remain authoritative for Flutter paint.
    final system = await OfficeSystemFonts.load();
    final byFamily = <String, List<OfficeSystemFontFace>>{};
    for (final face in system) {
      byFamily
          .putIfAbsent(face.family, () => <OfficeSystemFontFace>[])
          .add(face);
    }
    for (final entry in byFamily.entries) {
      try {
        await OfficeHostFonts.registerFamily(
          family: entry.key,
          faces: <ByteData>[
            for (final face in entry.value) ByteData.sublistView(face.bytes),
          ],
          hasItalic: entry.value.any((face) => face.italic),
        );
      } on Object {
        // A bundled compatibility alias already owns this family name.
      }
    }
    // Optional open packs fill remaining gaps after exact Office faces.
    try {
      await OfficeFontPacks.registerInstalled();
    } on Object {
      // Widget tests and unsupported hosts have no application-support path.
    }
  }

  /// A stable list in catalog order, suitable for sending to a PDF worker.
  /// SFNT parsing and layout remain in that worker on native platforms.
  static Future<List<Uint8List>> loadExportFaces() async => Future.wait(
    documentFontAssets.map((face) async {
      final data = await _load(face.asset);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    }),
  );
}
