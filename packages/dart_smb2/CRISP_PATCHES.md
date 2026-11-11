# Crisp packaging patch

This is dart_smb2 0.2.5, retaining its BSD-3-Clause license and upstream authors.
The Dart transport implementation is unchanged. libsmb2 remains LGPL-2.1-or-later.

The upstream Apple binaries cannot accommodate Dart's longer install names in
some checkout paths. The hook now builds Apple assets from the exact r10 source
recipe with `-Wl,-headerpad_max_install_names`. It needs Xcode, Python 3, curl,
make/zip and the command-line tools. Other platforms retain upstream r10's
checksum-verified release binaries. Explicit local-library overrides still work.

`native/` contains the Apple recipe, shared patches, config and license texts from
libsmb2-scripts commit `eca28a3ef007d6c268ebfd4a4950a0c28de6335c`.
`UPSTREAM.json` records each original file's SHA-256. Our recipe changes add header
padding and bounded source-download timeouts. Source is pinned to libsmb2 commit
`4d9ce67863332462236d86bf76c85617a0b2897d`, verified against its archive hash before
patching or compiling. Build variables cannot replace that pin. Each hook build
uses an isolated output tree; original files and the global pub cache are read-only.

The r10 update also includes upstream fixes for encrypted request handling,
malformed replies and NTLM initialization. This preserves the libsmb2 fallback
while updating its native runtime. Final app artifacts must still include the
LGPL notice and corresponding source/build recipe, plus their own binary hashes.

Git attributes preserve LF endings for this package, including its native recipe
and license texts. This keeps the recorded SHA-256 evidence stable on Windows
checkouts with `core.autocrlf=true`; the integrity test checks original bytes.
