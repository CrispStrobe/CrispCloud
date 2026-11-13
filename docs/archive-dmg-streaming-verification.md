# DMG streaming verification above 2 GiB

Date: 13 November 2026. Tested production revision:
`f1a03e807b1261361a17f66a37fa94858481e1e7`.

The native DMG codecs and production file spools created and rewrote actual
outer containers larger than 2 GiB, reopened both through the complete canonical
HFSX data-profile inspection, and verified the complete large member. The
standalone Dart process exited successfully and cleaned all temporary storage.
This is codec and spool evidence. Hosted application publication is tracked
separately in [runtime verification](archive-containers-runtime-verification.md).

## Retained evidence

- [Complete machine-readable receipt](evidence/archive-dmg-streaming-verification.json).
- [Exact standalone reproducer](evidence/verify_dmg_2g.dart).
- [Supported ISO/RAR/DMG profiles](archive-iso-rar-dmg.md).

The probe ran on Linux x64 with Dart 3.13.7 from
`2026-11-13T05:25:46.418789Z` to `2026-11-13T05:28:53.696193Z`.
Elapsed time was **187,275 ms**. During execution the branch advanced to
`6dc3fad40560b8c75e961262724ec16f78504bb6`, which changed only documentation;
the production code stayed identical to the tested revision.

## Fixture and measured results

The member is **2,147,487,745 bytes** (`2 GiB + 4,097`). Its deterministic
256 KiB block uses the same LCG seed and high-byte output as the hosted native
workflow fixture, with explicit first/last sentinel bytes. The block is larger
than zlib's window and sufficiently incompressible to keep the rewritten outer
image above 2 GiB. This avoids mistaking a huge logical zero-filled filesystem
with a tiny UDIF encoding for a large packed container.

The first image uses Store/raw data runs. The rewrite uses the normal zlib/raw
selection and renames the large member, removes another file, adds a new file
and retains an empty folder. Both outputs use real file-backed spools.

| Measurement | Result |
| --- | ---: |
| Large member | 2,147,487,745 bytes |
| Original outer DMG | **2,148,753,423 bytes** |
| Rewritten outer DMG | **2,147,601,376 bytes** |
| Original creation | 42,864 ms |
| Original canonical profile and CRC verification | 2,877 ms |
| Rewrite with normal zlib/raw selection | 101,745 ms |
| Candidate canonical profile and CRC verification | 2,546 ms |
| Complete reopened candidate payload SHA-256 | 37,068 ms |
| Cleanup | 132 ms |

No sparse export was used. The byte counts above are actual encoded container
lengths, including UDIF framing. Filesystem allocated-block counts were not
measured; they are distinct from encoded lengths on compressed or deduplicating
storage.

## Content and metadata checks

All three complete payload hashes matched: the generated input, the original
DMG member read while rewriting, and the reopened candidate member:

```text
5c476ddb577e294d969696ffe5592f15743448007199015e067c59aa98bc1843
```

Both opens passed canonical HFSX inspection and both UDIF CRC layers. The
preservation verifier compared retained volume/root/member metadata after
rewriting. A deliberately different creation-only volume name supplied to the
writer did not replace the source label.

The candidate contains exactly `added.txt`, `empty-folder` and `renamed.bin`.
The removed member and original large-member name are absent. The added file's
content, permission mode and modification time also match the plan.

## Bounded I/O and lifetime checks

- Generated input chunks and exposed member chunks were at most **256 KiB**.
- UDIF writer sink chunks and positional input reads were at most **1 MiB**.
- Both source handles closed exactly once and rejected later reads, including
  after repeated archive-close calls.
- The dedicated temporary directory was empty after cleanup.
- Process RSS started at 323,731,456 bytes and reached a sampled peak of
  432,664,576 bytes: **108,933,120 bytes of observed growth**. Sampling occurred
  every 50 ms. This includes the Dart runtime/JIT and is not a memory ceiling.

The explicit resource bound was 8 GiB. This fixture does not qualify the entire
8 GiB ceiling. It also does not establish Flutter UI or app publication behavior,
macOS mounting, all supported operating systems, arbitrary filesystem rewrites,
application-bundle preservation or signed-image verification. The completed
normal app suite and separately enabled hosted large cases have their own
receipts in the runtime record.

## Reproduction

Use a resolved CrispCloud checkout and its pinned Dart SDK. The probe needs a
dedicated empty temporary directory on a volume with at least 6 GiB free. Keep
the JSON output outside that directory so the cleanup assertion remains exact.
The revision argument records the checkout being tested; the retained receipt
above was checked against the frozen production revision before and after its
execution.

```bash
mkdir -p build/dmg-2g-temp
TMPDIR="$PWD/build/dmg-2g-temp" dart --packages=.dart_tool/package_config.json \
  docs/evidence/verify_dmg_2g.dart \
  --output="$PWD/build/dmg-2g-result.json" \
  --revision="$(git rev-parse HEAD)"
```

The reproducer has a 14-minute cancellation deadline and writes its receipt
after cleanup. Its SHA-256 is
`82326eb8c94fb41b29a7e59bb597c6d5912b8b241b70d17c56380a1e7a64833e`.
The retained JSON receipt's SHA-256 is
`8487f90eccd503ef26c6a7f6f32f43d33fb32b5c634f9876b53e3f52c88394c1`.
