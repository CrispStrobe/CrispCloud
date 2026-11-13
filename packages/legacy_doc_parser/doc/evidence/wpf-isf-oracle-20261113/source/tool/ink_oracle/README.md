# Independent Windows WPF ISF author and oracle

This .NET 8 Windows console project uses the actual WPF
`System.Windows.Ink.StrokeCollection` implementation to author valid nonempty
Ink Serialized Format fixtures. It contains no parser/converter import and
no independent attempt to encode or decode ISF bits. It is an independent
runtime oracle for later portable-decoder work, not a Word rendering oracle.

Six independently authored controls cover a solid polyline, one-point dot,
alpha color and asymmetric elliptical tip, multiple colored strokes including
a rectangular tip, pressure-sensitive drawing, and signed half-Himetric
coordinate boundaries. Authored coordinates and widths use Himetric
(1/100 mm); the input DIP conversion is exactly the stated ratio `96/2540`.
The signed control deliberately includes half-unit values. Its actual reload
differences are recorded rather than replaced with assumed rounding results.

Each collection is saved with `compress=false` and `compress=true`, loaded
by WPF, saved a second time in the same mode and loaded again. The output keeps
all original/reloaded point coordinates, pressure values and metrics, drawing
attributes, bounds and file hashes. `RenderTargetBitmap` renders each stage
at 96 DPI with a fixed 32-DIP translation on an opaque white canvas and a
software-rendering preference. PNG and raw pixel hashes, changed pixel counts
and visible bounds remain separate from decoded-coordinate comparisons.

The program requires the expected stroke/point counts, visible non-clipped
ink and unchanged original objects. It does not require serialization bytes,
attributes or rasters to remain identical: any observed normalization is
evidence. `summary.json` records the exact checked-out commit, Windows/.NET/WPF
assembly identity and GitHub run identity. `manifest.json` binds every other
output file's bytes and SHA-256. The inspected source reference below is not
silently substituted for the installed WPF assembly's actual build identity.

On Windows with the .NET 8 SDK:

```powershell
cd tool/ink_oracle
dotnet build InkOracle.csproj --configuration Release --output ../../build/ink-oracle-bin
../../build/ink-oracle-bin/InkOracle.exe NEW_OUTPUT_DIRECTORY (git rev-parse HEAD)
```

The helper's local `global.json` selects SDK 8.0.428 without changing the
repository's other .NET validation tools. Installed WPF runtime patch and
assembly identities are recorded from the actual process.

The checkpoint workflow is limited to pushes on
`checkpoint/ink-oracle-20261113` that change this helper or its workflow. It
also supports explicit dispatch. It uploads raw outputs and build/runtime
logs even if the oracle fails. Collected artifacts will be verified against
the successful run's commit and hashes before any fixtures are retained.

Primary references:

- [WPF StrokeCollection.Save](https://learn.microsoft.com/en-us/dotnet/api/system.windows.ink.strokecollection.save)
- [WPF StrokeCollection stream constructor](https://learn.microsoft.com/en-us/dotnet/api/system.windows.ink.strokecollection.-ctor)
- [WPF StylusPoint and pressure](https://learn.microsoft.com/en-us/dotnet/api/system.windows.input.styluspoint)
- [WPF DrawingAttributes](https://learn.microsoft.com/en-us/dotnet/api/system.windows.ink.drawingattributes)
- [RenderTargetBitmap](https://learn.microsoft.com/en-us/dotnet/api/system.windows.media.imaging.rendertargetbitmap)
- [Inspected WPF source revision](https://github.com/dotnet/wpf/tree/e7acf467c05e51901b17684b1f2c330e7dc5fc4d/src/Microsoft.DotNet.Wpf/src/PresentationCore/MS/internal/Ink/InkSerializedFormat)
