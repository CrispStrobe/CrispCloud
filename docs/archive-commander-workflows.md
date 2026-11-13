# Commander archive workflows

This continuation adds practical archive workflows to the existing format,
editing and publication support. It implements bounded parts of the
[Total Commander / Double Commander acceptance matrix](archive-commander-parity.md);
it does not establish full application or plugin parity.

Source branch: `feature/archive-commander-parity-20261113`.
Review: [PR #97](https://github.com/CrispStrobe/CrispCloud/pull/97).

## Background creation and separate archives

On native desktop, select local files or folders and choose **Create archive…**.
The usual foreground creation remains available. **Queue in background** saves the
captured local selection, format, options and exact destination before a worker
starts. **Archive jobs** in Tools or the command palette opens the same queue.
Closing either dialog leaves the application-owned queue running.

For two or more selected items, **One archive per selected item** previews a
separate output for each item. The complete source name is retained in the
output name: `report.txt.zip` and `report.csv.zip` stay distinct. The selected
format must support each individual input. All requested jobs are admitted in
one durable update after checking every output name; a collision does not admit
a partial batch. Each admitted archive then has its own progress and result.
Source files are retained.

Jobs run serially in a native isolate. The queue provides pending-job ordering,
pause/resume, cancellation, queue pause and terminal results. It retains the
necessary local access scopes until the worker has actually stopped. One native
lease protects queue ownership across application windows; closing a controller
also drains an in-flight journal save before relinquishing that lease.

After an application restart, unfinished jobs are **Interrupted**. Review their
captured source paths and output, then choose **Restart from source**. This
rebuilds and verifies an archive from the selected sources; it does not resume
from an arbitrary compressed byte offset. Protected jobs require their password
again. Passwords are held only in memory, never in the ordinary job journal.

Before publishing an output, the worker saves an acknowledged receipt containing
the exact output path, length, entry count and SHA-256. An output whose completion
acknowledgement was lost can be checked with **Verify saved output**. Only an
exact size/hash match is accepted. A mismatch remains visible and is not
overwritten or automatically adopted. A cancellation arriving after successful
publication cannot turn that publication into a reported rollback.

The queue retains at most 128 records in a bounded 4 MiB journal. Each creation
request retains the existing format and source limits; background execution
does not increase encrypted, nested or codec budgets. See
[creation](archive-creation.md) for the 35 built-in choices and their limits.
Installed external packers use the separate foreground workflow below.

## Test selected archives

Select one or more archive files, then choose **Test selected archives** from
Tools, the context menu or the command palette. The dialog tests a captured
selection sequentially and retains a copyable report for each input. The action
also works through supported remote/browser read backends; it does not publish
to those backends.

The report distinguishes checked files, issues, skipped inputs and unchecked
work. Regular member contents are read, available format integrity information
is checked and SHA-256 values are recorded. Invalid archives do not hide the
results of later independent inputs. Password cancellation, three failed
password attempts, unsupported members, checksumless formats and exhausted
budgets are explicit outcomes. **Cancel** preserves the partial report.

A private captured input is retained across password retries. Numbered 7z sets
additionally compare the fingerprint of every captured part before another
attempt, including an attempt that failed while reading encrypted headers.
Changing an archive while a password prompt is open requires a fresh operation.

Native eligible readers can stream within their existing 8 GiB limits. The
selected archives are processed one at a time. Buffered readers and browser
snapshots keep their smaller limits; a streamable input does not make every
compression method streamable. A testing batch accepts at most 5,000 selected inputs and
retains at most 200,000 report members and 16 MiB of member-path text. This is
integrity/readability checking, not archive repair or publisher authentication.

## Preview and extract a batch

On native platforms, select archives and choose **Extract selected archives**
from Tools, the context menu or the command palette. The initial destination is
captured from the other pane's verified local directory, the local source parent,
or the local fallback directory. Review or change that path before **Preview**.
Navigation cannot redirect a prepared operation.

Choose a member mask, matching by filename or full member path, case sensitivity,
and a folder layout. Masks support `*`, `?`, `;` alternatives and `|` exclusions,
for example `*.jpg;*.png|thumb*`. The default is all entries, filename matching,
case-insensitive, with original member paths preserved.

| Layout | Destination behavior |
| --- | --- |
| One folder per archive | Removes the recognized compound suffix to name the archive's destination folder |
| Shared folder | Places selected paths under the one reviewed destination; directory merges are allowed |
| Smart folders | Retains one selected top-level file/folder directly; otherwise creates a folder named for the archive |

**Flatten files** discards member directories and omits empty folders. In smart
mode it always adds the archive folder. Duplicate flattened filenames, multiple
archives claiming the same separate folder, file/directory conflicts, unsafe
paths and collisions with existing files are refused. There is no implicit
replace or keep-both policy in this first batch workflow.

Preview captures private immutable archive snapshots and builds the complete
combined output namespace. It then validates every destination without creating
output files. The list includes the exact path of every selected member. All
sources are captured before extraction begins; cancelled/declined passwords,
no matching members and other skips remain visible.

**Extract** rechecks the complete destination plan, then uses verified exclusive
publication for each file. A late collision, access change or damaged member
stops the batch. Already completed files remain in place and are listed in the
copyable report; later work stays explicitly unprocessed. Cancellation does not
claim that those completed files were rolled back. Source archives and volume
parts are protected from output writes and are never deleted.

A batch accepts at most 128 archives, 200,000 output paths and 16 MiB of path
text. Retained input snapshots and selected expanded output each have an 8 GiB
aggregate native budget; every underlying reader retains its smaller method,
member, metadata and protection limits. Prepared snapshots are closed on
completion, cancellation, failure or dialog closure. A prepared preview is not
persisted across application restart. Browser destinations and destructive
extract-and-delete remain outside this workflow.

## Installed packers and advanced 7z options

From **Create archive…**, open **Use installed packer…** on native desktop. Configure
the absolute path of a locally installed 7-Zip or RAR executable and run its
check. CrispCloud records the exact executable identity and verifies generated
probe archives with its independent reader. An executable filename or a
successful version command alone does not enable creation.

| Installed engine | Enabled new outputs | Compression | Protection |
| --- | --- | --- | --- |
| 7-Zip | ZIP and 7z | Store, Normal, Maximum | Unencrypted |
| RAR | RAR5 | Store, Normal, Maximum | Unencrypted, nonsolid |

These are separate verified outputs. The adapter does not enable arbitrary
external-tool extraction, existing-archive modification, SFX creation or volume
creation. Existing compressed RAR containers retain their read-only policy.
The application bundles no external packer and does not download one at runtime.
Users supply an appropriately licensed installed tool.

For 7z output, the checked profile includes:

| Control | Available values |
| --- | --- |
| LZMA2 dictionary | 1, 4 or 16 MiB |
| Threads | 1, 2 or 4 |
| Solid block | Off, 16 or 32 MiB |

Defaults are 16 MiB, two threads and solid mode off. Changing the profile
disables creation until that exact combination passes its runtime check at all
three compression levels. Store does not use a compression dictionary. ZIP and
RAR reject 7z-only overrides. Arbitrary extra command-line switches are not
accepted.

The initial external profile is bounded to **64 MiB per source member and decoded
7z folder**, and **256 MiB aggregate source/output**. A single file larger than
the requested solid block can occupy its own block; the independent decoded
folder limit still applies. An installed tool that ignores the requested block
limit and produces an unreadable oversized folder is rejected before publication.

Arguments are passed directly without a shell. Private staging, explicit member
lists, bounded process output, exit status, cancellation and child-process drain
are checked before publication. Generated output must reopen as the requested
format and match the entire captured namespace, member hashes, times and ordinary
permissions. Tool output that adds, drops or substitutes a member is rejected.
If process shutdown cannot be established, its owned staging is retained with
an error rather than deleted beneath a live process.

Linux runtime qualification used **7-Zip 23.01** and **RAR 7.23**. All 27 exposed
7z profiles passed Store, Normal and Maximum probes. The Linux test binaries are
development evidence, not redistributed application dependencies. Other installed
versions must pass the same runtime probes; native macOS/Windows execution
remains a separate platform acceptance gate.

## Read numbered 7z volumes

Open the first file of a set such as `backup.7z.001`. Three- through six-digit
numbering is supported, beginning with `.001`, `.0001`, `.00001` or `.000001`.
Every part must be a nonempty regular sibling in the same captured directory,
with the same base name and numbering width. Missing parts, duplicate numeric
aliases, case/padding ambiguities, mixed storage identities and changed parts
are rejected.

Pane browsing, F3, integrity checking and native extraction use the same complete
captured set. Positional reads cross part boundaries without joining a permanent
output file. The initial 7z header, CRC and declared end are checked, so a
missing final part or trailing bytes cannot be mistaken for a complete set.
Opening metadata does not itself test every payload; use **Test selected
archives** for member checking.

There are at most 1,024 parts, with the numbering width's smaller limit where
applicable. Aggregate captured input is capped at **8 GiB on native** and
**256 MiB in the browser**. Eligible native unencrypted member reads stream;
encrypted or unsupported streaming methods fall back to the existing bounded
reader, normally 64 MiB per decoded member/folder. Private snapshots are removed
when their owning archive closes. Native F3 can additionally retain a temporary
copy of its first remote part for the raw viewer modes, so free space must allow
both that copy and the captured set.

These are read-only format-aware 7z volume sets. RAR volumes, ZIP `.z01` sets,
arbitrary `.001` files, split creation and split updating remain separate work.

All bounded 7z fallbacks, including SFX and encrypted volume payloads, preflight
their public and decoded headers before invoking the compatibility decoder.
They cap source input at 256 MiB, each packed range and coder output at 64 MiB,
LZMA/LZMA2 dictionaries at 64 MiB, inspected header metadata at 16 MiB and AES
key-derivation power at 20. Oversized intermediate streams are refused even if
the final member claims a small size. This conservative fallback is separate
from the eligible native 8 GiB streaming decoder.

## Inspect self-extracting archives

Supported unsigned Windows PE executables can expose an immediately appended
ZIP, 7z or RAR payload. Use archive browsing from the pane, or choose **Archive**
in F3. Ordinary `.exe` files retain their usual open action and binary viewer
default; generic folder navigation does not assume every executable contains
an archive. `.sfx` offers
archive inspection directly. Inspecting the archive never runs the executable.

The reader checks the PE header, section boundaries and archive extent. It
supports the checked PE32/PE32+ machine profiles and ZIP relative/physical
offsets, including validated ZIP64 structures. The executable prefix is limited
to 32 MiB and inspected metadata to 16 MiB. It refuses signed PE files,
unsupported symbol/debug overlays, installers with intervening overlay data,
ambiguous embedded signatures and truncated layouts.

The resulting format is explicitly `sfx/zip`, `sfx/7z` or `sfx/rar` and stays
read-only even when renamed with an ordinary archive suffix. No rewrite may
silently discard the executable stub or its metadata. SFX generation and signed
installer/package rebuilding are not enabled by this reader.

## Remaining parity boundaries

The acceptance matrix remains the complete gap record. This continuation does
not close WCX ABI hosting, the full external-adapter action catalog, split/SFX
creation, archive repair/recovery-record creation, arbitrary external-editor
repack handoff, reverse/two-way archive synchronization, nested cross-container
moves, all uncommon codecs or remote/browser archive publication. Existing
format-specific metadata and signing restrictions continue to apply.

ISO editing is still for inspected data images, not bootable/hybrid/UDF images.
DMG editing still requires the verified canonical HFSX data-volume profile;
APFS, arbitrary mounted filesystems and signed application images are separate
capabilities. See [format coverage](archive-format-coverage.md) and
[ISO/RAR/DMG profiles](archive-iso-rar-dmg.md).

## Verification

Focused local runs cover queue persistence and publication acknowledgement,
native worker lifetime, complete batch admission, password retries, external
process failures, independently decoded output, supported SFX layouts and
numbered volume snapshots. They use Flutter 3.47.8 / Dart 3.13.7, matching the
repository pin. The final regression record is added here after the integrated
source is frozen.

The branch's **Commander archive workflows** CI runs archive/menu regression,
scoped analysis, offline-help validation and a versioned release web build. It
retains the exact source SHA, dependency hashes, test events and logs. Earlier
normal and >2 GiB hosted evidence remains recorded against its own source
revisions in [runtime verification](archive-containers-runtime-verification.md);
it is not retroactive qualification of every new option.
