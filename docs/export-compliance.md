# Encryption export compliance

Reviewed against official sources on **2026-11-07**. This is an engineering
release decision guide, not a government classification or legal certification.
The exporter must apply it to the actual product and distribution.

## Intended route: retain functionality without the two BIS filings

The proposed default is a **finished consumer application using documented,
published cryptography**, eligible for internal mass-market self-classification
as **ECCN 5D992.c** under EAR §740.17(b)(1) and Category 5 Part 2 Note 3. An
eligible finished application does **not** require either a BIS annual
self-classification **report** or a CCATS classification request. Making a
classification decision is different from filing a report. [1][2][3]

This does not require deleting Filen or Internxt end-to-end encryption,
reducing key lengths, moving all crypto to operating-system APIs, or creating a
crypto-free App Store edition. Assess the entire distributed app and its
dependencies. Hiding a feature does not change the code shipped.

The previous version of this document incorrectly presented a BIS report or
CCATS as unavoidable when retaining file encryption. BIS narrowed the
reporting rules in March 2021. Its amendment table distinguishes qualifying
mass-market products from items still requiring filings. Some BIS overview
pages retain older, broader wording; use the current regulation and amendment
table for this distinction. [1][2]

## 1. Establish eligibility for the finished app

Record evidence for these conditions before relying on the proposed route:

| Condition | Evidence |
| --- | --- |
| Ordinary public retail/electronic distribution with broad consumer or business appeal. | Store listing, price and published functionality. Free distribution alone is not a classification. |
| Installation without substantial supplier assistance. | Normal App Store/Android installation and onboarding. |
| Users cannot readily alter the shipped cryptographic functionality. | Supported algorithms/protocols and review of plugins, scripting or externally supplied crypto interfaces. |
| Technical details are available to the competent authority on request. | Source revision, dependencies, inventory and build evidence. |
| No different classification/reporting provision applies. | Review EAR §740.17(b)(2), (b)(3) and (e)(3), including non-standard crypto, open crypto interfaces, customized government products, cryptanalysis/forensics and specified network infrastructure. |

The first four conditions summarize Note 3. [3] Section 740.17(e)(3) does not
make every runnable program reportable: its special `executable software`
category concerns software from an existing hardware component and excludes
complete end-item software images. An APK or IPA is not reportable merely
because it is executable. [1]

The §772.1 definition of non-standard cryptography addresses proprietary or
unpublished functionality, including algorithms/protocols without
standards-body approval that have not otherwise been published. Identifying
AES inside an undocumented construction is insufficient evidence for the
whole construction. [4] Do not describe this file-encryption app as
“authentication only” or rely casually on ancillary-encryption exclusions:
BIS expressly identifies file encryption and data backup among relevant
information-security functions. [5]

## 2. Public source is a separate route

EAR §742.15(b) excludes eligible publicly available encryption source from the
EAR. Current notification requirements apply only to source performing
**non-standard cryptography**; standard publicly available encryption source
no longer needs that email notification. Section 734.17(b) also addresses
corresponding object code. [2][6][7]

For the binary route, establish that the distributed object code is publicly
available and corresponds to eligible publicly available source, including
relevant cryptographic dependencies. Retain the exact release tag/commit,
dependency provenance and build correspondence. A public library dependency
alone does not establish this exclusion for a private application built on it;
BIS requires evaluating the new item as a whole. [7][8]

If non-standard crypto remains, §742.15(b)(2)'s source notification is distinct
from a CCATS or annual report, and does not resolve Apple's separate treatment
of proprietary algorithms. The old TSU §740.13(e) reference is obsolete; use
§742.15(b). [1][6][9] Record this exclusion separately if relying on it. The
finished-app mass-market route above is the primary proposed store-build
route, not a claim that public hosting removes the need for assessment.

## 3. Apple: disclose the actual encryption and territories

The iOS and macOS `ITSAppUsesNonExemptEncryption` setting remains `true`.
Do not flip it merely to suppress questions or because a BIS filing is
unnecessary. Apple assesses third-party libraries too. Its current table
states: [9][10]

| Encryption used | App Store Connect documentation |
| --- | --- |
| Limited to Apple's operating-system encryption | None required. |
| Industry-standard algorithms implemented outside Apple's OS | French declaration if distributing in France; no US CCATS listed for this category. |
| Proprietary algorithms not accepted by international standards bodies | US CCATS; also a French declaration when distributing in France. |

For a build whose inventory and tests establish the standard-algorithm case,
answer **yes, the app uses encryption**, and disclose its standard algorithms.
Filen/Internxt E2EE, local file encryption and bundled vault crypto must not be
represented as HTTPS-only or Apple-OS-only. Complete the actual questionnaire
for the final binary and territories; do not invent a BIS receipt or CCATS
identifier to support the proposed no-filing decision.

The complete inventory also includes active traditional PKWARE ZipCrypto
decoding and published archive-specific key derivation. Do not label this
"only internationally standardized algorithms." Apple itself quotes the EAR
definition of non-standard cryptography, including the "not otherwise
published" qualification. PKWARE publishes the traditional cipher in APPNOTE
section 6.1. Lack of formal standardization alone does not establish an
automatic CCATS requirement; preserve this source evidence and assess the
whole product. This guide does not predict Apple's questionnaire result for a
specific release. [4][15][16]

If Apple's questionnaire determines that no documentation is required, retain
that result before using a plist shortcut. When documentation is reviewed,
`ITSEncryptionExportComplianceCode` takes the **Apple-issued code**, not a
self-created reference. [10][11]

France remains a separate distribution assessment. Keep an applicable French
declaration or supported exemption determination. ANSSI regulates supply and
import of cryptology products subject to exceptions. This change does not
alter existing territories. Excluding France is a product decision and is not
necessary to avoid the two **BIS** filings. [9][12]

Germany-based developers still face Apple's export process: Apple explains
that App Store/TestFlight uploads use US servers. Android distribution needs
an assessment of its actual channel as well; absence of an Apple questionnaire
is not an export classification. [10]

## 4. Germany and the EU

The EU assessment is separate from the US ECCN decision. Regulation (EU)
2021/821, Annex I, contains both the General Software Note's public-domain
provision and Category 5 Part 2 Note 3's mass-market criteria. The general
retail-software provision alone does not release Category 5 Part 2 software;
use the applicable crypto-specific or public-domain provision. [13]

For EU purposes, public-domain software is available without restrictions on
further dissemination; copyright restrictions do not defeat that definition.
Intending to publish restricted software later is not permission for its
initial export. Confirm the release's provenance and availability and record
the German/EU basis. A US no-filing decision does not establish eligibility
for every destination, end user or sanctions regime. [13][14]

## 5. Release evidence and steps

Read [crypto-audit.md](crypto-audit.md) for implementation findings, limits and
validation results. The audit found a construction labelled AES-SIV that did
not implement RFC 5297. A standards claim must be based on the corrected code
and independent test vectors, not its former comment. This document does not
certify that every cryptographic path has been audited.

Include more than the four named services in the inventory: provider login,
metadata/filename/file encryption, transfer streams, key storage, account
backups and transitive packages all matter. Filen and Internxt E2EE must remain
compatible with their published formats. An external desktop VeraCrypt mount
process and bundled cross-platform vault code are different release facts.

Before each release:

1. Run relevant crypto known-answer/tamper and provider compatibility tests.
   Record untested live-account and device flows explicitly.
2. Build actual release targets from the recorded commit and locked
   dependencies. Generate evidence with
   [`tool/crypto_release_evidence.py`](../tool/crypto_release_evidence.py);
   retain artifact hashes and build logs alongside it. A source inventory does
   not prove the contents of an unbuilt binary. The store workflows retain exact
   generated native lockfiles/Android plugin registration, their hashes and
   differences from the source revision. A CocoaPods reserialization of the iOS
   project is recorded only when Apple's parser establishes that every parsed
   value and array order matches the source revision; the exact bytes and diff
   are retained. Changed project settings or references still fail the gate.
   Review any newly resolved native
   dependencies and their source availability; recording a change does not
   establish its classification.
3. Complete the decision record below for those artifacts. Resolve any failed
   condition before relying on the route; do not silently substitute a report
   or CCATS application.
4. Complete Apple's questions for the actual iOS/macOS builds and territories;
   record the France decision and any Apple-issued code.
5. Reassess when crypto, dependencies, extension interfaces, product positioning
   or distribution changes.

This workflow generates engineering evidence. It does not email authorities,
file a report, request CCATS, submit an app or change store territories.

### Observed store blocker (2026-11-07)

The signed macOS `1.1.0 (10)` package built from `79dbb56` reached
`altool --validate-app` but Apple rejected it with **ITMS-90592 / 90592**
(*Invalid Export Compliance Code*). The package contains
`ITSAppUsesNonExemptEncryption=true` and no
`ITSEncryptionExportComplianceCode`, while App Store Connect app `6789570314`
has no app encryption declaration for the app
(`GET /v1/appEncryptionDeclarations?filter[app]=6789570314` returned an empty
list). The build was **not uploaded**, so no duplicate build was created.

Do not resolve this by blindly flipping the plist to `false` or inventing a
code. Before the next TestFlight attempt, either:

1. complete Apple's encryption questionnaire/declaration for the actual
   binary, obtain the Apple-issued `codeValue`, and add it as
   `ITSEncryptionExportComplianceCode` while keeping the declaration true; or
2. establish that the app qualifies for the no-documentation answer and is
   not distributed in France, then record that decision and use the matching
   plist answer.

The macOS release workflow is otherwise healthy: the clean-runner startup
smoke test now recognizes the first-run credential chooser instead of treating
it as a crash.

**Release decision (2026-11-07):** create an App Store Connect app encryption
declaration for the actual binary with `containsProprietaryCryptography=false`,
`containsThirdPartyCryptography=true` and `availableOnFrenchStore=false`; keep
France out of App Store availability for this release. This is the no-French-
declaration route. Record the Apple-issued `codeValue`, add it as
`ITSEncryptionExportComplianceCode`, and keep
`ITSAppUsesNonExemptEncryption=true`. Revisit the declaration before enabling
France or changing the cryptographic inventory.

### Internal release decision record

Fill in facts and references; checked boxes without evidence do not establish
eligibility.

```text
Product/version and build identifiers:
Source commit/tag and dependency lock revision:
Artifacts and SHA-256 hashes (iOS / macOS / Android as applicable):
Inventory/evidence and test results:
Open implementation findings and release disposition:
Distribution method, price, audience and territories:

US route relied on:
  [ ] Finished mass-market app, 5D992.c, EAR 740.17(b)(1)
      Note 3 supporting evidence:
      740.17(b)(2)/(b)(3) review and result:
      Basis for no reporting under 740.17(e)(3):
  [ ] Public source/corresponding object code exclusion
      Exact public source, dependencies and binary references:
      Source-to-binary correspondence evidence:
      742.15(b)(2) notification: not required / applicable; basis:
No BIS report / no CCATS rationale:
German/EU basis and destination restrictions:
Apple answers and resulting documentation requirement:
France declaration/exemption or territory decision:
Apple compliance code, only if actually issued:
Responsible exporter/reviewer and decision date:
```

## Official sources

Checked 2026-11-07. BIS regulation pages displayed an eCFR currency date of
2026-11-06. The EU consolidated text below is dated 2026-09-21.

1. [EAR Part 740: §740.17(b), (e)(3); §740.13(e) reserved](https://www.bis.gov/regulations/ear/740).
2. [BIS: March 29, 2021 reporting changes, with before/after table](https://www.bis.gov/media/documents/table-changes-enc-wa2019-rule-final-version.pdf).
3. [Commerce Control List: Category 5 Part 2, Cryptography Note 3](https://www.bis.gov/regulations/ear/interactive-commerce-control-list).
4. [EAR Part 772: definition of non-standard cryptography](https://www.bis.gov/regulations/ear/772).
5. [BIS: 5A002.a and information-security functions](https://www.bis.gov/learn-support/encryption-controls/5a002-a.1-a.5).
6. [EAR Part 742: §742.15(b), publicly available encryption source](https://www.bis.gov/regulations/ear/742).
7. [EAR Part 734: §734.17(b), source and corresponding object code](https://www.bis.gov/regulations/ear/734).
8. [BIS: items not subject to the EAR and the whole-item caveat](https://www.bis.gov/learn-support/encryption-controls/encryption-items-not-subject-to-ear). Read its general notification wording with the newer rule in sources 2 and 6.
9. [Apple: documentation by encryption type](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption/).
10. [Apple: complying with encryption export regulations](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations).
11. [Apple: determine and upload encryption documentation](https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation).
12. [ANSSI: controls for cryptology products](https://cyber.gouv.fr/reglementation/reglementation-identite-confiance-numerique/controles-reglementaires-cryptographie/controle-moyen-de-cryptologie/).
13. [Regulation (EU) 2021/821, consolidated 2026-09-21: Annex I notes, definitions and Category 5 Part 2](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:02021R0821-20260921).
14. [European Commission Recommendation (EU) 2021/1700: public-domain software guidance](https://eur-lex.europa.eu/legal-content/DE/ALL/?uri=CELEX:32021H1700).
15. [Apple: overview of export compliance and its quoted non-standard-cryptography definition](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance).
16. [PKWARE APPNOTE 6.3.10: published ZIP format and traditional encryption, section 6.1](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT).
