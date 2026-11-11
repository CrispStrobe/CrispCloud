import 'package:quds_office_engine/quds_office_engine.dart';
import 'step_input.dart';

const slideOperations = <String, List<String>>{
  'shapeText': ['slide', 'shape', 'text'],
  'shapeFormat': [
    'slide',
    'shape',
    'size',
    'color',
    'fill',
    'alignment',
    'rtl',
  ],
  'shapeGeometry': ['slide', 'shape', 'x', 'y', 'width', 'height', 'rotation'],
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
  'slideImageReplace': ['slide', 'shape', 'file'],
};

void applySlideStep(
  PmlPresentation deck,
  Map<String, Object?> values, {
  String? assetDirectory,
}) {
  final s = StepInput(values);
  final op = s.string('op');
  final fields = slideOperations[op];
  if (fields == null) throw ArgumentError('Unknown PPTX operation: $op');
  s.fields(fields);
  final slide = s.item('slide', deck.slides, fallback: 0);
  PmlShape shape() => s.item('shape', slide.shapes);
  switch (op) {
    case 'shapeText':
      final target = shape();
      if (target.visual != null || target.table != null) {
        throw ArgumentError('shapeText requires a text shape');
      }
      target.text = s.string('text');
    case 'shapeFormat':
      final target = shape();
      if (target.visual != null || target.table != null) {
        throw ArgumentError('shapeFormat requires a text shape');
      }
      if (s.has('size')) target.fontSizePt = s.number('size', min: 1);
      if (s.has('color')) target.textColor = s.color('color');
      if (s.has('fill')) target.fillColor = s.color('fill');
      if (s.has('alignment')) {
        target.textAlign = PmlTextAlign.values.byName(s.string('alignment'));
      }
      if (s.has('rtl')) target.rightToLeft = s.boolean('rtl');
    case 'shapeGeometry':
      final target = shape();
      final before = target.transform;
      final transform = PmlTransform(
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
      if (deck.sections.isNotEmpty) {
        throw ArgumentError(
          'Slide reorder requires updating section boundaries first',
        );
      }
      deck.slides.remove(slide);
      deck.slides.insert(at, slide);
    case 'slideTransition':
      slide.transition = PmlSlideTransition(
        kind: PmlTransitionKind.values.byName(s.string('kind')),
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
      );
    case 'slideImageReplace':
      final visual = shape().visual;
      if (visual == null || !visual.isPicture) {
        throw ArgumentError('Shape is not a picture');
      }
      visual.imageBytes = readPicture(s, assetDirectory);
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
