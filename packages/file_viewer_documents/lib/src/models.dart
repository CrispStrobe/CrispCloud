typedef DocumentJson = Map<String, dynamic>;

enum DocumentPreviewKind { wordperfect, chm, spreadsheet, ppt, postscript, xml }

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
