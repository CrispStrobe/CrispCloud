import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';

/// An owned, immutable PDF snapshot. Passwords are never included in metadata.
class PdfInput {
  PdfInput(Uint8List bytes,
      {this.name = 'document.pdf', this.password = ''})
      : bytes = Uint8List.fromList(bytes).asUnmodifiableView();

  final Uint8List bytes;
  final String name;
  final String password;
}

/// One merge source and its one-based page selection, in the requested order.
class PdfMergeInput {
  const PdfMergeInput(this.input, {this.pages = 'all'});

  final PdfInput input;
  final String pages;
}

/// A machine-readable failure. [fieldErrors] contains field names, not values.
class PdfOperationException implements Exception {
  PdfOperationException(this.code, this.message,
      {Map<String, String> fieldErrors = const {}})
      : fieldErrors = Map.unmodifiable(fieldErrors);

  final String code;
  final String message;
  final Map<String, String> fieldErrors;

  Map<String, Object?> toJson() => {
        'code': code,
        'message': message,
        if (fieldErrors.isNotEmpty) 'fieldErrors': fieldErrors,
      };

  @override
  String toString() => message;
}

class PdfOperationResult {
  PdfOperationResult({
    required Uint8List bytes,
    required this.pageCount,
    List<String> warnings = const [],
    List<String> filledFields = const [],
  })  : bytes = Uint8List.fromList(bytes).asUnmodifiableView(),
        warnings = List.unmodifiable(warnings),
        filledFields = List.unmodifiable(filledFields);

  final Uint8List bytes;
  final int pageCount;
  final List<String> warnings;
  final List<String> filledFields;

  /// Result metadata only; never serializes the PDF or any password.
  Map<String, Object?> toJson() => {
        'pageCount': pageCount,
        'byteLength': bytes.length,
        'warnings': warnings,
        if (filledFields.isNotEmpty) 'filledFields': filledFields,
      };
}

class PdfInspection {
  PdfInspection({
    required this.pageCount,
    required this.encrypted,
    required this.hasSignatures,
    required this.hasXfa,
    required List<PdfPageDescription> pages,
    required List<PdfFormFieldDescription> fields,
    List<String> warnings = const [],
  })  : pages = List.unmodifiable(pages),
        fields = List.unmodifiable(fields),
        warnings = List.unmodifiable(warnings);

  final int pageCount;
  final bool encrypted;
  final bool hasSignatures;
  final bool hasXfa;
  final List<PdfPageDescription> pages;
  final List<PdfFormFieldDescription> fields;
  final List<String> warnings;

  Map<String, Object?> toJson() => {
        'pageCount': pageCount,
        'encrypted': encrypted,
        'hasSignatures': hasSignatures,
        'hasXfa': hasXfa,
        'pages': [for (final page in pages) page.toJson()],
        'fields': [for (final field in fields) field.toJson()],
        'warnings': warnings,
      };
}

class PdfPageDescription {
  const PdfPageDescription({
    required this.pageIndex,
    required this.width,
    required this.height,
    required this.rotation,
    required this.cropBox,
  });

  /// Zero-based page index. JSON also carries the human-facing `page` number.
  final int pageIndex;

  /// Displayed crop-box dimensions in points, accounting for page rotation.
  final double width;
  final double height;
  final int rotation;
  final PdfRect cropBox;

  Map<String, Object?> toJson() => {
        'page': pageIndex + 1,
        'pageIndex': pageIndex,
        'width': width,
        'height': height,
        'rotation': rotation,
        'cropBox': rectToJson(cropBox),
      };
}

class PdfFormOption {
  const PdfFormOption({required this.value, required this.label});

  final String value;
  final String label;

  Map<String, Object?> toJson() => {'value': value, 'label': label};
}

class PdfFormFieldDescription {
  PdfFormFieldDescription({
    required this.name,
    required this.type,
    required this.readOnly,
    required this.required,
    required this.password,
    required this.multiSelect,
    required this.editableChoice,
    required List<PdfFormOption> options,
    required List<String> onStates,
    required List<int> pageIndices,
    required List<String> values,
    this.maxLength,
  })  : options = List.unmodifiable(options),
        onStates = List.unmodifiable(onStates),
        pageIndices = List.unmodifiable(pageIndices),
        values = List.unmodifiable(values);

  final String name;
  final String type;
  final bool readOnly;
  final bool required;
  final bool password;
  final bool multiSelect;
  final bool editableChoice;
  final int? maxLength;
  final List<PdfFormOption> options;
  final List<String> onStates;
  final List<int> pageIndices;

  /// Password-field values are always omitted, including pre-existing values.
  final List<String> values;

  Map<String, Object?> toJson() => {
        'name': name,
        'type': type,
        'readOnly': readOnly,
        'required': required,
        'password': password,
        'multiSelect': multiSelect,
        'editableChoice': editableChoice,
        if (maxLength != null) 'maxLength': maxLength,
        'options': [for (final option in options) option.toJson()],
        'onStates': onStates,
        'pages': [for (final index in pageIndices) index + 1],
        'pageIndices': pageIndices,
        if (!password) 'values': values,
      };
}

enum PdfPlacementAnchor {
  topLeft,
  topCenter,
  topRight,
  centerLeft,
  center,
  centerRight,
  bottomLeft,
  bottomCenter,
  bottomRight,
}

/// A foreground watermark. Exactly one of [text] and [imageBytes] is required.
class PdfWatermarkOptions {
  const PdfWatermarkOptions({
    this.text,
    this.imageBytes,
    this.fontSize = 36,
    this.opacity = .2,
    this.angleDegrees = -35,
    this.color = 0x808080,
    this.anchor = PdfPlacementAnchor.center,
    this.widthFraction = .65,
    this.margin = 24,
    this.flatten = true,
    this.font,
  });

  final String? text;
  final Uint8List? imageBytes;
  final double fontSize;
  final double opacity;

  /// Positive angles turn clockwise in the displayed page.
  final double angleDegrees;
  final int color;
  final PdfPlacementAnchor anchor;

  /// Maximum width relative to the displayed page, before rotation.
  final double widthFraction;
  final double margin;

  /// Bake only this newly added mark into page content; leave forms/comments.
  final bool flatten;
  final PdfEmbeddedFont? font;
}

/// A box in the displayed crop area, with a top-left origin and unit fractions.
class PdfImagePlacement {
  const PdfImagePlacement({
    this.x = .1,
    this.y = .1,
    this.width = .3,
    this.height,
    this.opacity = 1,
    this.angleDegrees = 0,
    this.flatten = true,
  });

  final double x;
  final double y;
  final double width;

  /// Null retains the image's aspect ratio; otherwise uses this box height.
  final double? height;
  final double opacity;
  final double angleDegrees;
  final bool flatten;
}

class PdfPageTextResult {
  const PdfPageTextResult({required this.pageIndex, required this.text});

  final int pageIndex;
  final String text;

  Map<String, Object?> toJson() => {
        'page': pageIndex + 1,
        'pageIndex': pageIndex,
        'text': text,
      };
}

class PdfSearchResult {
  PdfSearchResult({
    required this.pageIndex,
    required this.start,
    required this.end,
    required this.text,
    required List<PdfRect> bounds,
  }) : bounds = List.unmodifiable(bounds);

  final int pageIndex;
  final int start;
  final int end;
  final String text;
  final List<PdfRect> bounds;

  Map<String, Object?> toJson() => {
        'page': pageIndex + 1,
        'pageIndex': pageIndex,
        'start': start,
        'end': end,
        'text': text,
        'bounds': [for (final rect in bounds) rectToJson(rect)],
      };
}

/// Recognition for one page, in PDF point coordinates (bottom-left origin).
class PdfOcrPage {
  PdfOcrPage({required this.pageIndex, required List<PdfOcrSpan> spans})
      : spans = List.unmodifiable(spans);

  final int pageIndex;
  final List<PdfOcrSpan> spans;

  /// JSON uses one-based `page` numbers and `[left,bottom,right,top]` bounds.
  factory PdfOcrPage.fromJson(Map<String, Object?> json) {
    final page = json['page'];
    final raw = json['spans'];
    if (page is! int || page < 1 || raw is! List) {
      throw PdfOperationException('invalidOcr',
          'OCR pages require a positive integer page and a spans array.');
    }
    final spans = <PdfOcrSpan>[];
    for (final item in raw) {
      if (item is! Map) {
        throw PdfOperationException('invalidOcr', 'Invalid OCR span.');
      }
      final text = item['text'];
      final box = item['bounds'];
      final confidence = item['confidence'] ?? 1;
      if (text is! String ||
          box is! List ||
          box.length != 4 ||
          box.any((value) => value is! num || !value.isFinite) ||
          confidence is! num ||
          !confidence.isFinite ||
          confidence < 0 ||
          confidence > 1) {
        throw PdfOperationException('invalidOcr',
            'OCR spans require text, four finite bounds, and confidence 0–1.');
      }
      final coordinates = [for (final value in box) (value as num).toDouble()];
      final bounds = PdfRect(coordinates[0], coordinates[1],
          coordinates[2], coordinates[3]);
      if (bounds.width <= 0 || bounds.height <= 0) {
        throw PdfOperationException('invalidOcr',
            'OCR span bounds must have positive width and height.');
      }
      spans.add(PdfOcrSpan(
          text: text, bounds: bounds, confidence: confidence.toDouble()));
    }
    return PdfOcrPage(pageIndex: page - 1, spans: spans);
  }

  Map<String, Object?> toJson() => {
        'page': pageIndex + 1,
        'spans': [
          for (final span in spans)
            {
              'text': span.text,
              'bounds': rectToJson(span.bounds),
              'confidence': span.confidence,
            },
        ],
      };
}

/// An optional OCR backend seam. The host owns rasterization and transport.
///
/// Recognition coordinates must refer to the supplied document's PDF space.
/// No model, network request, or image renderer is included in this package.
abstract interface class PdfRecognitionBackend {
  Future<List<PdfOcrPage>> recognize(
      PdfInput input, List<int> pageIndices);
}

List<double> rectToJson(PdfRect rect) =>
    [rect.left, rect.bottom, rect.right, rect.top];
