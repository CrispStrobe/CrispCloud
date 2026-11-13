typedef DocumentJson = Map<String, dynamic>;

/// A trusted, already bundled font offered by the embedding application.
///
/// [asset] is an exact Flutter asset key, never a file path or a remote URL.
/// Font programs are loaded only when a renderer needs their family/style;
/// this descriptor does not add another copy of the font to the package.
class DocumentPreviewFont {
  const DocumentPreviewFont({
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

enum DocumentPreviewKind { wordperfect, chm, spreadsheet, ppt, postscript, xml }

/// PS owns its interpreter fonts, CHM retains archive fonts, and XML is source
/// tooling. Only these three document renderers use the app's shared catalog.
bool documentPreviewUsesSharedFonts(DocumentPreviewKind kind) => switch (kind) {
  DocumentPreviewKind.wordperfect ||
  DocumentPreviewKind.spreadsheet ||
  DocumentPreviewKind.ppt => true,
  _ => false,
};

DocumentPreviewKind? documentPreviewKind(String filename) {
  final ext = filename.toLowerCase().split('.').last;
  return switch (ext) {
    'wpd' || 'wp' || 'wp5' || 'wp6' => DocumentPreviewKind.wordperfect,
    'chm' => DocumentPreviewKind.chm,
    'xls' || 'xlt' || 'xlsb' => DocumentPreviewKind.spreadsheet,
    'ppt' || 'pot' || 'pps' => DocumentPreviewKind.ppt,
    'ps' || 'eps' => DocumentPreviewKind.postscript,
    'xml' || 'xsl' || 'xslt' || 'xsd' => DocumentPreviewKind.xml,
    _ => null,
  };
}

const documentPreviewMaxBytes = 64 * 1024 * 1024;
const documentPreviewChannel = 'crisp-document-v1';
const documentPreviewChunkBytes = 192 * 1024;

int documentPreviewByteLimit(DocumentPreviewKind kind) => switch (kind) {
  DocumentPreviewKind.xml => 4 * 1024 * 1024,
  DocumentPreviewKind.ppt ||
  DocumentPreviewKind.spreadsheet ||
  DocumentPreviewKind.postscript => 32 * 1024 * 1024,
  _ => documentPreviewMaxBytes,
};
