# UNIX compress writer profiles

CrispCloud's bounded `.Z` encoder is an original Dart implementation of the
UNIX compress LZW wire format. No VaultExplorer implementation, tests, assets
or dependencies were inspected or imported. GNU gzip and libarchive are used
only as independent validation tools; neither becomes an app dependency.

## Format references and encoding choices

- [OpenBSD compress(1)](https://man.openbsd.org/compress.1) documents LZW,
  the 9–16-bit dictionary range, dictionary resets, `.Z` naming and `.taz` as a
  compressed TAR alias. Its portability notes recommend a 14-bit limit for
  systems restricted to the POSIX minimum.
- The [libarchive compress reader](https://github.com/libarchive/libarchive/blob/d0bf2da07ebaa3964090ee936edea538d1602449/libarchive/archive_read_support_filter_compress.c)
  documents the wire behavior in a primary implementation: header flags,
  least-significant-bit code packing and eight-code group alignment at width
  changes and resets. This BSD-licensed reference was consulted for format
  behavior; its source is not copied into the Dart implementation.
- Existing externally generated decoder fixtures and their provenance remain
  in [UNIX_COMPRESS_REFERENCE.md](UNIX_COMPRESS_REFERENCE.md).

The new encoder emits one block-mode stream with real dictionary compression.
Fast, Normal and Maximum select 12-, 14- and 16-bit dictionary limits. It resets
a full dictionary when another phrase must be added, and writes zero alignment
padding. Its reset policy is a legal encoding choice, independent of the
adaptive compression-ratio policy of a particular `compress` executable.
Larger dictionaries do not promise a smaller output for every input.

The writer caps input and output separately at 64 MiB. Dictionary capacity is
at most 65,536 entries. It rejects unsupported dictionary settings, output
overflow and inputs above the limit before encoding. The bit packer holds at
most 23 bits at once, so its operations are exact in both the Dart VM and
JavaScript. Empty input produces the valid three-byte header-only stream.

Creation exposes **UNIX compress — one file** (`.Z`) and **TAR.Z** (`.tar.Z`).
Neither supports Store or password protection. `.taz` is an existing supported
TAR wrapper alias. Extension validation is case-insensitive and suggested new
filenames retain the conventional uppercase `Z`.

## Rewrite boundary

Eligible 9–16-bit block and nonblock inputs use the existing bounded decoder
before rewriting. Saved output uses the normal 14-bit block profile, preserving
decoded content while normalizing encoding settings and padding. UNIX compress
does not store a member filename, modification time, permission bits or other
per-file metadata; a single payload's displayed name comes from the outer name.

An editable `.Z` workspace must expose its immediate regular payload. A listing
that has recursively opened another compressed stream, archive or disk image
cannot become a single-payload rewrite. TAR.Z rewriting additionally requires
one physical UNIX compress wrapper and the existing supported TAR preservation
profile. Source ownership fields, supported timestamps, names, ordering,
directory entries and other supported TAR metadata follow that inspector. An
opaque TAR extension, link, sparse entry or another unsupported structure keeps
the whole workspace read-only. Physical wrapper checks also prevent a renamed
wrapped 7z file from losing its compression layer.

UNIX compress stores **neither a payload checksum nor a decoded length**.
Invalid codes, reserved flags, partial codes and invalid alignment are rejected,
but a valid shorter code sequence or a bit change that remains valid LZW cannot
be detected without trusted external evidence. Reading, rewriting and testing
an archive must not turn these structural checks into a checksum or completeness
claim. Creation and publication still compare the complete decoded output with
the captured source bytes.

## Independent acceptance

`test/support/emit_archive_unix_compress_profiles.dart` emits original data,
fresh `.Z` and TAR.Z output, preservation-aware repacks of an existing external
TAR.Z fixture, and a manifest of all input and output identities. Run from the
repository root with the pinned Dart SDK and resolved dependencies:

```sh
CI=true FLUTTER_SUPPRESS_ANALYTICS=true dart \
  --packages=.dart_tool/package_config.json \
  test/support/emit_archive_unix_compress_profiles.dart /path/to/output
python3 test/support/check_archive_unix_compress_profiles.py /path/to/output
```

The checker uses gzip and libarchive. This acceptance run used **GNU gzip 1.13**
and **libarchive 3.7.4**. Both independently decode every generated stream and
must reproduce the exact original bytes. A separate Python wire inspector
checks dictionary widths, resets and zero group padding. Python's standard TAR
reader verifies member names, file/directory types, exact payload hashes, modes,
owners, group names and times in all five TAR cases. The saved
`compress-writer-profile-manifest.json` records the accepted sizes and SHA-256
identities; emitted binaries can be reproduced from the tools and original
payload recipes.

All **23 cases passed**:

| Cases | Profiles | What is independently checked |
| --- | --- | --- |
| Empty and one-byte input | 12, 14, 16 bits | Header-only empty streams and partial final bytes |
| 256 distinct literal bytes | 12, 14, 16 bits | Terminal first-width transition and group boundary |
| Repeated phrases and repeated text | 12, 14, 16 bits | Real compression, dictionary references and the forward-reference case |
| 300,000 deterministic pseudorandom bytes | 12, 14, 16 bits | Every code width through the selected maximum and 75, 16 or 3 resets respectively |
| Fresh five-entry TAR | 12, 14, 16 bits | Unicode path, binary data, empty file, empty directory, modes and times |
| Unchanged external TAR repack | 14 bits | Source payloads and all inspected member metadata |
| Edited external TAR repack | 14 bits | Replaced regular payload with the original metadata retained |

The pseudorandom payload uses an LCG seeded with `0x12345678`, multiplier
`1664525`, increment `1013904223`, reduction modulo 2^32 and the high byte after
each step. Other payload recipes are explicit in
`archive_unix_compress_writer_fixtures.dart` and the emitter.

The existing reference-tool limitation for full nine-bit dictionaries does not
affect new output: creation uses 12, 14 or 16 bits. Incoming nine-bit decoding
retains its independently checked ncompress fixture and workspace rewrite test.

## Actual web execution

`verify_archive_unix_compress_profiles_portable.dart` compares all 18 codec
outputs against the exact native-accepted output hashes, then reads them in the
same JavaScript runtime. This checks the three dictionary profiles through
their width transitions and resets, beyond merely compiling the application.

```sh
CI=true FLUTTER_SUPPRESS_ANALYTICS=true dart compile js -O2 \
  test/support/verify_archive_unix_compress_profiles_portable.dart \
  -o /path/to/output/unix-compress.js
node /path/to/output/unix-compress.js
```

All **18 profiles passed** with Dart 3.13.7 compiled to JavaScript and executed
by Node. These Linux reference and web checks do not establish platform-wide
native release acceptance.
