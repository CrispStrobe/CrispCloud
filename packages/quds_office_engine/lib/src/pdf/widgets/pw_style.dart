/// Text and theme tokens for the PDF widget tree.
library;

import 'pw_types.dart';

/// Same names as Flutter / `package:pdf` [TextDecoration].
class TextDecoration {
  /// TextDecoration API.
  const TextDecoration._(this._mask);

  final int _mask;

  /// none API.
  static const TextDecoration none = TextDecoration._(0);

  /// underline API.
  static const TextDecoration underline = TextDecoration._(1);

  /// lineThrough API.
  static const TextDecoration lineThrough = TextDecoration._(4);

  /// contains API.
  bool contains(TextDecoration other) => (_mask | other._mask) == _mask;
}

/// Run style. Measured and painted by the PDF layout engine.
class TextStyle {
  /// TextStyle API.
  const TextStyle({
    this.color,
    this.fontSize,
    this.fontWeight,
    this.fontStyle,
    this.decoration,
    this.lineSpacing,
    this.height,
    this.letterSpacing,
  });

  /// RRGGBB or `#RRGGBB`.
  final String? color;

  /// fontSize API.
  final double? fontSize;

  /// fontWeight API.
  final FontWeight? fontWeight;

  /// fontStyle API.
  final FontStyle? fontStyle;

  /// decoration API.
  final TextDecoration? decoration;

  /// Line-height multiplier (legacy alias — prefer [height]).
  final double? lineSpacing;

  /// Line-height multiplier (Flutter / package:pdf [TextStyle.height]).
  final double? height;

  /// Extra advance between glyphs, in points.
  final double? letterSpacing;

  /// Effective line-height multiplier (package:pdf default is 1.0).
  double get lineHeightFactor => height ?? lineSpacing ?? 1.0;

  /// merge API.
  TextStyle merge(TextStyle? other) {
    if (other == null) {
      return this;
    }
    return TextStyle(
      color: other.color ?? color,
      fontSize: other.fontSize ?? fontSize,
      fontWeight: other.fontWeight ?? fontWeight,
      fontStyle: other.fontStyle ?? fontStyle,
      decoration: other.decoration ?? decoration,
      lineSpacing: other.lineSpacing ?? lineSpacing,
      height: other.height ?? height,
      letterSpacing: other.letterSpacing ?? letterSpacing,
    );
  }

  /// copyWith API.
  TextStyle copyWith({
    String? color,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    TextDecoration? decoration,
    double? lineSpacing,
    double? height,
    double? letterSpacing,
  }) {
    return TextStyle(
      color: color ?? this.color,
      fontSize: fontSize ?? this.fontSize,
      fontWeight: fontWeight ?? this.fontWeight,
      fontStyle: fontStyle ?? this.fontStyle,
      decoration: decoration ?? this.decoration,
      lineSpacing: lineSpacing ?? this.lineSpacing,
      height: height ?? this.height,
      letterSpacing: letterSpacing ?? this.letterSpacing,
    );
  }
}

/// Inherited text + heading styles for a [Document].
class ThemeData {
  /// ThemeData API.
  const ThemeData({
    this.defaultTextStyle = const TextStyle(fontSize: 11, color: '212121'),
    this.fontName,
    this.paragraphStyle,
    this.header0,
    this.header1,
    this.header2,
    this.header3,
    this.header4,
    this.header5,
    this.tableHeader = const TextStyle(
      color: 'FFFFFF',
      fontWeight: FontWeight.bold,
      fontSize: 10,
    ),
    this.tableCell = const TextStyle(fontSize: 10),
    this.bulletStyle,
  });

  /// withFont API.
  factory ThemeData.withFont({String? base}) {
    return ThemeData(fontName: base);
  }

  /// Optional face name (the writer still embeds [Document.font]).
  final String? fontName;

  /// defaultTextStyle API.
  final TextStyle defaultTextStyle;

  /// paragraphStyle API.
  final TextStyle? paragraphStyle;

  /// header0 API.
  final TextStyle? header0;

  /// header1 API.
  final TextStyle? header1;

  /// header2 API.
  final TextStyle? header2;

  /// header3 API.
  final TextStyle? header3;

  /// header4 API.
  final TextStyle? header4;

  /// header5 API.
  final TextStyle? header5;

  /// Default style for [Table.fromTextArray] headers.
  final TextStyle tableHeader;

  /// Default style for [Table.fromTextArray] body cells.
  final TextStyle tableCell;

  /// Optional bullet text style.
  final TextStyle? bulletStyle;

  /// headerStyle API.
  TextStyle headerStyle(int level) {
    final TextStyle? named = switch (level) {
      0 => header0,
      1 => header1,
      2 => header2,
      3 => header3,
      4 => header4,
      _ => header5,
    };
    if (named != null) {
      return defaultTextStyle.merge(named);
    }
    final double size = switch (level) {
      0 => 26,
      1 => 20,
      2 => 16,
      3 => 13,
      4 => 12,
      _ => 11,
    };
    return defaultTextStyle.merge(
      TextStyle(
        fontSize: size,
        fontWeight: FontWeight.bold,
        color: '1A237E',
      ),
    );
  }

  /// copyWith API.
  ThemeData copyWith({
    TextStyle? defaultTextStyle,
    TextStyle? paragraphStyle,
    TextStyle? tableHeader,
    TextStyle? tableCell,
    TextStyle? bulletStyle,
  }) {
    return ThemeData(
      defaultTextStyle: defaultTextStyle ?? this.defaultTextStyle,
      fontName: fontName,
      paragraphStyle: paragraphStyle ?? this.paragraphStyle,
      header0: header0,
      header1: header1,
      header2: header2,
      header3: header3,
      header4: header4,
      header5: header5,
      tableHeader: tableHeader ?? this.tableHeader,
      tableCell: tableCell ?? this.tableCell,
      bulletStyle: bulletStyle ?? this.bulletStyle,
    );
  }
}
