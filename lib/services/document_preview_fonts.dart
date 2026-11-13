import 'package:file_viewer_documents/file_viewer_documents.dart';

import 'document_font_catalog.dart';

/// Stable configuration; actual font bytes remain in their existing packages.
final documentPreviewFonts = List<DocumentPreviewFont>.unmodifiable([
  for (final face in documentFontAssets)
    DocumentPreviewFont(
      asset: face.asset,
      family: face.family,
      aliases: documentFontAliases(face.family),
      weight: face.weight,
      italic: face.italic,
    ),
]);
