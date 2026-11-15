# Independent review of Quds worksheet comments correction

Reviewed immutable source `25c373626368c4a800dbaff2024c7972ba8a6e50` against `6e4c3b16b4310f2c21b6d8b5e412af9850eb17ea`. Review date: 2026-11-15 UTC. This review did not modify the canonical Quds repository, CrispCloud, or any remote branch.

## Verdict

One concrete blocker remains in the reviewed commit: clearing linked comments can reactivate unrelated legacy fallback comments. The owner has accepted the finding and is adding a targeted correction. Do not treat this note as approval of the reviewed commit for mirroring.

## Confirmed regression: clearing linked comments resurrects a fixed-name decoy

Production location: `packages/quds_office_engine/lib/src/sheet/serial/sheet_serial.dart`, `_writeSheetExtras` empty-comments branch (lines 985–989 at the reviewed commit), interacting with `_sheetCommentsPart` fallback (lines 60–68).

Minimal package:

- Worksheet `/xl/worksheets/sheet1.xml`, sheet ID 1, with a valid internal comments relationship to `/xl/annotations/note42.xml`.
- That linked comments part contains `authored note` at A1.
- The package also retains a valid, unreferenced comments part `/xl/comments1.xml` containing `unrelated decoy` at A1.

The relationship correctly wins on import. After the imported worksheet's comments list is cleared, writing and reopening the ZIP removes the linked relationship and its owned part but retains the unrelated decoy. Without an authoritative relationship on the next import, the legacy filename fallback reads the decoy as active comments.

An isolated runtime reproduction against an immutable archive of the exact reviewed engine library produced:

```json
{
  "before_clear": ["authored note"],
  "after_clear_save_reopen": ["unrelated decoy"],
  "authored_part_removed": true,
  "comments_relationship_removed": true,
  "unrelated_decoy_bytes_preserved": true,
  "expected_comments_after_clear": 0,
  "success": false
}
```

Evidence directory: `comments-review-25c37362/`. Preserve `clear_decoy.dart`, `source-binding.json`, `reproduction.json`, `clear-decoy.stdout.jsonl`, and `clear-decoy.stderr.log`. The copied `packages/` library and rewritten local `package_config.json` are disposable execution inputs, not new repository source or independent full-suite qualification.

Recommended correction: retain an authoritative, valid empty comments part/relationship when deletion would expose a different unowned fixed-name fallback comments part. Keep the unrelated decoy bytes unchanged. Reuse the existing copy-on-write path if the authoritative part has another owner. Tests should combine relocation, a decoy, clearing, and three serialized reopen cycles, with a second case in which another worksheet still owns the original authoritative part.

## Review of the proposed narrow correction

The owner's proposed predicate requires an existing comments part, a different fixed-name part with the comments content type, and no other internal owner of that fixed-name part. Entering the existing namespace-correct writer for either nonempty comments or this condition produces an empty authoritative part without changing legacy fallback rules or unrelated bytes. The predicate covers the confirmed single-owner and shared-owner combinations. No additional concrete valid-package defect was found in this predicate. Approval of the actual corrected source and evidence remains pending.

## Source areas reviewed without another concrete blocker

- The root receives the SpreadsheetML namespace, inherited by its children; each plain comment uses `text/t`, and `xml:space="preserve"` retains the supplied text. Author IDs use first-seen deduplicated table order.
- The worksheet relationship determines the authoritative part, including relocated comments and nested worksheet paths; URI relativization is performed from the actual worksheet location.
- The helper rejects multiple comments links, external targets, empty targets, scheme/authority/query/fragment targets, missing/wrong-content-type parts, and wrong root names/namespaces. The compatibility fallback is bounded to the legacy filename and a comments part without another internal owner.
- Existing-source ownership checks occur before package writes. The new regression inventory checks refusal without changing serialized package bytes for its concrete malformed-target cases.
- The edit path copies a shared comments part before changing one worksheet's contents. Clearing removes the current worksheet relationship and only deletes the actual part once no internal reference remains.
- The ordinary clear tests and relation-precedence test are individually sound; they did not originally combine decoy precedence with clearing, which caused the blocker above to escape the initial passing inventory.

This is a scoped code review and isolated reproduction. It does not claim full XML validation of arbitrary malformed inputs, coverage of all OPC inconsistencies, native Excel rendering, or whole-workbook schema conformance. The owner separately reports the saved gate inventory; those results are not relabeled as executions by this reviewer.

## Primary schema proof for an empty authoritative part

The official [ECMA-376 Part 4, fifth edition ZIP](https://ecma-international.org/wp-content/uploads/ECMA-376-4_5th_edition_december_2016.zip), linked from the [ECMA-376 publication page](https://ecma-international.org/publications-and-standards/standards/ecma-376/), supplies the Transitional `sml.xsd` used for verification.

`CT_Comments` requires exactly one `authors` element followed by exactly one `commentList`. `CT_Authors` allows zero or more `author` children, and `CT_CommentList` allows zero or more `comment` children. Thus an empty `authors` table does not need a fabricated author. Using lxml 6.1.1 / libxml2 2.14.6, validation of the exact namespaced `<comments><authors/><commentList/></comments>` document against the complete downloaded `sml.xsd` succeeded with no errors.

The retrieval URL, source and XML SHA-256 hashes, tool versions, validation scope, and result are in `comments-schema-proof/empty-comments-validation.json`; cardinality fragments are in `comments-schema-proof/comments-types-fragment.xsd.txt`. The source archive hash is in `comments-schema-proof/outer-zip-metadata.json`.
