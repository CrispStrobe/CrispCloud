# External NTFS fixture evidence

This package preserves external producer/oracle results and exact corpus
reproduction. It does not establish final application-source qualification,
Windows chkdsk acceptance, or complete filesystem consistency.

Three supported NTFS 3.1 images contain 143 regular unnamed path instances.
One valid externally mastered image uses a directory ATTRIBUTE_LIST that the
bounded reader intentionally refuses; that image contributes 61 independently
extracted paths. The external totals are 204 unnamed paths and eight named DATA
streams. The supported subset contains 143 unnamed paths and six named streams.

INDEX.json maps original paths and hashes to stored files, preserves the
54-input reproduction binding, and identifies omitted reproducible images and
payloads. Both complete command receipts use deterministic gzip. The compressed
external-channel-index maps every stdout/stderr channel to its exact text entry
in external-text-logs.tar.gz, an explicit empty stream, or an omitted payload
with its manifest/hash reference. Tar entries have safe relative paths and fixed
metadata. Some deterministic text channels were not separately saved originally;
their recovery method is explicit and every recovered byte sequence must match
the exact original length and SHA256 in the contemporaneous command receipt.

## Security-descriptor inspection limitation

The ntfsinfo inspection of inode 9 ($Secure) exits zero but emits:

    Corrupt attribute 0x80 in inode 9
    Failed to read $SDS attribute: Value too large for defined data type

Its security-descriptor content inspection is incomplete. A fresh untouched
mkntfs control reproduces this diagnostic before the original population helper
runs. Direct ntfscat extraction of $SDS succeeds and produces identical
262396-byte output in the fresh and populated images. Both remain unchanged by
those read-only inspections. This establishes that the diagnostic predates
fixture population; it does not establish security-descriptor semantic validity.
The diagnostic-control receipt and all text outputs are preserved separately.

The independently recorded ntfsfix -n and ntfsresize --info --no-action results,
all user-payload and named-stream hashes, and source invariance remain separate
claims with their exact outputs preserved.
