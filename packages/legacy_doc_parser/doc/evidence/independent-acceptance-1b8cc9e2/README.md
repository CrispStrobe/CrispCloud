# Independent-oracle integration acceptance

Measured parser commit: `1b8cc9e28aa9f4da2d0f0fa9318758bce0e923f1`.
Measured tree: `8b826eb2239438565faefa718bd42da61107d95e`.

The portable and Open XML SDK gates ran against the same clean, frozen source
used by the final native and conversion-path runs. All 1,386 tracked inputs,
the dependency lock, and package configuration were hashed before and after
each launch; none changed. The evidence is an observation of that source, not
a claim that later evidence-only commits were executed.

## Results

| Gate | Observed result |
| --- | --- |
| Dart formatting | 220 files; no changes |
| Dart analysis | No issues |
| Dart tests | 1,089 passed |
| Python controls | 184 passed |
| Original fidelity corpus | All 24 input hashes and corpus graph checks passed |
| Actual compiled JavaScript | Legacy DOC, media, ink, ink/header, symbols, fields, and font charsets passed |
| Package dry run | Zero warnings |
| Open XML SDK 3.3.0, Office 2019 target | 265 DOCX outputs, zero errors |
| Repeat corpus generation | Both 560-file generations were byte-identical |
| Schema rejection controls | Both malformed-input controls rejected; validator discovery controls passed |

The JavaScript field acceptance retains owner-story bindings and the deliberate
same-length URL swap that must be rejected. It does not evaluate fields. Font
acceptance retains raw charset decisions and does not remap private-use text.
The existing ink/header receipt's one explicitly classified metric difference
is preserved; no historical result is relabelled.

## Retained evidence and replay

`validation-artifacts.tar.xz` contains 1,552 files: raw portable output and
receipts, both generated SDK corpora, validator reports and controls, 390
schema/build source inputs, launch receipts, toolchain recovery receipts, and
the measured Git commit/tree objects. Four reproducible validator DLLs are
omitted with their identities retained. The archive is 1,543,832 bytes, SHA-256
`52f16315daad944a1de13472c1edc0c5fe72fa867bbb411824dc820718de812c`.

From the repository root:

```sh
python3 doc/evidence/independent-acceptance-1b8cc9e2/seal_validation_evidence.py --self-test
python3 -O doc/evidence/independent-acceptance-1b8cc9e2/seal_validation_evidence.py --self-test
```

Add `--repository /path/to/legacy-doc-parser` to check the measured tracked
inputs against the retained commit in that Git object database. This does not
require checking out the measured source or running captured code.

Both modes passed with all nine deliberately corrupted receipts rejected,
including a wrong measured source, a substituted launch executable, a lost
owner-swap check, omitted SDK cases, false determinism, and resealed document
hash or validator-result changes. These are integrity and derivation checks;
replaying the retained evidence is not another independent correctness vote.

Schema validity and these bounded acceptance cases do not establish visual or
semantic fidelity for arbitrary documents. See the separate native-corpus,
field, symbol/font, crisp-docx, and conversion-path evidence for those measured
properties and their remaining limitations.
