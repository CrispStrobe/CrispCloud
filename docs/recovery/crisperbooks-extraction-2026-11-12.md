# Crisperbooks extraction and continuation — 12 November 2026

Recovered remote baseline: `8ee4de600e595f36c66bdf01cf57d25259701335`, branch `feature/ebook-reader-editor`, draft PR #53. The workspace was reconstructed from that remote; the later read-aloud and browser Kindle conversion described in the interrupted session were not in its saved tree.

The user requested frequent remote checkpoints, completion of the reader/editor across supported formats and platforms, and extraction into the existing empty `CrispStrobe/crisperbooks` repository for CrispCloud consumption and eventual pub.dev publication.

## Implementation boundary

- Move the reusable EPUB model/editor, sandboxed renderer and Kindle conversion packages into crisperbooks, preserving upstream notices and package identities.
- Move reusable edit-session/prose/reading-data APIs behind an application-independent Flutter package. Keep CrispCloud file/account operations, provider state and cloud library integration in CrispCloud.
- Pin the consuming application's dependencies to an immutable crisperbooks commit. Maintain development/test commands and package-owned platform fixtures in the extracted repository.
- Complete browser Kindle output and foreground speech only with real runtime evidence and explicit unavailable capabilities where needed.
- Keep both feature branches and draft PRs as reviewable incremental checkpoints. Publishing to pub.dev and merging main are later release decisions.

## Recovered qualification

The native platform and Linux workflows on the recovered head have started. Enhanced Linux now reaches real WebKit startup but its JavaScript bridge returns an unsupported Promise value to native evaluation. This is being fixed without changing the rendering assertions or sandbox configuration. The workspace suite reports 924 passing tests with one FictionBook formatting failure; its formatting correction is ready.

Further results and exact saved revisions will be appended as work completes. “All platforms and all features” remains a verification target, not an established result.
