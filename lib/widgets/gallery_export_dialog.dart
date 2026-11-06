import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/gallery_media_provider.dart';
import '../services/gallery_device_export.dart';
import '../services/gallery_export_service.dart';
import '../services/gallery_media_service.dart';

Future<void> showGalleryExportDialog(
  BuildContext context,
  WidgetRef ref,
  PanelSide side,
  List<FileItem> files, {
  bool contactSheet = false,
}) async {
  final GalleryExportService service;
  final List<GalleryMediaRequest> requests;
  try {
    final media = ref.read(galleryMediaServiceProvider);
    service = GalleryExportService(loadImage: media.loadImage);
    requests = List<GalleryMediaRequest>.unmodifiable(files.map(
      (file) => captureGalleryMediaRequest(ref, side, file),
    ));
  } catch (_) {
    if (!context.mounted) return;
    final german = Localizations.localeOf(context).languageCode == 'de';
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(
      german
        ? 'Die Bildquelle ist nicht mehr verfügbar. Ordner aktualisieren und Export erneut öffnen.'
        : 'The image source is no longer available. Refresh the folder and reopen the export.',
    )));
    return;
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => GalleryExportDialog(
      requests: requests,
      service: service,
      contactSheet: contactSheet,
    ),
  );
}

/// The prepared export stays in the dialog until the user saves a copy.
/// A cancelled picker leaves it available for another save attempt.
class GalleryExportDialog extends StatefulWidget {
  const GalleryExportDialog({
    super.key,
    required this.requests,
    required this.service,
    this.contactSheet = false,
    this.exporter = exportGalleryFile,
  });

  final List<GalleryMediaRequest> requests;
  final GalleryExportService service;
  final bool contactSheet;
  final GalleryDeviceExporter exporter;

  @override
  State<GalleryExportDialog> createState() => _GalleryExportDialogState();
}

class _GalleryExportDialogState extends State<GalleryExportDialog> {
  final _formKey = GlobalKey<FormState>();
  final _width = TextEditingController(text: '2048');
  final _height = TextEditingController(text: '2048');
  GalleryExportFormat _format = GalleryExportFormat.jpeg;
  bool _resize = true;
  bool _upscale = false;
  double _quality = 90;
  int _quarterTurns = 0;
  bool _flipHorizontal = false;
  bool _flipVertical = false;
  double _brightness = 1;
  double _contrast = 1;
  double _saturation = 1;
  int _columns = 4;
  int _tileSize = 320;
  bool _captions = true;
  bool _running = false;
  bool _saving = false;
  GalleryExportCancellation? _cancellation;
  GalleryExportProgress? _progress;
  GalleryExportReport? _report;
  String? _error;
  String? _saveStatus;

  bool get _busy => _running || _saving;
  bool get _german => Localizations.localeOf(context).languageCode == 'de';
  String _t(String english, String german) => _german ? german : english;

  @override
  void dispose() {
    _cancellation?.cancel();
    _width.dispose();
    _height.dispose();
    super.dispose();
  }

  void _change(VoidCallback change) {
    if (_busy) return;
    setState(() {
      change();
      _report = null;
      _error = null;
      _saveStatus = null;
    });
  }

  String? _dimensionError(String? value) {
    final parsed = int.tryParse(value?.trim() ?? '');
    if (parsed == null || parsed < 1 ||
        parsed > widget.service.limits.maxDimension) {
      return _t('Enter 1–${widget.service.limits.maxDimension}',
        '1–${widget.service.limits.maxDimension} eingeben');
    }
    return null;
  }

  Future<void> _prepare() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    final token = GalleryExportCancellation();
    setState(() {
      _cancellation = token;
      _running = true;
      _report = null;
      _error = null;
      _saveStatus = null;
      _progress = null;
    });
    void progress(GalleryExportProgress value) {
      if (mounted) setState(() => _progress = value);
    }
    try {
      final report = widget.contactSheet
        ? await widget.service.contactSheet(
            widget.requests,
            options: GalleryContactSheetOptions(columns: _columns,
              cellWidth: _tileSize, cellHeight: _tileSize * 3 ~/ 4,
              captions: _captions),
            cancellation: token, onProgress: progress,
          )
        : await widget.service.convert(
            widget.requests,
            options: GalleryConversionOptions(
              format: _format, quality: _quality.round(),
              maxWidth: _resize ? int.parse(_width.text.trim()) : null,
              maxHeight: _resize ? int.parse(_height.text.trim()) : null,
              allowUpscale: _upscale, quarterTurns: _quarterTurns,
              flipHorizontal: _flipHorizontal, flipVertical: _flipVertical,
              brightness: _brightness, contrast: _contrast,
              saturation: _saturation,
            ),
            cancellation: token, onProgress: progress,
          );
      if (mounted) setState(() => _report = report);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is GalleryExportException
          ? _problem(error.problem)
          : _t('Could not prepare this export. Try fewer or smaller images.',
            'Export konnte nicht erstellt werden. Weniger oder kleinere Bilder versuchen.'));
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _save() async {
    final report = _report;
    if (_busy || report == null || !report.hasOutput) return;
    if (widget.requests.any((request) => !request.isCurrent)) {
      setState(() => _error = _problem(GalleryExportProblem.staleSource));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _saveStatus = null;
    });
    try {
      final result = await widget.exporter(report.bytes!, report.suggestedName,
        mimeType: report.mimeType,
        dialogTitle: _t('Save gallery export', 'Galerieexport speichern'));
      if (!mounted) return;
      setState(() => _saveStatus = switch (result) {
        GalleryExportResult.savedCopy => _t('Copy saved.', 'Kopie gespeichert.'),
        GalleryExportResult.downloadedCopy =>
          _t('Download started.', 'Download gestartet.'),
        null => _t('Save cancelled. Your prepared export is still available.',
          'Speichern abgebrochen. Der vorbereitete Export ist weiterhin verfügbar.'),
      });
    } catch (_) {
      if (mounted) setState(() => _error =
        _t('The copy could not be saved. Try again.',
          'Die Kopie konnte nicht gespeichert werden. Bitte erneut versuchen.'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _cancel() {
    if (_running) {
      setState(() => _cancellation?.cancel());
    } else if (!_saving) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.contactSheet
      ? _t('Create contact sheet', 'Kontaktabzug erstellen')
      : _t('Batch image export', 'Bilder als Stapel exportieren');
    return PopScope(
      canPop: !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _running) _cancel();
      },
      child: Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 700,
            maxHeight: math.max(240.0, MediaQuery.sizeOf(context).height - 64)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
              child: Row(children: [
                Expanded(child: Text(title,
                  style: Theme.of(context).textTheme.titleLarge)),
                IconButton(onPressed: _saving ? null : _cancel,
                  tooltip: _t('Close', 'Schließen'),
                  icon: const Icon(Icons.close)),
              ]),
            ),
            Flexible(child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Form(key: _formKey, child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_t('${widget.requests.length} images selected',
                    '${widget.requests.length} Bilder ausgewählt'),
                    style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Text(widget.contactSheet
                    ? _t('Create a PNG overview with filenames. Animated and '
                        'multipage files use their first frame or page.',
                      'PNG-Übersicht mit Dateinamen erstellen. Bei Animationen '
                        'und mehrseitigen Dateien wird das erste Bild verwendet.')
                    : _t('Export new copies in a ZIP archive. EXIF, IPTC and XMP '
                        'are omitted; animated and multipage files use their first '
                        'frame or page. JPEG uses white behind transparency.',
                      'Neue Kopien als ZIP-Archiv exportieren. EXIF, IPTC und XMP '
                        'werden weggelassen; bei Animationen und mehrseitigen '
                        'Dateien wird das erste Bild verwendet. Transparente '
                        'Bereiche erhalten bei JPEG einen weißen Hintergrund.')),
                  const SizedBox(height: 16),
                  if (widget.contactSheet) _sheetOptions() else _conversionOptions(),
                  const SizedBox(height: 12),
                  Text(_t('Up to ${widget.service.limits.maxFiles} images; '
                      '${widget.service.limits.maxInputBytes ~/ (1024 * 1024)} MB per source. '
                      'Processing stops at the export size and pixel limits.',
                    'Bis zu ${widget.service.limits.maxFiles} Bilder; '
                      '${widget.service.limits.maxInputBytes ~/ (1024 * 1024)} MB pro Quelldatei. '
                      'Größen- und Pixelgrenzen begrenzen den Export.'),
                    style: Theme.of(context).textTheme.bodySmall),
                  if (_running) _progressView(),
                  if (_error != null) Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(_error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                  if (_report != null) _reportView(_report!),
                  if (_saveStatus != null) Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_saveStatus!),
                  ),
                  const SizedBox(height: 20),
                ],
              )),
            )),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8,
                children: [
                  TextButton(onPressed: _saving ? null : _cancel,
                    child: Text(_running
                      ? _t('Cancel after this image', 'Nach diesem Bild abbrechen')
                      : _t('Close', 'Schließen'))),
                  if (_report?.hasOutput == true)
                    OutlinedButton(onPressed: _busy ? null : _prepare,
                      child: Text(_t('Create again', 'Erneut erstellen'))),
                  FilledButton.icon(
                    onPressed: _busy ? null :
                      (_report?.hasOutput == true ? _save : _prepare),
                    icon: Icon(_report?.hasOutput == true ? Icons.save_alt :
                      widget.contactSheet ? Icons.grid_on : Icons.archive_outlined),
                    label: Text(_saving ? _t('Saving…', 'Wird gespeichert…') :
                      _report?.hasOutput == true ? _t('Save copy', 'Kopie speichern') :
                      widget.contactSheet ? _t('Create PNG', 'PNG erstellen') :
                      _t('Create ZIP', 'ZIP erstellen')),
                  ),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _conversionOptions() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(spacing: 16, runSpacing: 12, children: [
        SizedBox(width: 180, child: DropdownButtonFormField<GalleryExportFormat>(
          initialValue: _format,
          decoration: InputDecoration(labelText: _t('Format', 'Format')),
          items: const [
            DropdownMenuItem(value: GalleryExportFormat.jpeg, child: Text('JPEG')),
            DropdownMenuItem(value: GalleryExportFormat.png, child: Text('PNG')),
          ],
          onChanged: _busy ? null : (value) {
            if (value != null) _change(() => _format = value);
          },
        )),
        SizedBox(width: 210, child: DropdownButtonFormField<int>(
          initialValue: _quarterTurns,
          decoration: InputDecoration(labelText: _t('Rotate clockwise', 'Im Uhrzeigersinn drehen')),
          items: [0, 1, 2, 3].map((value) => DropdownMenuItem(value: value,
            child: Text('${value * 90}°'))).toList(),
          onChanged: _busy ? null : (value) {
            if (value != null) _change(() => _quarterTurns = value);
          },
        )),
      ]),
      if (_format == GalleryExportFormat.jpeg)
        _slider(_t('JPEG quality', 'JPEG-Qualität'), _quality, 1, 100,
          (value) => _quality = value, suffix: '${_quality.round()}'),
      SwitchListTile.adaptive(contentPadding: EdgeInsets.zero,
        title: Text(_t('Resize to fit', 'In Begrenzung einpassen')),
        subtitle: Text(_t('Keep the aspect ratio', 'Seitenverhältnis beibehalten')),
        value: _resize,
        onChanged: _busy ? null : (value) => _change(() => _resize = value)),
      if (_resize) ...[
        Row(children: [
          Expanded(child: TextFormField(controller: _width, enabled: !_busy,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: _t('Maximum width', 'Maximale Breite'),
              suffixText: 'px'), validator: _dimensionError,
            onChanged: (_) => _change(() {}))),
          const SizedBox(width: 16),
          Expanded(child: TextFormField(controller: _height, enabled: !_busy,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: _t('Maximum height', 'Maximale Höhe'),
              suffixText: 'px'), validator: _dimensionError,
            onChanged: (_) => _change(() {}))),
        ]),
        CheckboxListTile(contentPadding: EdgeInsets.zero,
          title: Text(_t('Allow enlarging smaller images', 'Kleinere Bilder vergrößern')),
          value: _upscale, controlAffinity: ListTileControlAffinity.leading,
          onChanged: _busy ? null : (value) => _change(() => _upscale = value ?? false)),
      ],
      Wrap(spacing: 12, runSpacing: 8, children: [
        FilterChip(label: Text(_t('Flip horizontally', 'Horizontal spiegeln')),
          selected: _flipHorizontal,
          onSelected: _busy ? null : (value) => _change(() => _flipHorizontal = value)),
        FilterChip(label: Text(_t('Flip vertically', 'Vertikal spiegeln')),
          selected: _flipVertical,
          onSelected: _busy ? null : (value) => _change(() => _flipVertical = value)),
      ]),
      const SizedBox(height: 6),
      ExpansionTile(tilePadding: EdgeInsets.zero,
        title: Text(_t('Color adjustments', 'Farbanpassungen')),
        children: [
          _slider(_t('Brightness', 'Helligkeit'), _brightness, 0, 2,
            (value) => _brightness = value),
          _slider(_t('Contrast', 'Kontrast'), _contrast, 0, 2,
            (value) => _contrast = value),
          _slider(_t('Saturation', 'Sättigung'), _saturation, 0, 2,
            (value) => _saturation = value),
        ],
      ),
    ],
  );

  Widget _sheetOptions() => Column(children: [
    Row(children: [
      Expanded(child: DropdownButtonFormField<int>(initialValue: _columns,
        decoration: InputDecoration(labelText: _t('Columns', 'Spalten')),
        items: List.generate(8, (index) => DropdownMenuItem(value: index + 1,
          child: Text('${index + 1}'))),
        onChanged: _busy ? null : (value) {
          if (value != null) _change(() => _columns = value);
        })),
      const SizedBox(width: 16),
      Expanded(child: DropdownButtonFormField<int>(initialValue: _tileSize,
        decoration: InputDecoration(labelText: _t('Tile width', 'Kachelbreite')),
        items: [160, 240, 320, 480, 640].map((value) => DropdownMenuItem(
          value: value, child: Text('$value px'))).toList(),
        onChanged: _busy ? null : (value) {
          if (value != null) _change(() => _tileSize = value);
        })),
    ]),
    CheckboxListTile(contentPadding: EdgeInsets.zero,
      title: Text(_t('Show filenames', 'Dateinamen anzeigen')),
      value: _captions, controlAffinity: ListTileControlAffinity.leading,
      onChanged: _busy ? null : (value) => _change(() => _captions = value ?? true)),
  ]);

  Widget _slider(String title, double value, double minimum, double maximum,
      void Function(double) change, {String? suffix}) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('$title: ${suffix ?? '${(value * 100).round()}%'}'),
      Slider(value: value, min: minimum, max: maximum,
        divisions: maximum == 100 ? 99 : 40,
        onChanged: _busy ? null : (next) => _change(() => change(next))),
    ]),
  );

  Widget _progressView() {
    final progress = _progress;
    final stage = switch (progress?.stage) {
      GalleryExportStage.loading => _t('Reading', 'Wird gelesen'),
      GalleryExportStage.processing => _t('Processing', 'Wird verarbeitet'),
      GalleryExportStage.finishing => _t('Creating output', 'Export wird erstellt'),
      null => _t('Preparing', 'Wird vorbereitet'),
    };
    return Padding(padding: const EdgeInsets.only(top: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LinearProgressIndicator(value: progress == null || progress.total == 0
          ? null : progress.completed / progress.total),
        const SizedBox(height: 8),
        Text(_cancellation?.isCancelled == true
          ? _t('Cancelling after the current operation…',
            'Nach dem aktuellen Vorgang wird abgebrochen…')
          : '$stage ${progress?.completed ?? 0}/${widget.requests.length}'
            '${progress?.fileName == null ? '' : ' · ${progress!.fileName}'}'),
      ]));
  }

  Widget _reportView(GalleryExportReport report) {
    final summary = report.cancelled
      ? _t('Export cancelled. No file was saved.', 'Export abgebrochen. Keine Datei gespeichert.')
      : !report.hasOutput
        ? _t('No images could be exported.', 'Es konnten keine Bilder exportiert werden.')
        : _t('${report.succeeded} ready · ${report.failed} skipped · '
            '${_size(report.bytes!.length)}',
          '${report.succeeded} bereit · ${report.failed} übersprungen · '
            '${_size(report.bytes!.length)}');
    return Padding(padding: const EdgeInsets.only(top: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(summary, style: Theme.of(context).textTheme.titleSmall),
        if (report.hasOutput && widget.contactSheet) Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Image.memory(report.bytes!, height: 180, cacheHeight: 360,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const SizedBox.shrink()),
        ),
        if (report.items.isNotEmpty) ExpansionTile(
          tilePadding: EdgeInsets.zero, initiallyExpanded: report.failed > 0,
          title: Text(_t('Per-file results', 'Ergebnisse pro Datei')),
          children: report.items.map((item) => ListTile(
            dense: true, contentPadding: EdgeInsets.zero,
            leading: Icon(item.succeeded ? Icons.check_circle_outline : Icons.error_outline,
              color: item.succeeded ? Theme.of(context).colorScheme.primary :
                Theme.of(context).colorScheme.error),
            title: Text(item.sourceName),
            subtitle: Text(item.problem != null ? _problem(item.problem!) :
              '${item.outputName ?? ''}${item.outputName == null ? '' : ' · '}'
              '${item.width} × ${item.height}'
              '${item.firstFrameOnly ? _t(' · first frame/page', ' · erstes Bild/erste Seite') : ''}'),
          )).toList(),
        ),
      ]));
  }

  String _size(int bytes) => bytes < 1024 * 1024
    ? '${(bytes / 1024).toStringAsFixed(1)} KB'
    : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  String _problem(GalleryExportProblem problem) => switch (problem) {
    GalleryExportProblem.noImages => _t('Select at least one image.', 'Mindestens ein Bild auswählen.'),
    GalleryExportProblem.tooManyFiles => _t('Choose no more than ${widget.service.limits.maxFiles} images.',
      'Höchstens ${widget.service.limits.maxFiles} Bilder auswählen.'),
    GalleryExportProblem.invalidOptions => _t('Check the export dimensions and settings.',
      'Exportabmessungen und Einstellungen prüfen.'),
    GalleryExportProblem.inputTooLarge => _t('Source file exceeds the input size limit.',
      'Quelldatei überschreitet die Größenbegrenzung.'),
    GalleryExportProblem.inputDimensionsTooLarge => _t('Source image exceeds the pixel limit.',
      'Quellbild überschreitet die Pixelbegrenzung.'),
    GalleryExportProblem.inputBudgetExceeded => _t('This batch exceeds the input budget. Export fewer images.',
      'Dieser Stapel ist zu groß. Weniger Bilder exportieren.'),
    GalleryExportProblem.unsupportedImage => _t('This format cannot be converted here.',
      'Dieses Format kann hier nicht konvertiert werden.'),
    GalleryExportProblem.invalidImage => _t('The image could not be decoded.',
      'Das Bild konnte nicht dekodiert werden.'),
    GalleryExportProblem.readFailed => _t('The source file could not be read.',
      'Die Quelldatei konnte nicht gelesen werden.'),
    GalleryExportProblem.staleSource => _t('The source or connection changed. Reopen the export.',
      'Quelle oder Verbindung geändert. Export erneut öffnen.'),
    GalleryExportProblem.outputTooLarge => _t('Output exceeds the size or pixel limit. Reduce its dimensions.',
      'Export überschreitet die Größen- oder Pixelgrenze. Abmessungen reduzieren.'),
    GalleryExportProblem.outputBudgetExceeded => _t('Export size limit reached. Choose fewer or smaller images.',
      'Exportgrößenbegrenzung erreicht. Weniger oder kleinere Bilder auswählen.'),
  };
}
