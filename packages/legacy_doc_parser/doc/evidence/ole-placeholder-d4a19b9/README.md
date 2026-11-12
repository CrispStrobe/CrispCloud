# OLE placeholder: validity and native presentation limit

The writer correction in `d4a19b9edef51fef3d96ed8399cbd5586479d0dd`
gives `o:OLEObject` a valid numeric `ObjectID` and an existing `v:shape`
target. The reviewed insertion fixture retains the original embedded CFB bytes,
the source application identity, and a generic `DrawAspect="Icon"` placeholder.
It does not reconstruct a source preview. The separate 24-case SDK run returned
zero validation errors; its exact report is retained in the archive.

## Native result

LibreOfficeDev `26.8.0.0.alpha0 2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`
renders the generic grey rectangle, approximately 72 by 36 points, but omits the
two textbox label lines. Both PDF text extractions contain only `X\n`, and the
retained crop visually confirms that the rectangle has no label. The markup
still contains "Embedded object" and "Preview unavailable". This observation
does not establish Word's rendering or embedded-application activation.

The original converted DOCX was rendered without modification. A second
controlled derivative unwraps `w:ins` elements in `word/document.xml`, retaining
their children, and leaves every other package member byte-for-byte unchanged.
It produces the same label suppression. This isolates the observation from
insertion visibility without accepting any change in the original document.

`receipt.json` records input, derivative, PDF, native executable and artifact
hashes; the exact changed package member; preserved payload bytes; PDF words;
rectangle geometry; and the projection recipe. The original converted DOCX
hash remained unchanged through both renders and the final evidence capture.
Each native conversion used a separate profile with macro execution and
external link/field/chart updates disabled through `run.office_convert`.

## Retained evidence

`artifacts.tar.xz` contains the independently authored binary fixture, unchanged
converted DOCX, accepted-insertion derivative, both native PDFs and extracted
texts, conversion logs, the original native report, the small inspected crop,
and the 24-case SDK report. The receipt hashes every extracted member and the
archive itself. No native profile, source document or golden was modified to
obtain the result.

This is a documented remaining visual limitation. `partialFormatting` remains
reported by conversion. A portable visible placeholder is a named followup;
neither a source preview nor a source-independent raster substitute was added
in this checkpoint.
