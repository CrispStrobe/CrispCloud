# Reviewed S3 block-copy qualification

**981 tests passed across 52 native Flutter suites, with zero failures, skips or error events.** Strict analysis of all 23 changed Dart files also passed. The qualified source is `832d3a26e004cf5268928d093841d3df61a3c5ea`, tree `5b185bf4c52650cb64c0895f0c7c349f800c8808`.

The native run executed on Linux x86-64 with Flutter 3.47.8 / Dart 3.13.7 and real native hooks. Dependencies were resolved offline from the committed manifest and lockfile, including their existing declared overrides. No task-specific dependency override or hook disabling was introduced.

Execution ran on **2026-11-14, 22:53:01–22:57:04 Europe/Berlin** (21:53:01–21:57:04 UTC). All **8,390 input entries** matched before and after, and HEAD, tree and clean Git status stayed unchanged. The inventory includes every tracked file outside `docs/evidence/**` plus the root generated package configuration and package graph. Endpoint equality does not prove absence of transient writes between the observations.

## Gates

| Gate | Exact source | Result |
| --- | --- | --- |
| Native copy/core/provider/queue/recovery/bandwidth/UI/catalogue cohort | `832d3a26` | 981 passed / 52 suites; 0 failed, skipped or errors |
| Strict Dart analysis, fatal warnings and infos | `832d3a26` | All 23 changed `lib`/`test` Dart files; no issues |
| Catalogue Rust unit tests | `8b2ec107` | 14 passed; 0 failed; one existing million-row stress case explicitly ignored; 0 doc tests |

The Rust source, manifests, lockfiles and vendored inputs are byte-identical in the accepted candidate. Only a Dart test and evidence changed after its run. Its Unix alias/self-exclusion regression passed. This Linux result does not establish reproduction of the original Windows path-prefix failure.

The earlier standalone 790/43 cohort, Word 60-case refresh and canonical Office 232-case run retain their separate source pins and evidence. They are not added to the 981 count and were not rerun as part of this copy-method increment.

## What the run establishes

The three new runtime suites comprise **68 cases**: 23 prepared-content cases, 27 S3 strategy cases and 18 ordinary copy/queue integration cases. The remaining suites cover earlier delta behavior, ordinary provider transfers, staged publication, metadata, resource claims, scheduling, job management, recovery, both conflict UIs, options, translations, Settings and catalogue surfaces. The exact manifest and per-suite counts are retained below.

The new Copy method can build its map while delivering a first conditional full copy, then reuse proven local blocks for the same current S3 revision and live adapter. Complete logical contents retain progress, the per-job stream limiter and whole-file SHA-256 evidence. Actual covered HTTP payload bytes remain charged to the captured foreground bandwidth context. A consumer zone cannot replace that context.

A queue fixture copies a **4,259,840-byte** source once, then reconstructs a later replacement using **4,194,304 local bytes** and **65,536 downloaded bytes**. Both runs produce the complete source contents and whole-file journal hash. This is deterministic test evidence, not a live-provider performance benchmark or a claim about end-to-end traffic including metadata.

The cohort includes an actual signed loopback HTTP first copy and journaled all-reuse repeat through the new method, as well as the existing real-HTTP standalone reconstruction case. Mock transports inject malformed ranges, stale ETags, content/map changes, pending headers/body reads, abort races, reused buffers, changed authentication and cache-write failures.

The committing journal write and pause gate finish before renewed source, original-destination and candidate proofs. Tests change each of those after durable commit intent, revoke the captured source during final provider validation, introduce a new destination, pause/cancel, and check that unreviewed bytes are not published. Whole-file SHA evidence reconciles a lost committed acknowledgement without another source-content transfer. A late cancellation after acknowledged publication can still stop remaining job work; the installed data and journal evidence remain available for review.

Recovery explicitly changes the method to ordinary streaming while retaining the existing source/account checks, prefix verification, confirmed-copy reconciliation and owned-stage rules. It does not deserialize map trust or a prepared-content capability.

## Evidence and reproduction

- [Native command](native/command.json), [metadata](native/metadata.json), [per-suite summary](native/summary.json), [raw events](native/stdout.jsonl), [stderr](native/stderr.log), and [artifact hashes](native/artifacts-sha256.json).
- [Before](native/inputs-before.json.gz) and [after](native/inputs-after.json.gz) native input inventories.
- [Strict analysis metadata](analysis/metadata.json), [command](analysis/command.json), [file scope](analysis/files.txt), [output](analysis/stdout.log), and [artifact hashes](analysis/artifacts-sha256.json).
- [Catalogue summary](catalogue/summary.json), [command](catalogue/command.json), [stdout](catalogue/stdout.log), [environment](catalogue/environment.json), and [artifact hashes](catalogue/artifacts-sha256.json).
- [Independent review](independent-review.json), covering raw event counts, source equivalence, stable inputs and the carried catalogue gate.
- [Suite manifest](../native-suites.txt), [native receipt runner](../run_delta_qualification.py) and [offline dependency resolution](../setup/pub-get.log).

The recorded native command uses `flutter test --no-pub --concurrency=1 --machine` followed by the manifest paths. The launcher path belongs to the recorded workspace; a developer with the specified installed toolchain can run the listed command directly. The native stderr retains an expected Windows compiler-probe message emitted on Linux; the actual build and tests completed with exit code zero.

## Prior attempts and boundaries

The [prior fixed-source run](prior-native/summary.json) at `8b2ec107` records 980 passes and one failed assertion. Its existing clone-contract test iterated every copy-method enum and incorrectly expected the newly added S3-only method to admit local-to-local copies. The corrected test preserves the three ordinary clone/stream contracts and explicitly verifies rejection of the unsupported verified-block source before side effects. No runtime source changed for that correction. Earlier evolving-tree fixture attempts are retained in [development](../development/README.md).

Automatic delta selection remains disabled. This profile does not provide durable cross-session block-map trust or delta-plan resume, remote delta writes, S3 SSE-C support, cross-process path exclusion, or atomic compare-and-swap against external local writers. It does not qualify live S3 interoperability, browser/mobile packaging, Windows/macOS execution, external Office rendering, or a production release build. The suite whose filename includes `browser` ran on the native VM here.
