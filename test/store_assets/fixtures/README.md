# Store screenshot font fixture

`MaterialIcons-Regular.otf` is the unchanged full icon font previously declared
as the release asset `assets/fonts/MaterialIcons-Regular.otf`.

- SHA-256: `d9865b671a09d683d13a863089d8825e0f61a37696ce5d7d448bc8023aa62453`
- Copyright 2019 Google LLC. All Rights Reserved.
- Retained grant: [MaterialIcons_LICENSE.txt](../../../assets/fonts/MaterialIcons_LICENSE.txt)

The store screenshot widget test loads these bytes directly from its fixture.
It does not require the full font to be a Flutter application asset. Release
builds continue using Flutter's normal Material Icons font and icon tree shaking.
