# Distribution profiles

The macOS build and signing policy has two explicit profiles. This separates
filesystem permissions from dependency licensing; changing one does not settle
the other. The project's own AGPL-3.0 licence remains unchanged.

| Profile | Host access | Optional FUSE integration |
| --- | --- | --- |
| `appstore` (default) | App Sandbox, user-selected files and bookmarks | Refused; no helper compiled or bundled |
| `github` | Host runs without App Sandbox, with hardened runtime | Only with explicit compile-time `--fuse` opt-in |

The current App Store dependency boundary excludes the removed LGPL libsmb2
backend and the optional LGPL-header FUSE helper. Existing iOS Bison exceptions
and native notices remain complete. This targeted packaging policy is not a
claim of blanket App Store approval or an audit of every upstream source byte.
Approved GPL/LGPL components may be considered for the GitHub edition, with
the applicable source, notices, modification/relinking and distribution duties.
No removed dependency is restored merely because the channel permits it.

## Build

```sh
python3 tool/macos_distribution.py build --profile appstore -- --no-pub
python3 tool/macos_distribution.py build --profile github -- --no-pub
python3 tool/macos_distribution.py build --profile github --fuse -- --no-pub
```

`--flutter /path/to/flutter` selects a toolchain. Arguments after `--` are
forwarded to Flutter. The wrapper supplies `CRISP_DISTRIBUTION` and
`CRISP_ENABLE_FUSE`, temporarily overrides only the Runner target's release
entitlements, and restores its generated override even if the compiler fails.
The Finder extension retains its own sandbox. A native build phase rejects
mismatched Dart/native profiles and writes signed `CrispDistribution.json`
metadata into the application resources. A subsequent default build removes
any old FUSE helper.

Release packaging verifies the actual signed host entitlements, helper
presence, profile metadata and the existing component exclusions. It does not
trust a filename or the metadata alone. Local signing selects the same profile
from the built app. For example:

```sh
bash tool/sign_macos_local.sh build/macos/Build/Products/Release/CrispCloud.app
python3 tool/macos_distribution.py verify --profile github \
  --app build/macos/Build/Products/Release/CrispCloud.app
```

The GitHub Release workflow selects `github --fuse`; App Store/TestFlight macOS
builds select `appstore`. iOS App Store builds explicitly disable FUSE. Existing
release tags are immutable: `v1.3.4` retains its earlier sandboxed macOS recipe;
these profile changes apply to subsequent builds of this source.

## Access, signing and data

Unsandboxed does not mean administrator access. macOS privacy permissions,
Full Disk Access approval, Unix permissions and SIP still apply. iOS and browser
builds keep their platform sandbox; Linux/Windows keep normal account and OS
access controls. See [Apple's sandbox requirement](https://developer.apple.com/documentation/security/app-sandbox)
and [file access controls](https://support.apple.com/guide/mac-help/mchld5a35146/mac).

GitHub macOS app/DMG and CLI releases now use the retained Developer ID identity
and shared notarization key, with mandatory signature checks. The app and Finder
extension have their own Developer ID profiles, preserving the signed application
identifiers needed for Keychain access. See [public signing](public-signing.md)
for the configured secret names, live acceptance and CLI runtime exception.
The registered-Mac development signing script remains for local testing.

Sandboxed and unsandboxed processes can resolve different settings/support
directories. Switching editions is not an automatic settings/vault migration.
Keep the original profile and export/import supported configuration deliberately;
never infer that an absent vault authorizes silently replacing an existing one.
Existing credential setup, vault creation and App Lock checks remain in force.
A whole-app cross-edition migration has not been certified by the native profile
fixture tests.

Neither macFUSE nor FUSE-T is bundled. Their separate runtime/commercial terms
still apply; enabling GPL/LGPL code for GitHub does not waive those terms.
See [the FUSE audit](fuse_and_license_audit.md) and
[dependency boundaries](distribution-license-cleanup-20261115.md).
