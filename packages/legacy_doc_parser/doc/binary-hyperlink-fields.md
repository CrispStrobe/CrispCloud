# Internal hyperlinks with binary Word metadata

The retained native `bookmarks` case contained an internal `HYPERLINK` field
whose instruction ended in U+0001. Its actual `CFData` and `CPicLocation`
properties referenced a `NilPICFAndBinData` payload in the `Data` stream. The
payload contains an HFD hyperlink object with location `Beta`, agreeing with
the field's literal `\\l "Beta"` target. Treating that metadata marker as
instruction text made the whole field inert and discarded its navigation.

The writer now recognizes this bounded internal-location form. It requires
the exact referenced character position, a unique binary-data artifact, the
standard hyperlink CLSID, serialization version 2, a location-only object,
an exactly bounded NUL-terminated UTF-16 string, and agreement with the
literal field target. It replaces only the one metadata marker with a space,
preserving all UTF-16 positions used by field and story events. The resulting
Word field remains locked with its original cached display text. The original
instruction and binary payload remain in the evidence package, and a distinct
`binaryHyperlinkField` record explains the normalization.

This change neither reads a target nor generalizes arbitrary binary field
payloads. External monikers, additional serialized fields, conflicting targets,
unreferenced bytes, malformed strings and ambiguous data occurrences retain
the previous inert-evidence behavior. The regression suite includes quoted,
unquoted and non-ASCII targets, malformed binary extents and flags, and the
byte-identical native source from the old corpus. The source fixture's
provenance records the original DOCX, bridge DOC and retained archive.

This is a navigation-preservation fix. The native renderer's blue underline
and the cached result's explicit character properties require separate style
attribution; preserving the target does not establish a visual match.

The binary interpretation follows
[MS-DOC NilPICFAndBinData](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/5830324c-4f03-462a-b1f7-45707cd4036e),
[HFD](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/f41daffe-fb3b-4373-a071-d3e86c59409d),
[HFDBits](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/3bfc60ed-a4c6-4626-ac33-4639b8df10c7),
[MS-OSHARED Hyperlink Object](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-oshared/c0437222-4868-4660-81f8-6b7ee236d3f8)
and [HyperlinkString](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-oshared/1a9f6231-df63-4a95-b998-5c2b95b82965).
