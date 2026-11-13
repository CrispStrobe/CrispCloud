# Independent semantic inputs and oracle controls

The current snapshot schema is **6**. It adds relationship-bound font charset
declarations after a paired `02`/`01` font-table control exposed equal text and
run properties with different native rendering. Font-table part names, relationship
IDs, declaration order and hexadecimal case normalize; missing or changed
charsets and duplicate definitions remain observable. Unrelated orphan parts do
not supply metadata. Older schema-5 reports and exact measurement sources remain
unchanged; they must not be relabeled or replayed as though they had measured
this additional property. See [the source font fix](font-charsets.md).

The fidelity oracle now measures field instructions and nesting, symbol font/code
operands, resolved note references, bookmarks and hyperlink bindings separately
from cached visible text. Its snapshot version is **5**. Existing sealed reports
keep their original version and observations; they are not regenerated as new
goldens.

## Concrete blind spots closed

Four independently authored mutations returned an empty semantic difference list
with the oracle at `43027f9ddb626a4f8fccbef1c41c7f2ea9fccf47`:

| Authored source mutation | Why equal visible text was insufficient | New finding |
| --- | --- | --- |
| Change a Symbol glyph operand from `F061` to `F062` | Glyph identity is carried by `w:sym`, not `w:t` | `inlineContent` records the exact font and normalized hexadecimal code |
| Change `REF Target_A` to `REF WrongTarget` | The deliberately unchanged cached result hides a changed field target | Literal instruction text, nested field topology and story context are retained |
| Redirect the first footnote reference from note 19 to note 7 | Both note bodies still exist, so their text multiset is unchanged | Each anchor resolves to note content and definition identity |
| Delete `w:noBreakHyphen` | The prior text reader ignored the run control | The character is read as U+2011; optional hyphen U+00AD is also retained |

The original and new observations, baseline source hashes and exact fixture hashes
are retained in [counterexamples.json](evidence/independent-oracle-controls-20261113/counterexamples.json).
These controls do not invoke the Dart parser and do not derive expected values
from a converted output.

The regression suite also changes a hyperlink's referenced relationship while
keeping both URL relationships and the displayed text unchanged. It confirms
that relationship-ID renaming alone is harmless. Other controls cover quoted
field arguments, instruction text split across runs, nested instruction/result
boundaries, field placement in headers, simple fields, property-only decoys,
shared note identity with identical note text, and harmless note-ID renumbering.

## Authored inputs

[`independent_semantic_cases.py`](../tool/fidelity/independent_semantic_cases.py)
creates four deterministic source packages and a literal contract manifest in a
new directory. The committed inputs are in
[`test/fixtures/fidelity/semantic-contracts`](../test/fixtures/fidelity/semantic-contracts/contracts.json).

```sh
python3 tool/fidelity/independent_semantic_cases.py --output /absolute/new/input-directory
python3 -m unittest discover -s tool/fidelity -p 'test_inline_semantics.py' -v
python3 -m unittest discover -s tool/fidelity -p 'test_*.py'
```

All **170 Python fidelity tests** passed after this change, including eight new
test methods with multiple discriminating mutations. Some existing negative
tests deliberately print compile or schema failures; their successful rejection
is part of the test result.

The four authored contracts are:

- **Character controls:** hard and optional hyphens, actual tab versus paragraph
  tab-stop property, combining and supplementary Unicode, right-to-left text and
  preserved edge spaces.
- **Symbol glyphs:** two Symbol operands and one Wingdings operand, with ordinary
  punctuation/Unicode controls. A symbol's font/code pair is authoritative; no
  guessed Unicode equivalent is accepted as the source expectation.
- **Locked fields:** distinct cached results for `REF`, internal `HYPERLINK` and
  `QUOTE`, plus the referenced bookmark. Native evaluation or rewriting must be
  measured independently of the parser import.
- **Note joins:** definition order and numeric IDs differ from reference order.
  Correctness requires the reference-to-note association, not merely both bodies
  appearing somewhere in the output.

## Measurement boundaries

The oracle represents each font-specific symbol as U+FFFC in its text-position
view and retains its font/code operands in `inlineContent`. That placeholder is
an opaque oracle position, not a substituted document glyph. Offsets count
Unicode scalars and are not binary DOC character positions. Literal field
instruction whitespace and quotes remain significant; adjacent instruction runs
are coalesced without evaluating a field. Malformed or unfinished complex-field
boundaries remain findings rather than disappearing.

Note IDs are resolved to definition identity and accepted/rejected content.
Definition order is retained; this is not a claim that arbitrary reordering of
note definitions is equivalent. Existing story, table, style and revision
measurements remain separate. Hyperlink targets are inspected as strings and
relationships only; no link is followed.

These authored packages strengthen the independent measurement layer. They do
not by themselves establish binary DOC fidelity or native rendering equivalence.
An actual native DOC export, its native DOCX interpretation, our DOC import, and
each repeated bridge must be retained and compared separately before assigning a
runtime defect to the parser. The initial symbol investigation is not a claimed
runtime fix.

## Primary references

- [MS-DOC Character Properties](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/7022285b-9621-42e9-ad4d-4e02c115ef18)
  and [CSymbolOperand](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/d950b816-1794-4adf-bc44-1f1be8027f9e)
  distinguish the symbol flag, font index and character operand from ordinary
  stored text.
- [WordprocessingML SymbolChar](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.symbolchar)
  defines the glyph using `w:font` and `w:char`, independently of run fonts.
- The existing oracle's ISO/IEC 29500 content/property and markup-compatibility
  rules continue to exclude formatting properties and inactive alternatives from
  active text.
