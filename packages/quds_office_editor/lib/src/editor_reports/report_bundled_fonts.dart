import 'package:flutter/services.dart';
import 'package:quds_office_engine/quds_reports.dart';

/// Loads the TrueType faces bundled with the editor package into a
/// [ReportFontRegistry], so the report preview and exports embed real fonts
/// (Liberation for Latin, Noto Naskh for Arabic) without host font files.
abstract final class ReportBundledFonts {
  static Future<ReportFontRegistry>? _shared;

  /// One registry shared by every designer (faces are parsed once).
  static Future<ReportFontRegistry> shared() => _shared ??= load();

  /// Fresh registry: Liberation Sans (default), Serif, Mono, Noto Naskh
  /// Arabic. Missing glyphs fall through families in that order.
  static Future<ReportFontRegistry> load({AssetBundle? bundle}) async {
    final AssetBundle b = bundle ?? rootBundle;
    final ReportFontRegistry fonts = ReportFontRegistry();
    Future<Uint8List> asset(String file) async {
      final ByteData data = await b.load(
        'packages/quds_office_editor/fonts/$file',
      );
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    }

    fonts.registerBytes(
      'Liberation Sans',
      await asset('LiberationSans-Regular.ttf'),
      bold: await asset('LiberationSans-Bold.ttf'),
      italic: await asset('LiberationSans-Italic.ttf'),
      boldItalic: await asset('LiberationSans-BoldItalic.ttf'),
    );
    fonts.registerBytes(
      'Noto Naskh Arabic',
      await asset('NotoNaskhArabic-Regular.ttf'),
      bold: await asset('NotoNaskhArabic-Bold.ttf'),
    );
    fonts.registerBytes(
      'Liberation Serif',
      await asset('LiberationSerif-Regular.ttf'),
      bold: await asset('LiberationSerif-Bold.ttf'),
      italic: await asset('LiberationSerif-Italic.ttf'),
      boldItalic: await asset('LiberationSerif-BoldItalic.ttf'),
    );
    fonts.registerBytes(
      'Liberation Mono',
      await asset('LiberationMono-Regular.ttf'),
      bold: await asset('LiberationMono-Bold.ttf'),
      italic: await asset('LiberationMono-Italic.ttf'),
      boldItalic: await asset('LiberationMono-BoldItalic.ttf'),
    );
    fonts.defaultFamily = 'Liberation Sans';
    return fonts;
  }
}
