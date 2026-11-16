# Pre-integration local acceptance

At source `ea560e8c20c897f98809664e54961509e570b9cb`, the complete terminal
cohort passed **980 tests with two platform skips across 81 files**. The real
OpenSSH cohort passed **22 tests with three explicit environment skips across
four files**. Analysis and formatting passed for **153 Dart files**. All four
phases recorded identical 5,544-file source inventories without changes.

During these runs, a fresh fetch found main `c7463402` and PRs #162/#163 with
new ODS numeric/date validation. These passing results are preserved here before
that integration. The final acceptance record at the parent directory will use
the combined source; these overlapping runs are not added to its test total.

Logs and source inventories are gzip-compressed with deterministic metadata.
The phase JSON receipts retain their original commands, timestamps and source
identity. No GitHub Actions were queried or awaited.
