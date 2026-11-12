# CrispCloud Kindle conversion

This package wraps the vendored Kindling 0.46.2 engine. It accepts immutable
input bytes and returns output bytes; only the application save session writes
the user's selected destination.

## Operations

| Operation | Output and limits |
| --- | --- |
| EPUB export | AZW3/KF8 or dual MOBI containing KF7 and KF8. This is conversion; typography, navigation, and unsupported features can change. |
| Kindle metadata update | Title, multiple authors, publisher, description, language, ISBN, ASIN, publication date, subjects, identifier, and replacement of an existing cover. Unchanged text/resource records are retained. |
| No-op metadata update | Returns byte-identical input. |
| MOBI/AZW3 import into EPUB | Provided by the separate `crisp_ebook_reader` Foliate adapter, not by this package. |

DRM-protected input is refused. EPUB font obfuscation using the IDPF or Adobe
algorithms is distinguished from DRM; Kindling can decode supported embedded
font resources. KFX is outside this package's supported formats.

The wrapper rejects unsafe archive paths, duplicate/case-colliding entries,
external resource paths, XML entity declarations, unsupported markup encodings,
and inputs exceeding its bounded archive/image budgets. Export runs upstream
Kindling validation, including the restored lightningcss grammar parser, then
reads back the produced Kindle container. A parsing or validation failure does
not overwrite the input. The original archive is never passed as an output path.

The default budgets are 64 MiB input, 128 MiB output, 192 MiB expanded content,
32 MiB per entry, 10,000 entries, and 50 million pixels per raster image. A
conversion makes a private temporary copy and checks that the copy is unchanged
before returning.

## Runtime and build

Native builds use a Dart code-assets build hook to compile and bundle the Rust
library. Install Rust 1.88 or newer and the target needed by the build. The
checked-in Cargo lockfile is always used with `--locked`.

Apple builds forward the complete minimum OS version supplied by Flutter,
including minor and patch components. The hook requires code_assets 2.2 or
newer so a deployment target such as macOS 10.15 is not truncated to 10.0.

| Platform | Build mapping |
| --- | --- |
| Linux | x64 and arm64; a cross linker/sysroot is required when not building for the host. |
| macOS | x64 and arm64, using the selected macOS SDK. |
| Windows | x64 and arm64 MSVC targets; the matching Visual Studio toolchain is required. |
| iOS | arm64 device, arm64 simulator, and x64 simulator, using the selected iOS SDK. |
| Android | arm64, armv7, and x64 through the NDK; shared-library alignment supports 16 KiB pages. |
| Browser | Kindle export and metadata rewrite report unavailable. EPUB reading/editing and reader-side import are separate features. |

These target mappings describe the build configuration. They do not establish
that every target has passed a device runtime test. Check the feature's CI and
release smoke results before making a platform compatibility claim.

`.github/actions/setup-ebook-rust` installs Rust targets and the app's Android
NDK where needed. `ANDROID_NDK_HOME` or `ANDROID_NDK_ROOT` selects an explicit
NDK for local builds; otherwise the hook looks beneath the Android SDK.

An application may configure the hook in its own `pubspec.yaml`:

```yaml
hooks:
  user_defines:
    crisp_ebook_conversion:
      # Defaults to true. false deliberately omits the native converter.
      enabled: true
      # Optional instead of compiling; must match the actual build target:
      # kindling_library: /absolute/path/libcrisp_kindling_bridge.so
      # Optional toolchain locations:
      # cargo: /absolute/path/cargo
      # cargo_home: /absolute/path/cargo-home
      # rustup_home: /absolute/path/rustup-home
```

Dart runs hooks with a filtered environment. A nonstandard Rust installation
must use the user-defines above for its Cargo/Rustup homes; shell variables
`CARGO_HOME` and `RUSTUP_HOME` are not forwarded to hooks. Standard tool
discovery uses the permitted PATH and home-directory locations.

`KindlingConverter.capabilities()` reports whether the bundled runtime is
available. Native operations run on one worker thread and support cooperative
cancellation: the caller receives cancellation immediately, output is discarded,
and private files are retained until the worker has stopped using them. An
upstream synchronous build cannot be forcibly preempted. A separately built
desktop helper can be supplied through `executablePath` when process termination
is preferred. No helper is discovered or executed from arbitrary `PATH` entries.

## Reproduce verification

From this directory, with the application Dart SDK and Rust toolchain on PATH:

```sh
cargo test --manifest-path native/Cargo.toml --locked --lib
cargo build --manifest-path native/Cargo.toml --release --locked
python3 tool/check_vendor.py
python3 tool/check_licenses.py
python3 tool/smoke.py
dart pub get
dart analyze
dart test
```

The native smoke suite independently inspects the PalmDB records, text,
Unicode content, metadata changes, no-op stability, source preservation,
DRM refusal, malformed EPUB confinement, and conversion budgets. It produces
original test MOBI/AZW3 fixtures under ignored `test/fixtures/generated/` for
the reader's independent import/reading smoke tests. These small fixtures
exercise the integration; they are not a representative compatibility corpus
for every publisher's ebooks.

Legacy MOBI verification also checks its TOC guide, nested labels, and exact
byte-offset navigation targets. The independent Foliate suite reads both the
modern KF8 and legacy KF7 streams and imports each into EPUB.

The cross-package import gate then checks the actual result with EPUBCheck
5.4.0. It retains metadata, Unicode, the nested TOC, cross-chapter links, and
every non-XHTML resource byte, reopens the emitted EPUB through the core, and
requires zero EPUBCheck errors or warnings for both the source fixture and all
three resulting EPUBs. It also verifies that all input file hashes remain
unchanged. Prepare the core's Dart dependencies and the reader's Node
dependencies, then run from this package:

```sh
(cd ../crisp_ebook && dart pub get)
(cd ../crisp_ebook_reader && npm ci --ignore-scripts --no-audit --no-fund)
python3 tool/verify_import_chain.py --epubcheck /path/to/epubcheck-5.4.0/epubcheck.jar
```

Reports and imported EPUBs are written to ignored `build/import-chain/`.
`--output` selects another directory. `--dart`, `--node`, and `--java` may
select explicit toolchains. In an environment without a writable default Java
temporary directory, supply `--java-temp-dir /writable/temporary/directory`
so EPUBCheck's ImageIO cache can validate PNG files correctly.

## Source and licenses

Kindling is MIT. Its exact upstream revision, selected files, and local patch
are in `UPSTREAM.md`, `UPSTREAM.json`, and `UPSTREAM.patch`. The CSS parser and
some of its dependencies use MPL-2.0, which is approved for this integration.
Those crates are unmodified; the shipped `licensing/THIRD_PARTY_LICENSES.txt`
contains their notices and links to the exact source releases. The complete
resolved Cargo dependency inventory includes platform and build dependencies.

For a deliberate dependency change, review source/license changes before
running `python3 tool/check_licenses.py --record`. The checker rejects an
unreviewed grant or missing license evidence rather than silently dropping it.
