import 'dart:typed_data';

import '../io/byte_source.dart';
import 'sfnt_parser.dart';

/// A quadratic Bézier path command in font units.
enum GlyphPathOp { move, line, quad, close }

/// Class GlyphPathCommand.
class GlyphPathCommand {
  /// GlyphPathCommand API.
  const GlyphPathCommand(
    this.op, [
    this.x = 0,
    this.y = 0,
    this.cx = 0,
    this.cy = 0,
  ]);

  /// op API.
  final GlyphPathOp op;

  /// x API.
  final double x;

  /// y API.
  final double y;

  /// cx API.
  final double cx;

  /// cy API.
  final double cy;
}

/// Decoded TrueType `glyf` outline.
class GlyphOutline {
  /// GlyphOutline API.
  GlyphOutline({
    required this.glyphId,
    required this.xMin,
    required this.yMin,
    required this.xMax,
    required this.yMax,
    required this.commands,
    required this.componentGlyphIds,
  });

  /// glyphId API.
  final int glyphId;

  /// xMin API.
  final int xMin;

  /// yMin API.
  final int yMin;

  /// xMax API.
  final int xMax;

  /// yMax API.
  final int yMax;

  /// commands API.
  final List<GlyphPathCommand> commands;

  /// componentGlyphIds API.
  final List<int> componentGlyphIds;

  /// isEmpty API.
  bool get isEmpty => commands.isEmpty;
}

/// Converts TrueType quadratic contours (and composites) to path commands.
class GlyphOutlineDecoder {
  /// GlyphOutlineDecoder API.
  GlyphOutlineDecoder(this.font);

  /// font API.
  final SfntFont font;

  /// decode API.
  GlyphOutline decode(int glyphId) {
    if (!font.hasTable('glyf') || glyphId < 0 || glyphId >= font.numGlyphs) {
      return GlyphOutline(
        glyphId: glyphId,
        xMin: 0,
        yMin: 0,
        xMax: 0,
        yMax: 0,
        commands: const <GlyphPathCommand>[],
        componentGlyphIds: const <int>[],
      );
    }
    final int start = font.glyphOffsets[glyphId];
    final int end = font.glyphOffsets[glyphId + 1];
    if (end <= start) {
      return GlyphOutline(
        glyphId: glyphId,
        xMin: 0,
        yMin: 0,
        xMax: 0,
        yMax: 0,
        commands: const <GlyphPathCommand>[],
        componentGlyphIds: const <int>[],
      );
    }
    final Uint8List glyf = font.tableBytes('glyf');
    final ByteCursor cursor = ByteCursor(
      Uint8List.sublistView(glyf, start, end),
    );
    final int numberOfContours = cursor.i16be();
    final int xMin = cursor.i16be();
    final int yMin = cursor.i16be();
    final int xMax = cursor.i16be();
    final int yMax = cursor.i16be();
    if (numberOfContours >= 0) {
      return GlyphOutline(
        glyphId: glyphId,
        xMin: xMin,
        yMin: yMin,
        xMax: xMax,
        yMax: yMax,
        commands: _simple(cursor, numberOfContours),
        componentGlyphIds: const <int>[],
      );
    }
    final List<int> components = <int>[];
    final List<GlyphPathCommand> commands = <GlyphPathCommand>[];
    _composite(cursor, commands, components, 1, 0, 0, 1, 0, 0);
    return GlyphOutline(
      glyphId: glyphId,
      xMin: xMin,
      yMin: yMin,
      xMax: xMax,
      yMax: yMax,
      commands: commands,
      componentGlyphIds: components,
    );
  }

  List<GlyphPathCommand> _simple(ByteCursor cursor, int contourCount) {
    final List<int> endPts = <int>[
      for (int i = 0; i < contourCount; i++) cursor.u16be(),
    ];
    final int instructionLen = cursor.u16be();
    cursor.skip(instructionLen);
    if (endPts.isEmpty) {
      return const <GlyphPathCommand>[];
    }
    final int pointCount = endPts.last + 1;
    final List<int> flags = <int>[];
    while (flags.length < pointCount) {
      final int flag = cursor.u8();
      flags.add(flag);
      if ((flag & 0x08) != 0) {
        final int repeat = cursor.u8();
        for (int i = 0; i < repeat; i++) {
          flags.add(flag);
        }
      }
    }
    final List<int> xs = _coords(cursor, flags, 0x02, 0x10);
    final List<int> ys = _coords(cursor, flags, 0x04, 0x20);
    final List<GlyphPathCommand> commands = <GlyphPathCommand>[];
    int start = 0;
    for (final int end in endPts) {
      _emitContour(
        commands,
        xs.sublist(start, end + 1),
        ys.sublist(start, end + 1),
        flags.sublist(start, end + 1),
      );
      start = end + 1;
    }
    return commands;
  }

  void _emitContour(
    List<GlyphPathCommand> out,
    List<int> xs,
    List<int> ys,
    List<int> flags,
  ) {
    if (xs.isEmpty) {
      return;
    }
    final List<_Pt> pts = <_Pt>[
      for (int i = 0; i < xs.length; i++)
        _Pt(xs[i].toDouble(), ys[i].toDouble(), (flags[i] & 0x01) != 0),
    ];
    // Insert implied on-curve midpoints between consecutive off-curve points.
    final List<_Pt> expanded = <_Pt>[];
    for (int i = 0; i < pts.length; i++) {
      final _Pt cur = pts[i];
      final _Pt next = pts[(i + 1) % pts.length];
      expanded.add(cur);
      if (!cur.on && !next.on) {
        expanded.add(_Pt((cur.x + next.x) / 2, (cur.y + next.y) / 2, true));
      }
    }
    int i = 0;
    if (!expanded[0].on) {
      expanded.insert(
        0,
        _Pt(
          (expanded[0].x + expanded.last.x) / 2,
          (expanded[0].y + expanded.last.y) / 2,
          true,
        ),
      );
    }
    out.add(GlyphPathCommand(GlyphPathOp.move, expanded[0].x, expanded[0].y));
    i = 1;
    while (i < expanded.length) {
      final _Pt p = expanded[i];
      if (p.on) {
        out.add(GlyphPathCommand(GlyphPathOp.line, p.x, p.y));
        i++;
      } else {
        final _Pt next = expanded[(i + 1) % expanded.length];
        out.add(GlyphPathCommand(GlyphPathOp.quad, next.x, next.y, p.x, p.y));
        i += next.on ? 2 : 1;
      }
    }
    out.add(const GlyphPathCommand(GlyphPathOp.close));
  }

  void _composite(
    ByteCursor cursor,
    List<GlyphPathCommand> commands,
    List<int> components,
    double xx,
    double xy,
    double yx,
    double yy,
    double dx,
    double dy,
  ) {
    var more = true;
    while (more) {
      final int flags = cursor.u16be();
      final int glyphIndex = cursor.u16be();
      components.add(glyphIndex);
      more = (flags & 0x0020) != 0;
      double arg1;
      double arg2;
      if ((flags & 0x0001) != 0) {
        arg1 = cursor.i16be().toDouble();
        arg2 = cursor.i16be().toDouble();
      } else {
        arg1 = _i8(cursor.u8()).toDouble();
        arg2 = _i8(cursor.u8()).toDouble();
      }
      double nxx = 1, nxy = 0, nyx = 0, nyy = 1;
      if ((flags & 0x0008) != 0) {
        nxx = nyy = cursor.i16be() / 16384.0;
      } else if ((flags & 0x0040) != 0) {
        nxx = cursor.i16be() / 16384.0;
        nyy = cursor.i16be() / 16384.0;
      } else if ((flags & 0x0080) != 0) {
        nxx = cursor.i16be() / 16384.0;
        nxy = cursor.i16be() / 16384.0;
        nyx = cursor.i16be() / 16384.0;
        nyy = cursor.i16be() / 16384.0;
      }
      final double odx = (flags & 0x0002) != 0 ? arg1 : 0;
      final double ody = (flags & 0x0002) != 0 ? arg2 : 0;
      final GlyphOutline child = decode(glyphIndex);
      for (final GlyphPathCommand cmd in child.commands) {
        if (cmd.op == GlyphPathOp.close) {
          commands.add(cmd);
          continue;
        }
        final double x =
            xx * (nxx * cmd.x + nxy * cmd.y) +
            xy * (nyx * cmd.x + nyy * cmd.y) +
            dx +
            odx;
        final double y =
            yx * (nxx * cmd.x + nxy * cmd.y) +
            yy * (nyx * cmd.x + nyy * cmd.y) +
            dy +
            ody;
        final double cx =
            xx * (nxx * cmd.cx + nxy * cmd.cy) +
            xy * (nyx * cmd.cx + nyy * cmd.cy) +
            dx +
            odx;
        final double cy =
            yx * (nxx * cmd.cx + nxy * cmd.cy) +
            yy * (nyx * cmd.cx + nyy * cmd.cy) +
            dy +
            ody;
        commands.add(GlyphPathCommand(cmd.op, x, y, cx, cy));
      }
      if ((flags & 0x0100) != 0) {
        final int n = cursor.u16be();
        cursor.skip(n);
      }
    }
  }

  static List<int> _coords(
    ByteCursor cursor,
    List<int> flags,
    int shortFlag,
    int sameFlag,
  ) {
    final List<int> out = <int>[];
    int value = 0;
    for (final int flag in flags) {
      if ((flag & shortFlag) != 0) {
        final int mag = cursor.u8();
        value += (flag & sameFlag) != 0 ? mag : -mag;
      } else if ((flag & sameFlag) == 0) {
        value += cursor.i16be();
      }
      out.add(value);
    }
    return out;
  }
}

class _Pt {
  const _Pt(this.x, this.y, this.on);

  /// x API.
  final double x;

  /// y API.
  final double y;
  final bool on;
}

int _i8(int value) => value >= 128 ? value - 256 : value;
