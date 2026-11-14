# Preliminary portable NTFS acceptance

**PRE-FREEZE SMOKE ONLY — this is not final source-pin qualification.**

Saved VM and actual dart2js -O2/Node outputs each report 18 groups and 2037 checks.
Complete parsed JSON and raw stdout bytes are identical. The driver checks all
143 supported unnamed path instances, exact alternate-stream metadata, the
authentic unsupported ATTRIBUTE_LIST image, malformed controls, resource limits,
provider behavior, and derived MBR/GPT compositions including an offset above
2 TiB.

Application sources were evolving during these executions. No complete
before/after source binding was captured, and no qualification commit is
assigned. A separately recorded saved-source final qualification must supersede
these results. INDEX.json preserves commands observed in the session, saved
outputs, compiled-artifact hashes, dependency paths, compiler-log preservation
limits, and tool versions observed during packaging. No missing historical
compiler log has been fabricated.
