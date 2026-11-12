# Localization and acceptance

[Gap register and closure rules](README.md). Baseline: `28b7b9c`.

Every item below has a separate completion boundary. A prototype, reader-only
codec or passing loopback test does not imply the broader platform or write
capability. Required live/device checks remain visible after code implementation.

## G48

### UI language coverage

**Status:** Scoped. **Dependencies:** Terminology review; localization inventory.

**Scope:** Add the fifteen missing requested languages and complete supported-locale fallbacks.

**Implementation:** Inventory user-visible strings and add Italian, Danish, Swedish, Norwegian Bokmal, Dutch, Czech, Russian, Polish, Hungarian, Hebrew, Greek, Afrikaans, Catalan, Turkish and Ukrainian. Complete missing strings in the nine current locales.

**Boundary:** Locale registration alone is not translation coverage. Preserve stable command IDs and placeholders; add right-to-left behavior where required. Document intentionally untranslated technical identifiers separately from fallback prose.

**Acceptance:**

- All registered message keys/placeholders are complete and valid in each claimed locale.
- Representative narrow/large-text/RTL screens and shortcuts are exercised without clipping or incorrect focus order.
- Terminology and functional instructions are reviewed across navigation, operations, errors, security and recovery flows.

**Starting points:** Localization inventory/catalogs; existing localization/layout tests.

## G49

### Localized help

**Status:** Implementing. **Dependencies:** Canonical English guide; documentation localization.

**Scope:** Provide maintained German and French help, then align other locales with available guides.

**Implementation:** Create maintained German and French help from the canonical user workflows, then organize additional help locales with explicit coverage. Link context-sensitive help to stable topics and version the screenshots/examples.

**Boundary:** Translated summaries must not claim unsupported features or bypass operation review. Missing topics show an explicit available-language fallback. Keep implementation references and user instructions clearly separated.

**Acceptance:**

- Links, anchors and in-app topic routes resolve offline or through the supported help surface.
- Translated operation/recovery/security instructions agree with current UI behavior and supported limits.
- A source-topic update has a visible translation-update workflow so help does not silently diverge.

**Starting points:** docs/USER_GUIDE.md and help routes; G48 terminology.

## G50

### Native and live-provider acceptance

**Status:** Acceptance pending. **Dependencies:** Target machines; explicit test accounts and fixtures.

**Scope:** Run platform permission, signed-app and live-server matrices after implementation.

**Implementation:** Maintain a matrix of feature, platform, build/signing identity, provider/server version, test fixture and observed result. Run access-grant, native integration and live-server acceptance with isolated test data.

**Boundary:** Unit, widget, loopback and compilation evidence remain separate from signed runtime or live-provider acceptance. Use dedicated test accounts and explicitly chosen local folders; do not exercise unrelated user data.

**Acceptance:**

- Every claimed native bridge has observed target-device permission, lifecycle and recovery tests.
- Each advertised provider capability has recorded supported-server conformance, including conflict and interruption behavior.
- Failed/unavailable acceptance remains visible in docs and capabilities; credentials and private paths are excluded from evidence.

**Starting points:** Target machines, signing identities, isolated provider accounts; feature-specific fixtures.

**Current evidence:** G01 incoming drops, G04 configurable menus and G12 external
terminal launch are implemented and have automated regression evidence, but their
named real OS/browser interaction checks remain pending. The native conversion
fixture ran on Linux and transport fixtures ran on loopback; these do not replace
signed application, macOS access-grant or live-provider acceptance. See the
[current validation record](validation-20261112.md).

## G51

### Web runtime and WebAssembly acceptance

**Status:** Acceptance pending. **Dependencies:** Browser test harness; dependency compatibility.

**Scope:** Verify browser runtime workflows and investigate the optional WebAssembly build failure.

**Implementation:** Add browser-runtime checks for granted local folders, remote providers, keyboard/drop workflows and resource limits. Reproduce and diagnose the optional WebAssembly dry-run failure separately from the working JavaScript build.

**Boundary:** A successful JavaScript compile is not WebAssembly support or browser-runtime acceptance. Identify unsupported imports/dependencies and measured memory/compiler failures before changing the advertised build modes.

**Acceptance:**

- Browser tests cover grant revocation, canceled operations, large inputs and source-bound navigation/drop behavior.
- JavaScript release builds inject version/hash and pass a deterministic runtime smoke suite.
- WebAssembly support is enabled only after a successful build and representative runtime tests, with dependency limitations documented.

**Starting points:** Browser harness; web dependency/build configuration; G01/G50 acceptance.

**Current evidence:** The JavaScript release build for code checkpoint `ebede8d`
passed with `APP_VERSION=1.1.0+12` and `GIT_HASH=ebede8d`. The optional WebAssembly
dry run again exited 247. No WebAssembly support or browser-runtime acceptance
is established by this compilation. The failure's underlying cause remains to
be diagnosed; an exit code alone is not evidence of a specific memory or
dependency cause.
