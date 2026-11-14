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
