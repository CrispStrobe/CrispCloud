import 'package:quds_office_engine/quds_office_engine.dart';
import 'step_input.dart';

const slideOperations = <String, List<String>>{
  'shapeText': ['slide', 'shape', 'shapeName', 'topLevel', 'text'],
  'shapeTextFrame': [
    'slide',
    'shape',
    'shapeName',
    'topLevel',
    'anchor',
    'marginLeft',
    'marginTop',
    'marginRight',
    'marginBottom',
  ],
  'shapeFormat': [
    'slide',
    'shape',
    'shapeName',
    'topLevel',
    'size',
    'font',
    'bold',
    'italic',
    'underline',
    'color',
    'fill',
    'alignment',
    'rtl',
  ],
  'shapeGeometry': [
    'slide',
    'shape',
    'shapeName',
    'topLevel',
    'x',
    'y',
    'width',
    'height',
    'rotation',
  ],
  'slideNotes': ['slide', 'text'],
  'slideHidden': ['slide', 'hidden'],
  'slideOrder': ['slide', 'to'],
  'slideTransition': [
    'slide',
    'kind',
    'direction',
    'durationMs',
    'advanceOnClick',
  ],
  'slideImageReplace': ['slide', 'shape', 'shapeName', 'topLevel', 'file'],
};

void applySlideStep(
  PmlPresentation deck,
  Map<String, Object?> values, {
  OfficeMacroAssetResolver? resolveAsset,
}) {
  final s = StepInput(values);
  final op = s.string('op');
  final fields = slideOperations[op];
  if (fields == null) throw ArgumentError('Unknown PPTX operation: $op');
  s.fields(fields);
  final slide = s.item('slide', deck.slides, fallback: 0);
  PmlShape shape() {
    if (s.has('shape') == s.has('shapeName')) {
      throw ArgumentError('Provide exactly one of shape or shapeName');
    }
    if (s.boolean('topLevel', fallback: false)) {
      _requireTopLevelShapes(deck, slide);
    }
    if (s.has('shape')) return s.item('shape', slide.shapes);
    final name = s.string('shapeName');
    if (name.isEmpty) throw ArgumentError('shapeName must not be empty');
    final matches = slide.shapes.where((shape) => shape.name == name).toList();
    if (matches.length != 1) {
      throw ArgumentError(
        matches.isEmpty
            ? 'No shape named $name'
            : 'Ambiguous shape name: $name',
      );
    }
    return matches.single;
  }

  switch (op) {
    case 'shapeTextFrame':
      final target = shape();
      if (target.visual != null || target.table != null) {
        throw ArgumentError('shapeTextFrame requires a text shape');
      }
      final margins = <PmlTextInsetSide, double>{};
      for (final side in PmlTextInsetSide.values) {
        final field = switch (side) {
          PmlTextInsetSide.left => 'marginLeft',
          PmlTextInsetSide.top => 'marginTop',
          PmlTextInsetSide.right => 'marginRight',
          PmlTextInsetSide.bottom => 'marginBottom',
        };
        if (!s.has(field)) continue;
        final points = s.number(field, min: 0, max: 2147483647 / 12700);
        final emu = points * 12700;
        if (emu.round() / 12700 != points) {
          throw ArgumentError(
            '$field must have an exact integer EMU representation',
          );
        }
        margins[side] = points;
      }
      final anchor = s.has('anchor')
          ? PmlTextAnchor.values.byName(s.string('anchor'))
          : null;
      if (anchor == null && margins.isEmpty) {
        throw ArgumentError('shapeTextFrame requires an anchor or margin');
      }
      if (anchor != null) {
        target.textAnchor = anchor;
        target.textAnchorOverride = true;
      }
      for (final entry in margins.entries) {
        target.textInsets = target.textInsets.withSide(entry.key, entry.value);
        target.textInsetOverrides.add(entry.key);
      }
    case 'shapeText':
      final target = shape();
      if (target.visual != null || target.table != null) {
        throw ArgumentError('shapeText requires a text shape');
      }
      target.text = s.string('text');
      target.textReplacementRequested = true;
    case 'shapeFormat':
      final target = shape();
      if (target.visual != null || target.table != null) {
        throw ArgumentError('shapeFormat requires a text shape');
      }
      if (s.has('size')) {
        target.fontSizePt = s.number('size', min: 1);
        target.textSizeOverride = true;
      }
      if (s.has('color')) {
        target.textColor = s.color('color');
        target.textColorOverride = true;
      }
      if (s.has('bold')) target.textBold = s.boolean('bold');
      if (s.has('italic')) target.textItalic = s.boolean('italic');
      if (s.has('underline')) target.textUnderline = s.boolean('underline');
      if (s.has('font')) {
        final font = s.string('font');
        if (font.trim().isEmpty ||
            font.length > 255 ||
            RegExp(r'[\x00-\x1f\x7f]').hasMatch(font)) {
          throw ArgumentError(
            'font must be a nonempty typeface name of at most 255 characters',
          );
        }
        target.textFontFamily = font;
      }
      if (s.has('fill')) target.fillColor = s.color('fill');
      if (s.has('alignment')) {
        target.textAlign = PmlTextAlign.values.byName(s.string('alignment'));
        target.textAlignOverride = true;
      }
      if (s.has('rtl')) {
        target.rightToLeft = s.boolean('rtl');
        target.textDirectionOverride = true;
      }
    case 'shapeGeometry':
      final target = shape();
      final before = target.transform;
      final transform = before.copyWith(
        x: (s.number('x', fallback: before.xPoints) * 12700).round(),
        y: (s.number('y', fallback: before.yPoints) * 12700).round(),
        cx: (s.number('width', fallback: before.widthPoints, min: 0.01) * 12700)
            .round(),
        cy:
            (s.number('height', fallback: before.heightPoints, min: 0.01) *
                    12700)
                .round(),
        rot: (s.number('rotation', fallback: before.rotationDegrees) * 60000)
            .round(),
        flipH: before.flipH,
        flipV: before.flipV,
      );
      target.transform = transform;
      if (target.visual case final OfficeVisual visual) {
        visual.width = transform.widthPoints;
        visual.height = transform.heightPoints;
      }
    case 'slideNotes':
      slide.notes = s.string('text');
    case 'slideHidden':
      slide.hidden = s.boolean('hidden');
    case 'slideOrder':
      final at = s.integer('to', max: deck.slides.length - 1);
      PmlSections.reorderSlide(deck, deck.slides.indexOf(slide), at);
    case 'slideTransition':
      final transitionIssue = slide.transition.source?.unsupportedContext;
      if (transitionIssue != null) {
        throw UnsupportedError(transitionIssue);
      }
      if (slide.transition.source?.isOpaqueContainer ?? false) {
        throw UnsupportedError(
          'Transition changes do not support markup-compatibility containers',
        );
      }
      slide.transition = PmlSlideTransition(
        kind: PmlTransitionKind.values.byName(
          s.string('kind', fallback: slide.transition.kind.name),
        ),
        direction: PmlTransitionDir.values.byName(
          s.string('direction', fallback: slide.transition.direction.name),
        ),
        durationMs: s.integer(
          'durationMs',
          fallback: slide.transition.durationMs,
          min: 1,
        ),
        advanceOnClick: s.boolean(
          'advanceOnClick',
          fallback: slide.transition.advanceOnClick,
        ),
        advanceAfterMs: slide.transition.advanceAfterMs,
        source: slide.transition.source,
        effectOverride:
            slide.transition.effectOverride ||
            s.has('kind') ||
            s.has('direction'),
        durationOverride:
            slide.transition.durationOverride || s.has('durationMs'),
        advanceOnClickOverride:
            slide.transition.advanceOnClickOverride || s.has('advanceOnClick'),
      );
    case 'slideImageReplace':
      final visual = shape().visual;
      if (visual == null || !visual.isPicture) {
        throw ArgumentError('Shape is not a picture');
      }
      visual.imageBytes = readPicture(s, resolveAsset);
  }
}

// The native model exposes flattened group children. VBA Shapes is instead
// the top-level Office collection, so admit it only when source provenance
// proves the same complete object order. Keep the existing native selector
// contract for callers that do not request this stricter scope.
void _requireTopLevelShapes(PmlPresentation deck, PmlSlide slide) {
  if (slide.shapes.any((shape) => shape.groupId != null)) {
    throw UnsupportedError(
      'Top-level Shapes selectors do not support grouped slides',
    );
  }
  final uri = slide.sourcePartUri;
  if (uri == null) return;
  final part = deck.package?.getPart(uri);
  if (part == null) {
    throw UnsupportedError(
      'Top-level Shapes collection has no source provenance',
    );
  }
  final tree = XmlDocument.parse(part.readText()).root
      ?.firstChild('cSld', namespaceUri: OfficeNamespaces.p)
      ?.firstChild('spTree', namespaceUri: OfficeNamespaces.p);
  if (tree == null) {
    throw UnsupportedError(
      'Top-level Shapes collection has no native shape tree',
    );
  }
  final objects = <XmlElement>[];
  for (final child in tree.childElements) {
    if (child.namespaceUri == OfficeNamespaces.p &&
        const {'nvGrpSpPr', 'grpSpPr', 'extLst'}.contains(child.localName)) {
      continue;
    }
    if (child.namespaceUri != OfficeNamespaces.p ||
        !const {
          'sp',
          'pic',
          'graphicFrame',
          'cxnSp',
        }.contains(child.localName)) {
      throw UnsupportedError(
        'Top-level Shapes collection contains an unsupported object',
      );
    }
    objects.add(child);
  }
  if (objects.length != slide.shapes.length) {
    throw UnsupportedError('Native and modeled Shapes collections differ');
  }
  final ids = <int>{};
  for (var index = 0; index < objects.length; index++) {
    final object = objects[index];
    final properties = object
        .firstChild(switch (object.localName) {
          'sp' => 'nvSpPr',
          'pic' => 'nvPicPr',
          'graphicFrame' => 'nvGraphicFramePr',
          _ => 'nvCxnSpPr',
        }, namespaceUri: OfficeNamespaces.p)
        ?.firstChild('cNvPr', namespaceUri: OfficeNamespaces.p);
    final id = int.tryParse(properties?.getAttribute('id') ?? '');
    final shape = slide.shapes[index];
    if (id == null ||
        !ids.add(id) ||
        id != shape.id ||
        (object.localName == 'graphicFrame' &&
            shape.table == null &&
            shape.visual == null)) {
      throw UnsupportedError(
        'Native and modeled Shapes identities or order differ',
      );
    }
  }
}

Map<String, Object?> inspectSlides(PmlPresentation deck) => <String, Object?>{
  'format': 'pptx',
  'slides': <Object?>[
    for (final slide in deck.slides)
      <String, Object?>{
        'id': slide.id,
        'notes': slide.notes,
        'hidden': slide.hidden,
        'transition': slide.transition.kind.name,
        'shapes': <Object?>[
          for (final shape in slide.shapes)
            <String, Object?>{
              'id': shape.id,
              'name': shape.name,
              'text': shape.text,
              'x': shape.transform.xPoints,
              'y': shape.transform.yPoints,
              'width': shape.transform.widthPoints,
              'height': shape.transform.heightPoints,
              'rotation': shape.transform.rotationDegrees,
              'picture': shape.visual?.isPicture ?? false,
            },
        ],
      },
  ],
};
