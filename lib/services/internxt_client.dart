// internxt_client.dart — Flutter app integration shim.
//
// Phase 6.c: the embedded ~4400-line protocol monolith here was
// replaced with a dependency on the published internxt_client
// package (hosted dep on pub.dev, see pubspec.yaml). Local dev can
// still pin to ../internxt-dart via a gitignored pubspec_overrides.yaml.
//
// What this file used to contain (now gone):
//   - InternxtCLI class + handlers (~1700 LOC) — dead code in the
//     Flutter app, only referenced by its own main()
//   - InternxtClient + crypto + auth + drive + upload + download
//     code (~2620 LOC) — replaced by the package
//   - ConfigService (~270 LOC) — replaced by the package + a
//     SharedPreferencesStorage impl in internxt_flutter/
//   - InternxtFileSystem subclasses (~45 LOC) — dead code, only
//     used by the dead InternxtCLI's WebDAV mount commands
//
// What stays here:
//   - A re-export from the package so existing imports of this
//     file ('internxt_client.dart' show ConfigService etc.) keep
//     working without a flag-day refactor across cloud-dart.
//   - kIsWeb-aware URL constants for the Vercel proxy paths used
//     by the Web build.
//
// See AUDIT_6B.md in the internxt-dart repo for the full audit
// that drove this rewire.

import 'package:flutter/foundation.dart' show kIsWeb;

export 'package:internxt_client/internxt_client.dart';

/// Web build routes API calls through Vercel proxy paths to avoid
/// CORS / mixed-content issues with the Internxt gateway. Native
/// builds hit the gateway directly via the published library's
/// defaults.
class InternxtUrls {
  static String get networkUrl =>
      kIsWeb ? '/api/internxt-network' : 'https://gateway.internxt.com/network';

  static String get driveApiUrl =>
      kIsWeb ? '/api/internxt-drive' : 'https://gateway.internxt.com/drive';
}
