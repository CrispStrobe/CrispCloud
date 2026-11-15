# Independent comment ownership fix review

**No concrete blocker found** in saved Quds source `47e44e0ae35adcc406eee2a2ae2118dd2a4a082a` (tree `9b5f9f9aeeb2fc59f46f0331037118a980b864b3`). This is a static source and lifecycle-test review; runtime acceptance remains a separate owner gate.

The saved serializer is byte-identical to the previously reviewed candidate: Git blob **`4cbc5fa6bc476572253cfbd30685e6fbdece9fad`**, SHA-256 **`4bfabb807ff50edf68d6e2e1d3a32623847ef10b9dc055ab392bf5614014eeb7`**. `review.json` records exact identities for the serializer, lifecycle suite and external-reader fixture. The commit preserves the raw failing baseline in parent `7a7fd2fe776d5733ddb824315e0768d01d1cbabc`.

The change captures existing worksheet comment ownership before package writes. Serialization uses that captured ownership, so assigning a new worksheet URI no longer causes an unrelated conventional comments part to be adopted or validated as owned. The existing collision allocator and shared/foreign-part guards remain in place.

A new empty sheet facing a conventional orphan comment part now receives a separate, explicitly empty authority. That authoritative relationship persists through reopen, adding a note and clearing it, so legacy fallback cannot resurrect unrelated text. Existing owned-target validation still runs before column metrics, formula evaluation, shared strings, styles, properties or worksheet mutation.

The four additive lifecycle cases cover valid/malformed orphan parts crossed with an initially empty/explicit new note. They preserve orphan bytes and content type, require a distinct authoritative relationship, retain the original sheet's content, and verify reopened values through addition and clear. Existing shared-part, foreign-part, relocated-comment and malformed-owned-target controls are unchanged. The final saved assertions also preserve the orphan's unrelated relationship XML, require exactly one owner, validate the SpreadsheetML comment structure and require genuinely empty author/comment lists for an empty sheet. No existing assertion was removed or weakened.

The fixture producer retains three repeated-save packages and adds six orphan-collision packages (valid/malformed orphan through empty/add/clear). Its expected comment values, orphan bytes and relationship bytes are authored independently of serializer output. This gives the external-reader check concrete lifecycle and byte-preservation inputs; this review did not execute that check.

The regression-only source `55fe279284130d8691c9edcd3fe5ae68656a7037` produced four failures with stable input/HEAD records; all eight indexed baseline artifacts were verified in the initial review. No app or canonical source file, index or HEAD was modified, and no tests or new remote refresh were executed by this review.
