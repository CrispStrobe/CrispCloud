import 'package:quds_office_engine/quds_office_engine.dart';

import 'word_page_setup_steps.dart';

/// Sets the break that starts one existing section without taking ownership of
/// its geometry, numbering, header/footer references, or retained extensions.
/// Every check and source edit is prepared before publishing to the live model.
void setWordSectionStart(
  WmlDocument document,
  WmlSection section, {
  required String kind,
}) {
  final value = switch (kind) {
    'continuous' => WmlSectionBreakKind.continuous,
    'nextPage' => WmlSectionBreakKind.nextPage,
    'evenPage' => WmlSectionBreakKind.evenPage,
    'oddPage' => WmlSectionBreakKind.oddPage,
    _ => throw ArgumentError('Unsupported section start: $kind'),
  };
  final source = section.sourceProperties;
  final root = source == null ? null : XmlDocument.parse(source.xml).root;
  if (source != null &&
      (root == null ||
          root.namespaceUri != OfficeNamespaces.w ||
          root.localName != 'sectPr')) {
    throw UnsupportedError('Section start requires native section properties.');
  }
  validateWordSectionIdentity(document, root);

  WmlSectionSource? replacementSource;
  if (source != null && root != null) {
    final starts = root
        .childrenNamed('type', namespaceUri: OfficeNamespaces.w)
        .toList();
    if (starts.length > 1) {
      throw UnsupportedError('Section start refuses duplicate native type.');
    }
    final start = starts.isEmpty
        ? XmlElement(
            localName: 'type',
            prefix: 'w',
            namespaceUri: OfficeNamespaces.w,
          )
        : starts.single;
    if (start.attributes
            .where(
              (attribute) =>
                  attribute.namespaceUri == OfficeNamespaces.w &&
                  attribute.localName == 'val',
            )
            .length >
        1) {
      throw UnsupportedError('Section start refuses duplicate native values.');
    }
    // An explicit assignment owns the native attribute even when the model
    // already contains that value (including an imported fallback value).
    setWordSectionAttribute(start, 'val', kind);
    if (starts.isEmpty) root.addChild(start);
    replacementSource = WmlSectionSource(
      xml: XmlDocument(root: root).toXmlString(declaration: false),
      values: {...source.values, 'type': value.name},
    );
  }

  section.breakKind = value;
  if (replacementSource != null) section.sourceProperties = replacementSource;
}
