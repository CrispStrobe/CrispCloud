# Resolved paint on editable textboxes

Textboxes now retain the solid-fill opacity, simple-line opacity, dash, join
and cap, and simple offset-shadow properties already represented by the
OfficeArt model. The previous textbox writer emitted only fill/stroke colors
and explicit border width. The shape writer's existing paint serialization is
shared, with independent guards for fill, stroke and shadow: an unresolved
fill does not discard a resolved line, and an unresolved shadow is not emitted
as an apparently complete simple shadow.

Explicit zero opacity, disabled line/shadow flags, zero offsets and absent
properties remain distinct. These changes do not materialize an absent line
width, relax the general unsupported-property guard, or flatten pattern,
texture, picture or gradient fills. Editable text and original binary
artifacts remain retained with the existing partial-formatting limitation.

## Frame relationship

Dash patterns and simple offset shadows do not change a simple border's
outside thickness. The source-to-target frame calculation therefore applies
to these resolved cases as well as solid borders, retaining the original
source coordinates in the model and evidence. Unsupported shadow properties,
other shadow types, compound borders and the other guards documented in
[textbox-frame-borders.md](textbox-frame-borders.md) remain excluded.

This follows the pinned native importer's
[`GetEscherLineMatch` and `MatchSdrBoxIntoFlyBoxItem`](https://github.com/LibreOffice/core/blob/2c87e51eeaa2b413ff4ae097b2705eea1995d8e5/sw/source/filter/ww8/ww8graf.cxx):
the outside half-width is calculated before dash mapping, while shadow
properties are assigned separately. The
[VML text-frame importer](https://github.com/LibreOffice/core/blob/2c87e51eeaa2b413ff4ae097b2705eea1995d8e5/oox/source/vml/vmlshape.cxx)
uses the emitted frame rectangle directly and maps fill opacity to the frame's
background transparency. Source flags keep the independent use-bit semantics
specified for [fill](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/baf2613d-c676-43c8-8077-828bdcc70dca)
and [line](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/b359a9d1-941b-49ad-8462-7c0bb894d125).

## Independent controls

`tool/fidelity/textbox_paint_probe.py` authors small OOXML inputs independently
of the DOC converter, then retains original, native binary, baseline-parser
and candidate-parser renders separately. Cases run sequentially with fresh
native profiles. The reports record source/compiler/tool/font identities and
lossless 72-DPI RGB rasters, and refuse changing source inputs. An initial
probe correctly stopped before native measurement when Dart created the
baseline's previously absent package configuration during compilation; that
failure is retained separately from completed runs.

The completed controls establish exact binary-to-parser renders for 50% and
0% solid fill opacity, the 2-point dashed border, and an opaque simple offset
shadow. The first two previously had raster differences; the latter two also
had 1-point word displacement. Each corrected control matches its regenerated
binary exactly through three repeat imports. The opacity and dash controls
also remain exact to the first parser import. The opaque shadow has a native
bridge raster change in the first repeat, which remains separately recorded.
Plain, disabled-shadow and line-opacity controls retain their previous exact
output. The line-opacity control does not prove that the
native bridge stores transparency on text-frame borders; the separate model
tests protect its serialization.

The translucent-shadow source is a retained counterexample. The native bridge
stores color `0x7F665544`, whose high byte is not a resolved OfficeArt RGB color
operand, and changes unequal x/y offsets to their mean. Its color remains
unsupported rather than interpreting unknown flags as RGB or claiming complete
shadow preservation. The opaque-shadow result is qualified against its exact
binary input; the native export's literal offset normalization remains in the
retained source properties even where the original render matches.

The Word14 source remains a separate follow-up. Its six textboxes use solid,
pattern, texture, picture and shade-title fills plus absent border widths and
other properties. None of those unresolved cases is certified by these small
resolved-paint controls, and the original failures and reviewed goldens are
unchanged.
