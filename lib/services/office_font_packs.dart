import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:quds_office_editor/quds_office_editor.dart'
    show
        OfficeFontPack,
        OfficeFontPackStatus,
        OfficeFontPackStore,
        OfficeSystemFontFace;

/// App-owned optional open font packs.
///
/// Installed files live under the writable application-support directory,
/// never inside the signed application bundle. Exact Microsoft fonts remain
/// runtime-only from an installed Office copy and are never redistributed.
abstract final class OfficeFontPacks {
  static OfficeFontPackStore? _store;

  static Future<OfficeFontPackStore?> store() async {
    if (kIsWeb) return null;
    final existing = _store;
    if (existing != null) return existing;
    final support = await getApplicationSupportDirectory();
    return _store = OfficeFontPackStore('${support.path}/fonts');
  }

  static Future<List<OfficeFontPackStatus>> statuses() async =>
      (await store())?.statuses() ?? const <OfficeFontPackStatus>[];

  static Future<void> install(OfficeFontPack pack) async {
    final fonts = await store();
    if (fonts == null) return;
    await fonts.install(pack);
    await fonts.registerInstalled();
  }

  static Future<void> remove(OfficeFontPack pack) async {
    await (await store())?.remove(pack);
  }

  /// Registers verified pack faces after exact Office/OS and bundled faces.
  static Future<void> registerInstalled() async {
    await (await store())?.registerInstalled();
  }

  /// Faces for the PDF engine, verified when read.
  static Future<List<OfficeSystemFontFace>> loadInstalled() async =>
      (await store())?.loadInstalled() ?? const <OfficeSystemFontFace>[];
}
