# CrispCloud inherited differences — supplemental disposition

This read-only review compares host implementation `07083d1983db87a9868c3e8ba0cda1efd283b445` with canonical Quds `b87f9d6c3a2532c9695024adf48ca9fbd3c0927a` and proves inheritance from frozen host main `553f3be64da9ad3c35730f1b6a67d79f1ac54b72`. All **14 unmanaged content differences** and **six host-only localization files** retain exactly their baseline Git blobs and modes. The **eight managed executable-bit differences** also retain exactly their baseline modes; their current content matches canonical.

**The original strict verifier still fails its `managed_non_parser_git_blobs_and_modes_identical` check.** This supplement explains the failure and inherited customizations; it does not alter the verifier, its result, or its gate. All 652 managed non-parser blob IDs match canonical. All 2,509 manifest byte hashes match the host, and the 1,857 managed parser entries retain their baseline inventory, bytes and modes.

Evidence: [original verification](delivery-verification.json), [complete original records](delivery-verification.details.json.gz), [baseline Git object proof](unmanaged-baseline-proof.json), and [this disposition as JSON](host-inherited-differences.json). The full original comparison includes 197 additional unmanaged mode-only observations; the fourteen entries below are its actual unmanaged content differences.

## Unmanaged content differences

Each listed host blob **and** mode is unchanged from `553f3be6`. The saved diffs run from canonical Quds to the host.

| Path | Classification and retained behavior |
| --- | --- |
| [packages/quds_office_editor/lib/src/editor_reports/quds_report_designer.dart](unmanaged-diffs/01-quds_report_designer.dart.diff) | **Report interface localization.** Localizes template menus, status and diagnostics; forwards the selected strings to preview and avoids translating custom template names. Optional translateActions defaults to existing behavior. |
| [packages/quds_office_editor/lib/src/editor_reports/render_report_data_explorer.dart](unmanaged-diffs/02-render_report_data_explorer.dart.diff) | **Report interface localization.** Localizes accessibility labels and row/column counts; takes text direction from the selected report language. |
| [packages/quds_office_editor/lib/src/editor_reports/render_report_designer.dart](unmanaged-diffs/03-render_report_designer.dart.diff) | **Report interface localization.** Localizes band captions, element placeholders and accessibility labels; includes direction in the label cache key. Small const/formatting differences are nonfunctional. |
| [packages/quds_office_editor/lib/src/editor_reports/render_report_inspector.dart](unmanaged-diffs/04-render_report_inspector.dart.diff) | **Report interface localization.** Uses shared localized element/inspector headings and font-face names while retaining document-defined names. |
| [packages/quds_office_editor/lib/src/editor_reports/render_report_preview.dart](unmanaged-diffs/05-render_report_preview.dart.diff) | **Report interface localization.** Adds an optional strings parameter with an English default; localizes empty/error/page/warning/accessibility messages and invalidates label/semantics caches on language changes. Report page painting is unchanged. |
| [packages/quds_office_editor/lib/src/editor_reports/report_designer_controller.dart](unmanaged-diffs/06-report_designer_controller.dart.diff) | **Report interface localization.** Keeps original notices plus structured family, error and imported-row values to localize displayed notices without parsing user names; localizes a property hint. Existing font import and report export work remains in place. |
| [packages/quds_office_editor/lib/src/editor_reports/report_designer_strings.dart](unmanaged-diffs/07-report_designer_strings.dart.diff) | **Report interface localization.** Extends English/Arabic with German, French, Spanish, Portuguese, Chinese, Japanese and Korean; adds count, diagnostic, template-value, element-title, font-face and notice helpers. Unknown messages and supplied user/provider values are preserved. |
| [packages/quds_office_editor/lib/src/editor_reports/report_element_painter.dart](unmanaged-diffs/08-report_element_painter.dart.diff) | **Report interface localization.** Adds an optional strings argument for crosstab/subreport placeholder frame labels; other element painting is unchanged. |
| [packages/quds_office_editor/lib/src/embed/office_uri_io.dart](unmanaged-diffs/09-office_uri_io.dart.diff) | **Host platform integration.** Uses url_launcher LaunchMode.externalApplication with Uri.tryParse instead of desktop Process.start commands. The public office_uri.dart wrapper and viewer scheme/navigation/host-callback checks are unchanged. |
| [packages/quds_office_engine/lib/quds_reports.dart](unmanaged-diffs/10-quds_reports.dart.diff) | **Nonfunctional export ordering.** Moves the report_shape.dart export one position relative to report_pdf_writer.dart; the exported library set is identical. |
| [packages/quds_office_engine/lib/src/opc/crypto/office_crypto.dart](unmanaged-diffs/11-office_crypto.dart.diff) | **Host Office package integrity hardening.** Authenticates the complete encrypted Office package before returning plaintext; validates integrity metadata and distinguishes KeyData salt size from password salt size. Existing writer files are accepted only when their legacy HMAC-key length produces a valid HMAC. |
| [packages/quds_office_engine/lib/src/pdf/widgets/pw_paint.dart](unmanaged-diffs/12-pw_paint.dart.diff) | **Redundant PDF nullability compatibility form.** Retains a nullable local face and duplicate null checks in the watermark path. An identical earlier guard returns whenever stampFace is null, so the extra null branch cannot change reachable rendering behavior. |
| [packages/quds_office_engine/test/arabic_pdf_export_test.dart](unmanaged-diffs/13-arabic_pdf_export_test.dart.diff) | **Equivalent test syntax adaptation.** Uses if (latin != null) latin instead of the nullable collection element ?latin. Both add the same non-null Latin fallback font; the assertions and PDF inputs are unchanged. |
| [packages/quds_office_engine/test/office_crypto_test.dart](unmanaged-diffs/14-office_crypto_test.dart.diff) | **Host integrity regression coverage.** Adds six existing host tests for ciphertext/size tampering, missing metadata and an independently constructed HMAC fixture, including distinct salt sizes and metadata rejection. The fixture explicitly does not claim complete Microsoft Office interoperability. |

## Six host-only files

All are under `packages/quds_office_editor/lib/src/editor_reports/`; all retain baseline blob and mode.

| File | Purpose |
| --- | --- |
| `report_asset_strings.dart` | Recognizes report package/font/shape/data asset messages and translates fixed templates while preserving file names and supplied details. |
| `report_data_error_strings.dart` | Translation tables for JSON/data-path/CSV diagnostics. |
| `report_font_extra_strings.dart` | Translation tables for font-wrapper, missing-glyf and family-name diagnostics. |
| `report_notice_strings.dart` | Translates known validation notices and enum terms, retaining supplied names and values. |
| `report_special_asset_strings.dart` | Translation tables for existing font, shape and bundled-template diagnostics. |
| `report_template_strings.dart` | Localizes bundled template categories, families and language labels; custom template titles/family names pass through unchanged. |

## Managed executable modes

These eight paths have canonical mode `100644` and inherited host mode `100755`. Their current blob IDs equal canonical, and their host modes equal frozen main. The existing updater preserves target permissions when its plan does not supply explicit modes; the existing `test_apply_without_source_modes_keeps_existing_permission_behavior` regression records that contract.

| Path | Content compared with host baseline |
| --- | --- |
| `packages/quds_office_editor/lib/src/core/input_bridge.dart` | Unchanged |
| `packages/quds_office_editor/lib/src/editor_pdf/pdf_font_faces.dart` | Unchanged |
| `packages/quds_office_editor/lib/src/editor_pdf/pdf_page_thumb.dart` | Unchanged |
| `packages/quds_office_editor/lib/src/editor_pdf/render_pdf_canvas.dart` | Unchanged |
| `packages/quds_office_editor/lib/src/embed/office_direction_keys.dart` | Unchanged |
| `packages/quds_office_engine/lib/src/fonts/font_subsetter.dart` | Updated to canonical; executable mode preserved |
| `packages/quds_office_engine/lib/src/pdf/pdf_document.dart` | Updated to canonical; executable mode preserved |
| `packages/quds_office_engine/lib/src/pdf/pdf_font.dart` | Updated to canonical; executable mode preserved |

The official sync byte checks and the auxiliary strict Git mode check answer different questions. The former passed; the latter remains false. No mode was normalized and no check was weakened.

## Compatibility with the incoming PDF and Zotero work

**No concrete new compatibility risk was identified in this bounded source review.**

### PDF watermark and CID encoding

No concrete new incompatibility identified. pwEmitStampLine has the same early return for null stampFace in both trees, making the host-only later null checks redundant. Incoming PdfEmbeddedFace.encoding is optional, with null explicitly retaining CID-equals-glyph identity encoding. pw_core.dart and report_pdf_writer.dart still construct faces without encoding; office_pdf_export.dart opts into the new encoding and emits its CIDs. The watermark continues to emit subset glyph IDs under the retained identity contract.

### Report localization

No concrete new incompatibility identified. The eight differing report files and six helper files change generated interface text and localization state. No report document schema, font embedding API or Zotero request/field format changes are introduced by these inherited differences. New PDF encoding remains optional for the unchanged report writer.

### URL launching and Zotero

No concrete new incompatibility identified. The inherited url_launcher adapter is behind the unchanged PDF viewer wrapper. The viewer still permits only http, https and mailto, honors preventLinkNavigation and prefers onOpenUri. Incoming font/CID work does not change those call sites; the Zotero engine/client paths are outside this adapter. No live platform launch or Zotero account acceptance is asserted.

### Office crypto and test adaptations

No concrete new incompatibility with the incoming PDF/Zotero code identified. The integrity change and six host regressions predate this recovery and are retained byte-for-byte. The Arabic fallback syntax is equivalent, and the reports barrel exports the same libraries. These inherited tests were inspected only; they are not additional test executions in the recovery totals.

The strongest shared-interface check is the PDF writer contract: the new optional `PdfEmbeddedFace.encoding` preserves the previous identity mapping when omitted. The unchanged widget/report constructors omit it, while the updated Office exporter explicitly supplies the new character-to-glyph mapping. The host-only watermark null checks occur after an identical non-null guard and therefore do not create a divergent reachable path.

## Method and limits

The baseline proof uses `git ls-tree -r -z` at the two exact host commits and compares mode, object type and blob ID for every listed path. Current host/canonical entries come from the preserved complete delivery verification. The content diffs and source call sites were read without running tests or changing either source tree, its index, the SDK or a harness. These observations do not add to fresh qualification totals or claim a full application build, live Zotero account, Word/LibreOffice, platform URL launch or keychain acceptance.

The original diagnostic files were read only. Their SHA-256 values at review time are:

- `delivery-verification.json`: `e410bd23b862ff88c407d1cc8db9c1b3cfee1879c2a9b5281139e15fd5865210`
- `delivery-verification.details.json.gz`: `d2dab368e12279c23341a112a4fd8d8473789247ce48662e102115a57947a53e`
- `unmanaged-baseline-proof.json`: `77320d4af46dc7d9e06a0bfc7eaec0f615e483f8f50dd8a2916b2c49d056c501`

No additional tests were run: this inspection found no concrete incompatibility that would justify expanding the frozen qualification scope.
