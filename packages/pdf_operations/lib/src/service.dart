import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart' hide PdfPageRange;
import 'package:pdf_graphics/pdf_graphics.dart';

import 'models.dart';
import 'page_range.dart';

/// Reusable, synchronous PDF operations with no storage or UI dependency.
///
/// Hosts should run larger jobs outside the UI isolate and save a returned
/// snapshot only after reviewing [PdfOperationResult.warnings]. These methods
/// never modify [PdfInput.bytes] or persist any output. Signed originals should
/// always be kept separately; a source signature does not certify a new edit.
class PdfOperationsService {
  const PdfOperationsService({
    this.maxInputBytes = 64 * 1024 * 1024,
    this.maxOutputBytes = 128 * 1024 * 1024,
    this.maxTotalInputBytes = 256 * 1024 * 1024,
    this.maxPageCount = 10000,
    this.maxImagePixels = 32 * 1024 * 1024,
    this.maxTextCharacters = 16 * 1024 * 1024,
  });

  final int maxInputBytes;
  final int maxOutputBytes;
  final int maxTotalInputBytes;
  final int maxPageCount;
  final int maxImagePixels;
  final int maxTextCharacters;

  PdfInspection inspect(PdfInput input) {
    final document = _open(input);
    final form = PdfAcroForm.of(document);
    return PdfInspection(
      pageCount: document.pageCount,
      encrypted: document.cos.isEncrypted,
      hasSignatures: PdfSignature.of(document).isNotEmpty,
      hasXfa: _hasXfa(document),
      pages: [
        for (var i = 0; i < document.pageCount; i++)
          _describePage(document.page(i), i),
      ],
      fields: [
        for (final field in form?.fields ?? const <PdfFormField>[])
          PdfFormFieldDescription(
            name: field.name,
            type: field.type.name,
            readOnly: field.isReadOnly,
            required: field.isRequired,
            password: field.isPassword,
            multiSelect: field.isMultiSelect,
            editableChoice: _editableChoice(field),
            multiline: field.isMultiline,
            maxLength: field.maxLength,
            options: [
              for (final option in field.options)
                PdfFormOption(value: option.$1, label: option.$2),
            ],
            onStates: field.onStates,
            pageIndices: {
              for (var i = 0; i < field.widgets.length; i++)
                if (field.widgetPageIndex(i) >= 0) field.widgetPageIndex(i),
            }.toList()
              ..sort(),
            values: field.isPassword ? const [] : field.values,
          ),
      ],
      warnings: _sourceWarnings(document),
    );
  }

  /// Merge in the exact input/page order. The first whole PDF is the base.
  ///
  /// A first-input subset is extracted into a fresh PDF. That extraction, or
  /// importing a protected source into an unprotected base, requires explicit
  /// [allowDecryption]. Later sources are encrypted using the base's policy.
  PdfOperationResult merge(List<PdfMergeInput> inputs,
      {bool allowDecryption = false}) {
    if (inputs.isEmpty) {
      throw PdfOperationException('invalidInputs', 'Select at least one PDF.');
    }
    final total =
        inputs.fold<int>(0, (n, source) => n + source.input.bytes.length);
    if (total > maxTotalInputBytes) {
      throw PdfOperationException('totalInputLimit',
          'The combined PDF inputs exceed the configured memory limit.');
    }
    final documents = [
      for (final source in inputs) _open(source.input, edit: true)
    ];
    final selections = [
      for (var i = 0; i < inputs.length; i++)
        PdfPageRange.parse(inputs[i].pages, documents[i].pageCount),
    ];
    final pageCount = selections.fold<int>(0, (n, pages) => n + pages.length);
    _checkPageCount(pageCount);
    final firstIsWhole = selections.first.length == documents.first.pageCount;
    final outputEncrypted = firstIsWhole && documents.first.cos.isEncrypted;
    final decrypting = !outputEncrypted &&
        documents.any((document) => document.cos.isEncrypted);
    if (decrypting && !allowDecryption) _requireDecryption();
    final warnings = <String>[
      for (final document in documents) ..._sourceWarnings(document),
      if (decrypting)
        'The merged PDF is unencrypted. Source passwords are not retained.',
      if (outputEncrypted && inputs.length > 1)
        'All imported pages use the first PDF’s encryption and password.',
      if (inputs.length > 1)
        'The first PDF supplies document metadata. Later attachments and '
            'document JavaScript are not merged; colliding form field names '
            'and named destinations are renamed.',
      if (selections
          .asMap()
          .entries
          .any((entry) => entry.value.length != documents[entry.key].pageCount))
        'Links or bookmarks targeting pages outside the selection may be removed.',
    ];
    final PdfDocument base;
    if (firstIsWhole) {
      base = documents.first;
    } else {
      final bytes = documents.first.extractPages(selections.first);
      _checkOutputLength(bytes.length);
      base = PdfDocument.open(bytes);
      warnings.add(_extractionWarning);
    }
    final editor = PdfEditor(base);
    if (firstIsWhole && !_isNaturalOrder(selections.first)) {
      editor.reorderPages(selections.first);
    }
    for (var i = 1; i < documents.length; i++) {
      editor.appendPagesFrom(documents[i], indices: selections[i]);
    }
    return _finish(editor, warnings);
  }

  PdfOperationResult extract(PdfInput input,
      {required String pages, bool allowDecryption = false}) {
    final document = _open(input, edit: true);
    final indices = PdfPageRange.parse(pages, document.pageCount);
    if (document.cos.isEncrypted && !allowDecryption) _requireDecryption();
    final output = document.extractPages(indices);
    return _result(output, indices.length, [
      ..._sourceWarnings(document),
      _extractionWarning,
      if (document.cos.isEncrypted)
        'The extracted PDF is unencrypted. The source password is not retained.',
    ]);
  }

  PdfOperationResult rotate(PdfInput input,
      {String pages = 'all', int degrees = 90}) {
    if (degrees % 90 != 0) {
      throw PdfOperationException(
          'invalidRotation', 'Page rotation must be a multiple of 90 degrees.');
    }
    final document = _open(input, edit: true);
    final indices = PdfPageRange.parse(pages, document.pageCount);
    final warnings = _sourceWarnings(document);
    final editor = PdfEditor(document)..rotatePages(indices, degrees);
    return _finish(editor, warnings);
  }

  PdfOperationResult reorder(PdfInput input, {required String pages}) {
    final document = _open(input, edit: true);
    final indices = PdfPageRange.parse(pages, document.pageCount);
    if (indices.length != document.pageCount) {
      throw PdfOperationException('invalidPages',
          'Reordering requires every page exactly once. Use extraction for a subset.');
    }
    final warnings = _sourceWarnings(document);
    final editor = PdfEditor(document)..reorderPages(indices);
    return _finish(editor, warnings);
  }

  PdfOperationResult deletePages(PdfInput input, {required String pages}) {
    final document = _open(input, edit: true);
    final indices = PdfPageRange.parse(pages, document.pageCount);
    if (indices.length >= document.pageCount) {
      throw PdfOperationException(
          'invalidPages', 'At least one page must remain in the PDF.');
    }
    final warnings = [
      ..._sourceWarnings(document),
      'Page deletion changes the page tree. Removed pages can remain in '
          'the file’s incremental history; this is not secure erasure.',
    ];
    final editor = PdfEditor(document)..removePages(indices);
    return _finish(editor, warnings);
  }

  List<PdfPageTextResult> text(PdfInput input, {String pages = 'all'}) {
    final document = _open(input);
    final indices = PdfPageRange.parse(pages, document.pageCount);
    var characters = 0;
    final result = <PdfPageTextResult>[];
    for (final index in indices) {
      final extracted = PdfTextExtractor.extract(document, index);
      characters += extracted.text.length;
      _checkTextLength(characters);
      result.add(PdfPageTextResult(pageIndex: index, text: extracted.text));
    }
    return List.unmodifiable(result);
  }

  List<PdfSearchResult> search(PdfInput input,
      {required String query,
      String pages = 'all',
      bool caseSensitive = false,
      bool regex = false,
      bool wholeWord = false}) {
    if (query.isEmpty || query.length > 4096) {
      throw PdfOperationException('invalidSearch',
          'Search text must contain between 1 and 4096 characters.');
    }
    if (regex) {
      try {
        RegExp(query, caseSensitive: caseSensitive, multiLine: true);
      } on FormatException {
        throw PdfOperationException(
            'invalidSearch', 'Invalid regular expression.');
      }
    }
    final document = _open(input);
    final indices = PdfPageRange.parse(pages, document.pageCount);
    final result = <PdfSearchResult>[];
    var characters = 0;
    for (final index in indices) {
      final extracted = PdfTextExtractor.extract(document, index);
      characters += extracted.text.length;
      _checkTextLength(characters);
      for (final match in extracted.findAll(query,
          caseSensitive: caseSensitive, regex: regex, wholeWord: wholeWord)) {
        if (result.length >= 10000) {
          throw PdfOperationException('searchLimit',
              'More than 10,000 matches. Narrow the query or page range.');
        }
        result.add(PdfSearchResult(
            pageIndex: index,
            start: match.start,
            end: match.end,
            text: extracted.text.substring(match.start, match.end),
            bounds: match.rects));
      }
    }
    return List.unmodifiable(result);
  }

  /// Fill a named AcroForm map, validating every requested value before edit.
  ///
  /// Text uses recognized Acrobat keystroke/validation helpers. Arbitrary
  /// JavaScript is never executed. Checkboxes are set to a bool, never toggled.
  /// Field names, types, option values, glyph coverage and length limits must
  /// match; failures return no partially filled PDF. Password fields, computed
  /// fields, signatures, push buttons and read-only fields are rejected.
  PdfOperationResult fillForm(PdfInput input,
      {required Map<String, Object?> values, PdfEmbeddedFont? appearanceFont}) {
    final document = _open(input, edit: true);
    final form = PdfAcroForm.of(document);
    if (form == null || form.fields.isEmpty) {
      throw PdfOperationException('invalidForm',
          'This PDF has no named AcroForm fields. Positioned text is a separate operation.');
    }
    if (values.isEmpty) {
      throw PdfOperationException(
          'invalidForm', 'Provide at least one field value.');
    }
    final byName = <String, List<PdfFormField>>{};
    for (final field in form.fields) {
      byName.putIfAbsent(field.name, () => []).add(field);
    }
    final errors = <String, String>{};
    final normalized = <String, Object>{};
    for (final entry in values.entries) {
      final candidates = byName[entry.key];
      if (candidates == null) {
        errors[entry.key] = 'Unknown field name.';
        continue;
      }
      if (candidates.length != 1) {
        errors[entry.key] = 'The field name is ambiguous in this PDF.';
        continue;
      }
      final field = candidates.single;
      try {
        normalized[entry.key] =
            _validateField(field, entry.value, appearanceFont);
      } on PdfOperationException catch (error) {
        errors[entry.key] = error.message;
      }
    }
    if (errors.isNotEmpty) {
      throw PdfOperationException('invalidForm',
          'Some form values could not be applied. No output was produced.',
          fieldErrors: errors);
    }
    final warnings = _sourceWarnings(document);
    final editor = PdfEditor(document);
    for (final entry in normalized.entries) {
      final field = byName[entry.key]!.single;
      switch (field.type) {
        case PdfFieldType.text:
          if (appearanceFont != null) {
            editor.setTextFieldStyle(field, font: appearanceFont);
          }
          // The complete map passed checkInput above; write normalized values
          // directly so validation is not run twice with time-varying scripts.
          editor.setTextValue(field, entry.value as String);
        case PdfFieldType.checkBox:
          editor.setCheckBoxValue(field, entry.value as bool);
        case PdfFieldType.radioGroup:
          editor.setRadioValue(field, entry.value as String);
        case PdfFieldType.comboBox || PdfFieldType.listBox:
          if (appearanceFont != null) {
            editor.setChoiceFieldStyle(field, font: appearanceFont);
          }
          if (entry.value is List<String>) {
            editor.setChoiceValues(field, entry.value as List<String>);
          } else {
            editor.setChoiceValue(field, entry.value as String);
          }
        default:
          throw StateError('A non-fillable field passed validation.');
      }
    }
    final calculated = editor.recalculateFields();
    for (final calculation in calculated) {
      final field = calculation.field;
      _checkFieldAppearance(field, field.displayFor(calculation.value).text);
    }
    if (form.fields.any((field) => field.scripts.hasUnsupported)) {
      warnings.add('Unsupported form JavaScript was not executed.');
    }
    final authored = [
      for (final entry in normalized.entries)
        if (byName[entry.key]!.single.type == PdfFieldType.text)
          byName[entry.key]!.single.displayFor(entry.value as String).text
        else if (byName[entry.key]!.single.type == PdfFieldType.comboBox ||
            byName[entry.key]!.single.type == PdfFieldType.listBox) ...[
          if (entry.value is String) entry.value as String,
          if (entry.value is List<String>) ...(entry.value as List<String>),
          for (final option in byName[entry.key]!.single.options) option.$2,
        ],
      for (final calculation in calculated)
        calculation.field.displayFor(calculation.value).text,
    ].join(' ');
    if (_needsComplexShaping(authored)) warnings.add(_shapingWarning);
    return _finish(editor, warnings, filledFields: normalized.keys.toList());
  }

  PdfOperationResult watermark(PdfInput input,
      {required PdfWatermarkOptions watermark, String pages = 'all'}) {
    _validateWatermark(watermark);
    final document = _open(input, edit: true);
    final indices = PdfPageRange.parse(pages, document.pageCount);
    final image = watermark.imageBytes == null
        ? null
        : _decodeImage(watermark.imageBytes!);
    if (watermark.text != null) {
      _checkAuthoredText(watermark.text!, watermark.font);
    }
    final placements = [
      for (final index in indices)
        _watermarkPlacement(document.page(index), index, watermark, image),
    ];
    final warnings = _sourceWarnings(document);
    if (_needsComplexShaping(watermark.text ?? ''))
      warnings.add(_shapingWarning);
    final editor = PdfEditor(document);
    final names = _annotationNames(document);
    for (final placement in placements) {
      final name = _nextAnnotationName(names, 'watermark');
      if (image != null) {
        editor.addImageStamp(placement.pageIndex, placement.rect, image,
            opacity: watermark.opacity, name: name);
      } else {
        editor.addFreeText(
          placement.pageIndex,
          placement.rect,
          watermark.text!,
          fontSize: placement.fontSize,
          font: watermark.font ?? PdfStandardFont.helvetica,
          align: PdfTextAlign.center,
          verticalAlign: PdfTextVerticalAlign.center,
          color: watermark.color,
          borderWidth: 0,
          opacity: watermark.opacity,
          name: name,
        );
      }
      _finishMark(editor, placement.pageIndex, name, watermark.angleDegrees,
          watermark.flatten);
    }
    return _finish(editor, warnings);
  }

  PdfOperationResult insertImage(PdfInput input,
      {required Uint8List imageBytes,
      required PdfImagePlacement placement,
      String pages = '1'}) {
    _validateImagePlacement(placement);
    final image = _decodeImage(imageBytes);
    final document = _open(input, edit: true);
    final indices = PdfPageRange.parse(pages, document.pageCount);
    final boxes = <int, PdfRect>{};
    var clipped = false;
    for (final index in indices) {
      final page = document.page(index);
      final geometry = _geometry(page);
      final x = geometry.width * placement.x;
      final y = geometry.height * placement.y;
      final width = geometry.width * placement.width;
      final height = placement.height == null
          ? width * image.height / image.width
          : geometry.height * placement.height!;
      if (y + height > geometry.height + 1e-7) {
        throw PdfOperationException('invalidPlacement',
            'The image extends below page ${index + 1}. Reduce its width or height.');
      }
      final (rotatedWidth, rotatedHeight) =
          _rotatedSize(width, height, placement.angleDegrees);
      final centerX = x + width / 2;
      final centerY = y + height / 2;
      clipped |= centerX - rotatedWidth / 2 < 0 ||
          centerY - rotatedHeight / 2 < 0 ||
          centerX + rotatedWidth / 2 > geometry.width ||
          centerY + rotatedHeight / 2 > geometry.height;
      boxes[index] = _visualRect(page, x, y, width, height);
    }
    final warnings = [
      ..._sourceWarnings(document),
      if (clipped)
        'Part of the rotated image lies outside the visible page and is clipped.',
    ];
    final editor = PdfEditor(document);
    final names = _annotationNames(document);
    for (final entry in boxes.entries) {
      final name = _nextAnnotationName(names, 'image');
      editor.addImageStamp(entry.key, entry.value, image,
          opacity: placement.opacity, name: name);
      _finishMark(
          editor, entry.key, name, placement.angleDegrees, placement.flatten);
    }
    return _finish(editor, warnings);
  }

  /// Apply externally recognized text; this method performs no recognition.
  PdfOperationResult applyOcr(PdfInput input,
      {required List<PdfOcrPage> pages,
      PdfEmbeddedFont? font,
      bool skipExistingText = true,
      double minConfidence = 0}) {
    if (!minConfidence.isFinite || minConfidence < 0 || minConfidence > 1) {
      throw PdfOperationException(
          'invalidOcr', 'Minimum confidence must be between 0 and 1.');
    }
    if (pages.isEmpty) {
      throw PdfOperationException(
          'invalidOcr', 'Provide recognition for at least one page.');
    }
    final document = _open(input, edit: true);
    final seen = <int>{};
    for (final page in pages) {
      if (page.pageIndex < 0 ||
          page.pageIndex >= document.pageCount ||
          !seen.add(page.pageIndex)) {
        throw PdfOperationException('invalidOcr',
            'OCR page indices must be unique and in the document.');
      }
      for (final span in page.spans) {
        if (!span.confidence.isFinite ||
            span.confidence < 0 ||
            span.confidence > 1 ||
            !rectToJson(span.bounds).every((number) => number.isFinite) ||
            span.bounds.width <= 0 ||
            span.bounds.height <= 0) {
          throw PdfOperationException('invalidOcr',
              'OCR spans require finite positive bounds and confidence 0–1.');
        }
        if (span.confidence >= minConfidence)
          _checkAuthoredText(span.text, font);
      }
    }
    final warnings = _sourceWarnings(document);
    final editor = PdfEditor(document);
    for (final page in pages) {
      if (skipExistingText &&
          PdfTextExtractor.extract(document, page.pageIndex)
              .text
              .trim()
              .isNotEmpty) {
        warnings.add(
            'Page ${page.pageIndex + 1} already has text; OCR was skipped.');
        continue;
      }
      editor.injectTextLayer(page.pageIndex, page.spans,
          embeddedFont: font, minConfidence: minConfidence);
    }
    warnings.add(
        'The searchable text reflects the supplied recognition. Review OCR accuracy before relying on it.');
    return _finish(editor, warnings);
  }

  /// Optional backend orchestration; the caller provides and authorizes it.
  Future<PdfOperationResult> recognize(PdfInput input,
      {required PdfRecognitionBackend backend,
      String pages = 'all',
      PdfEmbeddedFont? font,
      bool skipExistingText = true,
      double minConfidence = 0}) async {
    final document = _open(input, edit: true);
    final indices = PdfPageRange.parse(pages, document.pageCount);
    final recognized = await backend.recognize(input, indices);
    if (recognized.any((page) => !indices.contains(page.pageIndex))) {
      throw PdfOperationException(
          'invalidOcr', 'The OCR backend returned an unrequested page.');
    }
    return applyOcr(input,
        pages: recognized,
        font: font,
        skipExistingText: skipExistingText,
        minConfidence: minConfidence);
  }

  PdfDocument _open(PdfInput input, {bool edit = false}) {
    if (input.bytes.isEmpty || input.bytes.length > maxInputBytes) {
      throw PdfOperationException('inputLimit',
          'The PDF is empty or exceeds the configured input limit.');
    }
    final PdfDocument document;
    try {
      document = PdfDocument.open(input.bytes, password: input.password);
    } on CosPasswordException {
      throw PdfOperationException(
          input.password.isEmpty ? 'passwordRequired' : 'invalidPassword',
          input.password.isEmpty
              ? 'This PDF requires a password.'
              : 'The PDF password is incorrect.');
    } on CosParseException {
      throw PdfOperationException(
          'invalidPdf', 'The file could not be read as a PDF.');
    } on UnsupportedEncryptionException {
      throw PdfOperationException('unsupportedEncryption',
          'This PDF uses an unsupported encryption method.');
    }
    _checkPageCount(document.pageCount);
    if (edit && _hasXfa(document)) {
      throw PdfOperationException('unsupportedXfa',
          'XFA forms cannot be edited by these operations. Use an AcroForm or ordinary PDF.');
    }
    return document;
  }

  bool _hasXfa(PdfDocument document) {
    final form = PdfAcroForm.of(document);
    return form?.hasXfa == true || form?.xfaNeedsRendering == true;
  }

  void _checkPageCount(int count) {
    if (count < 1 || count > maxPageCount) {
      throw PdfOperationException('pageLimit',
          'The PDF must contain between 1 and $maxPageCount pages.');
    }
  }

  void _checkOutputLength(int bytes) {
    if (bytes > maxOutputBytes) {
      throw PdfOperationException(
          'outputLimit', 'The PDF result exceeds the configured output limit.');
    }
  }

  void _checkTextLength(int length) {
    if (length > maxTextCharacters) {
      throw PdfOperationException('textLimit',
          'The extracted text exceeds the configured limit. Select fewer pages.');
    }
  }

  Never _requireDecryption() => throw PdfOperationException(
      'decryptionRequired',
      'This operation would create an unencrypted PDF. Explicitly allow unencrypted output to continue.');

  List<String> _sourceWarnings(PdfDocument document) => [
        if (PdfSignature.of(document).isNotEmpty)
          'Keep the signed original. Its signatures do not certify the modified or extracted PDF.',
        if (_hasXfa(document)) 'XFA forms are not supported for editing.',
      ];

  static const _extractionWarning =
      'Extraction creates a new PDF. Attachments, document JavaScript and '
      'signature validity are not preserved; links to omitted pages may be removed.';
  static const _shapingWarning =
      'This text uses a script that may require shaping beyond the PDF writer’s '
      'supported layout. Verify the visible text in the output.';

  PdfOperationResult _finish(PdfEditor editor, List<String> warnings,
          {List<String> filledFields = const []}) =>
      _result(editor.hasChanges ? editor.save() : editor.document.cos.bytes,
          editor.document.pageCount, warnings,
          filledFields: filledFields);

  PdfOperationResult _result(
      Uint8List bytes, int pageCount, List<String> warnings,
      {List<String> filledFields = const []}) {
    _checkOutputLength(bytes.length);
    _checkPageCount(pageCount);
    return PdfOperationResult(
        bytes: bytes,
        pageCount: pageCount,
        warnings: warnings.toSet().toList(),
        filledFields: filledFields);
  }

  bool _isNaturalOrder(List<int> pages) {
    for (var i = 0; i < pages.length; i++) {
      if (pages[i] != i) return false;
    }
    return true;
  }

  PdfPageDescription _describePage(PdfPage page, int index) {
    final geometry = _geometry(page);
    return PdfPageDescription(
        pageIndex: index,
        width: geometry.width,
        height: geometry.height,
        rotation: page.rotation,
        cropBox: page.cropBox);
  }

  ({double width, double height}) _geometry(PdfPage page) {
    final box = page.cropBox;
    if (!rectToJson(box).every((number) => number.isFinite) ||
        box.width <= 0 ||
        box.height <= 0) {
      throw PdfOperationException(
          'invalidGeometry', 'The PDF contains an invalid page crop box.');
    }
    final sideways = page.rotation == 90 || page.rotation == 270;
    return (
      width: sideways ? box.height : box.width,
      height: sideways ? box.width : box.height
    );
  }

  bool _editableChoice(PdfFormField field) =>
      field.type == PdfFieldType.comboBox &&
      field.flags & PdfFormField.editFlag != 0;

  Object _validateField(
      PdfFormField field, Object? value, PdfEmbeddedFont? font) {
    Never fail(String message) =>
        throw PdfOperationException('invalidForm', message);
    if (field.isReadOnly) fail('The field is read-only.');
    if (field.isPassword)
      fail('Password field values are not written by batch filling.');
    if (field.scripts.hasUnsupported)
      fail('The field uses an unsupported form script.');
    if (field.scripts.calculate != null)
      fail('The field is calculated; fill its source fields instead.');
    switch (field.type) {
      case PdfFieldType.text:
        if (value is! String) fail('A text field requires a string.');
        final check = field.checkInput(value);
        if (!check.isValid)
          fail('The field’s validation rule rejected this value.');
        final normalized = check.value;
        if (field.isRequired && normalized.trim().isEmpty)
          fail('The field is required.');
        if (field.maxLength != null &&
            normalized.runes.length > field.maxLength!) {
          fail('The value exceeds the field’s maximum length.');
        }
        if (!field.isMultiline && normalized.contains(RegExp(r'[\r\n]'))) {
          fail('A single-line field cannot contain line breaks.');
        }
        _checkFieldAppearance(field, field.displayFor(normalized).text, font);
        return normalized;
      case PdfFieldType.checkBox:
        if (value is! bool) fail('A checkbox requires true or false.');
        if (field.isRequired && !value)
          fail('This required checkbox must be checked.');
        return value;
      case PdfFieldType.radioGroup:
        if (value is! String ||
            (value != 'Off' && !field.onStates.contains(value))) {
          fail('Use one of the radio field’s on-state names, or Off.');
        }
        if (value == 'Off' &&
            (field.isRequired ||
                field.flags & PdfFormField.noToggleToOffFlag != 0)) {
          fail('This radio group cannot be cleared.');
        }
        return value;
      case PdfFieldType.comboBox || PdfFieldType.listBox:
        final List<String> requested;
        if (field.isMultiSelect) {
          if (value is! List || value.any((item) => item is! String)) {
            fail('A multi-select field requires an array of strings.');
          }
          requested = value.cast<String>();
        } else {
          if (value is! String) fail('This choice field requires a string.');
          requested = [value];
        }
        if (field.isRequired &&
            (requested.isEmpty || requested.every((item) => item.isEmpty))) {
          fail('The field is required.');
        }
        final labels = <String>[];
        final normalized = <String>[];
        for (final item in requested) {
          final options = field.options
              .where((option) => option.$1 == item || option.$2 == item)
              .toList();
          if (options.isEmpty) {
            if (!_editableChoice(field))
              fail('A choice value is not one of the field’s options.');
            labels.add(item);
            normalized.add(item);
          } else if (options.length > 1 &&
              options.map((option) => option.$1).toSet().length > 1) {
            fail('A choice label is ambiguous; use its export value.');
          } else {
            labels.add(options.first.$2);
            normalized.add(options.first.$1);
          }
        }
        // A list-box appearance shows its other rows as well as the selected
        // ones, so all visible option labels need a working font.
        final displayed = field.type == PdfFieldType.listBox
            ? field.options.map((option) => option.$2).join('\n')
            : labels.join('\n');
        _checkFieldAppearance(field, displayed, font);
        return field.isMultiSelect
            ? normalized.toSet().toList()
            : normalized.single;
      default:
        fail('This field type cannot be filled from a value map.');
    }
  }

  ({String name, CosDictionary? dictionary}) _fieldFont(PdfFormField field) {
    // Match the editor's /DA choice: the last Tf wins, with Helv as its
    // fallback. Checking the first resource could validate a different font
    // from the one used to regenerate the field's visible appearance.
    var name = 'Helv';
    final tokens = (field.defaultAppearance ?? '').trim().split(RegExp(r'\s+'));
    for (var i = 2; i < tokens.length; i++) {
      if (tokens[i] == 'Tf' && tokens[i - 2].startsWith('/')) {
        name = tokens[i - 2].substring(1);
      }
    }
    final resources = field.form.defaultResources;
    if (resources == null) return (name: name, dictionary: null);
    final cos = field.form.document.cos;
    final fonts = cos.resolve(resources['Font']);
    if (fonts is! CosDictionary) return (name: name, dictionary: null);
    final dictionary = cos.resolve(fonts[name]);
    return (
      name: name,
      dictionary: dictionary is CosDictionary ? dictionary : null
    );
  }

  void _checkFieldAppearance(PdfFormField field, String text,
      [PdfEmbeddedFont? font]) {
    if (font != null) {
      _checkAuthoredText(text, font);
      return;
    }
    final resource = _fieldFont(field);
    final dictionary = resource.dictionary;
    final cos = field.form.document.cos;
    final embedded = dictionary == null
        ? null
        : PdfEmbeddedFont.fromFontDict(cos, dictionary, resource.name);
    _checkAuthoredText(text, embedded);
    if (embedded != null || dictionary == null) return;
    // The existing form appearance writer emits simple-font text as Latin-1
    // bytes. A subset /Differences map or /ToUnicode map can give those same
    // bytes entirely different meanings. Do not report a successful fill
    // whose visible/searchable text differs from the requested value.
    final encoding = cos.resolve(dictionary['Encoding']);
    final baseFont = cos.resolve(dictionary['BaseFont']);
    final isBase14 = baseFont is CosName &&
        PdfStandardFont.values.any((font) => font.baseFont == baseFont.value);
    if (!isBase14 ||
        cos.resolve(dictionary['Subtype']) != const CosName('Type1') ||
        encoding != const CosName('WinAnsiEncoding') ||
        dictionary.containsKey('ToUnicode')) {
      throw PdfOperationException(
          'unsupportedText',
          'The field uses a font encoding that cannot be safely regenerated. '
              'Provide a covering TTF or OTF appearance font.');
    }
  }

  void _checkAuthoredText(String text, PdfEmbeddedFont? font) {
    if (text.length > 100000) {
      throw PdfOperationException(
          'textLimit', 'An authored text value is too long.');
    }
    final printable = text.replaceAll(RegExp(r'[\r\n\t]'), ' ');
    if (printable.runes
        .any((rune) => rune < 32 || (rune >= 127 && rune < 160))) {
      throw PdfOperationException(
          'unsupportedText', 'Text contains unsupported control characters.');
    }
    if (font != null) {
      if (!font.canRender(printable)) {
        throw PdfOperationException('unsupportedText',
            'The selected font does not contain every required glyph. Choose a covering TTF or OTF font.');
      }
    } else if (printable.runes.any((rune) => rune > 255)) {
      throw PdfOperationException(
          'unsupportedText', 'This text requires an embedded TTF or OTF font.');
    }
  }

  bool _needsComplexShaping(String text) => text.runes.any((rune) =>
      (rune >= 0x0600 && rune <= 0x08ff) ||
      (rune >= 0x0900 && rune <= 0x0dff) ||
      (rune >= 0x0e00 && rune <= 0x109f) ||
      (rune >= 0x1780 && rune <= 0x17ff));

  void _validateWatermark(PdfWatermarkOptions options) {
    if ((options.text == null) == (options.imageBytes == null) ||
        options.text?.trim().isEmpty == true) {
      throw PdfOperationException('invalidWatermark',
          'Choose either non-empty watermark text or one PNG/JPEG image.');
    }
    if (!options.fontSize.isFinite ||
        options.fontSize <= 0 ||
        options.fontSize > 1000 ||
        !options.widthFraction.isFinite ||
        options.widthFraction <= 0 ||
        options.widthFraction > 1 ||
        !options.margin.isFinite ||
        options.margin < 0 ||
        options.color < 0 ||
        options.color > 0xffffff) {
      throw PdfOperationException('invalidWatermark',
          'Invalid watermark size, color, width, or margin.');
    }
    _checkAppearanceNumbers(options.opacity, options.angleDegrees);
  }

  void _validateImagePlacement(PdfImagePlacement placement) {
    if (![
          placement.x,
          placement.y,
          placement.width,
          if (placement.height != null) placement.height!
        ].every((number) => number.isFinite) ||
        placement.x < 0 ||
        placement.y < 0 ||
        placement.x >= 1 ||
        placement.y >= 1 ||
        placement.width <= 0 ||
        placement.x + placement.width > 1 ||
        (placement.height != null &&
            (placement.height! <= 0 || placement.y + placement.height! > 1))) {
      throw PdfOperationException('invalidPlacement',
          'Image coordinates are fractions of the visible page; the box must fit inside it.');
    }
    _checkAppearanceNumbers(placement.opacity, placement.angleDegrees);
  }

  void _checkAppearanceNumbers(double opacity, double angle) {
    if (!opacity.isFinite || opacity <= 0 || opacity > 1 || !angle.isFinite) {
      throw PdfOperationException('invalidAppearance',
          'Opacity must be greater than 0 and at most 1; rotation must be finite.');
    }
  }

  PdfEmbeddableImage _decodeImage(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxInputBytes) {
      throw PdfOperationException('inputLimit',
          'The image is empty or exceeds the configured input limit.');
    }
    try {
      final int width;
      final int height;
      const png = [137, 80, 78, 71, 13, 10, 26, 10];
      if (bytes.length >= 24 &&
          List.generate(8, (i) => bytes[i] == png[i]).every((match) => match)) {
        final data = ByteData.sublistView(bytes);
        width = data.getUint32(16);
        height = data.getUint32(20);
      } else {
        final info = readJpegInfo(bytes);
        width = info.width;
        height = info.height;
      }
      if (width <= 0 || height <= 0 || width * height > maxImagePixels) {
        throw PdfOperationException('imageLimit',
            'The image dimensions exceed the configured pixel limit.');
      }
      return PdfEmbeddableImage.decode(bytes);
    } on PdfOperationException {
      rethrow;
    } on Object {
      throw PdfOperationException('invalidImage',
          'The image could not be decoded as a supported PNG or JPEG.');
    }
  }

  _MarkPlacement _watermarkPlacement(PdfPage page, int index,
      PdfWatermarkOptions options, PdfEmbeddableImage? image) {
    final geometry = _geometry(page);
    final availableWidth = geometry.width - 2 * options.margin;
    final availableHeight = geometry.height - 2 * options.margin;
    if (availableWidth <= 6 || availableHeight <= 6) {
      throw PdfOperationException('invalidWatermark',
          'The watermark margin leaves no usable space on page ${index + 1}.');
    }
    var width =
        math.min(geometry.width * options.widthFraction, availableWidth);
    if (width <= 6) {
      throw PdfOperationException('invalidWatermark',
          'The watermark is too narrow on page ${index + 1}. Increase its width.');
    }
    var fontSize = options.fontSize;
    var lineCount = 1;
    var unitTextWidth = 0.0;
    double height;
    if (image != null) {
      height = width * image.height / image.width;
    } else {
      final lines = options.text!
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n')
          .split('\n');
      final font = options.font ?? PdfStandardFont.helvetica;
      lineCount = lines.length;
      unitTextWidth =
          lines.map((line) => font.measure(line, 1)).fold<double>(0, math.max);
      final measured = lines
          .map((line) => font.measure(line, fontSize))
          .fold<double>(0, math.max);
      if (measured > width - 6) fontSize *= (width - 6) / measured;
      height = lines.length * fontSize * 1.25 + 6;
    }
    final (rotatedWidth, rotatedHeight) =
        _rotatedSize(width, height, options.angleDegrees);
    final scale = math.min(
        1.0,
        math.min(
            availableWidth / rotatedWidth, availableHeight / rotatedHeight));
    width *= scale;
    height *= scale;
    fontSize *= scale;
    if (image == null) {
      // FreeText uses fixed three-point padding, even after fitting the rotated
      // mark. Account for that padding again so long/multiline text is not
      // silently clipped when the complete mark had to shrink.
      if (width <= 6 || height <= 6) {
        throw PdfOperationException('invalidWatermark',
            'The watermark text does not fit page ${index + 1}.');
      }
      fontSize = math.min(fontSize, (height - 6) / (lineCount * 1.25));
      if (unitTextWidth > 0)
        fontSize = math.min(fontSize, (width - 6) / unitTextWidth);
      if (fontSize < .5) {
        throw PdfOperationException('invalidWatermark',
            'The watermark would be too small to read on page ${index + 1}.');
      }
    }
    final boundingWidth = rotatedWidth * scale;
    final boundingHeight = rotatedHeight * scale;
    final column = options.anchor.index % 3;
    final row = options.anchor.index ~/ 3;
    final centerX = switch (column) {
      0 => options.margin + boundingWidth / 2,
      2 => geometry.width - options.margin - boundingWidth / 2,
      _ => geometry.width / 2,
    };
    final centerY = switch (row) {
      0 => options.margin + boundingHeight / 2,
      2 => geometry.height - options.margin - boundingHeight / 2,
      _ => geometry.height / 2,
    };
    return _MarkPlacement(
        index,
        _visualRect(
            page, centerX - width / 2, centerY - height / 2, width, height),
        fontSize);
  }

  (double, double) _rotatedSize(double width, double height, double degrees) {
    final radians = degrees % 360 * math.pi / 180;
    final c = math.cos(radians).abs();
    final s = math.sin(radians).abs();
    return (width * c + height * s, width * s + height * c);
  }

  /// Mirrors the viewer's crop/rotation map, without importing dart:ui.
  PdfRect _visualRect(
      PdfPage page, double x, double y, double width, double height) {
    final crop = page.cropBox;
    (double, double) point(double vx, double vy) {
      final (ux, uy) = switch (page.rotation) {
        90 => (vy, crop.height - vx),
        180 => (crop.width - vx, crop.height - vy),
        270 => (crop.width - vy, vx),
        _ => (vx, vy),
      };
      return (crop.left + ux, crop.top - uy);
    }

    final a = point(x, y);
    final b = point(x + width, y + height);
    return PdfRect.normalized(a.$1, a.$2, b.$1, b.$2);
  }

  Set<String> _annotationNames(PdfDocument document) => {
        for (final page in document.pages)
          for (final annotation in page.annotations)
            if (annotation.name != null) annotation.name!,
      };

  String _nextAnnotationName(Set<String> used, String kind) {
    var i = used.length;
    while (!used.add('crisp-pdf-$kind-$i')) {
      i++;
    }
    return 'crisp-pdf-$kind-$i';
  }

  void _finishMark(
      PdfEditor editor, int index, String name, double angle, bool flatten) {
    final annotation = editor.document
        .page(index)
        .annotations
        .singleWhere((item) => item.name == name);
    if (angle % 360 != 0) {
      editor.rotateAnnotation(index, annotation, -(angle % 360));
    }
    if (flatten) {
      editor.flattenAnnotations(index, annotations: [annotation]);
    }
  }
}

class _MarkPlacement {
  const _MarkPlacement(this.pageIndex, this.rect, this.fontSize);
  final int pageIndex;
  final PdfRect rect;
  final double fontSize;
}
