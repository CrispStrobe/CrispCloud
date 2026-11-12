# Continuation acceptance at 01b64ea

The immutable source checkpoint `01b64eaa9e96ef7cf25eb8117ba0d1291a79e77f` combines
metafile arc previews with independent object/reference revision provenance.
The isolated checkout passed 663 Dart tests, 110 Python oracle controls,
formatting, fatal-info analysis, corpus integrity, and JavaScript document/media
acceptance (47 media checks). Complete portable output is retained.

The expanded independent Open XML SDK gate generated 153 deterministic cases
and reported 12 errors in nine newly added object/revision outputs. Six had
paragraph-mark revision children after character properties; three embedded
object cases each had an invalid ObjectID and a dangling ShapeID. This initial
result is **a failure**, retained to explain and reproduce the follow-up fixes.
No cases or validator assertions were removed to obtain acceptance.

The full native run stopped when temporary disk space was exhausted, after
seven measured cases and two case errors. The last atomic report and complete
log remain here; its `running` status describes the interrupted process, not
success. Raw rasters were removed after failure to recover space. Their
measurements and hashes remain in the report. This is not complete native
acceptance, and later successful measurements do not change that result.

`initial-summary.json` identifies every schema failure and hashes the full
compressed reports and log. The schema build report records validator source,
compiler, assembly, source-input and generated-output hashes, positive/negative
controls and deterministic generation. Subsequent corrected acceptance is
recorded separately.
