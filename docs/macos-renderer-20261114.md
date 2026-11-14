# macOS startup renderer qualification

The signed universal app at runtime checkpoint `1ba3d652` passed credential
preflight but exited with SIGSEGV (139) on its first local startup. The macOS
crash report identifies `io.flutter.raster` in FlutterMacOS. Its log contains:

```
Impeller validation: The texture and its descriptor disagree about its size.
Impeller validation: Store action needs resolve but no valid resolve texture specified.
```

A second Impeller startup survived 30 seconds. This is an intermittent renderer
failure; the credential policy was ready before the crash.

## Mitigation and executed checks

`macos/Runner/Info.plist` now sets `FLTEnableImpeller` to false, selecting GPU
rendering through Skia Metal. The pinned Flutter 3.47.8 SDK reads that Boolean
in `FlutterDartProject.mm` and selects the backend in `FlutterEngine.mm`; this
is a supported engine setting. Requalify Impeller before restoring it. The
Skia choice does not establish Impeller-specific GPU or wide-gamut acceptance.

Two independently signed Skia Metal launches of the same Dart build survived
30 seconds each. Both logged the selected Skia Metal backend and completed
credential preflight without the texture errors.

The startup guard also rejects these exact errors when the process stays alive.
Four Python tests execute the real guard over isolated child executables:
healthy startup, missing credential preflight, early process failure, and both
texture-error variants. They pass, and every child is reaped. The release test
job includes these checks. Final rebuilt-app acceptance is recorded with the
integration receipts after signing and startup verification.
