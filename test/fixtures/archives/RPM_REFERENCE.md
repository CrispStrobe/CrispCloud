# Independent RPM reader fixtures

These two small, unmodified binary RPMs come from the libarchive v3.7.4 test
corpus. They were built independently with `rpmbuild`; they are not output
from CrispCloud's fixture builder. They contain three original text files,
`./etc/file1`, `./etc/file2` and `./etc/file3`, each containing `hello\n`.
Each file has mode 0644 and modification time 86401 seconds after the Unix
epoch. The package's declared license is BSD.

| File | Bytes | SHA-256 | Upstream Git blob (uuencoded source) |
| --- | ---: | --- | --- |
| `libarchive-gzip.rpm` | 1909 | `dcc4f3ab933335bf3822d94079fdf4f0b7ac4c65773ca8e9a973a1cec7c553d6` | `54d305b7742c2c030391540ca2ab4af68a3525a9` |
| `libarchive-bzip2.rpm` | 1972 | `d652b81accaeaf5761b807971fd9ca75f00ebaeefad237a80f08f7764a24b66c` | `884ca9487cb87d129fbfb20508267a1c3b25a536` |

Sources and original native generation recipes:

- [gzip fixture](https://github.com/libarchive/libarchive/blob/v3.7.4/libarchive/test/test_read_format_cpio_svr4_gzip_rpm.rpm.uu)
  and [rpmbuild recipe / original assertions](https://github.com/libarchive/libarchive/blob/v3.7.4/libarchive/test/test_read_format_cpio_svr4_gzip_rpm.c).
- [bzip2 fixture](https://github.com/libarchive/libarchive/blob/v3.7.4/libarchive/test/test_read_format_cpio_svr4_bzip2_rpm.rpm.uu)
  and [rpmbuild recipe / original assertions](https://github.com/libarchive/libarchive/blob/v3.7.4/libarchive/test/test_read_format_cpio_svr4_bzip2_rpm.c).

The original recipes create the text files, install them under `/etc` in an
isolated build root, fix their timestamps, and invoke `rpmbuild -bb`. The gzip
recipe uses `%_binary_payload w9.gzdio`; the bzip2 recipe uses `w9.bzdio`.
The checked-in files are obtained by uudecoding the corresponding upstream
`.rpm.uu` files without changing the package or recompressing its payload.
The upstream sources contain cleanup commands intended for their original
temporary build roots; inspect and adapt those commands before regenerating.

`test/archive_rpm_reader_test.dart` checks both real RPMs through the new
reader, including original MD5, CPIO hierarchy, file bytes, times and modes.
Original generated mutation fixtures independently cover the remaining
supported wrappers, payload SHA-256, malformed headers, source ownership,
limits, traversal and special records. No native tool is needed to run the
Dart tests and no RPM is installed or executed.

## Reader scope

The reader supports classic v3/v4 RPMs with header-style signatures and
newc/CRC CPIO payloads. gzip, bzip2, XZ, Zstandard and uncompressed payloads
are bounded to 64 MiB packed and 64 MiB expanded by default; caller-provided
lower limits are enforced before allocation. RPM headers have a shared
16 MiB metadata and 200,000 index-entry budget. XZ dictionaries and Zstandard
windows are limited to 64 MiB. Links, hard-linked records, special entries
and unsafe paths retain the existing CPIO extraction restrictions.

Present header/payload MD5 values and compressed/expanded payload SHA-256
digests are verified. The optional payload digest algorithm tag must be 8
(SHA-256); other digest profiles are refused. Publisher signatures and
separate header/file digest records are not authenticated or verified, as
the viewer notice states. A successful read does not establish package
installation validity or publisher trust. RPM v6, stripped CPIO large-file
payloads, unsupported codecs, duplicate/malformed header tags and invalid
declared sizes are refused.

The [official tag table](https://rpm.org/docs/latest/manual/tags) identifies
`RPMFORMAT` as tag 5114 of type int32. The
[RPM v6 format](https://rpm.org/docs/6.0.x/manual/format_v6.html) introduces
that explicit format-version field; its value is checked when present so
the reader cannot silently treat a v6 package as a supported classic RPM.

## Upstream fixture license

Copyright (c) 2003-2007 Tim Kientzle

Copyright (c) 2009 Michihiro NAKAJIMA

All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:

1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE AUTHOR(S) "AS IS" AND ANY EXPRESS OR
IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
IN NO EVENT SHALL THE AUTHOR(S) BE LIABLE FOR ANY DIRECT, INDIRECT,
INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
