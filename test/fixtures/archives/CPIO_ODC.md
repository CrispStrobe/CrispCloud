# Portable ASCII CPIO reference fixture

`reference-odc.cpio` was generated with native **libarchive 3.7.4** through its
`archive_write_set_format_cpio_odc` API. It is independent of CrispCloud's Dart
CPIO reader and writer. The filenames and text payloads are original test data.
The generator is optional test tooling; the application adds no native runtime
dependency.

Regenerate from the repository root on Linux with `libarchive.so.13` installed:

```sh
python3 test/support/generate_cpio_odc_reference.py
```

The complete native API calls and fixed input metadata are recorded in
[`generate_cpio_odc_reference.py`](../../support/generate_cpio_odc_reference.py).
The writer uses one-byte physical blocks, so the fixture ends after the
`TRAILER!!!` record without unrelated block padding.

## Expected data

Every ordinary entry has UID **123**, GID **456**, one link, and modification
time **1700000000** (2023-11-14 22:13:20 UTC). Inodes are assigned in order.

| Name | Kind | Mode | Payload |
| --- | --- | --- | --- |
| `docs` | Directory | `040755` | Empty |
| `docs/hello.txt` | Regular file | `100640` | `Independent portable CPIO fixture\n` (34 bytes) |
| `docs/odd` | Regular file | `100644` | `odd` (3 bytes) |

The first file record starts at byte **81**. The directory's five-byte stored
pathname includes its NUL terminator and is not rounded to an even boundary.
The `docs/odd` name occupies nine bytes including its NUL terminator, followed
immediately by its three-byte payload. These records distinguish portable ASCII
CPIO's unaligned layout from newc's four-byte alignment.

## Recorded output

- Generator runtime: Python `ctypes`, native libarchive **3.7.4**.
- Format magic: ASCII `070707` (portable ASCII/ODC CPIO).
- Length: **381 bytes**.
- SHA-256: `654f5817c061f00101f57a70e014c1762eb33d58a17923a3ccedfcd0907d4729`.

Reference implementation:
[libarchive 3.7.4 CPIO writer](https://github.com/libarchive/libarchive/blob/v3.7.4/libarchive/archive_write_set_format_cpio_odc.c).
