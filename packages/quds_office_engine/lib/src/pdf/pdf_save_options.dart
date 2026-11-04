/// Options applied when compiling a PDF (`PdfDocument.save`).
class PdfSaveOptions {
  /// PdfSaveOptions API.
  const PdfSaveOptions({
    this.pdfA = false,
    this.tagged = false,
  });

  /// When true, emits PDF/A-2b-oriented catalog extras:
  /// XMP metadata, sRGB OutputIntent, and `/MarkInfo`.
  ///
  /// Requires embedded fonts for non-Latin text (use a glyf [SfntFont] /
  /// [OfficeFontSet]). Does not claim full validator-certified PDF/A.
  final bool pdfA;

  /// When true, emits `/StructTreeRoot` + `/MarkInfo` from document outlines
  /// (heading bookmarks become structure elements).
  final bool tagged;
}
