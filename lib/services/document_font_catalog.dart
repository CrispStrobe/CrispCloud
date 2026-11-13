/// One inventory of existing font assets shared by Office preview, export,
/// editor registration, and the isolated browser document host.
///
/// Aliases are rendering substitutions only; source document properties are
/// never rewritten. No font bytes are duplicated by this catalog.
class DocumentFontAsset {
  const DocumentFontAsset({
    required this.asset,
    required this.family,
    this.aliases = const [],
    this.weight = 400,
    this.italic = false,
  });

  final String asset;
  final String family;
  final List<String> aliases;
  final int weight;
  final bool italic;
}

const _officeFontPrefix = 'packages/quds_office_editor/fonts/';
const _pdfFontPrefix = 'packages/dart_pdf_editor_assets/assets/fonts/';

const documentFontAssets = <DocumentFontAsset>[
  DocumentFontAsset(
    asset: '${_officeFontPrefix}LiberationSans-Regular.ttf',
    family: 'Liberation Sans',
    aliases: ['Arial', 'Helvetica', 'SansSerif', 'sans-serif'],
  ),
  DocumentFontAsset(
    asset: '${_officeFontPrefix}LiberationSans-Bold.ttf',
    family: 'Liberation Sans',
    weight: 700,
  ),
  DocumentFontAsset(
    asset: '${_officeFontPrefix}LiberationSans-Italic.ttf',
    family: 'Liberation Sans',
    italic: true,
  ),
  DocumentFontAsset(
    asset: '${_officeFontPrefix}LiberationSans-BoldItalic.ttf',
    family: 'Liberation Sans',
    weight: 700,
    italic: true,
  ),
  DocumentFontAsset(
    asset: '${_officeFontPrefix}LiberationSerif-Regular.ttf',
    family: 'Liberation Serif',
    aliases: ['Times New Roman', 'Times', 'Times-Roman', 'serif'],
  ),
  DocumentFontAsset(
    asset: '${_officeFontPrefix}LiberationSerif-Bold.ttf',
    family: 'Liberation Serif',
    weight: 700,
  ),
  DocumentFontAsset(
    asset: '${_officeFontPrefix}LiberationSerif-Italic.ttf',
    family: 'Liberation Serif',
    italic: true,
  ),
  DocumentFontAsset(
    asset: '${_officeFontPrefix}LiberationSerif-BoldItalic.ttf',
    family: 'Liberation Serif',
    weight: 700,
    italic: true,
  ),
  DocumentFontAsset(
    asset: '${_officeFontPrefix}LiberationMono-Regular.ttf',
    family: 'Liberation Mono',
    aliases: ['Courier New', 'Courier', 'monospace'],
  ),
  DocumentFontAsset(
    asset: '${_officeFontPrefix}LiberationMono-Bold.ttf',
    family: 'Liberation Mono',
    weight: 700,
  ),
  DocumentFontAsset(
    asset: '${_officeFontPrefix}LiberationMono-Italic.ttf',
    family: 'Liberation Mono',
    italic: true,
  ),
  DocumentFontAsset(
    asset: '${_officeFontPrefix}LiberationMono-BoldItalic.ttf',
    family: 'Liberation Mono',
    weight: 700,
    italic: true,
  ),
  DocumentFontAsset(
    asset: '${_officeFontPrefix}NotoNaskhArabic-Regular.ttf',
    family: 'Noto Naskh Arabic',
    aliases: ['NotoNaskhArabic'],
  ),
  DocumentFontAsset(
    asset: '${_officeFontPrefix}NotoNaskhArabic-Bold.ttf',
    family: 'Noto Naskh Arabic',
    weight: 700,
  ),
  DocumentFontAsset(
    asset: '${_pdfFontPrefix}Carlito-Regular.ttf',
    family: 'Carlito',
    aliases: ['Calibri'],
  ),
  DocumentFontAsset(
    asset: '${_pdfFontPrefix}Carlito-Bold.ttf',
    family: 'Carlito',
    weight: 700,
  ),
  DocumentFontAsset(
    asset: '${_pdfFontPrefix}Carlito-Italic.ttf',
    family: 'Carlito',
    italic: true,
  ),
  DocumentFontAsset(
    asset: '${_pdfFontPrefix}Carlito-BoldItalic.ttf',
    family: 'Carlito',
    weight: 700,
    italic: true,
  ),
  DocumentFontAsset(
    asset: 'assets/fonts/Roboto-Regular.ttf',
    family: 'Roboto',
    aliases: ['StoreRoboto'],
  ),
  DocumentFontAsset(
    asset: 'assets/fonts/Roboto-Medium.ttf',
    family: 'Roboto',
    weight: 500,
  ),
  DocumentFontAsset(
    asset: 'assets/fonts/Roboto-Bold.ttf',
    family: 'Roboto',
    weight: 700,
  ),
];

/// Resolve known compatibility aliases without guessing unfamiliar font names.
String documentFontFamily(String requested) {
  final name = requested.trim();
  final key = name.toLowerCase();
  for (final face in documentFontAssets) {
    if (face.family.toLowerCase() == key ||
        face.aliases.any((alias) => alias.toLowerCase() == key)) {
      return face.family;
    }
  }
  return name;
}

/// All compatibility names apply to every real style in a family.
List<String> documentFontAliases(String family) => documentFontAssets
    .where((face) => face.family == family)
    .expand((face) => face.aliases)
    .toSet()
    .toList(growable: false);

const documentFontFallbacks = [
  'Liberation Sans',
  'Liberation Serif',
  'Noto Naskh Arabic',
];
