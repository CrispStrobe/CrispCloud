import '../../xml/namespaces.dart';
import '../../xml/xml_node.dart';
import '../../xml/xml_reader.dart';
import '../../xml/xml_writer.dart';
import '../model/pml_presentation.dart';
import 'pml_motion.dart';

const _powerPoint2010 =
    'http://schemas.microsoft.com/office/powerpoint/2010/main';
const _powerPoint2012 =
    'http://schemas.microsoft.com/office/powerpoint/2012/main';
const _powerPoint2015 =
    'http://schemas.microsoft.com/office/powerpoint/2015/09/main';

/// parseSlideMotion helper.
void parseSlideMotion(String xml, PmlSlide slide) {
  /// reader API.
  final XmlPullReader reader = XmlPullReader(xml);

  /// inTransition API.
  var inTransition = false;
  var hasTransition = false;
  // Preserve the public helper's historical conventional-prefix fragment
  // input. Real documents with declared namespaces still use URI matching.
  var legacyFragment = false;

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
      if (reader.localName == 'transition' &&
          _isPresentationMotionElement(reader, legacyFragment) &&
          reader.depth == 1) {
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
    if (reader.depth == 1) {
      legacyFragment =
          reader.localName == 'sld' &&
          reader.prefix == 'p' &&
          reader.namespaceUri.isEmpty;
    }
    if (reader.localName == 'transition' &&
        _isPresentationMotionElement(reader, legacyFragment) &&
        reader.depth == 2) {
      inTransition = !reader.isEmptyElement;
      hasTransition = true;
      durationMs = _spdToMs(reader.getAttribute('spd', namespaceUri: ''));
      final String? dur =
          reader.getAttribute('dur', namespaceUri: _powerPoint2010) ??
          reader.getAttribute('dur', namespaceUri: '');
      if (dur != null) {
        durationMs = int.tryParse(dur) ?? durationMs;
      }
      advClick = reader.getAttribute('advClick', namespaceUri: '') != '0';
      final int? tm = int.tryParse(
        reader.getAttribute('advTm', namespaceUri: '') ?? '',
      );
      if (tm != null && tm > 0) {
        advAfter = tm;
      }
    } else if (inTransition &&
        kind == null &&
        reader.depth == 3 &&
        _isTransitionEffectElement(reader, legacyFragment)) {
      if (reader.localName == 'prstTrans' &&
          reader.getAttribute('prst', namespaceUri: '') == 'morph') {
        kind = PmlTransitionKind.morph;
      } else {
        final PmlTransitionKind? parsed = _kindFromXml(reader.localName);
        if (parsed != null) {
          kind = parsed;
          if (reader.getAttribute('thruBlk', namespaceUri: '') == '1' &&
              parsed == PmlTransitionKind.fade) {
            kind = PmlTransitionKind.fadeThroughBlack;
          }
          dir = _dirFromXml(
            reader.getAttribute('dir', namespaceUri: '') ??
                reader.getAttribute('orient', namespaceUri: ''),
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
  final root = XmlDocument.parse(xml).root;
  XmlElement? sourceElement;
  var opaqueContainer = false;
  if (root?.namespaceUri == OfficeNamespaces.p && root?.localName == 'sld') {
    for (final child in root!.childElements) {
      if (child.namespaceUri == OfficeNamespaces.p &&
          child.localName == 'transition') {
        sourceElement = child;
        break;
      }
      if (child.namespaceUri == OfficeNamespaces.mc &&
          child.localName == 'AlternateContent' &&
          _containsTransitionBranch(child)) {
        sourceElement = child;
        opaqueContainer = true;
        break;
      }
    }
  }
  if (hasTransition || sourceElement != null) {
    final value = opaqueContainer
        ? const PmlSlideTransition()
        : PmlSlideTransition(
            kind: kind ?? PmlTransitionKind.none,
            direction: dir,
            durationMs: durationMs,
            advanceOnClick: advClick,
            advanceAfterMs: advAfter,
          );
    String? source;
    String? unsupportedContext;
    if (sourceElement != null) {
      final copy = sourceElement.copy();
      unsupportedContext = _inheritTransitionContext(root!, copy);
      source = XmlDocument(root: copy).toXmlString(declaration: false);
    }
    slide.transition = PmlSlideTransition(
      kind: value.kind,
      direction: value.direction,
      durationMs: value.durationMs,
      advanceOnClick: value.advanceOnClick,
      advanceAfterMs: value.advanceAfterMs,
      source: source == null
          ? null
          : PmlTransitionSource(
              xml: source,
              value: value,
              isOpaqueContainer: opaqueContainer,
              unsupportedContext: unsupportedContext,
            ),
    );
  }
}

bool _isPresentationMotionElement(XmlPullReader reader, bool legacyFragment) =>
    reader.namespaceUri == OfficeNamespaces.p ||
    (legacyFragment && reader.namespaceUri.isEmpty && reader.prefix == 'p');

bool _isTransitionEffectElement(XmlPullReader reader, bool legacyFragment) =>
    const <String>{
      OfficeNamespaces.p,
      _powerPoint2010,
      _powerPoint2012,
      _powerPoint2015,
    }.contains(reader.namespaceUri) ||
    (legacyFragment &&
        reader.namespaceUri.isEmpty &&
        const <String>{'p', 'p14', 'p15', 'p159'}.contains(reader.prefix));

// Preserve the root namespace scope even when prefixes occur only in values,
// such as mc:Choice@Requires. Ignorable is cumulative, and its prefixes must
// retain the namespace meaning they had at the parent rather than a child
// rebinding. More complex inherited directives are explicitly unsupported.
String? _inheritTransitionContext(XmlElement root, XmlElement fragment) {
  for (final attribute in root.attributes) {
    if ((attribute.prefix == 'xmlns' || attribute.qualifiedName == 'xmlns') &&
        !fragment.attributes.any(
          (own) => own.qualifiedName == attribute.qualifiedName,
        )) {
      fragment.attributes.add(attribute.copy());
    }
  }
  for (final inherited in root.attributes) {
    if (inherited.namespaceUri != OfficeNamespaces.mc) continue;
    if (inherited.localName != 'Ignorable') {
      return 'Inherited markup-compatibility directives other than Ignorable '
          'are not supported for transition serialization';
    }
    final own = fragment.attributes.where(
      (attribute) =>
          attribute.namespaceUri == OfficeNamespaces.mc &&
          attribute.localName == 'Ignorable',
    );
    if (own.length > 1) {
      return 'Duplicate markup-compatibility Ignorable attributes';
    }
    final prefixes = <String>{
      if (own.isNotEmpty)
        ...own.single.value
            .split(RegExp(r'\s+'))
            .where((token) => token.isNotEmpty),
    };
    for (final token in inherited.value.split(RegExp(r'\s+'))) {
      if (token.isEmpty) continue;
      final declarations = root.attributes.where(
        (attribute) => attribute.qualifiedName == 'xmlns:$token',
      );
      if (declarations.length != 1 || declarations.single.value.isEmpty) {
        return 'Inherited Ignorable prefix has no unique namespace binding';
      }
      prefixes.add(
        _transitionContextPrefix(fragment, token, declarations.single.value),
      );
    }
    if (own.isNotEmpty) {
      own.single.value = prefixes.join(' ');
    } else {
      fragment.attributes.add(
        XmlAttribute(
          localName: 'Ignorable',
          prefix: _transitionContextPrefix(
            fragment,
            inherited.prefix,
            OfficeNamespaces.mc,
          ),
          namespaceUri: OfficeNamespaces.mc,
          value: prefixes.join(' '),
        ),
      );
    }
  }
  return null;
}

String _transitionContextPrefix(
  XmlElement fragment,
  String preferred,
  String uri,
) {
  for (final declaration in fragment.attributes) {
    if (declaration.prefix == 'xmlns' && declaration.value == uri) {
      return declaration.localName;
    }
  }
  var prefix = preferred.isEmpty ? 'qudsContext' : preferred;
  var suffix = 0;
  while (fragment.attributes.any(
    (attribute) => attribute.qualifiedName == 'xmlns:$prefix',
  )) {
    prefix = 'qudsContext${suffix++}';
  }
  fragment.attributes.add(
    XmlAttribute(localName: prefix, prefix: 'xmlns', value: uri),
  );
  return prefix;
}

bool _containsTransitionBranch(XmlElement container) {
  for (final child in container.childElements) {
    if (child.namespaceUri == OfficeNamespaces.p &&
        child.localName == 'transition') {
      return true;
    }
    if (child.namespaceUri == OfficeNamespaces.mc &&
        const <String>{
          'AlternateContent',
          'Choice',
          'Fallback',
        }.contains(child.localName) &&
        _containsTransitionBranch(child)) {
      return true;
    }
  }
  return false;
}

// XmlElement.setAttribute with an empty namespace matches foreign attributes
// too. Remove only the owned attribute, then add its exact expanded name.
void _setTransitionAttribute(XmlElement element, String name, String value) {
  element.removeAttribute(name, namespaceUri: '');
  element.attributes.add(XmlAttribute(localName: name, value: value));
}

void _setTransitionDuration(XmlElement element, int milliseconds) {
  var prefix = 'p14';
  var suffix = 0;
  while (element.attributes.any(
    (attribute) =>
        attribute.qualifiedName == 'xmlns:$prefix' &&
        attribute.value != _powerPoint2010,
  )) {
    prefix = 'qudsDuration${suffix++}';
  }
  if (!element.attributes.any(
    (attribute) => attribute.qualifiedName == 'xmlns:$prefix',
  )) {
    element.attributes.add(
      XmlAttribute(localName: prefix, prefix: 'xmlns', value: _powerPoint2010),
    );
  }
  element.removeAttribute('dur', namespaceUri: _powerPoint2010);
  element.removeAttribute('dur', namespaceUri: '');
  element.attributes.add(
    XmlAttribute(
      localName: 'dur',
      prefix: prefix,
      namespaceUri: _powerPoint2010,
      value: '$milliseconds',
    ),
  );
}

bool _writePreservedTransition(
  XmlWriter writer,
  PmlSlideTransition transition,
) {
  final source = transition.source;
  if (source == null) return false;
  final contextIssue = source.unsupportedContext;
  if (contextIssue != null) throw UnsupportedError(contextIssue);
  final body = XmlDocument.parse(source.xml).root;
  if (body == null) {
    throw const FormatException('Imported slide transition is empty');
  }
  final before = source.value;
  if (source.isOpaqueContainer) {
    if (transition.effectOverride ||
        transition.durationOverride ||
        transition.advanceOnClickOverride ||
        transition.kind != before.kind ||
        transition.direction != before.direction ||
        transition.durationMs != before.durationMs ||
        transition.advanceOnClick != before.advanceOnClick ||
        transition.advanceAfterMs != before.advanceAfterMs) {
      throw UnsupportedError(
        'Transition changes do not support markup-compatibility containers',
      );
    }
    body.writeTo(writer);
    return true;
  }
  if (transition.durationOverride ||
      transition.durationMs != before.durationMs) {
    _setTransitionAttribute(body, 'spd', _msToSpd(transition.durationMs));
    _setTransitionDuration(body, transition.durationMs);
  }
  if (transition.advanceOnClickOverride ||
      transition.advanceOnClick != before.advanceOnClick) {
    _setTransitionAttribute(
      body,
      'advClick',
      transition.advanceOnClick ? '1' : '0',
    );
  }
  if (transition.advanceAfterMs != before.advanceAfterMs) {
    if (transition.advanceAfterMs == null) {
      body.removeAttribute('advTm', namespaceUri: '');
    } else {
      _setTransitionAttribute(body, 'advTm', '${transition.advanceAfterMs}');
    }
  }
  if (transition.effectOverride ||
      transition.kind != before.kind ||
      transition.direction != before.direction) {
    body.children.removeWhere(
      (node) =>
          node is XmlElement &&
          !(node.namespaceUri == OfficeNamespaces.p &&
              (node.localName == 'sndAc' || node.localName == 'extLst')),
    );
    if (!transition.isNone) {
      final effect = XmlElement(
        localName: _kindToXml(transition.kind),
        prefix: body.prefix,
        namespaceUri: OfficeNamespaces.p,
      );
      if (transition.kind == PmlTransitionKind.fadeThroughBlack) {
        effect.setAttribute('thruBlk', '1');
      }
      if (transition.kind == PmlTransitionKind.morph) {
        effect.setAttribute('option', 'byObject');
      }
      final direction = _dirToXml(transition);
      if (direction != null) effect.setAttribute('dir', direction);
      body.children.insert(0, effect..parent = body);
    }
  }
  body.writeTo(writer);
  return true;
}

/// writeSlideMotion helper.
void writeSlideMotion(XmlWriter w, PmlSlide slide) {
  if (_writePreservedTransition(w, slide.transition)) {
    // The imported node owns unrelated transition settings.
  } else if (!slide.transition.isNone ||
      !slide.transition.advanceOnClick ||
      slide.transition.advanceAfterMs != null ||
      slide.transition.durationMs != 700 ||
      slide.transition.durationOverride ||
      slide.transition.advanceOnClickOverride ||
      slide.transition.effectOverride) {
    w.writeStartElement('transition', prefix: 'p');
    w.writeAttribute('spd', _msToSpd(slide.transition.durationMs));
    w.writeNamespace(
      'p14',
      'http://schemas.microsoft.com/office/powerpoint/2010/main',
    );
    w.writeAttribute('p14:dur', '${slide.transition.durationMs}');
    w.writeAttribute('advClick', slide.transition.advanceOnClick ? '1' : '0');
    if (slide.transition.advanceAfterMs != null) {
      w.writeAttribute('advTm', '${slide.transition.advanceAfterMs}');
    }
    if (!slide.transition.isNone) {
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
    }
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
