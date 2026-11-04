import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:quds_office_engine/pdf_file.dart';

import '../editor_pdf/render_pdf_canvas.dart';
import 'office_context_menu.dart';
import 'office_theme.dart';
import 'pdf_controller.dart';
import 'pdf_viewer_options.dart';

/// Display-only PDF surface (`viewing` / `selecting`).
class QudsPdfViewer extends StatefulWidget {
  /// QudsPdfViewer API.
  const QudsPdfViewer({
    super.key,
    required this.controller,
    this.config,
    this.options = const PdfViewerOptions(),
    this.toolbarBuilder,
    this.statusBarBuilder,
    this.onViewCreated,
    this.onLoadComplete,
    this.onPageChanged,
    this.onRender,
    this.onError,
    this.onPageError,
    this.onFollowLink,
    this.onLinkHandle,
    this.onDraw,
  });

  /// controller API.
  final PdfViewerController controller;

  /// config API.
  final OfficeSurfaceConfig? config;

  /// Tunable viewer behaviour (zoom clamps, swipe, night mode, …).
  final PdfViewerOptions options;

  /// toolbarBuilder API.
  final Widget Function(BuildContext context, PdfViewerController controller)?
  toolbarBuilder;

  /// statusBarBuilder API.
  final Widget Function(BuildContext context, PdfViewerController controller)?
  statusBarBuilder;

  /// Fired once when the surface mounts.
  final PdfViewCreatedCallback? onViewCreated;

  /// Fired when [controller] already has pages (or after the first frame).
  final PdfLoadCompleteCallback? onLoadComplete;

  /// Fired when the visible page index changes.
  final PdfPageChangedCallback? onPageChanged;

  /// Fired when a page raster finishes.
  final PdfRenderCallback? onRender;

  /// Fired when opening / loading fails (host-driven loads).
  final PdfErrorCallback? onError;

  /// Fired when a single page raster fails.
  final PdfPageErrorCallback? onPageError;

  /// onFollowLink API (also receives prevented URI navigations).
  final void Function(PdfLinkAction action)? onFollowLink;

  /// Alias for link activations; prefer this when using [options.preventLinkNavigation].
  final PdfLinkHandleCallback? onLinkHandle;

  /// Optional host overlay after a page is painted.
  final PdfDrawCallback? onDraw;

  @override
  State<QudsPdfViewer> createState() => _QudsPdfViewerState();
}

class _QudsPdfViewerState extends State<QudsPdfViewer> {
  OverlayEntry? _contextMenu;
  var _lastPage = -1;
  var _appliedInitialFit = false;
  var _notifiedCreated = false;
  var _notifiedLoad = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_tick);
    if (widget.config != null) {
      widget.controller.config = widget.config!;
    }
    widget.controller.applyOptions(widget.options, jumpToDefaultPage: true);
    widget.controller.onError = widget.onError;
    _lastPage = widget.controller.pageIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (!_notifiedCreated) {
        _notifiedCreated = true;
        widget.onViewCreated?.call(widget.controller);
      }
      _maybeLoadComplete();
      _applyInitialFit();
    });
  }

  @override
  void didUpdateWidget(covariant QudsPdfViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_tick);
      widget.controller.addListener(_tick);
      _appliedInitialFit = false;
      _notifiedLoad = false;
      _lastPage = widget.controller.pageIndex;
    }
    if (oldWidget.config != widget.config && widget.config != null) {
      widget.controller.config = widget.config!;
    }
    if (oldWidget.options != widget.options) {
      widget.controller.applyOptions(widget.options);
      _appliedInitialFit = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _applyInitialFit();
        }
      });
    }
    widget.controller.onError = widget.onError;
  }

  @override
  void dispose() {
    OfficeContextMenu.dismiss(_contextMenu);
    widget.controller.removeListener(_tick);
    super.dispose();
  }

  void _maybeLoadComplete() {
    if (_notifiedLoad) {
      return;
    }
    final int count = widget.controller.pageCount;
    if (count <= 0) {
      return;
    }
    _notifiedLoad = true;
    widget.onLoadComplete?.call(count);
  }

  void _applyInitialFit() {
    if (_appliedInitialFit) {
      return;
    }
    final Size extent = widget.controller.viewport.extent;
    if (extent.width <= 0 || extent.height <= 0) {
      SchedulerBinding.instance.scheduleFrameCallback((_) {
        if (mounted) {
          _applyInitialFit();
        }
      });
      return;
    }
    _appliedInitialFit = true;
    widget.controller.applyFitPolicy(widget.options.fitPolicy);
  }

  void _emitPageChanged() {
    final int page = widget.controller.pageIndex;
    if (page == _lastPage) {
      return;
    }
    _lastPage = page;
    widget.onPageChanged?.call(page, widget.controller.pageCount);
  }

  void _showContext(PdfContextHit hit) {
    OfficeContextMenu.dismiss(_contextMenu);
    _contextMenu = OfficeContextMenu.show(
      context: context,
      globalPosition: hit.globalPosition,
      actions: OfficeContextMenu.pdf(controller: widget.controller, hit: hit),
      onSelect: (String id) {
        _contextMenu = null;
        _runContext(id, hit);
      },
    );
  }

  void _runContext(String id, PdfContextHit hit) {
    final PdfViewerController c = widget.controller;
    final Size view = c.viewport.extent;
    switch (id) {
      case 'copy':
        c.copyToClipboard();
      case 'selectAll':
        c.selectAll();
      case 'selectPage':
        c.selectPage(hit.pageIndex);
      case 'followLink':
        final PdfLinkAction? link = hit.link;
        if (link != null) {
          _handleLink(link);
        }
      case 'zoomIn':
        c.zoomBy(1.1);
      case 'zoomOut':
        c.zoomBy(1 / 1.1);
      case 'actualSize':
        c.setScale(1);
      case 'fitWidth':
        c.fitWidth(view.width > 0 ? view.width : 720);
      case 'fitPage':
        c.fitPage(
          view.width > 0 ? view.width : 720,
          view.height > 0 ? view.height : 900,
        );
      case 'previousPage':
        c.goToPage(hit.pageIndex - 1);
      case 'nextPage':
        c.goToPage(hit.pageIndex + 1);
      case 'highlight':
      case 'strikethrough':
      case 'underline':
      case 'deleteAnnot':
      case 'rotatePage':
      case 'rotatePageLeft':
      case 'insertPage':
      case 'deletePage':
      case 'undo':
      case 'redo':
        _runEdit(id, hit);
    }
  }

  void _handleLink(PdfLinkAction action) {
    widget.controller.followLink(action);
    widget.onLinkHandle?.call(action);
    widget.onFollowLink?.call(action);
  }

  void _runEdit(String id, PdfContextHit hit) {
    final PdfViewerController viewer = widget.controller;
    if (viewer is! PdfEditorController || !viewer.config.allowsMutation) {
      return;
    }
    switch (id) {
      case 'highlight':
        viewer.markSelection('Highlight');
      case 'strikethrough':
        viewer.markSelection('StrikeOut', color: 0xCCE53935);
      case 'underline':
        viewer.markSelection('Underline', color: 0xCC1565C0);
      case 'deleteAnnot':
        final PdfAnnot? annot = hit.annot;
        if (annot != null) {
          viewer.deleteAnnot(hit.pageIndex, annot);
        }
      case 'rotatePage':
        viewer.rotatePageAt(hit.pageIndex, 90);
      case 'rotatePageLeft':
        viewer.rotatePageAt(hit.pageIndex, -90);
      case 'insertPage':
        viewer.insertBlankPage(hit.pageIndex + 1);
      case 'deletePage':
        viewer.deletePageAt(hit.pageIndex);
      case 'undo':
        viewer.undo();
      case 'redo':
        viewer.redo();
    }
  }

  void _tick() {
    _maybeLoadComplete();
    _emitPageChanged();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final PdfViewerController c = widget.controller;
    final PdfViewerOptions opts = widget.options;
    return Column(
      children: <Widget>[
        if (widget.toolbarBuilder != null) widget.toolbarBuilder!(context, c),
        Expanded(
          child: Focus(
            autofocus: true,
            onKeyEvent: (FocusNode node, KeyEvent event) {
              if (event is! KeyDownEvent) {
                return KeyEventResult.ignored;
              }
              final bool shortcut =
                  HardwareKeyboard.instance.isControlPressed ||
                  HardwareKeyboard.instance.isMetaPressed;
              if (shortcut && event.logicalKey == LogicalKeyboardKey.keyC) {
                c.copyToClipboard();
                return KeyEventResult.handled;
              }
              if (shortcut && event.logicalKey == LogicalKeyboardKey.keyA) {
                if (HardwareKeyboard.instance.isShiftPressed) {
                  c.selectPage(c.pageIndex);
                } else {
                  c.selectAll();
                }
                return KeyEventResult.handled;
              }
              if (shortcut && event.logicalKey == LogicalKeyboardKey.keyZ) {
                final PdfEditorController? editor = c is PdfEditorController
                    ? c
                    : null;
                if (editor != null && editor.config.allowsMutation) {
                  if (HardwareKeyboard.instance.isShiftPressed) {
                    editor.redo();
                  } else {
                    editor.undo();
                  }
                  return KeyEventResult.handled;
                }
              }
              if (shortcut && event.logicalKey == LogicalKeyboardKey.keyY) {
                final PdfEditorController? editor = c is PdfEditorController
                    ? c
                    : null;
                if (editor != null && editor.config.allowsMutation) {
                  editor.redo();
                  return KeyEventResult.handled;
                }
              }
              if (shortcut &&
                  (event.logicalKey == LogicalKeyboardKey.equal ||
                      event.logicalKey == LogicalKeyboardKey.numpadAdd ||
                      event.logicalKey == LogicalKeyboardKey.add)) {
                c.zoomBy(1.1);
                return KeyEventResult.handled;
              }
              if (shortcut &&
                  (event.logicalKey == LogicalKeyboardKey.minus ||
                      event.logicalKey == LogicalKeyboardKey.numpadSubtract)) {
                c.zoomBy(1 / 1.1);
                return KeyEventResult.handled;
              }
              if (shortcut && event.logicalKey == LogicalKeyboardKey.digit0) {
                c.setScale(1);
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.escape) {
                c.setSelection(null);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: PdfCanvasView(
              lists: c.lists,
              viewport: c.viewport,
              scale: c.viewport.scale,
              config: c.config,
              selection: c.selection,
              findMarks: c.findMarks,
              findIndex: c.findIndex,
              annots: <List<PdfAnnot>>[
                if (c.file != null)
                  for (int i = 0; i < c.pageCount; i++) c.file!.annotsOn(i),
              ],
              editing: c is PdfEditorController,
              enableSwipe: opts.enableSwipe,
              swipeHorizontal: opts.swipeHorizontal,
              pageFling: opts.pageFling,
              pageSnap: opts.pageSnap,
              showScrollIndicators: opts.showScrollIndicators,
              nightMode: opts.nightMode,
              backgroundColor: opts.backgroundColor,
              onChanged: c.viewportChanged,
              onZoomBy: (double factor, Offset focal, {bool animate = true}) {
                c.zoomBy(factor, focal: focal, animate: animate);
              },
              onFollowLink: _handleLink,
              onSelectText: c.setSelection,
              onContextMenu: _showContext,
              onRender: widget.onRender,
              onPageError: widget.onPageError,
              onDraw: widget.onDraw,
              onGestureSettled: c.snapToNearestPage,
            ),
          ),
        ),
        if (widget.statusBarBuilder != null)
          widget.statusBarBuilder!(context, c),
      ],
    );
  }
}

/// Annotate / form-fill PDF surface.
class QudsPdfEditor extends StatelessWidget {
  /// QudsPdfEditor API.
  const QudsPdfEditor({
    super.key,
    required this.controller,
    this.config,
    this.options = const PdfViewerOptions(),
    this.toolbarBuilder,
    this.statusBarBuilder,
    this.onViewCreated,
    this.onLoadComplete,
    this.onPageChanged,
    this.onRender,
    this.onError,
    this.onPageError,
    this.onFollowLink,
    this.onLinkHandle,
    this.onDraw,
  });

  /// controller API.
  final PdfEditorController controller;

  /// config API.
  final OfficeSurfaceConfig? config;

  /// Forwarded viewer options (night invert is skipped while editing).
  final PdfViewerOptions options;

  /// toolbarBuilder API.
  final Widget Function(BuildContext context, PdfEditorController controller)?
  toolbarBuilder;

  /// statusBarBuilder API.
  final Widget Function(BuildContext context, PdfEditorController controller)?
  statusBarBuilder;

  /// Fired once when the surface mounts.
  final PdfViewCreatedCallback? onViewCreated;

  /// Fired when pages are ready.
  final PdfLoadCompleteCallback? onLoadComplete;

  /// Fired when the visible page index changes.
  final PdfPageChangedCallback? onPageChanged;

  /// Fired when a page raster finishes.
  final PdfRenderCallback? onRender;

  /// Fired when opening / loading fails.
  final PdfErrorCallback? onError;

  /// Fired when a single page raster fails.
  final PdfPageErrorCallback? onPageError;

  /// onFollowLink API.
  final void Function(PdfLinkAction action)? onFollowLink;

  /// Link activations (including when navigation is prevented).
  final PdfLinkHandleCallback? onLinkHandle;

  /// Optional host overlay after a page is painted.
  final PdfDrawCallback? onDraw;

  @override
  Widget build(BuildContext context) {
    return QudsPdfViewer(
      controller: controller,
      config: config ?? controller.config,
      options: options,
      toolbarBuilder: toolbarBuilder == null
          ? null
          : (BuildContext ctx, PdfViewerController _) =>
                toolbarBuilder!(ctx, controller),
      statusBarBuilder: statusBarBuilder == null
          ? null
          : (BuildContext ctx, PdfViewerController _) =>
                statusBarBuilder!(ctx, controller),
      onViewCreated: onViewCreated,
      onLoadComplete: onLoadComplete,
      onPageChanged: onPageChanged,
      onRender: onRender,
      onError: onError,
      onPageError: onPageError,
      onFollowLink: onFollowLink,
      onLinkHandle: onLinkHandle,
      onDraw: onDraw,
    );
  }
}
