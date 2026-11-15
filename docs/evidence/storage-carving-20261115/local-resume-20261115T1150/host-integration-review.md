# Host integration for parser recovery

Prepared against the saved app source; no app checkout mutation at preparation.
The canonical parser integration is owned by qualification_setup. Runtime
verification remains pending until root applies the new pin and authorizes
the local targeted gate.

## Findings and resulting behavior

The new parser result has `recoveredTextOnly`, but the host previously ignored
it. A successful fallback therefore carried the label "Built-in structured
conversion" and `LegacyWordCopy.isTextOnly == false`. That misclassified the
output and caused the subsequent conversion action to follow its structured
copy workflow. The overlay carries the actual result flag into the copy, its
review UI, its saved retry and the later editor handoff.

The existing source-inspection function requires a valid compound directory
and Word97 `wIdent=0xa5ec`; it cannot inventory a Word6/95 document with
`wIdent=0xa5dc` or a destroyed directory. The overlay preserves that strict
inspection. On `invalidInput` only, initialization asks the bounded canonical
converter whether text-only DOCX recovery succeeds. An accepted recovery has
no source inventory and offers only the explicit built-in text choice. It
never invents absent source features, offers DOCM or launches an installed
converter without a source inventory. Encrypted/oversized inspection failures
remain rejected, and rejected recovery never enables a save.

Recovered output is still validated as a real bounded OPC package. Its report
marks `sourceInspected=false` when source evidence is unavailable; output
counts are separate from preservation. Recovery is always shown with a
localized text-only label, a specific recovery explanation, the complete
existing omission notice, and explicit acknowledgement before saving.
Automatic names use `(text).docx`; deliberate names remain the user's choice.
The saved copy stays separate and the original source bytes remain unchanged.
The bulk document conversion service also emits an explicit text-only notice.

## Concrete regression coverage

- Generated Word6/95 and damaged-directory CFBF inputs reach the reviewed DOCX
  text route, while the structured/DOCM choice is unavailable.
- A valid CFBF with unsupported counted FIB structure passes the original
  source inspection, then falls back and is correctly reclassified. A forced
  filename collision proves retry preserves the reviewed bytes, report and
  recovery identity while allowing a new filename.
- Encrypted Word6 and non-Word PDF input never enable the conversion button
  or save a copy.
- All three supported fixtures pass through the bulk document conversion
  service with an explicit loss notice and readable recovered text.
- Unknown source inventory still requires valid OPC output; malformed output
  is rejected instead of being accepted merely because source evidence is
  unavailable.
- Existing localization assertions now include all three recovery labels in
  every supported language.

The prepared six-suite focused run is separate from the final app cohort; its
counts are not added to the final acceptance totals. Existing copy-target,
installed converter, F3 preview/projection/routing and structured conversion
suites are included in the 63-suite app manifest for the changed parser/host
boundary. The canonical parser agent separately verifies its new input bounds,
Word6 encoding handling and annotation rollback behavior.
