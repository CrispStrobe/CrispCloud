import '../../xml/xml_reader.dart';
import '../../xml/xml_writer.dart';
import '../model/pml_presentation.dart';
import 'pml_motion.dart';

/// parseSlideMotion helper.
void parseSlideMotion(String xml, PmlSlide slide) {
  /// reader API.
  final XmlPullReader reader = XmlPullReader(xml);

  /// inTransition API.
  var inTransition = false;

  /// inTiming API.
  var inTiming = false;

  /// kind API.
  PmlTransitionKind? kind;

  /// dir API.
  var dir = PmlTransitionDir.left;

  /// durationMs API.
  var durationMs = 700;

  /// advClick API.
  var advClick = true;

  /// advAfter API.
  int? advAfter;

  /// pendingSpid API.
  int? pendingSpid;

  /// pendingClass API.
  PmlAnimClass? pendingClass;

  /// pendingPreset API.
  PmlAnimPreset? pendingPreset;

  /// pendingDur API.
  var pendingDur = 500;

  /// pendingDelay API.
  var pendingDelay = 0;

  /// pendingTrigger API.
  var pendingTrigger = PmlAnimTrigger.onClick;

  /// pendingDir API.
  var pendingDir = PmlTransitionDir.left;

  /// order API.
  var order = 0;
  while (reader.next()) {
    if (reader.eventType == XmlEventType.endElement) {
      if (reader.localName == 'transition') {
        inTransition = false;
      } else if (reader.localName == 'timing') {
        inTiming = false;
      } else if (reader.localName == 'cTn' &&
          pendingPreset != null &&
          pendingSpid != null) {
        slide.animations.add(
          PmlShapeAnimation(
            shapeId: pendingSpid,
            preset: pendingPreset,
            trigger: pendingTrigger,
            direction: pendingDir,
            durationMs: pendingDur,
            delayMs: pendingDelay,
            order: order++,
          ),
        );
        pendingPreset = null;
        pendingSpid = null;
        pendingDelay = 0;
        pendingDir = PmlTransitionDir.left;
        pendingDur = 500;
      }
      continue;
    }
    if (reader.eventType != XmlEventType.startElement) {
      continue;
    }
    if (reader.localName == 'transition') {
      inTransition = true;
      durationMs = _spdToMs(reader.getAttribute('spd'));
      final String? dur =
          reader.getAttribute('dur') ?? reader.getAttribute('p14:dur');
      if (dur != null) {
        durationMs = int.tryParse(dur) ?? durationMs;
      }
      advClick = reader.getAttribute('advClick') != '0';
      final int? tm = int.tryParse(reader.getAttribute('advTm') ?? '');
      if (tm != null && tm > 0) {
        advAfter = tm;
      }
    } else if (inTransition && kind == null) {
      if (reader.localName == 'prstTrans' &&
          reader.getAttribute('prst') == 'morph') {
        kind = PmlTransitionKind.morph;
      } else {
        final PmlTransitionKind? parsed = _kindFromXml(reader.localName);
        if (parsed != null) {
          kind = parsed;
          if (reader.getAttribute('thruBlk') == '1' &&
              parsed == PmlTransitionKind.fade) {
            kind = PmlTransitionKind.fadeThroughBlack;
          }
          dir = _dirFromXml(
            reader.getAttribute('dir') ?? reader.getAttribute('orient'),
          );
        }
      }
    } else if (reader.localName == 'timing') {
      inTiming = true;
    } else if (inTiming && reader.localName == 'cTn') {
      final String? cls = reader.getAttribute('presetClass');
      final int? id = int.tryParse(reader.getAttribute('presetID') ?? '');
      final int? dur = int.tryParse(reader.getAttribute('dur') ?? '');
      if (cls != null) {
        pendingClass = switch (cls) {
          'entr' => PmlAnimClass.entrance,
          'emph' => PmlAnimClass.emphasis,
          'exit' => PmlAnimClass.exit,
          'path' => PmlAnimClass.motion,
          _ => pendingClass,
        };
        pendingPreset = _presetFromId(id, pendingClass);
        if (dur != null && dur > 0) {
          pendingDur = dur;
        }
        final int? subtype = int.tryParse(
          reader.getAttribute('presetSubtype') ?? '',
        );
        if (subtype != null) {
          pendingDir = _dirFromSubtype(subtype);
        }
        final String? node = reader.getAttribute('nodeType');
        pendingTrigger = switch (node) {
          'withEffect' => PmlAnimTrigger.withPrevious,
          'afterEffect' => PmlAnimTrigger.afterPrevious,
          _ => PmlAnimTrigger.onClick,
        };
      }
    } else if (inTiming && reader.localName == 'cond') {
      final int? delay = int.tryParse(reader.getAttribute('delay') ?? '');
      if (delay != null && delay > 0 && delay < 100000) {
        pendingDelay = delay;
      }
    } else if (inTiming && reader.localName == 'spTgt') {
      pendingSpid = int.tryParse(reader.getAttribute('spid') ?? '');
    }
  }
  if (kind != null) {
    slide.transition = PmlSlideTransition(
      kind: kind,
      direction: dir,
      durationMs: durationMs,
      advanceOnClick: advClick,
      advanceAfterMs: advAfter,
    );
  }
}

/// writeSlideMotion helper.
void writeSlideMotion(XmlWriter w, PmlSlide slide) {
  if (!slide.transition.isNone) {
    w.writeStartElement('transition', prefix: 'p');
    w.writeAttribute('spd', _msToSpd(slide.transition.durationMs));
    w.writeAttribute('dur', '${slide.transition.durationMs}');
    w.writeAttribute('advClick', slide.transition.advanceOnClick ? '1' : '0');
    if (slide.transition.advanceAfterMs != null) {
      w.writeAttribute('advTm', '${slide.transition.advanceAfterMs}');
    }
    final String name = _kindToXml(slide.transition.kind);
    w.writeStartElement(name, prefix: 'p');
    if (slide.transition.kind == PmlTransitionKind.fadeThroughBlack) {
      w.writeAttribute('thruBlk', '1');
    }
    if (slide.transition.kind == PmlTransitionKind.morph) {
      w.writeAttribute('option', 'byObject');
    }
    final String? dir = _dirToXml(slide.transition);
    if (dir != null) {
      w.writeAttribute('dir', dir);
    }
    w.writeEndElement();
    w.writeEndElement();
  }
  if (slide.animations.isEmpty) {
    return;
  }

  /// writeStartElement API.
  w.writeStartElement('timing', prefix: 'p');

  /// writeStartElement API.
  w.writeStartElement('tnLst', prefix: 'p');

  /// writeStartElement API.
  w.writeStartElement('par', prefix: 'p');

  /// writeStartElement API.
  w.writeStartElement('cTn', prefix: 'p');

  /// writeAttribute API.
  w.writeAttribute('id', '1');

  /// writeAttribute API.
  w.writeAttribute('dur', 'indefinite');

  /// writeAttribute API.
  w.writeAttribute('nodeType', 'tmRoot');

  /// writeStartElement API.
  w.writeStartElement('childTnLst', prefix: 'p');

  /// id API.
  var id = 2;
  for (final PmlShapeAnimation anim in slide.animations) {
    w.writeStartElement('par', prefix: 'p');
    w.writeStartElement('cTn', prefix: 'p');
    w.writeAttribute('id', '${id++}');
    w.writeAttribute('presetID', '${_presetId(anim.preset)}');
    w.writeAttribute('presetSubtype', '${_dirToSubtype(anim.direction)}');
    w.writeAttribute('presetClass', switch (anim.category) {
      PmlAnimClass.entrance => 'entr',
      PmlAnimClass.emphasis => 'emph',
      PmlAnimClass.exit => 'exit',
      PmlAnimClass.motion => 'path',
    });
    w.writeAttribute('dur', '${anim.durationMs}');
    w.writeAttribute('nodeType', switch (anim.trigger) {
      PmlAnimTrigger.onClick => 'clickEffect',
      PmlAnimTrigger.withPrevious => 'withEffect',
      PmlAnimTrigger.afterPrevious => 'afterEffect',
    });
    w.writeStartElement('stCondLst', prefix: 'p');
    w.writeStartElement('cond', prefix: 'p');
    w.writeAttribute('delay', '${anim.delayMs}');
    w.writeEndElement();
    w.writeEndElement();
    w.writeStartElement('childTnLst', prefix: 'p');
    w.writeStartElement('animEffect', prefix: 'p');
    w.writeAttribute(
      'transition',
      anim.category == PmlAnimClass.exit ? 'out' : 'in',
    );
    w.writeAttribute('filter', anim.preset.name);
    w.writeStartElement('cBhvr', prefix: 'p');
    w.writeStartElement('cTn', prefix: 'p');
    w.writeAttribute('id', '${id++}');
    w.writeAttribute('dur', '${anim.durationMs}');
    w.writeEndElement();
    w.writeStartElement('tgtEl', prefix: 'p');
    w.writeStartElement('spTgt', prefix: 'p');
    w.writeAttribute('spid', '${anim.shapeId}');
    w.writeEndElement();
    w.writeEndElement();
    w.writeEndElement();
    w.writeEndElement();
    w.writeEndElement();
    w.writeEndElement();
    w.writeEndElement();
  }

  /// writeEndElement API.
  w.writeEndElement();

  /// writeEndElement API.
  w.writeEndElement();

  /// writeEndElement API.
  w.writeEndElement();

  /// writeEndElement API.
  w.writeEndElement();

  /// writeEndElement API.
  w.writeEndElement();
}

PmlTransitionKind? _kindFromXml(String name) {
  return switch (name) {
    'fade' => PmlTransitionKind.fade,
    'cut' => PmlTransitionKind.cut,
    'push' => PmlTransitionKind.push,
    'wipe' => PmlTransitionKind.wipe,
    'split' => PmlTransitionKind.split,
    'pull' => PmlTransitionKind.uncover,
    'cover' => PmlTransitionKind.cover,
    'dissolve' => PmlTransitionKind.dissolve,
    'checker' => PmlTransitionKind.checkerboard,
    'blinds' => PmlTransitionKind.blinds,
    'wheel' || 'clock' => PmlTransitionKind.clock,
    'circle' => PmlTransitionKind.shapeCircle,
    'diamond' => PmlTransitionKind.shapeDiamond,
    'plus' => PmlTransitionKind.shapePlus,
    'newsflash' => PmlTransitionKind.newsflash,
    'zoom' => PmlTransitionKind.zoom,
    'flash' => PmlTransitionKind.flash,
    'comb' => PmlTransitionKind.comb,
    'strips' => PmlTransitionKind.strips,
    'randomBar' => PmlTransitionKind.randomBars,
    'reveal' => PmlTransitionKind.reveal,
    'gallery' => PmlTransitionKind.gallery,
    'doors' => PmlTransitionKind.doors,
    'morph' => PmlTransitionKind.morph,
    _ => null,
  };
}

String _kindToXml(PmlTransitionKind kind) {
  return switch (kind) {
    PmlTransitionKind.none ||
    PmlTransitionKind.fade ||
    PmlTransitionKind.fadeThroughBlack => 'fade',
    PmlTransitionKind.cut => 'cut',
    PmlTransitionKind.push => 'push',
    PmlTransitionKind.wipe => 'wipe',
    PmlTransitionKind.split => 'split',
    PmlTransitionKind.uncover => 'pull',
    PmlTransitionKind.cover => 'cover',
    PmlTransitionKind.dissolve => 'dissolve',
    PmlTransitionKind.checkerboard => 'checker',
    PmlTransitionKind.blinds => 'blinds',
    PmlTransitionKind.clock => 'wheel',
    PmlTransitionKind.shapeCircle => 'circle',
    PmlTransitionKind.shapeDiamond => 'diamond',
    PmlTransitionKind.shapePlus => 'plus',
    PmlTransitionKind.newsflash => 'newsflash',
    PmlTransitionKind.zoom => 'zoom',
    PmlTransitionKind.flash => 'flash',
    PmlTransitionKind.comb => 'comb',
    PmlTransitionKind.strips => 'strips',
    PmlTransitionKind.randomBars => 'randomBar',
    PmlTransitionKind.reveal => 'reveal',
    PmlTransitionKind.gallery => 'gallery',
    PmlTransitionKind.doors => 'doors',
    PmlTransitionKind.morph => 'morph',
  };
}

PmlTransitionDir _dirFromXml(String? raw) {
  return switch (raw) {
    'r' || 'right' => PmlTransitionDir.right,
    'u' || 'up' => PmlTransitionDir.up,
    'd' || 'down' => PmlTransitionDir.down,
    'horz' => PmlTransitionDir.horizontal,
    'vert' => PmlTransitionDir.vertical,
    'in' => PmlTransitionDir.inward,
    'out' => PmlTransitionDir.outward,
    _ => PmlTransitionDir.left,
  };
}

String? _dirToXml(PmlSlideTransition t) {
  if (!PmlMotionCatalog.usesDirection(t.kind)) {
    return null;
  }
  if (t.kind == PmlTransitionKind.split || t.kind == PmlTransitionKind.doors) {
    return t.direction == PmlTransitionDir.vertical ? 'd' : 'r';
  }
  return switch (t.direction) {
    PmlTransitionDir.right => 'r',
    PmlTransitionDir.up => 'u',
    PmlTransitionDir.down => 'd',
    PmlTransitionDir.horizontal => 'l',
    PmlTransitionDir.vertical => 'd',
    PmlTransitionDir.inward => 'in',
    PmlTransitionDir.outward => 'out',
    PmlTransitionDir.left => 'l',
  };
}

int _spdToMs(String? spd) {
  return switch (spd) {
    'slow' => 1200,
    'fast' => 350,
    _ => 700,
  };
}

String _msToSpd(int ms) {
  if (ms <= 400) {
    return 'fast';
  }
  if (ms >= 1000) {
    return 'slow';
  }
  return 'med';
}

int _presetId(PmlAnimPreset preset) {
  return switch (preset) {
    PmlAnimPreset.appear => 1,
    PmlAnimPreset.flyIn => 2,
    PmlAnimPreset.floatIn => 3,
    PmlAnimPreset.split => 4,
    PmlAnimPreset.wipe => 5,
    PmlAnimPreset.grow => 6,
    PmlAnimPreset.zoom => 7,
    PmlAnimPreset.bounce => 8,
    PmlAnimPreset.shrink => 9,
    PmlAnimPreset.fade => 10,
    PmlAnimPreset.peekIn => 12,
    PmlAnimPreset.riseUp => 13,
    PmlAnimPreset.swivel => 14,
    PmlAnimPreset.growTurn => 15,
    PmlAnimPreset.pulse => 23,
    PmlAnimPreset.spin => 24,
    PmlAnimPreset.teeter => 25,
    PmlAnimPreset.growShrink => 26,
    PmlAnimPreset.disappear => 1,
    PmlAnimPreset.fadeOut => 10,
    PmlAnimPreset.flyOut => 2,
    PmlAnimPreset.pathLine => 16,
    PmlAnimPreset.pathArc => 17,
  };
}

PmlAnimPreset _presetFromId(int? id, PmlAnimClass? cls) {
  if (cls == PmlAnimClass.emphasis) {
    return switch (id) {
      24 => PmlAnimPreset.spin,
      25 => PmlAnimPreset.teeter,
      26 => PmlAnimPreset.growShrink,
      _ => PmlAnimPreset.pulse,
    };
  }
  if (cls == PmlAnimClass.exit) {
    return switch (id) {
      2 => PmlAnimPreset.flyOut,
      9 => PmlAnimPreset.shrink,
      10 => PmlAnimPreset.fadeOut,
      _ => PmlAnimPreset.disappear,
    };
  }
  if (cls == PmlAnimClass.motion) {
    return id == 17 ? PmlAnimPreset.pathArc : PmlAnimPreset.pathLine;
  }
  return switch (id) {
    2 => PmlAnimPreset.flyIn,
    3 => PmlAnimPreset.floatIn,
    4 => PmlAnimPreset.split,
    5 => PmlAnimPreset.wipe,
    6 => PmlAnimPreset.grow,
    7 => PmlAnimPreset.zoom,
    8 => PmlAnimPreset.bounce,
    10 => PmlAnimPreset.fade,
    12 => PmlAnimPreset.peekIn,
    13 => PmlAnimPreset.riseUp,
    14 => PmlAnimPreset.swivel,
    15 => PmlAnimPreset.growTurn,
    _ => PmlAnimPreset.appear,
  };
}

int _dirToSubtype(PmlTransitionDir dir) {
  return switch (dir) {
    PmlTransitionDir.up => 1,
    PmlTransitionDir.right => 2,
    PmlTransitionDir.down => 4,
    PmlTransitionDir.left => 8,
    PmlTransitionDir.horizontal => 16,
    PmlTransitionDir.vertical => 32,
    PmlTransitionDir.inward => 64,
    PmlTransitionDir.outward => 128,
  };
}

PmlTransitionDir _dirFromSubtype(int subtype) {
  return switch (subtype) {
    1 => PmlTransitionDir.up,
    2 => PmlTransitionDir.right,
    4 => PmlTransitionDir.down,
    16 => PmlTransitionDir.horizontal,
    32 => PmlTransitionDir.vertical,
    64 => PmlTransitionDir.inward,
    128 => PmlTransitionDir.outward,
    _ => PmlTransitionDir.left,
  };
}
