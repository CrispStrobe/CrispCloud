# Bounded late integration: completed handoff

The authoritative final run is **`qualification-2`**, which completed with
exit code zero against these remotely saved source commits:

- Quds: `732fc3d0bc7a1118f3eb86e6c762fe70182c4fd2`
- CrispCloud: `084815b665df7779357155d86c5fff9bd31bfc43`

| Final bounded cohort | Passed |
| --- | ---: |
| Canonical sheet cache/save and style namespace suites | 18 |
| Existing four actual-host test files | 41 |
| Complete document-service test file, including both new ODT regressions | 39 |
| Python sync/verifier tests | 28 |

These are **126 completed checks in overlapping reruns**. They must not be
added to the earlier 1,128-test qualification as a new unique total. The
earlier receipts remain bound to Quds `5b056643…` and host `342b744a…`.

All three canonical commands and all twelve host commands passed. This
includes strict canonical/host/vendored analysis, all required format checks,
the final 2,521-file source and tracked-vendor guards, Python checks, and
whitespace checks. Canonical before/after maps cover 1,582 source inputs and
1,770 dependency/runtime inputs; host maps cover 3,745 source inputs and
5,983 dependency/runtime inputs. All stability, harness/fixture, and temporary
analyzer-configuration restoration gates passed.

The ODT service tests cover independent per-frame geometry while sharing the
same image bytes, as well as invalid, nonpositive, and non-finite dimensions.
The complete viewer dependency graph was not resolved. Its delivered source
is bound by Git blob and SHA-256, and its strict formatting check passed;
this does **not** claim viewer compilation or live rendering acceptance.

## Evidence and exclusions

`qualification-2/receipt.json` is the combined terminal receipt.
Its `canonical/` and `host/` subdirectories contain complete command logs,
before/after maps, analyzer graphs, and child receipts. The exact invocation
is `late-invocation-2.json`; the launch journal is
`qualification-2-launcher.log`. Execution session 63542 exited zero.

`qualification-1` remains a failed attempt. Its tests and analyses passed,
but the unchanged incoming viewer failed strict formatting before Python and
final guards ran. Its original logs and receipts are retained separately and
none of its progress counts is added to qualification 2. The exact formatter
proposal was applied in fourteen wrapping hunks, with file mode unchanged,
and saved in host commit `084815b6…`. The failed gate was not weakened.
`viewer-format-application.json` and the proposal patch record this correction.

The isolated service graph has 107 packages. All 97 hosted package versions
and archive hashes match the production lock; the eleven additions are the
required `koni_archive` dependency family, `glob`, `html`, and `csslib`.
Every newly downloaded archive was hash-checked. Existing SDK, harness, and
cache inputs were not rewritten. See
`service-setup/full-production-lock-comparison.json`, the completed setup
receipt, and `service-harness-inputs.json.gz`.

The first setup resolution correctly rejected two local engine/editor lock
paths still pointing at the old harness. `setup-attempt-1.json`, the original
seed lock, and its log preserve that diagnostic. The actual successful setup
used the separately executed `resume-service-setup.py`: it rebased only those
two paths, then ran the same offline `--enforce-lockfile` command twice with
package identities unchanged and the final lock byte-stable. This setup ran
no application tests.

`prepare-service-harness.py` was amended after its failed attempt to include
the path correction for future fresh runs. **That revised helper was only
statically reviewed; it was not executed end to end.** The successful setup
receipt therefore belongs to the original preparation followed by the
recovery helper, not to the revised one-pass helper.

No contemporaneous snapshot or checksum of the initial preparation script
was recorded. `setup-provenance/prepare-service-harness.reconstructed-initial.py`
is explicitly a reconstruction of its pre-correction form, not independently
verified executed bytes. Its lock-building behavior reproduces the retained
failed seed lock byte for byte. The provenance bundle preserves the revised
helper, the unchanged executed recovery helper, their hashes, the one-line
reconstruction-to-revision delta, and the exact original logs and receipts'
identities. See `setup-provenance/provenance.json` for these limits.

## Reproduction

First reconstruct the genuine runtime and original focused harnesses using
the separately published setup package. No qualification should be active
while preparing or changing source checkouts. Move clean checkouts named
`quds` and `crisp` to the two final commits above. Their dependency
declarations and the original focused lockfiles remain unchanged.

Place these scripts under a fresh `runtime/late-main` directory, preserving
their contents. The service setup requires Python with PyYAML and support for
`tarfile.extractall(filter='data')`, plus Git and curl. The following fresh-run
recipe uses the revised, static-reviewed preparation helper. It has not been
executed as a complete fresh-run recipe in this session; the accepted graph
was established by the original failed preparation and successful recovery
sequence documented above. Keep this reproduction distinction when reporting
results. To execute the fresh-run recipe:

```bash
source runtime/env.sh

python3 runtime/late-main/prepare-service-harness.py \
  --repo "$PWD/crisp" \
  --base-harness "$PWD/runtime/crisp-host-harness" \
  --flutter "$PWD/runtime/flutter-sdk" \
  --output-root "$PWD/runtime/late-main/service-setup"

python3 runtime/late-main/run-late-integration.py \
  --quds-source "$PWD/quds" --host-source "$PWD/crisp" \
  --quds-commit 732fc3d0bc7a1118f3eb86e6c762fe70182c4fd2 \
  --host-commit 084815b665df7779357155d86c5fff9bd31bfc43 \
  --runtime "$PWD/runtime" \
  --output "$PWD/runtime/late-main/qualification-new"
```

Use a new output directory; no script replaces previous qualification
evidence. Keep all source-pin, package-lock, successful-terminal-marker,
zero-skip, timeout, input-stability, restoration, and required-command gates.
The host's original 41-test and 28-Python-test assertions are unchanged.
The two sheet files and separate service file require positive complete
results; their accepted observed counts are recorded in the receipts.

`canonical-support.py` preserves the prior fingerprint implementation.
`run-late-host.py` retains the existing host runner and adds the separate
service test, service targets, vendored `sml_styles.dart`, and viewer format
check. `runner-origins.json` and `host-runner-delta.patch` record that origin.
No broad engine/editor Zotero or Harper suites are rerun here.

## Packaging boundary

Preserve the scripts, invocation/origin/delta/proposal/application records,
this README, the setup-provenance bundle, qualification 2's complete
receipts/logs/maps, and service setup receipts, lock-correction record,
eight-input bundle, lock comparison, and compressed setup logs. Keep qualification 1 separately labeled as failed.
Exclude service caches, harness directories, downloaded package archives,
temporary files, and configuration directories. The exact archive URLs and
hashes are reproducible from the preparation script and production lock
entries in the setup receipt. No GitHub Actions or CI endpoints were used.

**Handoff:** source, runtime, harnesses, scripts, and terminal receipts are
frozen. No test or setup process remains active under this agent.
