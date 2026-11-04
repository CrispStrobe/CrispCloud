import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf_document/pdf_document.dart' show PdfDocument;
import 'package:pdf_operations/pdf_operations.dart';

import '../l10n/pdf_operations_strings.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../services/log_service.dart';
import '../services/pdf_file_store.dart';
import '../services/pdf_operations_host.dart';

export '../services/pdf_operations_host.dart' show PdfOperationAction;

const _log = Log('PdfOperations');

extension PdfOperationActionLabel on PdfOperationAction {
  String get label => switch (this) {
    PdfOperationAction.merge => 'Merge selected PDFs',
    PdfOperationAction.extract => 'Extract these pages',
    PdfOperationAction.rotate => 'Rotate selected pages',
    PdfOperationAction.reorder => 'Reorder PDF pages',
    PdfOperationAction.deletePages => 'Delete PDF pages',
    PdfOperationAction.watermark => 'Add a watermark',
    PdfOperationAction.fillForm => 'Fill known form fields',
    PdfOperationAction.insertImage => 'Insert an image',
    PdfOperationAction.importOcr => 'Import OCR text',
  };

  String get fileSuffix => switch (this) {
    PdfOperationAction.merge => 'merged',
    PdfOperationAction.extract => 'pages',
    PdfOperationAction.rotate => 'rotated',
    PdfOperationAction.reorder => 'reordered',
    PdfOperationAction.deletePages => 'edited',
    PdfOperationAction.watermark => 'watermarked',
    PdfOperationAction.fillForm => 'filled',
    PdfOperationAction.insertImage => 'image',
    PdfOperationAction.importOcr => 'searchable',
  };

  IconData get icon => switch (this) {
    PdfOperationAction.merge => Icons.merge_outlined,
    PdfOperationAction.extract => Icons.content_copy,
    PdfOperationAction.rotate => Icons.rotate_90_degrees_cw,
    PdfOperationAction.reorder => Icons.reorder,
    PdfOperationAction.deletePages => Icons.delete_outline,
    PdfOperationAction.watermark => Icons.branding_watermark_outlined,
    PdfOperationAction.fillForm => Icons.edit_note,
    PdfOperationAction.insertImage => Icons.add_photo_alternate_outlined,
    PdfOperationAction.importOcr => Icons.document_scanner_outlined,
  };
}

/// Context-menu and command-palette entries share the same selection rules.
List<PdfOperationAction> pdfOperationsForSelection(List<FileItem> files) {
  if (files.isEmpty ||
      files.any(
        (file) => file.isFolder || !file.name.toLowerCase().endsWith('.pdf'),
      )) {
    return const [];
  }
  if (files.length > 1) return const [PdfOperationAction.merge];
  return PdfOperationAction.values
      .where((action) => action != PdfOperationAction.merge)
      .toList();
}

Future<void> showPdfOperationsDialog(
  BuildContext context,
  WidgetRef ref,
  List<FileItem> files,
  PanelSide side,
  PdfOperationAction action,
) async {
  PdfOperationsHost? host;
  try {
    if (!pdfOperationsForSelection(files).contains(action)) {
      throw ArgumentError(
        'Select two or more PDFs to merge, or one PDF for a page or form operation.',
      );
    }
    host = PdfOperationsHost.capture(ref: ref, side: side, files: files);
    final sourcePanel = ref.read(panelProvider(side));
    final otherPanel = ref.read(
      panelProvider(
        side == PanelSide.local ? PanelSide.remote : PanelSide.local,
      ),
    );
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog.fullscreen(
        child: PdfOperationsDialog(
          host: host!,
          action: action,
          onSaved: () {
            if (!context.mounted) return;
            // Refresh whatever the panes currently show; saving uses the
            // captured host, never their current account or dropdown value.
            unawaited(
              sourcePanel.refresh().catchError((Object _) {
                _log.warn('Could not refresh source panel after PDF save.');
              }),
            );
            unawaited(
              otherPanel.refresh().catchError((Object _) {
                _log.warn('Could not refresh other panel after PDF save.');
              }),
            );
          },
        ),
      ),
    );
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${context.pdfOpTr('Could not start PDF operation')}\n$error',
          ),
        ),
      );
    }
  } finally {
    host?.dispose();
  }
}

/// A preview-first batch operation surface. The preview is the exact byte
/// snapshot subsequently saved; failed writes leave it available for retry or
/// an independent export. Folder saves always create a new file; device exports
/// follow the destination and overwrite confirmation chosen in the picker.
class PdfOperationsDialog extends StatefulWidget {
  const PdfOperationsDialog({
    super.key,
    required this.host,
    required this.action,
    this.onSaved,
    this.autoRenderWorker = true,
  });

  final PdfOperationsHost host;
  final PdfOperationAction action;
  final VoidCallback? onSaved;
  final bool autoRenderWorker;

  @override
  State<PdfOperationsDialog> createState() => _PdfOperationsDialogState();
}

class _PdfOperationsDialogState extends State<PdfOperationsDialog> {
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  final _pages = TextEditingController(text: 'all');
  final _name = TextEditingController();
  final _watermarkText = TextEditingController(text: 'DRAFT');
  final _fontSize = TextEditingController(text: '36');
  final _angle = TextEditingController(text: '-35');
  final _margin = TextEditingController(text: '24');
  final _width = TextEditingController(text: '65');
  final _imageX = TextEditingController(text: '10');
  final _imageY = TextEditingController(text: '10');
  final _imageWidth = TextEditingController(text: '30');
  final _imageHeight = TextEditingController();
  final _imageAngle = TextEditingController(text: '0');
  final _json = TextEditingController(text: '{}');
  final _ocrJson = TextEditingController(text: '[]');
  final _ocrConfidence = TextEditingController(text: '0');
  final _previewSearch = TextEditingController();
  final _searchFocus = FocusNode();
  final _viewer = PdfViewerController();
  Timer? _searchDebounce;
  final _mergePages = <int, TextEditingController>{};
  final _formValues = <String, Object?>{};
  List<PdfOperationSource> _sources = const [];
  List<int> _order = [];
  PdfOperationResult? _result;
  PdfDocument? _preview;
  Uint8List? _imageBytes;
  String? _imageName;
  PdfEmbeddedFont? _font;
  String _fontName = 'DejaVu Sans';
  PdfPlacementAnchor _anchor = PdfPlacementAnchor.center;
  double _opacity = .2;
  int _rotation = 90;
  int _loadedCount = 0;
  int _formEpoch = 0;
  bool _loading = true;
  bool _working = false;
  bool _saving = false;
  bool _watermarkImage = false;
  bool _flatten = true;
  bool _allowDecryption = false;
  bool _jsonMode = false;
  bool _ocrSkipExistingText = true;
  bool _allowPop = false;
  bool _closing = false;
  bool _saved = false;
  bool _downloadStarted = false;
  String? _error;

  bool get _busy => _loading || _working || _saving;
  bool get _isMerge => widget.action == PdfOperationAction.merge;
  bool get _hasEncryptedSource =>
      _sources.any((source) => source.inspection.encrypted);

  @override
  void initState() {
    super.initState();
    final base = widget.host.stores.first.displayName.replaceFirst(
      RegExp(r'\.pdf$', caseSensitive: false),
      '',
    );
    _name.text = '$base-${widget.action.fileSuffix}.pdf';
    if (widget.action == PdfOperationAction.insertImage) _opacity = 1;
    if (widget.action == PdfOperationAction.insertImage ||
        widget.action == PdfOperationAction.deletePages) {
      _pages.text = '1';
    }
    unawaited(_load());
  }

  @override
  void dispose() {
    widget.host.dispose();
    _searchDebounce?.cancel();
    _viewer.clearSearch();
    _viewer.dispose();
    _searchFocus.dispose();
    for (final controller in [
      _pages,
      _name,
      _watermarkText,
      _fontSize,
      _angle,
      _margin,
      _width,
      _imageX,
      _imageY,
      _imageWidth,
      _imageHeight,
      _imageAngle,
      _json,
      _ocrJson,
      _ocrConfidence,
      _previewSearch,
      ..._mergePages.values,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _loadedCount = 0;
    });
    try {
      final sources = await widget.host.load(
        requestPassword: _askPassword,
        onProgress: (completed, _) {
          if (mounted) setState(() => _loadedCount = completed);
        },
      );
      if (!mounted) return;
      for (final controller in _mergePages.values) {
        controller.dispose();
      }
      _mergePages.clear();
      for (var index = 0; index < sources.length; index++) {
        _mergePages[index] = TextEditingController(text: 'all');
      }
      setState(() {
        _sources = sources;
        _order = List.generate(sources.length, (index) => index);
        _loading = false;
      });
    } on PdfOperationCancelled {
      if (mounted) await _close();
    } catch (error) {
      _reportError(error);
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String?> _askPassword(String name, bool incorrect) async {
    if (!mounted) return null;
    final text = TextEditingController();
    final route = DialogRoute<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.pdfOpTr('Password required')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name),
            if (incorrect)
              Text(context.pdfOpTr('Incorrect password. Try again.')),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('pdf-operation-password'),
              controller: text,
              autofocus: true,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: context.pdfOpTr('Password'),
              ),
              onSubmitted: (_) => Navigator.pop(dialogContext, text.text),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.pdfOpTr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, text.text),
            child: Text(context.pdfOpTr('Open')),
          ),
        ],
      ),
    );
    final answer = await Navigator.of(context).push(route);
    unawaited(route.completed.then((_) => text.dispose()));
    return answer;
  }

  Future<PdfEmbeddedFont> _appearanceFont() async {
    if (_font != null) return _font!;
    final bytes = await DefaultAssetBundle.of(context).load(
      'packages/dart_pdf_editor_assets/assets/fonts/DejaVuSans.ttf',
    );
    return _font ??= PdfEmbeddedFont.parse(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
  }

  double _number(
    TextEditingController controller,
    String label,
    double minimum,
    double maximum,
  ) {
    final value = double.tryParse(controller.text.trim());
    if (value == null ||
        !value.isFinite ||
        value < minimum ||
        value > maximum) {
      throw ArgumentError('${context.pdfOpTr(label)}: $minimum–$maximum');
    }
    return value;
  }

  Map<String, Object?> _readFormValues() {
    if (!_jsonMode) return Map.of(_formValues);
    if (utf8.encode(_json.text).length > 4 * 1024 * 1024) {
      throw ArgumentError('Form data exceeds 4 MiB.');
    }
    final value = jsonDecode(_json.text);
    if (value is! Map<String, dynamic>) {
      throw const FormatException(
        'Form data must be a JSON object keyed by field name.',
      );
    }
    return Map<String, Object?>.from(value);
  }

  void _switchFormMode(bool jsonMode) {
    if (_busy || jsonMode == _jsonMode) return;
    try {
      if (jsonMode) {
        _json.text = const JsonEncoder.withIndent('  ').convert(_formValues);
      } else {
        final values = _readFormValues();
        final fields = _sources.first.inspection.fields;
        final errors = <String, String>{};
        final typedValues = <String, Object?>{};
        for (final entry in values.entries) {
          final matches = fields
              .where((field) => field.name == entry.key)
              .toList();
          if (matches.length != 1) {
            errors[entry.key] = matches.isEmpty
                ? 'Unknown field name.'
                : 'The field name is ambiguous.';
            continue;
          }
          final field = matches.single;
          final type = field.type.toLowerCase();
          final value = entry.value;
          if (_fieldDisabled(field)) {
            errors[entry.key] = 'This field cannot be filled from a value map.';
          } else if (type.contains('checkbox')) {
            if (value is bool) {
              typedValues[entry.key] = value;
            } else {
              errors[entry.key] = 'A checkbox requires true or false.';
            }
          } else if (field.multiSelect) {
            if (value is List && value.every((item) => item is String)) {
              typedValues[entry.key] = [
                for (final item in value) _optionValue(field, item as String),
              ];
            } else {
              errors[entry.key] =
                  'A multi-select field requires an array of strings.';
            }
          } else if (value is String) {
            typedValues[entry.key] = _optionValue(field, value);
          } else {
            errors[entry.key] = 'This field requires a string.';
          }
        }
        if (errors.isNotEmpty) {
          throw PdfOperationException(
            'invalidForm',
            'Correct the JSON field names and value types before switching to fields.',
            fieldErrors: errors,
          );
        }
        _formValues
          ..clear()
          ..addAll(typedValues);
        // TextFormField.initialValue is read only when its state is created.
        // A new epoch displays imported values instead of an earlier edit.
        _formEpoch++;
      }
      setState(() {
        _jsonMode = jsonMode;
        _error = null;
      });
    } catch (error) {
      // Keep the JSON visible and intact when it cannot populate the controls.
      _reportError(error);
    }
  }

  String _optionValue(PdfFormFieldDescription field, String value) {
    final byValue = field.options.where((option) => option.value == value);
    if (byValue.isNotEmpty) return value;
    final byLabel = field.options
        .where((option) => option.label == value)
        .toList();
    return byLabel.length == 1 ? byLabel.single.value : value;
  }

  bool _fieldDisabled(PdfFormFieldDescription field) {
    final type = field.type.toLowerCase();
    return field.readOnly ||
        field.password ||
        type.contains('signature') ||
        type.contains('pushbutton') ||
        type == 'unknown';
  }

  List<PdfOcrPage> _readOcrPages([String? source]) {
    final text = source ?? _ocrJson.text;
    if (utf8.encode(text).length > 16 * 1024 * 1024) {
      throw ArgumentError(context.pdfOpTr('OCR data exceeds 16 MiB.'));
    }
    final value = jsonDecode(text);
    if (value is! List || value.any((page) => page is! Map<String, dynamic>)) {
      throw FormatException(
        context.pdfOpTr(
          'OCR data must be a JSON array of pages with text spans.',
        ),
      );
    }
    return [
      for (final page in value)
        PdfOcrPage.fromJson(Map<String, Object?>.from(page as Map)),
    ];
  }

  Future<void> _createPreview() async {
    if (_busy || _sources.isEmpty) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await WidgetsBinding.instance.endOfFrame;
      PdfEmbeddedFont? font;
      if (widget.action == PdfOperationAction.fillForm ||
          widget.action == PdfOperationAction.importOcr ||
          (widget.action == PdfOperationAction.watermark && !_watermarkImage)) {
        font = await _appearanceFont();
      }
      if (!mounted) return;
      final request = PdfOperationRequest(
        action: widget.action,
        sources: [
          for (final index in _order)
            PdfMergeInput(
              _sources[index].input,
              pages: _mergePages[index]!.text.trim(),
            ),
        ],
        pages: _pages.text.trim(),
        degrees: _rotation,
        allowDecryption: _allowDecryption,
        fields: widget.action == PdfOperationAction.fillForm
            ? _readFormValues()
            : const {},
        appearanceFont: font,
        ocrPages: widget.action == PdfOperationAction.importOcr
            ? _readOcrPages()
            : const [],
        ocrMinConfidence: widget.action == PdfOperationAction.importOcr
            ? _number(_ocrConfidence, 'Minimum confidence (0–1)', 0, 1)
            : 0,
        ocrSkipExistingText: _ocrSkipExistingText,
        watermark: widget.action == PdfOperationAction.watermark
            ? PdfWatermarkOptions(
                text: _watermarkImage ? null : _watermarkText.text,
                imageBytes: _watermarkImage ? _requireImage() : null,
                font: font,
                fontSize: _number(_fontSize, 'Font size', 1, 500),
                opacity: _opacity,
                angleDegrees: _number(_angle, 'Angle', -360, 360),
                anchor: _anchor,
                margin: _number(_margin, 'Margin (points)', 0, 1000),
                widthFraction: _number(_width, 'Width (%)', 1, 100) / 100,
                flatten: _flatten,
              )
            : null,
        imageBytes: widget.action == PdfOperationAction.insertImage
            ? _requireImage()
            : null,
        imagePlacement: widget.action == PdfOperationAction.insertImage
            ? PdfImagePlacement(
                x: _number(_imageX, 'Left (%)', 0, 100) / 100,
                y: _number(_imageY, 'Top (%)', 0, 100) / 100,
                width: _number(_imageWidth, 'Width (%)', .1, 100) / 100,
                height: _imageHeight.text.trim().isEmpty
                    ? null
                    : _number(_imageHeight, 'Height (%)', .1, 100) / 100,
                angleDegrees: _number(_imageAngle, 'Angle', -360, 360),
                opacity: _opacity,
                flatten: _flatten,
              )
            : null,
      );
      final result = await widget.host.perform(request);
      if (!mounted) return;
      final preview = PdfDocument.open(
        result.bytes,
        password: _sources[_order.first].input.password,
      );
      _clearPreviewSearch();
      setState(() {
        _result = result;
        _preview = preview;
        _saved = false;
        _downloadStarted = false;
      });
    } catch (error) {
      _reportError(error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Uint8List _requireImage() {
    final bytes = _imageBytes;
    if (bytes == null)
      throw ArgumentError(context.pdfOpTr('Choose a PNG or JPEG image.'));
    return bytes;
  }

  Future<void> _pickImage() async {
    if (_busy) return;
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg'],
        withData: true,
      );
      if (!mounted || picked == null) return;
      final file = picked.files.single;
      if (file.size > kPdfEditorInputLimitBytes ||
          (file.bytes?.length ?? 0) > kPdfEditorInputLimitBytes) {
        throw const PdfFileTooLargeException(kPdfEditorInputLimitBytes);
      }
      if (file.bytes == null)
        throw StateError(
          context.pdfOpTr('The selected file could not be read.'),
        );
      setState(() {
        _imageBytes = file.bytes;
        _imageName = file.name;
        _error = null;
      });
    } catch (error) {
      _reportError(error);
    }
  }

  Future<void> _pickFont() async {
    if (_busy) return;
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['ttf', 'otf'],
        withData: true,
      );
      if (!mounted || picked == null) return;
      final file = picked.files.single;
      if (file.size > 16 * 1024 * 1024 ||
          (file.bytes?.length ?? 0) > 16 * 1024 * 1024) {
        throw ArgumentError('Font files must be at most 16 MiB.');
      }
      if (file.bytes == null)
        throw StateError(
          context.pdfOpTr('The selected file could not be read.'),
        );
      final font = PdfEmbeddedFont.parse(file.bytes!);
      setState(() {
        _font = font;
        _fontName = font.displayName;
        _error = null;
      });
    } catch (error) {
      _reportError(error);
    }
  }

  Future<void> _importJson() async {
    if (_busy) return;
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      if (!mounted || picked == null) return;
      final file = picked.files.single;
      if (file.size > 4 * 1024 * 1024 ||
          (file.bytes?.length ?? 0) > 4 * 1024 * 1024) {
        throw ArgumentError('Form data exceeds 4 MiB.');
      }
      if (file.bytes == null)
        throw StateError(
          context.pdfOpTr('The selected file could not be read.'),
        );
      final text = utf8.decode(file.bytes!);
      if (jsonDecode(text) is! Map<String, dynamic>) {
        throw const FormatException(
          'Form data must be a JSON object keyed by field name.',
        );
      }
      setState(() {
        _json.text = text;
        _jsonMode = true;
        _error = null;
      });
    } catch (error) {
      _reportError(error);
    }
  }

  Future<void> _importOcrJson() async {
    if (_busy) return;
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      if (!mounted || picked == null) return;
      final file = picked.files.single;
      if (file.size > 16 * 1024 * 1024 ||
          (file.bytes?.length ?? 0) > 16 * 1024 * 1024) {
        throw ArgumentError(context.pdfOpTr('OCR data exceeds 16 MiB.'));
      }
      if (file.bytes == null)
        throw StateError(
          context.pdfOpTr('The selected file could not be read.'),
        );
      final text = utf8.decode(file.bytes!);
      _readOcrPages(text);
      setState(() {
        _ocrJson.text = text;
        _error = null;
      });
    } catch (error) {
      _reportError(error);
    }
  }

  Future<void> _save({required bool device}) async {
    if (_busy || _result == null) return;
    final name = _name.text.trim();
    if (name.isEmpty ||
        name == '.' ||
        name == '..' ||
        RegExp(r'[<>:"/\\|?*\x00-\x1f]').hasMatch(name)) {
      setState(
        () => _error = context.pdfOpTr(
          'Choose a new PDF file name without a folder path.',
        ),
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final outcome = device
          ? await widget.host.export(_result!.bytes, name)
          : await widget.host.saveSibling(_result!.bytes, name);
      if (!mounted || outcome == null) return;
      setState(() {
        _saved = _saved || outcome != PdfSaveOutcome.downloadedCopy;
        _downloadStarted = outcome == PdfSaveOutcome.downloadedCopy;
      });
      if (!device) {
        try {
          widget.onSaved?.call();
        } catch (_) {
          _log.warn('Could not refresh panels after saving a PDF copy.');
        }
      }
      _messenger.currentState?.showSnackBar(
        SnackBar(
          content: Text(
            context.pdfOpTr(
              _downloadStarted
                  ? 'Download started. Keep the downloaded file before closing.'
                  : 'PDF copy saved.',
            ),
          ),
        ),
      );
    } catch (error) {
      _reportError(error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _reportError(Object error) {
    // Field values and document passwords must never enter the app log.
    _log.warn('PDF operation failed (${error.runtimeType}).');
    if (!mounted) return;
    final detail =
        error is PdfOperationException && error.fieldErrors.isNotEmpty
        ? '${error.message}\n${error.fieldErrors.entries.map((entry) => '${entry.key}: ${entry.value}').join('\n')}'
        : '$error';
    setState(() => _error = detail);
  }

  void _clearPreviewSearch() {
    _searchDebounce?.cancel();
    _previewSearch.clear();
    _viewer.clearSearch();
  }

  Future<void> _searchPreview() async {
    _searchDebounce?.cancel();
    if (_result == null || !mounted) return;
    try {
      await _viewer.search(_previewSearch.text);
    } catch (error) {
      _reportError(error);
    }
  }

  Widget _previewSearchBar() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            key: const ValueKey('pdf-operation-search'),
            controller: _previewSearch,
            focusNode: _searchFocus,
            decoration: InputDecoration(
              labelText: context.pdfOpTr('Search preview text'),
              border: const OutlineInputBorder(),
              isDense: true,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: context.pdfOpTr('Clear search'),
                onPressed: _clearPreviewSearch,
                icon: const Icon(Icons.close),
              ),
            ),
            onChanged: (_) {
              _searchDebounce?.cancel();
              _searchDebounce = Timer(const Duration(milliseconds: 250), () {
                unawaited(_searchPreview());
              });
            },
            onSubmitted: (_) => unawaited(_searchPreview()),
          ),
        ),
        const SizedBox(width: 8),
        AnimatedBuilder(
          animation: _viewer,
          builder: (context, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_viewer.isSearching)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (_viewer.query.isNotEmpty)
                Text('${_viewer.currentMatch + 1} / ${_viewer.matchCount}'),
              IconButton(
                tooltip: context.pdfOpTr('Previous match'),
                onPressed: _viewer.matchCount == 0
                    ? null
                    : _viewer.previousMatch,
                icon: const Icon(Icons.keyboard_arrow_up),
              ),
              IconButton(
                tooltip: context.pdfOpTr('Next match'),
                onPressed: _viewer.matchCount == 0 ? null : _viewer.nextMatch,
                icon: const Icon(Icons.keyboard_arrow_down),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Future<void> _requestClose() async {
    if (_saving || _working || _closing) return;
    _closing = true;
    try {
      if (_result != null && !_saved) {
        final leave = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(
              context.pdfOpTr(
                _downloadStarted
                    ? 'Close after downloading?'
                    : 'Close without saving?',
              ),
            ),
            content: Text(
              context.pdfOpTr(
                _downloadStarted
                    ? 'Make sure the downloaded PDF is available before closing.'
                    : 'The generated PDF has not been saved. You can return to the preview to save or export it.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(context.pdfOpTr('Return to preview')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(context.pdfOpTr('Close')),
              ),
            ],
          ),
        );
        if (leave != true || !mounted) return;
      }
      await _close();
    } finally {
      _closing = false;
    }
  }

  Future<void> _close() async {
    if (!mounted || _allowPop) return;
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
  }

  Widget _numberField(
    TextEditingController controller,
    String label, {
    String? hint,
  }) => SizedBox(
    width: 160,
    child: TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      decoration: InputDecoration(
        labelText: context.pdfOpTr(label),
        helperText: hint == null ? null : context.pdfOpTr(hint),
        border: const OutlineInputBorder(),
      ),
    ),
  );

  Widget _pageSelection() => TextField(
    key: const ValueKey('pdf-operation-pages'),
    controller: _pages,
    decoration: InputDecoration(
      labelText: context.pdfOpTr(
        widget.action == PdfOperationAction.reorder
            ? 'New page order'
            : 'Pages',
      ),
      helperText: context.pdfOpTr(
        widget.action == PdfOperationAction.reorder
            ? 'List every page once, for example 3,1,2 or 5-1.'
            : 'Use all, 1-3,7, or a descending range such as 5-1.',
      ),
      helperMaxLines: 3,
      border: const OutlineInputBorder(),
    ),
  );

  Widget _mergeInputs() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        context.pdfOpTr(
          'PDFs are merged in the order below. Choose pages from each source.',
        ),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 12),
      for (var position = 0; position < _order.length; position++)
        _mergeInput(position),
    ],
  );

  Widget _mergeInput(int position) {
    final index = _order[position];
    final source = _sources[index];
    return Card(
      key: ValueKey('pdf-merge-source-$index'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(radius: 15, child: Text('${position + 1}')),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    source.input.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  key: ValueKey('pdf-merge-up-$index'),
                  tooltip: context.pdfOpTr('Move up'),
                  onPressed: position == 0
                      ? null
                      : () => setState(() {
                          _order.removeAt(position);
                          _order.insert(position - 1, index);
                        }),
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  key: ValueKey('pdf-merge-down-$index'),
                  tooltip: context.pdfOpTr('Move down'),
                  onPressed: position == _order.length - 1
                      ? null
                      : () => setState(() {
                          _order.removeAt(position);
                          _order.insert(position + 1, index);
                        }),
                  icon: const Icon(Icons.arrow_downward),
                ),
              ],
            ),
            Text('${source.inspection.pageCount} ${context.pdfOpTr('pages')}'),
            const SizedBox(height: 10),
            TextField(
              key: ValueKey('pdf-merge-pages-$index'),
              controller: _mergePages[index],
              decoration: InputDecoration(
                labelText: context.pdfOpTr('Pages'),
                hintText: 'all / 1-3,7',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imagePicker() => Wrap(
    spacing: 12,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      OutlinedButton.icon(
        onPressed: _pickImage,
        icon: const Icon(Icons.image_outlined),
        label: Text(context.pdfOpTr('Choose PNG / JPEG')),
      ),
      if (_imageName != null) Text(_imageName!),
    ],
  );

  Widget _fontPicker() => Wrap(
    spacing: 12,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text('${context.pdfOpTr('Font')}: $_fontName'),
      OutlinedButton.icon(
        onPressed: _pickFont,
        icon: const Icon(Icons.font_download_outlined),
        label: Text(context.pdfOpTr('Choose TTF / OTF')),
      ),
    ],
  );

  Widget _opacityControl() => Row(
    children: [
      Text(context.pdfOpTr('Opacity')),
      Expanded(
        child: Slider(
          key: const ValueKey('pdf-watermark-opacity'),
          value: _opacity,
          min: .05,
          max: 1,
          divisions: 19,
          label: '${(_opacity * 100).round()}%',
          onChanged: (value) => setState(() => _opacity = value),
        ),
      ),
      SizedBox(width: 50, child: Text('${(_opacity * 100).round()}%')),
    ],
  );

  Widget _flattenControl() => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    value: _flatten,
    onChanged: (value) => setState(() => _flatten = value),
    title: Text(context.pdfOpTr('Bake the new marks into page content')),
    subtitle: Text(
      context.pdfOpTr(
        'Turn off to keep the new marks as editable annotations. Existing annotations and form fields are preserved.',
      ),
    ),
  );

  Widget _watermarkControls() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SegmentedButton<bool>(
        segments: [
          ButtonSegment(
            value: false,
            label: Text(context.pdfOpTr('Text')),
            icon: const Icon(Icons.text_fields),
          ),
          ButtonSegment(
            value: true,
            label: Text(context.pdfOpTr('Logo / image')),
            icon: const Icon(Icons.image_outlined),
          ),
        ],
        selected: {_watermarkImage},
        onSelectionChanged: (values) =>
            setState(() => _watermarkImage = values.single),
      ),
      const SizedBox(height: 16),
      if (_watermarkImage)
        _imagePicker()
      else ...[
        TextField(
          key: const ValueKey('pdf-watermark-text'),
          controller: _watermarkText,
          decoration: InputDecoration(
            labelText: context.pdfOpTr('Watermark text'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        _fontPicker(),
      ],
      const SizedBox(height: 16),
      Wrap(
        spacing: 12,
        runSpacing: 16,
        children: [
          if (!_watermarkImage) _numberField(_fontSize, 'Font size'),
          _numberField(_angle, 'Angle'),
          _numberField(_width, 'Width (%)'),
          _numberField(_margin, 'Margin (points)'),
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<PdfPlacementAnchor>(
              initialValue: _anchor,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: context.pdfOpTr('Position'),
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final anchor in PdfPlacementAnchor.values)
                  DropdownMenuItem(
                    value: anchor,
                    child: Text(
                      context.pdfOpTr(_anchorName(anchor)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _anchor = value);
              },
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      _opacityControl(),
      _flattenControl(),
      Text(
        context.pdfOpTr(
          'Watermarks are placed over page content. Review the generated preview before saving.',
        ),
      ),
    ],
  );

  String _anchorName(PdfPlacementAnchor anchor) => switch (anchor) {
    PdfPlacementAnchor.topLeft => 'Top left',
    PdfPlacementAnchor.topCenter => 'Top center',
    PdfPlacementAnchor.topRight => 'Top right',
    PdfPlacementAnchor.centerLeft => 'Center left',
    PdfPlacementAnchor.center => 'Center',
    PdfPlacementAnchor.centerRight => 'Center right',
    PdfPlacementAnchor.bottomLeft => 'Bottom left',
    PdfPlacementAnchor.bottomCenter => 'Bottom center',
    PdfPlacementAnchor.bottomRight => 'Bottom right',
  };

  Widget _imageControls() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _imagePicker(),
      const SizedBox(height: 16),
      Text(
        context.pdfOpTr(
          'Placement is measured from the visible top-left corner of each page, including rotated pages.',
        ),
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 12,
        runSpacing: 16,
        children: [
          _numberField(_imageX, 'Left (%)'),
          _numberField(_imageY, 'Top (%)'),
          _numberField(_imageWidth, 'Width (%)'),
          _numberField(
            _imageHeight,
            'Height (%)',
            hint: 'Blank keeps aspect ratio',
          ),
          _numberField(_imageAngle, 'Angle'),
        ],
      ),
      _opacityControl(),
      _flattenControl(),
    ],
  );

  Widget _formControls() {
    final fields = _sources.first.inspection.fields;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (fields.isEmpty)
          Text(
            context.pdfOpTr(
              'This PDF has no named AcroForm fields. Open the editor to place text or create form fields.',
            ),
          ),
        Text(
          context.pdfOpTr(
            'Only changed fields are written. Field names and option values must match the PDF exactly. Password, signature, and read-only fields cannot be batch-filled.',
          ),
        ),
        const SizedBox(height: 12),
        _fontPicker(),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: false,
                  label: Text(context.pdfOpTr('Fields')),
                ),
                const ButtonSegment(value: true, label: Text('JSON')),
              ],
              selected: {_jsonMode},
              onSelectionChanged: (values) => _switchFormMode(values.single),
            ),
            OutlinedButton.icon(
              onPressed: _importJson,
              icon: const Icon(Icons.upload_file),
              label: Text(context.pdfOpTr('Import JSON')),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_jsonMode) ...[
          TextField(
            key: const ValueKey('pdf-form-json'),
            controller: _json,
            minLines: 6,
            maxLines: 14,
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: InputDecoration(
              labelText: context.pdfOpTr('Field name → value'),
              helperText: context.pdfOpTr(
                'Text: string; checkbox: true/false; radio/choice: option value; multiple choice: array of values.',
              ),
              helperMaxLines: 4,
              border: const OutlineInputBorder(),
            ),
          ),
          ExpansionTile(
            title: Text(context.pdfOpTr('Known field names')),
            children: [
              for (final field in fields)
                ListTile(
                  dense: true,
                  title: SelectableText(field.name),
                  subtitle: Text(_fieldSummary(field)),
                ),
            ],
          ),
        ] else ...[
          for (final field in fields)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _formField(field),
            ),
        ],
      ],
    );
  }

  String _fieldSummary(PdfFormFieldDescription field) => [
    field.type,
    if (field.required) context.pdfOpTr('required'),
    if (field.readOnly) context.pdfOpTr('read-only'),
    if (field.password) context.pdfOpTr('password'),
    if (field.options.isNotEmpty)
      field.options.map((option) => option.value).join(', '),
    if (field.onStates.isNotEmpty) field.onStates.join(', '),
  ].join(' · ');

  Widget _formField(PdfFormFieldDescription field) {
    final type = field.type.toLowerCase();
    final disabled = _fieldDisabled(field);
    final key = ValueKey('pdf-form-${field.name}-$_formEpoch');
    final current = _formValues.containsKey(field.name)
        ? _formValues[field.name]
        : null;
    final label = '${field.name}${field.required ? ' *' : ''}';
    if (disabled) {
      return ListTile(
        key: key,
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.lock_outline),
        title: Text(label),
        subtitle: Text(_fieldSummary(field)),
      );
    }
    if (type.contains('checkbox')) {
      final checked = current is bool
          ? current
          : field.values.any((value) => value.isNotEmpty && value != 'Off');
      return CheckboxListTile(
        key: key,
        contentPadding: EdgeInsets.zero,
        value: checked,
        title: Text(label),
        subtitle: Text(_fieldSummary(field)),
        onChanged: (value) =>
            setState(() => _formValues[field.name] = value ?? false),
      );
    }
    if (field.multiSelect) {
      final selected = current is List
          ? current.cast<String>().toSet()
          : field.values.toSet();
      return Column(
        key: key,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          Wrap(
            spacing: 8,
            children: [
              for (final option in field.options)
                FilterChip(
                  label: Text(option.label),
                  selected: selected.contains(option.value),
                  onSelected: (select) => setState(() {
                    final next = Set<String>.from(selected);
                    if (select) {
                      next.add(option.value);
                    } else {
                      next.remove(option.value);
                    }
                    _formValues[field.name] = next.toList();
                  }),
                ),
            ],
          ),
        ],
      );
    }
    final choices = <String, String>{
      for (final option in field.options) option.value: option.label,
    };
    if (type.contains('radio')) {
      for (final value in field.onStates.where((value) => value != 'Off')) {
        choices.putIfAbsent(value, () => value);
      }
    }
    final initial = current is String
        ? current
        : (field.values.isEmpty ? '' : field.values.first);
    if (choices.isNotEmpty && !field.editableChoice) {
      return DropdownButtonFormField<String>(
        key: key,
        initialValue: choices.containsKey(initial) ? initial : null,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          helperText: _fieldSummary(field),
          helperMaxLines: 3,
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final entry in choices.entries)
            DropdownMenuItem(
              value: entry.key,
              child: Text(entry.value, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (value) {
          if (value != null) setState(() => _formValues[field.name] = value);
        },
      );
    }
    return TextFormField(
      key: key,
      initialValue: initial,
      maxLines: field.multiline ? 4 : 1,
      keyboardType: field.multiline
          ? TextInputType.multiline
          : TextInputType.text,
      textInputAction: field.multiline
          ? TextInputAction.newline
          : TextInputAction.next,
      maxLength: field.maxLength,
      decoration: InputDecoration(
        labelText: label,
        helperText: _fieldSummary(field),
        helperMaxLines: 3,
        border: const OutlineInputBorder(),
      ),
      onChanged: (value) => _formValues[field.name] = value,
    );
  }

  Widget _ocrControls() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        context.pdfOpTr(
          'Import text already recognized by an OCR tool. This action does not recognize images or contact a recognition service.',
        ),
      ),
      const SizedBox(height: 12),
      Text(
        context.pdfOpTr(
          'Use one-based page numbers. Each span needs text and bounds [left, bottom, right, top] in PDF points, not image pixels. Confidence is optional and defaults to 1.',
        ),
      ),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: _importOcrJson,
          icon: const Icon(Icons.upload_file),
          label: Text(context.pdfOpTr('Import OCR JSON')),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const ValueKey('pdf-ocr-json'),
        controller: _ocrJson,
        minLines: 6,
        maxLines: 14,
        style: const TextStyle(fontFamily: 'monospace'),
        decoration: InputDecoration(
          labelText: context.pdfOpTr('Recognized page spans (JSON)'),
          helperText: '[{"page":1,"spans":[{"text":"Example","bounds":[72,700,130,718],"confidence":0.98}]}]',
          helperMaxLines: 5,
          border: const OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 16),
      _fontPicker(),
      const SizedBox(height: 16),
      _numberField(_ocrConfidence, 'Minimum confidence (0–1)'),
      CheckboxListTile(
        key: const ValueKey('pdf-ocr-skip-existing'),
        contentPadding: EdgeInsets.zero,
        value: _ocrSkipExistingText,
        onChanged: (value) =>
            setState(() => _ocrSkipExistingText = value ?? true),
        title: Text(context.pdfOpTr('Skip pages that already contain text')),
        subtitle: Text(
          context.pdfOpTr(
            'Turning this off appends another text layer and can duplicate existing searchable text.',
          ),
        ),
      ),
      Text(
        context.pdfOpTr(
          'The added text is invisible. Select or search text in the generated preview to check the result.',
        ),
      ),
    ],
  );

  Widget _options() => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: AbsorbPointer(
          absorbing: _busy,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_isMerge)
                _mergeInputs()
              else ...[
                Text(
                  _sources.first.input.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  '${_sources.first.inspection.pageCount} ${context.pdfOpTr('pages')}',
                ),
                const SizedBox(height: 20),
                if (widget.action != PdfOperationAction.fillForm &&
                    widget.action != PdfOperationAction.importOcr)
                  _pageSelection(),
                const SizedBox(height: 20),
              ],
              if (widget.action == PdfOperationAction.rotate)
                DropdownButtonFormField<int>(
                  key: const ValueKey('pdf-operation-rotation'),
                  initialValue: _rotation,
                  decoration: InputDecoration(
                    labelText: context.pdfOpTr('Rotation'),
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 90,
                      child: Text(context.pdfOpTr('90° clockwise')),
                    ),
                    const DropdownMenuItem(value: 180, child: Text('180°')),
                    DropdownMenuItem(
                      value: 270,
                      child: Text(context.pdfOpTr('90° counterclockwise')),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _rotation = value);
                  },
                ),
              if (widget.action == PdfOperationAction.watermark)
                _watermarkControls(),
              if (widget.action == PdfOperationAction.insertImage)
                _imageControls(),
              if (widget.action == PdfOperationAction.fillForm) _formControls(),
              if (widget.action == PdfOperationAction.importOcr) _ocrControls(),
              if (widget.action == PdfOperationAction.deletePages)
                Text(
                  context.pdfOpTr(
                    'At least one page must remain. Deleting pages is a page organization action; it is not secure content removal.',
                  ),
                ),
              if (_hasEncryptedSource &&
                  (_isMerge || widget.action == PdfOperationAction.extract))
                CheckboxListTile(
                  key: const ValueKey('pdf-allow-decryption'),
                  contentPadding: EdgeInsets.zero,
                  value: _allowDecryption,
                  onChanged: (value) =>
                      setState(() => _allowDecryption = value ?? false),
                  title: Text(
                    context.pdfOpTr(
                      'Allow an unprotected output when required',
                    ),
                  ),
                  subtitle: Text(
                    context.pdfOpTr(
                      'Page extraction can remove password protection. Merge output follows the first PDF’s encryption. Only continue if that output is appropriate.',
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              Text(
                context.pdfOpTr(
                  'Review the generated PDF, then save a new copy or export it to your device.',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _previewResult() => Column(
    children: [
      if (_result!.warnings.isNotEmpty)
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 190),
          child: SingleChildScrollView(
            child: ExpansionTile(
              initiallyExpanded: true,
              leading: const Icon(Icons.info_outline),
              title: Text(context.pdfOpTr('Review output notes')),
              children: [
                for (final warning in _result!.warnings)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(warning),
                    ),
                  ),
              ],
            ),
          ),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('pdf-operation-output-name'),
                controller: _name,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: context.pdfOpTr('Output file name'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Text('${_result!.pageCount} ${context.pdfOpTr('pages')}'),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '${context.pdfOpTr('New copy beside')}: ${widget.host.destinationPath}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      _previewSearchBar(),
      Expanded(
        child: PdfMaterialHost(
          child: PdfViewer(
            key: ValueKey(_result),
            document: _preview!,
            controller: _viewer,
            autoRenderWorker: widget.autoRenderWorker,
            interactiveForms: false,
            textSelectionEditing: false,
            textSelectionMarkup: false,
            textSelectionRedaction: false,
            showInlineTextStyleChip: false,
            highlightFormFields: false,
          ),
        ),
      ),
    ],
  );

  Widget _footer() => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: [
          if (_result != null)
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () {
                      _clearPreviewSearch();
                      setState(() {
                        _result = null;
                        _preview = null;
                        _error = null;
                      });
                    },
              child: Text(context.pdfOpTr('Back to options')),
            ),
          if (_result == null) ...[
            TextButton(
              onPressed: _saving || _working ? null : _requestClose,
              child: Text(context.pdfOpTr('Cancel')),
            ),
            FilledButton.icon(
              key: const ValueKey('pdf-operation-preview'),
              onPressed: _busy || _sources.isEmpty ? null : _createPreview,
              icon: const Icon(Icons.preview_outlined),
              label: Text(context.pdfOpTr('Preview PDF')),
            ),
          ] else ...[
            OutlinedButton.icon(
              key: const ValueKey('pdf-operation-export'),
              onPressed: _busy ? null : () => _save(device: true),
              icon: const Icon(Icons.download_outlined),
              label: Text(
                context.pdfOpTr(kIsWeb ? 'Download PDF' : 'Export PDF'),
              ),
            ),
            FilledButton.icon(
              key: const ValueKey('pdf-operation-save'),
              onPressed: _busy ? null : () => _save(device: false),
              icon: const Icon(Icons.save_as_outlined),
              label: Text(context.pdfOpTr('Save new copy')),
            ),
          ],
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowPop,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_requestClose());
    },
    child: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
          if (_result != null) _searchFocus.requestFocus();
        },
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () {
          if (_result != null) _searchFocus.requestFocus();
        },
      },
      child: ScaffoldMessenger(
        key: _messenger,
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            leading: IconButton(
              key: const ValueKey('pdf-operation-close'),
              tooltip: context.pdfOpTr('Close'),
              onPressed: _saving || _working ? null : _requestClose,
              icon: const Icon(Icons.close),
            ),
            title: Text(context.pdfOpTr(widget.action.label)),
          ),
          body: Column(
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: SingleChildScrollView(
                    child: Container(
                      width: double.infinity,
                      color: Theme.of(context).colorScheme.errorContainer,
                      padding: const EdgeInsets.all(12),
                      child: Semantics(
                        liveRegion: true,
                        child: SelectableText(
                          _error!,
                          key: const ValueKey('pdf-operation-error'),
                        ),
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: _loading
                    ? Center(
                        child: Text(
                          '${context.pdfOpTr('Reading PDFs…')} $_loadedCount/${widget.host.stores.length}',
                        ),
                      )
                    : _sources.isEmpty
                    ? Center(
                        child: TextButton(
                          onPressed: _load,
                          child: Text(context.pdfOpTr('Retry')),
                        ),
                      )
                    : _result == null
                    ? _options()
                    : _previewResult(),
              ),
              _footer(),
            ],
          ),
        ),
      ),
    ),
  );
}
