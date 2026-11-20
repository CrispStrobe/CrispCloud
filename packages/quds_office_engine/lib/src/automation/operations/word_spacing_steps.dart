import 'package:quds_office_engine/quds_office_engine.dart';

/// Set an explicit Word line rule and its point value as one native edit.
///
/// Word uses twelve points to express one line for multiple spacing. The
/// native model stores that rule as a multiplier, while exact/minimum spacing
/// remains in points. Owning both values avoids interpreting an old document
/// value according to a different rule.
void setWordLineSpacing(
  WmlDocument document,
  WmlParagraph paragraph, {
  required String rule,
  required double points,
}) {
  final nativeRule = switch (rule) {
    'atLeast' => WmlLineSpacingRule.atLeast,
    'exact' => WmlLineSpacingRule.exact,
    'multiple' => WmlLineSpacingRule.auto,
    _ => throw ArgumentError('rule must be atLeast, exact, or multiple'),
  };
  final twips = points * 20;
  if (!points.isFinite ||
      points <= 0 ||
      twips > 2147483647 ||
      twips.round() / 20 != points) {
    throw ArgumentError(
      'points must be positive exact twentieth-points with at most '
      '2147483647 twips',
    );
  }
  validateWordLineSpacingSource(document, paragraph);
  final properties = paragraph.properties.copy();
  // Preserve sparse ownership of before/after attributes and foreign source
  // metadata. Removing the granular snapshot also records a same-value write
  // as direct formatting, even when its effective value came from a style.
  properties.importedValues?.remove('spacing:line');
  properties.lineSpacingRule = nativeRule;
  properties.lineSpacing = rule == 'multiple' ? points / 12 : points;
  properties.explicitLineSpacing = true;
  paragraph.properties = properties;
}

const _w = OfficeNamespaces.w;

bool _word(XmlElement node, String name) =>
    node.localName == name && node.namespaceUri == _w;

/// Validate source ownership and serialization boundaries before any native
/// line-spacing edit, including presets in the general paragraph operation.
void validateWordLineSpacingSource(
  WmlDocument document,
  WmlParagraph paragraph,
) {
  if (WordFieldSpans.unbalanced(document).isNotEmpty) {
    throw UnsupportedError(
      'Line-spacing edits cannot preserve unbalanced modeled field boundaries.',
    );
  }
  final source = paragraph.properties.sourcePropertiesXml;
  if (source != null && source.isNotEmpty) {
    final wrapper = XmlDocument.parse(
      '<w:context xmlns:w="$_w">$source</w:context>',
    ).root!;
    final roots = wrapper.childElements.toList(growable: false);
    if (roots.length != 1 || !_word(roots.single, 'pPr')) {
      throw UnsupportedError(
        'Line-spacing edits require unambiguous native paragraph properties.',
      );
    }
    _checkElement(roots.single);
  }
  for (final part in document.package?.parts ?? <PackagePart>[]) {
    if (!part.contentType.endsWith('+xml') ||
        (!part.contentType.contains('wordprocessingml') &&
            !part.contentType.contains('vnd.ms-word'))) {
      continue;
    }
    final source = part.readText();
    if (!source.contains('spacing') && !source.contains('pPr')) continue;
    final root = XmlDocument.parse(source).root;
    if (root == null) {
      throw UnsupportedError('Missing native Word XML root.');
    }
    _checkElement(root);
  }
}

void _checkElement(XmlElement element, {bool alternative = false}) {
  final insideAlternative =
      alternative ||
      (element.localName == 'AlternateContent' &&
          element.namespaceUri == OfficeNamespaces.mc);
  if (element.localName == 'spacing' && insideAlternative) {
    // Even a foreign spacing lookalike may be discarded when the reader
    // selects an alternative. Refuse rather than claiming to preserve a
    // property packet whose opaque branch is not retained by this model.
    throw UnsupportedError(
      'Line-spacing edits do not resolve spacing-bearing '
      'markup-compatibility alternatives.',
    );
  }
  if (_word(element, 'spacing')) {
    for (final name in const ['line', 'lineRule']) {
      if (element.attributes
              .where((a) => a.localName == name && a.namespaceUri == _w)
              .length >
          1) {
        throw UnsupportedError('Ambiguous duplicate native spacing $name.');
      }
    }
  }
  if (_word(element, 'pPr') &&
      element.childElements.where((child) => _word(child, 'spacing')).length >
          1) {
    throw UnsupportedError('Ambiguous duplicate native paragraph spacing.');
  }
  if (_word(element, 'p') &&
      element.childElements.where((child) => _word(child, 'pPr')).length > 1) {
    throw UnsupportedError('Ambiguous duplicate native paragraph properties.');
  }
  for (final child in element.childElements) {
    _checkElement(child, alternative: insideAlternative);
  }
}
