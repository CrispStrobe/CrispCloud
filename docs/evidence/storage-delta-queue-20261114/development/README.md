# Development attempts

These exploratory runs used the evolving working tree. They are retained for diagnosis and are **not** qualification evidence for a fixed source commit.

- `attempt-01`: queue integration plus prepared/core/legacy-S3 suites. Three newly added recovery cases failed because the test fixture had not initialized persistent local installation identity. The fixture was corrected before the implementation checkpoint. The formal, fixed-source cohort is recorded separately.

Raw Flutter machine output includes framework loading/hidden events; do not treat every `testDone` event as a user test.

- `attempt-02`: 138 visible cases passed and one existing Ask-background widget case failed only its pending-timer invariant. The widget fixture now unmounts and disposes its externally owned provider container within the test. All functional assertions are unchanged. New S3/provider, queue/hash, and recovery cases passed. This run also used the evolving tree and is not the formal qualification.
