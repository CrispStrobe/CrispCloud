// SPDX-License-Identifier: MPL-2.0

/// Metafile/device or OfficeArt geometry coordinates, independent of placement.
class LegacyWordVectorBounds {
  const LegacyWordVectorBounds(this.left, this.top, this.right, this.bottom);
  final int left, top, right, bottom;
  int get width => right - left;
  int get height => bottom - top;
}

class LegacyWordOfficeArtPoint {
  const LegacyWordOfficeArtPoint(this.x, this.y);
  final int x, y;
}

enum LegacyWordOfficeArtPathKind { move, line, cubic, close }

/// A resolved path command. Move/line have one point; cubic has three, and
/// close has none. Guides and unsupported escape segments are never guessed.
class LegacyWordOfficeArtPathCommand {
  LegacyWordOfficeArtPathCommand(
    this.kind, [
    List<LegacyWordOfficeArtPoint> points = const [],
  ]) : points = List.unmodifiable(points);
  final LegacyWordOfficeArtPathKind kind;
  final List<LegacyWordOfficeArtPoint> points;
}

class LegacyWordOfficeArtGeometry {
  LegacyWordOfficeArtGeometry({
    required this.bounds,
    this.preset,
    List<LegacyWordOfficeArtPathCommand> path = const [],
  }) : path = List.unmodifiable(path);

  /// A fixed supported identifier: rect, roundRect, ellipse or line.
  /// A custom path has no preset.
  final String? preset;
  final LegacyWordVectorBounds bounds;
  final List<LegacyWordOfficeArtPathCommand> path;
}

/// Explicit resolved properties; null means the property was not specified.
/// RGB values contain six uppercase hexadecimal digits without a prefix.
class LegacyWordOfficeArtFill {
  const LegacyWordOfficeArtFill({
    this.enabled,
    this.type,
    this.color,
    this.opacityFixed16,
  });
  final bool? enabled;
  final int? type;
  final String? color;
  final int? opacityFixed16;
}

class LegacyWordOfficeArtLine {
  const LegacyWordOfficeArtLine({
    this.enabled,
    this.type,
    this.color,
    this.opacityFixed16,
    this.widthEmu,
    this.dash,
    this.join,
    this.cap,
  });
  final bool? enabled;
  final int? type;
  final String? color;
  final int? opacityFixed16;
  final int? widthEmu;
  final int? dash, join, cap;
}

class LegacyWordOfficeArtShadow {
  const LegacyWordOfficeArtShadow({
    this.enabled,
    this.type,
    this.color,
    this.opacityFixed16,
    this.offsetXEmu,
    this.offsetYEmu,
    this.obscured,
  });
  final bool? enabled;
  final int? type;
  final String? color;
  final int? opacityFixed16;
  final int? offsetXEmu, offsetYEmu;
  final bool? obscured;
}

/// Raw documented enum values and explicitly used Boolean properties.
/// Insets are signed EMUs. Absence is distinct from an explicit zero margin.
class LegacyWordOfficeArtText {
  const LegacyWordOfficeArtText({
    this.insetLeftEmu,
    this.insetTopEmu,
    this.insetRightEmu,
    this.insetBottomEmu,
    this.anchor,
    this.wrapMode,
    this.flow,
    this.fontDirection,
    this.fitShapeToText,
    this.autoTextMargin,
  });
  final int? insetLeftEmu, insetTopEmu, insetRightEmu, insetBottomEmu;
  final int? anchor, wrapMode, flow, fontDirection;
  final bool? fitShapeToText, autoTextMargin;
}

/// The resolved, bounded subset of an OfficeArt FSP/FOPT shape. Unknown or
/// context-dependent data remains in the original OfficeArt artifact.
class LegacyWordOfficeArtShape {
  LegacyWordOfficeArtShape({
    required this.type,
    this.rotationFixed16 = 0,
    this.flipHorizontal = false,
    this.flipVertical = false,
    this.geometry,
    this.fill,
    this.line,
    this.shadow,
    this.text,
    List<int> unsupportedProperties = const [],
  }) : unsupportedProperties = List.unmodifiable(unsupportedProperties);

  /// MSOSPT from OfficeArtFSP.recInstance, never inferred from image bytes.
  final int type;
  final int rotationFixed16;
  final bool flipHorizontal, flipVertical;
  final LegacyWordOfficeArtGeometry? geometry;
  final LegacyWordOfficeArtFill? fill;
  final LegacyWordOfficeArtLine? line;
  final LegacyWordOfficeArtShadow? shadow;
  final LegacyWordOfficeArtText? text;
  final List<int> unsupportedProperties;
}
