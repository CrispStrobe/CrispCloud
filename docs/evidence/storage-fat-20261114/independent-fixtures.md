# Independently mastered FAT reference volumes

These fixtures bind the new reader to filesystem bytes produced by an
independent implementation. ChaN FatFs R0.16 formatted and populated all four
images through its public filesystem API. The committed host shim and payloads
are original MIT code and data. The app does not link, ship, or execute FatFs.

## External implementation and license

The upstream implementation is [ChaN FatFs](https://elm-chan.org/fsw/ff/).
Its [license explanation](https://elm-chan.org/fsw/ff/doc/appnote.html#license)
describes the included license as equivalent to BSD-1-Clause. The
[R0.16 archive](https://elm-chan.org/fsw/ff/arc/ff16.zip) used here has SHA-256
99f7dc1f7e095356e4a9e3dbe29959090d8b948afe2bbc5441e52fdf4b85449e.
The archive hash is the authoritative pin because an upstream release archive
can receive maintenance updates. The manifest also pins the five individual
upstream source files used by the external build.

The upstream source notice is retained below for attribution, including any
formatter-generated boot-sector template bytes represented in the fixtures:

> Copyright (C) 2025, ChaN, all right reserved.
>
> FatFs module is an open source software. Redistribution and use of FatFs in
> source and binary forms, with or without modification, are permitted provided
> that the following condition is met:
>
> 1. Redistributions of source code must retain the above copyright notice,
>    this condition and the following disclaimer.
>
> This software is provided by the copyright holder and contributors "AS IS"
> and any warranties related to this software are DISCLAIMED.
> The copyright owner or contributors be NOT LIABLE for any damages caused
> by use of this software.

[rust-fatfs](https://github.com/rafalh/rust-fatfs) is another open FAT library;
its [upstream license](https://github.com/rafalh/rust-fatfs/blob/master/LICENSE.txt)
is MIT. It was evaluated as a candidate and is not imported or used by this
increment. The reader itself uses the app's existing Dart byte-source and
archive interfaces, preserving VM and JavaScript portability.

## Mastered inputs

| Fixture | Full image size | FAT | Logical sector | File data |
| --- | ---: | ---: | ---: | --- |
| fat12 | 1,474,560 bytes | 12 | 512 bytes | Nine original files, two directories |
| fat16 | 8,388,608 bytes | 16 | 512 bytes | Same payloads |
| fat32 | 67,108,864 bytes | 32 | 512 bytes | Same payloads |
| fat16-sector4096 | 33,554,432 bytes | 16 | 4,096 bytes | Same payloads |

Each volume has two FAT copies and one sector per cluster. Dates are fixed at
2000-01-01 00:00:00. The original payloads include an ASCII short name, UTF-8
text, café-雪.txt, emoji-😀.txt, a name occupying exactly thirteen UTF-16
code units, a multiple-record long name, an empty file, an empty directory,
and an 8,193-byte nested file.

The host shim alternates 512-byte appends to fragmented.bin and blocker.bin.
FatFs itself allocates the resulting noncontiguous chains. The generator walks
the resulting allocation table, checks both FAT copies for each chain entry,
and records the exact chain in the manifest. No allocation table, directory,
timestamp, or payload bytes are patched after the writer finishes.

The fixture Dart file stores exact nonzero 512-byte sector runs; every omitted
byte is zero. Gzip/base64 only compresses this lossless representation.
Reconstruction is checked against each full image's SHA-256. This keeps the
committed source small while retaining externally mastered physical image
identity. FatReferenceSource can expose those exact bytes through bounded
positional reads without allocating a whole 64 MiB volume.

The reference images are not examples of large-image qualification. Their
complete sizes are listed above. Any synthetic GPT/MBR wrapper, corrupt input,
or large-offset case built from these images must be described separately as
derived or synthetic.

## Reproduction

Download the pinned archive separately, then run from the repository root:

~~~sh
python3 test/support/generate_fat_reference.py \
  --fatfs-zip /path/to/ff16.zip \
  --output-dir /path/to/external-build-directory \
  --cc /path/to/gcc \
  --dart /path/to/dart \
  --check
~~~

The generator refuses a different archive or source hash, writes all upstream
sources and build products into the specified external directory, compiles the
original host shim, masters every image, formats generated Dart, and compares
the resulting Dart and JSON files with the committed versions. It never adds
an application dependency. The exact local invocation, versions, source
hashes, and successful reproduction log accompany this document.

## Independent extraction

The separate check_archive_fat.py script reconstructs the committed Dart
fixtures, verifies every range and full image hash against the manifest, then
asks an externally supplied 7-Zip executable to extract each image:

~~~sh
python3 test/support/check_archive_fat.py \
  --sevenzip /path/to/7zz \
  --work-dir /path/to/temporary-extraction-directory \
  --report /path/to/oracle-receipt.json
~~~

7-Zip 26.06 successfully extracted all four complete images. All 36 extracted
files have the exact expected names, sizes, and SHA-256 values; all eight
directory instances match, including the empty directories. Each input image
has the same SHA-256 before and after extraction.

fat-sevenzip-oracle.json contains each external exit code and raw output,
per-file hashes, image hashes, and the external executable hash. The executable
is a validation-only tool outside this repository and the application. No
external extractor or formatter binary is bundled.
