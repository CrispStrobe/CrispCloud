// SPDX-License-Identifier: MPL-2.0

import 'legacy_word_structured_model.dart';

/// Validate the MS-DOC section geometry retained by the public model.
/// Section Properties (2.6.4) gives top/bottom margins a narrower domain than
/// YAS. Gutter size is a full unsigned 16-bit value, not an XAS_nonNeg.
void validateLegacyWordSectionGeometry(LegacyWordSection section) {
  void bounded(int? value, int minimum, int maximum, String name) {
    if (value != null && (value < minimum || value > maximum)) {
      throw FormatException('Invalid Word section $name.');
    }
  }

  bounded(section.pageWidthTwips, 144, 31680, 'page width');
  bounded(section.pageHeightTwips, 144, 31680, 'page height');
  bounded(section.marginTopTwips, -31665, 31665, 'top margin');
  bounded(section.marginBottomTwips, -31665, 31665, 'bottom margin');
  bounded(section.marginLeftTwips, 0, 31680, 'left margin');
  bounded(section.marginRightTwips, 0, 31680, 'right margin');
  bounded(section.headerDistanceTwips, 0, 31680, 'header distance');
  bounded(section.footerDistanceTwips, 0, 31680, 'footer distance');
  bounded(section.columnsSpaceTwips, 0, 31680, 'column spacing');
  bounded(section.gutterTwips, 0, 65535, 'gutter');
}
