# Independent native disk-image fixtures

`native-hfsplus.hfs.gz` contains an 8 MiB HFS+ volume produced independently
of CrispCloud's Dart reader. The gzip wrapper keeps its repository size small.
It contains only original fixture text, a `docs` directory, and an
`Applications` symbolic link; no application, executable, or third-party
document is included.

The image contains a multi-level catalog B-tree, 42 regular files, one ordinary
directory and one symbolic link. Every regular file contains exactly:

```text
CrispCloud independently created HFS+ fixture
```

The text has a final LF newline. The regular paths are `hello.txt`,
`docs/nested.txt`, and `docs/entry-00.txt` through `docs/entry-39.txt`.

## Creation and validation

- Formatter: Ubuntu `hfsprogs` `540.1.linux3-5build3`, derived from Apple's
  filesystem tools. [Package and checksum](https://packages.ubuntu.com/noble/amd64/hfsprogs/download).
- Package SHA-256: `21aab68916cdba913b8571f1d83285f958878d2378255ee87a225575b917b77f`.
- Populator: [mozilla/libdmg-hfsplus](https://github.com/mozilla/libdmg-hfsplus)
  commit `e18579b391950589b9ed16ee630c54ce4319bb29`, built as a temporary native
  test utility. The utility is not an application dependency and its source
  is not included in CrispCloud.
- `fsck.hfsplus -n native-fixture.hfs` checked extents, catalog, hierarchy,
  extended attributes, volume bitmap and volume information and reported the
  volume OK. No image was mounted.

Representative commands, with the two utilities on `PATH`:

```sh
truncate -s 8M native-fixture.hfs
mkfs.hfsplus -v CrispArchive native-fixture.hfs
printf 'CrispCloud independently created HFS+ fixture\n' > hello.txt
hfsplus native-fixture.hfs add hello.txt /hello.txt
hfsplus native-fixture.hfs mkdir /docs
hfsplus native-fixture.hfs add hello.txt /docs/nested.txt
hfsplus native-fixture.hfs symlink /Applications /Applications
for i in $(seq -w 0 39); do
  hfsplus native-fixture.hfs add hello.txt "/docs/entry-$i.txt"
done
fsck.hfsplus -n native-fixture.hfs
```

The committed gzip was produced with Python `gzip.compress(raw, mtime=0)`.
Native volume timestamps/identifiers can differ when regenerating the image;
the test verifies paths, file contents, link classification and reader limits.

`native-hfsplus.dmg` was then created by the same pinned Mozilla tool:

```sh
dmg -c zlib build native-fixture.hfs native-hfsplus.dmg
dmg extract native-hfsplus.dmg native-roundtrip.hfs
cmp native-fixture.hfs native-roundtrip.hfs
```

The independent extract roundtrip matched the original HFS+ bytes exactly.
The UDIF image contains five block maps: driver descriptor, Apple partition
map, ATAPI driver, the HFS+ filesystem, and an ignored/free region. Its 32
compressed HFS+ chunks exercise random access across multiple blocks. The
free-region block is `BLOCK_IGNORE` (type 2), with CRC32 zero; the ignored
region does not contribute zero bytes to the partition checksum.

| Artifact | SHA-256 |
| --- | --- |
| Expanded HFS+ image | `1b74ae366c66819a2af64ed547693a8e70ed434f5b3b099f1d238e42890f6fa3` |
| Committed gzip | `e7170e5739ec31bef10b16dcbd7a78ce16cae74cccd027871ecd5cc009e3e118` |
| Native UDIF DMG | `ee40765ee597887860eda0acfd53bca9570ea764cf536cb9e0fbeca81524ec25` |
