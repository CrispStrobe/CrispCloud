import 'dart:typed_data';

/// A font installed by the host OS or by Microsoft Office.
///
/// Bytes are read at runtime and never bundled with the application. This lets
/// a locally installed copy of Office supply the exact faces and metrics used
/// by PowerPoint without redistributing Microsoft fonts.
class OfficeSystemFontFace {
  const OfficeSystemFontFace({
    required this.family,
    required this.bytes,
    this.weight = 400,
    this.italic = false,
    this.aliases = const <String>[],
  });

  final String family;
  final Uint8List bytes;
  final int weight;
  final bool italic;
  final List<String> aliases;
}
