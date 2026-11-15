# Final independent comments correction review

**Approved for the reviewed comments source scope.** Exact saved commit: `fd14d8a68477165e7ca3317b647f403f2308e353`; tree: `a5cb6713e63d59fc96784bdb141a8a290a80c887`. Review date: 2026-11-15 UTC. No canonical or application project file, index, ref, or remote branch was changed by this reviewer.

## Closed finding

The blocker recorded in `comments-review-25c37362.md` is corrected. Clearing a worksheet's relocated comments while preserving an unrelated fixed-name comments part now retains an authoritative empty comments part and relationship. Reopening the saved ZIP therefore continues to show no comments, while the unrelated decoy remains byte-identical.

The production delta after regression checkpoint `9d1f6755a21c5d9936fd89532a4ebdbb510e9a2d` is exactly 11 added lines and one removed line in `packages/quds_office_engine/lib/src/sheet/serial/sheet_serial.dart`. It computes whether the existing authoritative part differs from an unowned fixed-name comments part, and enters the existing comments writer when that empty authority must be preserved. Existing shared-part copy-on-write protects other owners. Ordinary clear behavior retains its existing deletion path.

The committed single-owner and shared-owner regressions exercise three actual ZIP save/reopen cycles. They assert empty imported comments, unchanged decoy bytes, a distinct active comments part with the correct content type and namespace, empty `authors`/`commentList` containers, and the shared owner's unchanged original text/author and relationship target.

## Independent exact-source reproduction

The same minimal reproduction that failed at `25c37362` was executed against a fresh immutable archive of the engine library at the saved correction. Only its reported source label was changed. Existing pinned workspace dependency resolution was reused outside the project through a private rewritten package configuration.

Result: Dart exit **0**, empty stderr.

```json
{
  "before_clear": ["authored note"],
  "after_clear_save_reopen": [],
  "authored_part_removed": false,
  "comments_relationship_removed": false,
  "unrelated_decoy_bytes_preserved": true,
  "expected_comments_after_clear": 0,
  "success": true
}
```

`comments-review-fd14d8a6/reproduction.json` records the command, time, source commit, script/config/binding hashes, stdout, stderr, and exit code. `source-binding.json` records the immutable engine archive hash and resolution configuration hashes. The snapshot's copied `packages/` tree and local package configuration are disposable execution inputs.

## Independent receipt reading

The owner's `decoy-corrected-focused-tests/stdout.jsonl` contains exactly two visible successful tests, no skipped tests, no error events, and a successful terminal done event. Both test names correspond to the committed single-owner/shared-owner decoy regressions. Its metadata records the exact saved commit and tree above, 3,060 inputs, equal before/after input digests, and stable tools/source. The reviewer read these raw records; this is not a claim to have independently rerun the owner's two-test gate.

The review and receipt hashes are saved in `comments-review-fd14d8a6/focused-receipt-review.json`.

## Schema and remaining qualification boundary

The exact empty comments shape was separately validated against the official ECMA-376 Part 4 fifth-edition Transitional `sml.xsd`: the required `authors` and `commentList` containers both permit zero children. Primary source, tool versions, hashes, and successful result remain in `comments-schema-proof/empty-comments-validation.json`.

No further concrete blocker was found in the reviewed correction. Approval covers the comments import/edit/clear fix, relationship precedence and ownership, namespace/plain-text serialization, and its specific decoy correction. It does not extend previous full-suite results to newly joined ODS/parser/application source. The parent retains ownership of those separately scoped integration gates.
