/// AcroForm field (ISO 32000-1 §12.7).
class PdfFormField {
  /// PdfFormField API.
  PdfFormField({
    required this.name,
    required this.type,
    this.value = '',
    this.exportValue = '',
    this.options = const <String>[],
    this.multiline = false,
    this.readOnly = false,
    this.pageIndex = 0,
    this.objectId,
  });

  /// Fully qualified field name.
  final String name;

  /// `Tx`, `Btn`, `Ch`, or `Sig`.
  final String type;

  /// value API.
  String value;

  /// exportValue API.
  String exportValue;

  /// options API.
  final List<String> options;

  /// multiline API.
  final bool multiline;

  /// readOnly API.
  final bool readOnly;

  /// pageIndex API.
  final int pageIndex;

  /// objectId API.
  final int? objectId;
}

/// Class PdfAcroForm.
class PdfAcroForm {
  /// PdfAcroForm API.
  PdfAcroForm({
    List<PdfFormField>? fields,
    this.needAppearances = false,
    this.hasXfa = false,
  }) : fields = fields ?? <PdfFormField>[];

  /// fields API.
  final List<PdfFormField> fields;

  /// needAppearances API.
  bool needAppearances;

  /// `/XFA` is present. Deprecated; extract nothing from the packet.
  final bool hasXfa;

  /// field API.
  PdfFormField? field(String name) {
    for (final PdfFormField item in fields) {
      if (item.name == name) {
        return item;
      }
    }
    return null;
  }
}
