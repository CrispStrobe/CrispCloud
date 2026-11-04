import 'dart:typed_data';

import '../model/pdf_annot.dart';
import '../model/pdf_page_info.dart';

/// Device-independent page paint ops (ISO 32000 content stream result).
class PdfDisplayList {
  /// PdfDisplayList API.
  PdfDisplayList({
    required this.page,
    List<PdfPaintOp>? ops,
    List<PdfTextRun>? runs,
    List<PdfHotspot>? hotspots,
  }) : ops = ops ?? <PdfPaintOp>[],
       runs = runs ?? <PdfTextRun>[],
       hotspots = hotspots ?? <PdfHotspot>[];

  /// page API.
  final PdfPageInfo page;

  /// ops API.
  final List<PdfPaintOp> ops;

  /// Extractable / selectable text in visual order.
  final List<PdfTextRun> runs;

  /// hotspots API.
  final List<PdfHotspot> hotspots;

  /// plainText API.
  String get plainText {
    final StringBuffer buf = StringBuffer();
    for (final PdfTextRun run in runs) {
      if (buf.isNotEmpty && run.breakBefore) {
        buf.write('\n');
      }
      buf.write(run.text);
    }
    return buf.toString();
  }
}

/// One paint command.
sealed class PdfPaintOp {
  /// PdfPaintOp API.
  const PdfPaintOp();
}

/// ExtGState `/BM` subset (ISO 32000-1 §8.4.5).
enum PdfBlendMode {
  /// `/Normal`.
  normal,

  /// `/Multiply`.
  multiply,

  /// `/Screen`.
  screen,
}

/// Class PdfFillPath.
final class PdfFillPath extends PdfPaintOp {
  /// PdfFillPath API.
  const PdfFillPath({
    required this.points,
    required this.color,
    this.evenOdd = false,
    this.blend = PdfBlendMode.normal,
  });

  /// Flattened path: move/line/cubic encoded as [PdfPathVerb] stream.
  final List<PdfPathVerb> points;

  /// ARGB.
  final int color;

  /// evenOdd API.
  final bool evenOdd;

  /// blend API.
  final PdfBlendMode blend;
}

/// Class PdfStrokePath.
final class PdfStrokePath extends PdfPaintOp {
  /// PdfStrokePath API.
  PdfStrokePath({
    required this.points,
    required this.color,
    this.width = 1,
    this.cap = 0,
    this.join = 0,
    this.miter = 10,
    List<double>? dash,
    this.dashPhase = 0,
    this.blend = PdfBlendMode.normal,
  }) : dash = dash ?? const <double>[];

  /// points API.
  final List<PdfPathVerb> points;

  /// color API.
  final int color;

  /// width API.
  final double width;

  /// PDF `J`: 0 butt, 1 round, 2 square.
  final int cap;

  /// PDF `j`: 0 miter, 1 round, 2 bevel.
  final int join;

  /// PDF `M` miter limit.
  final double miter;

  /// PDF `d` dash array (user space, already scaled with [width]).
  final List<double> dash;

  /// PDF `d` phase.
  final double dashPhase;

  /// blend API.
  final PdfBlendMode blend;
}

/// Class PdfDrawImage.
final class PdfDrawImage extends PdfPaintOp {
  /// PdfDrawImage API.
  const PdfDrawImage({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.bytes,
    this.jpeg = false,
    this.placeholder = false,
    this.pixelWidth = 0,
    this.pixelHeight = 0,
    this.hasAlpha = false,
    this.blend = PdfBlendMode.normal,
    this.softMaskJpeg,
  });

  /// x API.
  final double x;

  /// y API.
  final double y;

  /// width API.
  final double width;

  /// height API.
  final double height;

  /// bytes API.
  final Uint8List bytes;

  /// jpeg API.
  final bool jpeg;

  /// Undecoded filter (JPX, arithmetic JBIG2, or another typed-unsupported codec).
  final bool placeholder;

  /// Source pixel width from the XObject (`/Width`).
  final int pixelWidth;

  /// Source pixel height from the XObject (`/Height`).
  final int pixelHeight;

  /// [bytes] are RGBA8888 (SMask / ImageMask). Otherwise RGB888 or JPEG/PNG.
  final bool hasAlpha;

  /// Raw `/SMask` DCT stream when [jpeg] is true (composed by the host raster).
  final Uint8List? softMaskJpeg;

  /// blend API.
  final PdfBlendMode blend;
}

/// Class PdfDrawText.
final class PdfDrawText extends PdfPaintOp {
  /// PdfDrawText API.
  const PdfDrawText({
    required this.x,
    required this.y,
    required this.size,
    required this.color,
    required this.text,
    this.italic = false,
    this.bold = false,
    this.fontFamily = 'Helvetica',
    this.fontBytes,
    this.angle = 0,
  });

  /// x API.
  final double x;

  /// y API.
  final double y;

  /// size API.
  final double size;

  /// color API.
  final int color;

  /// text API.
  final String text;

  /// italic API.
  final bool italic;

  /// bold API.
  final bool bold;

  /// PDF BaseFont, mapped to a host face when [fontBytes] is absent.
  final String fontFamily;

  /// Embedded `/FontFile2` bytes when the file carries a glyf face.
  final Uint8List? fontBytes;

  /// Baseline rotation in screen space (y down). Zero is horizontal.
  ///
  /// Non-zero means [text] is one logical string, not a letter picked out of
  /// a run. The painter rotates that string as a unit so Arabic stays joined.
  final double angle;
}

/// `q` — push graphics state (clip + transform) for the painter.
final class PdfSaveGState extends PdfPaintOp {
  /// PdfSaveGState API.
  const PdfSaveGState();
}

/// `Q` — pop graphics state.
final class PdfRestoreGState extends PdfPaintOp {
  /// PdfRestoreGState API.
  const PdfRestoreGState();
}

/// `W` / `W*` clip (already mapped to page space).
final class PdfClipPath extends PdfPaintOp {
  /// PdfClipPath API.
  const PdfClipPath({required this.points, this.evenOdd = false});

  /// points API.
  final List<PdfPathVerb> points;

  /// evenOdd API.
  final bool evenOdd;
}

/// Class PdfPathVerb.
class PdfPathVerb {
  /// PdfPathVerb API.
  const PdfPathVerb(this.kind, this.x, this.y, [this.x2 = 0, this.y2 = 0, this.x3 = 0, this.y3 = 0]);

  /// kind API.
  final PdfPathKind kind;

  /// x API.
  final double x;

  /// y API.
  final double y;

  /// x2 API.
  final double x2;

  /// y2 API.
  final double y2;

  /// x3 API.
  final double x3;

  /// y3 API.
  final double y3;
}

/// Class PdfPathKind.
enum PdfPathKind { move, line, cubic, close, rect }

/// Selectable text run with a box in top-left page space.
class PdfTextRun {
  /// PdfTextRun API.
  const PdfTextRun({
    required this.text,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.breakBefore = false,
  });

  /// text API.
  final String text;

  /// x API.
  final double x;

  /// y API.
  final double y;

  /// width API.
  final double width;

  /// height API.
  final double height;

  /// breakBefore API.
  final bool breakBefore;

  /// contains API.
  bool contains(double px, double py) =>
      px >= x && py >= y && px <= x + width && py <= y + height;
}

/// Clickable annotation hotspot in top-left page space.
class PdfHotspot {
  /// PdfHotspot API.
  const PdfHotspot({required this.rect, required this.action, this.annotId});

  /// rect API.
  final PdfRect rect;

  /// action API.
  final PdfLinkAction action;

  /// annotId API.
  final int? annotId;
}
