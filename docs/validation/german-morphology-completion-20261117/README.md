# German morphology completion and macOS build 31

The real grammar gaps are fixed in upstream Quds and CrispCloud. The historical corpus is unchanged: literal matching improves from **73/81 to 77/81**. An explicit review accounts for every original row: **78 necessary corrections and three preserved valid readings**, giving **81/81 reviewed decisions**. These are different metrics; the reviewed score is not a claim that 81 sentences require correction.

## What changed

- Preserve explicit singular evidence in malformed determiners, including shared singular/plural noun surfaces such as `für diesem Schlüssel` → `für diesen Schlüssel`.
- Offer complete, internally agreeing noun-phrase alternatives when the original is invalid under every supported reading. `Ich habe ein schönen Tag` offers masculine and neuter repairs; `Ich sehe der neue Kunde` offers the supported masculine and feminine readings. Existing valid readings still veto an error.
- Recognize bounded genitive attributes in complete copula clauses and selected abstract prepositional objects. Literal locations remain eligible for abstention.
- Preserve the incoming complete-verb-object safety gate, including fronted objects, agreement ambiguity, protected text and incomplete clauses. Share its ambiguity veto with the older context rules.
- Apply each changed word of a phrase choice inside one undo transaction, preserving individual run formatting. Tracked replacements inherit the changed source word's formatting and comment ownership. Tests cover bold/italic runs, tracking, undo/redo and DOCX save/reopen.
- Retain the existing host icon painter in canonical source and reserve a leading text slot so numeric glyphs cannot cover it. A pixel regression caught both missing and obscured markers. Incoming calendar, field, bookmark and conditional-format fidelity work remains included.

No new analyzer runtime, model, daemon or subprocess transport is introduced. Existing first-party work surrounding the historical analyzer remains; incompletely documented AOT/RML/nlp_base material is excluded. Native spaCy implementation remains separate. Lexical resources and their pinned licensing inputs are unchanged.

## Unchanged gold and explicit adjudication

[The historical corpus](https://github.com/CrispStrobe/quds_office_suite/blob/6245a6956a76a38f925e1eb18851c0086730112d/tools/proofing/german_morphology_cases.json) was not edited. [The separate review](https://github.com/CrispStrobe/quds_office_suite/blob/6245a6956a76a38f925e1eb18851c0086730112d/tools/proofing/german_morphology_adjudication_20261117.json) binds four decisions to its exact SHA-256, source texts and original expected outputs:

| Original row | Decision |
| --- | --- |
| `Wir sprechen mit dem Mensch.` | Preserve the recorded neuter regional/dated reading. This exact input is also a protected valid control in the release corpus. [Duden declension](https://www.duden.de/deklination/substantive/Mensch_Frau). |
| `Wir stehen bei den Computer.` | Accept the existing plural repair `bei den Computern` alongside the gold's singular repair. [Duden declension](https://www.duden.de/deklination/substantive/Computer). |
| `Wir helfen der Kunde.` | Preserve the grammatically valid feminine dative reading; odd semantics do not establish a different gender. [Duden's feminine entry](https://www.duden.de/rechtschreibung/Kunde_Nachricht). |
| `Sie wartet auf dem neuen Bus.` | Preserve a possible literal location reading. An intended waiting-for object would use accusative; the isolated sentence does not establish that intention. [IDS on prepositional objects](https://grammis.ids-mannheim.de/progr@mm/6736), [Hamburg grammar explanation](https://www.slm.uni-hamburg.de/germanistik/personen/imo/downloads/imo-grammatik-loesungen.pdf). |

The context corpus also accepts the already valid plural repair `Sie antwortet den Lehrern.` separately from its original singular gold. The literal context score improves **21/23 → 22/23**; the explicitly reviewed context score is **23/23**.

The reporter cannot silently replace the original exact score. Checks reject a different corpus hash, changed original gold, duplicate base results and a control regression. Necessary corrections still require findings; preservation decisions require clean source text. Qualification now rechecks every offered first correction, including corrections that differ from literal gold.

## Qualification

| Corpus | Literal errors corrected | Flagged valid controls |
| --- | --- | --- |
| Original | 18/18 | 0/12 |
| Context | 22/23 | 0/60 |
| Holdout | 46/46 | 0/58 |
| Release cases | 9/9 | 0/29 |
| Broader morphology | 77/81; reviewed decisions 81/81 | 0/175 |
| Frozen follow-up regressions | 18/18 | 0/32 |
| Independent review | 24/24 | 0/60 |

VM and compiled JavaScript outputs agree. Broader morphology records 1,280 requests and the independent review 420, including offset/soft-hyphen/locale and protected-code variants. The accuracy counts above are base sentences; parity and safety checks across variants do not imply that every conservative clause gate accepts every decorated input. No operational, protection, ignore or recheck failures were recorded. These finite engineering corpora are not population accuracy measurements.

Accepted local cohorts include **1,039 proofing**, **267 ODF/ODS/ODP**, and **611 ODT/save-cache** engine tests; **247** further affected incoming-format tests; **111** editor/controller/rendering tests; and host cohorts of **39 services, 29 workflows, and 14 vendor UI tests**. The additional cohorts overlap and must not be added as distinct tests. Targeted analysis reports no issues.

A combined host run stalled while loading the renderer after 73 completed cases during severe disk pressure. It was interrupted and is not an acceptance result. Smaller clean cohorts passed afterward. Earlier disk-exhausted runs, failing development assertions and the failing-before-fix style/pixel probes remain separate from the accepted evidence.

## Frozen release and delivery

Built host: `a2a6319a0e8798e2a4878548d1ae6b651648b59f`. Canonical pin: `6245a6956a76a38f925e1eb18851c0086730112d`. The host's **2,631-file** tracked inventory matches canonical source and the separately pinned 1,857-file parser. The final host ancestry merge changes documentation only relative to the qualified runtime tree; its equivalence receipt is retained.

Both app and Finder extension are **1.3.4/build 31**, ARM64. Strict signatures, component/profile checks and a 15-second startup of the development-signed copy pass; startup reaches `Credential policy ready`. The distribution installer is signed separately. Build logs retain dependency/toolchain and removed compiler-cache debug-symbol warnings; they are not reported as warning-free.

Installer SHA-256: `75cb30b889f0b8d9e33cb542995e554f19f4da72e838114df5943b76df1239a8`.

Apple's live artifact/source/country preflight passed, including explicit French exclusion. Existing encryption answers, reviewed tester groups and membership remain unchanged. The Mac screen is locked, preventing manual signed UI interactions. Apple validation and upload succeeded; processing is `VALID`. Build 31 is `IN_BETA_TESTING` internally and assigned to both existing reviewed groups. External review submission was rejected with `ENTITY_UNPROCESSABLE.ANOTHER_BUILD_IN_REVIEW`: build 29 remains `WAITING_FOR_REVIEW`. Build 31 is therefore **not yet externally available**. No older build was expired. Apple documents [one build per version in review at a time](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/); the [documented beta review API](https://developer.apple.com/documentation/appstoreconnectapi/beta-app-review-submissions) exposes creation and reads, with no withdrawal operation. Exact state is recorded in [release-receipt.json](release-receipt.json).

## Evidence

`evidence-index.json` records hashes of compressed receipts and logs. User-home prefixes are redacted in published text; original and published hashes are both retained. No credentials, user-document GUI dumps, compiler caches, native model binaries or installers are published. No GitHub Actions jobs or CI status endpoints were queried or awaited.
