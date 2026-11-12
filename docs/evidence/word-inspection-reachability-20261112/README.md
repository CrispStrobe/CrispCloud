# Reachable Word conversion evidence

Conversion loss warnings now require a compatible internal relationship from
the actual main document or an attached Word story. Disconnected ZIP parts and
glossary-only stories retain their inventory counts but cannot prove that
headers, notes, comments, or objects survived conversion. Story target types
and roots must agree; separator-only note parts do not count as normal notes.
Object links cannot alias document/story/relationship structural parts, while
embedded packages retain their permitted extensible content types. Note
separator attributes are namespace-aware in counts and warnings.

All 32 data-only inspection tests pass, including 11 new adversarial controls.
The exact production service was compiled through the app's resolved package
registrations. A temporary copy of the tests changed only the Flutter test
import to the cached Dart test runner. Its inverse transform was byte-checked
against the repository test. `provenance.json` records sources, runner/package
configuration, the exact command and verification. `summary.json` hashes the
source and full compressed log. Analysis of both changed Dart files is clean.

The Flutter runner was not accepted as a completed test: environment detection
and an unrelated SMB native-library download encountered automatic network
approval blocks before tests executed. The direct cached runner invokes no
Flutter process, pub resolution, native build hook or network download. The
release pubspec was restored exactly. This validates package inspection logic,
not widget behavior, native SMB, ebook conversion, or a release build.

The inspection remains a part/relationship presence check. It does not verify
every text anchor or note/comment ID, compare object payload semantics, or
certify rendering fidelity. Independent parser oracles and schema/native
acceptance remain separate requirements.
