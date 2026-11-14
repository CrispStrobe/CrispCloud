# Final portable NTFS qualification

Qualification source: **dec983b2fcb71dea7f90e1020c5d73e3f926a3f6**.

Fresh Dart VM execution, dart2js -O2 compilation, and actual Node execution
passed 18 groups and 2037 checks per target. Complete JSON and raw stdout are
identical, with no excluded fields. All 5048 selected tracked source paths
(4988 Dart files, package manifests/configuration, and NTFS corpus sources)
match the qualification commit before and after. All 606 actual compiler
inputs, the original primary package map, and Dart/Node executable bytes remain
unchanged. Production pubspec.yaml and pubspec.lock also match the recorded
pre-NTFS revision.

INDEX.json maps every stored receipt, log, and compressed binding to its exact
hashes. The principal receipt embeds the runner source and records exact
commands, versions, timings, exit codes, output hashes, source bindings, compiler
inputs, and scope limits. Large bindings and dependency paths use deterministic
gzip. Command logs and all stored/decompressed hashes were verified after saving.

The reader accepts three externally mastered images with 143 regular unnamed
path instances, and explicitly refuses one authentic ATTRIBUTE_LIST image.
External oracle totals of 204 unnamed paths and eight named streams are
separate from application extraction counts. Named streams remain metadata-only.
The external ntfsinfo security-descriptor content inspection remains incomplete;
its warning and fresh untouched control are preserved in the adjacent
external-fixtures evidence package. This is not Windows chkdsk, browser-engine,
WebAssembly, native-device packaging, or deployment qualification.

Any later commit requires its own execution attribution or a separately stated
input-equivalence proof. These executions remain attributed to the source above.

## Native-test correction equivalence

The separate [runtime/compiler equivalence receipt](runtime-equivalence-dec983b2-to-c2c17f7.json)
compares the executed revision above with corrected native-test revision
**c2c17f7a273c45760fd54b9e5a8fe3cd57b0d51b**. Their only non-documentation change
is the ordinary-dot control in test/archive_ntfs_reader_test.dart, which is
absent from all 606 actual portable compiler inputs.

Every actual compiler input, the primary package map, production manifests, and
Dart/Node executable bytes still match the original qualification. Every tracked
compiler input also has the same Git blob at both revisions. This supports reuse
of the portable results for the unchanged inputs at the corrected test revision.
No application or compiler was rerun for this proof: the portable executions
remain attributed to **dec983b2fcb71dea7f90e1020c5d73e3f926a3f6**. The native
suite's execution at the corrected revision is recorded separately.
