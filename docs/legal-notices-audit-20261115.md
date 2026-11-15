# About, trademarks and bundled notices — 15 November 2026

## Product names

Microsoft's [Trademark and Brand Guidelines](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks)
permit truthful descriptive references such as “Word documents”, ask for a
trademark footnote, and prohibit implying endorsement or using its logos without
permission. This is Microsoft's published policy, not a determination of every
jurisdiction's trademark law. A notice does not grant permission to copy logos,
fonts or software, or establish complete file-format compatibility.

CrispCloud retains descriptive format labels and its own generic editor icons.
The existing licences page displays one central ownership/non-affiliation
paragraph. Buttons, filenames and document canvases do not acquire repeated
symbols, popups or disclaimers. Genuine third-party logos/assets require their
own grants. The About source button now links to CrispCloud and its reported
revision, instead of the obsolete dart-cloud repository.

## Findings and corrections

The installed 6fcc4497 macOS build's generated NOTICES.Z was inspected, together
with the explicit runtime LicenseRegistry registrations and source asset rules.
The automatic file alone is not the entire runtime registry.

| Area | Finding / resulting coverage |
|---|---|
| Dart dependencies | Flutter reads package-root NOTICES, otherwise LICENSE. Existing manual registrations supplement fonts, archive adaptations, terminal, document engines and ebooks. |
| CrispCloud itself | LICENSE.txt was not automatically collected. Its full AGPL text and additional permission are now an explicit asset/registry entry, with a source link. The licence itself is unchanged. |
| Audio and iOS shell | Their existing root NOTICES/LICENSE files already preserve miniaudio/dr codecs and shell/native grants in the generated list. No duplicate registration added. |
| Office fonts | The fork's two one-line notices did not supply the full OFL texts. Supplemental notices now retain upstream licence texts and the copyright metadata of all 14 shipped font files. Their exact hashes are checked. Managed fork files were not altered. |
| Native storage | Previously had audited SPDX/hash inventories but no aggregate shipped to Flutter's collector. A root NOTICES now includes the exact retained evidence for 318 dependency versions across both locked graphs, including platform/build dependencies. Alternative licences remain alternatives; existing selected grants are preserved. |
| Windows PDFium | pdfx 2.9.2 selects the 97.0.4690.0 Windows archive by default. Its exact supplied LICENSE is now bundled and registered, with archive/licence/DLL hashes retained. This is the supplied core/package text, not certification of every transitive component in the DLL. |

`tool/generate_storage_notices.py --write` regenerates native storage notices
from the existing audited inventories and locked Cargo metadata. It rejects
changed evidence rather than substituting a generic SPDX description.
`tool/verify_bundled_notices.py` checks the notice/inventory/lock hashes,
complete inventory membership, PDFium notice hash and complete Office font
coverage. The existing CI evidence job runs this check without needing Cargo
or network access. Tests also reject omitted dependencies, truncated notices
and unreviewed lockfile changes.

## Remaining acceptance limits

**Do not describe the licence screen as a complete cross-platform legal audit.**
The focused corrections do not certify every platform binary, source offer,
linking/relinking obligation, dependency licence compatibility or store contract.
In particular:

- Audit the Windows PDFium DLL's transitive native libraries against its matching
  build/source configuration, and verify final Windows packaging preserves all
  resulting notices. The provided archive LICENSE alone is insufficient evidence
  to close that review. Version overrides must trigger a new review.
- Compare Android's resolved Maven/native runtime dependencies and Apple's
  packaged native frameworks with their actual notices/acknowledgements.
  Existing Android media notices and Dart package notices are useful coverage,
  rather than proof that all transitive native artefacts are accounted for.
- Repeat artifact/source correspondence checks for release binaries; a source
  inventory is not a per-platform binary reachability report. Existing SMB,
  ebook and MPL-source notices retain their separate corresponding-source terms.

The notice page is an attribution mechanism, not a warranty or a licence grant
for third-party trademarks. Fonts keep their own licences; product name
attribution and open-source licence obligations are separate concerns.
