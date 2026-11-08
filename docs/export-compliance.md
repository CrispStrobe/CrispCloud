# Encryption export compliance

Apple, French and cited EAR requirements rechecked against official sources on
**2026-11-08**. This is an engineering release decision guide, not a government
classification or legal certification. The exporter must apply it to the actual
product and distribution. The repository records an intended outside-France
Apple release route; it does not establish the app's live store availability or
historical distribution.

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

The iOS and macOS plist answer depends on the declared territories and the
actual cryptography. Do not flip it merely to suppress questions or because a
BIS filing is unnecessary. Apple assesses third-party libraries too. Its
current table states: [9][10]

| Encryption used | App Store Connect documentation |
| --- | --- |
| Limited to Apple's operating-system encryption | None required. |
| Industry-standard algorithms implemented outside Apple's OS | French declaration if distributing in France; no US CCATS listed for this category. |
| Proprietary algorithms not accepted by international standards bodies | US CCATS; also a French declaration when distributing in France. |

Answer **yes, the app uses encryption**, and disclose the complete inventory.
Filen/Internxt E2EE, local file encryption and bundled vault crypto must not be
represented as HTTPS-only or Apple-OS-only. Tests establish implementation
properties; they do not make a legal classification or determine Apple's
questionnaire answers.

If the final whole-app assessment supports Apple's third-party,
non-proprietary case and the distribution assessment excludes France, the
no-documentation route can use `ITSAppUsesNonExemptEncryption=false`. That
value means no non-exempt encryption documentation is required for the reviewed
release; it does **not** mean the app contains no encryption. The recorded
2026-11-07 HTTP 409, discussed below, is consistent with this route but is not
approval of the supplied answers. Retain the actual questionnaire result and
supporting inventory and distribution evidence before relying on the shortcut.

If France is included, declare `availableOnFrenchStore=true`, provide the
required French documentation, and use the Apple-issued compliance code with
the appropriate `ITSAppUsesNonExemptEncryption=true` declaration. Do not retain
this app's outside-France `false` answer while distributing there. If Apple's
assessment requires a different route, resolve that requirement rather than
inventing a BIS receipt, CCATS identifier or Apple code. [9][10][11]

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

### France: supply, distribution history and declaration

French law distinguishes using cryptology from supplying or importing it.
LCEN Article 30 makes use unrestricted and separately exempts means limited
exclusively to authentication or integrity. Supplying, importing or transferring
a confidentiality product into France generally requires a prior declaration
unless an applicable exception exists. CrispCloud encrypts arbitrary files and
cloud data, so an authentication-only description is incorrect. ANSSI assigns
the formalities to the supplier or first importer. Apple's documentation rules
do not themselves grant a French-law exemption. [12][17]

No applicable exemption for this general-purpose file/cloud encryption app has
been established by this repository. Do not substitute a public-source claim,
a US mass-market classification or use of an OS library for that assessment.
The decree's personal-import exception concerns an individual's own import,
not the publisher's supply. ANSSI's `grand public` status is requested with the
declaration and validated by ANSSI; the resulting export treatment does not
erase the supply/import declaration. [18][19]

An outside-France decision must cover actual distribution, not just a current
storefront checkbox. Apple says customers who previously downloaded an app in
a subsequently deselected country continue receiving updates and can
redownload it. Review prior French App Store availability and downloads,
continuing updates/redownloads, French TestFlight recipients, and direct,
Android, web or other distribution into France. A live `FRA` exclusion does not
resolve those other channels or history. If prior French distribution is
present or cannot be determined, resolve the French compliance basis before
claiming this release excludes France. [20]

To enable French distribution:

1. Identify the actual legal supplier, responsible representative and covered
   supply/import operations. Do not infer a legal entity from a GitHub name.
2. Prepare the administrative and technical dossier. The current form requests
   a company presentation, a recent registry extract or equivalent foreign
   document, product and technical descriptions, and available user/admin
   manuals. Describe the exact product/version, platforms, algorithms and key
   lengths, modes, KDFs, randomness/nonces, key management, provider protocols,
   legacy compatibility and dependency provenance. The inventory and audit are
   inputs to this description, not evidence that a filing has occurred. [21]
3. Use the [current ANSSI declaration portal][21]. ANSSI's current control and
   forms pages direct applicants there. Retain the submitted scope, complete
   dossier date, receipt and any attestation or exemption determination. [12][22]
4. Apply the timing for the actual operation. Decree 2007-663 Articles 4-5
   require filing at least one month before covered supply/import operations;
   a request for missing material restarts the period on receipt of the
   additional material. After the complete one-month period without an ANSSI
   response, the declared operations may proceed; ANSSI can also issue an
   earlier attestation. Article 8 extends those periods to two months for
   cryptology services and exports outside the EU. A receipt alone is not an
   authorization to disregard the applicable period or a security approval. [18]
5. Complete Apple's documentation process for the actual France-enabled app
   and binary. Retain the approved declaration and the Apple-issued code,
   configure the matching plist answer, and verify the packaged binary and
   actual availability before release. [9][11]

Excluding France is a distribution decision and is not necessary to avoid the
two **BIS** filings. It does not establish that a different channel is outside
French rules. No declaration, exemption decision, past-distribution clearance
or store change is claimed by this document.

[21]: https://demarche.numerique.gouv.fr/commencer/declaration-relative-a-un-moyen-de-cryptologie

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
4. Complete Apple's questions for the actual iOS/macOS builds and distribution;
   record the France decision, historical/channel review, questionnaire result
   and any Apple-issued code. Apply the upload checks below to the final
   packaged app; source-plist checks alone do not validate it.
5. Reassess when crypto, dependencies, extension interfaces, product positioning
   or distribution changes.

The source-evidence tool generates engineering evidence. Passing it is not
permission to upload, proof of live App Store Connect state, or completion of
the pending distribution review. It does not email authorities, file a report,
request CCATS, submit an app or change store territories.

### Apple upload evidence

The machine-readable release decision is
[`apple-export-policy.json`](apple-export-policy.json). Its
`france.prior_distribution_review` and `testflight.distribution_review` are
currently **pending**. The existing `false`
source-plist values express the intended outside-France route, not a completed
review. The live upload and external TestFlight gates block their respective
pending reviews; source and offline artifact checks can still run. Do not
change a pending value merely to make a gate pass.

The publication gate must enforce these requirements, separately from ordinary
source checks:

- **Outside-France/no-documentation route:** a completed review of historical
  French distribution and all relevant channels; live, fully paginated App
  Store Connect availability showing France excluded; and the final packaged
  app's plist matching the policy's `false` answer without an export code.
  The live response cannot establish whether previous French customers or
  other channels still receive the app, so retain that separate review.
- **Approved-documentation route:** an Apple-issued code in the final packaged
  app, a matching approved App Store Connect encryption declaration for the
  correct app and distribution, and a matching `true` plist answer. A
  nonempty string or a historical approval for a different declaration is
  insufficient. Complete the applicable French process before relying on
  France-enabled documentation.
- **Both routes:** retain the exact source revision, binary identity and
  artifact hash with the policy, inventory and live check results. Recheck
  current availability at upload; a saved response is historical evidence.

These are required checks, not a claim that the current build, availability,
questionnaire or policy review has passed them. An upload gate cannot make a
government classification or prove that a human's supplied answers are true.

### Completing the structured policy

Record the actual evidence and responsible review before updating these fields.
An evidence reference should identify a retained decision or document, with its
scope and date; a filled-in reference is not itself proof of that decision.

| Policy field | Interpretation |
| --- | --- |
| `reviewed_on`, `bundle_id` | Review date and exact application identity. A review date does not establish that a later artifact or distribution change is covered. |
| `uses_non_exempt_encryption` | Expected boolean in both source and packaged plists, based on the completed Apple assessment. It does not say whether encryption exists. |
| `documentation.status`, `reference`, `compliance_code` | `unreviewed` blocks upload. `not_required` records the substantiated no-documentation route with a `null` code. `approved` requires the actual Apple-issued code and retained approval evidence; the live gate verifies the matching declaration. |
| `france.store_availability` | Intended App Store state, `excluded` or `included`, which the live gate compares with the explicit French territory record. It does not restrict TestFlight or establish past availability. |
| `france.prior_distribution_review`, `reference` | Leave `pending` until history and relevant channels have been reviewed. Use `no_prior_distribution` only with evidence supporting that conclusion. Use `covered` when French distribution is covered by the documented compliance route; this requires the approved-code route, including French coverage in the live declaration. |
| `inventory_sha256`, `pubspec_lock_sha256`, `reviewed_source_sha256` | Bind the policy to the inventory, dependency lock and reviewed source files. A change requires reassessment before refreshing fingerprints. Matching fingerprints establish source consistency, not correspondence with an uploaded binary. |

### Running offline and live artifact checks

Run these commands from the repository root, replacing the example artifact
paths with the exact release files. The tool accepts an iOS `.ipa`, a macOS
`.pkg`, or a `.zip` containing one main application. Inspecting `.pkg` requires
macOS and `pkgutil`.

```sh
python3 tool/apple_export_preflight.py --platform ios --check-artifact \
  --artifact /absolute/path/to/CrispCloud.ipa \
  --output build/export-compliance/ios-artifact.json

python3 tool/apple_export_preflight.py --platform macos --check-artifact \
  --artifact /absolute/path/to/CrispCloud.pkg \
  --output build/export-compliance/macos-artifact.json
```

`--check-artifact` needs no App Store Connect credentials or network access. It
checks the policy fingerprints, source and packaged encryption declarations,
bundle identity, version/build and target platform, and records artifact and
plist hashes. Pending distribution reviews do not turn that offline result
into permission to distribute. It does not establish signing validity, inspect
all executable crypto, or prove which source produced the binary.

For the live preflight, provide the real API key identifiers and the path to
the private `.p8` file through the environment. `ASC_APP_ID` is an optional
additional identity check; set it to the reviewed app ID when known. The tool
also needs OpenSSL for API authentication. These example values are
placeholders, not credentials or approval evidence.

```sh
export ASC_KEY_ID='YOUR_KEY_ID'
export ASC_ISSUER_ID='YOUR_ISSUER_ID'
export ASC_KEY_PATH='/absolute/path/to/AuthKey_YOUR_KEY_ID.p8'
export ASC_APP_ID='YOUR_REVIEWED_APP_ID'

python3 tool/apple_export_preflight.py --platform ios \
  --artifact /absolute/path/to/CrispCloud.ipa \
  --output build/export-compliance/ios-live-preflight.json

python3 tool/apple_export_preflight.py --platform macos \
  --artifact /absolute/path/to/CrispCloud.pkg \
  --output build/export-compliance/macos-live-preflight.json
```

Without `--check-artifact`, the tool first requires the completed policy review,
then checks the same artifact and performs authenticated **GET-only** requests
for current app identity, fully paginated availability and any required Apple
declaration. It does not upload, submit, change territories or file documents.
The current pending France history review stops this mode before API access.
Missing availability, including the absence of an `appAvailabilities` resource,
does not pass as France exclusion. Retain the output with the artifact, build
logs and release evidence; run the live check again immediately before upload.

### External TestFlight: separate recipient review

The `testflight` object records a separate distribution decision. Its current
values are `distribution_review: "pending"`, `reference: null`,
`external_group_ids: []` and `allow_public_links: false`; they intentionally do
not authorize external distribution. The normal policy/history checks must
also pass before [`tool/testflight_external.rb`](../tool/testflight_external.rb)
can proceed.

| TestFlight field | Required completed review |
| --- | --- |
| `distribution_review` | `no_france` means the reviewed recipients exclude France. `france_covered` means the applicable French process is covered and the Apple-approved-code route is used. |
| `reference` | Evidence identifying the intended recipients, distribution scope and basis for the selected conclusion. A private group or email address alone does not establish a recipient's location. |
| `external_group_ids` | Nonempty, unique allowlist of exact App Store Connect external group resource IDs for this app. A group name is not an identifier or an authorization. |
| `allow_public_links` | Must be `false` for `no_france`, and the live group must explicitly have public links disabled. For `france_covered`, an enabled public link is permitted only when this field is explicitly `true`; the guard does not enable links. |

Select one reviewed ID with `TESTFLIGHT_GROUP_ID`, or the external TestFlight
workflow's `group_id` input. If omitted, the script can select the allowlist's
sole ID; multiple reviewed IDs require an explicit selection. `TESTFLIGHT_GROUP`
and the workflow's `group` input are optional exact-name cross-checks only.
They cannot discover a group, substitute for an allowlisted ID or create one.

After the evidence is complete, this example uses the API environment above
to distribute an already uploaded macOS build. Replace the build and group
placeholders with the reviewed values. This command can create missing test
instructions, assign the build to the group and submit it for beta review;
unlike the Python preflight, it performs those App Store Connect writes.

```sh
export ASC_PLATFORM='MAC_OS'
export ASC_BUILD_NUMBER='REVIEWED_BUILD_NUMBER'
export ASC_BUILD_ID='REVIEWED_APP_STORE_CONNECT_BUILD_ID'
export TESTFLIGHT_GROUP_ID='REVIEWED_EXTERNAL_GROUP_ID'
ruby tool/testflight_external.rb
```

For an iOS build, use `ASC_PLATFORM='IOS'`. The guard verifies the selected
external group belongs to this app, its public-link state, and the uploaded
build's identity, processing state and encryption answer before every write.
The marketing version and build counter come from the reviewed checkout's
`pubspec.yaml`; `ASC_BUILD_NUMBER` must equal that counter, and the live build's
platform and marketing version must also match. `ASC_BUILD_ID`, or
the workflow's `build_id` input, selects an exact build ID. It may be omitted
only when the complete response contains one matching candidate. Ambiguous or
partially paginated results never silently select the newest build.
For the non-exempt route it also checks the build's matching approved Apple
declaration. `france_covered` additionally requires
`availableOnFrenchStore=true` in that declaration, even if the App Store
storefront itself is excluded. An unknown public-link state or a changed group
blocks further writes. These checks are repeated preflights, not an atomic
transaction or proof of every tester's location.

**Uploaded-build provenance remains a separate requirement.** A matching
`usesNonExemptEncryption` boolean, app ID or build number does not prove that
the uploaded binary was built from this branch or contains its crypto fixes.
The TestFlight guard does not download and compare that binary. Retain the
exact artifact hash, source commit, dependency/build evidence and upload record
that connect the reviewed artifact to the selected App Store Connect build.
Source review and a passing API check cannot replace that release evidence.

### Observed store blocker (2026-11-07)

The repository's 2026-11-07 record states that the signed macOS `1.1.0 (10)`
package built from `79dbb56` reached
`altool --validate-app` but Apple rejected it with **ITMS-90592 / 90592**
(*Invalid Export Compliance Code*). The package contains
`ITSAppUsesNonExemptEncryption=true` and no
`ITSEncryptionExportComplianceCode`, while App Store Connect app `6789570314`
had no app encryption declaration for the app at that time
(`GET /v1/appEncryptionDeclarations?filter[app]=6789570314` returned an empty
list). That initial validation attempt did **not** upload the package. The
later build-specific record below describes a subsequent upload using the
changed plist answer.

A declaration create request with `containsProprietaryCryptography=false`,
`containsThirdPartyCryptography=true` and `availableOnFrenchStore=false` was
then rejected with HTTP 409:
*"Cannot create appEncryptionDeclarations unless either
containsProprietaryCryptography is True or containsThirdPartyCryptography and
availableOnFrenchStore are both True."* This input-validation response is
consistent with Apple's no-documentation route for those supplied answers. It
does not establish that the answers accurately describe CrispCloud, that France
was excluded in the actual availability settings, or that Apple or a government
approved the classification. This audit has not reproduced that historical
request or treated it as current live-account evidence.

**Recorded intended route (2026-11-07), still conditional:** exclude France
from App Store distribution and use `ITSAppUsesNonExemptEncryption=false` in
the iOS and macOS plists, with no `ITSEncryptionExportComplianceCode`. The
complete inventory must support the non-proprietary answers, and the pending
historical/channel review plus live availability must substantiate the France
decision. The 2026-11-08 review preserves those boolean values without claiming
these external facts are established. Before enabling France, complete its
applicable declaration/documentation route; before adding proprietary or
non-standard crypto, reassess both US and Apple requirements. The BIS 5D992.c
assessment remains separate from Apple's plist answer.

**Later build-specific record, incorporated from PR #35:** macOS `1.1.0 (10)`
was subsequently uploaded with `ITSAppUsesNonExemptEncryption=false`. The
record says App Store Connect had no `appAvailabilities` resource for the
still-unreleased app when checked, so it did not establish that France was
excluded. This audit has not independently verified that uploaded binary or
live account state. Treat its outside-France answer as conditional: establish
the actual exclusion and complete the historical/channel review before App
Store submission or external TestFlight distribution. The new upload gate
rejects missing availability evidence; absence of a resource is not evidence
of an excluded territory.

If France is enabled instead, do **not** reuse that build 10 artifact: complete
the applicable French process and Apple declaration with
`availableOnFrenchStore=true`, obtain the Apple-issued code, set the matching
plist answer to `true`, and upload a new build. The source fixes in this audit
also require a newly built artifact; an already uploaded build does not gain
them when this branch changes.

This audit branch advances the source version to `1.1.0+11` for that rebuilt
artifact. On 2026-11-08, build 11 was built, passed the live App Store Connect
preflight, uploaded to App Store Connect, assigned to the reviewed external
TestFlight group `b044f8c9-394b-47dd-a470-796fd052580a`, and submitted for Beta
App Review (`WAITING_FOR_REVIEW`). Build 10 was expired so it could not remain
the active review in the same train. These are operational records, not an
Apple approval or a legal classification.

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
Questionnaire result/evidence for this release:
France declaration/exemption or substantiated distribution exclusion:
Historical French downloads and continuing updates/redownloads review:
TestFlight and other distribution channels review:
Current full App Store Connect availability evidence and retrieval time:
Packaged app plist, app/build identity and artifact hash:
Apple compliance code, only if actually issued:
Matching approved declaration and live verification, if required:
Responsible exporter/reviewer and decision date:
```

## 6. Applied store evidence (2026-11-08)

The following live App Store Connect state was applied and read back on
2026-11-08 for app `6789570314` (`com.CrispStrobe.cloud`):

- App availability was created with the full territory list. France (`FRA`)
  is explicitly `available=false` with content status `CANNOT_SELL`; all
  other territories were submitted as available. The API returned the full
  territory-availability set for the app.
- The app has two App Store versions, macOS and iOS `1.0.0`, both in
  `PREPARE_FOR_SUBMISSION`; there is no released App Store version and no
  public storefront listing. This establishes the current no-prior-App-Store-
  distribution basis, not a prediction about future distribution.
- The previous external TestFlight group with a public link has had its public
  link disabled. A new invitation-only external group
  `b044f8c9-394b-47dd-a470-796fd052580a` was created and contains exactly the
  project owner (`cstr+beta@mailbox.org`), who is outside France. The old
  public-link group is not used for build 11.
- These are live-state records. Re-run the preflight immediately before any
  upload; the evidence is not a legal opinion and does not establish future
  tester locations.

## Official sources

Apple, ANSSI, French legislation and cited EAR text rechecked 2026-11-08. BIS
regulation pages displayed an eCFR currency date of 2026-11-07. The existing EU
assessment cites the consolidated text dated 2026-09-21; its source review and
the dependency-format references were recorded on 2026-11-07.

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
17. [LCEN Article 30: use, authentication/integrity and confidentiality supply/import](https://www.legifrance.gouv.fr/codes/section_lc/JORFTEXT000000801164/LEGISCTA000006136109/).
18. [Decree 2007-663: Articles 4-5 and 8 timing; Annex I exceptions](https://www.legifrance.gouv.fr/loda/id/JORFTEXT000000646995).
19. [ANSSI: procedures and the request for grand-public status](https://cyber.gouv.fr/reglementation/reglementation-identite-confiance-numerique/controles-reglementaires-cryptographie/controle-moyen-de-cryptologie/controle-rglementaire-cryptographie-demarches/).
20. [Apple: availability changes, continuing updates and redownloads](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-for-your-app-on-the-app-store).
21. [Current ANSSI declaration portal and requested supporting documents](https://demarche.numerique.gouv.fr/commencer/declaration-relative-a-un-moyen-de-cryptologie).
22. [ANSSI: current forms and filing route](https://cyber.gouv.fr/reglementation/reglementation-identite-confiance-numerique/controles-reglementaires-cryptographie/controle-moyen-de-cryptologie/controle-reglementaire-cryptographie-formulaires/).
