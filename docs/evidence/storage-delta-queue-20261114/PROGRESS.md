# Verified S3 block copy through the reviewed queue

## Starting point

Continuation of PR #107 at `781458d765100ae3556906ff8ca923e70c956afa`, following the validated native delta core. The fresh source audit at **2026-11-14 22:15:39 Europe/Berlin** found no incoming primary source work: all three current branch heads and all 97 PR heads are ancestors of the integration branch. The audit includes 23 tag objects and preserves the previously documented alternate MadEdit2 archive disposition. See [initial-audit/receipt.json](initial-audit/receipt.json) and its hashed supporting files.

GitHub had 32 queued checks and no completed check results at that cutoff. Pending CI is not a passing qualification.

## Increment under implementation

Add an explicitly reviewed **Reuse verified S3 blocks** copy method to the existing Copy dialog, queue and durable journal:

- Native direct S3 to the captured native local backend, regular files only.
- A cache miss performs one complete conditional transfer while building a map. A trusted map from this adapter and remote revision can subsequently reconstruct a private candidate from verified local blocks and exact conditional remote ranges.
- The complete logical stream retains ordinary progress, per-job rate limiting and SHA-256 evidence. Global network accounting charges actual HTTP response bytes.
- The durable committing checkpoint and any pause/cancellation gate finish before the source, baseline and candidate receive their final publication checks.
- Existing staging, destination reservations, conflict decisions and metadata handling remain the owners of publication. No external-writer compare-and-swap is claimed.
- Recovery requires review and uses ordinary streaming; cached maps and live execution authority are never restored from journal JSON. No append, partial resume, move or preallocation combination is admitted for the new method.
- The global experimental preference remains inactive. This increment does not enable background/automatic delta selection, remote delta upload or browser/mobile acceptance.

This checkpoint preserves the audit and plan. Implementation and qualification are in progress; no new passing runtime evidence is claimed yet.

## Implementation checkpoint

The explicit method, scoped core/provider contents, ordinary queue/journal integration, UI eligibility, recovery downgrade and focused regressions are implemented. Independent source reviews addressed final captured-backend authority after provider proof, missing-ETag admission before source bytes, and cancellation/transport exception ordering.

A first native development cohort exercised the new queue integration and existing delta core/provider suites. The core/provider regressions passed. Three new recovery cases revealed that the fixture had not initialized the durable local installation identity; that setup was corrected so the tests exercise actual persistent recovery rather than a session-only destination. Combined qualification is still pending; this is a preservation checkpoint, not a passing release claim.

## Reconciled source cutoff before qualification

The final remote audit found and integrated main `e58da70149182301efbbe85807edb6298ff37ff1` (the four-commit catalogue self-exclusion / version 1.3.3 continuation) and Office recovery `764cb5184c93ac89dc57638fc0e88d42aa82154b` (worksheet-navigation scope documentation). All five new primary commits are retained as ancestors. No merge conflict or managed Office source change was required. The qualified canonical pin stays `a379ecc455890032906098b6cf58e17504581ed0`.

The [final audit](final-audit/receipt.json) records 3 current branches, 97 PR heads and 24 tag objects, including v1.3.3. All source work outstanding at that finite cutoff is incorporated; the archived alternate MadEdit2 API remains preserved under its documented disposition. PR checks were queued, without completed CI results.

The next fixed-source cohort covers 52 native Flutter suites, including the explicit queue path, provider/core fault cases, reviewed copy/recovery UI, ordinary transfers, bandwidth and the newly merged catalogue surfaces. Catalogue Rust tests will run separately. Dependencies were resolved offline using the committed manifest/lock and its existing declared overrides; no task-specific override was introduced. Development receipts remain separate from qualification.
