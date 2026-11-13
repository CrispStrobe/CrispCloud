import 'package:flutter/services.dart';
import 'package:quds_office_editor/quds_office_editor.dart'
    show OfficeHostFonts;

import 'document_font_catalog.dart';

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

  static Future<void> _register() async {
    await OfficeHostFonts.ensureRegistered();
    // The editor owns Liberation and Noto. These two additional families reuse
    // bytes already bundled by CrispCloud and the PDF editor asset package.
    for (final family in const ['Carlito', 'Roboto']) {
      final faces = documentFontAssets.where((face) => face.family == family);
      await OfficeHostFonts.registerFamily(
        family: family,
        faces: await Future.wait(faces.map((face) => _load(face.asset))),
        aliases: faces.expand((face) => face.aliases).toSet().toList(),
        hasItalic: faces.any((face) => face.italic),
      );
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
