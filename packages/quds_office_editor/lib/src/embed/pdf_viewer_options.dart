import 'dart:ui' show Canvas, Color, Size;

import 'package:quds_office_engine/pdf_file.dart';

import 'pdf_controller.dart';

/// How the first layout pass sizes the page to the viewport.
enum PdfFitPolicy {
  /// Scale so the page width fills the view (default).
  width,

  /// Scale so the whole page fits inside the view.
  page,

  /// Scale so the page height fills the view.
  height,

  /// Keep the current scale.
  none,
}

/// Tunable viewer behaviour. Pass on [QudsPdfViewer] / [QudsPdfEditor].
class PdfViewerOptions {
  /// PdfViewerOptions API.
  const PdfViewerOptions({
    this.defaultPage = 0,
    this.fitPolicy = PdfFitPolicy.width,
    this.minZoom = 0.25,
    this.maxZoom = 4.0,
    this.enableSwipe = true,
    this.swipeHorizontal = false,
    this.pageFling = true,
    this.pageSnap = false,
    this.preventLinkNavigation = false,
    this.backgroundColor,
    this.nightMode = false,
    this.showScrollIndicators = true,
    this.password,
  });

  /// Zero-based page shown after open / first layout.
  final int defaultPage;

  /// Initial fit after the viewport has a non-zero extent.
  final PdfFitPolicy fitPolicy;

  /// Lower scale clamp (logical zoom).
  final double minZoom;

  /// Upper scale clamp (logical zoom).
  final double maxZoom;

  /// When false, pan and wheel scroll are ignored (Ctrl+zoom still works).
  final bool enableSwipe;

  /// Stack pages left-to-right instead of top-to-bottom.
  final bool swipeHorizontal;

  /// Keep scroll momentum after pointer-up. When false, velocity is cleared.
  final bool pageFling;

  /// After a drag/fling settles, align to the nearest page edge.
  final bool pageSnap;

  /// Deliver the link to [onLinkHandle] / [onFollowLink] but do not open URIs.
  final bool preventLinkNavigation;

  /// Canvas chrome behind the paper. Null keeps the theme surface colour.
  final Color? backgroundColor;

  /// Invert page rasters for a dark reading surface (viewer paint only).
  final bool nightMode;

  /// Show the overlay scrollbar.
  final bool showScrollIndicators;

  /// Optional password used by host helpers that load through the widget.
  final String? password;

  /// copyWith API.
  PdfViewerOptions copyWith({
    int? defaultPage,
    PdfFitPolicy? fitPolicy,
    double? minZoom,
    double? maxZoom,
    bool? enableSwipe,
    bool? swipeHorizontal,
    bool? pageFling,
    bool? pageSnap,
    bool? preventLinkNavigation,
    Color? backgroundColor,
    bool? nightMode,
    bool? showScrollIndicators,
    String? password,
  }) {
    return PdfViewerOptions(
      defaultPage: defaultPage ?? this.defaultPage,
      fitPolicy: fitPolicy ?? this.fitPolicy,
      minZoom: minZoom ?? this.minZoom,
      maxZoom: maxZoom ?? this.maxZoom,
      enableSwipe: enableSwipe ?? this.enableSwipe,
      swipeHorizontal: swipeHorizontal ?? this.swipeHorizontal,
      pageFling: pageFling ?? this.pageFling,
      pageSnap: pageSnap ?? this.pageSnap,
      preventLinkNavigation:
          preventLinkNavigation ?? this.preventLinkNavigation,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      nightMode: nightMode ?? this.nightMode,
      showScrollIndicators: showScrollIndicators ?? this.showScrollIndicators,
      password: password ?? this.password,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PdfViewerOptions &&
        other.defaultPage == defaultPage &&
        other.fitPolicy == fitPolicy &&
        other.minZoom == minZoom &&
        other.maxZoom == maxZoom &&
        other.enableSwipe == enableSwipe &&
        other.swipeHorizontal == swipeHorizontal &&
        other.pageFling == pageFling &&
        other.pageSnap == pageSnap &&
        other.preventLinkNavigation == preventLinkNavigation &&
        other.backgroundColor == backgroundColor &&
        other.nightMode == nightMode &&
        other.showScrollIndicators == showScrollIndicators &&
        other.password == password;
  }

  @override
  int get hashCode => Object.hash(
    defaultPage,
    fitPolicy,
    minZoom,
    maxZoom,
    enableSwipe,
    swipeHorizontal,
    pageFling,
    pageSnap,
    preventLinkNavigation,
    backgroundColor,
    nightMode,
    showScrollIndicators,
    password,
  );
}

/// Fired once when the viewer surface mounts with its controller.
typedef PdfViewCreatedCallback = void Function(PdfViewerController controller);

/// Fired after bytes are opened and display lists are ready.
typedef PdfLoadCompleteCallback = void Function(int pageCount);

/// Fired when the visible page index changes.
typedef PdfPageChangedCallback = void Function(int page, int total);

/// Fired when a page raster finishes successfully.
typedef PdfRenderCallback = void Function(int page);

/// Fired when opening or loading the document fails.
typedef PdfErrorCallback = void Function(Object error);

/// Fired when a single page raster fails.
typedef PdfPageErrorCallback = void Function(int page, Object error);

/// Fired for link activations (uri or go-to).
typedef PdfLinkHandleCallback = void Function(PdfLinkAction action);

/// Fired after a page is painted so the host can overlay ink.
typedef PdfDrawCallback = void Function(Canvas canvas, Size size, int page);
