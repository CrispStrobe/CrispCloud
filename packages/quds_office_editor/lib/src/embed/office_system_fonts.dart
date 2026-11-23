import 'office_system_font_face.dart';
import 'office_system_fonts_stub.dart'
    if (dart.library.io) 'office_system_fonts_io.dart'
    as impl;

export 'office_system_font_face.dart';

/// Discovers installed Microsoft Office/OS fonts without bundling them.
abstract final class OfficeSystemFonts {
  /// Returns exact local faces when the host has Office or compatible fonts.
  /// Web and sandboxed hosts return an empty list and keep bundled fallbacks.
  static Future<List<OfficeSystemFontFace>> load({
    bool allowPostScriptOutlines = false,
  }) => impl.load(allowPostScriptOutlines: allowPostScriptOutlines);
}
