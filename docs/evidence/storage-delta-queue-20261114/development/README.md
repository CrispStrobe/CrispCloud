# Development attempts

These exploratory runs used the evolving working tree. They are retained for diagnosis and are **not** qualification evidence for a fixed source commit.

- `attempt-01`: queue integration plus prepared/core/legacy-S3 suites. Three newly added recovery cases failed because the test fixture had not initialized persistent local installation identity. The fixture was corrected before the implementation checkpoint. The formal, fixed-source cohort is recorded separately.

Raw Flutter machine output includes framework loading/hidden events; do not treat every `testDone` event as a user test.
