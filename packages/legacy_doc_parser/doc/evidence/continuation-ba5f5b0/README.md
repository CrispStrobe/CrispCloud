# Corrected continuation acceptance at ba5f5b0

The exact clean source `ba5f5b0cdd540bd0c03f62aabc88faadd8660e0b` passed
**666 Dart tests, 110 Python oracle tests, formatting, fatal-info analysis,
corpus integrity and JavaScript document/media acceptance (47 media checks)**.
The independent Open XML SDK accepted **all 153 required DOCX outputs with zero
errors**, including all 24 new object/revision cases. Exact output inventories,
deterministic generation, unchanged inputs and positive/negative controls pass.

The [initial failure](../continuation-01b64ea/README.md) is retained unchanged.
The correction orders paragraph-mark revisions before character properties and
emits valid OLE identities linked to an actual VML shape. No case was removed
from the validator gate. `schema-report.json.gz` retains compiler, assembly,
source and output hashes plus every stage. `schema-validation.json.gz` retains
every validated output and its errors (none); `portable.log.gz` is the full log.

Native arc acceptance is recorded [separately](../metafile-arcs-24580b0/README.md).
The [OLE placeholder observation](../ole-placeholder-d4a19b9/README.md) retains
LibreOffice's suppressed label text rather than claiming a recovered preview.
These are scoped source/validity/behavior checks, not universal Word rendering
or editing fidelity. The complete repeated native corpus has its own receipt.
