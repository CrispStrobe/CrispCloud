# Large writable archives and commander parity

Date: 13 November 2026. Branch: `feature/archive-parity-large-20261113`.
Baseline: current `main` plus the preserved archive sync / native TAR continuation.

## Requested outcome

Treat ZIP, 7z and TGZ as writable folders, including large members and containers
of at least 2 GiB. Compare Double Commander and Total Commander capabilities and
preserve incremental implementation checkpoints on the remote branch.

## Implementation in progress

The previous workspace collected its container and every replacement in memory:
64 MiB per member and 256 MiB per archive/aggregate. Increasing those constants
would not establish large-file support. This continuation adds native streamed
readers, writers, private file snapshots, streamed imports and publication. Its
explicit native resource budget is 8 GiB for containers and expanded contents;
buffered editors, browsers, protected and nested profiles retain separate bounds.

The first checkpoint preserves existing one-way directory synchronization,
two-container moves and streamed TAR work. Subsequent checkpoints add each part
of the large archive path. Checkpoint commits are recoverable work; they are not
release or acceptance claims. Final verification evidence belongs below once
the integrated code has been exercised.

## Comparison sources

- Double Commander archive workflow: https://doublecmd.github.io/doc/en/multiarc.html
- Double Commander bundled format plugins: https://doublecmd.github.io/doc/en/plugins.html
- Double Commander file operation commands: https://doublecmd.github.io/doc/en/help.html
- Total Commander features: https://www.ghisler.com/featurel.htm
- Total Commander current 7z capabilities: https://www.ghisler.com/mailing.htm
- Total Commander release history: https://www.ghisler.ch/wiki/index.php/List_of_changes

Both products browse archives as directories and expose writes according to the
selected engine. Current Total Commander has built-in 7z compression; older
plugin-only comparisons are obsolete. Format recognition does not establish
mutation support: many disk images and package formats are read-only. GZ is a
single stream; TGZ is the multi-file TAR hierarchy wrapped in gzip. Neither
product's format list justifies claiming every container writable or unlimited.

## Acceptance to record

Create, open, add, replace, mkdir, rename, delete, review, publish and reopen the
three required formats; verify hashes and supported metadata independently.
Exercise large logical members, real archive offsets, cancellation, changed
sources, corrupted output, exact publication and recovery. Record environment
and physical disk constraints explicitly. Keep remote/browser publication,
large encrypted/solid profiles and split volumes accurately distinguished.
