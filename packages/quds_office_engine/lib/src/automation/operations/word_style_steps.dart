import 'package:quds_office_engine/quds_office_engine.dart';

import 'step_input.dart';

/// Assign one existing native paragraph style without replacing direct format.
void setWordParagraphStyle(
  WmlDocument document,
  WmlParagraph paragraph,
  StepInput input,
) {
  if (input.has('name') == input.has('builtin')) {
    throw ArgumentError('paragraphStyle requires exactly one name or builtin');
  }
  WordDeserializer().editParagraphStyle(
    document,
    paragraph,
    name: input.has('name') ? input.string('name') : null,
    builtin: input.has('builtin')
        ? input.integer('builtin', min: -75, max: -1)
        : null,
  );
}
