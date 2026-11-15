# Intermediate host qualification at f0f38636

This preserved run qualified CrispCloud source
`f0f3863604ba272149af3b00d165c41abae16521` with canonical Quds pin
`55d46a0fb5f7392dab1a604bc3c15126bd3e380d`.

All 37 host tests passed, eight strict analyzer targets were clean, both vendor
gates verified 2,391 entries, and all 1,577 measured source/dependency files
were unchanged before and after execution. The complete results and command
log hashes are in [host-validation-receipt.json](host-validation-receipt.json).

A later terminal continuation was merged at CrispCloud `6a53294a`. This run
remains valid for its recorded source; the [parent directory](../README.md)
records the qualification repeated after that integration. The original
inventories, dependency inputs and all command logs are retained unchanged.
The executed script is [run-host-validation.py](../run-host-validation.py),
whose digest is recorded in the receipt.
