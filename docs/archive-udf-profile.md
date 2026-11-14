# UDF reading profile

CrispCloud's original MIT Dart reader opens a bounded physical-partition subset
of UDF for listing, preview and extraction. It uses the existing owned
`koni.ByteSource`, safe-member policy, extraction limits and positional streaming.
No native runtime, mount operation or new Pub dependency is required.

## Supported structures

- UDF domain revisions **1.02, 1.50, 2.00 and 2.01**, with 2048-byte sectors and
  logical blocks. A valid BEA01 / NSR02 or NSR03 / TEA01 recognition sequence is
  required. ISO descriptors may precede it in a bridge image.
- The anchor at sector 256, its main volume descriptor sequence, one primary
  volume, one logical volume, and up to 32 nonoverlapping physical partitions
  referenced through Type 1 maps on the same volume.
- A bounded logical-volume integrity sequence. Open volumes are identified in
  the listing notice; no repair, journal replay or consistency guarantee follows
  from successful listing.
- One file set, optionally followed by its terminating descriptor. Ordinary
  file entries (FE) and UDF 2.00/2.01 extended file entries (EFE), ICB strategy 4.
- Regular files and directories with embedded contents, short allocation
  descriptors, or long allocation descriptors. Ordered multiple extents may
  be physically separated, reversed or repeated. A final allocation's sub-block
  padding is excluded from logical contents. Allocated but unrecorded and
  unallocated regular-file extents produce zero bytes.
- Bounded allocation-extent descriptor chains. Both CRC forms allowed by UDF
  section 2.3.11 (the eight fixed bytes or the complete allocation list) are
  accepted. Chain cycles are rejected.
- OSTA compressed Unicode names with compression IDs 8 and 16, excluding
  surrogate code units. Safe Unicode names, empty regular files, nested and
  empty directories, representable modification times and POSIX permission
  bits are exposed. Unsafe path components and duplicate resulting paths fail.
- Symbolic links and other recognized special entries are listed as special
  entries. The existing archive policy prevents reading or extracting them as
  regular files. Deleted directory entries are omitted.

Descriptor tag checksums, reserved tag bytes, versions, expected locations and
required CRC coverage are checked before metadata drives traversal. Allocation
ranges must remain within their selected physical partition and the input.
UDF has no general checksum for file contents: valid metadata CRCs do not
establish content integrity or authenticity.

## Deliberate boundaries

Type 2 maps (including virtual/VAT, sparable and metadata partitions), revisions
2.50/2.60, multiple volumes or logical volumes, indirect/terminal ICBs, record
formats, transformed data, extended allocation descriptors, named/system
streams, multiple/chained file sets, chained volume/integrity sequences and
sparse directories are explicitly unsupported. External or embedded extended
attribute contents are not restored.

The reader uses the primary anchor and main descriptor sequence. It does not
silently select a reserve sequence or backup anchor after damage. This profile
is a filesystem reader, not UDF reconstruction, repair or multisession recovery.

UDF and ISO/UDF bridge images remain read-only. Recognition or successful
reading does not grant ISO writer eligibility. An existing ISO writer must
continue to reject UDF-bearing layouts.

## Resource limits

| Resource | Default / fixed boundary |
| --- | --- |
| Recognition headers | At most 128, seven bytes each, from sector 16; stop on unrelated descriptor |
| Physical source read | At most 64 KiB per request |
| Main, integrity or file-set sequence extent | At most 1 MiB each |
| Partition maps | 32 |
| Metadata bytes read | 64 MiB, configurable downward or upward by a trusted caller |
| Directory contents | 32 MiB total, configurable |
| Listed entries | 100,000, configurable |
| Directory depth | 64, configurable |
| Allocation descriptors | 100,000 total, configurable; 4,096 data extents per file |
| Allocation continuation depth | 256 |
| One ICB, FID or allocation-continuation extent | 2048 bytes |
| Retained filename code units | 16 MiB measured as two bytes per code unit |
| Full member path | 4,096 code units |
| Logical file size | 8 GiB; each operation retains its smaller caller allowance |
| Buffered file reads | At most 64 MiB, including callers with a larger streaming allowance |

Unsigned 64-bit information lengths are checked as separate 32-bit halves
before conversion into a bounded exact Dart integer. Physical positions use
partition-relative 32-bit block numbers and exact multiplication, including
compiled JavaScript. Stream cancellation stops subsequent extent reads; closing
the returned archive closes the source, and opening failures also close it.
The recognition probe is non-owning and never closes its source.

## Source and qualification

The implementation is original code written from the structure definitions and
requirements in the primary specifications. No DiscUtils, kernel, recovery-tool
or filesystem-library implementation was copied or bundled. DiscUtils was
considered as an MIT helper/library option; a Dart implementation fits the
existing browser and native positional-source boundary.

- [ECMA-167, third edition, June 1997](https://ecma-international.org/wp-content/uploads/ECMA-167_3rd_edition_june_1997.pdf),
  parts 2–4: recognition, volume descriptors, partition maps, file sets, FIDs,
  ICBs, FE/EFE and allocation descriptors.
- [Official UDF specification republication, ECMA TR/112](https://ecma-international.org/publications-and-standards/technical-reports/ecma-tr-112/),
  parts 4–7: UDF 2.01, 2.00, 1.50 and 1.02. In particular, UDF 2.01 sections
  2.1–2.3 define CS0 names, domain revisions, metadata CRC coverage, physical
  partition constraints and allocation-continuation CRC exceptions.

The first independent fixture set was mastered with an external UDF 1.02 image
writer and extracted independently with 7-Zip. It includes a bridge image, a
UDF-only derivative and a deliberately nonascending fragmented-file derivative.
The committed fixture generator, fixture manifest and portable acceptance driver
record exact image/payload identities and derivation. Synthetic fixtures qualify
additional admitted structures; see the current turn's evidence for completed
runs and explicit test limits. External verification tools are not bundled with
the application.
