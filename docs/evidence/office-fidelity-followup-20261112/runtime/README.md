# Reproducing this continuation

These archived scripts record the exact local acceptance procedure. Place them
in a scratch runtime directory with the pinned tools; the recorded absolute
paths describe the audited machine and can be replaced through the CLI's
explicit repository/output/SDK arguments.

Source acceptance uses Flutter 3.44.0 and cached Dart; host acceptance uses
Flutter 3.47.8. Set CI=true and suppress analytics before invoking the cached
Flutter tools. Source engine acceptance must finish before editor acceptance:
the editor's bookmark/content-control oracles also read engine outputs.

Run the engine and editor acceptance helpers against the clean implementation
commit. Editor mode requires the passed engine receipt. Then collect exactly
321 source outputs with run_source_external.py. Run the unmodified host gate
through run_host_acceptance_verified.py at its frozen implementation, then use
app_external_acceptance.py for the 296-engine + 62-host SDK snapshot and the
eleven-file native upload probe. The six-file run_host_tab_native.py helper
requires that accepted snapshot. Native runs are serialized.

The validator is compiled from the unchanged repository Program.cs with
DocumentFormat.OpenXml 3.3.0 and .NET SDK 8.0.428 / runtime 8.0.34.
The native runtime is the official LibreOffice 24.2.7.2 release through
LibreOfficeKit. Its archive, library, adapter, headers, compiler and Poppler
hashes are recorded in the provenance receipts. The unchanged adapter source
and prior setup instructions are also preserved in the consolidation evidence.
Do not update goldens, relax the renderer or replace original inputs to obtain
a pass.

Raw-log archives retain the original relative validation paths and byte hashes.
The source archive also retains intentional RED probes and the first parallel
editor sequencing failure; final acceptance uses the successful serial run.
Host tracked-tree.json.gz decompresses to the identical original before/after
snapshots recorded in its gate receipt.

A concurrent resumable checkpoint a62e396ce2e3966555f224a0cc234061fe8e72ce
added resumption.json and run_host_acceptance.py while final evidence was
being saved. Both original files are retained byte-for-byte. The completed
acceptance used the separately archived run_host_acceptance_verified.py
(original scratch filename: run_host_acceptance.py); its hash matches the
final host receipt. The resumption checkpoint is historical, not a replacement
for the passing final receipts.
