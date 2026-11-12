# Vendored Kindling provenance

- Repository: <https://github.com/ciscoriordan/kindling>
- Version/tag: `0.46.2` / `v0.46.2`
- Commit: `7774dbae758435d6ed94a4cd4a50e3f33ab61aa7`
- Annotated tag object: `97ac9b2afbf0ff0f86849d367ea7ded2618ab7e9`
- License: MIT; the upstream license and README are retained verbatim.

`native/vendor/kindling` contains the upstream `src/` tree, `Cargo.toml`,
`LICENSE`, and `README.md`. The standalone upstream CLI is not built. The
application calls a narrow library adapter in `native/src/lib.rs`; only the
reviewed request/response helper in `native/src/main.rs` is exposed as a process.

`UPSTREAM.json` records upstream and local SHA-256 values for every imported
file. `UPSTREAM.patch` contains the changes relative to that commit. Verify
the local file set and hashes with `python3 tool/check_vendor.py`.

## Local differences from the upstream revision

| File | Reason |
| --- | --- |
| `Cargo.toml` | Disable the upstream CLI; exclude the unused EPUB writer's `scraper`/`ego-tree` dependencies; limit raster codecs; pin lightningcss alpha.71 and parcel_selectors 0.28.2 to the reviewed compatible pair. |
| `src/lib.rs` | Exclude the unused EPUB writer module. CrispCloud's package-preserving EPUB writer owns that operation. |
| `src/extracted.rs` | Remove only the unused scraper HTML cache. Retain upstream lightningcss grammar checking and the existing Kindle rule extraction. |
| `src/fonts.rs` | Stop an absent-encryption search at the EPUB container root so it does not inspect unrelated ancestor directories. |
| `src/mobi.rs` | Preserve the source TOC in the legacy KF7 half of dual MOBI exports. Append a nested HTML TOC, insert its `type="toc"` guide reference, and resolve all navigation targets through the final byte-offset pass. |
| `src/mobi_rewrite.rs` | Extract the shared metadata byte API behind the native file wrapper; validate PalmDB/section bounds and encrypted secondary KF8 headers; avoid inflating embedded source ZIPs for ordinary metadata edits; preserve UTF-8/Windows-1252 metadata encoding with lossless rejection, set the EXTH-present flag on inserted blocks, and reconcile EXTH title/hash and header title independently. |

The original checkpoint replaced lightningcss with a local delimiter-only
checker to avoid MPL dependencies. That replacement has been removed now that
MPL-2.0 is explicitly allowed. A regression tests a balanced but invalid CSS
selector, which the weaker checker accepted. `parcel_selectors` 0.28.3 changed
its cssparser dependency incompatibly with lightningcss alpha.71; the pin uses
the exact 0.28.2 version in Kindling v0.46.2's upstream Cargo lockfile.

All resolved registry sources are locked in `native/Cargo.lock` and
`wasm/Cargo.lock` and inventoried
in `licensing/cargo_licenses.json`. The notices include exact source-download
URLs. For published subcrates that omitted their workspace-root license,
`licensing/upstream/` preserves that license from the crate's exact
`.cargo_vcs_info.json` revision; the checker verifies that revision before using
the supplemental notice.

The browser metadata adapter uses the same reviewed byte implementation in a
separate Wasm crate. `WASM.json` records the compiled asset, worker, source inputs,
Rust compiler and pinned wasm-bindgen postprocessor. The final module has no
host imports. EPUB-to-Kindle conversion and cover replacement remain native
operations; no browser filesystem emulation or external conversion service is
part of this adapter.

## Updating

Check out the proposed upstream commit, compare the imported file set, reapply
the narrow patch, and rerun native, Dart, and reader compatibility checks. Keep
the original upstream license files and regenerate the provenance hashes and
dependency notices after review. Do not update to a moving branch or silently
replace the Cargo lockfile during release builds.
