# Independent app failure classification

The complete first 63-suite app run at `f7c831ffcf971bdd3e2919369954f31a173c72fa` ended unsuccessfully. All **20 error events** have been classified:

- **18 suite-loading errors** share the missing exhaustive `WmlUnderline` cases in `lib/widgets/office_editor_ribbon.dart`. Incoming canonical PR25 adds styles that the host switch did not name. `incoming_audit` owns this host correction.
- **2 runtime errors** share the generated damaged-compound fixture. Bulk conversion directly throws `CfbfException: Invalid compound root directory`; the conversion dialog cannot offer the text-only choice because initialization encounters that same unhandled exception, and its test subsequently cannot find the menu item. `qualification_setup` owns the canonical parser correction and deterministic regression.

There are **no remaining unclassified error events** in the completed raw stream. This is failed qualification; observed successes in the same run are not acceptance for the corrected source.

The parser defect is specific: `convertLegacyWord(recover:true)` and its plain-text helper catch `FormatException`, while the bounded compound reader may propagate the distinct `CfbfException` type from root-directory validation. The fixture preserves the complete referenced Word body and CLX but zeros only the root-directory sector. The same bounded recovery route must handle that typed malformed-container error, without broadening strict/default/DOCM behavior or changing size/work limits. The canonical owner received the exact fixture and stack.

A separate source-only enum scan identified the font-settings dropdown in `lib/widgets/office_editor_dialogs.dart`: it initializes from any imported underline style but offers only the original five styles. That violates Flutter's dropdown value invariant for the new styles. The underline UI owner is incorporating all styles and a real font-dialog unchanged-apply/save/reopen regression in `test/widget/office_font_fidelity_test.dart`. This static finding was not misrepresented as an executed failure.

No source, dependency graph, HEAD, or active gate was modified during this review. `classification.json` retains the exact raw-stream hash, per-error suite/test identities, and relevant print/stack events.
