import 'package:flutter/services.dart';
import 'package:quds_office_engine/quds_reports.dart';

/// The ready-made report templates: `.qrep` files in this package's
/// `templates/` folder, each with a `template.json` manifest.
///
/// Every family ships an Arabic and an English version. Open one in the
/// designer, change it, and save it as a report, or as a template of your
/// own with a [ReportTemplateManifest].
abstract final class ReportTemplateLibrary {
  /// Asset folder of the bundled templates.
  static const String folder = 'packages/quds_office_editor/templates/';

  static Future<List<ReportTemplateInfo>>? _shared;

  /// The bundled templates in menu order ([ReportTemplateInfo.compare]).
  ///
  /// Read once per app from [rootBundle]; pass [bundle] to read another
  /// bundle instead.
  static Future<List<ReportTemplateInfo>> bundled({AssetBundle? bundle}) {
    if (bundle != null) {
      return _load(bundle);
    }
    return _shared ??= _load(rootBundle);
  }

  static Future<List<ReportTemplateInfo>> _load(AssetBundle bundle) async {
    final AssetManifest manifest = await AssetManifest.loadFromAssetBundle(
      bundle,
    );
    final List<ReportTemplateInfo> out = <ReportTemplateInfo>[];
    for (final String key in manifest.listAssets()) {
      if (key.startsWith(folder) && key.toLowerCase().endsWith('.qrep')) {
        final ByteData data = await bundle.load(key);
        out.add(ReportTemplateInfo.decode(Uint8List.sublistView(data)));
      }
    }
    return sorted(out);
  }

  /// [templates] in menu order ([ReportTemplateInfo.compare]).
  static List<ReportTemplateInfo> sorted(
    Iterable<ReportTemplateInfo> templates,
  ) => templates.toList()..sort(ReportTemplateInfo.compare);
}
