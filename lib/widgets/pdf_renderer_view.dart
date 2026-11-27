import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart' as editor;
import 'package:pdf_cos/pdf_cos.dart' show CosPasswordException;
import 'package:quds_office_editor/quds_office_editor.dart' as office;

import '../services/log_service.dart';

import '../l10n/commander_strings.dart';
import '../services/pdf_open_preferences.dart';
import 'document_page_navigation.dart';
import 'pdf_review_status.dart';

/// Read-only PDF surfaces. No edit controller, form writer or save callback is
/// supplied to either engine. Switching engines never writes the source.
class PdfRendererView extends StatefulWidget {
  const PdfRendererView({
    super.key,
    required this.bytes,
    required this.backend,
    required this.onCompatibility,
    this.onOpenFailure,
    this.autoRenderWorker = true,
  });
  final Uint8List bytes;
  final PdfViewerBackend backend;
  final VoidCallback onCompatibility;
  final bool Function(PdfViewerBackend)? onOpenFailure;
  final bool autoRenderWorker;
  @override
  State<PdfRendererView> createState() => PdfRendererViewState();
}

class PdfRendererViewState extends State<PdfRendererView> {
  editor.PdfDocument? _document;
  final _viewer = editor.PdfViewerController();
  office.PdfViewerController? _office;
  String? _error;
  Size _size = Size.zero;
  @override
  void initState() {
    super.initState();
    editor.PdfPerfLog.diagnosticSink = const Log('PdfRenderer').warn;
    _viewer.addListener(_changed);
    _viewer.viewportChanges.addListener(_changed);
    _scheduleOpen();
  }

  @override
  void didUpdateWidget(PdfRendererView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.backend != widget.backend ||
        !identical(oldWidget.bytes, widget.bytes)) {
      final old = _office;
      _office = null;
      old?.removeListener(_changed);
      _document = null;
      _error = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        old?.dispose();
      });
      _scheduleOpen();
    }
  }

  bool _changeQueued = false;
  (int, int, double)? _footerMetrics;
  void _changed() {
    if (!mounted) return;
    final metrics = (_page, _count, zoom);
    if (metrics == _footerMetrics) return;
    _footerMetrics = metrics;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_changeQueued) return;
      _changeQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _changeQueued = false;
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _viewer.viewportChanges.removeListener(_changed);
    _viewer.removeListener(_changed);
    _viewer.dispose();
    _office?.dispose();
    super.dispose();
  }

  int _openEpoch = 0;
  void _scheduleOpen() {
    final epoch = ++_openEpoch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && epoch == _openEpoch) _open(epoch);
    });
  }

  Future<void> _open(int epoch) async {
    if (widget.bytes.length > 64 * 1024 * 1024) {
      if (widget.onOpenFailure?.call(widget.backend) == true) return;
      setState(
        () => _error =
            'Use the native compatibility viewer for PDFs larger than 64 MiB.',
      );
      return;
    }
    var password = '';
    while (mounted && epoch == _openEpoch) {
      try {
        if (widget.backend == PdfViewerBackend.crispOffice) {
          final file = office.PdfFile.open(widget.bytes, password: password);
          _office = office.PdfViewerController(
            file: file,
            lists: List.generate(
              file.pageCount,
              (index) => _DeferredOfficePdfPage(file, index),
              growable: false,
            ),
          )..addListener(_changed);
        } else {
          _document = editor.PdfDocument.open(widget.bytes, password: password);
        }
        if (mounted) setState(() {});
        return;
      } catch (error) {
        final needsPassword =
            error is CosPasswordException ||
            error is office.PdfOpenException &&
                error.error == office.PdfOpenError.wrongPassword;
        if (!needsPassword) {
          const Log('PdfRenderer').warn(
            'PDF engine ${widget.backend.name} open failed (${error.runtimeType})',
          );
          if (!mounted || epoch != _openEpoch) return;
          if (widget.onOpenFailure?.call(widget.backend) == true) return;
          setState(() => _error = '$error');
          return;
        }
        final entered = await _password();
        if (!mounted || epoch != _openEpoch) return;
        if (entered == null) {
          setState(
            () => _error = context.commanderTr('Password entry cancelled.'),
          );
          return;
        }
        password = entered;
      }
    }
  }

  Future<String?> _password() async {
    final input = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.commanderTr('PDF password')),
        content: TextField(
          controller: input,
          autofocus: true,
          obscureText: true,
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.commanderTr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, input.text),
            child: Text(context.commanderTr('Open')),
          ),
        ],
      ),
    );
    // Dialog exit animations can still reference the controller in this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      input.dispose();
    });
    return value;
  }

  double get zoom => _office?.viewport.scale ?? _viewer.zoom;
  void zoomBy(double factor) {
    final value = (zoom * factor).clamp(.25, 16.0);
    if (_office case final c?) {
      c.setScale(value, animate: false);
    } else {
      _viewer.setZoom(value);
    }
  }

  void _fit(bool width) {
    if (_office case final c?) {
      if (width) {
        c.fitWidth(_size.width);
      } else {
        c.fitPage(_size.width, _size.height);
      }
      return;
    }
    final doc = _document;
    if (doc == null || doc.pageCount == 0) return;
    final page = doc.page(_viewer.currentPage.clamp(0, doc.pageCount - 1));
    final box = page.cropBox;
    final sideways = page.rotation == 90 || page.rotation == 270;
    final widthPoints = sideways ? box.height : box.width;
    final heightPoints = sideways ? box.width : box.height;
    final x = (_size.width - 32) / widthPoints;
    final y = (_size.height - 32) / heightPoints;
    _viewer.setZoom((width ? x : math.min(x, y)).clamp(.25, 16.0));
  }

  int get _page => _office?.pageIndex ?? _viewer.currentPage;
  int get _count => _office?.pageCount ?? _document?.pageCount ?? 0;

  void scrollPage(int direction) {
    if (_office case final controller?) {
      scrollOfficePdfViewport(controller, direction);
    } else {
      scrollPdfViewport(_viewer, direction);
    }
  }

  void _jump(int delta) {
    if (_count == 0) return;
    final page = (_page + delta).clamp(0, _count - 1);
    if (_office case final c?) {
      c.goToPage(page);
    } else {
      _viewer.jumpToPage(page);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error case final error?) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SelectableText(error),
            TextButton(
              onPressed: widget.onCompatibility,
              child: Text(
                context.commanderTr('Open in native compatibility viewer'),
              ),
            ),
          ],
        ),
      );
    }
    if (_office == null && _document == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        if (_office case final controller?)
          PdfReviewStatus(
            controller: controller,
            onCompatibility: widget.onCompatibility,
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              _size = Size(box.maxWidth, box.maxHeight);
              return _office != null
                  ? office.QudsPdfViewer(
                      controller: _office!,
                      options: const office.PdfViewerOptions(
                        minZoom: .25,
                        maxZoom: 16,
                      ),
                      config: const office.OfficeSurfaceConfig(
                        mode: office.OfficeInteractionMode.viewing,
                        showRulers: false,
                      ),
                    )
                  : editor.PdfViewer(
                      document: _document,
                      autoRenderWorker: widget.autoRenderWorker,
                      controller: _viewer,
                      interactiveForms: false,
                      textSelectionEditing: false,
                      textSelectionMarkup: false,
                      textSelectionRedaction: false,
                      initialFit: editor.PdfViewerFit.width,
                      maxZoom: 16,
                    );
            },
          ),
        ),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(
              tooltip: context.commanderTr('Previous page'),
              onPressed: _page > 0 ? () => _jump(-1) : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Text('${_page + 1} / $_count'),
            IconButton(
              tooltip: context.commanderTr('Next page'),
              onPressed: _page + 1 < _count ? () => _jump(1) : null,
              icon: const Icon(Icons.chevron_right),
            ),
            IconButton(
              key: const ValueKey('pdf-renderer-zoom-out'),
              tooltip: context.commanderTr('Zoom out'),
              onPressed: () => zoomBy(1 / 1.2),
              icon: const Icon(Icons.zoom_out),
            ),
            Text('${(zoom * 100).round()}%'),
            IconButton(
              key: const ValueKey('pdf-renderer-zoom-in'),
              tooltip: context.commanderTr('Zoom in'),
              onPressed: () => zoomBy(1.2),
              icon: const Icon(Icons.zoom_in),
            ),
            TextButton(
              onPressed: () => _fit(true),
              child: Text(context.commanderTr('Fit width')),
            ),
            TextButton(
              onPressed: () => _fit(false),
              child: Text(context.commanderTr('Fit page')),
            ),
          ],
        ),
      ],
    );
  }
}

/// Layout can read all page sizes without interpreting their contents. The
/// canvas requests paint operations only for pages near the viewport.
class _DeferredOfficePdfPage extends office.PdfDisplayList {
  _DeferredOfficePdfPage(this._file, this._index)
    : super(page: _file.pageAt(_index));

  final office.PdfFile _file;
  final int _index;
  static const _log = Log('PdfRenderer');
  late final office.PdfDisplayList _content = _load();

  office.PdfDisplayList _load() {
    try {
      final content = _file.displayList(_index);
      if (content.issues.isNotEmpty) {
        _log.warn(
          'CrispOffice page ${_index + 1} incomplete '
          'issues=${content.issues.map((issue) => issue.name).join(",")}',
        );
      }
      return content;
    } on Object catch (error) {
      _log.warn('CrispOffice page ${_index + 1} failed (${error.runtimeType})');
      rethrow;
    }
  }

  @override
  List<office.PdfPaintOp> get ops => _content.ops;

  @override
  List<office.PdfTextRun> get runs => _content.runs;

  @override
  List<office.PdfHotspot> get hotspots => _content.hotspots;

  @override
  Set<office.PdfPageRenderIssue> get issues => _content.issues;
}
