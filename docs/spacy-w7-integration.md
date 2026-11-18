# Local MacBook integration — 18 November 2026

Build 32 imports Quds `ca42a7fa3947d0b59b9b2d3e14e807116327d714`: current upstream main plus the reconciled native spelling, Zotero workspace, document review/comparison, and spaCy distribution/NER-adapter work. All managed engine/editor/spaCy sources are checked by the guarded inventory; existing host report customizations and the independently pinned legacy parser are retained.

The native ARM64 component is built from CrispEmbed `28d8ce0eb` (including merged PRs #238, #239 and #240), with static PCRE2 and F32 model weights. The signed component and the authenticated five-file model bundle travel inside the app. Runtime analysis performs no download and uses no Python, daemon or pipe. NER weights are not included; NER remains optional.

Word's Review ribbon exposes German analysis, working Spell check, Review changes and Compare documents. Analysis runs only on an explicit action and never changes document text. Comparison uses separate documents and exports a report through the existing copy exporter. Ordinary typing and persisted optional grammar defaults remain unchanged. Mac grammar qualification is not inherited from the historical Linux library.

The historical footer regression is repaired in the canonical DOCX builder: a PAGE packet has begin, instruction, separator, formatted result and end. Existing field-preservation and independent note numbering checks pass. Mac pixel references are separated from retained Linux/legacy references, with exact comparisons and repeated save/reopen checks. The latest incoming Zotero branch supplies its targeted narrow-window repairs.

Accepted local checks: 1,171 engine tests, 146 editor tests, 86 spaCy package controls, four native CTests, nine vendor-sync controls, 47 initial host checks and 13 final focused host checks. Host cohorts overlap. Incoming source reconciliations after the canonical execution change changelogs and test host selection only, not runtime libraries. Earlier failures remain separate evidence; the accepted counts do not include interrupted attempts or snapshot generation. These checks do not establish general grammar accuracy or Linux/device qualification.

The build uses the registered Mac development identity and retains the sandbox and library validation. Final build/signature/startup observations are recorded separately after execution. No store upload or release is part of this local preview.
