/// Constraint-layout protocol, document, and page composers.
library;

import 'dart:typed_data';

import '../../fonts/font_subsetter.dart';
import '../../fonts/sfnt_parser.dart';
import '../../pdf/pdf_canvas.dart';
import '../../pdf/pdf_document.dart';
import 'pw_style.dart';
import 'pw_types.dart';

/// Builds a single child from the current [Context].
typedef BuildCallback = Widget Function(Context context);

/// Builds a flowing list of children (used by [MultiPage]).
typedef BuildListCallback = List<Widget> Function(Context context);

/// Rebuilds a subtree.
typedef WidgetBuilder = Widget Function(Context context);

/// Heading recorded for TOC / PDF outlines.
class PwHeading {
  /// PwHeading API.
  PwHeading({
    required this.level,
    required this.title,
    required this.pageNumber,
    this.destY = 0,
  });

  /// level API.
  final int level;

  /// title API.
  final String title;

  /// 1-based page number.
  final int pageNumber;

  /// Set once the heading box has a page position.
  var placed = false;

  /// Top-left page Y, filled when the heading is placed.
  double destY;
}

/// Layout / paint environment. Flutter-like, no `dart:ui`.
class Context {
  /// Context API.
  Context({
    required this.document,
    required this.pageFormat,
    required this.theme,
    required this.textDirection,
    this.pageNumber = 1,
    this.pagesCount = 1,
    this.canvas,
    this.subset,
    this.boldSubset,
    Set<int>? usedCodePoints,
    List<PdfEmbeddedImage>? images,
    List<PdfLinkAnnot>? links,
    List<PdfAcroField>? acroFields,
    List<PwHeading>? headings,
    List<PwHeading>? frozenHeadings,
    Map<String, PwHeading>? anchors,
    this.measuring = false,
  }) : usedCodePoints = usedCodePoints ?? <int>{},
       images = images ?? <PdfEmbeddedImage>[],
       links = links ?? <PdfLinkAnnot>[],
       acroFields = acroFields ?? <PdfAcroField>[],
       headings = headings ?? <PwHeading>[],
       frozenHeadings = frozenHeadings ?? <PwHeading>[],
       anchors = anchors ?? <String, PwHeading>{};

  /// document API.
  final Document document;

  /// pageFormat API.
  final PdfPageFormat pageFormat;

  /// theme API.
  final ThemeData theme;

  /// textDirection API.
  final TextDirection textDirection;

  /// pageNumber API.
  int pageNumber;

  /// pagesCount API.
  int pagesCount;

  /// canvas API.
  PdfCanvas? canvas;

  /// subset API (regular face → `/F1`).
  FontSubset? subset;

  /// Bold face subset → `/F3`.
  FontSubset? boldSubset;

  /// usedCodePoints API.
  final Set<int> usedCodePoints;

  /// images API.
  final List<PdfEmbeddedImage> images;

  /// links API.
  final List<PdfLinkAnnot> links;

  /// AcroForm fields registered during paint.
  final List<PdfAcroField> acroFields;

  /// headings API.
  final List<PwHeading> headings;

  /// Frozen headings from the measure pass (TOC page numbers).
  final List<PwHeading> frozenHeadings;

  /// Named destinations.
  final Map<String, PwHeading> anchors;

  /// Probe pass ([IntrinsicHeight]). Headings recorded here are discarded.
  final bool measuring;

  /// font API.
  SfntFont? get font => document.font;

  /// Bold face when embedded.
  SfntFont? get fontBold => document.fontBold;

  /// Face used for measurement / paint for [bold].
  SfntFont? faceFor({required bool bold}) {
    if (bold && document.fontBold != null) {
      return document.fontBold;
    }
    return document.font;
  }

  /// Subset + resource name for [bold].
  ({FontSubset? subset, String fontName}) embedFor({required bool bold}) {
    if (bold && boldSubset != null) {
      return (subset: boldSubset, fontName: 'F3');
    }
    return (subset: subset, fontName: 'F1');
  }

  /// copyWith API.
  Context copyWith({
    ThemeData? theme,
    TextDirection? textDirection,
    PdfPageFormat? pageFormat,
    bool? measuring,
  }) {
    return Context(
      document: document,
      pageFormat: pageFormat ?? this.pageFormat,
      theme: theme ?? this.theme,
      textDirection: textDirection ?? this.textDirection,
      pageNumber: pageNumber,
      pagesCount: pagesCount,
      canvas: canvas,
      subset: subset,
      boldSubset: boldSubset,
      usedCodePoints: usedCodePoints,
      images: images,
      links: links,
      acroFields: acroFields,
      headings: headings,
      frozenHeadings: frozenHeadings,
      anchors: anchors,
      measuring: measuring ?? this.measuring,
    );
  }

  /// useText API.
  void useText(String text) {
    for (final int cp in text.runes) {
      usedCodePoints.add(cp);
    }
  }

  /// nextImageName API.
  String nextImageName() => 'Im${images.length + 1}';

  /// registerHeading API.
  void registerHeading(int level, String title, {double destY = 0}) {
    if (measuring) {
      return;
    }
    final PwHeading heading = PwHeading(
      level: level,
      title: title,
      pageNumber: pageNumber,
      destY: destY,
    );
    headings.add(heading);
    if (title.isNotEmpty) {
      anchors[title] = heading;
    }
  }

  /// Stamp the first unplaced heading named [title] with a top-left [destY].
  void placeHeading(String title, double destY) {
    for (final PwHeading heading in headings) {
      if (heading.title != title ||
          heading.pageNumber != pageNumber ||
          heading.placed) {
        continue;
      }
      heading.destY = destY;
      heading.placed = true;
      anchors[title] = heading;
      return;
    }
  }

  /// Registers an AcroForm field for this page.
  void registerAcroField(PdfAcroField field) {
    if (measuring || field.name.isEmpty) {
      return;
    }
    acroFields.add(field);
  }

  /// registerAnchor API.
  void registerAnchor(String name, {double destY = 0}) {
    if (measuring) {
      return;
    }
    anchors[name] = PwHeading(
      level: 0,
      title: name,
      pageNumber: pageNumber,
      destY: destY,
    );
  }

  /// pageOfHeading API.
  int? pageOfHeading(String title) => headingNamed(title)?.pageNumber;

  /// Frozen heading from the previous pass, else one recorded this pass.
  PwHeading? headingNamed(String title) {
    for (final PwHeading heading in frozenHeadings) {
      if (heading.title == title) {
        return heading;
      }
    }
    for (final PwHeading heading in headings) {
      if (heading.title == title) {
        return heading;
      }
    }
    return null;
  }

  /// Headings registered during [child] layout do not yet know their page y.
  void restampHeadings({
    required int from,
    required int pageNumber,
    required double destY,
  }) {
    final int start = from < 0 ? 0 : from;
    for (int i = start; i < headings.length; i++) {
      final PwHeading heading = headings[i];
      headings[i] = PwHeading(
        level: heading.level,
        title: heading.title,
        pageNumber: pageNumber,
        destY: destY,
      );
    }
  }
}

/// Measured widget. Users subclass [Widget] and return a [PwBox].
abstract class PwBox {
  /// PwBox API.
  PwBox(this.size);

  /// size API.
  final PwSize size;

  /// Distance from the top of this box to the alphabetic baseline, if any.
  double? get baseline => null;

  /// paint API.
  void paint(Context context, PwOffset offset);

  /// Record heading destinations once page placement is known.
  void noteDestination(Context context, PwOffset offset) {}
}

/// Empty box.
class EmptyBox extends PwBox {
  /// EmptyBox API.
  EmptyBox([super.size = PwSize.zero]);

  @override
  void paint(Context context, PwOffset offset) {}
}

/// Parent that paints a decoration then a child.
class ProxyBox extends PwBox {
  /// ProxyBox API.
  ProxyBox(
    super.size, {
    this.child,
    this.childOffset = PwOffset.zero,
    this.decoration,
    this.onPaint,
    this.onNote,
    this.baselineOverride,
  });

  /// child API.
  final PwBox? child;

  /// childOffset API.
  final PwOffset childOffset;

  /// decoration API.
  final BoxDecoration? decoration;

  /// Extra paint after the child (links, overlays).
  final void Function(Context context, PwOffset offset)? onPaint;

  /// Called when the page position of this box is known.
  final void Function(Context context, PwOffset offset)? onNote;

  /// Alphabetic baseline of this box, if known.
  final double? baselineOverride;

  @override
  double? get baseline =>
      baselineOverride ??
      (child?.baseline == null ? null : child!.baseline! + childOffset.dy);

  @override
  void noteDestination(Context context, PwOffset offset) {
    onNote?.call(context, offset);
    child?.noteDestination(
      context,
      offset.translate(childOffset.dx, childOffset.dy),
    );
  }

  @override
  void paint(Context context, PwOffset offset) {
    final BoxDecoration? deco = decoration;
    if (deco != null) {
      // Imported via pw_box callers; decoration paint is in pw_paint.
      _paintDeco(context, offset, size, deco);
    }
    child?.paint(
      context,
      offset.translate(childOffset.dx, childOffset.dy),
    );
    onPaint?.call(context, offset);
  }
}

void _paintDeco(
  Context context,
  PwOffset offset,
  PwSize size,
  BoxDecoration decoration,
) {
  // Local fill/stroke so pw_core does not import pw_paint (cycle).
  final PdfCanvas? canvas = context.canvas;
  if (canvas == null) {
    return;
  }
  canvas.endText();
  final LinearGradient? gradient = decoration.gradient;
  if (gradient != null && gradient.colors.length >= 2) {
    _paintGradient(canvas, offset, size, gradient);
  } else if (decoration.color != null) {
    if (decoration.shape == BoxShape.circle) {
      canvas.setFillColor(decoration.color!);
      canvas.ellipse(offset.dx, offset.dy, size.width, size.height);
      canvas.fill();
    } else if (decoration.borderRadius > 0.2) {
      canvas.setFillColor(decoration.color!);
      canvas.roundedRect(
        offset.dx,
        offset.dy,
        size.width,
        size.height,
        decoration.borderRadius,
      );
      canvas.fill();
    } else {
      canvas.fillRect(
        offset.dx,
        offset.dy,
        size.width,
        size.height,
        decoration.color!,
      );
    }
  }
  final Border? border = decoration.border;
  if (border == null) {
    return;
  }
  void side(BorderSide s, double x1, double y1, double x2, double y2) {
    if (s.width <= 0) {
      return;
    }
    canvas.setStrokeColor(s.color);
    canvas.setLineWidth(s.width);
    canvas.moveTo(x1, y1);
    canvas.lineTo(x2, y2);
    canvas.stroke();
  }

  if (decoration.shape == BoxShape.circle && border.top.width > 0) {
    canvas.setStrokeColor(border.top.color);
    canvas.setLineWidth(border.top.width);
    canvas.ellipse(offset.dx, offset.dy, size.width, size.height);
    canvas.stroke();
    return;
  }
  final double r = offset.dx + size.width;
  final double b = offset.dy + size.height;
  side(border.top, offset.dx, offset.dy, r, offset.dy);
  side(border.right, r, offset.dy, r, b);
  side(border.bottom, offset.dx, b, r, b);
  side(border.left, offset.dx, offset.dy, offset.dx, b);
}

void _paintGradient(
  PdfCanvas canvas,
  PwOffset offset,
  PwSize size,
  LinearGradient gradient,
) {
  const int strips = 24;
  final List<String> colors = gradient.colors;
  for (int i = 0; i < strips; i++) {
    final double t0 = i / strips;
    final double t1 = (i + 1) / strips;
    final String hex = _sampleGradient(colors, (t0 + t1) / 2);
    if (gradient.vertical) {
      final double y = offset.dy + size.height * t0;
      final double h = size.height * (t1 - t0) + 0.15;
      canvas.fillRect(offset.dx, y, size.width, h, hex);
    } else {
      final double x = offset.dx + size.width * t0;
      final double w = size.width * (t1 - t0) + 0.15;
      canvas.fillRect(x, offset.dy, w, size.height, hex);
    }
  }
}

String _sampleGradient(List<String> colors, double t) {
  final double clamped = t.clamp(0.0, 1.0);
  final double scaled = clamped * (colors.length - 1);
  final int i = scaled.floor().clamp(0, colors.length - 2);
  final double local = scaled - i;
  return _lerpHex(colors[i], colors[i + 1], local);
}

String _lerpHex(String a, String b, double t) {
  int ch(String hex, int shift) {
    final String clean = hex.replaceAll('#', '');
    final int n = int.tryParse(
          clean.length >= 6 ? clean.substring(clean.length - 6) : clean,
          radix: 16,
        ) ??
        0;
    return (n >> shift) & 0xFF;
  }

  int mix(int shift) =>
      (ch(a, shift) + (ch(b, shift) - ch(a, shift)) * t).round().clamp(0, 255);
  final int rgb = (mix(16) << 16) | (mix(8) << 8) | mix(0);
  return rgb.toRadixString(16).padLeft(6, '0');
}

/// Multi-child box with absolute child origins (relative to this box).
class GroupBox extends PwBox {
  /// GroupBox API.
  GroupBox(super.size, this.children, {this.background});

  /// children API.
  final List<(PwBox box, PwOffset offset)> children;

  /// background API.
  final BoxDecoration? background;

  @override
  void paint(Context context, PwOffset offset) {
    if (background != null) {
      _paintDeco(context, offset, size, background!);
    }
    for (final (PwBox box, PwOffset childOffset) in children) {
      box.paint(context, offset.translate(childOffset.dx, childOffset.dy));
    }
  }

  @override
  void noteDestination(Context context, PwOffset offset) {
    for (final (PwBox box, PwOffset childOffset) in children) {
      box.noteDestination(
        context,
        offset.translate(childOffset.dx, childOffset.dy),
      );
    }
  }
}

/// One page-slice of a widget that can flow across [MultiPage].
class SpanSlice {
  /// SpanSlice API.
  const SpanSlice(this.box, this.rest);

  /// Content that fits the given height.
  final PwBox box;

  /// Remainder for the next page, or null when finished.
  final Widget? rest;
}

/// Constraint-layout widget. Subclass and implement [layout] (like RenderBox).
abstract class Widget {
  /// Widget API.
  const Widget();

  /// layout API.
  PwBox layout(Context context, BoxConstraints constraints);

  /// Split across pages when [constraints] has a bounded height.
  ///
  /// Return null to stay atomic (the default). [Table] overrides this so a
  /// long table continues on the next [MultiPage] sheet, repeating header rows.
  SpanSlice? layoutSpan(Context context, BoxConstraints constraints) => null;

  /// Stamp paint. The default lays out and paints glyph by glyph.
  void paintStamp(Context context, double pageW, double pageH) {
    final PdfCanvas? canvas = context.canvas;
    if (canvas == null) {
      return;
    }
    final PwBox mark = layout(
      context,
      BoxConstraints(maxWidth: pageW * 0.8, maxHeight: 80),
    );
    mark.paint(
      context,
      PwOffset((pageW - mark.size.width) / 2, (pageH - mark.size.height) / 2),
    );
  }

  /// Children [MultiPage] should flow individually (vertical columns).
  List<Widget>? get flowChildren => null;
}

/// Overlay drawn on every [MultiPage] sheet (watermark).
mixin PwPageOverlay on Widget {
  /// overlayChild API.
  Widget get overlayChild;

  /// isWatermark API.
  bool get isWatermark => true;
}

/// Forced page break inside [MultiPage].
class NewPage extends Widget {
  /// NewPage API.
  const NewPage();

  @override
  PwBox layout(Context context, BoxConstraints constraints) => EmptyBox();
}

/// Page chrome: format, margin, direction, theme.
class PageTheme {
  /// PageTheme API.
  const PageTheme({
    PdfPageFormat? pageFormat,
    this.theme,
    this.orientation = PageOrientation.natural,
    this.margin,
    this.textDirection,
    this.buildBackground,
    this.buildForeground,
  }) : pageFormat = pageFormat ?? PdfPageFormat.standard;

  /// pageFormat API.
  final PdfPageFormat pageFormat;

  /// theme API.
  final ThemeData? theme;

  /// orientation API.
  final PageOrientation orientation;

  /// margin API.
  final EdgeInsetsGeometry? margin;

  /// textDirection API.
  final TextDirection? textDirection;

  /// Optional full-page background (letterhead, colored band).
  final BuildCallback? buildBackground;

  /// Optional full-page overlay.
  final BuildCallback? buildForeground;

  /// resolvedFormat API.
  PdfPageFormat get resolvedFormat => pageFormat.apply(orientation);

  /// resolvedMargin API.
  EdgeInsets resolvedMargin() {
    final EdgeInsetsGeometry? inset = margin;
    if (inset != null) {
      return inset.resolve(textDirection ?? TextDirection.ltr);
    }
    final PdfPageFormat format = resolvedFormat;
    return EdgeInsets.fromLTRB(
      format.marginLeft,
      format.marginTop,
      format.marginRight,
      format.marginBottom,
    );
  }
}

/// One laid-out PDF page (widget API — not [PdfPage]).
class Page {
  /// Page API.
  Page({
    PageTheme? pageTheme,
    PdfPageFormat? pageFormat,
    required BuildCallback this._build,
    ThemeData? theme,
    PageOrientation? orientation,
    EdgeInsetsGeometry? margin,
    TextDirection? textDirection,
    this.header,
    this.footer,
  }) : pageTheme =
           pageTheme ??
           PageTheme(
             pageFormat: pageFormat,
             theme: theme,
             orientation: orientation ?? PageOrientation.natural,
             margin: margin,
             textDirection: textDirection,
           ),
       _buildList = null;

  Page._multi({
    required this.pageTheme,
    required BuildListCallback build,
    this.header,
    this.footer,
  }) : _build = null,
       _buildList = build;

  /// pageTheme API.
  final PageTheme pageTheme;

  /// header API.
  final BuildCallback? header;

  /// footer API.
  final BuildCallback? footer;

  final BuildCallback? _build;
  final BuildListCallback? _buildList;

  void _compose(Context seed, _PageSink sink) {
    if (_buildList != null) {
      _composeFlow(seed, sink, _buildList);
      return;
    }
    _composeSingle(seed, sink, _build!);
  }

  void _composeSingle(Context seed, _PageSink sink, BuildCallback build) {
    final PdfPageFormat format = pageTheme.resolvedFormat;
    final EdgeInsets inset = pageTheme.resolvedMargin();
    final Context ctx = seed.copyWith(
      theme: pageTheme.theme ?? seed.theme,
      textDirection: pageTheme.textDirection ?? seed.textDirection,
      pageFormat: format,
    );
    ctx.pageNumber = sink.nextPageNumber;
    final double contentW = (format.width - inset.left - inset.right).clamp(
      1,
      format.width,
    );
    final double contentH = (format.height - inset.top - inset.bottom).clamp(
      1,
      format.height,
    );
    PwBox? headerBox;
    PwBox? footerBox;
    var headerH = 0.0;
    var footerH = 0.0;
    final BuildCallback? headerBuild = header;
    if (headerBuild != null) {
      headerBox = headerBuild(ctx).layout(
        ctx,
        BoxConstraints(maxWidth: contentW, maxHeight: contentH * 0.25),
      );
      headerH = headerBox.size.height;
    }
    final BuildCallback? footerBuild = footer;
    if (footerBuild != null) {
      footerBox = footerBuild(ctx).layout(
        ctx,
        BoxConstraints(maxWidth: contentW, maxHeight: contentH * 0.2),
      );
      footerH = footerBox.size.height;
    }
    final double bodyH = (contentH - headerH - footerH).clamp(1, contentH);
    final int headingAt = ctx.headings.length;
    final PwBox body = build(ctx).layout(
      ctx,
      BoxConstraints(
        minWidth: contentW,
        maxWidth: contentW,
        maxHeight: bodyH,
      ),
    );
    ctx.restampHeadings(
      from: headingAt,
      pageNumber: ctx.pageNumber,
      destY: inset.top + headerH,
    );
    sink.emit(
      ctx: ctx,
      format: format,
      inset: inset,
      header: headerBox,
      footer: footerBox,
      headerH: headerH,
      footerH: footerH,
      body: <(PwBox, PwOffset)>[(body, PwOffset.zero)],
      background: pageTheme.buildBackground,
      foreground: pageTheme.buildForeground,
    );
  }

  void _composeFlow(Context seed, _PageSink sink, BuildListCallback build) {
    final PdfPageFormat format = pageTheme.resolvedFormat;
    final EdgeInsets inset = pageTheme.resolvedMargin();
    final Context ctx = seed.copyWith(
      theme: pageTheme.theme ?? seed.theme,
      textDirection: pageTheme.textDirection ?? seed.textDirection,
      pageFormat: format,
    );
    final List<Widget> raw = build(ctx);
    Widget? watermark;
    final List<Widget> children = <Widget>[];
    for (final Widget child in raw) {
      if (child is PwPageOverlay && child.isWatermark) {
        watermark = child.overlayChild;
        continue;
      }
      children.add(child);
    }
    final double contentW = (format.width - inset.left - inset.right).clamp(
      1,
      format.width,
    );
    final double contentH = (format.height - inset.top - inset.bottom).clamp(
      1,
      format.height,
    );

    List<(PwBox, PwOffset)> current = <(PwBox, PwOffset)>[];
    var used = 0.0;

    PwBox? layoutChrome(BuildCallback? cb, double maxH) {
      if (cb == null) {
        return null;
      }
      ctx.pageNumber = sink.nextPageNumber;
      return cb(ctx).layout(
        ctx,
        BoxConstraints(maxWidth: contentW, maxHeight: maxH),
      );
    }

    void flush() {
      if (current.isEmpty && sink.hasOpenPage) {
        return;
      }
      ctx.pageNumber = sink.nextPageNumber;
      final PwBox? headerBox = layoutChrome(header, contentH * 0.25);
      final PwBox? footerBox = layoutChrome(footer, contentH * 0.2);
      sink.emit(
        ctx: ctx,
        format: format,
        inset: inset,
        header: headerBox,
        footer: footerBox,
        headerH: headerBox?.size.height ?? 0,
        footerH: footerBox?.size.height ?? 0,
        body: current,
        watermark: watermark,
        background: pageTheme.buildBackground,
        foreground: pageTheme.buildForeground,
      );
      current = <(PwBox, PwOffset)>[];
      used = 0;
    }

    PwBox? headerProbe = layoutChrome(header, contentH * 0.25);
    PwBox? footerProbe = layoutChrome(footer, contentH * 0.2);
    double bodyH() =>
        (contentH -
                (headerProbe?.size.height ?? 0) -
                (footerProbe?.size.height ?? 0))
            .clamp(1, contentH);

    void place(PwBox box, int headingAt) {
      ctx.restampHeadings(
        from: headingAt,
        pageNumber: ctx.pageNumber,
        destY: inset.top + (headerProbe?.size.height ?? 0) + used,
      );
      final double x = ctx.textDirection == TextDirection.rtl
          ? (contentW - box.size.width).clamp(0.0, contentW)
          : 0.0;
      current.add((box, PwOffset(x, used)));
      used += box.size.height;
    }

    void placeFlow(Widget child) {
      final List<Widget>? flow = child.flowChildren;
      if (flow != null) {
        for (final Widget kid in flow) {
          placeFlow(kid);
        }
        return;
      }
      Widget? pending = child;
      var guard = 0;
      while (pending != null) {
        if (guard++ > 400) {
          break;
        }
        if (pending is NewPage) {
          if (current.isNotEmpty) {
            flush();
            headerProbe = layoutChrome(header, contentH * 0.25);
            footerProbe = layoutChrome(footer, contentH * 0.2);
          }
          pending = null;
          continue;
        }
        final double limit = bodyH();
        final double remaining = (limit - used).clamp(0.0, limit);
        ctx.pageNumber = sink.nextPageNumber;
        final int headingAt = ctx.headings.length;
        final SpanSlice? span = pending.layoutSpan(
          ctx,
          BoxConstraints(
            minWidth: contentW,
            maxWidth: contentW,
            maxHeight: remaining < 8 ? limit : remaining,
          ),
        );
        if (span != null) {
          final bool tooTallForSlot =
              used > 0.5 && span.box.size.height > remaining + 0.5;
          if (tooTallForSlot && current.isNotEmpty) {
            flush();
            headerProbe = layoutChrome(header, contentH * 0.25);
            footerProbe = layoutChrome(footer, contentH * 0.2);
            ctx.pageNumber = sink.nextPageNumber;
            continue;
          }
          place(span.box, headingAt);
          pending = span.rest;
          continue;
        }
        // Atomic child. package:pdf MultiPage uses width-only constraints so
        // Align/Center shrink-wrap instead of expanding to leftover height.
        final PwBox box = pending.layout(
          ctx,
          BoxConstraints(minWidth: contentW, maxWidth: contentW),
        );
        if (used + box.size.height > limit + 0.5 && current.isNotEmpty) {
          flush();
          headerProbe = layoutChrome(header, contentH * 0.25);
          footerProbe = layoutChrome(footer, contentH * 0.2);
          ctx.pageNumber = sink.nextPageNumber;
        }
        place(box, headingAt);
        pending = null;
      }
    }

    for (final Widget child in children) {
      if (child is NewPage) {
        if (current.isNotEmpty) {
          flush();
          headerProbe = layoutChrome(header, contentH * 0.25);
          footerProbe = layoutChrome(footer, contentH * 0.2);
        }
        continue;
      }
      placeFlow(child);
    }
    if (current.isNotEmpty || !sink.hasEmitted) {
      flush();
    }
  }
}

/// Flowing multi-page section.
class MultiPage extends Page {
  /// MultiPage API.
  MultiPage({
    PageTheme? pageTheme,
    PdfPageFormat? pageFormat,
    required super.build,
    ThemeData? theme,
    PageOrientation? orientation,
    EdgeInsetsGeometry? margin,
    TextDirection? textDirection,
    super.header,
    super.footer,
    BuildCallback? background,
    BuildCallback? foreground,
  }) : super._multi(
         pageTheme:
             pageTheme ??
             PageTheme(
               pageFormat: pageFormat,
               theme: theme,
               orientation: orientation ?? PageOrientation.natural,
               margin: margin,
               textDirection: textDirection,
               buildBackground: background,
               buildForeground: foreground,
             ),
       );
}

/// Widget-tree PDF writer. Emits a native [PdfDocument] — does not rename it.
class Document {
  /// Document API.
  Document({
    this.title = 'Quds Office',
    this.author = '',
    this.theme,
    this.font,
    this.fontBold,
    this.pageMode,
  });

  /// title API.
  final String title;

  /// author API.
  final String author;

  /// theme API.
  final ThemeData? theme;

  /// Embedded glyf face. When null, Latin text uses Helvetica (`/F2`).
  final SfntFont? font;

  /// Bold face (package:pdf `ThemeData.base` + bold). When set, [FontWeight.bold]
  /// uses this Type0 font (`/F3`) instead of fake double-stroke.
  final SfntFont? fontBold;

  /// Unused catalog hint kept for `package:pdf` compatibility.
  final String? pageMode;

  final List<Page> _pages = <Page>[];

  /// addPage API.
  void addPage(Page page) => _pages.add(page);

  /// Composes the tree and writes a PDF 1.7 file (synchronous).
  Uint8List save() {
    final ThemeData theme = this.theme ?? const ThemeData();
    final Context seed = Context(
      document: this,
      pageFormat: PdfPageFormat.a4,
      theme: theme,
      textDirection: TextDirection.ltr,
    );
    // Pass 1: collect text + headings (TOC still empty).
    seed.pagesCount = _measure(seed);
    _freezeHeadings(seed);
    if (font != null && seed.usedCodePoints.isNotEmpty) {
      seed.subset = FontSubsetter(font!).subset(seed.usedCodePoints);
    }
    if (fontBold != null && seed.usedCodePoints.isNotEmpty) {
      seed.boldSubset = FontSubsetter(fontBold!).subset(seed.usedCodePoints);
    }
    // Pass 2: TOC has entries; recount pages and restamp heading numbers.
    seed.pagesCount = _measure(seed);
    _freezeHeadings(seed);
    seed.pagesCount = _measure(seed);
    // Second pass placed headings with the TOC present. Keep those positions.
    _freezeHeadings(seed);
    final _PageSink paint = _PageSink(paint: true);
    seed.pageNumber = 1;
    seed.headings.clear();
    seed.anchors.clear();
    for (final Page page in _pages) {
      page._compose(seed, paint);
    }
    final PdfDocument pdf = PdfDocument(title: title, author: author);
    for (final PdfPage built in paint.pages) {
      pdf.addPage(built);
    }
    for (final PwHeading heading in seed.headings) {
      if (heading.level <= 2 && pdf.pages.isNotEmpty) {
        pdf.addOutline(
          PdfOutlineItem(
            title: heading.title,
            pageIndex: (heading.pageNumber - 1).clamp(0, pdf.pages.length - 1),
            destY: heading.destY,
          ),
        );
      }
    }
    final List<PdfEmbeddedFace> faces = <PdfEmbeddedFace>[
      if (seed.subset != null && font != null)
        PdfEmbeddedFace(
          subset: seed.subset!,
          source: font!,
          resourceName: 'F1',
        ),
      if (seed.boldSubset != null && fontBold != null)
        PdfEmbeddedFace(
          subset: seed.boldSubset!,
          source: fontBold!,
          resourceName: 'F3',
        ),
    ];
    return faces.isEmpty
        ? pdf.save(subset: seed.subset, font: font)
        : pdf.save(faces: faces);
  }

  int _measure(Context seed) {
    final _PageSink sink = _PageSink(paint: false);
    seed.pageNumber = 1;
    seed.headings.clear();
    seed.anchors.clear();
    for (final Page page in _pages) {
      page._compose(seed, sink);
    }
    return sink.pageCount;
  }

  static void _freezeHeadings(Context seed) {
    seed.frozenHeadings
      ..clear()
      ..addAll(seed.headings);
  }
}

class _PageSink {
  _PageSink({required this.paint});

  final bool paint;
  final List<PdfPage> pages = <PdfPage>[];
  var hasEmitted = false;

  int get pageCount => pages.length;

  int get nextPageNumber => pages.length + 1;

  bool get hasOpenPage => pages.isNotEmpty;

  void emit({
    required Context ctx,
    required PdfPageFormat format,
    required EdgeInsets inset,
    required PwBox? header,
    required PwBox? footer,
    required double headerH,
    required double footerH,
    required List<(PwBox, PwOffset)> body,
    Widget? watermark,
    BuildCallback? background,
    BuildCallback? foreground,
  }) {
    hasEmitted = true;
    ctx.pageNumber = pages.length + 1;
    final double bodyTop = inset.top + headerH;
    header?.noteDestination(ctx, PwOffset(inset.left, inset.top));
    for (final (PwBox box, PwOffset offset) in body) {
      box.noteDestination(
        ctx,
        PwOffset(inset.left + offset.dx, bodyTop + offset.dy),
      );
    }
    if (!paint) {
      pages.add(
        PdfPage(
          width: format.width,
          height: format.height,
          content: Uint8List(0),
        ),
      );
      return;
    }
    ctx.images.clear();
    ctx.links.clear();
    final PdfCanvas canvas = PdfCanvas(format.width, format.height);
    ctx.canvas = canvas;
    final PwBox? bg = background?.call(ctx).layout(
      ctx,
      BoxConstraints.tight(PwSize(format.width, format.height)),
    );
    bg?.paint(ctx, PwOffset.zero);
    if (watermark != null) {
      canvas.save();
      canvas.rotateAround(format.width / 2, format.height / 2, -32);
      watermark.paintStamp(ctx, format.width, format.height);
      canvas.restore();
    }
    header?.paint(ctx, PwOffset(inset.left, inset.top));
    canvas.save();
    canvas.clipRect(
      inset.left,
      bodyTop,
      format.width - inset.left - inset.right,
      format.height - bodyTop - inset.bottom - footerH,
    );
    for (final (PwBox box, PwOffset offset) in body) {
      box.paint(ctx, PwOffset(inset.left + offset.dx, bodyTop + offset.dy));
    }
    canvas.restore();
    footer?.paint(
      ctx,
      PwOffset(inset.left, format.height - inset.bottom - footerH),
    );
    final PwBox? fg = foreground?.call(ctx).layout(
      ctx,
      BoxConstraints.tight(PwSize(format.width, format.height)),
    );
    fg?.paint(ctx, PwOffset.zero);
    canvas.endText();
    pages.add(
      PdfPage(
        width: format.width,
        height: format.height,
        content: canvas.toStream(),
        images: List<PdfEmbeddedImage>.from(ctx.images),
        links: List<PdfLinkAnnot>.from(ctx.links),
        acroFields: <PdfAcroField>[
          for (final PdfAcroField field in ctx.acroFields)
            if (field.pageIndex == pages.length) field,
        ],
      ),
    );
    ctx.canvas = null;
  }
}
