# Local macOS builds and persistent Keychain access

Use `bash tool/build_macos_local.sh --debug --launch` for a local debug app, or `--release --launch` for a release preview. Signing preflight runs before compilation. The command signs and verifies the completed app before launching it, and refuses to overwrite an app that is running. Without `--launch` it leaves the signed app ready for inspection. Debug builds retain Flutter JIT, local VM service, and debugger permissions; release builds retain their normal entitlements. `flutter attach -d macos` can attach to an already running signed debug build.

The running debug app inspected on 2026-11-20 was ad hoc signed (`TeamIdentifier=not set`). Its designated requirement was a specific `cdhash`. Rebuilding changes that hash, so an earlier Always Allow entry cannot identify the new code. The selected `brickwright-build` keychain reported `no-timeout`; its repeated grants were not explained by an idle lock timer.

The local signer uses an Apple-issued certificate, the established `com.CrispStrobe.cloud` bundle ID, and an explicit designated requirement anchored to team `N9XSJ4M3GT`. It avoids pinning the app identity to a particular executable hash or development certificate common name. The same bundle/team identity is used for debug and local release builds.

Existing items granted to earlier ad hoc builds may need an authorization for the stable identity once. Ordinary rebuilds using the stable identity can retain that grant. A genuinely locked keychain still needs unlocking, and changing the app/team/access policy is a separate trust change. The application does not save the keychain password or grant access to other applications.

The build-only `tool/build_macos_release.sh` and raw Flutter/Xcode commands do not provide this local signing/launch guarantee. CI/distribution signing remains a separate workflow.

Apple explains the relationship between code identity and Keychain access in [TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements) and [Code Signing In Depth](https://developer.apple.com/library/archive/technotes/tn2206/).
