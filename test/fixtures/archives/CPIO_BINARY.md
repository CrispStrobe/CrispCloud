# Binary CPIO reference fixtures

The two fixtures contain original deterministic data written with **libarchive
3.7.4** using `archive_write_set_format_cpio_bin`. The opposite byte order is
made by swapping each 16-bit header word, leaving pathnames, padding and payload
bytes untouched. Both variants are then independently read with libarchive,
checking complete content, names, modes, sizes and modification times.

```sh
python3 test/support/generate_cpio_binary_reference.py --check-only
```

Omit `--check-only` to regenerate. The archive contains a directory, an odd-length
file, an empty file and a 65,869-byte file. The last file and the fixed timestamp
exercise the high-word-first 32-bit representation independently of the byte
order inside each 16-bit word.

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| `reference-binary-le.cpio` | 66050 | `c86a13d7b2939d642ee89a08c6548ab4fc0c0bf0b45ee68ce2ef981be5351892` |
| `reference-binary-be.cpio` | 66050 | `23df1317cf65fe5c56751c733364491bbd92e2e275961ef0604ebac105bccc0f` |

Format source: [libarchive's CPIO format manual](https://github.com/libarchive/libarchive/blob/master/libarchive/cpio.5).
The original application reader follows the modern binary layout. PWB-specific
type semantics are not inferred from the shared magic; unsupported/special
records and hard links remain non-extractable. Names must be valid UTF-8, headers
must retain one profile/byte order, word-alignment padding must be zero, and
non-padding tails/concatenated archives are refused. Binary CPIO remains
read-only; the newc/CRC writer inspector is unchanged.
