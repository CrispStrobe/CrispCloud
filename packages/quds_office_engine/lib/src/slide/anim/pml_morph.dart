import '../model/pml_presentation.dart';

/// Enum PmlMorphRole.
enum PmlMorphRole { keep, enter, exit }

/// Class PmlMorphPair.
class PmlMorphPair {
  /// PmlMorphPair API.
  const PmlMorphPair({this.from, this.to});

  /// from API.
  final PmlShape? from;

  /// to API.
  final PmlShape? to;

  /// role API.
  PmlMorphRole get role {
    if (from != null && to != null) {
      return PmlMorphRole.keep;
    }
    return from != null ? PmlMorphRole.exit : PmlMorphRole.enter;
  }
}

/// Interpolated shape drawn during a Morph transition.
class PmlMorphFrame {
  /// PmlMorphFrame API.
  const PmlMorphFrame({
    required this.shape,
    required this.transform,
    required this.fillColor,
    required this.text,
    required this.textColor,
    required this.fontSizePt,
    required this.opacity,
    required this.path,
    required this.preset,
    required this.role,
  });

  /// shape API.
  final PmlShape shape;

  /// transform API.
  final PmlTransform transform;

  /// fillColor API.
  final String fillColor;

  /// text API.
  final String text;

  /// textColor API.
  final String textColor;

  /// fontSizePt API.
  final double fontSizePt;

  /// opacity API.
  final double opacity;

  /// path API.
  final List<PmlPathPoint> path;

  /// preset API.
  final PmlShapePreset preset;

  /// role API.
  final PmlMorphRole role;
}

/// Matches shapes between two slides and samples Morph frames.
///
/// Pairing prefers a unique name, then a unique id, then unique
/// (preset + text). Other slides and other unmatched shapes are ignored.
class PmlMorph {
  /// ease API.
  static double ease(double t) {
    final double x = t.clamp(0.0, 1.0);
    return x * x * (3 - 2 * x);
  }

  /// pair API.
  static List<PmlMorphPair> pair(PmlSlide outgoing, PmlSlide incoming) {
    final List<PmlShape> left = List<PmlShape>.of(outgoing.shapes);
    final List<PmlShape> right = List<PmlShape>.of(incoming.shapes);
    final List<PmlMorphPair> pairs = <PmlMorphPair>[];

    void take(PmlShape a, PmlShape b) {
      pairs.add(PmlMorphPair(from: a, to: b));
      left.remove(a);
      right.remove(b);
    }

    void matchBy(
      String Function(PmlShape shape) keyOf, {
      bool skipEmpty = false,
    }) {
      final Map<String, List<PmlShape>> byLeft = _group(left, keyOf);
      final Map<String, List<PmlShape>> byRight = _group(right, keyOf);
      for (final MapEntry<String, List<PmlShape>> entry in byLeft.entries) {
        if (skipEmpty && entry.key.isEmpty) {
          continue;
        }
        final List<PmlShape> a = entry.value;
        final List<PmlShape>? b = byRight[entry.key];
        if (a.length == 1 && b != null && b.length == 1) {
          take(a.first, b.first);
        }
      }
    }

    matchBy((PmlShape s) => s.name, skipEmpty: true);
    matchBy((PmlShape s) => '${s.id}');
    matchBy((PmlShape s) => '${s.preset.name}\u001f${s.text}');
    for (final PmlShape shape in left) {
      pairs.add(PmlMorphPair(from: shape));
    }
    for (final PmlShape shape in right) {
      pairs.add(PmlMorphPair(to: shape));
    }
    return pairs;
  }

  /// keepIds API.
  static Set<int> keepIds(List<PmlMorphPair> pairs, {required bool outgoing}) {
    return <int>{
      for (final PmlMorphPair pair in pairs)
        if (pair.from != null && pair.to != null)
          (outgoing ? pair.from!.id : pair.to!.id),
    };
  }

  /// frames API.
  static List<PmlMorphFrame> frames(
    PmlSlide outgoing,
    PmlSlide incoming,
    double progress,
  ) {
    final double t = ease(progress.clamp(0.0, 1.0));
    final List<PmlMorphPair> pairs = pair(outgoing, incoming);
    final List<PmlMorphFrame> exits = <PmlMorphFrame>[];
    final List<PmlMorphFrame> keeps = <PmlMorphFrame>[];
    final List<PmlMorphFrame> enters = <PmlMorphFrame>[];
    for (final PmlMorphPair item in pairs) {
      final PmlMorphFrame frame = _frame(item, t);
      switch (item.role) {
        case PmlMorphRole.exit:
          exits.add(frame);
        case PmlMorphRole.keep:
          keeps.add(frame);
        case PmlMorphRole.enter:
          enters.add(frame);
      }
    }
    return <PmlMorphFrame>[...exits, ...keeps, ...enters];
  }

  static PmlMorphFrame _frame(PmlMorphPair pair, double t) {
    final PmlShape? from = pair.from;
    final PmlShape? to = pair.to;
    switch (pair.role) {
      case PmlMorphRole.keep:
        final PmlShape a = from!;
        final PmlShape b = to!;
        return PmlMorphFrame(
          shape: b,
          transform: _lerpTransform(a.transform, b.transform, t),
          fillColor: _lerpHex(a.fillColor, b.fillColor, t),
          text: t < 0.5 ? a.text : b.text,
          textColor: _lerpHex(
            a.textColor.isEmpty ? a.fillColor : a.textColor,
            b.textColor.isEmpty ? b.fillColor : b.textColor,
            t,
          ),
          fontSizePt: _lerpDouble(a.fontSizePt, b.fontSizePt, t),
          opacity: 1,
          path: _lerpPath(a.path, b.path, t),
          preset: t < 0.5 ? a.preset : b.preset,
          role: PmlMorphRole.keep,
        );
      case PmlMorphRole.enter:
        final PmlShape b = to!;
        return PmlMorphFrame(
          shape: b,
          transform: b.transform,
          fillColor: b.fillColor,
          text: b.text,
          textColor: b.textColor,
          fontSizePt: b.fontSizePt,
          opacity: t,
          path: b.path,
          preset: b.preset,
          role: PmlMorphRole.enter,
        );
      case PmlMorphRole.exit:
        final PmlShape a = from!;
        return PmlMorphFrame(
          shape: a,
          transform: a.transform,
          fillColor: a.fillColor,
          text: a.text,
          textColor: a.textColor,
          fontSizePt: a.fontSizePt,
          opacity: 1 - t,
          path: a.path,
          preset: a.preset,
          role: PmlMorphRole.exit,
        );
    }
  }

  static Map<String, List<PmlShape>> _group(
    List<PmlShape> shapes,
    String Function(PmlShape shape) keyOf,
  ) {
    final Map<String, List<PmlShape>> map = <String, List<PmlShape>>{};
    for (final PmlShape shape in shapes) {
      (map[keyOf(shape)] ??= <PmlShape>[]).add(shape);
    }
    return map;
  }

  static PmlTransform _lerpTransform(PmlTransform a, PmlTransform b, double t) {
    return PmlTransform(
      x: _lerpInt(a.x, b.x, t),
      y: _lerpInt(a.y, b.y, t),
      cx: _lerpInt(a.cx, b.cx, t),
      cy: _lerpInt(a.cy, b.cy, t),
      rot: _lerpRot(a.rot, b.rot, t),
    );
  }

  static List<PmlPathPoint> _lerpPath(
    List<PmlPathPoint> a,
    List<PmlPathPoint> b,
    double t,
  ) {
    if (a.isEmpty && b.isEmpty) {
      return const <PmlPathPoint>[];
    }
    if (a.length != b.length) {
      return t < 0.5 ? a : b;
    }
    return <PmlPathPoint>[
      for (int i = 0; i < a.length; i++)
        PmlPathPoint(_lerpInt(a[i].x, b[i].x, t), _lerpInt(a[i].y, b[i].y, t)),
    ];
  }

  /// round API.
  static int _lerpInt(int a, int b, double t) => (a + (b - a) * t).round();

  /// t API.
  static double _lerpDouble(double a, double b, double t) => a + (b - a) * t;

  static int _lerpRot(int a, int b, double t) {
    const double circle = 360.0 * 60000;
    var delta = (b - a).toDouble();
    while (delta > circle / 2) {
      delta -= circle;
    }
    while (delta < -circle / 2) {
      delta += circle;
    }
    return (a + delta * t).round();
  }

  static String _lerpHex(String from, String to, double t) {
    if (from.isEmpty || to.isEmpty) {
      return t < 0.5 ? from : to;
    }
    final int a = _rgb(from);
    final int b = _rgb(to);
    final int r = _lerpInt((a >> 16) & 0xFF, (b >> 16) & 0xFF, t);
    final int g = _lerpInt((a >> 8) & 0xFF, (b >> 8) & 0xFF, t);
    final int bl = _lerpInt(a & 0xFF, b & 0xFF, t);
    return ((r << 16) | (g << 8) | bl)
        .toRadixString(16)
        .padLeft(6, '0')
        .toUpperCase();
  }

  static int _rgb(String hex) {
    final String h = hex.length >= 6
        ? hex.substring(hex.length - 6)
        : hex.padLeft(6, '0');
    return int.tryParse(h, radix: 16) ?? 0x4472C4;
  }
}
