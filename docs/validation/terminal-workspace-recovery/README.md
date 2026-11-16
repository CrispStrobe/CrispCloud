# Automatic terminal workspace recovery

This continuation starts from `74fbdd5a9a17399237b54512877dc6700c0d76b2`
on `codex/terminal-screen-workspace` (draft PR #160).

## Initial source reconciliation

The fresh full branch/PR fetch includes **40 branch heads and 153 PR heads**.
Every advertised reference is already an actual ancestor of the starting head;
no incoming merge is needed at this cutoff. The newer shared SSH shells and
ODS numeric/date-validation changes are preserved. Exact refs and ancestry
checks are recorded in [initial-integration.json](initial-integration.json).

## Continuation scope

Implement opt-in automatic recovery of terminal tabs, split topology, active
pane, names, font sizes and sanitized SSH/tmux destinations. A separate explicit
preference may reopen local shells. Recovery does not store passwords, private
keys, output, commands, filesystem grants, broadcast authority or live route
ownership. SSH destinations require the existing connection/authentication flow.
This is workspace recovery and optional shell relaunch, not restoration of
operating-system process memory.

## Validation status

Implementation and fresh local validation are in progress. Prior acceptance
counts belong to the earlier commits and are not evidence for this continuation.
No GitHub Actions are queried, awaited or rerun. Checkpoints use `[skip ci]`.
