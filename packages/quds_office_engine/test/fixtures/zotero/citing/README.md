# Native Zotero citing verification fixtures

These fixtures are generated with the real JavaScript citation processor
shipped by Zotero and the actual Zotero HTTP integration wrapper. They are
verification inputs, not a bundled production citation processor.

`processor-output.json` contains five complete-document scenarios and nineteen
formatted citations. The German Chicago scenario covers identical and changed
page locators, an intervening source, removal/introduction of a locator, and a
multi-source cluster. The numeric scenarios show the renumbering caused by a
new first source. The APA scenarios show a previous citation changing from
2024 to 2024a when another work by the same author and year appears. Every
scenario includes embedded synthetic CSL item data and the processor's full
bibliography output.

`protocol-contract.json` records seventeen command/response shapes obtained by
executing Zotero's unmodified `httpIntegrationClient.js` wrapper. Only its
`sendCommand` IPC boundary is substituted. The fixture checks that field codes,
text and note indexes are cached reads, fields are objects, document/field IDs
are included in command arguments, and completion clears the in-progress flag.
The Dart runner test replays this contract, including a reference to an unlinked
field that is subsequently deleted.

## Reproduce

Use Node.js to run `generate-fixtures.cjs` with two arguments: a directory
containing the seven pinned upstream files and an output directory. The
`sources` array in `processor-output.json` gives the exact source URLs, commits,
Git blob SHAs, SHA-256 digests, and license declarations. Save each response
under its `name` without normalizing or appending line endings. The generator
verifies the Git blob SHA of every file before executing anything.

```sh
node generate-fixtures.cjs /path/to/pinned-sources /path/to/generated-fixtures
```

Expected report:

```json
{"processorVersion":"1.4.61","sources":7,"scenarios":5,"formattedCitations":19,"protocolCommands":17,"result":"passed"}
```

Pins:

- Zotero: `992853536935dce3249a4ecf61d0d129883f85c4`.
- CSL styles: `d16ba6427ca3c5dada6578a6f7a0f98bd3ea03b3`.
- CSL locales: `14940e56f7c783e4173cafbd92e0f5856f2caa14`.

The generated outputs are from Zotero's bundled citeproc-js **1.4.61**, with
unmodified Chicago 18th edition notes/subsequent-ibid, Elsevier Vancouver and
APA styles. German output uses `de-DE`. The chosen Chicago style produces
`Ebd.` for the same page and `Ebd., 34.` for a changed page; exact punctuation
is a style decision, not hardcoded in the editor.

The third-party processor, wrapper, styles and locales are downloaded only for
test generation and are not included here. The processor's header permits
CPAL-1.0 or AGPL-3.0-or-later; Zotero's HTTP wrapper uses AGPL-3.0-or-later;
the CSL styles and locales declare CC-BY-SA-3.0. Their source metadata and
attribution are retained in the fixtures. The generator does not modify them.

These checks establish real processor results and the HTTP wrapper contract.
They do not certify a live Zotero installation, native dialogs, account access,
or Word's own Zotero refresh behavior. Those remain separate acceptance checks.
