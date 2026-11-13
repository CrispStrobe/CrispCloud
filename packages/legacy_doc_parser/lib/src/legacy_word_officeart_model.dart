// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

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

/// An editing hint associated with an original vertex. It does not add a
/// rendered segment; the source escape code remains distinct from geometry.
class LegacyWordOfficeArtPathEditingHint {
  const LegacyWordOfficeArtPathEditingHint(this.vertexIndex, this.escape);
  final int vertexIndex, escape;
}

class LegacyWordOfficeArtGeometry {
  LegacyWordOfficeArtGeometry({
    required this.bounds,
    this.preset,
    List<LegacyWordOfficeArtPathCommand> path = const [],
    List<LegacyWordOfficeArtPathEditingHint> editingHints = const [],
  }) : path = List.unmodifiable(path),
       editingHints = List.unmodifiable(editingHints);

  /// A fixed supported identifier: rect, roundRect, ellipse or line.
  /// A custom path has no preset.
  final String? preset;
  final LegacyWordVectorBounds bounds;
  final List<LegacyWordOfficeArtPathCommand> path;
  final List<LegacyWordOfficeArtPathEditingHint> editingHints;
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
    this.compoundStyle,
    this.dash,
    this.join,
    this.cap,
  });
  final bool? enabled;
  final int? type;
  final String? color;
  final int? opacityFixed16;
  final int? widthEmu;

  /// MSOLINESTYLE: 0=single, 1=double, 2=thick/thin, 3=thin/thick, 4=triple.
  /// Compound styles remain unsupported for active output; absence is single.
  final int? compoundStyle;
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

/// Raw Word FOPT positioning properties. The Word producers represented by
/// the native corpus use 0=margin, 1=page, 2=column/paragraph, 3=character/line.
/// These differ from the one-based generic MS-ODRAW enum table. Values outside
/// the supported ranges survive here and are diagnosed, never reinterpreted.
/// The original SPA origins and signed offsets remain on the drawing.
class LegacyWordOfficeArtPosition {
  const LegacyWordOfficeArtPosition({
    this.horizontalMode,
    this.verticalMode,
    this.horizontalRelativeTo,
    this.verticalRelativeTo,
  });
  final int? horizontalMode, verticalMode;
  final int? horizontalRelativeTo, verticalRelativeTo;
}

/// Explicit nonnegative distances between a shape and surrounding content.
/// Word stores these OfficeArt values in EMUs, independently of text insets,
/// the FSPA wrapping mode, and the shape's anchor rectangle. Null preserves
/// absence; an explicit zero must not become a consumer's default clearance.
/// Unsupported signed-negative/complex operands remain source evidence.
class LegacyWordOfficeArtWrapDistances {
  const LegacyWordOfficeArtWrapDistances({
    this.leftEmu,
    this.topEmu,
    this.rightEmu,
    this.bottomEmu,
  });
  final int? leftEmu, topEmu, rightEmu, bottomEmu;
}

/// Only the stream version and its declared byte extent are inspected. A
/// matching header does not validate packets, properties or pen strokes.
enum LegacyWordInkHeaderStatus {
  version1Extent,
  unsupportedVersion,
  invalidHeader,
}

/// Inert ISF bytes unwrapped from a validated OfficeArt IMsoInkData envelope.
/// Boolean values are null unless their independent source use bit is set.
/// Neither the annotation bit nor a discussion anchor identifies a comment.
class LegacyWordOfficeArtInk {
  LegacyWordOfficeArtInk({
    Uint8List? data,
    this.annotation,
    this.hitTestInk,
    this.renderShape,
    this.renderInk,
  }) : data = _copyInkBytes(data);

  static const maxDataLength = 16 * 1024 * 1024;
  final Uint8List? data;
  final bool? annotation, hitTestInk, renderShape, renderInk;

  LegacyWordInkHeaderStatus? get headerStatus {
    final bytes = data;
    if (bytes == null) return null;
    var cursor = 0;
    int? number(int maximum) {
      var value = 0, multiplier = 1;
      for (var i = 0; i < 10 && cursor < bytes.length; i++) {
        final byte = bytes[cursor++], low = byte & 0x7f;
        if (low > (maximum - value) ~/ multiplier) return null;
        value += low * multiplier;
        if (byte < 128) return value;
        // Values already beyond the bounded extent cannot become valid by
        // adding more bits. Saturation also keeps JavaScript arithmetic exact.
        multiplier = multiplier <= maximum ~/ 128
            ? multiplier * 128
            : maximum + 1;
      }
      return null;
    }

    final version = number(0x7fffffff);
    if (version == null) return LegacyWordInkHeaderStatus.invalidHeader;
    if (version != 0) return LegacyWordInkHeaderStatus.unsupportedVersion;
    final length = number(maxDataLength);
    return length != null && length == bytes.length - cursor
        ? LegacyWordInkHeaderStatus.version1Extent
        : LegacyWordInkHeaderStatus.invalidHeader;
  }
}

Uint8List? _copyInkBytes(Uint8List? bytes) {
  if (bytes == null) return null;
  if (bytes.length > LegacyWordOfficeArtInk.maxDataLength) {
    throw const FormatException('OfficeArt ink exceeds its byte limit.');
  }
  return Uint8List.fromList(bytes).asUnmodifiableView();
}

/// The resolved, bounded subset of an OfficeArt FSP/FOPT shape. Unknown or
/// context-dependent data remains in the original OfficeArt artifact.
class LegacyWordOfficeArtShape {
  LegacyWordOfficeArtShape({
    required this.type,
    this.sourceFlags = 0,
    this.rotationFixed16 = 0,
    this.flipHorizontal = false,
    this.flipVertical = false,
    this.geometry,
    this.fill,
    this.line,
    this.shadow,
    this.text,
    this.position,
    this.wrapDistances,
    this.groupShapeBooleanProperties,
    this.ink,
    this.discussionAnchor = false,
    List<int> unsupportedProperties = const [],
  }) : unsupportedProperties = List.unmodifiable(unsupportedProperties) {
    final group = groupShapeBooleanProperties;
    if (group != null && (group < 0 || group > 0xffffffff)) {
      throw const FormatException('Invalid OfficeArt group Boolean word.');
    }
  }

  /// MSOSPT from OfficeArtFSP.recInstance, never inferred from image bytes.
  final int type;

  /// Original FSP flags. Group, child, OLE and master contexts need resolution
  /// before isolated geometry can be emitted as an active native shape.
  final int sourceFlags;

  /// The resolved 0x03BF property word, after independent use-bit inheritance.
  /// Original property records remain in the associated OfficeArt artifact.
  final int? groupShapeBooleanProperties;

  /// Null means the property was not explicitly used; its source default is
  /// true. Only this group Boolean currently has an active layout mapping.
  bool? get layoutInCell {
    final value = groupShapeBooleanProperties;
    if (value == null || ((value ~/ 65536) & 0x8000) == 0) return null;
    return (value & 0x8000) != 0;
  }

  final int rotationFixed16;
  final bool flipHorizontal, flipVertical;
  final LegacyWordOfficeArtGeometry? geometry;
  final LegacyWordOfficeArtFill? fill;
  final LegacyWordOfficeArtLine? line;
  final LegacyWordOfficeArtShadow? shadow;
  final LegacyWordOfficeArtText? text;
  final LegacyWordOfficeArtPosition? position;
  final LegacyWordOfficeArtWrapDistances? wrapDistances;
  final LegacyWordOfficeArtInk? ink;

  /// MS-ODRAW idDiscussAnchor equals 1. This is not a comment identifier.
  final bool discussionAnchor;
  final List<int> unsupportedProperties;
}
