# CPIO odc and binary writer profile verification

The application implements portable ASCII/odc and modern binary CPIO in both
byte orders from the published [CPIO format manual](https://github.com/libarchive/libarchive/blob/master/libarchive/cpio.5).
This extends CrispCloud's original package-writer architecture. No native packer
or new runtime dependency is used. No VaultExplorer implementation, test, asset,
or dependency was inspected or imported.

The existing `newc` creation default and inspected mixed newc/CRC rewrites remain
separate. A fresh legacy profile is selected explicitly; an existing source's
inspection determines the layout during rewriting, regardless of a caller's
fresh-creation preference.

## Preservation contract

Eligible inputs contain ordinary files and directories with valid UTF-8 names.
Each legacy record retains raw `dev`/`rdev`, inode, numeric ownership, link count,
permissions, whole-second modification time, profile, and original pathname
spelling when its logical path has not changed. Member order, a supported root
directory record, trailer fields, and zero trailing padding are preserved.
Supported edits may change names or contents and add/remove ordinary members.

Raw legacy device identifiers are not converted to newc major/minor fields;
that conversion would depend on the originating operating system. New members
receive distinct unused inode values, including when an existing member uses
the largest value in its profile. Duplicated device/inode identities, hardlinked
regular files, special records, profile/byte-order mixtures, nonzero alignment
padding, non-padding tails, and numeric overflow keep a container read-only.

Binary files use the modern type interpretation. PWB-specific semantics cannot
be inferred from the shared magic. Each 32-bit field stores its high 16-bit word
first, independently of byte order within the words. Binary numeric ownership,
device, inode and link fields are limited to 16 bits; odc uses 18-bit six-digit
octal fields. Binary sizes follow the supported signed-32-bit profile, and odc
size/time fields use eleven octal digits. Existing application member and
container limits remain stricter than these format limits.

Neither odc nor binary CPIO stores a payload checksum. Rewriting verifies exact
content through the existing whole-container publication workflow; native
readback below establishes interoperability, not a publisher signature.

## Independent references and commands

The saved baseline reader fixtures remain unchanged:

- [Portable ASCII fixture provenance](CPIO_ODC.md).
- [Binary LE/BE fixture provenance](CPIO_BINARY.md).

Fresh outputs use original deterministic text and byte patterns. They include
Unicode names, an empty file, an odd-length file, a directory with explicit
permission bits, a 65,869-byte payload, high inode values, and explicit raw
legacy device identifiers. Existing reference files are also rewritten without
edits and with a renamed/replaced member plus a new file.

Run from the repository root using the pinned Dart toolchain and dependencies:

```sh
dart run test/support/emit_archive_cpio_profiles.dart /tmp/cpio-profile-output
python3 test/support/check_archive_cpio_profiles.py /tmp/cpio-profile-output
```

The emitter creates nine cases: fresh, unchanged rewrite, and edited rewrite
for each of odc, binary LE, and binary BE. The checker reads each output through
native libarchive's CPIO reader and compares full payload SHA-256, names, sizes,
permission modes, UID/GID, modification times, raw device IDs, inode values,
and link counts against the original inputs. A separate Python `struct` parser
checks physical profile, high-word ordering, field values, alignment, trailer,
and tail boundaries. Unchanged rewrites must be byte-for-byte identical to the
saved native-produced fixtures.

These are test tools only. `test/archive_cpio_writer_profiles_test.dart` adds
preservation and refusal coverage for root location, stored-name spelling,
trailer metadata, repeated saves, output/input bounds, malformed metadata,
hardlinks, inode collisions and field overflow. The verification record for
this increment records the observed test and native-reference results.

## Portable runtime check

The optional `test/support/verify_archive_cpio_profiles_portable.dart` entry
point is compiled with Dart2JS and executed by Node. It recreates the three
fresh cases above and requires byte identities already accepted by native
libarchive, then reopens and rewrites them. It also checks odc's maximum
33-bit timestamp and rejects overflowing binary ownership metadata.

| Fresh output | SHA-256 |
| --- | --- |
| odc | `61cea07ea722ec14e24dbe5f08e4e9e40613bad20c7c5cafbb881ba57b8ca555` |
| binary LE | `35d91c10e3d2e4d56bc4cce7908f21574492a0f1aa702f5b47d4f21aad4afa21` |
| binary BE | `24f6f69dc70e64c1b99baa1f642abceb6def7b3c2a1e5a982296f517503fb9cf` |
