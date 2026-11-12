// Independent fixtures generated with Python 3.12 tarfile: USTAR, GNU and PAX.
// Deflate/base64 keeps the checked-in fixtures compact; no production TAR writer
// is used to construct these reference headers.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

Uint8List referenceTar(String kind) => const ZLibDecoder().decodeBytes(
  base64Decode(_references[kind]!),
  verify: true,
);

const _references = <String, String>{
  'ustar': 'eJzt0b0OgjAYheHOXgVXAC20Mju6Gm+gCfUnQSC1RC7fKg7GRDZw8H2G9vuSJj3JSTMxOxmVRj5vVRbjrsb9RShtcl2WUsdZKlmoXCRm/mhC9NdgfYzS3hrnJ94dfdt3SwRaVpqdXF23aRjCbH88Cl7rif61+ug/Vyb2L2dL9ObP+982letcPJqQ7De75OKCrWywyeE8hN671a8DAgAAAAAAAAAAAAAAAPjqDrBOMc4=',
  'gnu': 'eJzt1DFuwjAUBuA3cwpfoI4d7HiFsVLUoeIClnARApzIdVTGHqx7xx4JTNNUQoh2ihn4v8GOpUh+8f9iXtDoRGK0+J6lmfZr2a9/kFS6VMYIlZ6FFKUuienxSyPqXqMNjFHz5l34471VaLo2R0F58YIXs7rxq3rtNyPtMWR8ZU49Yc56IXWHqVL+9Uj1nBnyv1O82KbwH2x+PO7jrb8ecuR/+qkrJej9tOGHfbq4/5Wkw6+vTzE1lVbERI4DuPP7/9EvXevS4CNbzJ/ZzkW7tNGyl/U+dsFNbl0gAAAAAAAAAAAAAAAAAAAA/OsIl7qcpA==',
  'pax': 'eJzt1N1OgzAUB3CueYq+wKCnn9vFEr3TO2N8gUYqLtnYgiXy+Ba2anaxZYkZLvH/u6C0h8KhX0WZXR2PrOZjSVbu67SvH2SktFDWchXvOXFJImP6+qllWfcRXBtT2X42vj3zXN1uu90UCU2rKIvy7sn1D95VZ///F9Icnyi5NuZoLcT5F0JlrL9OOsfS/E/xrRtEc9atqiUJqbSx8wXPY0sdW1KdRK4N6xq38ctxj8y6Cw396rHfuHdm9YVyydkmrGI/smlNFN8JDlG3j5pFii7m1mglBQ3R1xTVh2h6CeUkDdu58L4syvW2qWduekXoQ/7Xs/5jioEYxt6oM+e/ouPzXwqr4vk/yZ785+f/Y1P5nY+XJrCX+2e28cFVLjj2tupD1/obWqoAAAAAAAAAAAAAAAAAAABwwhdgV9+V',
};
