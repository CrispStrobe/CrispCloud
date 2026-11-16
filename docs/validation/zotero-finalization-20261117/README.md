# Zotero finalization — 17 November 2026

The final host implementation is saved at `342b744a3cb66e3ee9387733ebcf8613cdb23a33`,
pinned to canonical Quds `5b05664357eead5ddc86922bab248224dbd4da6d`.

**Fresh host qualification completed: 41 actual-host tests and 28 Python
regressions passed.** All ten commands passed, including strict analysis and
formatting on 34 targets, source/tracked vendor guards on 2,521 managed files,
and unchanged source/dependency fingerprints with analyzer restoration.

See [terminal receipt](host-receipt.json), [archive identity](host-publication.json),
[complete raw evidence and reproduction scripts](host-evidence.tar.gz), and
[the frozen incoming audit](incoming-audit.json). The 274 incoming refs resolve
to 214 ancestors plus 60 exact whole-tree aliases; none is outstanding.

All 664 canonical-managed content blobs match their source; the 1,857-file
parser tree, 14 unmanaged content differences, six host-only files and eight
inherited executable modes are preserved. The stricter canonical-mode
diagnostic retains those eight inherited differences.

The production bundle now carries the six original notices, including the
American Kuiken permission and British MIT hyphenation notices. No whitelist
was widened. Existing notice and sync-boundary tests were extended.

Canonical combined-source qualification is running separately; no historical
results are added to the fresh counts above. The previous completed recovery
remains at [its original report](../zotero-recovery-20261116/README.md).

No GitHub Actions, workflow, job, status, artifact, wait or rerun API was used.
This focused qualification does not assert a full application build or new
live Zotero, Word/LibreOffice, picker or keychain acceptance.
